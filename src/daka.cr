require "./daka/**"
require "kemal"
require "kemal-basic-auth"
require "db"
require "sqlite3"
require "tallboy"

class CustomAuthHandler < Kemal::BasicAuth::Handler
  only ["/admin"]

  def call(context)
    return call_next(context) unless only_match?(context)
    super
  end
end

Kemal.config.auth_handler = CustomAuthHandler

basic_auth "user", ENV.fetch("DAKAPWD", "1234567")

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

def exceeded_the_threshold?(db, hostname, action)
  now = Time.local
  value = nil

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

    return false if result.nil?

    last_headbeat_time, last_id, last_action = result

    if (now - last_headbeat_time > TIME_SPAN + 2.minutes)
      #
      # 如果当前时间和最后一次保存的心跳时间间隔超过了预设的一分钟, 这通常意味着,
      # 系统在长时间断网后, 刚刚重新连接网络, 即: 系统刚刚启动或唤醒
      # 因此, 那么前一次成功的心跳的时间, 可以粗略认为是系统离线时间.
      #
      if last_action == "heartbeat"
        db.exec("update daka set action = ? where id = ?", "offline by #{action}", last_id)
      end

      if last_action == "online"
        db.exec("update daka set action = ? where id = ?", "timeout by daka", last_id)
      end

      value = "online"
    end
  end

  value
end

post "/daka" do |env|
  if !env.request.headers["user_agent"].starts_with?("xh/")
    halt env, status_code: 403, response: "Forbidden"
  end

  hostname = env.params.json["hostname"]?.try(&.as(String))

  if hostname.nil?
    halt env, status_code: 403, response: "Need a host name!"
  end

  action = "heartbeat"

  DB.connect(DB_FILE) do |db|
    #
    # 上次心跳是离线, 那么这次心跳一定是在线
    #
    action = exceeded_the_threshold?(db, hostname, "daka")

    db.exec(
      "INSERT INTO daka (hostname, action) VALUES (?, ?);",
      hostname,
      action
    ) unless action.nil?
  end

  "success!"
end

get "/version" do
  Daka::VERSION
end

get "/admin" do |env|
  DB.connect DB_FILE do |db|
    hostnames = [] of String

    db.query_each "SELECT DISTINCT hostname FROM daka;" do |rs|
      hostnames << rs.read(String)
    end

    hostnames.each do |hostname|
      exceeded_the_threshold?(db, hostname, "admin")
    end

    date_range = [1.days.ago, Time.local].map(&.to_s("%Y-%m-%d"))

    sql = date_range.map { |date| "\"#{date}\"" }.join(",")

    records = [] of {String, String, Time, String}

    db.query_each "SELECT
hostname,action,date,created_at
FROM daka
WHERE date IN (#{sql})
AND
action IN ('online','offline','offline by daka','offline by admin','timeout by daka')
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
