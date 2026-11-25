#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

lua - "$project_dir" <<'LUA'
local project_dir = arg[1]
unpack = unpack or table.unpack
package.preload["nixio.fs"] = function() return {} end
package.preload["luci.jsonc"] = function() return {} end
package.path = project_dir .. "/luci-app-simmanager/root/usr/lib/lua/?.lua;" ..
	project_dir .. "/luci-app-simmanager/root/usr/lib/lua/?/init.lua;" .. package.path

local sms = require "simmanager.sms"
local decoded, err = sms.decode_pdu("00040A9121436587090008621152410300000400480069")
assert(decoded, err)
assert(decoded.number == "+1234567890")
assert(decoded.text == "Hi")
assert(decoded.service_time == "2026-11-25 14:30:00")

local single = assert(sms.encode_submit("+919876543210", "Hello"))
assert(#single == 1 and single[1].length > 0)

local multipart = assert(sms.encode_submit("+919876543210", string.rep("அ", 150)))
assert(#multipart == 3)
assert(multipart[1].hex:sub(3, 4) == "71")

local emoji = assert(sms.encode_submit("+919876543210", string.rep("😀", 70)))
assert(#emoji == 3)
for _, part in ipairs(emoji) do assert(part.length <= 152) end

print("SMS codec tests passed")
LUA
