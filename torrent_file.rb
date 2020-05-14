require "digest/sha1"
require "./bencode"

class TorrentFile
  REQUEST_LENGTH = 16384 # 2 ^ 14

  attr_reader :announce, :info_hash, :pieces_hashes, :piece_length, :length,
    :name, :pieces

  def initialize f
    bencoded = Bencode.decode f
    @announce = bencoded["announce"]
    @piece_length = bencoded["info"]["piece length"]
    @length = bencoded["info"]["length"]
    @name = bencoded["info"]["name"]

    @info_hash = calculate_info_hash f
    @pieces_hashes = split_pieces bencoded["info"]["pieces"]

    @pieces = []
    @pieces_hashes.each_with_index do |piece_hash, idx|
      @pieces << Piece.new(idx, @piece_length, piece_hash)
    end
  end

  def downloaded?
    @pieces.map(&:have).all? { |p| p == true }
  end

  def have_bitfield
    bf = ""
    @pieces.each do |piece|
      bf << (piece.have ? "1": "0")
    end
    bf
  end

  def req_have_bitfield
    bf = ""
    @pieces.each do |piece|
      bf << (piece.have || piece.requested ? "1": "0")
    end
    bf
  end

  def request_piece peer_bitfield
    # the incoming bitfield might be padded with 0s at the end
    local_bitfield = req_have_bitfield
    a = peer_bitfield.unpack1('B*').length
    b = local_bitfield.length
    overhead = a - b || 0
    local_bitfield << '0' * overhead

    # if have_bitfield[0] == "1"
    #   require 'byebug'; byebug
    # end

    available = (
      # peer's bitfield                  AND NOT local bitfield
      peer_bitfield.unpack1('B*').to_i(2) & ~local_bitfield.to_i(2)
    ).to_s(2)

    # we need to pad with leading 0s for pieces that we already have
    a = peer_bitfield.unpack1('B*').length
    b = available.length
    overhead = a - b || 0
    available.prepend('0' * overhead)

    # XXX: find_index returns the first
    # p_idx = (0 ... available.length).find_all { |i| available[i,1] == '1' }.sample
    p_idx = available.split('').find_index('1')

    # @pieces.select { |p| !p.have }.sample
    piece = @pieces[p_idx]
    piece.requested = true
    piece
  end

  def address
    [index].pack('N*')
  end

  def write_file
    File.write(name, pieces.map(&:data).join(""))
  end

  private

  def calculate_info_hash f
    f.rewind
    f.gets "info"
    Digest::SHA1.digest f.read[0..-2]
  end

  def split_pieces pieces
    pieces.bytes.each_slice(20).to_a.map { |bs| bs.pack("c*") }
  end

  class Piece
    attr_reader :piece_hash, :have, :blocks
    attr_accessor :requested

    def initialize idx, length, hsh
      @index = idx
      @piece_hash = hsh
      @have = false

      blocks_per_piece = length / TorrentFile::REQUEST_LENGTH
      @blocks = []
      blocks_per_piece.times do |idx|
        @blocks << Block.new(idx)
      end
    end

    def index
      [@index].pack("N*")
    end

    def index_10
      @index
    end

    def validate!
      if downloaded?
        valid = Digest::SHA1.digest(data) == piece_hash
        if valid
          @have = true
          return true
        end

        invalidate!
      end
    end

    def invalidate!
      blocks.map(&:invalidate!)
    end

    def downloaded?
      blocks.map(&:have).all? { |b| b == true }
    end

    def data
      blocks.map(&:data).join("")
    end

    def missing_blocks
      blocks.select { |b| b.requested == false }
    end

    def corrupt_blocks
      blocks.select { |b| b.requested && !b.have }
    end

    def invalidate_corrupt_blocks
      corrupt_blocks.map(&:invalidate!)
    end

    def request_block
      block = missing_blocks.first
      return unless block
      block.request!
      block
    end
  end

  class Block
    attr_reader :index, :requested, :have, :data

    def initialize idx
      @index = idx
      @requested = false
      @have = false
      @data = ""
    end

    def offset
      [TorrentFile::REQUEST_LENGTH * index].pack("N*")
    end

    def self.find_index offset
       offset / TorrentFile::REQUEST_LENGTH
    end

    def receive data
      @data = data
      @have = true
    end

    def invalidate!
      @data = ""
      @have = false
      @requested = false
    end

    def request!
      @requested = true
    end
  end
end
