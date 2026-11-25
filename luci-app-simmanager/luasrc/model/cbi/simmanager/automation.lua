local fs = require "nixio.fs"
local jsonc = require "luci.jsonc"
local sys = require "luci.sys"
local uci = require "luci.model.uci".cursor()

local m = Map("simmanager", translate("Automatic Switching"),
	translate("Automatic switching is disabled by default. It detects sustained connectivity loss and repeated disconnects, recovers the active profile once, then uses the existing backup-and-rollback activation path to move to the other SIM. Data-usage exhaustion is not evaluated."))

local layout = m:section(SimpleSection)
layout.template = "simmanager/automation_style"

local s = m:section(NamedSection, "automation", "automation", translate("Failover policy"))
s.anonymous = true
s.addremove = false

local enabled = s:option(Flag, "enabled", translate("Enable automatic switching"),
	translate("Cannot be enabled while the router's built-in Automatic SIM card switching option is active."))
enabled.rmempty = false
enabled.default = enabled.disabled
function enabled.validate(self, value, section)
	if value == "1" and uci:get("cellular", "cellular", "hw_asw") == "1" then
		return nil, translate("Disable Automatic SIM card switching on the vendor Cellular Network page before enabling this controller.")
	end
	return Flag.validate(self, value, section)
end

local default_sim = s:option(ListValue, "default_sim", translate("Default SIM"),
	translate("The preferred primary SIM. After failover, the controller tests this SIM again after 6, 12, 18 and 24 hours."))
default_sim:value("sim1", translate("SIM Card 1"))
default_sim:value("sim2", translate("SIM Card 2"))
default_sim.default = "sim1"
default_sim.rmempty = false

local failure = s:option(Value, "failure_seconds", translate("Sustained failure time"),
	translate("Internet checks must continuously fail for this duration before recovery and failover are considered."))
failure.datatype = "range(10,120)"
failure.default = "20"
failure.rmempty = false
failure:value("10", translate("10 seconds — aggressive"))
failure:value("15", translate("15 seconds"))
failure:value("20", translate("20 seconds — recommended"))
failure:value("30", translate("30 seconds"))
failure:value("45", translate("45 seconds"))
failure:value("60", translate("60 seconds"))

local recover = s:option(Flag, "recover_before_failover", translate("Try current SIM recovery before switching"),
	translate("Disabled by default for faster client recovery. Enabling this may add one or more minutes before the standby SIM is tried."))
recover.rmempty = false
recover.default = recover.disabled

local disconnects = s:option(Value, "disconnect_limit", translate("Frequent disconnect threshold"),
	translate("A reconnect loop is declared when this many down transitions occur within the observation window."))
disconnects.datatype = "range(2,10)"
disconnects.default = "3"
disconnects.rmempty = false

local window = s:option(Value, "disconnect_window_minutes", translate("Disconnect observation window"))
window.datatype = "range(5,60)"
window.default = "10"
window.rmempty = false
window:value("5", translate("5 minutes"))
window:value("10", translate("10 minutes"))
window:value("15", translate("15 minutes"))
window:value("30", translate("30 minutes"))

local cooldown = s:option(Value, "cooldown_minutes", translate("Minimum switch cooldown"),
	translate("Prevents repeated SIM switching during an unstable network event."))
cooldown.datatype = "range(15,240)"
cooldown.default = "30"
cooldown.rmempty = false
cooldown:value("30", translate("30 minutes"))
cooldown:value("60", translate("1 hour"))
cooldown:value("120", translate("2 hours"))

local maximum = s:option(Value, "max_switches_per_day", translate("Maximum automatic switches per day"))
maximum.datatype = "range(1,12)"
maximum.default = "4"
maximum.rmempty = false

local schedule = s:option(DummyValue, "retry_schedule", translate("Primary retry schedule"))
schedule.rawhtml = true
schedule.cfgvalue = function()
	return "6 &rarr; 12 &rarr; 18 &rarr; 24 " .. translate("hours; subsequent retries remain every 24 hours")
end

local checks = s:option(DummyValue, "health_checks", translate("Connectivity proof"))
checks.cfgvalue = function()
	return translate("Three interface-bound probes run in parallel every 5 seconds. At least two must succeed. Signal strength alone never triggers a switch.")
end

local guard = s:option(DummyValue, "vendor_guard", translate("Vendor automatic switch"))
guard.cfgvalue = function()
	if uci:get("cellular", "cellular", "hw_asw") == "1" then
		local minutes = uci:get("cellular", "cellular", "hw_offtime") or "unknown"
		return translate("Enabled — this controller is blocked") .. " (" .. minutes .. " " .. translate("minute timer") .. ")"
	end
	return translate("Disabled — no controller conflict detected")
end

local status_data = jsonc.parse(fs.readfile("/tmp/simmanager-auto.json") or "") or {}
local status = m:section(SimpleSection, nil, translate("Runtime status"))

local state = status:option(DummyValue, "runtime_state", translate("State"))
state.cfgvalue = function() return status_data.state or translate("Stopped") end

local message = status:option(DummyValue, "runtime_message", translate("Message"))
message.cfgvalue = function() return status_data.message or translate("Automatic switching has not started.") end

local active = status:option(DummyValue, "runtime_active", translate("Active SIM"))
active.cfgvalue = function() return status_data.active_sim or uci:get("cellular", "cellular", "hw_sim") or translate("Unknown") end

local next_retry = status:option(DummyValue, "runtime_retry", translate("Next primary test"))
next_retry.cfgvalue = function()
	local stamp = tonumber(status_data.next_retry)
	return stamp and stamp > 0 and os.date("%Y-%m-%d %H:%M:%S", stamp) or translate("Not scheduled")
end

function m.on_after_commit(self)
	local committed = require "luci.model.uci".cursor():get("simmanager", "automation", "enabled")
	if committed == "1" then
		sys.call("/etc/init.d/simmanager-auto enable >/dev/null 2>&1")
		sys.call("/etc/init.d/simmanager-auto restart >/dev/null 2>&1")
	else
		sys.call("/etc/init.d/simmanager-auto stop >/dev/null 2>&1")
		sys.call("/etc/init.d/simmanager-auto disable >/dev/null 2>&1")
	end
end

return m
