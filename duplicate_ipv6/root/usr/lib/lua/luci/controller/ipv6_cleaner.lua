module("luci.controller.ipv6_cleaner", package.seeall)

function index()
    -- Modern LuCI uses menu.d and the JavaScript view instead.
    if nixio.fs.access("/www/luci-static/resources/view.js") then return end
    if not nixio.fs.access("/etc/config/ipv6_cleaner") then return end
    entry({"admin", "services", "ipv6-cleaner"}, cbi("ipv6_cleaner"), _("IPv6 Cleaner"), 65).leaf = true
end
