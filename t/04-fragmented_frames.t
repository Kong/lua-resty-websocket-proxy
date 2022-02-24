# vim:set ts=4 sts=4 sw=4 et ft=:

use lib '.';
use t::Tests;

plan tests => repeat_each() * (blocks() * 4);

run_tests();

__DATA__

=== TEST 1: forwards fragmented frames by default
--- http_config eval: $::HttpConfig
--- config
    location /upstream {
        content_by_lua_block {
            local server = require "resty.websocket.server"

            local wb, err = server:new()
            if not wb then
                ngx.log(ngx.ERR, "failed creating server: ", err)
                return ngx.exit(444)
            end

            for i = 1, 2 do
                local data, typ, err = wb:recv_frame()
                if not data then
                    ngx.log(ngx.ERR, "failed receiving frame: ", err)
                    return ngx.exit(444)
                end

                ngx.log(ngx.INFO, "frame type: ", typ, ", payload: \"", data, "\"")

                local bytes, err = wb:send_text(data)
                if not bytes then
                    ngx.log(ngx.ERR, "failed sending frame: ", err)
                    return ngx.exit(444)
                end
            end
        }
    }

    location /proxy {
        content_by_lua_block {
            local proxy = require "resty.websocket.proxy"

            local wp, err = proxy.new()
            if not wp then
                ngx.log(ngx.ERR, "failed creating proxy: ", err)
                return ngx.exit(444)
            end

            local ok, err = wp:connect_upstream(
                "ws://127.0.0.1:" .. ngx.var.server_port .. "/upstream"
            )
            if not ok then
                ngx.log(ngx.ERR, "failed connecting to upstream: ", err)
                return ngx.exit(444)
            end

            local ok, err = wp:connect_client()
            if not ok then
                ngx.log(ngx.ERR, "failed client handshake: ", err)
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
                if i == 1 then
                    assert(wb:send_frame(false, 0x1, "hello"))
                else
                    assert(wb:send_frame(true, 0x0, "world"))
                end

                local data = assert(wb:recv_frame())
                ngx.say(data)
            end

            wb:close()
        }
    }
--- response_body
hello
world
--- grep_error_log eval: qr/\[lua\].*/
--- grep_error_log_out eval
qr/.*?frame type: text, payload: "hello".*
.*?frame type: continuation, payload: "world".*/
--- no_error_log
[error]



=== TEST 2: opts.aggregate_fragments assembles fragmented client frames
--- http_config eval: $::HttpConfig
--- config
    location /proxy {
        content_by_lua_block {
            local proxy = require "resty.websocket.proxy"

            local wp, err = proxy.new({ aggregate_fragments = true })
            if not wp then
                ngx.log(ngx.ERR, "failed creating proxy: ", err)
                return ngx.exit(444)
            end

            local ok, err = wp:connect_upstream(proxy._tests.echo)
            if not ok then
                ngx.log(ngx.ERR, "failed connecting to upstream: ", err)
                return ngx.exit(444)
            end

            local ok, err = wp:connect_client()
            if not ok then
                ngx.log(ngx.ERR, "failed client handshake: ", err)
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
            assert(wb:send_frame(false, 0x1, "hello"))
            assert(wb:send_frame(true, 0x0, " world"))
            local data = assert(wb:recv_frame())
            ngx.say(data)
            wb:close()
        }
    }
--- response_body
hello world
--- grep_error_log eval: qr/\[lua\].*/
--- grep_error_log_out eval
qr/.*?frame type: text, payload: "hello world".*/
--- no_error_log
[error]



=== TEST 3: opts.aggregate_fragments assembles fragmented server frames
--- http_config eval: $::HttpConfig
--- config
    location /upstream {
        content_by_lua_block {
            local server = require "resty.websocket.server"

            local wb, err = server:new()
            if not wb then
                ngx.log(ngx.ERR, "failed creating server: ", err)
                return ngx.exit(444)
            end

            local data, typ, err = wb:recv_frame()
            if not data then
                ngx.log(ngx.ERR, "failed receiving frame: ", err)
                return ngx.exit(444)
            end

            ngx.log(ngx.INFO, "frame type: ", typ, ", payload: \"", data, "\"")

            local bytes, err = wb:send_frame(false, 0x1, "")
            if not bytes then
                ngx.log(ngx.ERR, "failed sending initial fragment: ", err)
                return ngx.exit(444)
            end

            for word in string.gmatch(data, "[^%s]+") do
                local bytes, err = wb:send_frame(false, 0x0, word)
                if not bytes then
                    ngx.log(ngx.ERR, "failed sending fragment: ", err)
                    return ngx.exit(444)
                end
            end

            local bytes, err = wb:send_frame(true, 0x0, "")
            if not bytes then
                ngx.log(ngx.ERR, "failed sending last fragment: ", err)
                return ngx.exit(444)
            end
        }
    }

    location /proxy {
        content_by_lua_block {
            local proxy = require "resty.websocket.proxy"

            local wp, err = proxy.new({ aggregate_fragments = true })
            if not wp then
                ngx.log(ngx.ERR, "failed creating proxy: ", err)
                return ngx.exit(444)
            end

            local ok, err = wp:connect_upstream(
                "ws://127.0.0.1:" .. ngx.var.server_port .. "/upstream"
            )
            if not ok then
                ngx.log(ngx.ERR, "failed connecting to upstream: ", err)
                return ngx.exit(444)
            end

            local ok, err = wp:connect_client()
            if not ok then
                ngx.log(ngx.ERR, "failed client handshake: ", err)
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
            assert(wb:send_text("hello world"))
            local data = assert(wb:recv_frame())
            ngx.say(data)
            wb:close()
        }
    }
--- response_body
helloworld
--- grep_error_log eval: qr/\[lua\].*/
--- grep_error_log_out eval
qr/.*?frame type: text, payload: "hello world".*/
--- no_error_log
[error]



=== TEST 4: opts.aggregate_fragments assembles fragmented frames consecutively
--- http_config eval: $::HttpConfig
--- config
    location /upstream {
        content_by_lua_block {
            local server = require "resty.websocket.server"

            local wb, err = server:new()
            if not wb then
                ngx.log(ngx.ERR, "failed creating server: ", err)
                return ngx.exit(444)
            end

            for i = 1, 2 do
                local data, typ, err = wb:recv_frame()
                if not data then
                    ngx.log(ngx.ERR, "failed receiving frame: ", err)
                    return ngx.exit(444)
                end

                ngx.log(ngx.INFO, "frame type: ", typ, ", payload: \"", data, "\"")

                local bytes, err = wb:send_frame(false, 0x1, "")
                if not bytes then
                    ngx.log(ngx.ERR, "failed sending initial fragment: ", err)
                    return ngx.exit(444)
                end

                for word in string.gmatch(data, "[^%s]+") do
                    local bytes, err = wb:send_frame(false, 0x0, word)
                    if not bytes then
                        ngx.log(ngx.ERR, "failed sending fragment: ", err)
                        return ngx.exit(444)
                    end
                end

                local bytes, err = wb:send_frame(true, 0x0, "")
                if not bytes then
                    ngx.log(ngx.ERR, "failed sending last fragment: ", err)
                    return ngx.exit(444)
                end
            end
        }
    }

    location /proxy {
        content_by_lua_block {
            local proxy = require "resty.websocket.proxy"

            local wp, err = proxy.new({ aggregate_fragments = true })
            if not wp then
                ngx.log(ngx.ERR, "failed creating proxy: ", err)
                return ngx.exit(444)
            end

            local ok, err = wp:connect_upstream(
                "ws://127.0.0.1:" .. ngx.var.server_port .. "/upstream"
            )
            if not ok then
                ngx.log(ngx.ERR, "failed connecting to upstream: ", err)
                return ngx.exit(444)
            end

            local ok, err = wp:connect_client()
            if not ok then
                ngx.log(ngx.ERR, "failed client handshake: ", err)
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
            assert(wb:send_frame(false, 0x1, "hello"))
            assert(wb:send_frame(true, 0x0, " world"))
            local data = assert(wb:recv_frame())
            ngx.say(data)

            assert(wb:send_frame(false, 0x1, "goodbye"))
            assert(wb:send_frame(true, 0x0, " world"))
            local data = assert(wb:recv_frame())
            ngx.say(data)

            wb:close()
        }
    }
--- response_body
helloworld
goodbyeworld
--- grep_error_log eval: qr/\[lua\].*/
--- grep_error_log_out eval
qr/.*?frame type: text, payload: "hello world".*
.*?frame type: text, payload: "goodbye world".*/
--- no_error_log
[error]



=== TEST 5: opts.on_frame with opts.aggregate_fragments
--- http_config eval: $::HttpConfig
--- config
    location /upstream {
        content_by_lua_block {
            local server = require "resty.websocket.server"

            local wb, err = server:new()
            if not wb then
                ngx.log(ngx.ERR, "failed creating server: ", err)
                return ngx.exit(444)
            end

            for i = 1, 2 do
                local data, typ, err = wb:recv_frame()
                if not data then
                    ngx.log(ngx.ERR, "failed receiving frame: ", err)
                    return ngx.exit(444)
                end

                local bytes, err = wb:send_frame(false, 0x1, "")
                if not bytes then
                    ngx.log(ngx.ERR, "failed sending initial fragment: ", err)
                    return ngx.exit(444)
                end

                for word in string.gmatch(data, "[^%s]+") do
                    local bytes, err = wb:send_frame(false, 0x0, word)
                    if not bytes then
                        ngx.log(ngx.ERR, "failed sending fragment: ", err)
                        return ngx.exit(444)
                    end
                end

                local bytes, err = wb:send_frame(true, 0x0, "")
                if not bytes then
                    ngx.log(ngx.ERR, "failed sending last fragment: ", err)
                    return ngx.exit(444)
                end
            end
        }
    }

    location /proxy {
        content_by_lua_block {
            local proxy = require "resty.websocket.proxy"

            local function on_frame(_, role, typ, data, fin, code)
                ngx.log(ngx.INFO, "from: ", role, ", type: ", typ,
                                  ", payload: ", data, ", fin: ", fin)

                return "updated " .. role .. " frame", code
            end

            local wp, err = proxy.new({
                aggregate_fragments = true,
                on_frame = on_frame,
            })
            if not wp then
                ngx.log(ngx.ERR, "failed creating proxy: ", err)
                return ngx.exit(444)
            end

            local ok, err = wp:connect_upstream(
                "ws://127.0.0.1:" .. ngx.var.server_port .. "/upstream"
            )
            if not ok then
                ngx.log(ngx.ERR, "failed connecting to upstream: ", err)
                return ngx.exit(444)
            end

            local ok, err = wp:connect_client()
            if not ok then
                ngx.log(ngx.ERR, "failed client handshake: ", err)
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
            assert(wb:send_frame(false, 0x1, "hello"))
            assert(wb:send_frame(true, 0x0, " world"))
            local data = assert(wb:recv_frame())
            ngx.say(data)

            assert(wb:send_frame(false, 0x1, "goodbye"))
            assert(wb:send_frame(true, 0x0, " world"))
            local data = assert(wb:recv_frame())
            ngx.say(data)

            wb:close()
        }
    }
--- response_body
updated upstream frame
updated upstream frame
--- grep_error_log eval: qr/\[lua\].*/
--- grep_error_log_out eval
qr/.*?from: client, type: text, payload: hello world, fin: true.*
.*?from: upstream, type: text, payload: updatedclientframe, fin: true.*
.*?from: client, type: text, payload: goodbye world, fin: true.*
.*?from: upstream, type: text, payload: updatedclientframe, fin: true.*/
--- no_error_log
[error]



=== TEST 6: opts.on_frame without opts.aggregate_fragments
--- http_config eval: $::HttpConfig
--- config
    location /upstream {
        content_by_lua_block {
            local server = require "resty.websocket.server"

            local wb, err = server:new()
            if not wb then
                ngx.log(ngx.ERR, "failed creating server: ", err)
                return ngx.exit(444)
            end

            for i = 1, 2 do
                local data, typ, err = wb:recv_frame()
                if not data then
                    ngx.log(ngx.ERR, "failed receiving frame: ", err)
                    return ngx.exit(444)
                end

                local bytes, err = wb:send_frame(false, 0x1, "")
                if not bytes then
                    ngx.log(ngx.ERR, "failed sending initial fragment: ", err)
                    return ngx.exit(444)
                end

                for word in string.gmatch(data, "[^%s]+") do
                    local bytes, err = wb:send_frame(false, 0x0, word)
                    if not bytes then
                        ngx.log(ngx.ERR, "failed sending fragment: ", err)
                        return ngx.exit(444)
                    end
                end

                local bytes, err = wb:send_frame(true, 0x0, "")
                if not bytes then
                    ngx.log(ngx.ERR, "failed sending last fragment: ", err)
                    return ngx.exit(444)
                end
            end
        }
    }

    location /proxy {
        content_by_lua_block {
            local proxy = require "resty.websocket.proxy"

            local function on_frame(_, role, typ, data, fin, code)
                ngx.log(ngx.INFO, "from: ", role, ", type: ", typ,
                                  ", payload: ", data, ", fin: ", fin)

                return "updated " .. role .. " frame", code
            end

            local wp, err = proxy.new({
                aggregate_fragments = false,
                on_frame = on_frame,
            })
            if not wp then
                ngx.log(ngx.ERR, "failed creating proxy: ", err)
                return ngx.exit(444)
            end

            local ok, err = wp:connect_upstream(
                "ws://127.0.0.1:" .. ngx.var.server_port .. "/upstream"
            )
            if not ok then
                ngx.log(ngx.ERR, "failed connecting to upstream: ", err)
                return ngx.exit(444)
            end

            local ok, err = wp:connect_client()
            if not ok then
                ngx.log(ngx.ERR, "failed client handshake: ", err)
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
            assert(wb:send_frame(false, 0x1, "hello"))
            assert(wb:send_frame(true, 0x0, " world"))
            local data = assert(wb:recv_frame())
            ngx.say(data)

            assert(wb:send_frame(false, 0x1, "goodbye"))
            assert(wb:send_frame(true, 0x0, " world"))
            local data = assert(wb:recv_frame())
            ngx.say(data)

            wb:close()
        }
    }
--- response_body
updated upstream frame
updated upstream frame
--- grep_error_log eval: qr/\[lua\].*/
--- grep_error_log_out eval
qr/.*?from: client, type: text, payload: hello, fin: false.*
.*?from: client, type: continuation, payload:  world, fin: true.*
.*?from: upstream, type: text, payload: , fin: false.*
.*?from: upstream, type: continuation, payload: updated, fin: false.*
.*?from: upstream, type: continuation, payload: client, fin: false.*
.*?from: upstream, type: continuation, payload: frame, fin: false.*
.*?from: upstream, type: continuation, payload: , fin: true.*
.*?from: upstream, type: text, payload: , fin: false.*
.*?from: upstream, type: continuation, payload: updated, fin: false.*
.*?from: upstream, type: continuation, payload: client, fin: false.*
.*?from: upstream, type: continuation, payload: frame, fin: false.*
.*?from: upstream, type: continuation, payload: , fin: true.*/
--- no_error_log
[error]



=== TEST 7: control frames interleaved with fragmented data frames (opts.aggregate_fragments off)
--- http_config eval: $::HttpConfig
--- config
    location /upstream {
        content_by_lua_block {
            local server = require "resty.websocket.server"

            local function check(ok, err, msg)
                if not ok then
                    ngx.log(ngx.ERR, msg, ": ", err)
                    return ngx.exit(444)
                end
            end

            local wb, err = server:new()
            check(wb, err, "failed creating server")

            local ok, err = wb:send_frame(false, 0x1, "")
            check(ok, err, "failed sending initial fragment")

            local payloads = { "a", "b", "c" }

            for i, data in ipairs(payloads) do
                ok, err = wb:send_frame(false, 0x0, data)
                check(ok, err, "failed sending partial data frame")

                ok, err = wb:send_ping(i)
                check(ok, err, "failed sending ping")
            end

            ok, err = wb:send_frame(true, 0x0, "")
            check(ok, err, "failed sending last fragment")

            local bytes, err = wb:send_close(1000, "server close")
            check(bytes, err, "failed sending close frame")
        }
    }

    location /proxy {
        content_by_lua_block {
            local proxy = require "resty.websocket.proxy"

            local function check(ok, err, msg)
                if not ok then
                    ngx.log(ngx.ERR, msg, ": ", err)
                    return ngx.exit(444)
                end
            end

            local wp, err = proxy.new({ aggregate_fragments = false })
            check(wp, err, "failed creating proxy")

            local uri = "ws://127.0.0.1:" .. ngx.var.server_port .. "/upstream"
            local ok, err = wp:connect_upstream(uri)
            check(ok, err, "failed connecting to upstream")

            ok, err = wp:connect_client()
            check(ok, err, "failed client handshake")

            local done, err = wp:execute()
            check(done, err, "failed proxying")
        }
    }

    location /t {
        content_by_lua_block {
            local client = require "resty.websocket.client"
            local fmt = string.format

            local wb = assert(client:new())
            local uri = "ws://127.0.0.1:" .. ngx.var.server_port .. "/proxy"

            assert(wb:connect(uri))

            repeat
                local data, typ, err = wb:recv_frame()
                ngx.say(fmt("typ: %s, data: %q, err/code: %s", typ, data, err))
            until typ == "close"
        }
    }
--- response_body
typ: text, data: "", err/code: again
typ: continuation, data: "a", err/code: again
typ: ping, data: "1", err/code: nil
typ: continuation, data: "b", err/code: again
typ: ping, data: "2", err/code: nil
typ: continuation, data: "c", err/code: again
typ: ping, data: "3", err/code: nil
typ: continuation, data: "", err/code: nil
typ: close, data: "server close", err/code: 1000
--- no_error_log
[error]
[crit]



=== TEST 8: control frames interleaved with fragmented data frames (opts.aggregate_fragments on)
--- http_config eval: $::HttpConfig
--- config
    location /upstream {
        content_by_lua_block {
            local server = require "resty.websocket.server"

            local function check(ok, err, msg)
                if not ok then
                    ngx.log(ngx.ERR, msg, ": ", err)
                    return ngx.exit(444)
                end
            end

            local wb, err = server:new()
            check(wb, err, "failed creating server")

            local ok, err = wb:send_frame(false, 0x1, "")
            check(ok, err, "failed sending initial fragment")

            local payloads = { "a", "b", "c" }

            for i, data in ipairs(payloads) do
                ok, err = wb:send_frame(false, 0x0, data)
                check(ok, err, "failed sending partial data frame")

                ok, err = wb:send_ping(i)
                check(ok, err, "failed sending ping")
            end

            ok, err = wb:send_frame(true, 0x0, "")
            check(ok, err, "failed sending final fragment")

            local bytes, err = wb:send_close(1000, "server close")
            check(bytes, err, "failed sending close frame")
        }
    }

    location /proxy {
        content_by_lua_block {
            local proxy = require "resty.websocket.proxy"

            local function check(ok, err, msg)
                if not ok then
                    ngx.log(ngx.ERR, msg, ": ", err)
                    return ngx.exit(444)
                end
            end

            local wp, err = proxy.new({ aggregate_fragments = true })
            check(wp, err, "failed creating proxy")

            local uri = "ws://127.0.0.1:" .. ngx.var.server_port .. "/upstream"
            local ok, err = wp:connect_upstream(uri)
            check(ok, err, "failed connecting to upstream")

            ok, err = wp:connect_client()
            check(ok, err, "failed client handshake")

            local done, err = wp:execute()
            check(done, err, "failed proxying")
        }
    }

    location /t {
        content_by_lua_block {
            local client = require "resty.websocket.client"
            local fmt = string.format

            local wb = assert(client:new())
            local uri = "ws://127.0.0.1:" .. ngx.var.server_port .. "/proxy"

            assert(wb:connect(uri))

            repeat
                local data, typ, err = wb:recv_frame()
                ngx.say(fmt("typ: %s, data: %q, err/code: %s", typ, data, err))
            until typ == "close"
        }
    }
--- response_body
typ: ping, data: "1", err/code: nil
typ: ping, data: "2", err/code: nil
typ: ping, data: "3", err/code: nil
typ: text, data: "abc", err/code: nil
typ: close, data: "server close", err/code: 1000
--- no_error_log
[error]
[crit]
