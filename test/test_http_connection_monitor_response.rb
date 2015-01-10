require 'minitest/autorun'
require 'http_connection_monitor'

class TestHTTPConnectionMonitorResponse < Minitest::Test

  def setup
    @response = HTTPConnectionMonitor::Response.new
  end

  def test_implicit_close_eh_bodyless
    @response << <<-RESPONSE
HTTP/1.1 204 No Content\r
\r
    RESPONSE

    Thread.pass while @response.in_process?

    refute @response.closed?
  end

  def test_closed_eh_connection_close
    @response << <<-RESPONSE
HTTP/1.1 200 OK\r
Connection: close\r
\r
    RESPONSE

    Thread.pass while @response.in_process?

    assert @response.closed?
  end

  def test_closed_eh_content_length
    @response << <<-RESPONSE
HTTP/1.1 200 OK\r
Content-Length: 1\r
\r
    RESPONSE

    Thread.pass while @response.in_process?

    refute @response.closed?
  end

  def test_closed_eh_content_length_many
    @response << <<-RESPONSE
HTTP/1.1 200 OK\r
Content-Length: 1\r
Content-Length: 2\r
\r
    RESPONSE

    Thread.pass while @response.in_process?

    assert @response.closed?
  end

  def test_closed_eh_content_length_negative
    @response << <<-RESPONSE
HTTP/1.1 200 OK\r
Content-Length: -1\r
\r
    RESPONSE

    Thread.pass while @response.in_process?

    assert @response.closed?
  end

  def test_closed_eh_chunked
    @response << <<-RESPONSE
HTTP/1.1 200 OK\r
Transfer-Encoding: chunked\r
\r
    RESPONSE

    Thread.pass while @response.in_process?

    refute @response.closed?
  end

end

