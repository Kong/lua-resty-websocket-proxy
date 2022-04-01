# vim:set ts=4 sts=4 sw=4 et ft=:

use Test::Nginx::Socket::Lua;
use Cwd qw(cwd);

plan tests => repeat_each() * (blocks() * 4);

my $pwd = cwd();

our $HttpConfig = qq{
    lua_package_path "$pwd/lib/?.lua;$pwd/misc/lua-resty-websocket/lib/?.lua;;";
};

log_level('info');
no_long_string();

run_tests();

__DATA__

=== TEST 1: calling connect_upstream() while already established logs a warning
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

            local wb, err = proxy.new({debug = true})
            if not wb then
                ngx.log(ngx.ERR, "failed creating proxy: ", err)
                return ngx.exit(444)
            end

            local uri = "ws://127.0.0.1:" .. ngx.var.server_port .. "/upstream"
            local ok, err = wb:connect(uri)
            if not ok then
                ngx.log(ngx.ERR, err)
                return ngx.exit(444)
            end

            assert(wb:connect_upstream(uri))

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
--- grep_error_log eval: qr/\[(info|warn)\].*/
--- grep_error_log_out eval
qr/\A\[warn\] .*? connection with upstream at "ws:.*?" already established.*
\[info\] .*? frame type: text, payload: "hello world!"/
--- no_error_log
[error]



=== TEST 2: calling connect_client() while client handshake already completed logs a warning
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

            local wb, err = proxy.new({debug = true})
            if not wb then
                ngx.log(ngx.ERR, "failed creating proxy: ", err)
                return ngx.exit(444)
            end

            local uri = "ws://127.0.0.1:" .. ngx.var.server_port .. "/upstream"
            local ok, err = wb:connect(uri)
            if not ok then
                ngx.log(ngx.ERR, err)
                return ngx.exit(444)
            end

            assert(wb:connect_client(uri))

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
--- grep_error_log eval: qr/\[(info|warn)\].*/
--- grep_error_log_out eval
qr/\A\[warn\] .*? client handshake already completed.*
\[info\] .*? frame type: text, payload: "hello world!"/
--- no_error_log
[error]



=== TEST 3: calling execute() without having completed the client handshake
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
        }
    }

    location /proxy {
        content_by_lua_block {
            local proxy = require "resty.websocket.proxy"

            local wb, err = proxy.new({debug = true})
            if not wb then
                ngx.log(ngx.ERR, "failed creating proxy: ", err)
                return ngx.exit(444)
            end

            local uri = "ws://127.0.0.1:" .. ngx.var.server_port .. "/upstream"
            local ok, err = wb:connect_upstream(uri)
            if not ok then
                ngx.log(ngx.ERR, "failed connecting to upstream: ", err)
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
            local ok, err = wb:connect(uri)
            if not ok then
                return ngx.exit(500)
            end
        }
    }
--- request
GET /t
--- error_code: 500
--- ignore_response_body
--- grep_error_log eval: qr/\[error\].*/
--- grep_error_log_out eval
qr/\A\[error\] .*? failed proxying: client handshake not complete.*/
--- no_error_log
[crit]
[emerg]



=== TEST 4: calling execute() without having established the upstream connection
--- http_config eval: $::HttpConfig
--- config
    location /proxy {
        content_by_lua_block {
            local proxy = require "resty.websocket.proxy"

            local wb, err = proxy.new({debug = true})
            if not wb then
                ngx.log(ngx.ERR, "failed creating proxy: ", err)
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
            local ok, err = wb:connect(uri)
            if not ok then
                return ngx.exit(500)
            end
        }
    }
--- request
GET /t
--- response_body
--- grep_error_log eval: qr/\[error\].*/
--- grep_error_log_out eval
qr/\A\[error\] .*? failed proxying: upstream connection not established.*/
--- no_error_log
[crit]
