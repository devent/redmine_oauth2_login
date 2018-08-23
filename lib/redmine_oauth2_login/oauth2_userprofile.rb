module RedmineOauth2Login

  class Oauth2UserProfile
    
    @profile = nil
    
    def initialize(args)
      @profile = args[:profile]
    end
    
    def username()
      for key in ["preferred_username", "username", "login", "user", "name"] do
        if @profile[key].present?
          return @profile[key]
        end
      end
    end
    
    def firstname()
      for key in ["given_name", "firstname", "fullname", "name", "username", "login", "user"] do
        if @profile[key].present?
          return @profile[key]
        end
      end
      return username()
    end

    def lastname()
      for key in ["family_name", "lastname"] do
        if @profile[key].present?
          return @profile[key]
        end
      end
      return "OAuth2User"
    end

    def email()
      for key in ["email"] do
        if @profile[key].present?
          return @profile[key]
        end
      end
      return username() + "@email.error"
    end

  end

end
