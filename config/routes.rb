Rails.application.routes.draw do
  # health
  get "up" => "rails/health#show", as: :rails_health_check
  # mcp
  mount ->(env) { MyTransport.call(env) }, at: "/mcp"
end
