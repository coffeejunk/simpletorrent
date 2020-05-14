def get_peers tf
  response = RestClient.get(tf.announce, params: {
    info_hash: tf.info_hash,
    port: PORT,
    peer_id: PEER_ID,
    download: 0, # TODO: update this as we upload / download ?
    uploaded: 0,
    left: tf.length,
    compact: 1, # see comment below
  })

  # re/ compact:
  # https://www.bittorrent.org/beps/bep_0023.html
  # It is common now to use a compact format where each peer is represented
  # using only 6 bytes. The first 4 bytes contain the 32-bit ipv4 address.
  # The remaining two bytes contain the port number.
  # Both address and port use network-byte order.

  peers_info = Bencode.decode response.body

  peers = []
  # 6 bytes for IP+Port
  # 4 bytes for IP
  # 2 bytes for Port in network order
  peers_len = 6
  peers_bytes = peers_info["peers"].bytes
  peers_num = peers_bytes.size / peers_len

  # https://ruby-doc.org/core-2.7.0/String.html#method-i-unpack
  # peers_info["peers"].unpack('C4 n')

  # ip = peers_info["peers"].byteslice(0, 4).unpack("C4").join(".")
  # port = peers_info["peers"].byteslice(4, 5).unpack1("n")

  peers_num.times do
    ip = peers_bytes.shift(4).join(".")

    # 2-byte (16-bit) number, which can range from 0 - 65535
    port = peers_bytes.shift * 256 + peers_bytes.shift

    peers << Peer.new(ip, port)
  end

  peers
end

def tcp_socket peer, tf
  ip = peer.ip
  port = peer.port
  local_host = nil
  local_port = nil
  timeout = 5
  sock = Socket.tcp(ip, port, local_host, local_port,
                    {connect_timeout: timeout})

  # The length of the protocol identifier, which is always 19 (0x13 in hex)
  # The protocol identifier, called the pstr which is always BitTorrent protocol
  # Eight reserved bytes, all set to 0. We’d flip some of them to 1 to indicate
  # that we support certain extensions. But we don’t, so we’ll keep them at 0.
  # The infohash that we calculated earlier to identify which file we want
  # The Peer ID that we made up to identify ourselves
  handshake = "#{PROTOCOL_IDENTIFIER}00000000#{tf.info_hash}#{PEER_ID}"

  ios_ready = IO.select([], [sock], [], timeout)
  if ios_ready.nil?
    raise "IO not ready"
  end

  # send handshake

  begin
    bytes_written = sock.write_nonblock(handshake)
    # puts "written #{bytes_written} bytes to sock"
  rescue IO::WaitWritable
    # Write would block (EWOULDBLOCK or we should try again (EINTR).
    # We could go try again here! Remember to check for a partial write.
    raise "Write failed"
  end

  # read returned handshake

  begin
    result = sock.read_nonblock(68) # 68 = length of the handshake
    # puts result.inspect
  rescue IO::WaitReadable
    IO.select([sock])
    retry
  end

  # validate the returned handshake

  raise "Wrong protocol identifier" unless result[0..19] == PROTOCOL_IDENTIFIER

  # puts "Extensions: #{result[20..27].inspect}" # 8 extension bytes
  # Not dealing with extensions for now
  # http://www.libtorrent.org/extension_protocol.html

  raise "Wrong info_hash returned" unless result[28..47] == tf.info_hash
  peer.id = result[48..67]
  puts "Peer ID: #{peer.id}"

  peer.socket = sock

  begin
    # we don't have anything downloaded yet, so can skip sending the bitfield

    # 4 bytes network order for length, 1 byte for id
    # N, C

    # only unchoke if we want to/once we can send blocks?
    # sock.write [1, 1].pack('NC')

    # send interested
    sock.write [1, 2].pack('NC')

    loop do
      # Length is a 32-bit integer, meaning it’s made out of four bytes
      # in big-endian order.
      length = sock.recv(4) # 4 bytes for length of message
      length = length.unpack1 "N"

      # 1 byte for message id
      # length += 1 # ???
      puts "Received length:\t#{length.inspect}"

      # keep alive
      if length == 0
        sock.write [0].pack("N")

        next
      end

      result = nil
      result = sock.recv(length)

      message = Message.new length, result
      puts message.inspect

      case message.id
      when 0
        peer.choking = true
      when 1
        peer.choking = false
        # XXX:
        return peer
      when 2
        peer.interested = true
      when 3
        peer.interested = false
      when 4
        peer.have_piece message.payload
      when 5
        peer.bitfield = message.payload
      when 6
        # TODO: handle request
      when 7
        # TODO: handle piece / block
      when 8
        # TODO: handle cancel
      end

      puts peer.inspect
      puts
    rescue EOFError
      break
    end
  rescue IO::WaitReadable
    IO.select([sock])
    retry
  end

  peer
rescue Errno::ETIMEDOUT, Errno::ECONNRESET, Errno::ECONNREFUSED,
  Errno::EADDRNOTAVAIL, EOFError
  puts "Connection to Peer failed"
rescue RangeError
  puts "Peer sent incorrect length"
end

def download_piece tf, peer
  piece = tf.request_piece peer.bitfield

  begin
    loop do
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

      download_block tf, peer, piece, block
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
def download_block tf, peer, piece, block
  payload = "#{piece.index}#{block.offset}#{[TorrentFile::REQUEST_LENGTH].pack("N*")}"
  request = "#{[1 + payload.bytesize].pack("N")}#{[6].pack("C")}#{payload}"

  peer.socket.write request

  puts "Requested Piece #{piece.index_10} block #{block.index}"

  loop do
    begin
      length = peer.socket.recv(4) # 4 bytes for length of message
      length = length.unpack1 "N"

      next unless length # nil

      # 1 byte for message id
      # length += 1 # ???
      puts "Received length:\t#{length.inspect}"

      # keep alive
      if length == 0
        peer.socket.write [0].pack("N")

        next
      end

      result = peer.socket.read_with_timeout(length, 8)

      message = Message.new length, result

      # puts message.inspect

      case message.name
      when 'piece'
        piece_idx = message.index
        block_idx = TorrentFile::Block.find_index(message.offset)

        tf.pieces[piece_idx].blocks[block_idx].receive(message.data)
        # puts block.inspect

        unless block.have
          block.invalidate!
        end

        return
      end
    rescue RuntimeError => e
      puts e.message
      block.invalidate!
      return
    end
  end
end
