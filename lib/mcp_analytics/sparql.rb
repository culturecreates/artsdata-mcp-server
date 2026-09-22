# frozen_string_literal: true

module McpAnalytics
  # Pulls two reportable facts out of a SPARQL query string.
  #
  # Deliberately regex-based rather than a real SPARQL parser. A parser would
  # mean a new dependency and, worse, would reject the malformed queries we most
  # want to see -- an agent failing to write valid SPARQL from get_schema output
  # is exactly the signal worth capturing. Nothing here ever raises.
  module Sparql
    UNKNOWN_FORM = "UNKNOWN"
    FORM_PATTERN = /\b(SELECT|ASK)\b/i
    LITERAL_PATTERN = /"""(?:.|\n)*?"""|'''(?:.|\n)*?'''|"(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'/
    NOISE_PATTERN = /#[^\n]*|\b(?:PREFIX\s+\S*:\s*<[^>]*>|BASE\s*<[^>]*>)/i

    module_function

    # SELECT, ASK or UNKNOWN when the string is not
    # recognisably a query. UNKNOWN paired with status=tool_error is the signal
    # that agents cannot write valid SPARQL from get_schema.
    #
    # Literals are blanked before the search so a keyword inside a string --
    # `?e schema:name "please ASK someone"` -- is not mistaken for the form.
    def form(query)
      text = strip_noise(query).gsub(LITERAL_PATTERN, '""')
      match = text[FORM_PATTERN, 1]
      match ? match.upcase : UNKNOWN_FORM
    rescue StandardError
      UNKNOWN_FORM
    end

    # The WHERE clause exactly as the agent wrote it, minus the PREFIX block and
    # with whitespace collapsed to single spaces. Collapsing is formatting, not
    # rewriting: the same query on one line or ten is the same query.
    #
    # Literals and variable names are left untouched, so two agents asking the
    # same question with different variable names produce different strings.
    def where_clause(query)
      text = strip_noise(query)

      inner = text[/\bWHERE\s*\{(.*)\}/mi, 1] ||
              text[/\bASK\s*\{(.*)\}/mi, 1] ||
              # WHERE is optional in SPARQL: SELECT ?s { ?s ?p ?o }
              text[/\{(.*)\}/m, 1]
      return nil if inner.nil?

      collapsed = inner.gsub(/\s+/, " ").strip
      collapsed.empty? ? nil : collapsed
    rescue StandardError
      nil
    end


    def strip_noise(query)
      query.to_s.gsub(NOISE_PATTERN, " ")
    end
  end
end
