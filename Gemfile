source "https://rubygems.org"

ruby "4.0.6"

gem "rails", "~> 8.1.0"

# Use the Puma web server [https://github.com/puma/puma]
gem "puma", ">= 5.0"

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[ windows jruby ]

# Reduces boot times through caching; required in config/boot.rb
gem "bootsnap", require: false

# Model Context Protocol server (tools, resources, Streamable HTTP transport)
gem "mcp"

# Parse the Artsdata ontology + SHACL shapes (Turtle) for the get_schema tool
gem "rdf", "~> 3.3"
gem "rdf-turtle", "~> 3.3"
# rdf requires ostruct, which is no longer a default gem since Ruby 4.0
gem "ostruct"

# Use Rack CORS for handling Cross-Origin Resource Sharing (CORS), making cross-origin Ajax possible
gem "rack-cors"

group :development, :test do
  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem "debug", platforms: %i[ mri windows ]
  gem "minitest", "~> 5.24"
end

group :test do
  # Validates tool payloads against the JSON schemas in app/schema (also a dependency of mcp)
  gem "json_schemer"
end
