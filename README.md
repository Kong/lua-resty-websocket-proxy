# lua-resty-websocket-proxy

Reverse-proxying of websocket frames.

Resources:

- [FTI-1948](https://konghq.atlassian.net/browse/FTI-1948)
- [RFC-6455](https://datatracker.ietf.org/doc/html/rfc6455)
- [lua-resty-websocket](https://github.com/openresty/lua-resty-websocket)

# Table of Contents

- [Synopsis](#synopsis)
- [Limitations](#limitations)
- [TODO](#todo)
- [Kong Integration ADR](#kong-integration-adr)

# Synopsis

```
http {
    server {
        listen 9000;

        location / {
            content_by_lua_block {
                local ws_proxy = require "resty.websocket.proxy"

                local proxy, err = ws_proxy.new({
                    upstream = "ws://127.0.0.1:9001"
                })
                if not proxy then
                    ngx.log(ngx.ERR, "failed to create proxy: ", err)
                    return ngx.exit(444)
                end

                -- Start a bi-directional websocket proxy between
                -- this client and the upstream
                proxy:execute()
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

# Kong Integration ADR

> In the context of [FTI-1948](https://konghq.atlassian.net/browse/FTI-1948)

This section details a possible integration of lua-resty-websocket-proxy in Kong
Gateway so as for it to satisfy the following requirements:

1. Ability to create runtime plugins for web socket requests.
2. Ability to access WebSocket frames properties.
3. Ability to access aggregated frames.
4. Ability to support URL path and query\* for session stickiness.

**\*** see the note at the end of this section for a foreseen issue with URL
query string arguments and session stickiness.

The current code path for WebSocket connections from the client is to land in
the [ngx_http_upstream](http://lxr.nginx.org/source/xref/nginx/src/http/ngx_http_upstream.c?r=7833%3A3ab8e1e2f0f7#3455)
Nginx module, which performs a bi-directional, transparent forwarding of bytes.

The `proxy:execute()` method of this library has a similar functioning: it takes
over the processing of the client connection, while also expecting frames from
this client's intended peer (the "upstream" WebSocket service). All received
frames (bi-directionally) are decoded, recoded, and forwarded all in Lua-land,
the frames payload can thus be manipulated by Lua extension points.

[RFC-6455](https://datatracker.ietf.org/doc/html/rfc6455) specifies that
WebSocket connections be distinguished by their
[URIs](https://datatracker.ietf.org/doc/html/rfc6455#section-3), which are
composed of: `ws(s)-URI = "ws(s):" "//" host [ ":" port ] path [ "?" query ]`.
This echoes requirement 4.

Kong Gateway's client-facing entity is Routes, and the client's protocol is one
of the determining factor in selecting a matching Route (e.g. `http`, `https`,
`tcp`, `grpc`...). By way of lua-resty-websocket-proxy, Routes can be updated to
also support the `ws` or `wss` protocols. In conjunction with hostname and URI
matching, this should allow for all WebSocket connections to be established
individually according to their URIs, and as per the pertained specification,
all within the framework of a core Gateway entity.

Thus, any client connection that matches a Route with a `ws` or `wss` protocol
then establishes a WebSocket proxy as per this library's [Synopsis](#synopsis).
The WebSocket upstream is the Route's associated Service. The WebSocket proxy
instance is given a function by Kong as a callback to invoke on each WebSocket
frame (or aggregated frame), and in this callback, Kong invokes its plugin
runloop onto a new `websocket_frame_by_lua` virtual phase. This will be the only
phase invoked by this connection for the remainder of its lifetime, until the
connection closes which will invoke `log_by_lua`. Implementers and plugin
authors should be cautious of long-lived memory allocations in the context of
WebSocket connections.

The following work items have so far been identified in this proposal:

1. Update of the Route entity to support `protocols=ws,wss`.
2. Update the Service entity to support `protocol=ws,wss`.
3. Plugins with `websocket_frame_by_lua`:
    - a. Update plugins so as to support a new handler in their interface:
         `:on_websocket_frame(opcode, payload, ...)`.
    - b. Update lua-resty-websocket-proxy to support a frame callback.
    - c. Such a callback is implemented in Kong so that when invoked, in turn
         invokes the plugins runloop with `websocket_frame_by_lua` being the
         current phase, which calls the `on_websocket_frame` handler.
    - d. Update core so that when a WebSocket client connects, the balancer
         phase is ran to select an upstream and the WebSocket proxy is started
         with the callback (`proxy:execute()`).
4. Update the PDK to support frame properties retrieval from within
   `websocket_frame_by_lua`. The frame properties will be passed to the on-frame
   callback, which must use the core/private PDK to set these values somewhere
   the public PDK can retrieve them from (e.g. `ngx.ctx`).

**Note:** As of presently (October 2021), Kong's Router does not support query
string arguments matching. Since this proposal relies on the Router matching
a WebSocket-defined Route to run this Route's plugin, it would not be possible
to execute a WebSocket plugin based on a query string argument without
additional efforts.
We must clarify if requirements 4. from the customer means an expectation to
to configure WebSocket frame inspection plugins based on a WebSocket's query
string argument (e.g.  `?arg=1`). If so, this translates to an expectation of
Kong being able to execute plugins based on query string arguments, which is
currently not possible. If the expectation on query string arguments is only to
distinguish clients (but running the same plugins on all proxied WebSocket
connections), then this can be negotiated within the Gateway's core as part of
work item 3.c.

[Back to TOC](#table-of-contents)
