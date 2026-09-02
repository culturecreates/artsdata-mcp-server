ENV["RAILS_ENV"] ||= "test"
ENV["ARTSDATA_RECONCILIATION_ENDPOINT"] ||= "https://staging-recon.artsdata.ca/"
require_relative "../config/environment"
require "rails/test_help"

class ActiveSupport::TestCase
end
