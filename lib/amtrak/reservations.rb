require 'amtrak'
require 'amtrak/train'
require 'chronic'

module Amtrak
  class Reservations
    
    attr_accessor :session
    
    def initialize(session)
      @session = session
    end
    
    def all
      raise ArgumentError('Must be logged in to request reservations') unless session.logged_in?
      @reservations ||= fetch
    end
    
    def by_date      
      @reservations_by_date ||= all.reduce{|m, r| m[r.date] = r}
    end
    
    def exists?(date:, origin:, destination:)
      raise ArgumentError "Date must be of type 'date'" unless date.is_a?(Date)
      unless /[a-z]{3}/i.match(origin) && /[a-z]{3}/i.match(destination)
        raise ArgumentError "Origin and destination must be code"
      end
      # Cache for future use
      @reservations_set ||= all.reduce(Set.new) do |m, r|
        m.add("#{r.date}#{r.origin.downcase}#{r.destination.downcase}")
      end
      @reservations_set.include?("#{date}#{origin.downcase}#{destination.downcase}")
    end
    
    private
    
    def fetch
      page = session.agent.get reservations_uri
      Amtrak.logger.debug 'Looking up reservations'
      reservations = []
      page.search("//div[@id='tripdetails']/div[contains(@class, 'tabbed_block')]").each do |res|
        date = Chronic.parse(res.search("div[@class='date']").text.strip).to_date
        train = /([0-9]{2,3}) /.match(res.search("div[@class='route']").text)[1]
        origin, destination = res.search("div[@class='route']/a").map{|s| s.text }
        Amtrak.logger.debug "#{date}, #{train}, #{origin} -> #{destination}"
        reservations << Amtrak::Train.new(date: date,
                                          train_number: train,
                                          is_available: true,
                                          origin: origin,
                                          destination: destination)
      end
      reservations
    end
    
    def reservations_uri
      #'https://assistive.usablenet.com/tt/tickets.amtrak.com/itd/amtrak/Reservations?un_jtt_v_show=yes'
      'https://tickets.amtrak.com/itd/amtrak/Reservations'
    end
    
  end
end