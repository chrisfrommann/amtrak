require 'logger'

module Amtrak
  class Error < StandardError; end

  def self.logger
    @logger ||= Logger.new(STDOUT)
    #@logger ||= Logger.new('./log.log')
  end

end

Dir["./lib/amtrak/*.rb"].each {|file| require file }