require "test_helper"

class DatabaseTest < Minitest::Test
  def setup = @dir = Dir.mktmpdir
  def teardown = FileUtils.rm_rf(@dir)

  # A database from the counter Footfall came from, which kept each view's language.
  def test_an_older_database_loses_the_language_column_and_keeps_its_counts
    path = File.join(@dir, "stats.sqlite3")
    old = SQLite3::Database.new(path)
    old.execute_batch(<<~SQL)
      CREATE TABLE views (
        day TEXT NOT NULL, path TEXT NOT NULL, locale TEXT NOT NULL, referrer TEXT NOT NULL,
        visitor TEXT NOT NULL, count INTEGER NOT NULL DEFAULT 1,
        PRIMARY KEY (day, path, referrer, visitor));
      INSERT INTO views VALUES ('2026-10-05', '/en', 'en', '', 'abc', 3);
    SQL
    old.close
    db = Footfall::Database.open(path)
    assert_equal %w[day path referrer visitor count],
      db.execute("PRAGMA table_info(views)").map { |column| column[1] }
    assert_equal [ [ "/en", 3 ] ], db.execute("SELECT path, count FROM views")
    db.execute("INSERT INTO views (day, path, referrer, visitor) VALUES ('2026-10-06', '/', '', 'x')")
  end
end
