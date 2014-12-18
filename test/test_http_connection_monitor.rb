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

    assert_empty       options[:devices]
    assert_equal [80], options[:ports]
    assert             options[:resolve_names]
    assert_nil         options[:run_as_directory]
    assert_nil         options[:run_as_user]
    refute             options[:show_filter]
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

    assert_equal %w[8080], options[:ports]

    options = HTTPConnectionMonitor.process_args %w[-p 8080,http]

    assert_equal %w[8080 http], options[:ports]
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

  def test_filter
    monitor = HTTPConnectionMonitor.new ports: %w[http 8080]

    expected = <<-FILTER.split(/\s{2,}/).join(' ').strip
      ((tcp dst port http) or
        (tcp src port http and (tcp[tcpflags] & tcp-fin != 0))) or
      ((tcp dst port 8080) or
        (tcp src port 8080 and (tcp[tcpflags] & tcp-fin != 0)))
    FILTER

    assert_equal expected, monitor.filter
  end

  def test_process_packet
    out, = capture_io do
      capp = Capp.open(ONE_REQUEST_PCAP).loop do |packet|
        @monitor.process_packet packet
      end
    end

    assert_empty @monitor.in_flight_requests

    stat = HTTPConnectionMonitor::Statistic.new
    stat.add 1

    expected = {
      '173.10.88.49.80' => stat,
    }

    assert_equal expected, @monitor.request_statistics

    assert_equal "173.10.88.49.80       1\n", out

    assert_equal 1, @monitor.aggregate_statistics.count
  end

  def test_report
    [1, 1, 2, 3, 5, 8, 13].each do |requests|
      @monitor.aggregate_statistics.add requests
      @monitor.request_statistics['192.0.2.2.80'].add requests
    end

    [13, 21, 34].each do |requests|
      @monitor.aggregate_statistics.add requests
      @monitor.request_statistics['192.0.2.3.80'].add requests
    end

    out = @monitor.report

    expected = <<-EXPECTED.strip
Aggregate: (connections, min, avg, max, stddev)
    10      1   10.1     34   10.6

Per-connection: (connections, min, avg, max, stddev)
192.0.2.2.80               7      1    4.7     13    4.4
192.0.2.3.80               3     13   22.7     34   10.6
    EXPECTED

    assert_equal expected, out
  end

end

