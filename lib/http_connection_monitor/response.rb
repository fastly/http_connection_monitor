require 'http_connection_monitor/message'
require 'net/http'

##
# A response in a stream of HTTP packets.
#
# This only parses the header for the response and ignores the body.

class HTTPConnectionMonitor::Response < HTTPConnectionMonitor::Message

  def initialize
    super

    @read = Net::BufferedIO.new @read

    @parser = Thread.new do
      @response = Net::HTTPResponse.read_new @read
    end
  end

  ##
  # Did the request include an explicit close?

  def explicit_close?
    /close/i =~ @response['connection']
  end

end

