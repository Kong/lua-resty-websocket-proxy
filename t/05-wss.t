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

=== TEST 1: forward a text frame back and forth over wss
--- http_config eval
qq{
    $::HttpConfig

    server {
        listen $ENV{TEST_NGINX_PORT2} ssl;
        ssl_certificate $ENV{TEST_NGINX_CERT_DIR}/cert.pem;
        ssl_certificate_key $ENV{TEST_NGINX_CERT_DIR}/key.pem;

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
qr/frame type: text, payload: hello world!/
--- no_error_log
[error]