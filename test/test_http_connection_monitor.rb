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

    assert_equal 1, @monitor.aggregate_statistics.count
  end

  def test_report
    @monitor.request_counts['192.0.2.2.80'] = [1, 1, 2, 3, 5, 8, 13]
    @monitor.request_counts['192.0.2.3.80'] = [13, 21, 34]

    @monitor.request_counts.values.flatten.each do |count|
      @monitor.aggregate_statistics.add count
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

  def test_statistics_per_connection
    @monitor.request_counts['192.0.2.2.80'] = [1, 1, 2, 3, 5, 8, 13]
    @monitor.request_counts['192.0.2.3.80'] = [13, 21, 34]

    stat_1 = HTTPConnectionMonitor::Statistic.new
    stat_1.add 1
    stat_1.add 1
    stat_1.add 2
    stat_1.add 3
    stat_1.add 5
    stat_1.add 8
    stat_1.add 13

    stat_2 = HTTPConnectionMonitor::Statistic.new
    stat_2.add 13
    stat_2.add 21
    stat_2.add 34

    expected = [
      ['192.0.2.2.80', stat_1],
      ['192.0.2.3.80', stat_2],
    ]

    assert_equal expected, @monitor.statistics_per_connection
  end

end

