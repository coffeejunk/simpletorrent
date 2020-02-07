require 'strscan'

class Bencode
  def Bencode.decode_scaner s
    case control = s.getch
    when "i"
      # Integers go between start and end markers, so 7 would encode to i7e.
      num = s.scan(/-?\d+/).to_i
      s.skip "e"
      num
    when /\d+/
      # Strings come with a length prefix, and look like 4:spam.
      chars = control.to_i
      s.skip ":"
      str = s.scan /.{#{chars}}/
    when "l"
      # Lists: l4:spami7ee represents ['spam', 7],
      ary = []

      while s.peek(1) != "e" do
        ary << decode_scaner(s)
      end

      ary
    when "d"
      # Hash/Dict: d4:spami7ee means {spam: 7}.
      hsh = {}

      while s.peek(1) != "e" do
        key = decode_scaner(s)
        value = decode_scaner(s)
        hsh[key] = value
      end

      hsh
    end
  end

  def Bencode.decode string
    decode_scaner(StringScanner.new(string))
  end
end
