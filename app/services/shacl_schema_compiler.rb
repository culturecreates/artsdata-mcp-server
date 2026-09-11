require "logger"
require "stringio"
require "rdf"
require "rdf/turtle"

# Compiles an RDF graph holding an ontology plus SHACL shapes (e.g. artsdata-schema.ttl) into a
# compact, class-centric JSON digest meant to be read by an LLM before it writes SPARQL.
#
# Compared with a mechanical Turtle -> JSON-LD conversion, the digest:
#   * is keyed by the classes you query (sh:targetClass), not by shape IRIs;
#   * merges every shape that applies to a class - including shapes on equivalent classes and
#     superclasses, and self-targeting value shapes (sh:targetObjectsOf) - into one property list;
#   * resolves shared property shapes, sh:node and sh:or indirection inline;
#   * writes every IRI as a CURIE (using the file's own prefixes) and every path as a SPARQL
#     property path, so values can be pasted straight into a query;
#   * drops validation-only noise (sh:message, sh:sparql, shape IRIs).
#
# The compiler is generic SHACL - nothing in here is specific to Artsdata except the input.
class ShaclSchemaCompiler
  SH = "http://www.w3.org/ns/shacl#".freeze
  RDFS = "http://www.w3.org/2000/01/rdf-schema#".freeze
  OWL = "http://www.w3.org/2002/07/owl#".freeze
  SKOS = "http://www.w3.org/2004/02/skos/core#".freeze
  DCTERMS = "http://purl.org/dc/terms/".freeze
  SCHEMA = "http://schema.org/".freeze

  MAX_NESTING = 3

  # Output key order for a property entry.
  PROPERTY_KEYS = %w[
    path label required min_count max_count node_kind datatypes classes in has_value pattern
    unique_lang language_in severity description range sub_property_of equivalent_properties value_shape
  ].freeze

  # Parses Turtle and compiles it. Raises RDF::ReaderError on invalid Turtle, with the parser's
  # first diagnostics in the message.
  def self.compile_turtle(turtle)
    graph = RDF::Graph.new
    # A fresh logger per parse: RDF.rb keeps its error count on the logger object and, with
    # validate: true, raises once that count is non-zero - so a shared logger (e.g. Rails.logger)
    # would make every parse after the first bad one fail. It also keeps diagnostics off stderr.
    diagnostics = StringIO.new
    reader = RDF::Turtle::Reader.new(turtle, validate: true, logger: Logger.new(diagnostics))
    begin
      reader.each_statement { |statement| graph << statement }
    rescue RDF::ReaderError => e
      details = diagnostics.string.lines.grep(/ERROR/).first(3).map(&:strip).join(" | ")
      raise RDF::ReaderError, [e.message, details].reject(&:empty?).join(": ")
    end
    prefixes = reader.prefixes.each_with_object({}) do |(name, iri), acc|
      acc[name.to_s] = iri.to_s unless name.to_s.empty?
    end
    new(graph, prefixes: prefixes).compile
  end

  attr_reader :graph, :prefixes

  def initialize(graph, prefixes:)
    @graph = graph
    @prefixes = prefixes.sort.to_h
  end

  def compile
    {
      "about" => about,
      "prefixes" => prefixes,
      "classes" => classes,
      "vocabularies" => vocabularies
    }
  end

  private

  # ---------------------------------------------------------------- about

  def about
    ontology = subjects(RDF.type, uri(OWL, "Ontology")).find(&:uri?)
    return {} unless ontology

    compact(
      "namespace" => ontology.to_s,
      "title" => text(objects(ontology, uri(DCTERMS, "title"))),
      "description" => text(objects(ontology, uri(DCTERMS, "description"))),
      "version" => text(objects(ontology, uri(OWL, "versionInfo"))),
      "modified" => text(objects(ontology, uri(DCTERMS, "modified")))
    )
  end

  # ---------------------------------------------------------------- classes

  def classes
    class_groups.map { |group| compile_class(group) }.sort_by { |c| c["class"] }
  end

  # Target classes, grouped so that owl:equivalentClass classes (e.g. ado:Event and schema:Event)
  # become one entry. The class targeted by the most shapes names the entry.
  def class_groups
    targeted = shapes_by_target_class.keys
    remaining = targeted.dup
    groups = []
    until remaining.empty?
      group = equivalence_closure(remaining.shift) & targeted
      remaining -= group
      groups << group.sort_by { |c| [-shapes_by_target_class[c].size, curie(c)] }
    end
    groups
  end

  def compile_class(group)
    primary = group.first
    members = equivalence_closure(primary)
    shapes = members.flat_map { |c| superclass_closure(c) }.uniq
                    .flat_map { |c| shapes_by_target_class.fetch(c, []) }.uniq

    property_entries = shapes.flat_map { |shape| objects(shape, sh(:property)) }.uniq
                             .map { |property_shape| compile_property_shape(property_shape, 0) }

    compact(
      "class" => curie(primary),
      "label" => first_text(members, uri(RDFS, "label")),
      "comment" => first_text(members, uri(RDFS, "comment")),
      "alternate_names" => members.flat_map { |c| objects(c, uri(SCHEMA, "alternateName")) }
                                  .select(&:literal?).map(&:value).uniq,
      "equivalent_classes" => (members - [primary]).map { |c| curie(c) }.sort,
      "subclass_of" => members.flat_map { |c| objects(c, uri(RDFS, "subClassOf")) }
                              .select(&:uri?).map { |c| curie(c) }.uniq.sort,
      "shapes" => shapes.select(&:uri?).map { |s| curie(s) }.sort
    ).merge("properties" => merge_by_path(property_entries).map { |entry| present(entry) })
  end

  # ---------------------------------------------------------------- property shapes

  def compile_property_shape(shape, depth)
    path = object(shape, sh(:path))
    return nil if path.nil? || deactivated?(shape)

    entry = constraints(shape, depth)
    entry["path"] = render_path(path)
    entry["label"] = text(objects(shape, sh(:name)))
    entry["description"] = text(objects(shape, sh(:description)))
    entry["min_count"] = integer(object(shape, sh(:minCount)))
    entry["max_count"] = integer(object(shape, sh(:maxCount)))
    entry["unique_lang"] = true if truthy?(object(shape, sh(:uniqueLang)))
    entry["language_in"] = list(object(shape, sh(:languageIn))).map(&:value)
    severity = object(shape, sh(:severity))
    entry["severity"] = local_name(severity) if severity && severity != sh(:Violation)

    if path.uri?
      add_ontology_facts(entry, path)
      value_shapes_for(path).each { |value_shape| attach_value_shape(entry, value_shape, depth) }
    end

    compact(entry)
  end

  # Value-type constraints shared by property shapes, node shapes and sh:or members.
  def constraints(shape, depth)
    entry = {
      "node_kind" => (kind = object(shape, sh(:nodeKind))) && local_name(kind),
      "datatypes" => objects(shape, sh(:datatype)).map { |d| curie(d) },
      "classes" => objects(shape, sh(:class)).map { |c| curie(c) },
      "in" => list(object(shape, sh(:in))).map { |v| render_value(v) },
      "has_value" => objects(shape, sh(:hasValue)).map { |v| render_value(v) },
      "pattern" => (pattern = object(shape, sh(:pattern))) && pattern.value
    }

    # sh:or / sh:xone: alternatives - surface the union of their datatypes and classes.
    [sh(:or), sh(:xone)].each do |alternatives|
      objects(shape, alternatives).flat_map { |l| list(l) }.each do |member|
        alternative = constraints(member, depth)
        entry["datatypes"] |= alternative.fetch("datatypes", [])
        entry["classes"] |= alternative.fetch("classes", [])
        entry["node_kind"] ||= alternative["node_kind"]
      end
    end

    objects(shape, sh(:node)).each { |node_shape| attach_value_shape(entry, node_shape, depth) }
    entry
  end

  # Describes the value node of a property: constraints on the node itself (class, node kind...)
  # are lifted onto the property entry, its own properties become `value_shape`.
  def attach_value_shape(entry, node_shape, depth)
    return if depth >= MAX_NESTING || deactivated?(node_shape)

    node = constraints(node_shape, depth + 1)
    %w[datatypes classes in has_value].each { |k| entry[k] = Array(entry[k]) | Array(node[k]) }
    entry["node_kind"] ||= node["node_kind"]
    entry["pattern"] ||= node["pattern"]

    properties = objects(node_shape, sh(:property)).map { |ps| compile_property_shape(ps, depth + 1) }.compact
    return if properties.empty?

    value_shape = { "label" => text(objects(node_shape, sh(:name))), "properties" => merge_by_path(properties) }
    entry["value_shape"] = merge_value_shapes([entry["value_shape"], compact(value_shape)].compact)
  end

  def add_ontology_facts(entry, property)
    entry["description"] ||= text(objects(property, uri(RDFS, "comment")))
    entry["range"] = objects(property, uri(RDFS, "range")).select(&:uri?).map { |r| curie(r) }
    entry["sub_property_of"] = objects(property, uri(RDFS, "subPropertyOf")).select(&:uri?).map { |p| curie(p) }
    equivalent = objects(property, uri(OWL, "equivalentProperty")) + subjects(uri(OWL, "equivalentProperty"), property)
    entry["equivalent_properties"] = equivalent.select(&:uri?).map { |p| curie(p) }.uniq.sort
  end

  # ---------------------------------------------------------------- merging

  # Several shapes can constrain the same path on one class (e.g. a core shape and an ontology
  # extension shape). All of them apply, so the merged entry keeps the strictest cardinality and
  # the union of the value constraints.
  def merge_by_path(entries)
    entries.compact.group_by { |e| e["path"] }.values
           .map { |group| merge_entries(group) }
           .sort_by { |e| [(e["min_count"] || 0) >= 1 ? 0 : 1, e["path"]] }
  end

  def merge_entries(entries)
    return entries.first if entries.one?

    merged = {}
    %w[path label description node_kind pattern].each { |k| merged[k] = entries.map { |e| e[k] }.compact.first }
    merged["min_count"] = entries.map { |e| e["min_count"] }.compact.max
    merged["max_count"] = entries.map { |e| e["max_count"] }.compact.min
    %w[datatypes classes has_value language_in range sub_property_of equivalent_properties].each do |k|
      merged[k] = entries.flat_map { |e| e.fetch(k, []) }.uniq
    end
    enumerations = entries.map { |e| e["in"] }.compact
    merged["in"] = enumerations.reduce(:&) unless enumerations.empty?
    merged["unique_lang"] = true if entries.any? { |e| e["unique_lang"] }
    severities = entries.map { |e| e["severity"] }.uniq
    merged["severity"] = severities.first if severities.one?
    merged["value_shape"] = merge_value_shapes(entries.map { |e| e["value_shape"] }.compact)
    compact(merged)
  end

  def merge_value_shapes(shapes)
    return nil if shapes.empty?
    return shapes.first if shapes.one?

    compact(
      "label" => shapes.map { |s| s["label"] }.compact.first,
      "properties" => merge_by_path(shapes.flat_map { |s| s.fetch("properties", []) })
    )
  end

  # Final, reader-facing form of a property entry: an explicit `required` flag, min_count only when
  # it says more than that, and a stable key order.
  def present(entry)
    out = entry.dup
    min = out.delete("min_count") || 0
    out["required"] = min >= 1
    out["min_count"] = min if min > 1
    out.delete("range") if out["classes"]&.any? # the shape's sh:class already says it
    if out["value_shape"]
      out["value_shape"] = out["value_shape"].merge(
        "properties" => out["value_shape"].fetch("properties", []).map { |p| present(p) }
      )
    end
    PROPERTY_KEYS.each_with_object({}) { |k, acc| acc[k] = out[k] if out.key?(k) }
  end

  # ---------------------------------------------------------------- vocabularies

  # Controlled vocabularies, from self-targeting value shapes such as
  #   ads:EventTypeConceptShape sh:targetObjectsOf ado:hasEventTypeConcept ;
  #     sh:property [ sh:path skos:inScheme ; sh:hasValue adr:ArtsdataEventTypes ] .
  def vocabularies
    in_scheme = uri(SKOS, "inScheme")
    value_shapes_by_property.flat_map do |property, shapes|
      shapes.flat_map do |shape|
        objects(shape, sh(:property))
          .select { |ps| object(ps, sh(:path)) == in_scheme }
          .flat_map { |ps| objects(ps, sh(:hasValue)) }
          .map do |scheme|
            compact(
              "property" => curie(property),
              "scheme" => curie(scheme),
              "label" => text(objects(shape, sh(:name))),
              "classes" => objects(shape, sh(:class)).map { |c| curie(c) }
            )
          end
      end
    end.sort_by { |v| v["property"] }
  end

  # ---------------------------------------------------------------- shape indexes

  def shapes_by_target_class
    @shapes_by_target_class ||= graph.query([nil, sh(:targetClass), nil])
                                     .reject { |st| deactivated?(st.subject) }
                                     .group_by(&:object)
                                     .transform_values { |sts| sts.map(&:subject).uniq }
  end

  def value_shapes_by_property
    @value_shapes_by_property ||= graph.query([nil, sh(:targetObjectsOf), nil])
                                       .reject { |st| deactivated?(st.subject) }
                                       .group_by(&:object)
                                       .transform_values { |sts| sts.map(&:subject).uniq }
  end

  def value_shapes_for(property)
    value_shapes_by_property.fetch(property, [])
  end

  def equivalence_closure(klass)
    equivalent = uri(OWL, "equivalentClass")
    seen = [klass]
    queue = [klass]
    until queue.empty?
      current = queue.shift
      (objects(current, equivalent) + subjects(equivalent, current)).each do |other|
        next if seen.include?(other)

        seen << other
        queue << other
      end
    end
    seen
  end

  # SHACL class targets also apply to instances of subclasses, so a class inherits the shapes of
  # its superclasses.
  def superclass_closure(klass)
    sub_class_of = uri(RDFS, "subClassOf")
    seen = [klass]
    queue = [klass]
    until queue.empty?
      objects(queue.shift, sub_class_of).each do |parent|
        next if seen.include?(parent)

        seen << parent
        queue << parent
      end
    end
    seen
  end

  # ---------------------------------------------------------------- rendering

  # Renders a SHACL property path as a SPARQL 1.1 property path.
  def render_path(path)
    return curie(path) if path.uri?

    if object(path, RDF.first)
      steps = list(path).map { |step| render_path(step) }
      return steps.one? ? steps.first : steps.join("/")
    end

    if (inverse = object(path, sh(:inversePath)))
      return "^#{group(render_path(inverse))}"
    end
    if (alternatives = object(path, sh(:alternativePath)))
      return "(#{list(alternatives).map { |step| render_path(step) }.join('|')})"
    end

    { zeroOrMorePath: "*", oneOrMorePath: "+", zeroOrOnePath: "?" }.each do |kind, suffix|
      inner = object(path, sh(kind))
      return "#{group(render_path(inner))}#{suffix}" if inner
    end

    path.to_s
  end

  def group(path)
    path.match?(%r{[/|^]}) && !path.start_with?("(") ? "(#{path})" : path
  end

  def render_value(term)
    term.uri? ? curie(term) : term.value
  end

  # CURIE for an IRI using the file's own prefixes; falls back to a SPARQL <IRI>.
  def curie(term)
    iri = term.to_s
    name, namespace = prefixes.select { |_, ns| iri.start_with?(ns) }.max_by { |_, ns| ns.length }
    return "<#{iri}>" unless namespace

    local = iri.delete_prefix(namespace)
    local.match?(/\A([A-Za-z0-9_](?:[\w\-.]*[\w\-])?)?\z/) ? "#{name}:#{local}" : "<#{iri}>"
  end

  def local_name(term)
    term.to_s.split(/[#\/]/).last
  end

  # ---------------------------------------------------------------- graph helpers

  def sh(local)
    uri(SH, local)
  end

  def uri(namespace, local)
    RDF::URI.new("#{namespace}#{local}")
  end

  def objects(subject, predicate)
    graph.query([subject, predicate, nil]).map(&:object).uniq
  end

  def object(subject, predicate)
    objects(subject, predicate).first
  end

  def subjects(predicate, object)
    graph.query([nil, predicate, object]).map(&:subject).uniq
  end

  def list(head)
    return [] if head.nil? || head == RDF.nil

    RDF::List.new(subject: head, graph: graph).to_a
  end

  # Prefers an English literal, then an untagged one.
  def text(terms)
    literals = terms.select(&:literal?)
    chosen = literals.find { |l| l.language.to_s == "en" } ||
             literals.find { |l| l.language.nil? } ||
             literals.first
    chosen&.value
  end

  def first_text(subjects, predicate)
    subjects.lazy.map { |s| text(objects(s, predicate)) }.find(&:itself)
  end

  def integer(term)
    term&.literal? ? Integer(term.value, exception: false) : nil
  end

  def truthy?(term)
    term&.literal? && term.value == "true"
  end

  def deactivated?(shape)
    truthy?(object(shape, sh(:deactivated)))
  end

  def compact(hash)
    hash.reject { |_, v| v.nil? || v == false || (v.respond_to?(:empty?) && v.empty?) }
  end
end
