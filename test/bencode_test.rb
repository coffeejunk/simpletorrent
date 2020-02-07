# this was taken from https://github.com/dasch/ruby-bencode
require "minitest/autorun"
require "shoulda"

require_relative "../bencode"

class MiniTest::Test
  def self.it_should_decode(expected, encoded, opts = {})
    it "should decode #{encoded.inspect} into #{expected.inspect}" do
      assert_equal expected, Bencode.decode(encoded)
    end
  end
end

describe "decoding" do
  it_should_decode 42, "i42e"
  it_should_decode 0, "i0e"
  it_should_decode(-42, "i-42e")

  it_should_decode "foo", "3:foo"
  it_should_decode "", "0:"

  it_should_decode [1, 2, 3], "li1ei2ei3ee"

  it_should_decode ["array", ["one", "two", "three"]],
    "l5:arrayl3:one3:two5:threeee"

  hsh = {"foo" => "bar", "baz" => "qux"}
  it_should_decode hsh, "d3:foo3:bar3:baz3:quxe"

  hsh_2 = {"array" => ["one", "two", "three"], "integer" => 42, "string" => "bar"}
  it_should_decode hsh_2, "d5:arrayl3:one3:two5:threee7:integeri42e6:string3:bare"

  # # it_should_decode 42, "i42eBOGUS", :ignore_trailing_junk => true

  it_should_decode "café", "5:café"
  it_should_decode ["你好", "中文"], "l6:你好6:中文e"
end

describe "bittorrent" do
  it "should load a bencoded torrent file" do
    Bencode.decode(File.open("debian-10.2.0-amd64-netinst.iso.torrent"))
    pass
  end
end
