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

basic_auth "user", "***REMOVED***"

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
            action TEXT,
            date DATETIME DEFAULT CURRENT_DATE,
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP
  );"
  end
end

post "/daka" do |env|
  action = env.params.json["action"].as(String)

  DB.connect DB_FILE do |db|
    db.exec("INSERT INTO daka (action) VALUES (?);", action)
  end

  "success!"
end

get "/admin" do |env|
end

Kemal.run
