# Amtrak CLI tool
This is a tool to automatically buy several weeks of Amtrak tickets between two locations subject to pricing and date/time specfications
(specified in `config.yml`).
It uses the Mechanize ruby gem to purchase tickets as you. It can also be used to grab schedule data and look up your current reservations.

## Why?
I go back and forth between NYC and DC almost every week, but am not always sure when I'll be able to get out of work. Amtrak lets you
cancel your ticket up to the time of travel for no penalty as long as you put the value of the ticket into an eVoucher, which then
must be used within a year. Therefore, this allows a traveler to avoid committing to a particular train (or paying the highest price
to change last minute).

## Setup
1. Run `gem install bundler`
2. `bundle install`
3. `cp config.sample.yml config.yml` and edit 

## Running
1. Run `ruby ./amtrak_cli.rb`

## Known issues
* Purchasing using a credit card doesn't currently work (CC verification is being prompted); you'll have to use eVouchers (I suggest
purchasing an Acela first class ticket and then cancelling it :wink:

## TODO
* This should really be a gem
* This should really have tests
