class HTTPConnectionMonitor::Message

  def initialize
    @read, @write = IO.pipe
  end

  ##
  # Appends captured +input+ for a request into the parser.

  def << input
    @write << input
    @parser.run unless @parser.status == false
  end

  ##
  # Is header parsing finished?

  def in_process?
    %w[run sleep].include? @parser.status
  end

end


