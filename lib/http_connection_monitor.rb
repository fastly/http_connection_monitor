require 'capp'
require 'optparse'
require 'resolv'
require 'thread'

##
# Monitors HTTP connections for reuse of persistent connections.

class HTTPConnectionMonitor

  ##
  # The version of http_connection_monitor you are using

  VERSION = '1.0'

  ##
  # HTTP methods

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

  HTTP_METHODS_RE = /\A#{Regexp.union HTTP_METHODS}/ # :nodoc:

  ##
  # Statistics across all completed connections.

  attr_reader :aggregate_statistics

  ##
  # Request counts for in-flight connections.

  attr_accessor :in_flight_requests

  ##
  # Ports to listen for HTTP traffic

  attr_reader :ports

  ##
  # Per-connection statistics.

  attr_accessor :request_statistics

  ##
  # Verbosity of output.  0 is quiet

  attr_accessor :verbosity

  ##
  # Processes arguments from +argv+ and returns an options Hash that ::new can
  # use.

  def self.process_args argv
    options = {
      devices:          [],
      ports:            [80],
      resolve_names:    true,
      run_as_directory: nil,
      run_as_user:      nil,
      verbosity:        1,
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

      opt.on('-p', '--port PORT[,PORT]', Array,
             'Listen for HTTP traffic on the given ports') do |ports|
        options[:ports] = ports
      end

      opt.separator nil

      opt.on('-q', '--quiet',
             'Do not display per-packet messages') do
        options[:verbosity] = 0
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

  ##
  # Runs the connection monitor using the arguments given in +argv+

  def self.run argv = ARGV
    options = process_args argv

    new(**options).run
  end

  ##
  # Creates a new HTTPConnectionMonitor.  The following arguments are
  # accepted:
  #
  # +devices+ ::
  #   The network interfaces to listen on.
  # +ports+ ::
  #   The ports to listen for HTTP traffic on.  May be either port numbers or
  #   names.
  # +resolve_names+ ::
  #   When true host names are resolved and displayed.
  # +run_as_directory+ ::
  #   Directory to chroot() to when dropping privileges.
  # +run_as_user+ ::
  #   User to run as when dropping privileges.
  # +show_filter+ ::
  #   When true HTTPConnectionMonitor will print out the filter for use with
  #   tcpdump instead of processing packets.

  def initialize devices: [], ports: [80], resolve_names: true,
                 run_as_directory: nil, run_as_user: nil, show_filter: false,
                 verbosity: 1
    @ports            = ports.map { |port| Socket.getservbyname port.to_s }
    @resolver         = Resolv if resolve_names
    @run_as_directory = run_as_directory
    @run_as_user      = run_as_user
    @show_filter      = show_filter
    @verbosity        = verbosity

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

  ##
  # Verifies the given list of +devices+.

  def initialize_devices devices # :nodoc:
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

  ##
  # Enqueues captured packets.

  def capture_loop capp # :nodoc:
    capp.loop do |packet|
      enqueue_packet packet
    end
  end

  ##
  # Sets up a capture device for processing HTTP packets.

  def create_capp device # :nodoc:
    max_http_method_length = HTTP_METHODS.map { |method| method.length }.max

    capp = Capp.open device, 100 + max_http_method_length

    capp.filter = filter

    capp
  end

  ##
  # Enqueues +packet+ for processing.

  def enqueue_packet packet # :nodoc:
    @incoming_packets.enq packet
  end

  ##
  # The tcpdump filter string used for capturing packets.

  def filter
    @ports.map do |port|
      <<-FILTER.split(/\s{2,}/).join(' ').strip
        ((tcp dst port #{port}) or
          (tcp src port #{port} and (tcp[tcpflags] & tcp-fin != 0)))
      FILTER
    end.join ' or '
  end

  ##
  # Updates statistics for +packet+

  def process_packet packet # :nodoc:
    tcp = packet.tcp_header

    src = packet.source @resolver
    dst = packet.destination @resolver

    src, dst = dst, src if @ports.include? tcp.source_port

    connection = "#{src}:#{dst}"

    if tcp.fin? then
      requests = @in_flight_requests[connection]
      @in_flight_requests.delete connection

      return if requests.zero? # ignore FIN from other end

      @request_statistics[dst].add requests
      @aggregate_statistics.add requests

      puts "%-21s %d" % [dst, requests] unless quiet?

      return
    end

    if @ports.include?(tcp.destination_port) and
       HTTP_METHODS_RE =~ packet.payload then
      @in_flight_requests[connection] += 1
    end
  end

  ##
  # Creates the thread for processing packets

  def process_packets # :nodoc:
    @running = true

    @process_thread = Thread.new do
      while @running and packet = @incoming_packets.deq do
        process_packet packet
      end
    end
  end

  ##
  # Is the monitor in quiet mode?

  def quiet?
    @verbosity.zero?
  end

  ##
  # Returns a report on the connections and requests captured.

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

  ##
  # The main run loop.  Captures packets or shows the tcpdump filter depending
  # on the initialization arguments.

  def run
    if @show_filter then
      puts filter
      exit
    end

    capps = @devices.map { |device| create_capp device }

    Capp.drop_privileges @run_as_user, @run_as_directory

    run_capture capps
  end

  ##
  # The run loop for packet capturing.

  def run_capture capps # :nodoc:
    capture_threads = start_capture capps

    trap_info

    process_packets

    capture_threads.each do |thread|
      thread.join
    end

    @incoming_packets.enq nil
  rescue Interrupt
    stop

    puts # clear ^C
  ensure
    @process_thread.join if @process_thread

    untrap_info

    puts report if $!.nil? || Interrupt === $!
  end

  ##
  # Starts capturing packets on the Capp devices in +capps+.  New devices can
  # be added at any time.

  def start_capture capps
    @capps.concat capps

    capps.map do |capp|
      Thread.new do
        capture_loop capp
      end
    end
  end

  ##
  # Stops packet capture.

  def stop
    @running = false

    @capps.each do |capp|
      capp.stop
    end

    @incoming_packets.enq nil
  end

  ##
  # Adds a SIGINFO handler that prints out current aggregate statistics.

  def trap_info # :nodoc:
    return unless Signal.list['INFO']

    trap 'INFO' do
      if @aggregate_statistics.count.zero? then
        puts "no requests"
      else
        puts "%6d %6d %6.1f %6d %6.1f (count, min, avg, max, stddev)" %
          @aggregate_statistics.to_a
      end
    end
  end

  ##
  # Removes the SIGINFO handler.

  def untrap_info
    return unless Signal.list['INFO']

    trap 'INFO', 'DEFAULT'
  end

end

require 'http_connection_monitor/statistic'

