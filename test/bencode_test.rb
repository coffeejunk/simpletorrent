# this was taken from https://github.com/dasch/ruby-bencode
require 'minitest/autorun'
require 'shoulda'

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
  it_should_decode -42, "i-42e"

  it_should_decode "foo", "3:foo"
  it_should_decode "", "0:"

  it_should_decode [1, 2, 3], "li1ei2ei3ee"

  hsh = {"foo" => "bar", "baz" => "qux"}
  it_should_decode hsh, "d3:foo3:bar3:baz3:quxe"

  # it_should_decode 42, "i42eBOGUS", :ignore_trailing_junk => true

  # for now stick to ASCII
  # it_should_decode "café", "5:café"
  # it_should_decode ["你好", "中文"], "l6:你好6:中文e"
end
