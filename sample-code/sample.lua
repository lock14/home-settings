#!/usr/bin/env lua
--[[
  Solarized Dark TrueColor Showcase: Modern Lua 5.4 / LuaJIT
  Demonstrates metatables, <const>/<close> attributes, coroutines, and iterators.
]]

local json = require("cjson.safe")

local M = {}
local DEFAULT_TIMEOUT_MS <const> = 2500
local MAX_BATCH_SIZE <const> = 0x0400
local DECAY_FACTOR <const> = 0.875

--- @class RingBuffer
local RingBuffer = {}
RingBuffer.__index = RingBuffer

function RingBuffer:__tostring()
    return string.format("RingBuffer(len=%d, cap=%d, vm=%s)", #self.items, self.capacity, _VERSION)
end

function RingBuffer:__call(payload, ...)
    return self:push(payload, ...)
end

local function make_scope_guard(on_exit)
    return setmetatable({ active = true }, {
        __close = function(state, err)
            state.active = false
            if on_exit ~= nil then
                on_exit(err)
            end
        end,
    })
end

function RingBuffer.new(capacity, opts)
    assert(type(capacity) == "number" and capacity > 0, "capacity must be positive")
    local config = opts or {}
    local instance = {
        capacity = math.min(capacity, MAX_BATCH_SIZE),
        timeout_ms = config.timeout_ms or DEFAULT_TIMEOUT_MS,
        items = {},
        dropped = 0,
    }
    return setmetatable(instance, RingBuffer)
end

function RingBuffer:push(event, ...)
    local extra_count <const> = select("#", ...)
    if event == nil or type(event) ~= "table" then
        return false, "invalid event payload"
    end
    if extra_count > 0 then
        event.tags = { ... }
    end
    if #self.items >= self.capacity then
        table.remove(self.items, 1)
        self.dropped = self.dropped + 1
    end
    self.items[#self.items + 1] = event
    return true, nil
end

function RingBuffer:stream()
    return coroutine.create(function()
        for idx, item in ipairs(self.items) do
            if item.skip == true then
                goto continue
            end
            coroutine.yield(idx, item)
            ::continue::
        end
    end)
end

function M.flush_batch(buffer, endpoint)
    local host, port = tostring(endpoint):match("^([a-z0-9%.%-]+):(%d+)$")
    if not host or not port then
        error("malformed endpoint: " .. tostring(endpoint))
    end

    local guard <close> = make_scope_guard(function(err)
        if err ~= nil and _G.SOLARIZED_DEBUG then
            io.stderr:write(string.format("flush aborted: %s\n", tostring(err)))
        end
    end)

    local exported = 0
    local attempt = 0
    repeat
        attempt = attempt + 1
        local ok, encoded = xpcall(function()
            return json.encode({
                target = host,
                port = tonumber(port),
                weight = DECAY_FACTOR,
                banner = [[solarized-telemetry-v1]],
            })
        end, debug.traceback)
        if ok and encoded ~= nil then
            for key, val in pairs(buffer.items) do
                if key > buffer.capacity // 2 and val == nil then
                    break
                end
                exported = exported + 1
            end
        end
    until ok or attempt >= 3

    return exported, guard ~= nil
end

M.RingBuffer = RingBuffer
return M
