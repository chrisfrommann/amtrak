require 'bundler/setup'
Bundler.require
require 'set'
require 'csv'
require 'active_support'
require 'active_support/core_ext'
require 'yaml'
require 'date'
require 'chronic'
require 'holidays/core_extensions/date'
class Date
  include Holidays::CoreExtensions::Date
end
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

require 'amtrak'

cli = HighLine.new

config = YAML.load_file('config.yml')
trains_by_dow = {}
config['trains'].each do |train|
  trains_by_dow[train['day_of_week']] ||= []
  trains_by_dow[train['day_of_week']] << train.reject{|k| k == 'day_of_week'}
end

today = Date.today.strftime('%Y-%m-%d')
now = DateTime.now
midnight = DateTime.new(now.year, now.month, now.day)

puts '========= Log-in ========='.blue.bold
# String.colors.each do |c|
#   begin
#     puts c.to_s.send(c)
#   rescue Exception => e
#     puts e.message
#   end
# end

config['credentials']['password'] = cli.ask("Enter your Amtrak username:  ") do |q|
  q.default = config['credentials']['username']
end
unless config['credentials'].has_key? 'password'
  config['credentials']['password'] = cli.ask("Enter your Amtrak password:  ") { |q| q.echo = false }
end

is_cc_billing = (cli.ask("Do you want to use a credit card (or just vouchers if available)? [Yn]") do |q|
  q.default = 'Y'
  q.limit = 1
  q.validate = /^[yn]$/i
end.downcase) == 'y'

if is_cc_billing
  config['billing'] = {
    'name' => cli.ask("What's your name on your card?") { |q| q.default = config['billing']['name'] },
    'credit_card_number' => cli.ask("Enter your credit card number:") do |q|
      q.default = config['billing']['credit_card_number']
    end,
    'credit_card_security_code' => cli.ask("What's your card security code") { |q| q.limit = 4 },
    'credit_card_expiration' => cli.ask("Enter the card expiration date", Date) do |q|
      q.default = config['billing']['credit_card_expiration']
    end,
    'address1' => cli.ask("Enter the first line of your billing address") do |q|
      q.default = config['billing']['address1']
    end,
    'address2' => cli.ask("Enter the second line of your billing address (if applicable)") do |q|
      q.default = config['billing']['address2']
    end,
    'city' => cli.ask("Enter the billing city") { |q| q.default = config['billing']['city'] },
    'state_province' => cli.ask("Enter your state or province") do |q|
      q.default = config['billing']['state_province']
    end,
    'postal_code' => cli.ask("Enter the postal code") { |q| q.default = config['billing']['postal_code'] }
  }
  puts config['billing'].inspect
end
  


# Log-in
session = Amtrak::Session.new
session.login(username: config['credentials']['username'],
              password: config['credentials']['password'])
a = session.agent

# Grab existing reservations
puts '========= Existing Reservations ========='.blue.bold
reservations = Amtrak::Reservations.new(session)
reservations.all.each do |t|
  if t.date < Date.today + 2.days
    puts "#{t.date.to_s.red}, #{t.train_number.blue}, #{t.origin} -> #{t.destination}"
  else
    puts "#{t.date.to_s}, #{t.train_number.blue}, #{t.origin} -> #{t.destination}"
  end
end


# Determine the date range we want to buy
puts '========= Buy new tickets ========='.blue.bold
schedule = Amtrak::Schedule.new(session)

((Date.today + 2.week)..(Date.today + 8.weeks)).each do |date|
  # Are we interested in this date?
  dow = date.strftime("%A")
  if trains = trains_by_dow[dow]
    if date.holiday?(:us)
      puts "Didn't buy because it's a holiday (#{dow}, #{date})"
      next
    end
    trains.each do |train|
      if reservations.exists?(date: date, origin: train['origin'], destination: train['destination'])
        puts "We've already bought trains from #{train['origin']} " + \
             "to #{train['destination']} on this day (#{dow}, #{date})"
      else
        puts "Let's buy #{train['origin']} to #{train['destination']} at #{dow}, #{date}"
        
        train['times'].each do |time|
          
          schedule.buy(origin: train['origin'],
                       destination: train['destination'],
                       date: date,
                       time: Date.today + time['time'].seconds,
                       max_price: time['max_price'],
                       billing_info: config['billing'])
        
        end
      end
    end
  end
  
end