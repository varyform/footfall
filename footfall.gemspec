require_relative "lib/footfall/version"

Gem::Specification.new do |spec|
  spec.name        = "footfall"
  spec.version     = Footfall::VERSION
  spec.authors     = [ "Oleh Khomei" ]
  spec.summary     = "Cookieless visitor, page view and download counts for a Rack app, in a SQLite file."
  spec.description = <<~TEXT
    Footfall is what a shop counts at its door: people coming in, not who they
    are. Rack middleware that counts page views, visitors, the sites they came
    from and file downloads into a SQLite file, and a report for the terminal.
    No cookies, no IP addresses, no full referrers: a visitor is a hash salted
    anew every day and the salt forgotten the next, so a day's visitors can be
    counted but not followed from day to day or traced back. Bots are left out.
  TEXT
  spec.homepage    = "https://github.com/varyform/footfall"
  spec.license     = "MIT"
  spec.required_ruby_version = ">= 3.2"
  spec.metadata = {
    "source_code_uri" => "https://github.com/varyform/footfall",
    "changelog_uri" => "https://github.com/varyform/footfall/blob/main/CHANGELOG.md",
    "rubygems_mfa_required" => "true"
  }

  spec.files = Dir["lib/**/*", "README.md", "CHANGELOG.md", "LICENSE"]
  spec.require_paths = [ "lib" ]

  spec.add_dependency "rack", ">= 2.2"
  spec.add_dependency "sqlite3", ">= 2.0"

  spec.add_development_dependency "minitest"
  spec.add_development_dependency "rack-test"
  spec.add_development_dependency "rake"
end
