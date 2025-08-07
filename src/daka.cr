require "kemal"
require "tallboy"
require "./daka/auth"
require "./daka/db"
require "./daka/version"

TIME_SPAN = ENV.fetch("DAKAINTERVAL", "1").to_i.minute

daka_db = Daka::DB.new

post "/daka" do |env|
  if !env.request.headers["user_agent"].starts_with?("xh/")
    halt env, status_code: 403, response: "Forbidden"
  end

  hostname = env.params.json["hostname"]?.try(&.as(String))

  if hostname.nil?
    halt env, status_code: 403, response: "Need a host name!"
  end

  daka_db.conn do |conn|
    #
    # 上次心跳是离线, 那么这次心跳一定是在线
    #
    conn.exec(
      "INSERT INTO daka (hostname, action, date) VALUES (?, ?, ?);",
      hostname,
      update_last_record_action(conn, hostname),
      Time.local.in(Time::Location.load("Asia/Shanghai")).to_s("%Y-%m-%d")
    )
  end

  "success!"
end

get "/version" do
  Daka::VERSION
end

get "/admin" do |env|
  # days 表示显示之前几天的记录, 默认仅显示之前一天的记录.
  days = (env.params.query["days"]? || 1).to_i
  conn = daka_db.conn

  hostnames = [] of String
  conn.query_each "SELECT DISTINCT hostname FROM daka;" do |rs|
    hostnames << rs.read(String)
  end

  hostnames.each do |hostname|
    update_last_record_action(conn, hostname)
  end

  date_ranges = [] of String
  (days..1).step(-1).each do |day|
    date_ranges << day.days.ago.to_s("%Y-%m-%d")
  end
  date_ranges << Time.local.to_s("%Y-%m-%d")

  sql = date_ranges.map { |date| "\"#{date}\"" }.join(",")

  records = [] of {hostname: String, action: String, created_at: Time, date: String}

  conn.query_each "SELECT
hostname,action,date,created_at
FROM daka
WHERE
date IN (#{sql})
AND
action IN ('online','offline','timeout')
ORDER BY id" do |rs|
    hostname, action, date = rs.read(String, String, String)
    created_at = rs.read(Time).in(Time::Location.load("Asia/Shanghai"))

    records << {hostname: hostname, action: action, created_at: created_at, date: date}
  end

  dates = records
    .group_by { |e| e[:date] }
    .transform_values { |v| v.sort_by { |e| e[:hostname] } }

  if env.request.headers["user_agent"].starts_with?("xh/")
    table = Tallboy.table do
      columns do
        add "hostname"
        add "action"
        add "time"
      end

      header

      dates.each do |date|
        header date[0], align: :left

        rows date[1].map { |e| [e[:hostname], e[:action], e[:created_at].to_s("%H:%M:%S")] }
      end
    end

    table.render.to_s
  else
    render "src/records.ecr"
  end
ensure
  conn.close if conn
end

Kemal.run

#
# 查找当前 hostname 的最后一条记录
# 并根据 `'现在时间` '和 `'最后一条记录时间` 的间隔，选择是否更新 action
# 返回 action 字符串。
#

private def update_last_record_action(conn, hostname) : String
  now = Time.local
  action = "heartbeat"

  conn.transaction do |tr|
    result = conn.query_one?(
      "SELECT created_at,id,action
FROM daka
WHERE hostname = ?
ORDER BY id DESC
LIMIT 1;
", hostname) do |rs|
      rs.read(Time, Int64, String)
    end

    return action if result.nil?

    last_headbeat_time, last_id, last_action = result

    #
    # 如果当前时间和最后一次保存的心跳时间间隔超过了预设的 TIME_SPAN (默认 1分钟),
    # 这通常意味着, 系统在长时间断网后, 刚刚重新连接网络, 即: 系统刚刚启动或唤醒
    #
    if (now - last_headbeat_time > TIME_SPAN + 2.minutes) # 额外加 2 分钟作为时间冗余
      #
      # 此时， 如果最后一次成功的打卡是正常的 heartbeat, 而不是其他 action，
      # 那就意味着这次打卡后，下次打卡之前，这个时间段客户系统离线。
      # 此时，可以粗略的认为，这最后一次成功的打卡，就是系统离线时间.
      #
      if last_action == "heartbeat"
        # 重新连接的时候，因为超时，更新最后一个 heartbeat 打卡为 offline
        conn.exec("update daka set action = ? where id = ?", "offline", last_id)
      end

      #
      # 刚刚更新为 online, 下一次打卡之前，立刻（下线）超时，
      # 即：长时间离线后，开机第一次 online 打卡，然后没有心跳了。
      # 近似等价于，客户系统刚开机就关机。
      #
      if last_action == "online"
        conn.exec("update daka set action = ? where id = ?", "timeout", last_id)
      end

      action = "online"
    end
  end

  action
end
