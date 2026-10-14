# Changelog

## 0.1.0 — 2026-10-09

- First version, extracted from mini-audition.com's own counter: the middleware, the
  SQLite schema and the terminal report. Options for where downloads live, the site's
  host, a proxy's client address header and the bot pattern; the report's download columns
  and feed pattern are configurable. Databases from that counter are upgraded on open (its
  per-language column is dropped).
