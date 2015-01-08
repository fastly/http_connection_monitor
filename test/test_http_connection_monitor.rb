require 'minitest/autorun'
require 'http_connection_monitor'

class TestHttpConnectionMonitor < Minitest::Test

  test = File.expand_path '..', __FILE__

  ONE_REQUEST_PCAP = File.join test, 'one_request.pcap'

  def setup
    @monitor = HTTPConnectionMonitor.new resolve_names: false
  end

  def test_class_process_args
    options = HTTPConnectionMonitor.process_args []

    assert_empty        options[:devices]
    assert_equal [80],  options[:ports]
    assert              options[:resolve_names]
    assert_nil          options[:run_as_directory]
    assert_nil          options[:run_as_user]
    assert_equal false, options[:show_reason]
    assert_equal false, options[:show_tcpdump]
    assert_equal 1,     options[:verbosity]
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

  def test_class_process_args_quiet
    options = HTTPConnectionMonitor.process_args %w[-q]

    assert_equal 0, options[:verbosity]
  end

  def test_class_process_args_run_as_directory
    options = HTTPConnectionMonitor.process_args %w[--run-as-directory /nonexistent]

    assert_equal '/nonexistent', options[:run_as_directory]
  end

  def test_class_process_args_run_as_user
    options = HTTPConnectionMonitor.process_args %w[--run-as-user nobody]

    assert_equal 'nobody', options[:run_as_user]
  end

  def test_class_process_args_show_reason
    options = HTTPConnectionMonitor.process_args %w[--show-reason]

    assert options[:show_reason]
  end

  def test_class_process_args_show_tcpdump
    options = HTTPConnectionMonitor.process_args %w[--show-tcpdump]

    assert options[:show_tcpdump]
  end

  def test_initialize_port
    monitor = HTTPConnectionMonitor.new ports: ['http', 8080]

    assert_equal [80, 8080], monitor.ports
  end

  def test_filter
    monitor = HTTPConnectionMonitor.new ports: %w[http 8080]

    expected = <<-FILTER.split(/\s{2,}/).join(' ').strip
      ((tcp dst port 80) or
        (tcp src port 80 and (tcp[tcpflags] & tcp-fin != 0))) or
      ((tcp dst port 8080) or
        (tcp src port 8080 and (tcp[tcpflags] & tcp-fin != 0)))
    FILTER

    assert_equal expected, monitor.filter
  end

  def test_process_packet
    out, = capture_io do
      Capp.open(ONE_REQUEST_PCAP).loop do |packet|
        @monitor.process_packet packet
      end
    end

    assert_empty @monitor.in_flight_request_counts

    stat = HTTPConnectionMonitor::Statistic.new
    stat.add 1

    expected = {
      '173.10.88.49.80' => stat,
    }

    assert_equal expected, @monitor.request_statistics

    assert_equal "173.10.88.49.80       1\n", out

    assert_equal 1, @monitor.aggregate_statistics.count

    refute_empty out
  end

  def test_process_packet_quiet
    @monitor.verbosity = 0

    assert_silent do
      Capp.open(ONE_REQUEST_PCAP).loop do |packet|
        @monitor.process_packet packet
      end
    end

    refute_empty @monitor.request_statistics
  end

  def test_quiet_eh
    refute @monitor.quiet?

    @monitor.verbosity = 0

    assert @monitor.quiet?
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

