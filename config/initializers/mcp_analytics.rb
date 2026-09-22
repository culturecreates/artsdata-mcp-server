McpAnalytics.configure do |config|
  config.logger = Rails.logger

  if Rails.env.test?
    config.reporting_disabled = true
    config.request_log = false
  elsif Rails.env.development?
    config.reporting_disabled = true
  end
end
