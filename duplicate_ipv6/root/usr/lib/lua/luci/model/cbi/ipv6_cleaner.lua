local sys = require "luci.sys"
local json = require "luci.jsonc"
local m = Map("ipv6_cleaner", translate("IPv6 Cleaner"),
    translate("Automatically discovers all IPv6 devices. Only explicitly deprecated global unicast addresses in 2000::/3 qualify; ULA, link-local, tentative and failed addresses are excluded."))

local status = m:section(SimpleSection)
status.template = "ipv6_cleaner/status"
status.data = json.parse(sys.exec("/usr/sbin/ipv6-cleaner status")) or {}

local s = m:section(NamedSection, "main", "cleaner", translate("Settings"))
s.addremove = false
local o = s:option(Flag, "enabled", translate("Enable scheduled scans"))
o.rmempty = false
o = s:option(ListValue, "mode", translate("Action"))
o:value("monitor", translate("Monitor only (safe default)"))
o:value("remove", translate("Remove deprecated public IPv6 addresses"))
o.description = translate("Removing an address can interrupt existing connections. Manual scans use the saved action even when scheduling is disabled.")
o = s:option(Value, "interval", translate("Scan frequency (seconds)"))
o:value("120", translate("2 minutes (suggested)"))
o:value("300", translate("5 minutes"))
o.datatype = "range(60,86400)"
o.rmempty = false
o.description = translate("Select a suggestion or enter a custom interval from 60 to 86400 seconds. Save & Apply restarts the schedule.")
o = s:option(Button, "_scan", translate("Manual scan"))
o.inputtitle = translate("Run saved action now")
o.inputstyle = "apply"
function o.write()
    local result = json.parse(sys.exec("/usr/sbin/ipv6-cleaner run")) or {}
    if result.error then
        m.message = result.error
    else
        m.message = translate("Scan finished. Reload the page to see the latest results.")
    end
end
function m.on_after_commit()
    sys.call("/etc/init.d/ipv6-cleaner reload >/dev/null 2>&1")
end
return m
