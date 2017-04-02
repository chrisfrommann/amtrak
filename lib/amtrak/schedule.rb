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
    
    def buy(origin:, destination:, date:, time: nil, train_number: nil, max_price: nil, billing_info: {})
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
              Amtrak.logger.debug "Verified the train # (#{train.train_number})"
              passenger_page = session.agent.get passenger_page_uri
              payment_page = process_passenger_info(passenger_page)
              confirmation_page = process_payment(payment_page, train, billing_info)
              # TODO: verify it went through
              pp confirmation_page
            end
          else
            puts "The lowest price (#{train.cost}) was higher than your max (#{max_price})"
          end
          
        end
      end
      return nil
    end
    
    def process_passenger_info(passenger_page)
      form = passenger_page.form('form')
      # Select e-ticket
      Amtrak.logger.debug "Select e-ticket"
      form.radiobutton_with(name: 'wdf_ticket_type',
                            value: 'TicketByEmail').check
      # Send a text alert if the train is running late
      Amtrak.logger.debug "Set up mobile notification for 45 mins"
      form.field_with(name: 'wdf_trainstatusalertmethod').value = 'S'
      # Set this to be hardcoded at 45 mins for now
      form.field_with(name: 'wdf_trainstatusalerttime').value = '00:45:00'
      # Decline the insurance (note, this loads via ajax on main site and can be skipped)
      # Amtrak.logger.debug "Decline the insurance"
      # form.radiobutton_with(name: 'AmtrakInsuranceOfferRadioOption1',
      #                       value: 'Declined').check
      form.submit(form.button_with(name: 
        '_handler=amtrak.presentation.handler.request.basket.AmtrakBasketTravellersRequestHandler'))
    end
    
    def process_payment(payment_page, train, billing_info)
      form = payment_page.form_with(id: 'payment_form')
      
      Amtrak.logger.debug "Grabbing and apply available vouchers"
      apply_vouchers(form, train)
      
      Amtrak.logger.debug "Fill in CC information for balance of ticket (if applicable)"
      if !billing_info.empty?
        # Payment info
        form.field_with(name: 'wdf_cc_holder_name').value = billing_info['name']
        form.field_with(name: 'wdf_cc_number').value = billing_info['credit_card_number']
        form.field_with(id: 'creditcardexpirymonth').value = "#{billing_info['credit_card_expiration'].month}-01"
        form.field_with(id: 'creditcardexpirydate').value = billing_info['credit_card_expiration'].year
        form.field_with(name: 'wdf_cc_security_id').value = billing_info['credit_card_security_code']
        # Address info
        form.field_with(name: 'wdf_cc_addressline1').value = billing_info['address1']
        form.field_with(name: 'wdf_cc_addressline2').value = billing_info['address2']
        form.field_with(name: 'wdf_cc_city').value = billing_info['city']
        form.field_with(name: 'wdf_cc_area').value = billing_info['state_province']
        form.field_with(name: 'wdf_cc_postcode').value = billing_info['postal_code']
      end
      
      Amtrak.logger.debug "Agree to the terms and conditions"
      # Oddly mechanizer won't let us select the existing field, perhaps
      # because it doesn't have a name or value?
      form.add_field!('termsandconditions', '1')
      
      # Make the purchase!
      form.submit(form.button_with(id: 'passenger_info_button'))
    end
    
    def apply_vouchers(form, train)
      # Grab the current valid vouchers from the vouchers endpoint
      voucher_page = session.agent.get voucher_uri
      # Add vouchers until value >= train.cost
      total_voucher_value = 0
      voucher_page.search("//input[contains(@name, 'eVoucherNumber')]").each do |voucher|
        voucher_value = (/^USD ([0-9.]+)/.match(voucher.attr('id')))[1].to_i
        if total_voucher_value < train.cost
          Amtrak.logger.debug "Applying $#{voucher_value} voucher"
          form.add_field!(voucher.attr('name'), voucher.attr('value'))
        else
          break
        end
        total_voucher_value += voucher_value 
      end
    end
    
    def fetch(date, origin, destination, &block)
      Amtrak.logger.debug "Looking up trains on #{date} for #{origin} -> #{destination}"
      page = session.agent.get tickets_uri
      form = page.form_with(name: 'form')
      # Set the origin and destination fields
      form.wdf_origin = origin
      form.wdf_destination = destination
      # Set the appropriate date
      if session.accessible?
        form.field_with(name: 'un_jtt_wdfdate1_dd').value = date.day
        form.field_with(name: 'un_jtt_wdfdate1_mm').value = date.month - 1
        form.field_with(name: 'un_jtt_wdfdate1_yyyy').value = date.year
        # Submit the page and the intermediate page to get results
        page = session.agent.submit(form, form.buttons.last)
        results = page.form('form').submit
      else
        form.field_with(name: "/sessionWorkflow/productWorkflow[@product='Rail']/tripRequirements/" +
          "journeyRequirements[1]/departDate.usdate").value = date.strftime("%m/%d/%Y")
        # Submit the page and the intermediate page to get results
        results = session.agent.submit(form, form.button_with(name: "_handler=amtrak.presentation.handler.request" + 
          ".rail.farefamilies.AmtrakRailFareFamiliesSearchRequestHandler/_xpath=/" +
          "sessionWorkflow/productWorkflow[@product='Rail']"))
      end
      
      parse(results, date, origin, destination, &block)
    end
    
    #
    # Parse results, where results is a Mechanizer page object for the schedule page
    #
    def parse(results, date, origin, destination, &block)
      trains = []
      
      results.search("//div[@id='dollar_section']/form[contains(@name, 'selectTrainForm')]").each do |form|
        buy_form = results.form_with(id: form.attr('id'))
        
        result = form.search(".//table[contains(@class, 'ffam-fare-family')]")

        train_time = result
          .search(".//tr[@class='ffam-segment-container']//div[@class='ffam-time']").text.strip
        train_number = result
          .search(".//tr[@class='ffam-segment-container']//div[@class='ffam-train-name-padding']").text.strip
        time_matches = /([0-9]{1,2}:[0-9]{2}[apm]{2})[\- ]*([0-9]{1,2}:[0-9]{2}[apm]{2})/.match(train_time)
        departure_time, arrival_time = Time.parse(time_matches[1]), Time.parse(time_matches[2])
        price_cells = result.search(".//tr[@class='ffam-prices-container']/td")
        add_to_cart_button = price_cells.search("div[@class='ffam-add-to-cart']/input").first
        lowest_price_span = price_cells.search("table[@class='ffam-price-container']//span").text.strip
        
        # Assume the train is sold out
        is_available = false
        lowest_price = 0
        if lowest_price_span.present?
          # This train is still available for purchase
          is_available = true
          lowest_price = (/\$([0-9]+)/.match(lowest_price_span)[1]).to_i
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
      'https://tickets.amtrak.com/itd/amtrak'
      #'https://assistive.usablenet.com/tt/tickets.amtrak.com/itd/amtrak?un_jtt_v_target=tickets'
    end
    
    def passenger_page_uri
      'https://tickets.amtrak.com/itd/amtrak?handler=amtrak%2epresentation%2ehandler' +
      '%2erequest%2erail%2eAmtrakRailSaveItineraryRequestHandler'
    end
    
    def voucher_uri
      'https://tickets.amtrak.com/itd/amtrak/RetrieveEVouchersLoggedIn'
    end
    
  end
end