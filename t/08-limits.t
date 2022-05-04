# vim:set ts=4 sts=4 sw=4 et ft=:

use lib '.';
use t::Tests;

plan tests => repeat_each() * (blocks() * 4);

run_tests();

__DATA__

=== TEST 1: limiting individual frame size (client)
--- http_config eval: $t::Tests::HttpConfig
--- config
    location /proxy {
        content_by_lua_block {
            local proxy = require "resty.websocket.proxy"

            local wp, err = proxy.new({ client_max_frame_size = 10 })
            if not wp then
                ngx.log(ngx.ERR, "failed creating proxy: ", err)
                return ngx.exit(444)
            end

            local ok, err = wp:connect(proxy._tests.echo .. "?repeat=1")
            if not ok then
                ngx.log(ngx.ERR, err)
                return ngx.exit(444)
            end

            local done, err = wp:execute()
            if not done then
                ngx.log(ngx.ERR, "failed proxying: ", err)
                return ngx.exit(444)
            end
        }
    }

    location /t {
        content_by_lua_block {
            local client = require "resty.websocket.client"
            local wb = assert(client:new())
            local uri = "ws://127.0.0.1:" .. ngx.var.server_port .. "/proxy"

            assert(wb:connect(uri))
            assert(wb:send_text("this is way too long"))
            local data, typ, err = wb:recv_frame()
            ngx.say(string.format("data: %q, typ: %s, err: %s", data, typ, err))
        }
    }
--- response_body
data: "Payload Too Large", typ: close, err: 1009
--- grep_error_log eval: qr/\[lua\].*/
--- grep_error_log_out eval
qr/frame type: close, payload: ""/
--- no_error_log
[error]



=== TEST 2: limiting individual frame size (upstream)
--- http_config eval: $t::Tests::HttpConfig
--- config
    location /proxy {
        content_by_lua_block {
            local proxy = require "resty.websocket.proxy"

            local wp, err = proxy.new({ upstream_max_frame_size = 10 })
            if not wp then
                ngx.log(ngx.ERR, "failed creating proxy: ", err)
                return ngx.exit(444)
            end

            local uri = "ws://127.0.0.1:" .. ngx.var.server_port .. "/upstream"
            local ok, err = wp:connect(uri)
            if not ok then
                ngx.log(ngx.ERR, err)
                return ngx.exit(444)
            end

            local done, err = wp:execute()
            if not done then
                ngx.log(ngx.ERR, "failed proxying: ", err)
                return ngx.exit(444)
            end
        }
    }

    location /upstream {
        content_by_lua_block {
            local server = require "resty.websocket.server"

            local wb, err = server:new()
            if not wb then
                ngx.log(ngx.ERR, "failed creating server: ", err)
                return ngx.exit(444)
            end

            local bytes, err = wb:send_text("this is way too long")
            if not bytes then
                ngx.log(ngx.ERR, "failed sending frame: ", err)
                return ngx.exit(444)
            end

            local data, typ, err = wb:recv_frame()
            if not data then
                ngx.log(ngx.ERR, "failed receiving frame: ", err)
                return ngx.exit(444)
            end

            ngx.log(ngx.INFO, "frame type: ", typ, ", payload: \"", data, "\"")
        }
    }

    location /t {
        content_by_lua_block {
            local client = require "resty.websocket.client"
            local wb = assert(client:new())
            local uri = "ws://127.0.0.1:" .. ngx.var.server_port .. "/proxy"

            assert(wb:connect(uri))
            assert(wb:send_text("hello"))
            local data, typ, err = wb:recv_frame()
            ngx.say(string.format("data: %q, typ: %s, err: %s", data, typ, err))
        }
    }
--- response_body
data: "", typ: close, err: 1001
--- grep_error_log eval: qr/\[lua\].*/
--- grep_error_log_out eval
qr/frame type: close, payload: "Payload Too Large"/
--- no_error_log
[error]



=== TEST 3: limiting aggregated frame size (client)
--- http_config eval: $t::Tests::HttpConfig
--- config
    location /proxy {
        content_by_lua_block {
            local proxy = require "resty.websocket.proxy"

            local wp, err = proxy.new({
                client_max_frame_size = 10,
                aggregate_fragments = true,
            })
            if not wp then
                ngx.log(ngx.ERR, "failed creating proxy: ", err)
                return ngx.exit(444)
            end

            local ok, err = wp:connect(proxy._tests.pong .. "?repeat=1")
            if not ok then
                ngx.log(ngx.ERR, err)
                return ngx.exit(444)
            end

            local done, err = wp:execute()
            if not done then
                ngx.log(ngx.ERR, "failed proxying: ", err)
                return ngx.exit(444)
            end
        }
    }

    location /t {
        content_by_lua_block {
            local client = require "resty.websocket.client"
            local wb = assert(client:new())
            local uri = "ws://127.0.0.1:" .. ngx.var.server_port .. "/proxy"

            assert(wb:connect(uri))

            local fmt = string.format

            local function ping_pong(i)
                local bytes, err = wb:send_ping(i)
                if not bytes then
                    return nil, fmt("send failed: %s", err)
                end

                local data, typ, err = wb:recv_frame()
                if not data then
                    return nil, fmt("recv failed: %s", err)
                elseif typ ~= "pong" then
                    return nil, fmt("unexpected frame %s => %q", typ, data)
                end

                return true
            end

            for i = 1, 5 do
                local opcode = (i == 1 and 0x1) or 0x0
                local bytes, err = wb:send_frame(false, opcode, "11")
                if not bytes then
                    ngx.log(ngx.ERR, "failed sending fragment ", i, ": ", err)
                    return ngx.exit(500)
                end

                local ok, err = ping_pong(i)
                if not ok then
                    ngx.log(ngx.ERR, "failed ping-pong: ", err)
                    return ngx.exit(500)
                end
            end

            local bytes, err = wb:send_frame(false, 0x0, "1")
            if not bytes then
                ngx.log(ngx.ERR, "failed sending final fragment: ", err)
                return ngx.exit(500)
            end

            local data, typ, err = wb:recv_frame()
            ngx.say(string.format("data: %q, typ: %s, err: %s", data, typ, err))
        }
    }
--- response_body
data: "Payload Too Large", typ: close, err: 1009
--- grep_error_log eval: qr/\[lua\].*/
--- grep_error_log_out eval
qr/frame type: close, payload: ""/
--- no_error_log
[error]



=== TEST 4: limiting aggregated frame size (upstream)
--- http_config eval: $t::Tests::HttpConfig
--- config
    location /proxy {
        content_by_lua_block {
            local proxy = require "resty.websocket.proxy"

            local wp, err = proxy.new({
                aggregate_fragments = true,
                upstream_max_frame_size = 10
            })
            if not wp then
                ngx.log(ngx.ERR, "failed creating proxy: ", err)
                return ngx.exit(444)
            end

            local uri = "ws://127.0.0.1:" .. ngx.var.server_port .. "/upstream"
            local ok, err = wp:connect(uri)
            if not ok then
                ngx.log(ngx.ERR, err)
                return ngx.exit(444)
            end

            local done, err = wp:execute()
            if not done then
                ngx.log(ngx.ERR, "failed proxying: ", err)
                return ngx.exit(444)
            end
        }
    }

    location /upstream {
        content_by_lua_block {
            local server = require "resty.websocket.server"

            local wb, err = server:new()
            if not wb then
                ngx.log(ngx.ERR, "failed creating server: ", err)
                return ngx.exit(444)
            end

            for i = 1, 5 do
                local opcode = (i == 1 and 0x1) or 0x0
                local bytes, err = wb:send_frame(false, opcode, "11")
                if not bytes then
                    ngx.log(ngx.ERR, "failed sending fragment ", i, ": ", err)
                    return ngx.exit(444)
                end
            end

            local bytes, err = wb:send_frame(false, 0x0, "1")
            if not bytes then
                ngx.log(ngx.ERR, "failed sending final fragment: ", err)
                return ngx.exit(444)
            end

            local data, typ, err = wb:recv_frame()
            ngx.log(ngx.INFO, "frame type: ", typ, ", payload: \"", data, "\", code: ", err)
        }
    }

    location /t {
        content_by_lua_block {
            local client = require "resty.websocket.client"
            local wb = assert(client:new())
            local uri = "ws://127.0.0.1:" .. ngx.var.server_port .. "/proxy"

            assert(wb:connect(uri))
            repeat
                local data, typ, err = wb:recv_frame()
                ngx.say(string.format("data: %q, typ: %s, err: %s",
                                      data, typ, err))
            until typ == "close" or not data
        }
    }
--- response_body
data: "", typ: close, err: 1001
--- grep_error_log eval: qr/\[lua\].*/
--- grep_error_log_out eval
qr/frame type: close, payload: "Payload Too Large", code: 1009/
--- no_error_log
[error]



=== TEST 5: control frames are not subject to max_frame_size
--- http_config eval: $t::Tests::HttpConfig
--- config
    location /proxy {
        content_by_lua_block {
            local proxy = require "resty.websocket.proxy"

            local wp, err = proxy.new({
                    client_max_frame_size = 2,
                    upstream_max_frame_size = 2,
            })
            if not wp then
                ngx.log(ngx.ERR, "failed creating proxy: ", err)
                return ngx.exit(444)
            end

            local ok, err = wp:connect(proxy._tests.pong .. "?repeat=1")
            if not ok then
                ngx.log(ngx.ERR, err)
                return ngx.exit(444)
            end

            local done, err = wp:execute()
            if not done then
                ngx.log(ngx.ERR, "failed proxying: ", err)
                return ngx.exit(444)
            end
        }
    }

    location /t {
        content_by_lua_block {
            local client = require "resty.websocket.client"
            local wb = assert(client:new())
            local uri = "ws://127.0.0.1:" .. ngx.var.server_port .. "/proxy"

            assert(wb:connect(uri))

            for i = 1, 2 do
                local sent, err = wb:send_ping("test-" .. i)
                if not sent then
                    ngx.log(ngx.ERR, "failed sending ping: ", err)
                    return ngx.exit(500)
                end

                local data, typ, err = wb:recv_frame()
                if not data then
                    ngx.log(ngx.ERR, "failed to receive pong: ", err)
                    return ngx.exit(500)

                elseif typ ~= "pong" then
                    ngx.log(ngx.ERR, "unexpecting response to ping: ", typ)
                    return ngx.exit(500)

                elseif #data <= 2 then
                    ngx.log(ngx.ERR, "broken test--pong frame is too short")
                    return ngx.exit(500)
                end

                ngx.say(string.format("data: %q, typ: %s", data, typ))
            end

            assert(wb:send_close(1002, "goodbye"))
        }
    }
--- response_body
data: "heartbeat server", typ: pong
data: "heartbeat server", typ: pong
--- grep_error_log eval: qr/\[lua\].*/
--- grep_error_log_out eval
qr/.*?frame type: ping, payload: "test-1".*
.*?frame type: ping, payload: "test-2".*
.*?forwarding close with code: 1002.*
.*?frame type: close, payload: "goodbye".*/
--- no_error_log
[error]



=== TEST 6: limiting the number of fragments (client)
--- http_config eval: $t::Tests::HttpConfig
--- config
    location /proxy {
        content_by_lua_block {
            local proxy = require "resty.websocket.proxy"

            local wp, err = proxy.new({
                client_max_fragments = 5,
                aggregate_fragments = true,
                debug = true,
            })
            if not wp then
                ngx.log(ngx.ERR, "failed creating proxy: ", err)
                return ngx.exit(444)
            end

            local ok, err = wp:connect(proxy._tests.pong .. "?repeat=1")
            if not ok then
                ngx.log(ngx.ERR, err)
                return ngx.exit(444)
            end

            local done, err = wp:execute()
            if not done then
                ngx.log(ngx.ERR, "failed proxying: ", err)
                return ngx.exit(444)
            end
        }
    }

    location /t {
        content_by_lua_block {
            local client = require "resty.websocket.client"
            local wb = assert(client:new())
            local uri = "ws://127.0.0.1:" .. ngx.var.server_port .. "/proxy"

            assert(wb:connect(uri))

            local fmt = string.format

            local function ping_pong(i)
                local bytes, err = wb:send_ping(i)
                if not bytes then
                    return nil, fmt("send failed: %s", err)
                end

                local data, typ, err = wb:recv_frame()
                if not data then
                    return nil, fmt("recv failed: %s", err)
                elseif typ ~= "pong" then
                    return nil, fmt("unexpected frame %s => %q", typ, data)
                end

                return true
            end

            for i = 1, 5 do
                local opcode = (i == 1 and 0x1) or 0x0
                local bytes, err = wb:send_frame(false, opcode, "11")
                if not bytes then
                    ngx.log(ngx.ERR, "failed sending fragment ", i, ": ", err)
                    return ngx.exit(500)
                end

                local ok, err = ping_pong(i)
                if not ok then
                    ngx.log(ngx.ERR, "failed ping-pong: ", err)
                    return ngx.exit(500)
                end
            end

            local bytes, err = wb:send_frame(false, 0x0, "1")
            if not bytes then
                ngx.log(ngx.ERR, "failed sending final fragment: ", err)
                return ngx.exit(500)
            end

            local data, typ, err = wb:recv_frame()
            ngx.say(string.format("data: %q, typ: %s, err: %s", data, typ, err))
        }
    }
--- response_body
data: "Payload Too Large", typ: close, err: 1009
--- grep_error_log eval: qr/\[lua\].*/
--- grep_error_log_out eval
qr/frame type: close, payload: ""/
--- no_error_log
[error]



=== TEST 7: limiting the number of fragments (upstream)
--- http_config eval: $t::Tests::HttpConfig
--- config
    location /proxy {
        content_by_lua_block {
            local proxy = require "resty.websocket.proxy"

            local wp, err = proxy.new({
                aggregate_fragments = true,
                upstream_max_fragments = 5,
            })
            if not wp then
                ngx.log(ngx.ERR, "failed creating proxy: ", err)
                return ngx.exit(444)
            end

            local uri = "ws://127.0.0.1:" .. ngx.var.server_port .. "/upstream"
            local ok, err = wp:connect(uri)
            if not ok then
                ngx.log(ngx.ERR, err)
                return ngx.exit(444)
            end

            local done, err = wp:execute()
            if not done then
                ngx.log(ngx.ERR, "failed proxying: ", err)
                return ngx.exit(444)
            end
        }
    }

    location /upstream {
        content_by_lua_block {
            local server = require "resty.websocket.server"

            local wb, err = server:new()
            if not wb then
                ngx.log(ngx.ERR, "failed creating server: ", err)
                return ngx.exit(444)
            end

            for i = 1, 5 do
                local opcode = (i == 1 and 0x1) or 0x0
                local bytes, err = wb:send_frame(false, opcode, "11")
                if not bytes then
                    ngx.log(ngx.ERR, "failed sending fragment ", i, ": ", err)
                    return ngx.exit(444)
                end
            end

            local bytes, err = wb:send_frame(false, 0x0, "1")
            if not bytes then
                ngx.log(ngx.ERR, "failed sending final fragment: ", err)
                return ngx.exit(444)
            end

            local data, typ, err = wb:recv_frame()
            ngx.log(ngx.INFO, "frame type: ", typ, ", payload: \"", data, "\", code: ", err)
        }
    }

    location /t {
        content_by_lua_block {
            local client = require "resty.websocket.client"
            local wb = assert(client:new())
            local uri = "ws://127.0.0.1:" .. ngx.var.server_port .. "/proxy"

            assert(wb:connect(uri))
            repeat
                local data, typ, err = wb:recv_frame()
                ngx.say(string.format("data: %q, typ: %s, err: %s",
                                      data, typ, err))
            until typ == "close" or not data
        }
    }
--- response_body
data: "", typ: close, err: 1001
--- grep_error_log eval: qr/\[lua\].*/
--- grep_error_log_out eval
qr/frame type: close, payload: "Payload Too Large", code: 1009/
--- no_error_log
[error]