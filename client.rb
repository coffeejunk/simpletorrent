require "rest-client"
require "securerandom"
require "digest/sha1"

require "./basic_socket"
require "./message"
require "./peer"
require "./torrent_file"

# Useful links
# - https://www.bittorrent.org/beps/bep_0003.html
# - https://blog.jse.li/posts/torrent/
# - https://wiki.theory.org/index.php/BitTorrentSpecification

class Client
  PROTOCOL_IDENTIFIER = "\x13BitTorrent protocol"
  PEER_ID = "CJ-" + SecureRandom.urlsafe_base64(16).to_s[0...17]
  PORT = 6881

  attr_reader :torrent_file, :available_peers, :connected_peers

  # expects torrent_file to be an IO object
  def initialize torrent_file
    @torrent_file = TorrentFile.new torrent_file
    @connected_peers = []
    @available_peers = []
  end

  # announces us to the tracker and retireves peers
  # returns the number of available_peers
  def announce_to_tracker
    response = RestClient.get(torrent_file.announce, params: {
      info_hash: torrent_file.info_hash,
      port: PORT,
      peer_id: PEER_ID,
      download: 0, # TODO: update this as we upload / download ?
      uploaded: 0,
      left: torrent_file.length,
      compact: 1, # see comment below
    })

    # re/ compact:
    # https://www.bittorrent.org/beps/bep_0023.html
    # It is common now to use a compact format where each peer is represented
    # using only 6 bytes. The first 4 bytes contain the 32-bit ipv4 address.
    # The remaining two bytes contain the port number.
    # Both address and port use network-byte order.

    peers_info = Bencode.decode response.body

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

      @available_peers << Peer.new(ip, port, torrent_file)
    end

    @available_peers.size
  end

  def connect_to_peer peer=nil
    raise "No peers available" if @available_peers.empty?

    peer ||= @available_peers.shift
    if peer.connect
      @connected_peers << peer
    else
      return
    end

    peer
  end

  private

end
