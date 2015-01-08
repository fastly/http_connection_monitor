require 'net/http'

class HTTPConnectionMonitor::Response

  def initialize
    read, @write = IO.pipe
    @read = Net::BufferedIO.new read

    @parser = Thread.new do
      @response = Net::HTTPResponse.read_new @read
    end
  end

  def << input
    @write << input
    @parser.run unless @parser.status == false
  end

  def explicit_close?
    /close/i =~ @response['connection']
  end

  def in_process?
    %w[run sleep].include? @parser.status
  end

end

