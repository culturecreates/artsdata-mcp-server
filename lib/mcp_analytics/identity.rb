require "digest"

module McpAnalytics


  module Identity


    SESSION_WINDOW_SECONDS = 30 * 60
    NAMESPACE = "artsdata-mcp"

    module_function

    def seed(session_id: nil, user_agent: nil, ip: nil)
      return "session:#{session_id}" if present?(session_id)

      "fingerprint:#{user_agent}|#{ip}"
    end

    def client_id(seed)
      digest = Digest::SHA256.hexdigest("#{NAMESPACE}:client:#{seed}")
      "#{digest[0, 9].to_i(16)}.#{digest[9, 9].to_i(16)}"
    end

    def session_id(seed, now: Time.now)
      bucket = now.to_i / SESSION_WINDOW_SECONDS
      Digest::SHA256.hexdigest("#{NAMESPACE}:session:#{seed}:#{bucket}")[0, 12].to_i(16).to_s
    end

    def present?(value)
      !(value.nil? || value.to_s.strip.empty?)
    end
  end
end
