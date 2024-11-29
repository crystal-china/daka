require "./daka/**"
require "kemal"
require "db"
require "sqlite3"

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

Kemal.run
