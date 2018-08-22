module AccountControllerPatch
  def self.included(base)
    base.send(:include, InstanceMethods)
    base.class_eval do
      unloadable
      alias_method_chain :login, :oauth2
      alias_method_chain :logout, :oauth2
    end
  end

  module InstanceMethods

    def login_with_oauth2
      if request.get? && oauth2_is_enabled && oauth2_is_replace_redmine_login
        if params.has_key?("admin")
          replaceRedmineLogin = "false".casecmp(params[:admin]) == 0
        elsif session[:using_redmine_login]
            replaceRedmineLogin = false
        else
          replaceRedmineLogin = true
        end
      end
      if replaceRedmineLogin
        redirect_to :controller => "account", :action => "oauth2_login", :provider => oauth2_get_provider, :origin => back_url and return
      else
        login_without_oauth2
      end
    end

    def logout_with_oauth2
      if oauth2_settings["enabled"]
        logout_user
        redirect_to oauth2_get_user_logout_uri + "?targetUrl=" + home_url and return
      else
        logout_without_oauth2
      end
    end

    def admin_login
      session[:using_redmine_login] = true
      render action: "login"
      session.delete(:using_redmine_login)
    end

    # login
    def oauth2_login
      if oauth2_settings["enabled"]
        session[:back_url] = params[:back_url]
        redirect_uri = oauth2_login_callback_url_1(:provider => params[:provider])
        hash = {:response_type => "code",
                :client_id => oauth2_get_client_id,
                :redirect_uri => redirect_uri}
        param_arr = []
        hash.each do |key , val|
          param_arr << "#{key}=#{val}"
        end
        params_str = param_arr.join("&")
        redirect_to oauth2_get_authorization_uri + "?#{params_str}" and return
      else
        password_authentication
      end
    end

    def oauth2_login_failure
      error = params[:message] || 'unknown'
      error = 'error_oauth2_login_' + error
      if oauth2_is_replace_redmine_login
        render_error({:message => error.to_sym, :status => 500})
        return false
      else
        flash[:error] = l(error.to_sym)
        redirect_to adminsignin_path and return
      end
    end

    # Token processing
    def oauth2_login_callback
      if params[:error]
        flash[:error] = l(:notice_access_denied)
        redirect_to adminsignin_path and return
      else
        # Access token
        code = params[:code]
        puts "Code: " + code
        conn = Faraday.new(:url => oauth2_get_access_token_uri) do |faraday|
          faraday.request :url_encoded
          faraday.response :logger
          faraday.adapter Faraday.default_adapter
        end
        response = conn.post do |req|
          req.params["grant_type"] = "authorization_code"
          req.params["client_id"] = oauth2_get_client_id
          req.params["client_secret"] = oauth2_get_client_secret
          req.params["code"] = code
          req.params["redirect_uri"] = oauth2_login_callback_url_1(:provider => params[:provider])
        end
        puts "response: #{response.body or 'nil'}"
        if "github".casecmp(params[:provider]) == 0
          token = CGI.parse(response.body)['access_token'][0].to_s
        else # oauth2
          token = JSON.parse(response.body)['access_token']
        end
        if token.blank?
          # logger.info("#{oauth2_settings['access_token_uri']} return #{response.body}")
          flash[:error] = l(:notice_unable_to_obtain_oauth2_access_token)
          redirect_to adminsignin_path and return
        end
        userInfoUri = oauth2_get_user_info_uri + "?access_token=#{token}"
        response = conn.get do |req|
          req.url userInfoUri
        end
        # Profile parse
        userDetails = JSON.parse(response.body)

        # if "github".casecmp(params[:provider]) == 0
        # Login
        if userDetails && userDetails["id"]
          extract_user_details userDetails
        else
          # logger.info("#{userInfoUri} return #{response.body}")
          flash[:error] = l(:notice_unable_to_obtain_oauth2_credentials)
          redirect_to adminsignin_path and return
        end
        #end provider=>github
      end
    end

    # Login
    def extract_user_details(userDetails)
      username = oauth2_username userDetails
      if username.blank?
        redirect_to adminsignin_path and return
        return
      end
      params[:back_url] = session[:back_url]
      session.delete(:back_url)
      if oauth2_settings["user_auto_create"]
        user = User.where(:login => username).first_or_create
        if user.new_record?
          user.login = username
          new_user user, userDetails
        else
          exist_user user
        end
      else
        user = User.where(:login => username).first
        if user
          exist_user user
        else 
          flash[:error] = l(:notice_user_access_denied)
          redirect_to adminsignin_path and return
        end
      end
    end

    # Exist user
    def exist_user(user)
        # Existing record
        if user.active?
          successful_authentication(user)
        else
          # Redmine 2.4 adds an argument to account_pending
          if Redmine::VERSION::MAJOR > 2 or
            (Redmine::VERSION::MAJOR == 2 and Redmine::VERSION::MINOR >= 4)
            account_pending(user)
          else
            account_pending
          end
        end
    end

    # Add new user
    def new_user(user, userDetails)
      # Create on the fly
      user.firstname = oauth2_firstname userDetails
      user.lastname = oauth2_lastname userDetails
      user.mail = oauth2_email userDetails
      user.random_password
      user.register
      # Here is some really dirty coding, because we override Redmine registration policies
      user.activate
      user.last_login_on = Time.now
      if user.save
        self.logged_user = user
        flash[:notice] = l(:notice_account_activated)
        redirect_to my_account_path and return
      else
        flash[:error] = l(:notice_oauth_account_denied)
        redirect_to adminsignin_path and return
      end
    end
    
    private
    def oauth2_is_enabled()
      return oauth2_settings["enabled"].gsub(/\/+$/, '')
    end

    private
    def oauth2_is_replace_redmine_login()
      return oauth2_settings["replace_redmine_login"]
    end

    private
    def oauth2_get_provider()
      return oauth2_settings["provider"]
    end

    private
    def oauth2_get_client_id()
      return oauth2_settings["client_id"]
    end

    private
    def oauth2_get_client_secret()
      return oauth2_settings["client_secret"]
    end

    private
    def oauth2_get_access_token_uri()
      return oauth2_settings["access_token_uri"].gsub(/\/+$/, '')
    end

    private
    def oauth2_get_authorization_uri()
      return oauth2_settings["authorization_uri"].gsub(/\/+$/, '')
    end

    private
    def oauth2_get_user_logout_uri()
      return oauth2_settings["user_logout_uri"].gsub(/\/+$/, '')
    end

    private
    def oauth2_get_user_info_uri()
      return oauth2_settings["user_info_uri"].gsub(/\/+$/, '')
    end

    private
    def oauth2_username(userDetails)
      for key in ["username", "login", "user", "name"] do
        if userDetails[key].present?
          return userDetails[key]
        end
      end
    end

    private
    def oauth2_firstname(userDetails)
      for key in ["firstname", "fullname", "name", "username", "login", "user"] do
        if userDetails[key].present?
          return userDetails[key]
        end
      end
      return oauth2_username(userDetails)
    end

    private
    def oauth2_lastname(userDetails)
      for key in ["lastname"] do
        if userDetails[key].present?
          return userDetails[key]
        end
      end
      return "OAuth2User"
    end

    private
    def oauth2_email(userDetails)
      for key in ["email", "fullname", "name", "username", "login", "user"] do
        if userDetails[key].present?
          return userDetails[key]
        end
      end
      return oauth2_username(userDetails) + "@email.error"
    end

    private
    def oauth2_callback_url(provider)
      return oauth2_login_url.gsub(/\/+$/, '') + "/callback/" + provider
    end

    private
    def oauth2_settings
      Setting.plugin_redmine_oauth2_login
    end
    
    private
    def oauth2_login_callback_url_1(args)
      return "https://project.anrisoftware.com" + "/oauth2/login/callback/" + args[:provider]
    end
  end
end