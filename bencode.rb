require "stringio"

class Bencode
  def self.decode string
    if string.is_a? IO
      load(string)
    else
      load(StringIO.new(string))
    end
  end

  def self.load s
    case peek(s)
    when "i"
      decode_int s
    when "0".."9"
      Bencode.decode_string s
    when "l"
      Bencode.decode_array s
    when "d"
      Bencode.decode_dict s
    end
  end

  # Integers go between start and end markers, so 7 would encode to i7e.
  def self.decode_int s
    s.getc

    s.gets("e").chop.to_i
  end

  # Strings come with a length prefix, and look like 4:spam.
  def self.decode_string s
    # get length of string
    num = s.gets(":").chop.to_i

    # get actual string
    s.read(num.to_i).force_encoding Encoding.default_external
  end

  # Lists: l4:spami7ee represents ['spam', 7],
  def self.decode_array s
    s.getc
    ary = []

    while peek(s) != "e"
      ary << load(s)
    end

    s.getc

    ary
  end

  # Hash/Dict: d4:spami7ee means {spam: 7}.
  def self.decode_dict s
    s.getc
    hsh = {}

    while peek(s) != "e"
      (key = load(s)) || raise("DecodeError: No key for dict")
      value = load(s)
      hsh[key] = value
    end

    hsh
  end

  def self.peek s
    c = s.getc
    s.ungetc c
    c
  end
end
