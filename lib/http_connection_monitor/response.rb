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
  # Was the connection terminated by this request?

  def closed?
    return true if /close/i =~ @response['connection']

    return false unless @response.class.body_permitted?

    if transfer_encoding = @response['transfer-encoding'] then
      return false if /chunked\z/i =~ transfer_encoding
      return true
    end

    if content_lengths = @response.to_hash['content-length'] then
      return true if content_lengths.length > 1
      return /\A\d+\z/ !~ content_lengths.first
    end

    true
  end

end

