require "test_helper"

# What gets counted, what doesn't, and that nobody can be picked out.
class MiddlewareTest < Minitest::Test
  include Rack::Test::Methods

  BROWSER = "Mozilla/5.0 (Macintosh; Intel Mac OS X 15_0) AppleWebKit/605.1.15 Safari/605.1.15"

  # Pages, a feed, a download (whole or a range), a redirect, a missing page and an asset.
  SITE = lambda do |env|
    case env["PATH_INFO"]
    when "/download/latest" then [ 302, { "location" => "/download/x.dmg" }, [] ]
    when %r{\A/download/} then [ env["HTTP_RANGE"] ? 206 : 200, { "content-type" => "application/x-apple-diskimage" }, [ "x" ] ]
    when "/blog/feed.xml" then [ 200, { "content-type" => "application/atom+xml" }, [ "<feed/>" ] ]
    when "/nope" then [ 404, { "content-type" => "text/plain" }, [ "no" ] ]
    when %r{\A/assets/} then [ 200, { "content-type" => "text/css" }, [ "a{}" ] ]
    else [ 200, { "content-type" => "text/html; charset=utf-8" }, [ "<html>" ] ]
    end
  end

  def setup
    @dir = Dir.mktmpdir
    @path = File.join(@dir, "stats", "stats.sqlite3")
    @day = Date.new(2026, 10, 5)
    @options = {}
  end

  def teardown = FileUtils.rm_rf(@dir)

  def app
    @app ||= Footfall::Middleware.new(SITE, path: @path, today: -> { @day }, **@options)
  end

  def db = SQLite3::Database.new(@path)

  def visit(path, ip: "203.0.113.7", agent: BROWSER, **headers)
    get path, {}, { "REMOTE_ADDR" => ip, "HTTP_USER_AGENT" => agent, "HTTP_HOST" => "example.com" }.merge(headers)
  end

  def test_pages_are_counted_with_where_they_came_from
    visit "/", "HTTP_REFERER" => "https://news.ycombinator.com/item?id=1"
    visit "/"
    visit "/blog", "HTTP_REFERER" => "https://www.example.com/"
    visit "/blog/feed.xml"
    rows = db.execute("SELECT path, referrer, count FROM views ORDER BY path, referrer")
    assert_equal [ [ "/", "", 1 ], [ "/", "news.ycombinator.com", 1 ], [ "/blog", "", 1 ],
      [ "/blog/feed.xml", "", 1 ] ], rows
    assert_equal 1, db.get_first_value("SELECT COUNT(DISTINCT visitor) FROM views")
  end

  def test_the_site_can_be_named
    @options = { host: "www.example.org" }
    visit "/", "HTTP_REFERER" => "https://example.org/blog"
    visit "/", "HTTP_REFERER" => "https://example.com/"
    assert_equal [ "", "example.com" ], db.execute("SELECT referrer FROM views ORDER BY referrer").flatten
  end

  # Puma hands over paths and headers as binary strings, which SQLite would keep as blobs
  # that no query for text ever matches.
  def test_values_are_kept_as_text
    env = Rack::MockRequest.env_for("/")
    env["PATH_INFO"] = "/".b
    env["HTTP_USER_AGENT"] = BROWSER.b
    env["HTTP_REFERER"] = "https://news.ycombinator.com/".b
    app.call(env)
    assert_equal [ %w[text text text] ],
      db.execute("SELECT typeof(path), typeof(referrer), typeof(visitor) FROM views")
    assert_equal 1, db.get_first_value("SELECT COUNT(*) FROM views WHERE path = '/'")
  end

  def test_bots_assets_and_errors_are_left_out
    visit "/", agent: "Googlebot/2.1"
    visit "/", agent: "curl/8.7"
    visit "/", agent: ""
    visit "/assets/site.css"
    visit "/nope"
    post "/", {}, { "HTTP_USER_AGENT" => BROWSER }
    assert_equal 0, db.get_first_value("SELECT COUNT(*) FROM views")
  end

  def test_a_download_counts_once
    visit "/download/latest"
    visit "/download/App-1.0.dmg"
    visit "/download/App-1.0.dmg", "HTTP_RANGE" => "bytes=1000-"
    visit "/download/App-1.0.dmg", ip: "198.51.100.2", "HTTP_RANGE" => "bytes=0-"
    visit "/download/Plugin-1.zip", agent: "App/1.0 CFNetwork"
    rows = db.execute("SELECT file, COUNT(*) FROM downloads GROUP BY file ORDER BY file")
    assert_equal [ [ "App-1.0.dmg", 2 ], [ "Plugin-1.zip", 1 ] ], rows
  end

  def test_downloads_can_live_elsewhere_or_not_be_counted
    @options = { downloads: "/files/" }
    visit "/files/App-1.0.dmg"
    visit "/download/App-1.0.dmg"
    assert_equal [ "App-1.0.dmg" ], db.execute("SELECT file FROM downloads").flatten
    @app = nil
    @options = { downloads: nil }
    visit "/files/App-1.0.dmg"
    assert_equal 1, db.get_first_value("SELECT COUNT(*) FROM downloads")
  end

  def test_visitors_cant_be_followed_from_one_day_to_the_next
    visit "/"
    first = db.get_first_value("SELECT visitor FROM views")
    @day += 1
    visit "/"
    refute_equal first, db.execute("SELECT visitor FROM views ORDER BY day").flatten.last,
      "a new salt every day"
    assert_equal 1, db.get_first_value("SELECT COUNT(*) FROM salts"), "yesterday's is gone"
    dump = db.execute("SELECT * FROM views").flatten.join(" ")
    refute_includes dump, "203.0.113.7", "no address"
    refute_includes dump, "Safari", "no browser"
  end

  # Behind Cloudflare every request comes from another of its servers.
  def test_a_proxy_can_say_who_the_visitor_is
    @options = { client_ip_header: "CF-Connecting-IP" }
    visit "/", ip: "172.71.144.3", "HTTP_CF_CONNECTING_IP" => "203.0.113.7"
    visit "/blog", ip: "162.158.111.203", "HTTP_CF_CONNECTING_IP" => "203.0.113.7"
    assert_equal 1, db.get_first_value("SELECT COUNT(DISTINCT visitor) FROM views")
  end

  def test_the_header_is_ignored_unless_asked_for
    visit "/", ip: "172.71.144.3", "HTTP_CF_CONNECTING_IP" => "203.0.113.7"
    visit "/blog", ip: "162.158.111.203", "HTTP_CF_CONNECTING_IP" => "203.0.113.7"
    assert_equal 2, db.get_first_value("SELECT COUNT(DISTINCT visitor) FROM views")
  end

  def test_counting_off_without_a_path
    counted = Footfall::Middleware.new(SITE, path: nil)
    assert_equal 200, counted.call(Rack::MockRequest.env_for("/"))[0]
    refute File.exist?(@path)
  end

  def test_counting_never_breaks_a_page
    app
    db.execute("DROP TABLE views")
    _, err = capture_io { visit "/" }
    assert_equal 200, last_response.status
    assert_match(/footfall: /, err)
  end
end
