require "digest"

module McpAnalytics
  # Reduces a SPARQL query to a short fingerprint of its *shape*, so that the
  # same question asked twice produces the same value however it was written.
  #
  # The point is pattern discovery: which query shapes do agents build against
  # Artsdata, and which recur often enough to be worth shipping as a template.
  # A fingerprint is therefore deliberately blind to everything that varies
  # between two askings of the same question, and sensitive to everything that
  # makes them different questions.
  #
  # What is normalised away, in the order it matters:
  #
  #   1. Variable names. This is the load-bearing step -- agents name variables
  #      differently every time, and without it nothing ever groups. Numbering
  #      is POSITIONAL (?v1, ?v2 in order of first appearance), never a single
  #      shared token: `{ ?a ?b ?c }` and `{ ?a ?a ?a }` are different shapes,
  #      and collapsing every variable to ?v would merge them.
  #   2. Literals and numbers. "festival" and "opera", LIMIT 20 and LIMIT 50.
  #   3. Prefix labels. Expanded to full IRIs, so schema: and s: agree.
  #
  # IRIs are kept whole and expanded, Artsdata resource URIs included: a query
  # about one venue is a different shape from a query about another. Patterns
  # are therefore narrower and more numerous, and they show which entities and
  # vocabulary concepts agents actually reach for.
  #
  # Regex-based rather than a real SPARQL parser, on purpose: a parser is a new
  # dependency and would reject the malformed queries most worth seeing. Nothing
  # here raises.
  module Sparql


    FINGERPRINT_LENGTH = 12

    PROLOGUE = /\bPREFIX\s+\S*:\s*<[^>]*>|\bBASE\s*<[^>]*>/i
    PREFIX_DECL = /\bPREFIX\s+(\S*):\s*<([^>]*)>/i
    LITERAL = /"""(?:.|\n)*?"""|'''(?:.|\n)*?'''|"(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'/
    NUMBER = /\b\d+(?:\.\d+)?\b/
    VARIABLE = /\?([A-Za-z_][A-Za-z0-9_]*)/

    module_function


    def fingerprint(query)
      shape = normalize(query)
      return nil if shape.nil?

      Digest::SHA256.hexdigest(shape)[0, FINGERPRINT_LENGTH]
    rescue StandardError
      nil
    end

    # The canonical shape the fingerprint is taken over. Exposed so it can be
    # inspected and tested directly -- a hash whose derivation you cannot read
    # is impossible to debug.
    def normalize(query)
      text = query.to_s
      return nil if text.strip.empty?

      prefixes = prefixes_in(text)

      shape = strip_comments(text)
      shape = shape.gsub(LITERAL, '"?"')
      shape = shape.gsub(PROLOGUE, " ")
      shape = expand_prefixes(shape, prefixes)
      shape = outside_iris(shape) { |run| run.gsub(NUMBER, "0") }
      shape = renumber_variables(shape)
      shape = shape.gsub(/\s+/, " ").strip

      shape.empty? ? nil : shape
    rescue StandardError
      nil
    end

    # A # starts a comment only outside an IRI and outside a string. Stripping
    # them with a plain regex destroys every namespace ending in # -- rdf:,
    # rdfs:, owl:, xsd:, skos: -- so this walks the text instead.
    def strip_comments(text)
      out = +""
      index = 0
      iri = false
      quote = nil

      while index < text.length
        char = text[index]

        if quote
          out << char
          if char == "\\"
            out << text[index + 1].to_s
            index += 2
            next
          end
          quote = nil if char == quote
        elsif iri
          out << char
          iri = false if char == ">"
        elsif char == "<"
          iri = true
          out << char
        elsif char == '"' || char == "'"
          quote = char
          out << char
        elsif char == "#"
          index += 1 while index < text.length && text[index] != "\n"
          next
        else
          out << char
        end

        index += 1
      end

      out
    end

    # Applies the block to every run of text that is not inside <...>.
    def outside_iris(text)
      text.split(/(<[^>]*>)/).each_with_index.map do |part, position|
        position.odd? ? part : yield(part)
      end.join
    end

    def prefixes_in(text)
      text.scan(PREFIX_DECL).to_h
    end

    def expand_prefixes(text, prefixes)
      prefixes.reduce(text) do |acc, (label, iri)|
        acc.gsub(/(?<![<\w])#{Regexp.escape(label)}:([A-Za-z0-9_\-.%]+)/) { "<#{iri}#{Regexp.last_match(1)}>" }
      end
    end

    # Positional, so that which variables are the SAME variable survives.
    def renumber_variables(text)
      seen = {}
      text.gsub(VARIABLE) do
        name = Regexp.last_match(1)
        seen[name] ||= "?v#{seen.size + 1}"
        seen[name]
      end
    end

  end
end
