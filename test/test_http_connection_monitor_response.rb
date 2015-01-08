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

  def test_explicit_close_eh_closed
    @response << EXPLICIT_CLOSE_RESPONSE

    Thread.pass while @response.in_process?

    assert @response.explicit_close?
  end

end

