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

  def test_append
    @request << CLOSE_REQUEST

    Thread.pass while @request.in_process?

    refute @request.in_process?
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

  def test_in_process_eh
    lines = PERSISTENT_REQUEST.lines

    assert @request.in_process?, 'no lines added'

    @request << lines.shift

    assert @request.in_process?, 'request incomplete, lines pending'

    lines.each do |line|
      @request << line
    end

    Thread.pass while @request.in_process?

    refute @request.in_process?, 'complete request added'
  end

end

