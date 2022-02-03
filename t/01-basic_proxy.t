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

=== TEST 1: forward a text frame back and forth
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
            local wb, err = proxy.new()
            if not wb then
                ngx.log(ngx.ERR, "failed creating proxy: ", err)
                return ngx.exit(444)
            end

            local ok, err = wb:connect_upstream(
                "ws://127.0.0.1:" .. ngx.var.server_port .. "/upstream"
            )

            if not ok then
                ngx.log(ngx.ERR, "failed connecting to upstream: ", err)
                return ngx.exit(444)
            end

            local ok, err = wb:connect_client()
            if not ok then
                ngx.log(ngx.ERR, "failed client handshake: ", err)
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
qr/frame type: text, payload: "hello world!"/
--- no_error_log
[error]



=== TEST 2: forward a ping/pong exchange
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

            local bytes, err = wb:send_pong("heartbeat server")
            if not bytes then
                ngx.log(ngx.ERR, "failed sending frame: ", err)
                return ngx.exit(444)
            end
        }
    }


    location /proxy {
        content_by_lua_block {
            local proxy = require "resty.websocket.proxy"
            local wb, err = proxy.new()
            if not wb then
                ngx.log(ngx.ERR, "failed creating proxy: ", err)
                return ngx.exit(444)
            end

            local ok, err = wb:connect_upstream(
                "ws://127.0.0.1:" .. ngx.var.server_port .. "/upstream"
            )

            if not ok then
                ngx.log(ngx.ERR, "failed connecting to upstream: ", err)
                return ngx.exit(444)
            end

            local ok, err = wb:connect_client()
            if not ok then
                ngx.log(ngx.ERR, "failed client handshake: ", err)
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
            assert(wb:send_ping("heartbeat client"))
            local data, opcode = assert(wb:recv_frame())
            ngx.say(opcode, ": ", data)
        }
    }
--- request
GET /t
--- response_body
pong: heartbeat server
--- grep_error_log eval: qr/\[lua\].*/
--- grep_error_log_out eval
qr/frame type: ping, payload: "heartbeat client"/
--- no_error_log
[error]



=== TEST 3: forward a binary frame back and forth
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
            local wb, err = proxy.new()
            if not wb then
                ngx.log(ngx.ERR, "failed creating proxy: ", err)
                return ngx.exit(444)
            end

            local ok, err = wb:connect_upstream(
                "ws://127.0.0.1:" .. ngx.var.server_port .. "/upstream"
            )

            if not ok then
                ngx.log(ngx.ERR, "failed connecting to upstream: ", err)
                return ngx.exit(444)
            end

            local ok, err = wb:connect_client()
            if not ok then
                ngx.log(ngx.ERR, "failed client handshake: ", err)
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
binary: 你好, WebSocket!
--- grep_error_log eval: qr/\[lua\].*/
--- grep_error_log_out eval
qr/frame type: binary, payload: "你好, WebSocket!"/
--- no_error_log
[error]



=== TEST 4: forward close frame exchange from the client
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

            ngx.log(ngx.INFO, "frame type: ", typ,
                              ", code: ", err,
                              ", payload: \"", data, "\"")

            local bytes, err = wb:send_close()
            if not bytes then
                ngx.log(ngx.ERR, "failed sending close frame: ", err)
                return ngx.exit(444)
            end
        }
    }

    location /proxy {
        content_by_lua_block {
            local proxy = require "resty.websocket.proxy"
            local wb, err = proxy.new()
            if not wb then
                ngx.log(ngx.ERR, "failed creating proxy: ", err)
                return ngx.exit(444)
            end

            local ok, err = wb:connect_upstream(
                "ws://127.0.0.1:" .. ngx.var.server_port .. "/upstream"
            )

            if not ok then
                ngx.log(ngx.ERR, "failed connecting to upstream: ", err)
                return ngx.exit(444)
            end

            local ok, err = wb:connect_client()
            if not ok then
                ngx.log(ngx.ERR, "failed client handshake: ", err)
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
            assert(wb:send_close(1000, "goodbye"))
            local data, opcode = assert(wb:recv_frame())
            ngx.say(opcode, ": ", data)
            wb:close()
        }
    }
--- request
GET /t
--- ignore_response_body
--- grep_error_log eval: qr/\[lua\].*/
--- grep_error_log_out eval
qr/frame type: close, code: 1000, payload: "goodbye"/
--- no_error_log
[crit]
[error]



=== TEST 5: forward close frame exchange from upstream
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

            local bytes, err = wb:send_close()
            if not bytes then
                ngx.log(ngx.ERR, "failed sending close frame: ", err)
                return ngx.exit(444)
            end
        }
    }

    location /proxy {
        content_by_lua_block {
            local proxy = require "resty.websocket.proxy"
            local wb, err = proxy.new()
            if not wb then
                ngx.log(ngx.ERR, "failed creating proxy: ", err)
                return ngx.exit(444)
            end

            local ok, err = wb:connect_upstream(
                "ws://127.0.0.1:" .. ngx.var.server_port .. "/upstream"
            )

            if not ok then
                ngx.log(ngx.ERR, "failed connecting to upstream: ", err)
                return ngx.exit(444)
            end

            local ok, err = wb:connect_client()
            if not ok then
                ngx.log(ngx.ERR, "failed client handshake: ", err)
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
            local data, opcode = assert(wb:recv_frame())
            ngx.say(opcode)
        }
    }
--- request
GET /t
--- response_body
close
--- grep_error_log eval: qr/\[lua\].*/
--- grep_error_log_out eval
qr/forwarding close with code: nil/
--- no_error_log
[error]



=== TEST 6: handshake with client before upstream
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
            local wb, err = proxy.new()
            if not wb then
                ngx.log(ngx.ERR, "failed creating proxy: ", err)
                return ngx.exit(444)
            end

            local ok, err = wb:connect_client()
            if not ok then
                ngx.log(ngx.ERR, "failed client handshake: ", err)
                return ngx.exit(444)
            end

            local ok, err = wb:connect_upstream(
                "ws://127.0.0.1:" .. ngx.var.server_port .. "/upstream"
            )

            if not ok then
                ngx.log(ngx.ERR, "failed connecting to upstream: ", err)
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
qr/frame type: text, payload: "hello world!"/
--- no_error_log
[error]
