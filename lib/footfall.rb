require "footfall/version"
require "footfall/database"
require "footfall/middleware"
require "footfall/report"

# Cookieless visitor, page view and download counts for a Rack app, in a SQLite file:
# Footfall::Middleware counts them, Footfall::Report prints them.
module Footfall
end
