require "fileutils"
require "sqlite3"

module Footfall
  # The SQLite file: a row per day, page, referring site and visitor for page views, and per
  # day, file and visitor for downloads, each with how many times; and the day's salt.
  module Database
    SCHEMA = <<~SQL
      CREATE TABLE IF NOT EXISTS salts (day TEXT PRIMARY KEY, salt TEXT NOT NULL);
      CREATE TABLE IF NOT EXISTS views (
        day TEXT NOT NULL, path TEXT NOT NULL, referrer TEXT NOT NULL,
        visitor TEXT NOT NULL, count INTEGER NOT NULL DEFAULT 1,
        PRIMARY KEY (day, path, referrer, visitor));
      CREATE TABLE IF NOT EXISTS downloads (
        day TEXT NOT NULL, file TEXT NOT NULL, visitor TEXT NOT NULL,
        count INTEGER NOT NULL DEFAULT 1,
        PRIMARY KEY (day, file, visitor));
    SQL

    # For counting: made (with its folder) if it isn't there yet. Readonly for reports.
    def self.open(path, readonly: false)
      return SQLite3::Database.new(path, readonly: true) if readonly

      FileUtils.mkdir_p(File.dirname(path))
      db = SQLite3::Database.new(path)
      db.busy_timeout = 2_000
      db.execute("PRAGMA journal_mode = WAL")
      db.execute_batch(SCHEMA)
      db
    end
  end
end
