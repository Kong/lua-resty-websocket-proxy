# vim:set ts=4 sts=4 sw=4 et ft=:

use Test::Nginx::Socket::Lua;
use Cwd qw(cwd);

plan tests => repeat_each() * (blocks() * 4);

my $pwd = cwd();

our $HttpConfig = qq{
    lua_package_path "$pwd/lib/?.lua;$pwd/misc/lua-resty-websocket/lib/?.lua;;";
};

log_level('info');

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
            local wb, err = proxy.new({
                upstream = "ws://127.0.0.1:" .. ngx.var.server_port .. "/upstream",
            })
            if not wb then
                ngx.log(ngx.ERR, "failed creating proxy: ", err)
                return ngx.exit(444)
            end

            local done, err = wb:execute()
            if not done then
                ngx.log(ngx.ERR, "failed proxying: ", err)
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
                    assert(wb:send_frame(true, 0x1, "world"))
                end

                local data = assert(wb:recv_frame())
                ngx.say(data)
            end

            wb:close()
        }
    }
--- request
GET /t
--- response_body
hello
world
--- grep_error_log eval: qr/\[lua\].*/
--- grep_error_log_out eval
qr/.*?frame type: text, payload: "hello".*
.*?frame type: text, payload: "world".*/
--- no_error_log
[error]



=== TEST 2: opts.aggregate_fragments assembles fragmented client frames
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

            local bytes, err = wb:send_text(data)
            if not bytes then
                ngx.log(ngx.ERR, "failed sending frame: ", err)
                return ngx.exit(444)
            end
        }
    }

    location /proxy {
        content_by_lua_block {
            local proxy = require "resty.websocket.proxy"
            local wb, err = proxy.new({
                upstream = "ws://127.0.0.1:" .. ngx.var.server_port .. "/upstream",
                aggregate_fragments = true,
            })
            if not wb then
                ngx.log(ngx.ERR, "failed creating proxy: ", err)
                return ngx.exit(444)
            end

            local done, err = wb:execute()
            if not done then
                ngx.log(ngx.ERR, "failed proxying: ", err)
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
            assert(wb:send_frame(true, 0x1, " world"))
            local data = assert(wb:recv_frame())
            ngx.say(data)
            wb:close()
        }
    }
--- request
GET /t
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

            for word in string.gmatch(data, "[^%s]+") do
                local bytes, err = wb:send_frame(false, 0x1, word)
                if not bytes then
                    ngx.log(ngx.ERR, "failed sending frame: ", err)
                    return ngx.exit(444)
                end
            end

            local bytes, err = wb:send_frame(true, 0x1, "")
            if not bytes then
                ngx.log(ngx.ERR, "failed sending frame: ", err)
                return ngx.exit(444)
            end
        }
    }

    location /proxy {
        content_by_lua_block {
            local proxy = require "resty.websocket.proxy"
            local wb, err = proxy.new({
                upstream = "ws://127.0.0.1:" .. ngx.var.server_port .. "/upstream",
                aggregate_fragments = true,
            })
            if not wb then
                ngx.log(ngx.ERR, "failed creating proxy: ", err)
                return ngx.exit(444)
            end

            local done, err = wb:execute()
            if not done then
                ngx.log(ngx.ERR, "failed proxying: ", err)
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
--- request
GET /t
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

                for word in string.gmatch(data, "[^%s]+") do
                    local bytes, err = wb:send_frame(false, 0x1, word)
                    if not bytes then
                        ngx.log(ngx.ERR, "failed sending frame: ", err)
                        return ngx.exit(444)
                    end
                end

                local bytes, err = wb:send_frame(true, 0x1, "")
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
            local wb, err = proxy.new({
                upstream = "ws://127.0.0.1:" .. ngx.var.server_port .. "/upstream",
                aggregate_fragments = true,
            })
            if not wb then
                ngx.log(ngx.ERR, "failed creating proxy: ", err)
                return ngx.exit(444)
            end

            local done, err = wb:execute()
            if not done then
                ngx.log(ngx.ERR, "failed proxying: ", err)
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
            assert(wb:send_frame(true, 0x1, " world"))
            local data = assert(wb:recv_frame())
            ngx.say(data)

            assert(wb:send_frame(false, 0x1, "goodbye"))
            assert(wb:send_frame(true, 0x1, " world"))
            local data = assert(wb:recv_frame())
            ngx.say(data)

            wb:close()
        }
    }
--- request
GET /t
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

                for word in string.gmatch(data, "[^%s]+") do
                    local bytes, err = wb:send_frame(false, 0x1, word)
                    if not bytes then
                        ngx.log(ngx.ERR, "failed sending frame: ", err)
                        return ngx.exit(444)
                    end
                end

                local bytes, err = wb:send_frame(true, 0x1, "")
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

            local function on_frame(role, typ, data, fin)
                ngx.log(ngx.INFO, "from: ", role, ", type: ", typ,
                                  ", payload: ", data, ", fin: ", fin)

                return "updated " .. role .. " frame"
            end

            local wb, err = proxy.new({
                upstream = "ws://127.0.0.1:" .. ngx.var.server_port .. "/upstream",
                aggregate_fragments = true,
                on_frame = on_frame,
            })
            if not wb then
                ngx.log(ngx.ERR, "failed creating proxy: ", err)
                return ngx.exit(444)
            end

            local done, err = wb:execute()
            if not done then
                ngx.log(ngx.ERR, "failed proxying: ", err)
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
            assert(wb:send_frame(true, 0x1, " world"))
            local data = assert(wb:recv_frame())
            ngx.say(data)

            assert(wb:send_frame(false, 0x1, "goodbye"))
            assert(wb:send_frame(true, 0x1, " world"))
            local data = assert(wb:recv_frame())
            ngx.say(data)

            wb:close()
        }
    }
--- request
GET /t
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

                for word in string.gmatch(data, "[^%s]+") do
                    local bytes, err = wb:send_frame(false, 0x1, word)
                    if not bytes then
                        ngx.log(ngx.ERR, "failed sending frame: ", err)
                        return ngx.exit(444)
                    end
                end

                local bytes, err = wb:send_frame(true, 0x1, "")
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

            local function on_frame(role, typ, data, fin)
                ngx.log(ngx.INFO, "from: ", role, ", type: ", typ,
                                  ", payload: ", data, ", fin: ", fin)

                return "updated " .. role .. " frame"
            end

            local wb, err = proxy.new({
                upstream = "ws://127.0.0.1:" .. ngx.var.server_port .. "/upstream",
                aggregate_fragments = false,
                on_frame = on_frame,
            })
            if not wb then
                ngx.log(ngx.ERR, "failed creating proxy: ", err)
                return ngx.exit(444)
            end

            local done, err = wb:execute()
            if not done then
                ngx.log(ngx.ERR, "failed proxying: ", err)
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
            assert(wb:send_frame(true, 0x1, " world"))
            local data = assert(wb:recv_frame())
            ngx.say(data)

            assert(wb:send_frame(false, 0x1, "goodbye"))
            assert(wb:send_frame(true, 0x1, " world"))
            local data = assert(wb:recv_frame())
            ngx.say(data)

            wb:close()
        }
    }
--- request
GET /t
--- response_body
updated upstream frame
updated upstream frame
--- grep_error_log eval: qr/\[lua\].*/
--- grep_error_log_out eval
qr/.*?from: client, type: text, payload: hello, fin: false.*
.*?from: client, type: text, payload:  world, fin: true.*
.*?from: upstream, type: text, payload: updated, fin: false.*
.*?from: upstream, type: text, payload: client, fin: false.*
.*?from: upstream, type: text, payload: frame, fin: false.*
.*?from: upstream, type: text, payload: , fin: true.*
.*?from: upstream, type: text, payload: updated, fin: false.*
.*?from: upstream, type: text, payload: client, fin: false.*
.*?from: upstream, type: text, payload: frame, fin: false.*
.*?from: upstream, type: text, payload: , fin: true.*/
--- no_error_log
[error]
