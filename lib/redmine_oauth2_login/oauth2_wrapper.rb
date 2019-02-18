module RedmineOauth2Login

  class Oauth2Wrapper
    
    @settings = nil
    
    def initialize(args)
      @settings = args[:settings]
    end

    def login_redirect()
      hash = {:response_type => "code",
              :client_id => client_id,
              :redirect_uri => login_callback_url}
      param_arr = []
      hash.each do |key , val|
        param_arr << "#{key}=#{val}"
      end
      params_str = param_arr.join("&")
      return authorization_uri + "?#{params_str}"
    end
    
    def token(code)
      conn = Faraday.new(:url => access_token_uri) do |faraday|
        faraday.request :url_encoded
        faraday.adapter Faraday.default_adapter
      end
      data = {
        :grant_type => "authorization_code",
        :client_id => client_id,
        :client_secret => client_secret,
        :code => code,
        :redirect_uri => login_callback_url
      }
      response = conn.post do |req|
        req.headers['Content-Type'] = 'application/x-www-form-urlencoded'
        req.body = URI.encode_www_form(data)
      end
      if "github".casecmp(provider) == 0
        token = CGI.parse(response.body)['access_token'][0].to_s
      else # oauth2
        token = JSON.parse(response.body)['access_token']
      end
      return token
    end
    
    def userProfile(token)
      conn = Faraday.new(:url => user_info_uri) do |faraday|
        faraday.adapter Faraday.default_adapter
      end
      response = conn.get do |req|
        req.headers['Content-Type'] = 'application/json'
        req.headers['Authorization'] = "Bearer " + token
      end
      user = Oauth2UserProfile.new({ :profile => JSON.parse(response.body) })
      return user
    end
    
    def is_enabled()
      return @settings["enabled"]
    end

    def is_replace_redmine_login()
      return @settings["replace_redmine_login"]
    end

    def logout_uri()
      return user_logout_uri + "?redirect_uri=" + redmine_uri
    end

    def redmine_uri()
      return @settings["redmine_uri"]
    end

    def provider()
      return @settings["provider"]
    end

    def client_id()
      return @settings["client_id"]
    end

    def client_secret()
      return @settings["client_secret"]
    end

    def access_token_uri()
      return @settings["access_token_uri"].gsub(/\/+$/, '')
    end

    def authorization_uri()
      return @settings["authorization_uri"].gsub(/\/+$/, '')
    end

    def user_logout_uri()
      return @settings["user_logout_uri"].gsub(/\/+$/, '')
    end

    def user_info_uri()
      return @settings["user_info_uri"].gsub(/\/+$/, '')
    end

    def login_callback_url()
      return redmine_uri + "/oauth2/login/callback/" + provider
    end

  end # Oauth2Wrapper

end # RedmineOauth2Login
