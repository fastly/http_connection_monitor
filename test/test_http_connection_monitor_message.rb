require 'minitest/autorun'
require 'http_connection_monitor'

class TestHTTPConnectionMonitorMessage < Minitest::Test

  class Message < HTTPConnectionMonitor::Message

    def initialize
      super

      @parser = Thread.new do
        @read.gets
      end
    end

  end

  def setup
    @message = Message.new
  end

  def test_append
    @message << "hello\n"

    Thread.pass while @message.in_process?

    refute @message.in_process?
  end

  def test_in_process_eh
    assert @message.in_process?, 'no lines added'

    @message << "hello"

    assert @message.in_process?, 'message incomplete, lines pending'

    @message << "\n"

    Thread.pass while @message.in_process?

    refute @message.in_process?, 'complete message added'
  end

end

