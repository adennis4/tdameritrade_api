module TDAmeritradeApi
  module BalancesAndPositions
    BALANCES_AND_POSITIONS_URL='https://apis.tdameritrade.com/apps/100/BalancesAndPositions'

    # +get_positions+ get account balances
    # +options+ may contain any of the params outlined in the API docs
    # * accountid - one of the account ids returned from the login service
    # * type - type of data to be returned ('b' or 'p')
    # * suppress_quotes - whether or not quotes should be suppressed on the positions (true/false)
    # * alt_balance_format - whether or not the balances response should be returned in alternative format (true/false)
    def get_positions(account_id, options={})
      request_params = build_bp_params(account_id, options)

      uri = URI.parse BALANCES_AND_POSITIONS_URL
      uri.query = URI.encode_www_form(request_params)

      response = HTTParty.get(uri, headers: {'Cookie' => "JSESSIONID=#{@session_id}"}, timeout: 10)
      if response.code != 200
        raise TDAmeritradeApiError, "HTTP response #{response.code}: #{response.body}"
      end

      bp_hash = {"error"=>"failed"}
      result_hash = Hash.from_xml(response.body.to_s)
      if result_hash['amtd']['result'] == 'OK' then
        bp_hash = result_hash['amtd']['positions']
      end

      bp_hash
    rescue Exception => e
      raise TDAmeritradeApiError, "error in get_positions() - #{e.message}" if !e.is_ctrl_c_exception?
    end

    def get_balances(account_id, options={})
      request_params = build_bp_params(account_id, options)

      uri = URI.parse BALANCES_AND_POSITIONS_URL
      uri.query = URI.encode_www_form(request_params)

      response = HTTParty.get(uri, headers: {'Cookie' => "JSESSIONID=#{@session_id}"}, timeout: 10)
      if response.code != 200
        raise TDAmeritradeApiError, "HTTP response #{response.code}: #{response.body}"
      end

      bp_hash = {"error"=>"failed"}
      result_hash = Hash.from_xml(response.body.to_s)

      if result_hash['amtd']['result'] == 'OK' then

        balance = result_hash['amtd']['balance']
        margin_balance = balance['margin_balance'] ? balance['margin_balance']['current'].to_i : 0

        bp_hash = {
          'cash_balance' => balance['cash_balance']['current'].to_i,
          'money_market_balance' => balance['money_market_balance']['current'].to_i,
          'margin_balance' => margin_balance
        }
      end

      bp_hash
    rescue Exception => e
      raise TDAmeritradeApiError, "error in get_balances() - #{e.message}" if !e.is_ctrl_c_exception?
    end

    private

    def build_bp_params(account_id, options)
      {source: @source_id, accountid: account_id}.merge(options)
    end
  end
end
