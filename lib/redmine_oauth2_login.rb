module RedmineOauth2Login

  def self.setup
    ::RedmineOauth2Login::AccountControllerPatch.apply
  end

end 
