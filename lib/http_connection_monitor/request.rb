require 'webrick'
require 'logger'

class HTTPConnectionMonitor::Request

  NULL_LOGGER = Logger.new IO::NULL

  def initialize
    @read, @write = IO.pipe
    @request =
      WEBrick::HTTPRequest.new InputBufferSize: 2048, Logger: NULL_LOGGER

    @parser = Thread.new do
      @request.parse @read
    end
  end

  def << input
    @write << input
    @parser.run unless @parser.status == false
  end

  def [] header
    @request[header]
  end

  def explicit_close?
    /close/i =~ @request['connection']
  end

  def in_process?
    %w[run sleep].include? @parser.status
  end

end

