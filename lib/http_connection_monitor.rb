require 'capp'
require 'optparse'
require 'resolv'
require 'thread'

class HTTPConnectionMonitor

  VERSION = '1.0'

  HTTP_METHODS = %w[
    CONNECT
    DELETE
    GET
    HEAD
    OPTIONS
    PATCH
    POST
    PUT
    TRACE
  ]

  HTTP_METHODS_RE = /\A#{Regexp.union HTTP_METHODS}/

  attr_reader :aggregate_statistics
  attr_accessor :in_flight_requests
  attr_accessor :request_statistics

  def self.process_args argv
    options = {
      devices:          [],
      port:             80,
      resolve_names:    true,
      run_as_directory: nil,
      run_as_user:      nil,
    }

    op = OptionParser.new do |opt|
      opt.on('-i', '--interface INTERFACE',
             'The interface to listen on or a tcpdump',
             'packet capture file.  Multiple interfaces',
             'can be specified.',
             "\n",
             'The tcpdump default interface and the',
             'loopback interface are the drbdump',
             'defaults') do |interface|
        options[:devices] << interface
      end

      opt.separator nil

      opt.on('-n', 'Disable name resolution') do |do_not_resolve_names|
        options[:resolve_names] = !do_not_resolve_names
      end

      opt.separator nil

      opt.on('-p', '--port PORT',
             'Listen for HTTP traffic on the given port') do |port|
        options[:port] = port
      end

      opt.separator nil

      opt.on(      '--show-filter',
             'Only show the tcpdump filter used.  This',
             'allows separate capture of packets via',
             'tcpdump which can be processed separately') do |show_filter|
        options[:show_filter] = show_filter
      end

      opt.separator nil

      opt.on(      '--run-as-directory DIRECTORY',
             'chroot to the given directory after',
             'starting packet capture',
             "\n",
             'Note that you must disable name resolution',
             'or provide /etc/hosts in the chroot',
             'directory') do |directory|
        options[:run_as_directory] = directory
      end

      opt.separator nil

      opt.on('-Z', '--run-as-user USER',
             'Drop root privileges and run as the',
             'given user') do |user|
        options[:run_as_user] = user
      end
    end

    op.parse! argv

    options
  rescue OptionParser::ParseError => e
    $stderr.puts op
    $stderr.puts
    $stderr.puts e.message

    abort
  end

  def self.run argv = ARGV
    options = process_args argv

    new(**options).run
  end

  def initialize devices: [], port: 80, resolve_names: true,
                 run_as_directory: nil, run_as_user: nil, show_filter: false
    @port             = port
    @resolver         = Resolv if resolve_names
    @run_as_directory = run_as_directory
    @run_as_user      = run_as_user
    @show_filter      = show_filter

    initialize_devices devices


    @aggregate_statistics = HTTPConnectionMonitor::Statistic.new

    # in-flight request count per connection
    @in_flight_requests   = Hash.new 0

    # history of request count per destination
    @request_statistics   = Hash.new do |h, destination|
      h[destination] = HTTPConnectionMonitor::Statistic.new
    end

    @capps            = []
    @incoming_packets = Queue.new
    @running          = false
  end

  def initialize_devices devices
    @devices = devices

    if @devices.empty? then
      devices = Capp.devices

      abort "you must run #{$0} with root permissions, try sudo" if
        devices.empty?

      loopback = devices.find do |device|
        device.addresses.any? do |address|
          %w[127.0.0.1 ::1].include? address.address
        end
      end

      @devices = [
        Capp.default_device_name,
        (loopback.name rescue nil),
      ].compact
    end

    @devices.uniq!
  end

  def capture_loop capp
    capp.loop do |packet|
      enqueue_packet packet
    end
  end

  def create_capp device
    max_http_method_length = HTTP_METHODS.map { |method| method.length }.max

    capp = Capp.open device, 100 + max_http_method_length

    capp.filter = filter

    capp
  end

  def display_connections
    @running = true

    @display_thread = Thread.new do
      while @running and packet = @incoming_packets.deq do
        process_packet packet
      end
    end
  end

  def enqueue_packet packet
    @incoming_packets.enq packet
  end

  def filter
    <<-FILTER.split(/\s{2,}/).join(' ').strip
      (tcp dst port #{@port}) or
        (tcp src port #{@port} and (tcp[tcpflags] & tcp-fin != 0))
    FILTER
  end

  def process_packet packet
    ip  = packet.ipv4_header || packet.ipv6_header
    tcp = packet.tcp_header

    src = packet.source @resolver
    dst = packet.destination @resolver

    src, dst = dst, src if tcp.source_port == 80

    connection = "#{src}:#{dst}"

    if tcp.fin? then
      requests = @in_flight_requests[connection]
      @in_flight_requests.delete connection

      return if requests.zero? # ignore FIN from other end

      @request_statistics[dst].add requests
      @aggregate_statistics.add requests

      puts "%-21s %d" % [dst, requests]

      return
    end

    if tcp.destination_port == 80 and HTTP_METHODS_RE =~ packet.payload then
      @in_flight_requests[connection] += 1
    end
  end

  def report
    aggregate = "%6d %6d %6.1f %6d %6.1f" % @aggregate_statistics.to_a

    per_connection = @request_statistics.map do |connection, statistic|
      "%-21s %6d %6d %6.1f %6d %6.1f" % [connection, *statistic]
    end

    out = []
    out << 'Aggregate: (connections, min, avg, max, stddev)'
    out << aggregate
    out << nil

    out << 'Per-connection: (connections, min, avg, max, stddev)'
    out.concat per_connection

    out.join "\n"
  end

  def run
    if @show_filter then
      puts filter
      exit
    end

    capps = @devices.map { |device| create_capp device }

    Capp.drop_privileges @run_as_user, @run_as_directory

    start_capture capps

    trap_info

    display_connections.join
  rescue Interrupt
    untrap_info

    stop

    @display_thread.join

    puts # clear ^C

    exit
  ensure
    puts report
  end

  def start_capture capps
    @capps.concat capps

    capps.map do |capp|
      Thread.new do
        capture_loop capp
      end
    end
  end

  def stop
    @running = false

    @capps.each do |capp|
      capp.stop
    end

    @incoming_packets.enq nil
  end

  def trap_info
    return unless Signal.list['INFO']

    trap 'INFO' do
      puts "%6d %6d %6.1f %6d %6.1f (count, min, avg, max, stddev)" %
        @aggregate_statistics.to_a
    end
  end

  def untrap_info
    return unless Signal.list['INFO']

    trap 'INFO', 'DEFAULT'
  end

end

require 'http_connection_monitor/statistic'

