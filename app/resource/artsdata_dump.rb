require "mcp"
require "json"

# MCP resource pointing at the latest full Artsdata dump.
#
# The dump file is far too large to inline into an MCP response,
# so `resources/read` returns a small JSON manifest instead: the
# download URL of the newest dump plus the metadata a client needs to decide whether to
# (re)fetch it - last-modified.
# Clients compare `last-modified` across reads to detect when a new dump lands.
class ArtsdataDump < MCP::Resource
  RESOURCE_URI = "artsdata://dumps/core".freeze
  MANIFEST_MIME_TYPE = "application/json".freeze

  uri RESOURCE_URI
  resource_name "artsdata_dump"
  title "Artsdata dump"
  description "Manifest for the latest complete Artsdata dump (gzipped Turtle)."\
              "Reading this resource returns JSON metadata (download URL, size, " \
              "last-modified) - not the dump itself. Download the file " \
              "from `dump.url` to get the data."
  mime_type MANIFEST_MIME_TYPE

  class << self
    def contents(server_context: nil)
      MCP::Resource::TextContents.new(
        uri: RESOURCE_URI,
        mime_type: MANIFEST_MIME_TYPE,
        text: JSON.generate(manifest)
      )
    end

    def manifest
      metadata = DataDumpClient.new.metadata

      {
        "resource" => RESOURCE_URI,
        "name" => name_value,
        "title" => title,
        "description" => "Complete dump of the Artsdata knowledge graph, as a gzipped Turtle file",
        "update_schedule" => "monthly",
        "dump" => metadata
      }
    end
  end
end
