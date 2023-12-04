# lua-resty-websocket-proxy

Reverse-proxying of websocket frames with in-flight inspection/update/drop and
frame aggregation support.

Resources:

- [RFC-6455](https://datatracker.ietf.org/doc/html/rfc6455)
- [lua-resty-websocket](https://github.com/openresty/lua-resty-websocket)

# Table of Contents

- [Status](#status)
- [Synopsis](#synopsis)
- [Limitations](#limitations)
- [TODO](#todo)
- [License](#license)

# Status

This library is usable although still under active development.

The Lua API may change without notice.

[Back to TOC](#table-of-contents)

# Synopsis

```lua
http {
    server {
        listen 9000;

        location / {
            content_by_lua_block {
                local ws_proxy = require "resty.websocket.proxy"

                local proxy, err = ws_proxy.new({
                    aggregate_fragments = true,
                    on_frame = function(proxy, role, typ, payload, last, code)
                        --   proxy: [table]       the proxy instance
                        --    role: [string]      "client" or "upstream"
                        --     typ: [string]      "text", "binary", "ping", "pong", "close"
                        -- payload: [string|nil]  payload if any
                        --    last: [boolean]     fin flag for fragmented frames; true if aggregate_fragments is on
                        --    code: [number|nil]  code for "close" frames

                        if update_payload then
                            -- change payload + code before forwarding
                            return "new payload", 1001
                        end

                        -- forward as-is
                        return payload
                    end
                })
                if not proxy then
                    ngx.log(ngx.ERR, "failed to create proxy: ", err)
                    return ngx.exit(444)
                end

                local ok, err = proxy:connect("ws://127.0.0.1:9001")
                if not ok then
                    ngx.log(ngx.ERR, err)
                    return ngx.exit(444)
                end

                -- Start a bi-directional websocket proxy between
                -- this client and the upstream
                local done, err = proxy:execute()
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

# License

Copyright 2022 Kong Inc.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

   http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

[Back to TOC](#table-of-contents)
