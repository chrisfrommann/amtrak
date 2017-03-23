require 'amtrak'
require 'amtrak/train'
require 'chronic'

module Amtrak
  class Schedule
    
    attr_accessor :session
    
    def initialize(session)
      @session = session
    end
    
    def find(origin:, destination:, date:, time: nil, train_number: nil)
      fetch(date, origin, destination)
    end
    
    def buy(origin:, destination:, date:, time: nil, train_number: nil, max_price: nil)
      raise ArgumentError 'Must be logged in to buy train' unless session.logged_in?
      raise ArgumentError "Time or train must not be nil" if time.nil? && train.nil?
      
      fetch(date, origin, destination) do |train, buy_form, lowest_price_radio_button, add_to_cart_button|
        # puts "time to buy: #{time}"
        # puts "train.departure_time: #{train.departure_time}"
        # puts "difference:  #{(time - train.departure_time).abs} < #{15.minutes} "
        
        if (time - train.departure_time).abs < 15.minutes
          Amtrak.logger.debug "Found a train within 15 minutes of desired time (#{time})"
          
          if train.cost <= max_price
            Amtrak.logger.info "Buying train #{train.train_number} for #{train.cost} " \
                                "at #{train.departure_time}"
            buy_form.radiobutton_with(name: lowest_price_radio_button.attr('name'),
                                      value: lowest_price_radio_button.attr('value')).check
            itinerary_page = buy_form.submit(buy_form.button_with(name: add_to_cart_button.attr('name')))
            # Verify we clicked on the right train
            train_info = itinerary_page.search("//div[@id='itinerary_wrapper']" \
              "/div[contains(@class, 'content_area')]/div[contains(@class, 'content')]/p").text
            if train.train_number.match(train_info)
              Amtrak.logger.debug "Verified the train #"
              passenger_page = itinerary_page.forms[1].submit
              payment_page = process_passenger_info(passenger_page)
              process_payment(payment_page)
            end
          else
            puts "The lowest price (#{train.cost}) was higher than your max (#{max_price})"
          end
          
        end
      end
    end
    
    def process_passenger_info(passenger_page)
      form = passenger_page.form('form')
      # Send a text alert if the train is running late
      Amtrak.logger.debug "Set up mobile notification for 45 mins"
      form.field_with(name: 'wdf_trainstatusalertmethod').value = 'S'
      # Set this to be hardcoded at 45 mins for now
      form.field_with(name: 'wdf_trainstatusalerttime').value = '00:45:00'
      passenger_page = form.submit(form.button_with(name: 'un_jtt_trainStatusAlertMethod_change'))
      form = passenger_page.form('form')
      # Decline the insurance
      Amtrak.logger.debug "Decline the insurance"
      form.radiobutton_with(name: 'AmtrakInsuranceOfferRadioOption1',
                            value: 'Declined').check
      pp passenger_page
      form.submit(form.button_with(name: '_handler=amtrak.presentation.handler.request.basket.AmtrakBasketTravellersRequestHandler'))
    end
    
    def process_payment(payment_page)
      Amtrak.logger.debug "Apply the first voucher, if available"
      form = payment_page.form_with(id: 'payment_form')
      # See if there are any vouchers to be processed
      payment_page = form.submit(form.button_with(name: 'un_jtt_retrieve'))
      form = payment_page.form_with(id: 'payment_form')
      pp payment_page.body
      pp form
      # TODO: if we see checkboxes, check the first one and then hit submit
      
    end
    
    def fetch(date, origin, destination, &block)
      Amtrak.logger.debug "Looking up trains on #{date} for #{origin} -> #{destination}"
      page = session.agent.get tickets_uri
      form = page.form_with(name: 'form')
      # Set the origin and destination fields
      form.wdf_origin = origin
      form.wdf_destination = destination
      # Set the appropriate date
      form.field_with(name: 'un_jtt_wdfdate1_dd').value = date.day
      form.field_with(name: 'un_jtt_wdfdate1_mm').value = date.month - 1
      form.field_with(name: 'un_jtt_wdfdate1_yyyy').value = date.year
      # Submit the page and the intermediate page to get results
      page = session.agent.submit(form, form.buttons.last)
      results = page.form('form').submit
      parse(results, date, origin, destination, &block)
    end
    
    #
    # Parse results, where results is a Mechanizer page object for the schedule page
    #
    def parse(results, date, origin, destination, &block)
      trains = []
      buy_form = results.form_with(id: 'un_train_results')
      results.search("//div[@id='dollar_section']/div//table").each do |result|
        train_time = result
          .search("tbody/tr[@class='ffam-segment-container']//div[@class='ffam-time']").text.strip
        train_number = result
          .search("tbody/tr[@class='ffam-segment-container']//div[@class='ffam-train-name-padding']").text.strip
        time_matches = /([0-9]{1,2}:[0-9]{2}[apm]{2})[\- ]*([0-9]{1,2}:[0-9]{2}[apm]{2})/.match(train_time)
        departure_time, arrival_time = Time.parse(time_matches[1]), Time.parse(time_matches[2])
        price_cells = result.search("tbody/tr[@class='ffam-prices-container']/td")
        add_to_cart_button = price_cells.first.search("input").first
        lowest_price_node = price_cells.search("label/span").text
        
        # Assume the train is sold out
        is_available = false
        lowest_price = 0
        if lowest_price_node
          # This train is still available for purchase
          is_available = true
          lowest_price = (/\$([0-9]+)/.match(lowest_price_node.strip)[1]).to_i
          lowest_price_radio_button = price_cells.search("input[@type='radio']").first
        end
        
        trains << Amtrak::Train.new(date: date,
                                    train_number: train_number,
                                    origin: origin,
                                    destination: destination,
                                    cost: lowest_price,
                                    is_available: is_available,
                                    departure_time: departure_time,
                                    arrival_time: arrival_time)
        Amtrak.logger.debug "Found train #{trains.last}"
        
        if block_given?
          block.call(trains.last, buy_form, lowest_price_radio_button, add_to_cart_button)
        end
        
      end
      return trains
    end
    
    def tickets_uri
      'https://assistive.usablenet.com/tt/tickets.amtrak.com/itd/amtrak?un_jtt_v_target=tickets'
    end
    
  end
end