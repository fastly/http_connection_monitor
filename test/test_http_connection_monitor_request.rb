require 'minitest/autorun'
require 'http_connection_monitor'

class TestHTTPConnectionMonitorRequest < Minitest::Test

  CLOSE_REQUEST = <<-REQUEST
GET / HTTP/1.1\r
Host: example\r
Connection: close\r
\r
  REQUEST

  PERSISTENT_REQUEST = <<-REQUEST
GET / HTTP/1.1\r
Host: example\r
\r
  REQUEST

  def setup
    @request = HTTPConnectionMonitor::Request.new
  end

  def test_explicit_close_eh_closed
    @request << CLOSE_REQUEST

    Thread.pass while @request.in_process?

    assert @request.explicit_close?
  end

  def test_explicit_close_eh_persistent
    @request << PERSISTENT_REQUEST

    Thread.pass while @request.in_process?

    refute @request.explicit_close?
  end

end

