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
      wrapper = RedmineOauth2Login::Oauth2Wrapper.new(oauth2_settings)
      if request.get? && wrapper.is_enabled && wrapper.is_replace_redmine_login
        if params.has_key?("admin")
          replaceRedmineLogin = "false".casecmp(params[:admin]) == 0
        elsif session[:using_redmine_login]
            replaceRedmineLogin = false
        else
          replaceRedmineLogin = true
        end
      end
      if replaceRedmineLogin
        redirect_to :controller => "account", :action => "oauth2_login", :provider => wrapper.provider, :origin => back_url and return
      else
        login_without_oauth2
      end
    end

    def logout_with_oauth2
      wrapper = RedmineOauth2Login::Oauth2Wrapper.new(oauth2_settings)
      if wrapper.is_enabled
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
      wrapper = RedmineOauth2Login::Oauth2Wrapper.new(oauth2_settings)
      if wrapper.is_enabled
        session[:back_url] = params[:back_url]
        redirect_to wrapper.login_redirect and return
      else
        password_authentication
      end
    end

    def oauth2_login_failure
      wrapper = RedmineOauth2Login::Oauth2Wrapper.new(oauth2_settings)
      error = params[:message] || 'unknown'
      error = 'error_oauth2_login_' + error
      if wrapper.is_replace_redmine_login
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
        wrapper = RedmineOauth2Login::Oauth2Wrapper.new(oauth2_settings)
        # Access token
        code = params[:code]
        token = wrapper.token(code)
        if token.blank?
          # logger.info("#{oauth2_settings['access_token_uri']} return #{response.body}")
          flash[:error] = l(:notice_unable_to_obtain_oauth2_access_token)
          redirect_to adminsignin_path and return
        end
        profile = wrapper.profile(token)

        # if "github".casecmp(params[:provider]) == 0
        # Login
        if userDetails && userDetails["preferred_username"]
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
    def oauth2_settings
      Setting.plugin_redmine_oauth2_login
    end
    
  end
end