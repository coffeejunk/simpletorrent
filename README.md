A very incomplete bittorrent implementation in ruby.

TODO:

- Check state (choked / unchoked) before writing to the socket
- make `pieces.request_piece` thread safe
- add threads
- pipelining of block requests

- Use https://github.com/peterc/bitarray for the bitarray instead of string
