# vim:set ts=4 sts=4 sw=4 et ft=:

use lib '.';
use t::Tests;

plan tests => repeat_each() * (blocks() * 4);

run_tests();

__DATA__

=== TEST 1: calling connect_upstream() while already established logs a warning
--- http_config eval: $t::Tests::HttpConfig
--- config
    location /proxy {
        content_by_lua_block {
            local proxy = require "resty.websocket.proxy"

            local wp, err = proxy.new()
            if not wp then
                ngx.log(ngx.ERR, "failed creating proxy: ", err)
                return ngx.exit(444)
            end

            local ok, err = wp:connect(proxy._tests.echo)
            if not ok then
                ngx.log(ngx.ERR, err)
                return ngx.exit(444)
            end

            assert(wp:connect_upstream(uri))

            local done, err = wp:execute()
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
--- response_body
hello world!
--- grep_error_log eval: qr/\[(info|warn)\].*/
--- grep_error_log_out eval
qr/\A\[warn\] .*? connection with upstream at "ws:.*?" already established.*
\[info\] .*? frame type: text, payload: "hello world!"/
--- no_error_log
[error]



=== TEST 2: calling connect_client() while client handshake already completed logs a warning
--- http_config eval: $t::Tests::HttpConfig
--- config
    location /proxy {
        content_by_lua_block {
            local proxy = require "resty.websocket.proxy"

            local wp, err = proxy.new()
            if not wp then
                ngx.log(ngx.ERR, "failed creating proxy: ", err)
                return ngx.exit(444)
            end

            local ok, err = wp:connect(proxy._tests.echo)
            if not ok then
                ngx.log(ngx.ERR, err)
                return ngx.exit(444)
            end

            assert(wp:connect_client(uri))

            local done, err = wp:execute()
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
--- response_body
hello world!
--- grep_error_log eval: qr/\[(info|warn)\].*/
--- grep_error_log_out eval
qr/\A\[warn\] .*? client handshake already completed.*
\[info\] .*? frame type: text, payload: "hello world!"/
--- no_error_log
[error]



=== TEST 3: calling execute() without having completed the client handshake
--- http_config eval: $t::Tests::HttpConfig
--- config
    location /proxy {
        content_by_lua_block {
            local proxy = require "resty.websocket.proxy"

            local wp, err = proxy.new()
            if not wp then
                ngx.log(ngx.ERR, "failed creating proxy: ", err)
                return ngx.exit(444)
            end

            local ok, err = wp:connect_upstream(proxy._tests.echo)
            if not ok then
                ngx.log(ngx.ERR, "failed connecting to upstream: ", err)
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
        }
    }
--- error_code: 500
--- ignore_response_body
--- grep_error_log eval: qr/\[error\].*/
--- grep_error_log_out eval
qr/\A\[error\] .*? failed proxying: client handshake not complete.*/
--- no_error_log
[crit]
[emerg]



=== TEST 4: calling execute() without having established the upstream connection
--- http_config eval: $t::Tests::HttpConfig
--- config
    location /proxy {
        content_by_lua_block {
            local proxy = require "resty.websocket.proxy"

            local wp, err = proxy.new({debug = true})
            if not wp then
                ngx.log(ngx.ERR, "failed creating proxy: ", err)
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
        }
    }
--- response_body
--- grep_error_log eval: qr/\[error\].*/
--- grep_error_log_out eval
qr/\A\[error\] .*? failed proxying: upstream connection not established.*/
--- no_error_log
[crit]
