require 'http_connection_monitor/message'
require 'net/http'

class HTTPConnectionMonitor::Response < HTTPConnectionMonitor::Message

  def initialize
    super

    @read = Net::BufferedIO.new @read

    @parser = Thread.new do
      @response = Net::HTTPResponse.read_new @read
    end
  end

  def explicit_close?
    /close/i =~ @response['connection']
  end

end

