require "mcp"
require "json"

class ArtsdataCoreMinusProvenanceDump < MCP::Resource
  RESOURCE_URI = "artsdata://dumps/core-minus-provenance/latest".freeze
  MANIFEST_MIME_TYPE = "application/json".freeze

  ARTIFACT = "core-minus-provenance".freeze
  ARTIFACT_URI = "http://kg.artsdata.ca/databus/culture-creates/artsdata-dump/#{ARTIFACT}".freeze

  DUMP_TYPE = "ArtsdataDump".freeze
  DUMP_NAME = "Artsdata core minus provenance".freeze
  DUMP_DESCRIPTION = "Latest public dump of the Artsdata core graph with provenance and RDF-star " \
    "annotations removed. Intended for RDF 1.1 consumers, AI agents, " \
    "reconciliation workflows, and systems that cannot parse RDF 1.2/Turtle-star.".freeze
  DUMP_CONTENT = "Artsdata core graph without provenance, RDF 1.1 compatible".freeze

  DUMP_FORMAT = "text/turtle".freeze
  DUMP_COMPRESSION = "gzip".freeze

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

    def manifest
      entry = DatabusClient.new.latest_artifact(ARTIFACT_URI)

      static_fields
        .merge(
          "version" => entry["latestVersion"],
          "content" => DUMP_CONTENT,
          "format" => DUMP_FORMAT,
          "compression" => DUMP_COMPRESSION,
          "downloadUrl" => entry["file"]
        )
        .compact
    rescue DatabusClient::Error => e
      Rails.logger.error("ArtsdataDump manifest unavailable: #{e.message}")
      static_fields.merge("error" => e.message)
    end

    private

    def static_fields
      {
        "@context": {
          "schema": "https://schema.org/",
          "dcat": "http://www.w3.org/ns/dcat#",
          "dataid": "http://dataid.dbpedia.org/ns/core#",

          "uri": "@id",
          "type": {
            "@id": "http://www.w3.org/1999/02/22-rdf-syntax-ns#type",
            "@type": "@id"
          },
          "name": "schema:name",
          "description": "schema:description",
          "version": "schema:version",
          "content": "schema:disambiguatingDescription",
          "format": "dcat:mediaType",
          "compression": "dcat:compressionFormat",
          "downloadUrl": {
            "@id": "dcat:downloadURL",
            "@type": "@id"
          },
          "artifactName": "dataid:artifactName",
          "artifactUri": "dataid:artifact"
        },
        "uri" => RESOURCE_URI,
        "type" => DUMP_TYPE,
        "name" => DUMP_NAME,
        "description" => DUMP_DESCRIPTION,
        "artifact" => ARTIFACT,
        "artifactUri" => ARTIFACT_URI
      }
    end
  end
end
