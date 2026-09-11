require "mcp"
require "json"

class ArtsdataCoreMinusProvenanceDump < MCP::Resource
  RESOURCE_URI = "artsdata://dumps/core-minus-provenance/latest".freeze
  MANIFEST_MIME_TYPE = "application/ld+json".freeze

  ARTIFACT = "core-minus-provenance".freeze
  ARTIFACT_URI = "http://kg.artsdata.ca/databus/culture-creates/artsdata-dump/#{ARTIFACT}".freeze

  DUMP_NAME = "Artsdata core minus provenance".freeze

  uri RESOURCE_URI
  resource_name "artsdata_dump"
  title DUMP_NAME
  description "Manifest for the latest Artsdata core-minus-provenance dump (gzipped Turtle). " \
                "Reading this resource returns JSON metadata (download URL, version, format) - " \
                "not the dump itself. Download the file from `downloadUrl` to get the data."
  mime_type MANIFEST_MIME_TYPE

  class << self
    def contents(server_context: nil)
      MCP::Resource::TextContents.new(
        uri: RESOURCE_URI,
        mime_type: MANIFEST_MIME_TYPE,
        text: JSON.generate(manifest)
      )
    end

    def context
      {
        "rdfs": "http://www.w3.org/2000/01/rdf-schema#",
        "schema": "https://schema.org/",
        "dcat": "http://www.w3.org/ns/dcat#",
        "dct": "http://purl.org/dc/terms/",

        "id": "@id",
        "name": "schema:name",
        "type": "@type",
        "byteSize": "dcat:byteSize",
        "downloadURL": "dcat:downloadURL",
        "comment": "rdfs:comment",
        "version": "schema:version",
        "isVersionOf": "dct:isVersionOf",
        "mediaType": "dcat:mediaType"
      }
    end

    def manifest
      entry = DatabusClient.new.latest_artifact(ARTIFACT_URI)

      static_fields
        .merge(
          "id": entry["distribution"],
          "comment": entry["comment"],
          "version": entry["version"],
          "isVersionOf": entry["artifact"],
          "downloadURL": entry["file"],
          "byteSize": entry["byteSize"]
        )
        .compact
    rescue DatabusClient::Error => e
      Rails.logger.error("ArtsdataDump manifest unavailable: #{e.message}")
      static_fields.merge("error" => e.message)
    end

    private

    def static_fields
      {
        "@context": context,
        "type": "dcat:Distribution",
        "name": DUMP_NAME,
        "mediaType": "text/turtle"
      }
    end

  end
end
