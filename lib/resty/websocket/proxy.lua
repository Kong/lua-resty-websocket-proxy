local new_tab = require "table.new"
local clear_tab = require "table.clear"
local ws_client = require "resty.websocket.client"
local ws_server = require "resty.websocket.server"


local type = type
local setmetatable = setmetatable
local insert = table.insert
local concat = table.concat
local yield = coroutine.yield
local fmt = string.format
local sub = string.sub
local gsub = string.gsub
local find = string.find
local log = ngx.log


local _DEBUG_PAYLOAD_MAX_LEN = 24
local _PROXY_STATES = {
    INIT = 0,
    ESTABLISHED = 1,
    CLOSING = 2,
}

local _TYP2OPCODE = {
    ["continuation"] = 0x0,
    ["text"] = 0x1,
    ["binary"] = 0x2,
    ["close"] = 0x8,
    ["ping"] = 0x9,
    ["pong"] = 0xa,
}


local _M     = {
    _VERSION = "0.0.1",
}

local _mt = { __index = _M }


function _M.new(opts)
    if opts == nil then
        opts = new_tab(0, 0)
    end

    if type(opts) ~= "table" then
        error("opts must be a table", 2)
    end

    if type(opts.upstream) ~= "string" then
        error("opts.upstream must be a string", 2)
    end

    if opts.on_frame ~= nil and type(opts.on_frame) ~= "function" then
        error("opts.on_frame must be a function", 2)
    end

    if opts.recv_timeout ~= nil and type(opts.recv_timeout) ~= "number" then
        error("opts.recv_timeout must be a number", 2)
    end

    local server, err = ws_server:new()
    if not server then
        return nil, "failed to create server: " .. err
    end

    local client, err = ws_client:new()
    if not client then
        return nil, "failed to create client: " .. err
    end

    local self = {
        server = server,
        client = client,
        upstream = opts.upstream,
        on_frame = opts.on_frame,
        recv_timeout = opts.recv_timeout,
        aggregate_fragments = opts.aggregate_fragments,
        debug = opts.debug,
        state = _PROXY_STATES.INIT,
        co_client = nil,
        co_server = nil,
    }

    return setmetatable(self, _mt)
end


function _M:dd(...)
    if self.debug then
        return log(ngx.DEBUG, ...)
    end
end


local function forwarder(self, ctx)
    local role = ctx.role
    local buf = ctx.buf
    local self_ws, peer_ws

    assert(self.state == _PROXY_STATES.ESTABLISHED)

    if role == "client" then
        self_ws = self.server
        peer_ws = self.client

    else
        -- role == "upstream"
        self_ws = self.client
        peer_ws = self.server
    end

    while true do
        if self.state == _PROXY_STATES.CLOSING then
            return
        end

        if self.recv_timeout then
            self_ws:set_timeout(self.recv_timeout)
        end

        self:dd(role, " receiving frame...")

        local data, typ, err = self_ws:recv_frame()
        if not data then
            if find(err, "timeout", 1, true) then
                log(ngx.INFO, fmt("timeout receiving frame from %s, reopening",
                                  role))
                -- continue

            elseif find(err, "closed", 1, true) then
                self.state = _PROXY_STATES.CLOSING
                return role

            else
                log(ngx.ERR, fmt("failed receiving frame from %s: %s",
                                 role, err))
                -- continue
            end
        end

        -- special flags

        local code
        local opcode = _TYP2OPCODE[typ]
        local fin = true
        if err == "again" then
            fin = false
            err = nil
        end

        if typ then
            if not opcode then
                log(ngx.EMERG, "NYI - unknown frame type: ", typ,
                               " (dropping connection)")
                return
            end

            if typ == "close" then
                code = err
            end

            -- debug

            if self.debug and (not err or typ == "close") then
                local arrow

                if typ == "close" then
                    arrow = role == "client" and "--x" or "x--"

                else
                    arrow = role == "client" and "-->" or "<--"
                end

                local payload = data and gsub(data, "\n", "\\n") or ""
                if #payload > _DEBUG_PAYLOAD_MAX_LEN then
                    payload = sub(payload, 1, _DEBUG_PAYLOAD_MAX_LEN) .. "[...]"
                end

                local extra = ""
                if code then
                    extra = fmt("\n  code: %d", code)
                end

                self:dd(fmt("\n[frame] downstream %s resty.proxy %s upstream\n" ..
                            "  type: \"%s\"\n" ..
                            "  payload: %s (len: %d)%s\n" ..
                            "  fin: %s",
                            arrow, arrow,
                            typ,
                            fmt("%q", payload), data and #data or 0, extra,
                            fin))
            end

            local bytes
            local forward = true

            -- fragmentation

            if self.aggregate_fragments then
                if not fin then
                    self:dd(role, " received fragmented frame, buffering")
                    insert(buf, data)
                    forward = false
                    -- continue

                elseif #buf > 0 then
                    self:dd(role, " received last fragmented frame, forwarding")
                    insert(buf, data)
                    data = concat(buf, "")
                    clear_tab(buf)
                end
            end

            -- forward

            if forward then

                -- callback

                if self.on_frame then
                    local updated = self.on_frame(role, typ, data, fin)
                    if updated ~= nil then
                        if type(updated) ~= "string" then
                            error("opts.on_frame return value must be " ..
                                  "nil or a string")
                        end

                        data = updated
                    end
                end

                if typ == "close" then
                    log(ngx.INFO, "forwarding close with code: ", code, ", payload: ",
                                  data)

                    bytes, err = peer_ws:send_close(code, data)

                else
                    bytes, err = peer_ws:send_frame(fin, opcode, data)
                end

                if not bytes then
                    log(ngx.ERR, fmt("failed forwarding a frame from %s: %s",
                                     role, err))
                    -- continue
                end
            end
        end

        self:dd(role, " yielding")

        yield(self)
    end
end


function _M:execute()
    assert(self.state == _PROXY_STATES.INIT)

    self:dd("connecting to \"", self.upstream, "\" upstream")

    local ok, err = self.client:connect(self.upstream)
    if not ok then
        return nil, "failed to connect client: " .. err
    end

    self.state = _PROXY_STATES.ESTABLISHED

    self:dd("connected to \"", self.upstream, "\" upstream")

    self.co_client = ngx.thread.spawn(forwarder, self, {
        role = "client",
        buf = new_tab(0, 0),
    })

    self.co_server = ngx.thread.spawn(forwarder, self, {
        role = "upstream",
        buf = new_tab(0, 0),
    })

    local ok, res = ngx.thread.wait(self.co_client, self.co_server)
    if not ok then
        log(ngx.ERR, "failed to wait for threads: ", res)

    elseif res == "client" then
        assert(self.state == _PROXY_STATES.CLOSING)

        self:dd(res, " thread terminated, killing server thread")

        ngx.thread.kill(self.co_server)

        self:dd("closing \"", self.upstream, "\" upstream websocket")

        self.client:close()

    elseif res == "upstream" then
        assert(self.state == _PROXY_STATES.CLOSING)

        self:dd(res, " thread terminated, killing client thread")

        ngx.thread.kill(self.co_client)
    end

    self.state = _PROXY_STATES.INIT

    return true
end


return _M
