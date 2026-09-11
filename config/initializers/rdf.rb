require "rdf"
require "rdf/util/cache"

# rdf 3.3.x interns URIs and blank nodes in RDF::Util::Cache, which on MRI defaults to an
# ObjectSpace._id2ref-based cache. Ruby 4.0 deprecates _id2ref and warns on every cache lookup.
# Use the gem's own WeakRef-based cache instead (what it already uses on JRuby).
#
# We can't simply upgrade: rdf >= 3.3.2 requires bigdecimal ~> 3.1, which conflicts with
# Rails 8.1's bigdecimal 4.x, and upstream (ruby-rdf/rdf develop) still picks ObjectSpaceCache.
# Remove this file once an rdf release no longer calls ObjectSpace._id2ref on Ruby >= 4.
if ObjectSpace.respond_to?(:_id2ref) && defined?(RDF::Util::Cache::WeakRefCache)
  module RdfWeakRefCacheFactory
    def new(*args)
      cache = RDF::Util::Cache::WeakRefCache.allocate
      cache.send(:initialize, *args)
      cache
    end
  end
  RDF::Util::Cache.singleton_class.prepend(RdfWeakRefCacheFactory)

  # Caches built while the gems were loading are still ObjectSpace-based; drop them so they are
  # rebuilt lazily with the WeakRef cache (they only intern objects, so nothing is lost).
  [RDF::URI, RDF::Node].each do |klass|
    klass.instance_variable_set(:@cache, nil) if klass.instance_variable_defined?(:@cache)
  end
end
