require "./daka/**"
require "kemal"
require "db"
require "sqlite3"
require "tallboy"

def find_db_path(db_name)
  (Path["#{Process.executable_path.as(String)}/../.."] / db_name).expand
end

DB_FILE = "sqlite3:#{find_db_path("daka.db")}"

def db_exists?
  db_file = DB_FILE.split(':')[1]

  File.exists?(db_file) && File.info(db_file).size > 0
end

unless db_exists?
  DB.connect DB_FILE do |db|
    db.exec "create table if not exists daka (
            id INTEGER PRIMARY KEY,
            hostname TEXT,
            action TEXT,
            date DATETIME DEFAULT CURRENT_DATE,
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP
  );"
  end
end

TIME_SPAN = ENV.fetch("DAKAINTERVAL", "1").to_i.minute

# Log.setup(:debug)

def next_record_action(db, hostname) : String
  now = Time.local
  action = "heartbeat"

  db.transaction do |tr|
    result = db.query_one?(
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

    if (now - last_headbeat_time > TIME_SPAN + 2.minutes)
      #
      # 如果当前时间和最后一次保存的心跳时间间隔超过了预设的一分钟, 这通常意味着,
      # 系统在长时间断网后, 刚刚重新连接网络, 即: 系统刚刚启动或唤醒
      # 因此, 那么前一次成功的心跳的时间, 可以粗略认为是系统离线时间.
      #
      if last_action == "heartbeat"
        db.exec("update daka set action = ? where id = ?", "offline", last_id)
      end

      if last_action == "online"
        db.exec("update daka set action = ? where id = ?", "timeout", last_id)
      end

      action = "online"
    end
  end

  action
end

post "/daka" do |env|
  if !env.request.headers["user_agent"].starts_with?("xh/")
    halt env, status_code: 403, response: "Forbidden"
  end

  hostname = env.params.json["hostname"]?.try(&.as(String))

  if hostname.nil?
    halt env, status_code: 403, response: "Need a host name!"
  end

  DB.connect(DB_FILE) do |db|
    #
    # 上次心跳是离线, 那么这次心跳一定是在线
    #
    db.exec(
      "INSERT INTO daka (hostname, action) VALUES (?, ?);",
      hostname,
      next_record_action(db, hostname)
    )
  end

  "success!"
end

get "/version" do
  p! "1"*100
  Daka::VERSION
end

get "/admin" do |env|
  # days 表示显示之前几天的记录, 默认仅显示之前一天的记录.
  days = (env.params.query["days"]? || 1).to_i
  date_ranges = [] of String

  DB.connect DB_FILE do |db|
    hostnames = [] of String

    db.query_each "SELECT DISTINCT hostname FROM daka;" do |rs|
      hostnames << rs.read(String)
    end

    hostnames.each do |hostname|
      next_record_action(db, hostname)
    end

    (days..1).step(-1).each do |day|
      date_ranges << day.days.ago.to_s("%Y-%m-%d")
    end
    date_ranges << Time.local.to_s("%Y-%m-%d")

    sql = date_ranges.map { |date| "\"#{date}\"" }.join(",")

    records = [] of {String, String, Time, String}

    db.query_each "SELECT
hostname,action,date,created_at
FROM daka
WHERE date IN (#{sql})
AND
action IN ('online','offline','timeout')
ORDER BY id" do |rs|
      hostname, action, date = rs.read(String, String, String)
      time = rs.read(Time).in(Time::Location.fixed(8*3600))

      records << {hostname, action, time, date}
    end

    dates = records
      .group_by { |e| e[3] }
      .transform_values { |v| v.group_by { |e| e[0] }.values.flatten }
      .to_a.reverse

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

          rows date[1].map { |e| [e[0], e[1], e[2].to_s("%H:%M:%S")] }
        end
      end

      table.render.to_s
    else
      render "src/records.ecr"
    end
  end
end

Kemal.run
