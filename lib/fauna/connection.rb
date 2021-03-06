module Fauna
  class Connection
    class Error < RuntimeError
      attr_reader :param_errors

      def initialize(message, param_errors = {})
        @param_errors = param_errors
        super(message)
      end
    end

    class NotFound < Error; end
    class BadRequest < Error; end
    class Unauthorized < Error; end
    class NotAllowed < Error; end
    class NetworkError < Error; end

    HANDLER = Proc.new do |res, _, _|
      case res.code
      when 200..299
        res
      when 400
        json = JSON.parse(res)
        raise BadRequest.new(json['error'], json['param_errors'])
      when 401
        raise Unauthorized, JSON.parse(res)['error']
      when 404
        raise NotFound, JSON.parse(res)['error']
      when 405
        raise NotAllowed, JSON.parse(res)['error']
      else
        raise NetworkError, res
      end
    end

    def initialize(params={})
      @logger = params[:logger] || nil
      @api_version = params[:version] || "v1/"

      if ENV["FAUNA_DEBUG"]
        @logger = Logger.new(STDERR)
        @debug = true
      end

      # Check credentials from least to most privileged, in case
      # multiple were provided
      @credentials = if params[:token]
        CGI.escape(@key = params[:token])
      elsif params[:client_key]
        CGI.escape(params[:client_key])
      elsif params[:publisher_key]
        CGI.escape(params[:publisher_key])
      elsif params[:email] and params[:password]
        "#{CGI.escape(params[:email])}:#{CGI.escape(params[:password])}"
      else
        raise TypeError
      end
    rescue TypeError
      raise ArgumentError, "Credentials must be in the form of a hash containing either :publisher_key, :client_key, or :token, or both :email and :password."
    end

    def get(ref, query = nil)
      parse(execute(:get, ref, nil, query))
    end

    def post(ref, data = nil)
      parse(execute(:post, ref, data))
    end

    def put(ref, data = nil)
      parse(execute(:put, ref, data))
    end

    def patch(ref, data = nil)
      parse(execute(:patch, ref, data))
    end

    def delete(ref, data = nil)
      execute(:delete, ref, data)
      nil
    end

    private

    def parse(response)
      obj = if response.empty?
        {}
      else
        JSON.parse(response)
      end
      obj.merge!("headers" => response.headers.stringify_keys)
      obj
    end

    def log(indent)
      Array(yield).map do |string|
        string.split("\n")
      end.flatten.each do |line|
        @logger.debug(" " * indent + line)
      end
    end

    def query_string_for_logging(query)
      if query
        "?" + query.map do |k,v|
          "#{k}=#{v}"
        end.join("&")
      end
    end

    def execute(action, ref, data = nil, query = nil)
      args = { :method => action, :url => url(ref), :headers => {} }

      if query
        args[:headers].merge! :params => query
      end

      if data
        args[:headers].merge! :content_type => :json
        args.merge! :payload => data.to_json
      end

      if @logger
        log(2) { "Fauna #{action.to_s.upcase}(\"#{ref}#{query_string_for_logging(query)}\")" }
        log(4) { "Request JSON: #{JSON.pretty_generate(data)}" } if @debug && data

        t0, r0 = Process.times, Time.now

        RestClient::Request.execute(args) do |res, _, _|
          t1, r1 = Process.times, Time.now
          real = r1.to_f - r0.to_f
          cpu = (t1.utime - t0.utime) + (t1.stime - t0.stime) + (t1.cutime - t0.cutime) + (t1.cstime - t0.cstime)
          log(4) { ["Response headers: #{JSON.pretty_generate(res.headers)}", "Response JSON: #{res}"] } if @debug
          log(4) { "Response (#{res.code}): API processing #{res.headers[:x_time_total]}ms, network latency #{((real - cpu)*1000).to_i}ms, local processing #{(cpu*1000).to_i}ms" }

          HANDLER.call(res)
        end
      else
        RestClient::Request.execute(args, &HANDLER)
      end
    end

    def url(ref)
      "https://#{@credentials}@rest.fauna.org/#{@api_version}#{ref}"
    end
  end
end
