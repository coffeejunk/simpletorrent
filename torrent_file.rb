require "digest/sha1"
require "./bencode"

class TorrentFile
  attr_reader :announce, :info_hash, :piece_hash, :piece_length, :length, :name
  # attr_reader :bencoded

  def initialize f
    bencoded = Bencode.decode f
    @announce = bencoded["announce"]
    @piece_length = bencoded["info"]["piece length"]
    @length = bencoded["info"]["length"]
    @name = bencoded["info"]["name"]

    @info_hash = calculate_info_hash f
    @piece_hash = split_pieces bencoded["info"]["pieces"]
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
end
