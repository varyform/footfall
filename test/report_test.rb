require "test_helper"

class ReportTest < Minitest::Test
  include Rack::Test::Methods

  BROWSER = MiddlewareTest::BROWSER

  def setup
    @dir = Dir.mktmpdir
    @path = File.join(@dir, "stats.sqlite3")
  end

  def teardown = FileUtils.rm_rf(@dir)

  def app = @app ||= Footfall::Middleware.new(MiddlewareTest::SITE, path: @path,
    today: -> { Date.new(2026, 10, 5) })

  def visit(path, agent: BROWSER, **headers)
    get path, {}, { "HTTP_USER_AGENT" => agent, "HTTP_HOST" => "example.com" }.merge(headers)
  end

  def report(**options)
    io = StringIO.new
    Footfall::Report.new(@path, io: io, **options).print(days: 30, today: Date.new(2026, 10, 9))
    io.string
  end

  def test_it_shows_visitors_pages_referrers_and_downloads
    visit "/", "HTTP_REFERER" => "https://news.ycombinator.com/"
    visit "/blog"
    visit "/blog/feed.xml", agent: "NetNewsWire (RSS Reader)"
    visit "/download/App-1.0.dmg"
    visit "/download/Plugin-1.zip"
    output = report(title: "example.com",
      downloads: { "App downloads" => "%.dmg", "Plugin installs" => "Plugin-%" })
    assert_includes output, "example.com, the last 30 days (since 2026-09-10); bots left out"
    assert_match(/Visitors \(a day each\)\s+Page views\s+App downloads\s+Plugin installs/, output)
    assert_match(/^\s+1\s+2\s+1\s+1$/, output, "two pages: the feed's apart")
    assert_includes output, "news.ycombinator.com"
    assert_match(/App-1\.0\.dmg\s+1\s+2026-10-05/, output)
    assert_includes output, "Feed readers (the latest day): 1"
  end

  def test_an_empty_database
    Footfall::Database.open(@path).close
    output = report
    assert_includes output, "Where they came from\n  (none)"
    assert_includes output, "Feed readers (the latest day): 0"
  end
end
