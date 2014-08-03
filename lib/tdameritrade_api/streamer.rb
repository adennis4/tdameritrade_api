require 'net/http'
require 'tdameritrade_api/streamer_types'

module TDAmeritradeApi
  module Streamer

    # +create_streamer+ use this to create a connection to the TDA streaming server
    def create_streamer
      Streamer.new(get_streamer_info, login_params_hash, @session_id)
    end

    class Streamer
      include StreamerTypes
      STREAMER_REQUEST_URL='http://ameritrade02.streamer.com/'

      attr_reader :streamer_info_response, :authentication_params, :session_id, :thread

      def initialize(streamer_info_raw, login_params, session_id)
        @streamer_info_response = streamer_info_raw

        @authentication_params = Hash.new
        @authentication_params = @authentication_params.merge(login_params).merge(parse_streamer_request_params)

        @session_id = session_id

        @buffer = String.new
        @message_block = nil
      end

      def run(&block)
        @message_block = block

        uri = URI.parse STREAMER_REQUEST_URL
        post_data="!U=#{authentication_params[:account_id]}&W=#{authentication_params[:token]}&" +
            "A=userid=#{authentication_params[:account_id]}&token=#{authentication_params[:token]}&" +
            "company=#{authentication_params[:company]}&segment=#{authentication_params[:segment]}&" +
            "cddomain=#{authentication_params[:cd_domain_id]}&usergroup=#{authentication_params[:usergroup]}&" +
            "accesslevel=#{authentication_params[:access_level]}&authorized=#{authentication_params[:authorized]}&" +
            "acl=#{authentication_params[:acl]}&timestamp=#{authentication_params[:timestamp]}&" +
            "appid=#{authentication_params[:app_id]}|S=QUOTE&C=SUBS&P=VXX+XIV&T=0+1+2|control=false" +
            "|source=#{authentication_params[:source]}\n\n"

        request = Net::HTTP::Post.new('/')
        request.body = post_data

        #outfile=File.join(Dir.tmpdir, "sample_stream.binary")
        #w = open(outfile, 'wb')
        @thread = Thread.new do
          Net::HTTP.start(uri.host, uri.port) do |http|
            http.request(request) do |response|
              response.read_body do |chunk|
                @buffer = @buffer + chunk
                #w.write(chunk)
                process_buffer
              end
            end
          end
        end
        # @thread = Thread.new do
        #   # 25.times do |i|
        #   #   yield({the_data: 123, iteration: i})
        #   #   sleep 1
        #   #end
        # end
      end

      private

      def post_data(data)
        @message_block.call(data) # sends formatted stream data back to wherever Streamer.run was called
      end

      def build_parameters(opts={})
        {
            "!U"=>authentication_params[:account_id],
            "W"=>authentication_params[:token],
            "A=userid"=>authentication_params[:account_id],
            "token"=>authentication_params[:token],
            "company"=>authentication_params[:company],
            "segment"=>authentication_params[:segment],
            "cddomain"=>authentication_params[:cd_domain_id],
            "usergroup"=>authentication_params[:usergroup],
            "accesslevel"=>authentication_params[:access_level],
            "authorized"=>authentication_params[:authorized],
            "acl"=>authentication_params[:acl],
            "timestamp"=>authentication_params[:timestamp],
            "appid"=>authentication_params[:app_id],
            "source"=>authentication_params[:source],
            "version"=>"1.0"
        }.merge(opts)
      end

      def parse_streamer_request_params
        p = Hash.new
        r = Nokogiri::XML::Document.parse @streamer_info_response
        si = r.xpath('/amtd/streamer-info').first
        p[:token] = si.xpath('token').text
        p[:cd_domain_id] = si.xpath('cd-domain-id').text
        p[:usergroup] = si.xpath('usergroup').text
        p[:access_level] = si.xpath('access-level').text
        p[:acl] = si.xpath('acl').text
        p[:app_id] = si.xpath('app-id').text
        p[:authorized] = si.xpath('authorized').text
        p[:timestamp] = si.xpath('timestamp').text
        p
      end

      def next_record_type_in_buffer
        if @buffer.length > 0
          case @buffer[0]
            when 'H'
              return :heartbeat
            when 'N'
              return :snapshot
            when 'S'
              return :stream_data
            else
              return nil
          end
        else
          return nil
        end
      end

      def unload_buffer(bytes)
        @buffer.slice!(0,bytes)
      end

      def process_heartbeat
        return if @buffer.length < 2

        if @buffer[0] == 'H'
          hb = Heartbeat.new

          # Next char is 'T' (followed by time stamp) or 'H' (no time stamp)
          if @buffer[1] == 'T'
            return if @buffer.length < 10
            hb.timestamp_indicator = true
            hb.timestamp = Time.at(@buffer[2..9].reverse.unpack('q').first/1000)
            unload_buffer(10)
          elsif @buffer[1] != 'H'
            hb.timestamp_indicator = false
            unload_buffer(2)
          else
            raise TDAmeritradeApiError, "Unexpected character in stream. Expected: Heartbeat timestamp indicator 'T' or 'H'"
          end

          post_data(hb)
        end

      end

      def process_snapshot
        return if @buffer.bytes.index(0x0A).nil?

        # !!!! THIS IS TEMPORARY PSEUDOCODE THAT DOES NOT REALLY PROCESS !!!!
        data = @buffer.slice!(0, @buffer.bytes.index(0x0A) + 1)
        post_data("'N' Snapshot found: #{data}")
      end

      def process_stream_data
        return if @buffer.bytes.index(0x0A).nil?

        # !!!! THIS IS TEMPORARY PSEUDOCODE THAT DOES NOT REALLY PROCESS !!!!
        data = @buffer.slice!(0, @buffer.bytes.index(0x0A) + 1)
        post_data("'S' Stream data found: #{data}")
      end

      def process_buffer
        # advance until we get a recognizable code in the stream
        until @buffer.length == 0 || !next_record_type_in_buffer.nil?
          @buffer.slice!(0,1)
        end

        case next_record_type_in_buffer
          when :heartbeat
            process_heartbeat
          when :snapshot
            process_snapshot
          when :stream_data
            process_stream_data
        end

      end

    end

    private

    STREAMER_INFO_URL='https://apis.tdameritrade.com/apps/100/StreamerInfo'

    def get_streamer_info
      uri = URI.parse STREAMER_INFO_URL
      uri.query = URI.encode_www_form({source: @source_id})

      response = HTTParty.get(uri, headers: {'Cookie' => "JSESSIONID=#{@session_id}"}, timeout: 10)
      if response.code != 200
        raise TDAmeritradeApiError, "HTTP response #{response.code}: #{response.body}"
      end

      response.body
    end

    def login_params_hash
      {
          company: @accounts.first[:company],
          segment: @accounts.first[:segment],
          account_id: @accounts.first[:account_id],
          source: @source_id
      }
    end
  end
end