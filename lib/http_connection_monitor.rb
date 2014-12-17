require 'capp'
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

  attr_accessor :in_flight_requests
  attr_accessor :request_counts

  def self.run argv = ARGV
    new.run
  end

  def initialize
    @capps = devices.map do |device|
      create_capp device
    end

    # in-flight request count per connection
    @in_flight_requests = Hash.new 0

    # history of request count per destination
    @request_counts     = Hash.new { |h, destination| h[destination] = [] }
    @incoming_packets   = Queue.new
    @running            = false
  end

  def capture_loop capp
    capp.loop do |packet|
      enqueue_packet packet
    end
  end

  def create_capp device
    max_http_method_length = HTTP_METHODS.map { |method| method.length }.max

    capp = Capp.open device, 100 + max_http_method_length

    # the last lines filter out zero-length packets just-in-case
    capp.filter = <<-FILTER
      ((tcp dst port 80) or (tcp src port 80 and (tcp[tcpflags] & tcp-fin != 0))) and
        ((((ip[2:2] - ((ip[0]&0xf)<<2)) - ((tcp[12]&0xf0)>>2)) != 0) or
         ((ip6[4:2]                     - ((tcp[12]&0xf0)>>2)) != 0))
    FILTER

    capp
  end

  def devices
    Capp.devices.select do |device|
      device.addresses.any? do |address|
        # an IPv4 addresses that is not point-to-point
        address.netmask =~ /\./ and not address.destination
      end
    end.map do |device|
      device.name # not necessary following capp-1.1
    end
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

  def process_packet packet
    ip  = packet.ipv4_header || packet.ipv6_header
    tcp = packet.tcp_header

    src = "#{ip.source}:#{tcp.source_port}"
    dst = "#{ip.destination}:#{tcp.destination_port}"

    src, dst = dst, src if tcp.source_port == 80

    connection = "#{src}:#{dst}"

    if tcp.fin? then
      requests = @in_flight_requests[connection]
      @in_flight_requests.delete connection

      return if requests.zero? # ignore FIN from other end

      @request_counts[dst] << requests

      puts "%-21s %d" % [dst, requests]

      return
    end

    if tcp.destination_port == 80 and HTTP_METHODS_RE =~ packet.payload
      @in_flight_requests[connection] += 1
    end
  end

  def run
    start_capture

    display_connections.join
  rescue Interrupt
    stop

    @display_thread.join

    puts # clear ^C

    exit
  end

  def start_capture
    @capps.map do |capp|
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

end