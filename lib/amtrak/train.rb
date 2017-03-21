require 'amtrak'

module Amtrak
  class Train
    
    attr_accessor :date, :departure_time, :arrival_time,
                  :cost, :train_number, :is_available, :origin, :destination
    
    def initialize(date:, departure_time: nil, arrival_time: nil,
                   cost: nil, train_number:, is_available:, origin:, destination:)
      @date = date
      @departure_time = departure_time
      @arrival_time = arrival_time
      @cost = cost
      @train_number = train_number
      @is_available = is_available
      @origin = origin
      @destination = destination
    end
    
    def is_available?
      is_available
    end
    
    def to_s
      s = []
      self.instance_variables.each do |var|
        s << "#{var}: #{instance_variable_get(var)}"
      end
      return "Amtrak::Reservation [#{s.join(', ')}]"
    end
  end
end