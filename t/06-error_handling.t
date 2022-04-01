# vim:set ts=4 sts=4 sw=4 et ft=:

use lib '.';
use t::Tests;

plan tests => repeat_each() * (blocks() * 4);

run_tests();

__DATA__

=== TEST 1: wss:// proxy over ws:// upstream
--- http_config eval
qq{
    $t::Tests::HttpConfig

    server {
        listen $ENV{TEST_NGINX_PORT2};

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

                ngx.log(ngx.INFO, "frame type: ", typ, ", payload: ", data)

                local bytes, err = wb:send_text(data)
                if not bytes then
                    ngx.log(ngx.ERR, "failed sending frame: ", err)
                    return ngx.exit(444)
                end
            }
        }
    }
}
--- config
    location /proxy {
        content_by_lua_block {
            local proxy = require "resty.websocket.proxy"

            local wp, err = proxy.new()
            if not wp then
                ngx.log(ngx.ERR, "failed creating proxy: ", err)
                return ngx.exit(444)
            end

            local ok, err = wp:connect("wss://127.0.0.1:9001/upstream")
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

            wb:connect(uri)
        }
    }
--- ignore_response_body
--- error_log
SSL_do_handshake() failed
failed connecting to upstream: ssl handshake failed: handshake failed
--- no_error_log
runtime error
