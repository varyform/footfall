require "date"

module Footfall
  # The counts in the terminal: totals, the last two weeks day by day, the busiest pages,
  # the sites visitors came from, every download, and feed readers. Feeds are counted
  # apart from pages, since readers poll them.
  #
  #   Footfall::Report.new("stats.sqlite3", title: "example.com",
  #     downloads: { "App" => "%.dmg", "Plugins" => "%.zip" }).print(days: 30)
  class Report
    # `downloads`: a column in the totals per kind of file, as SQL LIKE patterns of their
    # names; the first is also the day by day column.
    # `feeds`: a LIKE pattern of the feeds' paths.
    def initialize(path, title: nil, downloads: { "Downloads" => "%" }, feeds: "%/feed.xml",
      io: $stdout)
      @db = Database.open(path, readonly: true)
      @title = title
      @downloads = downloads
      @feeds = feeds
      @io = io
    end

    def print(days: 30, today: Date.today)
      since = (today - days + 1).iso8601
      @io.puts [ @title, "the last #{days} days (since #{since}); bots left out" ].compact.join(", ")
      totals(since)
      by_day(since)
      pages(since)
      referrers(since)
      downloads
      @io.puts "\nFeed readers (the latest day): #{feed_readers || 0}"
    end

    private

    def totals(since)
      visitors, views = @db.get_first_row(<<~SQL, [ since, @feeds ])
        SELECT COUNT(DISTINCT day || visitor), COALESCE(SUM(count), 0)
        FROM views WHERE day >= ? AND path NOT LIKE ?
      SQL
      files = @downloads.values.map do |pattern|
        @db.get_first_value(
          "SELECT COUNT(*) FROM downloads WHERE day >= ? AND file LIKE ?", [ since, pattern ])
      end
      table("Totals", [ [ visitors, views, *files ] ],
        [ "Visitors (a day each)", "Page views", *@downloads.keys ])
    end

    def by_day(since)
      rows = @db.execute(<<~SQL, [ @downloads.values.first, since, @feeds ])
        SELECT day, COUNT(DISTINCT visitor), SUM(count),
          (SELECT COUNT(*) FROM downloads d WHERE d.day = views.day AND d.file LIKE ?)
        FROM views WHERE day >= ? AND path NOT LIKE ?
        GROUP BY day ORDER BY day DESC LIMIT 14
      SQL
      table("By day", rows, [ "Day", "Visitors", "Views", @downloads.keys.first ])
    end

    def pages(since)
      rows = @db.execute(<<~SQL, [ since, @feeds ])
        SELECT path, COUNT(DISTINCT day || visitor), SUM(count)
        FROM views WHERE day >= ? AND path NOT LIKE ?
        GROUP BY path ORDER BY 2 DESC LIMIT 15
      SQL
      table("Pages", rows, [ "Page", "Visitors", "Views" ])
    end

    def referrers(since)
      rows = @db.execute(<<~SQL, [ since, @feeds ])
        SELECT referrer, COUNT(DISTINCT day || visitor)
        FROM views WHERE day >= ? AND referrer != '' AND path NOT LIKE ?
        GROUP BY referrer ORDER BY 2 DESC LIMIT 15
      SQL
      table("Where they came from", rows, [ "Site", "Visitors" ])
    end

    def downloads
      rows = @db.execute(<<~SQL)
        SELECT file, COUNT(*), MAX(day) FROM downloads GROUP BY file ORDER BY MAX(day) DESC, file
      SQL
      table("Downloads (all time)", rows, [ "File", "Downloads", "Last" ])
    end

    def feed_readers
      @db.get_first_value(<<~SQL, [ @feeds, @feeds ])
        SELECT COUNT(DISTINCT visitor) FROM views
        WHERE path LIKE ? AND day = (SELECT MAX(day) FROM views WHERE path LIKE ?)
      SQL
    end

    def table(title, rows, headers)
      @io.puts "\n#{title}"
      return @io.puts("  (none)") if rows.empty?

      all = [ headers ] + rows.map { |row| row.map(&:to_s) }
      widths = headers.each_index.map { |i| all.map { |row| row[i].length }.max }
      all.each_with_index do |row, index|
        cells = row.each_with_index.map { |cell, i| i.zero? ? cell.ljust(widths[i]) : cell.rjust(widths[i]) }
        @io.puts "  #{cells.join("  ")}"
        @io.puts "  #{widths.map { |width| "-" * width }.join("  ")}" if index.zero?
      end
    end
  end
end
