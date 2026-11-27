local sys = require "luci.sys"
local json = require "luci.jsonc"
local util = require "luci.util"
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
o:value("remove", translate("Remove deprecated addresses / restart stale IPv6 interface"))
o.description = translate("Removing an address can interrupt existing connections. Manual scans use the saved action even when scheduling is disabled.")
o = s:option(Flag, "stale_detection", translate("Check for stale ISP addresses"))
o.rmempty = false
o.description = translate("Checks preferred public /64 addresses with infinite lifetimes. Remove mode automatically rechecks and restarts only the owning logical IPv6 interface in about one minute when another address on the same WAN works. Monitor mode only reports them.")
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
o = s:option(Button, "_inspect", translate("Stale ISP diagnostics"))
o.inputtitle = translate("Check WAN addresses now")
function o.write()
    sys.call("/usr/libexec/ipv6-cleaner-diagnostics run </dev/null >/dev/null 2>&1 &")
    m.message = translate("WAN checks started. Reload this page for results.")
end
for i, finding in ipairs(status.data.diagnostics or {}) do
    if finding.verdict == "suspected_stale" then
        local item = finding
        local confirm = s:option(Flag, "_confirm_stale_" .. i, translate("Confirm IPv6-only restart for ") .. item.address)
        confirm.description = translate("Only this logical DHCPv6 interface restarts. IPv4 and other WANs stay running.")
        function confirm.cfgvalue() return "0" end
        function confirm.write() end
        function confirm.remove() end
        local remove = s:option(Button, "_remove_stale_" .. i, translate("Restart IPv6 interface"))
        remove.inputtitle = translate("Recheck and restart IPv6")
        function remove.write(self, section)
            if confirm:formvalue(section) ~= "1" then
                m.message = translate("Tick the confirmation checkbox first.")
                return
            end
            local result = json.parse(sys.exec("/usr/libexec/ipv6-cleaner-diagnostics restart " .. util.shellquote(item.device) .. " " .. util.shellquote(item.address) .. " confirmed")) or {}
            m.message = result.error or translate("Logical IPv6 interface restarted.")
        end
    end
end
function m.on_after_commit()
    sys.call("/etc/init.d/ipv6-cleaner reload >/dev/null 2>&1")
end
return m
