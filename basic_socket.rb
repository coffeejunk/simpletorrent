# Monkey patch read_with_timeout into BasicSocket
# timeout here means "max time between successive bytes."
class BasicSocket
  def read_with_timeout length, timeout
    @reply = ''.b
    begin
      while @reply.length < length
        char = self.read_nonblock 1
        break if char.nil?
        @reply += char
      end
    rescue IO::WaitReadable
      retry if IO.select([self], [], [], timeout)
    end
    @reply.length == length ? @reply : nil
  end
end
