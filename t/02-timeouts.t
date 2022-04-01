# vim:set ts=4 sts=4 sw=4 et ft=:

use lib '.';
use t::Tests;

plan tests => repeat_each() * (blocks() * 4);

run_tests();

__DATA__

=== TEST 1: on client recv_frame timeout
--- http_config eval: $t::Tests::HttpConfig
--- config
    lua_socket_log_errors off;

    location /proxy {
        content_by_lua_block {
            local proxy = require "resty.websocket.proxy"

            local wb, err = proxy.new({
                recv_timeout = 80,
            })
            if not wb then
                ngx.log(ngx.ERR, "failed creating proxy: ", err)
                return ngx.exit(444)
            end

            local ok, err = wb:connect_upstream(proxy._tests.echo)
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
            ngx.sleep(0.1)
            assert(wb:send_text("hello world!"))
            local data = assert(wb:recv_frame())
            ngx.say(data)
        }
    }
--- response_body
hello world!
--- grep_error_log eval: qr/\[lua\].*/
--- grep_error_log_out eval
qr/.*?timeout receiving frame from client, reopening.*
.*?timeout receiving frame from upstream, reopening.*
.*?frame type: text, payload: "hello world!".*/
--- no_error_log
[crit]



=== TEST 2: on upstream recv_frame timeout
--- http_config eval: $t::Tests::HttpConfig
--- config
    lua_socket_log_errors off;

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

            ngx.sleep(0.1)

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
                recv_timeout = 80,
            })
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
--- grep_error_log eval: qr/\[lua\].*/
--- grep_error_log_out eval
qr/.*?frame type: text, payload: "hello world!".*
.*?timeout receiving frame from upstream, reopening.*/
--- no_error_log
[crit]
