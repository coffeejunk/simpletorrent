require "rest-client"
require "securerandom"

require "./torrent_file"

PROTOCOL_IDENTIFIER = "\x13BitTorrent protocol"
PEER_ID = "CJ-" + SecureRandom.urlsafe_base64(16).to_s[0...17]
PORT = 6881

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
  timeout = 3
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
    # sock.write [1, 2].pack('NC')
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

      result = sock.recv(length)
      # payload = result[1..-1] if result.size > 1

      # if length == 1 && payload != nil
      #   byebug
      # end

      # message_id = result.bytes.first

      # puts "Received message_id:\t#{message_id.inspect}"
      # puts "Received payload:\t#{payload.inspect}"

      message = Message.new result.bytes.first, length,
        (result.size > 1 ? result[1..-1] : nil)
      puts message.inspect

      case message.id
      when 0
        peer.choking = true
      when 1
        peer.choking = false
      when 2
        peer.interested = true
      when 3
        peer.interested = false
      when 4
        # TODO: handle have
      when 5
        peer.bitfield = message.payload
      when 6
        # TODO: handle request
      when 7
        # TODO: handle request
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
rescue Errno::ETIMEDOUT, Errno::ECONNRESET, Errno::ECONNREFUSED, EOFError
  puts "Connection to Peer failed"
rescue RangeError
  puts "Peer sent incorrect length"
end

class Message
  TYPES = %w[
    choke
    unchoke
    interested
    not\ interested
    have
    bitfield
    request
    piece
    cancel
  ]

  attr_reader :id, :length, :payload, :name

  def initialize id, length, payload
    @id = id
    @name = TYPES[@id]
    puts "WARN: Invalid Message type #{@id}" unless @name

    @length = length
    @payload = payload

    # length == payload length + 1 for type
    unless !@payload || @payload.size + 1 == @length
      raise "Invalid payload length #{inspect}"
    end
  end
end

class Peer
  attr_reader :ip, :port, :socket

  attr_accessor :socket, :bitfield, :id

  attr_accessor :chocked, :interested
  attr_accessor :choking, :interesting

  def initialize ip, port
    @ip = ip
    @port = port

    # Connections start out choked and not interested.
    @peer.chocked = true
    @peer.choking = true
    @peer.interested  = false
    @peer.interesting = false
  end
end

# f = File.open "debian-10.2.0-amd64-netinst.iso.torrent"
# tf = TorrentFile.new f
# peers = get_peers tf
# tcp_socket peers.sample, tf
