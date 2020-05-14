load 'client.rb'
f = File.open "debian-10.3.0-amd64-netinst.iso.torrent"

client = Client.new f
client.announce_to_tracker

POOL_SIZE = 25

jobs = Queue.new
client.torrent_file.pieces.each { |piece| jobs.push piece }

workers = (POOL_SIZE).times.map do
  Thread.new do
    begin
      peer = nil
      while !peer do
        begin
          peer = client.connect_to_peer

          next unless peer

          peer.send_interested
        rescue RuntimeError => e
          puts e
          puts
        end
      end

      # pop piece from the queue
      while piece = jobs.pop(true)
        # check if peer has the piece
        # YES
        #   -> request piece
        # NO
        #   -> push piece back onto queue
        if peer.has_piece? piece
          peer.download_piece piece
        else
          jobs.push piece
        end
      end
    rescue ThreadError
    end
  end
end

workers.map(&:join)

require 'byebug'; byebug
client.torrent_file.write_file


