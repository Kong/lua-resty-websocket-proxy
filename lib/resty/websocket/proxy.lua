local new_tab = require "table.new"
local ws_client = require "resty.websocket.client"
local ws_server = require "resty.websocket.server"


local type = type
local setmetatable = setmetatable
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


local function forwarder(self, role)
    local self_ws, peer_ws, peer_role

    assert(self.state == _PROXY_STATES.ESTABLISHED)

    if role == "upstream" then
        self_ws = self.server
        peer_ws = self.client
        peer_role = "downstream"

    else
        -- role == "downstream"
        self_ws = self.client
        peer_ws = self.server
        peer_role = "upstream"
    end

    while true do
        if self.state == _PROXY_STATES.CLOSING then
            return
        end

        local data, typ, err = self_ws:recv_frame()
        if not data then
            if find(err, "timeout", 1, true) then
                -- continue

            elseif find(err, "closed", 1, true) then
                self.state = _PROXY_STATES.CLOSING
                return peer_role

            else
                log(ngx.ERR, fmt("failed receiving a frame from %s: %s",
                                 peer_role, err))
                -- continue
            end
        end

        -- special flags

        local code
        local fin = err ~= "again"
        local opcode = _TYP2OPCODE[typ]

        if opcode == nil then
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
                arrow = role == "upstream" and "--x" or "x--"

            else
                arrow = role == "upstream" and "-->" or "<--"
            end

            local payload = data and gsub(data, "\n", "\\n") or ""
            if #payload > _DEBUG_PAYLOAD_MAX_LEN then
                payload = sub(payload, 1, _DEBUG_PAYLOAD_MAX_LEN)
                              .. "[...]"
            end

            local extra
            if code then
                extra = fmt("\n  code: %d", code)
            end

            self:dd(fmt("\n[frame] downstream %s resty.proxy %s upstream\n" ..
                        "  type: \"%s\"\n" ..
                        "  payload: %s (len: %d)%s",
                        arrow, arrow,
                        typ,
                        fmt("%q", payload), data and #data or 0, extra or ""))
        end

        -- forward

        local bytes

        if typ == "close" then
            log(ngx.INFO, "forwarding close with code: ", code, ", payload: ",
                          data)

            bytes, err = peer_ws:send_close(code, data)

        else
            bytes, err = peer_ws:send_frame(fin, opcode, data)
        end

        if not bytes then
            log(ngx.ERR, fmt("failed forwarding a frame from %s: %s",
                             peer_role, err))
            -- continue
        end

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

    self.co_client = ngx.thread.spawn(forwarder, self, "downstream")
    self.co_server = ngx.thread.spawn(forwarder, self, "upstream")

    local ok, res = ngx.thread.wait(self.co_client, self.co_server)
    if not ok then
        log(ngx.ERR, "failed to wait for threads: ", res)

    elseif res == "downstream" then
        assert(self.state == _PROXY_STATES.CLOSING)

        self:dd("killing co_server thread")

        ngx.thread.kill(self.co_server)

        self:dd("closing \"", self.upstream, "\" upstream websocket")

        self.client:close()

    elseif res == "upstream" then
        assert(self.state == _PROXY_STATES.CLOSING)

        self:dd("killing co_client thread")

        ngx.thread.kill(self.co_client)
    end

    self.state = _PROXY_STATES.INIT

    return true
end


return _M
