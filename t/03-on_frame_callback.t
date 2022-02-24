# vim:set ts=4 sts=4 sw=4 et ft=:

use lib '.';
use t::Tests;

plan tests => repeat_each() * (blocks() * 4);

run_tests();

__DATA__

=== TEST 1: invokes opts.on_frame function on each frame
--- http_config eval: $t::Tests::HttpConfig
--- config
    location /proxy {
        content_by_lua_block {
            local proxy = require "resty.websocket.proxy"

            local function on_frame(_, role, typ, data, fin, code)
                ngx.log(ngx.INFO, "from: ", role, ", type: ", typ,
                                  ", payload: ", data, ", fin: ", fin,
                                  ", context: ", ngx.get_phase())
                -- test: only return data (code == nil)
                return data
            end

            local wp, err = proxy.new({ on_frame = on_frame })
            if not wp then
                ngx.log(ngx.ERR, "failed creating proxy: ", err)
                return ngx.exit(444)
            end

            local ok, err = wp:connect(proxy._tests.echo)
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
            assert(wb:send_text("hello world!"))
            local data = assert(wb:recv_frame())
            ngx.say(data)
        }
    }
--- response_body
hello world!
--- grep_error_log eval: qr/\[lua\].*?from:.*/
--- grep_error_log_out eval
qr/.*?from: client, type: text, payload: hello world!, fin: true, context: content.*?
.*?from: upstream, type: text, payload: hello world!, fin: true, context: content.*/
--- no_error_log
[error]



=== TEST 2: opts.on_frame can update a text frame payload
--- http_config eval: $t::Tests::HttpConfig
--- config
    location /proxy {
        content_by_lua_block {
            local proxy = require "resty.websocket.proxy"

            local function on_frame(_, role, typ, data, fin, code)
                ngx.log(ngx.INFO, "from: ", role, ", type: ", typ,
                                  ", payload: ", data, ", fin: ", fin)

                return "updated " .. role .. " frame", code
            end

            local wp, err = proxy.new({ on_frame = on_frame })
            if not wp then
                ngx.log(ngx.ERR, "failed creating proxy: ", err)
                return ngx.exit(444)
            end

            local ok, err = wp:connect(proxy._tests.echo)
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
            assert(wb:send_text("hello world!"))
            local data = assert(wb:recv_frame())
            ngx.say(data)
        }
    }
--- response_body
updated upstream frame
--- grep_error_log eval: qr/\[lua\].*from:.*/
--- grep_error_log_out eval
qr/.*?from: client, type: text, payload: hello world!, fin: true.*?
.*?from: upstream, type: text, payload: updated client frame, fin: true.*/
--- no_error_log
[error]



=== TEST 3: opts.on_frame can update a binary frame payload
--- http_config eval: $t::Tests::HttpConfig
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

            local bytes, err = wb:send_binary(data)
            if not bytes then
                ngx.log(ngx.ERR, "failed sending frame: ", err)
                return ngx.exit(444)
            end
        }
    }

    location /proxy {
        content_by_lua_block {
            local proxy = require "resty.websocket.proxy"

            local function on_frame(_, role, typ, data, fin, code)
                return "updated " .. role .. " frame (" .. typ .. ")", code
            end

            local wp, err = proxy.new({ on_frame = on_frame })
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

    location /t {
        content_by_lua_block {
            local client = require "resty.websocket.client"
            local wb = assert(client:new())
            local uri = "ws://127.0.0.1:" .. ngx.var.server_port .. "/proxy"

            assert(wb:connect(uri))
            assert(wb:send_binary("你好, WebSocket!"))
            local data, opcode = assert(wb:recv_frame())
            ngx.say(opcode, ": ", data)
        }
    }
--- response_body
binary: updated upstream frame (binary)
--- no_error_log
[error]
[crit]



=== TEST 4: opts.on_frame can update a close frame payload
--- log_level: debug
--- http_config eval: $t::Tests::HttpConfig
--- config
    location /upstream {
        content_by_lua_block {
            local server = require "resty.websocket.server"

            local wb, err = server:new()
            if not wb then
                ngx.log(ngx.ERR, "failed creating server: ", err)
                return ngx.exit(444)
            end

            local bytes, err = wb:send_close(1000, "server close")
            if not bytes then
                ngx.log(ngx.ERR, "failed sending close frame: ", err)
                return ngx.exit(444)
            end
        }
    }

    location /proxy {
        content_by_lua_block {
            local proxy = require "resty.websocket.proxy"
            local fmt = string.format

            local function on_frame(_, role, typ, data, fin, code)
                local msg = "updated " .. role .. " frame (" .. typ .. ")"

                ngx.log(ngx.DEBUG, fmt("updated %s [%s] frame payload from %s to %s",
                                       role, typ, fmt("%q", data), fmt("%q", msg)))

                return msg, code
            end

            local wp, err = proxy.new({ on_frame = on_frame })
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

    location /t {
        content_by_lua_block {
            local client = require "resty.websocket.client"
            local wb = assert(client:new())
            local uri = "ws://127.0.0.1:" .. ngx.var.server_port .. "/proxy"

            assert(wb:connect(uri))
            local data, typ, err = assert(wb:recv_frame())
            ngx.say(typ)
            ngx.say(data)
            ngx.say(err)
        }
    }
--- response_body
close
updated upstream frame (close)
1000
--- no_error_log
[error]
[crit]



=== TEST 5: opts.on_frame can update a close frame status code
--- log_level: debug
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

            local bytes, err = wb:send_close(1000, "server close")
            if not bytes then
                ngx.log(ngx.ERR, "failed sending close frame: ", err)
                return ngx.exit(444)
            end
        }
    }

    location /proxy {
        content_by_lua_block {
            local proxy = require "resty.websocket.proxy"
            local fmt = string.format

            local function on_frame(_, role, typ, data, fin, code)
                local updated = 1001

                ngx.log(ngx.DEBUG, fmt("updated %s [%s] status from %s to %s",
                                       role, typ, code, updated))

                return data, updated
            end

            local wp, err = proxy.new({ on_frame = on_frame })
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

    location /t {
        content_by_lua_block {
            local client = require "resty.websocket.client"
            local wb = assert(client:new())
            local uri = "ws://127.0.0.1:" .. ngx.var.server_port .. "/proxy"

            assert(wb:connect(uri))
            local data, typ, err = assert(wb:recv_frame())
            ngx.say(typ)
            ngx.say(data)
            ngx.say(err)
        }
    }
--- response_body
close
server close
1001
--- no_error_log
[error]
[crit]



=== TEST 6: opts.on_frame can cause a frame to be dropped
--- log_level: debug
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

            local payloads = { "a", "b", "drop me", "c"}
            for _, data in ipairs(payloads) do
                local ok, err = wb:send_text(data)
                if not ok then
                    ngx.log(ngx.ERR, "failed sending payload: ", err)
                    return ngx.exit(444)
                end
            end

            local bytes, err = wb:send_close(1000, "server close")
            if not bytes then
                ngx.log(ngx.ERR, "failed sending close frame: ", err)
                return ngx.exit(444)
            end
        }
    }

    location /proxy {
        content_by_lua_block {
            local proxy = require "resty.websocket.proxy"

            local function on_frame(_, role, typ, data, fin, code)
                if typ == "text" and data == "drop me" then
                    ngx.log(ngx.DEBUG, "dropping 'drop me' frame")
                    data = nil
                end

                return data, code
            end

            local wp, err = proxy.new({ on_frame = on_frame })
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

    location /t {
        content_by_lua_block {
            local client = require "resty.websocket.client"
            local fmt = string.format
            local wb = assert(client:new())
            local uri = "ws://127.0.0.1:" .. ngx.var.server_port .. "/proxy"

            assert(wb:connect(uri))

            repeat
                local data, typ, err = assert(wb:recv_frame())
                ngx.say(fmt("typ: %s, data: %q, err/code: %s",
                            typ, data, err))
            until typ == "close"
        }
    }
--- response_body
typ: text, data: "a", err/code: nil
typ: text, data: "b", err/code: nil
typ: text, data: "c", err/code: nil
typ: close, data: "server close", err/code: 1000
--- no_error_log
[error]
[crit]
