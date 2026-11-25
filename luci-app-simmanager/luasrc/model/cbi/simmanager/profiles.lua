local map = Map("simmanager", translate("SIM Profiles"),
	translate("Profiles are stored independently. Saving this page does not switch SIMs, restart cellular service, or modify the vendor cellular configuration. Applying a profile is a separate, confirmed action on the Activate & Roll Back page."))

local function add_profile(section_name, title)
	local section = map:section(NamedSection, section_name, "profile", title)
	section.addremove = false
	section.anonymous = true

	local name = section:option(Value, "name", translate("Profile name"))
	name.placeholder = title

	local number = section:option(Value, "phone_number", translate("SIM phone number"),
		translate("Used as the dashboard fallback because many SIM cards do not expose MSISDN to the modem."))

	local auto_apn = section:option(Flag, "apn_auto", translate("Automatic APN"))
	auto_apn.default = auto_apn.disabled

	local apn = section:option(Value, "apn", translate("APN"),
		translate("Enter the APN for this SIM. When Automatic APN is enabled, the vendor service may replace this value during activation."))
	apn.placeholder = "example.apn"

	local pdp = section:option(ListValue, "pdp_type", translate("PDP type"))
	pdp:value("IP", "IPv4")
	pdp:value("IPV6", "IPv6")
	pdp:value("IPV4V6", "IPv4 & IPv6")
	pdp.default = "IPV4V6"

	local pin = section:option(Value, "pin", translate("SIM PIN"))
	pin.password = true

	local auth_enabled = section:option(Flag, "auth_enabled", translate("APN authentication"))
	auth_enabled.default = auth_enabled.disabled

	local username = section:option(Value, "username", translate("Username"))
	username:depends("auth_enabled", "1")

	local password = section:option(Value, "password", translate("Password"))
	password.password = true
	password:depends("auth_enabled", "1")

	local auth = section:option(ListValue, "auth_type", translate("Authentication type"))
	auth:value("0", translate("None"))
	auth:value("1", "PAP")
	auth:value("2", "CHAP")
	auth:value("3", "PAP & CHAP")
	auth.default = "3"
	auth:depends("auth_enabled", "1")

	local mode = section:option(ListValue, "network_mode", translate("Preferred network mode"))
	mode:value("AUTO", translate("Automatic"))
	mode:value("LTE", translate("LTE only"))
	mode:value("NR5G:LTE", translate("5G NSA only"))
	mode:value("NR5G", translate("5G SA only"))
	mode.default = "AUTO"

	local band_auto = section:option(Flag, "band_auto", translate("Automatic band selection"))
	band_auto.default = band_auto.enabled

	local bands = section:option(Value, "bands", translate("Preferred bands"),
		translate("Profile metadata only for now, for example: LTE B3,B40; NR n78. Activation is blocked unless automatic band selection is enabled."))
	bands:depends("band_auto", "0")

	local last_operator = section:option(DummyValue, "last_operator", translate("Last known operator"))
	last_operator.default = translate("Not observed yet")
	local last_iccid = section:option(DummyValue, "last_iccid", "ICCID")
	last_iccid.default = translate("Not observed yet")
	local last_apn = section:option(DummyValue, "last_apn", translate("Last known APN"))
	last_apn.default = translate("Not observed yet")
	local last_band = section:option(DummyValue, "last_band", translate("Last known serving bands"))
	last_band.default = translate("Not observed yet")
	local last_seen = section:option(DummyValue, "last_seen", translate("Last observed"))
	last_seen.rawhtml = true
	function last_seen.cfgvalue(self, section_id)
		local value = tonumber(self.map:get(section_id, self.option))
		return value and value > 0 and string.format('<span class="simmanager-local-time" data-epoch="%d"></span>', value) or translate("Not observed yet")
	end
end

add_profile("sim1", translate("SIM 1"))
add_profile("sim2", translate("SIM 2"))

local local_time = map:section(SimpleSection)
local_time.template = "simmanager/local_time"

return map

