# vim:set ts=4 sts=4 sw=4 et ft=:

use Test::Nginx::Socket::Lua;
use Cwd qw(cwd);

$ENV{TEST_NGINX_CERT_DIR} ||= File::Spec->catdir(server_root(), '..', 'certs');
$ENV{TEST_NGINX_PORT2}   ||= 9001;

plan tests => repeat_each() * (blocks() * 4);

my $pwd = cwd();

our $HttpConfig = qq{
    lua_package_path "$pwd/lib/?.lua;$pwd/misc/lua-resty-websocket/lib/?.lua;;";
};

log_level('info');

run_tests();

__DATA__

=== TEST 1: wss:// proxy over ws:// upstream
--- http_config eval
qq{
    $::HttpConfig

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
            local wb, err = proxy.new({
                upstream = "wss://127.0.0.1:9001/upstream",
                debug = true,
            })
            if not wb then
                ngx.log(ngx.ERR, "failed creating proxy: ", err)
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

            wb:connect(uri)
        }
    }
--- request
GET /t
--- ignore_response_body
--- error_log
SSL_do_handshake() failed
failed proxying: failed to connect client: ssl handshake failed: handshake failed
--- no_error_log
runtime error
