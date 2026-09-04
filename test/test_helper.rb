ENV["RAILS_ENV"] ||= "test"
ENV["ARTSDATA_RECONCILIATION_ENDPOINT"] ||= "https://staging-recon.artsdata.ca/"
ENV["ARTSDATA_DUMPS_BUCKET_URL"] ||= "https://dumps.example.test"
ENV["ARTSDATA_DUMP_FOLDER"] ||= "core-graph-minus-provenance/monthly/"
require_relative "../config/environment"
require "rails/test_help"

class ActiveSupport::TestCase
end
