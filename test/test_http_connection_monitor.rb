require 'minitest/autorun'
require 'http_connection_monitor'

class TestHttpConnectionMonitor < MiniTest::Unit::TestCase

  test = File.expand_path '..', __FILE__

  ONE_REQUEST_PCAP = File.join test, 'one_request.pcap'

  def setup
    @monitor = HTTPConnectionMonitor.new resolve_names: false
  end

  def test_class_process_args
    options = HTTPConnectionMonitor.process_args []

    assert_empty     options[:devices]
    assert_equal 80, options[:port]
    assert           options[:resolve_names]
    assert_nil       options[:run_as_directory]
    assert_nil       options[:run_as_user]
    refute           options[:show_filter]
  end

  def test_class_process_args_interface
    options = HTTPConnectionMonitor.process_args %w[-i lo0 -i en0]

    assert_equal %w[lo0 en0], options[:devices]
  end

  def test_class_process_args_name_resolution
    options = HTTPConnectionMonitor.process_args %w[-n]

    refute options[:resolve_names]
  end

  def test_class_process_args_port
    options = HTTPConnectionMonitor.process_args %w[-p 8080]

    assert_equal '8080', options[:port]
  end

  def test_class_process_args_run_as_directory
    options = HTTPConnectionMonitor.process_args %w[--run-as-directory /nonexistent]

    assert_equal '/nonexistent', options[:run_as_directory]
  end

  def test_class_process_args_run_as_user
    options = HTTPConnectionMonitor.process_args %w[--run-as-user nobody]

    assert_equal 'nobody', options[:run_as_user]
  end

  def test_class_process_args_show_filter
    options = HTTPConnectionMonitor.process_args %w[--show-filter]

    assert options[:show_filter]
  end

  def test_process_packet
    out, = capture_io do
      capp = Capp.open(ONE_REQUEST_PCAP).loop do |packet|
        @monitor.process_packet packet
      end
    end

    assert_empty @monitor.in_flight_requests

    expected = {
      '173.10.88.49.80' => [1],
    }

    assert_equal expected, @monitor.request_counts

    assert_equal "173.10.88.49.80       1\n", out
  end

end

