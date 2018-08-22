module RedmineOauth2Login

  class Oauth2Wrapper
    
    def initialize(args)
      @settings = args.settings
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
    
    def profile(token)
      response = conn.get do |req|
        req.headers['Content-Type'] = 'application/json'
        req.headers['Authorization'] = "Bearer " + token
        req.url user_info_uri
      end
      profile = JSON.parse(response.body)
      return profile
    end
    
    def is_enabled()
      return @settings["enabled"].gsub(/\/+$/, '')
    end

    def is_replace_redmine_login()
      return @settings["replace_redmine_login"]
    end

    def logout_uri()
      return user_logout_uri + "?targetUrl=" + redmine_url
    end

    def redmine_url()
      return @settings["redmine_url"]
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

    def username(userDetails)
      for key in ["preferred_username", "username", "login", "user", "name"] do
        if userDetails[key].present?
          return userDetails[key]
        end
      end
    end

    def firstname(userDetails)
      for key in ["given_name", "firstname", "fullname", "name", "username", "login", "user"] do
        if userDetails[key].present?
          return userDetails[key]
        end
      end
      return username(userDetails)
    end

    def lastname(userDetails)
      for key in ["family_name", "lastname"] do
        if userDetails[key].present?
          return userDetails[key]
        end
      end
      return "OAuth2User"
    end

    def email(userDetails)
      for key in ["email"] do
        if userDetails[key].present?
          return userDetails[key]
        end
      end
      return username(userDetails) + "@email.error"
    end

    def callback_url(provider)
      return login_url.gsub(/\/+$/, '') + "/callback/" + provider
    end

    def login_callback_url()
      return redmine_url + "/oauth2/login/callback/" + provider
    end

    private
    def @settings
      Setting.plugin_redmine_oauth2_login
    end
    
  end
