# A very incomplete bittorrent implementation in ruby.

`ruby run.rb` will download `debian-10.3.0-amd64-netinst.iso.torrent`

This is _very, very_ work in progress.

TODO:

- Check state (choked / unchoked) before writing to the socket
- make `pieces.request_piece` thread safe
- add threads
- pipelining of block requests

- Use https://github.com/peterc/bitarray for the bitarray instead of string
