require 'minitest/autorun'
require 'http_connection_monitor'

class TestHttpConnectionMonitor < MiniTest::Unit::TestCase

  test = File.expand_path '..', __FILE__

  ONE_REQUEST_PCAP = File.join test, 'one_request.pcap'

  def setup
    @monitor = HTTPConnectionMonitor.new
  end

  def test_process_packet
    out, = capture_io do
      capp = Capp.open(ONE_REQUEST_PCAP).loop do |packet|
        @monitor.process_packet packet
      end
    end

    assert_empty @monitor.in_flight_requests

    expected = {
      '173.10.88.49:80' => [1],
    }

    assert_equal expected, @monitor.request_counts

    assert_equal "173.10.88.49:80       1\n", out
  end

end

