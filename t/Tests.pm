package t::Tests;

use strict;
use Test::Nginx::Socket::Lua -Base;
use Cwd qw(cwd);

our $pwd = cwd();

# TODO: switch to unix sockets once supported by lua-resty-websocket
#   -> will conflict when using TEST_NGINX_RANDOMIZE
$ENV{TEST_NGINX_PORT_UPSTREAM} ||= 1985;
$ENV{TEST_NGINX_PORT2} ||= 9001;
$ENV{TEST_NGINX_CERT_DIR} ||= File::Spec->catdir(server_root(), '..', 'certs');

our $HttpConfig = qq{
    lua_package_path "$pwd/lib/?.lua;$pwd/misc/lua-resty-websocket/lib/?.lua;;";

    init_worker_by_lua_block {
        local proxy = require "resty.websocket.proxy"

        proxy._tests = {
            echo = "ws://127.0.0.1:$ENV{TEST_NGINX_PORT_UPSTREAM}/echo",
            pong = "ws://127.0.0.1:$ENV{TEST_NGINX_PORT_UPSTREAM}/pong",
        }
    }

    server {
        listen $ENV{TEST_NGINX_PORT_UPSTREAM};

        location /echo {
            content_by_lua_block {
                local server = require "resty.websocket.server"

                local wb, err = server:new()
                if not wb then
                    ngx.log(ngx.ERR, "failed creating server: ", err)
                    return ngx.exit(444)
                end

                local once = not ngx.var.arg_repeat

                repeat
                    local data, typ, err = wb:recv_frame()
                    if not data then
                        ngx.log(ngx.ERR, "failed receiving frame: ", err)
                        return ngx.exit(444)
                    end

                    ngx.log(ngx.INFO, "frame type: ", typ,
                              ", payload: \\"", data,
                              "\\"")

                    local bytes, err
                    if typ == "close" then
                        bytes, err = wb:send_close(err, data)
                    else
                        bytes, err = wb:send_text(data)
                    end

                    if not bytes then
                        ngx.log(ngx.ERR, "failed sending frame: ", err)
                        return ngx.exit(444)
                    end
                until typ == "close" or once
            }
        }

        location /pong {
            content_by_lua_block {
                local server = require "resty.websocket.server"

                local wb, err = server:new()
                if not wb then
                    ngx.log(ngx.ERR, "failed creating server: ", err)
                    return ngx.exit(444)
                end

                local once = not ngx.var.arg_repeat

                repeat
                    local data, typ, err = wb:recv_frame()
                    if not data then
                        ngx.log(ngx.ERR, "failed receiving frame: ", err)
                        return ngx.exit(444)
                    end

                    ngx.log(ngx.INFO, "frame type: ", typ,
                            ", payload: \\"", data, "\\"")

                    local bytes, err = wb:send_pong("heartbeat server")
                    if not bytes then
                        ngx.log(ngx.ERR, "failed sending frame: ", err)
                        return ngx.exit(444)
                    end
                until typ == "close" or once
            }
        }
    }
};

our @EXPORT = qw(
    $pwd
    $HttpConfig
);

add_block_preprocessor(sub {
    my $block = shift;

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }
});

log_level('info');
no_long_string();

1;
