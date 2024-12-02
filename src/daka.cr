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

basic_auth "user", "1234567"

def find_db_path(name)
  (Path["#{Process.executable_path.as(String)}/../.."] / "daka.db").expand
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

TIME_SPAN = 1.minute

# Log.setup(:debug)

def update(db)
  now = Time.local

  last_headbeat_time, last_id, last_action = db.query_one "select created_at,id,action from daka order by id desc limit 1;" do |rs|
    rs.read(Time, Int64, String)
  end

  if (now - last_headbeat_time > TIME_SPAN + 1.minute) && last_action != "shutdown"
    #
    # 如果当前时间和最后一次保存的心跳时间间隔超过了预设的一分钟, 这通常意味着,
    # 系统在长时间断网后, 刚刚重新连接网络, 即: 系统刚刚启动或唤醒
    # 因此, 那么前一次成功的心跳的时间, 可以粗略认为是系统关机时间.
    #
    db.exec("update daka set action = ? where id = ?", "shutdown", last_id)

    true
  else
    false
  end
end

post "/daka" do |env|
  if !env.request.headers["user_agent"].starts_with?("xh/")
    halt env, status_code: 403, response: "Forbidden"
  end

  hostname = env.params.json["hostname"]?.try(&.as(String)) || "unknown"
  action = "heartbeat"

  db = DB.connect(DB_FILE) do |db|
    #
    # 上次心跳是关机, 那么这次心跳就是开机
    #
    action = "boot" if update(db)

    db.exec("INSERT INTO daka (hostname, action) VALUES (?, ?);", hostname, action)
  end

  "success!"
end

get "/admin" do |env|
  DB.connect DB_FILE do |db|
    update(db)

    date_range = [1.days.ago, Time.local].map(&.to_s("%Y-%m-%d"))

    sql = date_range.map { |date| "\"#{date}\"" }.join(",")

    records = [] of {String, String, Time, String}

    db.query_each "SELECT
hostname,action,date,created_at
FROM daka
WHERE date IN (#{sql})
AND
action IN ('boot','shutdown')
ORDER BY id DESC" do |rs|
      hostname, action, date = rs.read(String, String, String)
      time = rs.read(Time).in(Time::Location.fixed(8*3600))

      records << {hostname, action, time, date}
    end

    dates = records.group_by { |e| e[3] }

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

          data = date[1]
            .sort_by { |e| e[2] }
            .map { |e| [e[0], e[1], e[2].to_s("%H:%M:%S")] }

          rows data
        end
      end

      table.render.to_s
    else
      render "src/records.ecr"
    end
  end
end

Kemal.run
