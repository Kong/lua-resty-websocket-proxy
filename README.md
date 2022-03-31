# lua-resty-websocket-proxy

Reverse-proxying of websocket frames.

Resources:

- [RFC-6455](https://datatracker.ietf.org/doc/html/rfc6455)
- [lua-resty-websocket](https://github.com/openresty/lua-resty-websocket)

# Table of Contents

- [Synopsis](#synopsis)
- [Limitations](#limitations)
- [TODO](#todo)

# Synopsis

```lua
http {
    server {
        listen 9000;

        location / {
            content_by_lua_block {
                local ws_proxy = require "resty.websocket.proxy"

                local proxy, err = ws_proxy.new({
                    upstream = "ws://127.0.0.1:9001"
                    aggregate_fragments = true,
                    on_frame = function(origin, typ, payload, last)
                        --  origin: [string]     "client" or "upstream"
                        --     typ: [string]     "text", "binary", "ping", "pong", "close"
                        -- payload: [string|nil] payload if any
                        --    last: [boolean]    (always true if aggregate_fragments is on)

                        if update_payload then
                            return "new payload"
                        end

                        -- void: proxy payload as-is
                    end
                })
                if not proxy then
                    ngx.log(ngx.ERR, "failed to create proxy: ", err)
                    return ngx.exit(444)
                end

                -- Start a bi-directional websocket proxy between
                -- this client and the upstream
                local done, err = wb:execute()
                if not done then
                    ngx.log(ngx.ERR, "failed proxying: ", err)
                    return ngx.exit(444)
                end
            }
        }
    }
}
```

[Back to TOC](#table-of-contents)

# Limitations

* Built with [lua-resty-websocket](https://github.com/openresty/lua-resty-websocket)
  which only supports `Sec-Websocket-Version: 13` (no extensions) and denotes
  its client component a
  [work-in-progress](https://github.com/openresty/lua-resty-websocket/blob/master/lib/resty/websocket/client.lua#L4-L5).

[Back to TOC](#table-of-contents)

# TODO

- [ ] Limits on fragmented messages buffering (number of frames/payload size)
- [ ] Performance/latency analysis
- [ ] Peer review

[Back to TOC](#table-of-contents)
