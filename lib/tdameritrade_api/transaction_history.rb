module TDAmeritradeApi
  module TransactionHistory
    HISTORY_URL='https://apis.tdameritrade.com/apps/100/History'

    def get_transaction_history(account_id)
      request_params = build_transaction_history_params(account_id)

      uri = URI.parse HISTORY_URL
      uri.query = URI.encode_www_form(request_params)

      response = HTTParty.get(uri, headers: {'Cookie' => "JSESSIONID=#{@session_id}"}, timeout: 10)
      if response.code != 200
        raise TDAmeritradeApiError, "HTTP response #{response.code}: #{response.body}"
      end

      bp_hash = {"error"=>"failed"}
      result_hash = Hash.from_xml(response.body.to_s)
      if result_hash['amtd']['result'] == 'OK'
        bp_hash = result_hash['amtd']['history']
      end

      bp_hash
    rescue Exception => e
      raise TDAmeritradeApiError, "error in get_positions() - #{e.message}" if !e.is_ctrl_c_exception?
    end

    private

    def build_transaction_history_params(account_id)
      {
        source: @source_id,
        accountid: account_id,
        start_date: (Date.today - 1.month).strftime('%Y%m%d'),
        end_date: Date.today.strftime('%Y%m%d'),
        type: 0
      }
    end
  end
end
