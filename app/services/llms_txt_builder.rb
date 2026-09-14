require "set"

class LlmsTxtBuilder
  DEFAULT_ENDPOINT = "https://mcp.artsdata.ca/mcp".freeze

  def initialize(server: ArtsdataMCPServer, endpoint: DEFAULT_ENDPOINT)
    @server = server
    @endpoint = endpoint
  end

  def render
    sections = []
    sections << "# Artsdata MCP Server"
    sections << ""
    sections << "> Machine-readable guide for LLM and agent tooling."
    sections << ""
    sections << "## Programmatic / agent access"
    sections << ""
    sections << "- MCP server endpoint: #{@endpoint}"
    sections << "- Transport: Streamable HTTP (JSON-RPC 2.0 over POST)"
    sections << "- Session model: stateless"

    instructions = @server.instructions.to_s.strip
    sections << "- Server instructions: #{instructions}" unless instructions.empty?

    sections << ""
    sections << "## MCP tools"
    sections << ""

    tool_entries.each do |name, klass|
      sections.concat(render_tool(name, klass))
    end

    sections << ""
    sections << "## MCP resources"
    sections << ""

    resource_entries.each do |resource_klass|
      sections.concat(render_resource(resource_klass))
    end

    sections << ""
    sections << "## Notes for agents"
    sections << ""
    sections << "- Prefer MCP tools over scraping website HTML when possible."
    sections << "- Call get_schema before writing SPARQL for this graph model."
    sections << "- For raw graph queries, use sparql_query with explicit PREFIX declarations and LIMIT."

    sections.join("\n") + "\n"
  end

  private

  def tool_entries
    @server.tools.to_a
  end

  def resource_entries
    @server.resources.to_a
  end

  def render_tool(name, klass)
    lines = []
    lines << "### #{name}"
    lines << ""

    description = klass.description.to_s.strip
    lines << description unless description.empty?

    input_schema = schema_hash(klass.input_schema_value)
    if input_schema.any?
      lines << ""
      lines << "Input parameters"
      lines.concat(render_schema_properties(input_schema))
    end

    output_schema = schema_hash(klass.output_schema_value)
    output_description = output_schema_description(output_schema)
    unless output_description.empty?
      lines << ""
      lines << "Output"
      lines << "- #{output_description}"
    end

    lines << ""
    lines
  end

  def render_resource(resource_klass)
    lines = []
    lines << "### #{resource_klass.resource_name}"
    lines << ""

    title = resource_klass.respond_to?(:title) ? resource_klass.title.to_s.strip : ""
    lines << "- Title: #{title}" unless title.empty?
    lines << "- URI: #{resource_klass.uri}"
    lines << "- MIME type: #{resource_klass.mime_type}"

    description = resource_klass.description.to_s.strip
    lines << "- Description: #{description}" unless description.empty?

    lines << ""
    lines
  end

  def schema_hash(schema)
    return {} if schema.nil?

    schema.to_h
  end

  def render_schema_properties(schema)
    properties = schema.fetch(:properties, {})
    required = Set.new(Array(schema[:required]).map(&:to_s))

    return ["- None"] if properties.empty?

    properties.map do |name, definition|
      prop_name = name.to_s
      qualifier = required.include?(prop_name) ? "required" : "optional"
      type = schema_type(definition)
      description = definition[:description].to_s.strip

      detail_parts = [type, qualifier]
      detail_parts << "default #{definition[:default]}" if definition.key?(:default)
      detail_parts << "enum #{definition[:enum].join("|")}" if definition[:enum].is_a?(Array)
      detail_parts << "min #{definition[:minimum]}" if definition.key?(:minimum)
      detail_parts << "max #{definition[:maximum]}" if definition.key?(:maximum)
      detail_parts << "minItems #{definition[:minItems]}" if definition.key?(:minItems)
      detail_parts << "maxItems #{definition[:maxItems]}" if definition.key?(:maxItems)

      suffix = description.empty? ? "" : ": #{description}"
      "- #{prop_name} (#{detail_parts.join(", ")})#{suffix}"
    end
  end

  def output_schema_description(schema)
    title = schema[:title].to_s.strip
    description = schema[:description].to_s.strip

    return [title, description].reject(&:empty?).join(" - ") if title.present? || description.present?

    "JSON object"
  end

  def schema_type(definition)
    explicit_type = definition[:type]
    return explicit_type if explicit_type.is_a?(String)
    return explicit_type.join("|") if explicit_type.is_a?(Array)

    return "enum" if definition[:enum].is_a?(Array)
    return "array<#{schema_type(definition[:items])}>" if definition[:items].is_a?(Hash)

    "object"
  end
end