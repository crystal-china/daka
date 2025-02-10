require "db"
require "sqlite3"

module Daka
  class DB
    def initialize
      if !db_exists?
        ::DB.connect db_url do |conn|
          conn.exec "create table if not exists daka (
                id INTEGER PRIMARY KEY,
                hostname TEXT,
                action TEXT,
                date DATETIME DEFAULT CURRENT_DATE,
                created_at DATETIME DEFAULT CURRENT_TIMESTAMP
      );"
        end
      end
    end

    def conn
      ::DB.connect db_url
    end

    def conn(&block : SQLite3::Connection -> _)
      ::DB.connect db_url, &block
    end

    private def find_db_path(db_name)
      (Path["#{Process.executable_path.as(String)}/../.."] / db_name).expand
    end

    private def db_url
      "sqlite3:#{find_db_path("daka.db")}"
    end

    private def db_exists?
      db_file = db_url.split(':')[1]

      File.exists?(db_file) && File.info(db_file).size > 0
    end
  end
end
