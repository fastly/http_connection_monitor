require 'http_connection_monitor/message'

require 'webrick'
require 'logger'

##
# A request in a stream of HTTP packets.
#
# This only parses the header for the request and ignores the body.

class HTTPConnectionMonitor::Request < HTTPConnectionMonitor::Message

  NULL_LOGGER = Logger.new IO::NULL # :nodoc:

  def initialize # :nodoc:
    super

    @request =
      WEBrick::HTTPRequest.new InputBufferSize: 2048, Logger: NULL_LOGGER

    @parser = Thread.new do
      @request.parse @read
    end
  end

  ##
  # Did the request include an explicit close?

  def explicit_close?
    /close/i =~ @request['connection']
  end

end

