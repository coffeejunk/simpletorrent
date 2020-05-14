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

  # piece TODO: refactor this
  attr_reader :index, :offset, :data

  def initialize length, payload
    @id = payload.bytes.first
    @name = TYPES[@id]
    puts "WARN: Invalid Message type #{@id}" unless @name

    @length = length

    return if %w{ choke unchoke interested not\ interested }.include?(@name)

    @payload = payload[1..-1]

    case @name
    when 'piece'
      # payload
      # 4-byte piece index
      # 4-byte block offset within
      # a variable length block containing the raw bytes for the requested piece

      @index, @offset = *@payload.unpack("NN")
      @data = @payload[8..-1]
    end

    # length == payload length + 1 for type
    actual = @payload.bytesize + 1
    unless !@payload || actual == @length
      raise "ERROR: Expected length #{@length} but actual is #{actual}. "# Invalid payload length #{inspect}"
    end
  end

  def parse data
  end

  # TODO:
  # def serialize
  # end
end
