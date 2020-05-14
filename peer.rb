class Peer
  attr_reader :ip, :port, :torrent_file

  attr_accessor :socket, :thread, :bitfield, :id

  attr_accessor :chocked, :interested
  attr_accessor :choking, :interesting

  # timeout for socket reads
  TIMEOUT = 5

  def initialize ip, port, torrent_file
    @ip = ip
    @port = port

    @torrent_file = torrent_file

    @bitfield = "0" * torrent_file.pieces.size

    # Connections start out choked and not interested.
    @chocked = true
    @choking = true
    @interested  = false
    @interesting = false

    @mutex = Mutex.new
    @backlog = 0
  end

  def increment_backlog!
    @mutex.synchronize { @backlog += 1 }
  end

  def decrement_backlog!
    @mutex.synchronize { @backlog -= 1 }
  end

  def connect
    local_host = nil
    local_port = nil
    @socket = Socket.tcp(ip, port, local_host, local_port,
                      {connect_timeout: TIMEOUT})

    send_handshake

    start_read_loop

    true
  rescue Errno::ETIMEDOUT, Errno::ECONNRESET, Errno::ECONNREFUSED,
    Errno::EADDRNOTAVAIL, EOFError
    puts "Connection to Peer failed"
  end

  def send_handshake
    # The length of the protocol identifier, which is always 19 (0x13 in hex)
    # The protocol identifier, called the pstr which is always BitTorrent protocol
    # Eight reserved bytes, all set to 0. We’d flip some of them to 1 to indicate
    # that we support certain extensions. But we don’t, so we’ll keep them at 0.
    # The infohash that we calculated earlier to identify which file we want
    # The Peer ID that we made up to identify ourselves
    handshake = "#{Client::PROTOCOL_IDENTIFIER}00000000#{torrent_file.info_hash}#{Client::PEER_ID}"

    ios_ready = IO.select([], [socket], [], TIMEOUT)
    if ios_ready.nil?
      raise "IO not ready"
    end

    # send handshake
    begin
      bytes_written = socket.write(handshake)
      # puts "written #{bytes_written} bytes to socket"
    rescue IO::WaitWritable
      raise "Write failed"
    end

    # read returned handshake
    IO.select([], [socket], [], TIMEOUT)
    begin
      result = socket.read_with_timeout(68, TIMEOUT) # 68 = length of the handshake
      # puts result.inspect
    rescue IO::WaitReadable
      IO.select([socket])
      retry
    end

    # validate the returned handshake
    raise "Wrong protocol identifier" unless result[0..19] == Client::PROTOCOL_IDENTIFIER

    # puts "Extensions: #{result[20..27].inspect}" # 8 extension bytes
    # Not dealing with extensions for now
    # http://www.libtorrent.org/extension_protocol.html

    raise "Wrong info_hash returned" unless result[28..47] == torrent_file.info_hash
    id = result[48..67]
    puts "Peer ID: #{id}"
  rescue RangeError
    puts "Peer sent incorrect length"
  end

  def start_read_loop
    @thread = Thread.new do
      begin
        loop do
          # Calls select(2) system call. It monitors given arrays of IO
          # objects, waits until one or more of IO objects are ready for
          # reading (..)
          # ::select peeks the buffer of IO objects for testing readability.
          # If the IO buffer is not empty, ::select immediately notifies
          # readability.
          IO.select([socket], [], [])

          # 4 bytes for length of message
          length = socket.read_with_timeout(4, TIMEOUT)
          if length.nil?
            raise EOFError
          else
            length = length.unpack1 "N"
            # keep alive
            if length == 0
              socket.write [0].pack("N")

              next
            end

            payload = socket.read_with_timeout(length, TIMEOUT)

            handle_message length, payload
          end
        end
      rescue IO::WaitReadable
        IO.select([socket])
        retry
      end
    end
  end

  def handle_message length, payload
    message = Message.new length, payload
    # puts message.inspect

    case message.id
    when 0
      choking = true
    when 1
      choking = false
      # XXX:
      return true
    when 2
      interested = true
    when 3
      interested = false
    when 4
      have_piece message.payload
    when 5
      @bitfield = message.payload
    when 6
      # TODO: handle request
    when 7
      piece_idx = message.index
      block_idx = TorrentFile::Block.find_index(message.offset)

      block = torrent_file.pieces[piece_idx].blocks[block_idx]

      block.receive(message.data)

      unless block.have
        block.invalidate!
      end

      decrement_backlog!
    when 8
      # TODO: handle cancel
    end
  end

  def send_interested
    socket.write [1, 2].pack('NC')
  end

  def download_piece piece
    begin
      loop do
        if @backlog >= 5
          sleep 0.1
          next
        end

        block = piece.request_block

        if block.nil?
          if piece.corrupt_blocks.size > 0
            piece.invalidate_corrupt_blocks
            puts "INFO: invalidated corrupt blocks; try downloading blocks again"

            next
          end

          if piece.validate!
            puts "Piece #{piece.index_10} downloaded and validated"
          else
            puts "WARN: Piece #{piece.index_10} validation FAILED. Discarding blocks."
          end

          return
        end

        download_block piece, block

        increment_backlog!
      end
    rescue => e
      puts "Exception: #{e.message}"
      piece.invalidate!
    end
  end

  # message type consists of
  # - 4-byte message length
  # - 1-byte message ID
  # a payload composed of
  # - 4-byte piece index (0 based)
  # - 4-byte block offset
  # - 4-byte block length
  # within the piece (measured in bytes), and 4-byte block length
  def download_block piece, block
    payload = "#{piece.index}#{block.offset}#{[TorrentFile::REQUEST_LENGTH].pack("N*")}"
    request = "#{[1 + payload.bytesize].pack("N")}#{[6].pack("C")}#{payload}"

    socket.write request

    puts "Requested Piece #{piece.index_10} block #{block.index}"
  end

  # The payload is the zero-based index of a piece that has just been
  # successfully downloaded and verified via the hash.
  # The payload would be something like "\x00\x00\x04\xD1"
  def have_piece i
    bf_bin_string = bitfield.unpack1 'B*'

    idx = i.unpack1 "N*"

    bf_bin_string[idx] = '1'

    @bitfield = [bf_bin_string].pack('B*')
  end

  def has_piece? piece
    bf_bin_string = bitfield.unpack1 'B*'
    bf_bin_string[piece.index_10] == "1"
  end
end
