module("luci.controller.simmanager", package.seeall)

local function trim(value)
	if type(value) ~= "string" then
		return value
	end
	return value:match("^%s*(.-)%s*$")
end

local function read_json(path)
	local fs = require "nixio.fs"
	local jsonc = require "luci.jsonc"
	local raw = fs.readfile(path)
	if not raw or raw == "" then
		return {}
	end
	local parsed = jsonc.parse(raw)
	return type(parsed) == "table" and parsed or {}
end

local function first_value(data, keys)
	for _, key in ipairs(keys) do
		local value = trim(data[key])
		if value ~= nil and tostring(value) ~= "" then
			return value
		end
	end
	return nil
end

local function radio_value(value)
	if value == nil or tostring(value) == "" or tostring(value) == "0" then
		return nil
	end
	return value
end

function index()
	entry({"admin", "network", "simmanager"}, alias("admin", "network", "simmanager", "dashboard"), _("SIM Manager"), 16)
	entry({"admin", "network", "simmanager", "dashboard"}, template("simmanager/dashboard"), _("Dashboard"), 1)
	entry({"admin", "network", "simmanager", "profiles"}, cbi("simmanager/profiles"), _("SIM Profiles"), 2)
	entry({"admin", "network", "simmanager", "status"}, call("action_status")).leaf = true
end

function action_status()
	local http = require "luci.http"
	local jsonc = require "luci.jsonc"
	local sys = require "luci.sys"
	local uci = require "luci.model.uci".cursor()
	local fs = require "nixio.fs"
	local status = read_json("/tmp/4ginfo")
	local live = jsonc.parse(sys.exec("/usr/sbin/simmanager-status 2>/dev/null")) or {}
	local active_sim = uci:get("cellular", "cellular", "hw_sim") or "unknown"
	local profile_section = (active_sim == "sim1" or active_sim == "sim2") and active_sim or nil
	local profile_number = profile_section and uci:get("simmanager", profile_section, "phone_number") or nil
	local live_number = first_value(live, { "phone_number" }) or first_value(status, { "msisdn", "phone_number", "sim_number", "cnum" })
	local stat = fs.stat("/tmp/4ginfo")
	local rsrp = radio_value(live.rsrp) or radio_value(status.rsrp)

	local payload = {
		available = next(status) ~= nil or next(live) ~= nil,
		read_only = true,
		updated_at = stat and stat.mtime or nil,
		active_sim = active_sim,
		active_sim_title = uci:get("hw_info", "cellular", active_sim == "sim2" and "s2_title" or "s_title"),
		profile_name = profile_section and uci:get("simmanager", profile_section, "name") or nil,
		phone_number = live_number or profile_number,
		phone_number_source = live_number and "modem" or (profile_number and "profile" or "unavailable"),
		operator = first_value(status, { "isp", "operator" }),
		mccmnc = status.mccmnc,
		network_mode = status.nwmode,
		registration = live.registration or status.cgreg,
		signal_percent = rsrp and (live.signal_percent or status.signal) or nil,
		rsrp = rsrp,
		rsrq = radio_value(live.rsrq),
		rssi = radio_value(live.rssi),
		sinr = radio_value(live.sinr),
		nr_rsrp = radio_value(live.nr_rsrp),
		nr_rsrq = radio_value(live.nr_rsrq),
		nr_sinr = radio_value(live.nr_sinr),
		current_band = status.currband,
		cell_id = radio_value(live.cell_id) or radio_value(status.cellid),
		pci = radio_value(live.pci) or radio_value(status.pcid),
		frequency = radio_value(live.earfcn) or radio_value(status.freq),
		nr_pci = radio_value(live.nr_pci),
		nr_frequency = radio_value(live.nr_arfcn),
		lte_band = radio_value(live.lte_band),
		nr_band = radio_value(live.nr_band),
		apn = first_value(live, { "apn" }) or status.apn,
		sim_status = status.pin,
		iccid = status.iccid,
		device_model = status.device_model,
		imei = status.imei,
		scan_mode = status.scanmode,
		query_port = live.query_port,
		supported_bands = {
			wcdma = status.gwbandval,
			lte = status.ltebandval,
			nsa_5g = status.nsanr5gbandval,
			sa_5g = status.nr5gbandval
		}
	}

	local function sim_details(slot)
		local is_active = active_sim == slot
		local details = {
			slot = slot,
			title = uci:get("hw_info", "cellular", slot == "sim2" and "s2_title" or "s_title") or string.upper(slot),
			active = is_active,
			profile_name = uci:get("simmanager", slot, "name"),
			phone_number = uci:get("simmanager", slot, "phone_number"),
			profile_apn = uci:get("simmanager", slot, "apn"),
			apn_auto = uci:get("simmanager", slot, "apn_auto"),
			pdp_type = uci:get("simmanager", slot, "pdp_type"),
			network_mode = uci:get("simmanager", slot, "network_mode"),
			band_auto = uci:get("simmanager", slot, "band_auto"),
			bands = uci:get("simmanager", slot, "bands")
		}

		if is_active then
			details.phone_number = payload.phone_number or details.phone_number
			details.phone_number_source = payload.phone_number_source
			details.operator = payload.operator
			details.mccmnc = payload.mccmnc
			details.sim_status = payload.sim_status
			details.current_apn = payload.apn
			details.iccid = payload.iccid
			details.network_type = payload.network_mode
			details.signal_percent = payload.signal_percent
			details.rsrp = payload.rsrp
			details.current_band = payload.current_band
			details.cell_id = payload.cell_id
			details.pci = payload.pci
		end

		return details
	end

	payload.sims = {
		sim1 = sim_details("sim1"),
		sim2 = sim_details("sim2")
	}

	http.prepare_content("application/json")
	http.write(jsonc.stringify(payload))
end

