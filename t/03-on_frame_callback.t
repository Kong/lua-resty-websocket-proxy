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

=== TEST 1: invokes opts.on_frame function on each frame
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

            local function on_frame(role, typ, data, fin)
                ngx.log(ngx.INFO, "from: ", role, ", type: ", typ,
                                  ", payload: ", data, ", fin: ", fin,
                                  ", context: ", ngx.get_phase())
            end

            local wb, err = proxy.new({
                upstream = "ws://127.0.0.1:" .. ngx.var.server_port .. "/upstream",
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
            assert(wb:send_text("hello world!"))
            local data = assert(wb:recv_frame())
            ngx.say(data)
        }
    }
--- request
GET /t
--- response_body
hello world!
--- grep_error_log eval: qr/\[lua\].*/
--- grep_error_log_out eval
qr/.*?from: client, type: text, payload: hello world!, fin: true, context: content.*?
.*?from: upstream, type: text, payload: hello world!, fin: true, context: content.*/
--- no_error_log
[error]



=== TEST 2: opts.on_frame can update a text frame payload
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

            local function on_frame(role, typ, data, fin)
                ngx.log(ngx.INFO, "from: ", role, ", type: ", typ,
                                  ", payload: ", data, ", fin: ", fin)

                return "updated " .. role .. " frame"
            end

            local wb, err = proxy.new({
                upstream = "ws://127.0.0.1:" .. ngx.var.server_port .. "/upstream",
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
            assert(wb:send_text("hello world!"))
            local data = assert(wb:recv_frame())
            ngx.say(data)
        }
    }
--- request
GET /t
--- response_body
updated upstream frame
--- grep_error_log eval: qr/\[lua\].*/
--- grep_error_log_out eval
qr/.*?from: client, type: text, payload: hello world!, fin: true.*?
.*?from: upstream, type: text, payload: updated client frame, fin: true.*/
--- no_error_log
[error]



=== TEST 3: opts.on_frame can update a binary frame payload
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

            local function on_frame(role, typ, data, fin)
                return "updated " .. role .. " frame (" .. typ .. ")"
            end

            local wb, err = proxy.new({
                upstream = "ws://127.0.0.1:" .. ngx.var.server_port .. "/upstream",
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
            assert(wb:send_binary("你好, WebSocket!"))
            local data, opcode = assert(wb:recv_frame())
            ngx.say(opcode, ": ", data)
        }
    }
--- request
GET /t
--- response_body
binary: updated upstream frame (binary)
--- no_error_log
[crit]
[error]



=== TEST 4: opts.on_frame can update a close frame payload
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
            local fmt = string.format
            local proxy = require "resty.websocket.proxy"

            local function on_frame(role, typ, data, fin)
                local msg = "updated " .. role .. " frame (" .. typ .. ")"

                ngx.log(ngx.DEBUG, fmt("updated %s [%s] frame payload from %s to %s",
                                       role, typ, fmt("%q", data), fmt("%q", msg)))

                return msg
            end

            local wb, err = proxy.new({
                upstream = "ws://127.0.0.1:" .. ngx.var.server_port .. "/upstream",
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
            local data, typ, err = assert(wb:recv_frame())
            ngx.say(typ)
            ngx.say(data)
        }
    }
--- request
GET /t
--- response_body
close
updated upstream frame (close)
--- no_error_log
[crit]
[error]
