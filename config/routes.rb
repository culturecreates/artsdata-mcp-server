# config/routes.rb
Rails.application.routes.draw do
  # health
  get "up" => "rails/health#show", as: :rails_health_check
  # mcp
  mount ->(env) { MyTransport.call(env) }, at: "/mcp"

  get "search-entities", to: "entities#search"
  # Swagger routes
  mount Rswag::Ui::Engine => "/api-docs"
  mount Rswag::Api::Engine => "/api-docs"


end