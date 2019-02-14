module RedmineOauth2Login

  def setup
    RedmineOauth2Login::AccountControllerPatch.apply
  end

end 
