require 'minitest/autorun'
require 'http_connection_monitor'

class TestHTTPConnectionMonitorResponse < Minitest::Test

  EXPLICIT_CLOSE_RESPONSE = <<-RESPONSE
HTTP/1.1 200 OK\r
Connection: close\r
\r
  RESPONSE

  def setup
    @response = HTTPConnectionMonitor::Response.new
  end

  def test_append
    @response << EXPLICIT_CLOSE_RESPONSE

    Thread.pass while @response.in_process?

    refute @response.in_process?
  end

  def test_explicit_close_eh_closed
    @response << EXPLICIT_CLOSE_RESPONSE

    Thread.pass while @response.in_process?

    assert @response.explicit_close?
  end

  def test_in_process_eh
    lines = EXPLICIT_CLOSE_RESPONSE.lines

    assert @response.in_process?, 'no lines added'

    @response << lines.shift

    assert @response.in_process?, 'response incomplete, lines pending'

    lines.each do |line|
      @response << line
    end

    Thread.pass while @response.in_process?

    refute @response.in_process?, 'complete response added'
  end

end

