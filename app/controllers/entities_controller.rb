class EntitiesController < ApplicationController
  SUPPORTED_LANGUAGES = %w[en fr].freeze

  def search
    query = params[:query].to_s
    lang = normalize_lang(params[:lang])
    return render_invalid_lang if lang.nil?

    result = ArtsdataClient.new.search_items(query: query, lang: lang)

    render json: {
      tool: "search-entities",
      result: result,
      arguments: {
        query: query,
        lang: lang
      }
    }
  end

  def show
    entity_id = params[:id].to_s
    lang = normalize_lang(params[:lang])
    return render_invalid_lang if lang.nil?

    result = ArtsdataClient.new.get_statements(entity_id: entity_id, lang: lang)

    render json: {
      tool: "get_statements",
      result: result,
      arguments: {
        entity_id: entity_id,
        include_external_ids: false,
        lang: lang
      }
    }
  end

  private

  def normalize_lang(value)
    return "en" if value.blank?
    return value if SUPPORTED_LANGUAGES.include?(value)

    nil
  end

  def render_invalid_lang
    render json: { error: "lang must be one of: #{SUPPORTED_LANGUAGES.join(', ')}" }, status: :unprocessable_content
  end
end
