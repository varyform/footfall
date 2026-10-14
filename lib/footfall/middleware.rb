require "date"
require "digest"
require "rack"
require "securerandom"
require "uri"

module Footfall
  # Counts page views and downloads, after the app has answered. A page view is a GET of
  # a page (HTML, or an Atom or RSS feed) answered with 200; a download, a GET under
  # `downloads` that sends the whole file (200, or 206 from its first byte), so redirects
  # and the later pieces of a resumed download aren't counted again.
  #
  # Nothing that identifies anyone is kept: a visitor is a hash of their IP address and
  # browser with a salt that's new every day and forgotten the next. No cookies, no
  # addresses, no full referrers (only the site a visitor came from). Bots are left out.
  class Middleware
    # Crawlers, link previews, monitors and command-line tools.
    BOTS = /bot|crawl|spider|slurp|preview|monitor|curl|wget|python|ruby|go-http|java|
      httpclient|headless|lighthouse|facebookexternalhit|embedly|whatsapp|telegram/xi

    PAGES = %r{\A(text/html|application/(atom|rss)\+xml)\b}

    # `path`: the SQLite file; nil turns counting off.
    # `downloads`: the path prefix of files to count as downloads; nil for none.
    # `host`: this site, whose own links aren't counted as referrers (the request's host
    #   unless given).
    # `client_ip_header`: the header a proxy in front puts the visitor's address in, such
    #   as Cloudflare's "CF-Connecting-IP"; without one, the request's own address. Only
    #   set it behind such a proxy: anyone can send the header (it only skews the counts).
    def initialize(app, path:, downloads: "/download/", host: nil, client_ip_header: nil,
      bots: BOTS, today: -> { Date.today })
      @app = app
      @downloads = downloads
      @host = host && site(host)
      @client_ip = client_ip_header && "HTTP_#{client_ip_header.upcase.tr("-", "_")}"
      @bots = bots
      @today = today
      @lock = Mutex.new
      @db = path && Database.open(path)
    end

    def call(env)
      status, headers, body = @app.call(env)
      record(Rack::Request.new(env), status, headers) if @db
      [ status, headers, body ]
    end

    private

    # Never lets counting break a page.
    def record(request, status, headers)
      return unless request.get?
      agent = request.user_agent.to_s
      return if agent.empty? || @bots.match?(agent)

      path = request.path_info
      if @downloads && path.start_with?(@downloads)
        download(request, path, status)
      elsif status == 200 && PAGES.match?(headers["content-type"].to_s)
        upsert("views", day: today, path: path, referrer: referrer(request),
          visitor: visitor(request))
      end
    rescue StandardError => error
      warn "footfall: #{error.class}: #{error.message}"
    end

    def download(request, path, status)
      range = request.get_header("HTTP_RANGE").to_s
      return unless status == 200 || (status == 206 && range.match?(/\Abytes=0-/))

      upsert("downloads", day: today, file: File.basename(path), visitor: visitor(request))
    end

    # The site a visitor came from ("news.ycombinator.com"), or "" for none or this one.
    def referrer(request)
      from = site(URI.parse(request.referer.to_s).host.to_s)
      from == (@host || site(request.host.to_s)) ? "" : from
    rescue URI::InvalidURIError
      ""
    end

    def site(host) = host.downcase.delete_prefix("www.")

    def visitor(request)
      address = (@client_ip && request.get_header(@client_ip)) || request.ip
      Digest::SHA256.hexdigest("#{salt}|#{address}|#{request.user_agent}")[0, 16]
    end

    def today = @today.call.iso8601

    # Today's salt, made the first time it's needed; the days before are forgotten then.
    def salt
      day = today
      return @salt if @salt_day == day

      @lock.synchronize do
        @db.execute("DELETE FROM salts WHERE day < ?", [ day ])
        @db.execute("INSERT OR IGNORE INTO salts (day, salt) VALUES (?, ?)",
          [ day, SecureRandom.hex(16) ])
        @salt = @db.get_first_value("SELECT salt FROM salts WHERE day = ?", [ day ])
        @salt_day = day
      end
      @salt
    end

    def upsert(table, values)
      # As text: Rack's paths and headers can be binary strings, which SQLite would keep
      # as blobs, never equal to text in a query.
      values = values.transform_values { |value| value.to_s.dup.force_encoding(Encoding::UTF_8).scrub }
      marks = ([ "?" ] * values.size).join(", ")
      @lock.synchronize do
        @db.execute(
          "INSERT INTO #{table} (#{values.keys.join(", ")}) VALUES (#{marks}) " \
          "ON CONFLICT DO UPDATE SET count = count + 1", values.values)
      end
    end
  end
end
