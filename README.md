# footfall

Cookieless visitor, page view and download counts for a Rack app, in a SQLite file. Footfall
is what a shop counts at its door: people coming in, not who they are.

- **Pages, visitors, referrers and downloads.** A page view is a GET of HTML (or an Atom or
  RSS feed) answered with 200; a download, a GET under `/download/` that sends the whole
  file, counted once even when it's resumed in pieces.
- **Nobody can be picked out.** A visitor is a hash of their address and browser, salted
  anew every day; the salt is forgotten the next day, so a day's visitors can be counted but
  not followed from day to day, or traced back. No cookies, no IP addresses, and only the
  site a visitor came from, not the full referrer.
- **Bots left out:** crawlers, link previews, monitors and command-line tools.
- **One file, no service.** SQLite in WAL mode, next to your app; a report for the terminal.
- **Never breaks a page.** A counting error is logged and the response goes out as it was.

## Install

```ruby
# Gemfile
gem "footfall", github: "varyform/footfall"
```

## Count

```ruby
# config.ru
require "footfall"

# Outermost, so it sees every response, downloads too. Without a path it counts nothing,
# which suits development and tests.
use Footfall::Middleware, path: ENV["FOOTFALL_PATH"]
```

Options:

| Option | Default | |
|---|---|---|
| `path:` | (required) | The SQLite file, made with its folder; `nil` turns counting off. |
| `downloads:` | `"/download/"` | The path prefix of files counted as downloads; `nil` for none. |
| `host:` | the request's host | This site, whose own links aren't referrers (`www.` is ignored). |
| `client_ip_header:` | none | The header a proxy puts the visitor's address in, such as Cloudflare's `"CF-Connecting-IP"`. Only behind such a proxy: anyone can send it. |
| `bots:` | `Footfall::Middleware::BOTS` | A regexp of user agents left out. |

In Rails, `config.middleware.insert_before 0, Footfall::Middleware, path: …`.

## Report

```ruby
require "footfall"

Footfall::Report.new("storage/footfall.sqlite3",
  title: "example.com",
  downloads: { "App downloads" => "%.dmg", "Plugin installs" => "Plugin-%" }
).print(days: 30)
```

```
example.com, the last 30 days (since 2026-09-10); bots left out

Totals
  Visitors (a day each)  Page views  App downloads  Plugin installs
  ---------------------  ----------  -------------  ---------------
                    412         903             57               12

By day
  Day         Visitors  Views  App downloads
  …
```

Then the busiest pages, the sites visitors came from, every download, and the feed's
readers on the latest day. `downloads:` names a column in the totals per kind of file, as
SQL `LIKE` patterns of the file names; the first is also the day by day column. Feeds
(`feeds:`, `"%/feed.xml"` by default) are counted apart from pages, since readers poll them.

A small script makes it a command, for example for `kamal app exec`:

```ruby
#!/usr/bin/env ruby
require "bundler/setup"
require "footfall"

Footfall::Report.new(ENV.fetch("FOOTFALL_PATH"), title: "example.com")
  .print(days: Integer(ARGV.first || 30))
```

## The data

Three tables, for queries of your own:

- `views`: `day`, `path`, `referrer` (a host, or `""`), `visitor`, `count`, one row per day,
  page, referrer and visitor;
- `downloads`: `day`, `file`, `visitor`, `count`;
- `salts`: today's salt only.

Days are in the server's time zone. Visitors are only comparable within a day: count
`DISTINCT day || visitor` for "visitors, a day each".

## License

MIT
