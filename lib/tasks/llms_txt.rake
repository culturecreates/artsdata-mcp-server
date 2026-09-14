namespace :docs do
  desc "Generate public/llms.txt from MCP server metadata"
  task generate_llms: :environment do
    output_path = Rails.root.join("public", "llms.txt")
    File.write(output_path, LlmsTxtBuilder.new.render)

    puts "Wrote #{output_path}"
  end

  desc "Fail if public/llms.txt is out of sync with MCP metadata"
  task check_llms: :environment do
    output_path = Rails.root.join("public", "llms.txt")
    generated = LlmsTxtBuilder.new.render
    existing = File.exist?(output_path) ? File.read(output_path) : ""

    if existing != generated
      warn "#{output_path} is out of date. Run: bundle exec rake docs:generate_llms"
      exit 1
    end

    puts "#{output_path} is up to date"
  end
end