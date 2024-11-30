require "./daka/**"
require "kemal"
require "kemal-basic-auth"
require "db"
require "sqlite3"

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

post "/daka" do |env|
  hostname = env.params.json["hostname"]?.try(&.as(String)) || "unknown"
  action = env.params.json["action"].as(String)

  DB.connect DB_FILE do |db|
    db.exec("INSERT INTO daka (hostname, action) VALUES (?, ?);", hostname, action)
  end

  "success!"
end

get "/admin" do |env|
  DB.connect DB_FILE do |db|
    date_range = [1.days.ago, Time.local].map(&.to_s("%Y-%m-%d"))

    sql = String.build do |io|
      io << "("
      io << date_range.map { |date| "\"#{date}\"" }.join(",")
      io << ")"
    end

    records = [] of {String, String, Time, String}

    db.query_each "select hostname,action,created_at,date from daka where date in #{sql} order by id desc" do |rs|
      hostname = rs.read(String)
      action = rs.read(String)
      time = rs.read(Time).in(Time::Location.fixed(8*3600))
      date = rs.read(String)

      records << {hostname, action, time, date}
    end

    render "src/records.ecr"
  end
end

Kemal.run
