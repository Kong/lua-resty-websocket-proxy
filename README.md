## lua-resty-websocket-proxy

Reverse-proxying of websocket frames.

### TODO

- [ ] Fragmented messages support

### Limitations

* Built with [lua-resty-websocket](https://github.com/openresty/lua-resty-websocket) which
  only supports `Sec-Websocket-Version: 13` (no extensions) and denotes its
  client component a
  [work-in-progress](https://github.com/openresty/lua-resty-websocket/blob/master/lib/resty/websocket/client.lua#L4-L5).
