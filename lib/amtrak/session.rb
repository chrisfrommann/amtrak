require 'amtrak'
require 'mechanize'

module Amtrak

  class Session
    
    attr_reader :username

    def initialize
      @errors = []
    end
    
    def login(username: nil, password: nil, attempts: 2)
      @username ||= username
      @password ||= password
      
      Amtrak.logger.debug "Attempting to login as #{username}"
      
      if attempts > 1 && File.exist?(cookie_path)
        Amtrak.logger.debug "Found cached session cookie"
        agent.cookie_jar.load(cookie_path)
        page = agent.get(login_uri)
      else
        Amtrak.logger.debug "Posting creds to login page"
        page = agent.post(login_uri, request_body, headers)
        agent.cookie_jar.save(cookie_path, session: true)
      end
      
      if page.search("#un_logged_in").size > 0 || page.search("#pi_actions_list_logged_in").size > 0
        @logged_in = true
      elsif attempts > 0
        login(attempts: attempts - 1)
      else
        @logged_in = false
        @errors << 'Invalid or expired credentials'
      end
      @logged_in
    end
    
    def logout
      
    end
    
    def logged_in?
      if @logged_in
        return true
      else
        @errors << 'You are not logged in.'
        false
      end
    end
    
    def agent
      @agent ||= Mechanize.new.tap do |agent|
        agent.user_agent_alias = 'Windows Chrome'
        # agent.log = Amtrak.logger
        agent.log = Logger.new('./log.log')
      end
    end
    
    def accessible?
      false
    end
    
    private
    
    def cookie_path
      return "cookies-#{username.gsub(/[^a-z0-9]/i, '_')}.yml"
    end
    
    def login_uri
      'https://tickets.amtrak.com/itd/amtrak'
      #'https://assistive.usablenet.com/tt/tickets.amtrak.com/itd/amtrak'
    end
    
    def logout_uri
      raise NotImplementedError
    end
    
    def headers
      { 'Content-Type' => 'application/x-www-form-urlencoded' }
    end
    
    def request_body
      {
        "_handler=amtrak.presentation.handler.request.profile.AmtrakProfileLogonRequestHandler" + 
        "/_xpath=/sessionWorkflow/userWorkflow/profileAccountRequirements" => "",
        "requestor" => "amtrak.presentation.handler.page.profile.AmtrakProfileRegisterPageHandler",
        "xwdf_username" => "/sessionWorkflow/userWorkflow/profileAccountRequirements/userName",
        "wdf_username" => @username,
        "xwdf_password" => "/sessionWorkflow/userWorkflow/profileAccountRequirements/password",
        "wdf_password" => @password
      }
    end
    
  end
end