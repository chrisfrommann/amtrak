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

cli.ask("Enter your Amtrak username:  ") { |q| q.default = config['credentials']['username'] }
unless config['credentials'].has_key? 'password'
  config['credentials']['password'] = cli.ask("Enter your Amtrak password:  ") { |q| q.echo = false }
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

(Date.today..(Date.today + 6.weeks)).each do |date|
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

        # results = schedule.find(origin: train['origin'],
        #                         destination: train['destination'],
        #                         date: date)
        # results.each do |r|
        #   r.to_s
        # end
        
        train['times'].each do |time|
          puts time
          
          schedule.buy(origin: train['origin'],
                       destination: train['destination'],
                       date: date,
                       time: Date.today + time['time'].seconds,
                       max_price: time['max_price'])
        
        end
      end
    end
  end
  
end