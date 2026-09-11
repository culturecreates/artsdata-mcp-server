namespace :artsdata do
  namespace :schema do
    desc "Download artsdata-schema.ttl into the bundled snapshot used when the live file is unreachable"
    task refresh_snapshot: :environment do
      schema = ArtsdataSchema.new
      turtle = schema.fetch_remote
      ShaclSchemaCompiler.compile_turtle(turtle) # refuse to save a file that does not parse
      File.write(schema.snapshot_path, turtle)
      puts "Wrote #{schema.snapshot_path} from #{schema.source_url}"
    end
  end
end
