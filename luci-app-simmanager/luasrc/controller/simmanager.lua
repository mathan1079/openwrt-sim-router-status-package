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

local function signal_quality(rsrp)
	local value = tonumber(rsrp)
	if not value then return nil end
	if value >= -80 then return "excellent" end
	if value >= -90 then return "good" end
	if value >= -100 then return "fair" end
	if value >= -110 then return "poor" end
	return "very_poor"
end

local function persist_last_known(uci, slot, payload, status_mtime)
	if slot ~= "sim1" and slot ~= "sim2" then return false end
	if payload.sim_status ~= "READY" or not first_value(payload, { "iccid" }) then return false end

	local fs = require "nixio.fs"
	local marker_path = "/tmp/simmanager-observer-slot"
	local now = os.time()
	local marker = trim(fs.readfile(marker_path) or "")
	local marked_slot, marked_at = marker:match("^(sim[12])%s+(%d+)$")

	if marked_slot ~= slot then
		fs.writefile(marker_path, slot .. " " .. tostring(now) .. "\n")
		return false
	end

	local marker_time = tonumber(marked_at) or now
	local known_iccid = uci:get("simmanager", slot, "last_iccid")
	local identity_confirmed = known_iccid and tostring(payload.iccid) == tostring(known_iccid)
	if not identity_confirmed and (now - marker_time < 15 or (tonumber(status_mtime) or 0) <= marker_time) then
		return false
	end

	local signature = table.concat({
		tostring(payload.iccid or ""), tostring(payload.operator or ""),
		tostring(payload.apn or ""), tostring(payload.network_mode or ""),
		tostring(payload.current_band or "")
	}, "|")
	local changed = uci:get("simmanager", slot, "last_signature") ~= signature

	if changed then
		local values = {
			last_signature = signature,
			last_seen = tostring(now),
			last_operator = payload.operator,
			last_mccmnc = payload.mccmnc,
			last_iccid = payload.iccid,
			last_apn = payload.apn,
			last_network_type = payload.network_mode,
			last_signal_percent = payload.signal_percent,
			last_rsrp = payload.rsrp,
			last_band = payload.current_band,
			last_cell_id = payload.cell_id,
			last_pci = payload.pci
		}
		for key, value in pairs(values) do
			if value ~= nil and tostring(value) ~= "" then
				uci:set("simmanager", slot, key, tostring(value))
			end
		end
	end

	local profile_changed = false
	if not first_value({ value = uci:get("simmanager", slot, "apn") }, { "value" }) and first_value(payload, { "apn" }) then
		uci:set("simmanager", slot, "apn", tostring(payload.apn))
		profile_changed = true
	end
	if not first_value({ value = uci:get("simmanager", slot, "phone_number") }, { "value" }) and first_value(payload, { "phone_number" }) then
		uci:set("simmanager", slot, "phone_number", tostring(payload.phone_number))
		profile_changed = true
	end

	if changed or profile_changed then uci:commit("simmanager") end
	return true
end

function index()
	entry({"admin", "network", "simmanager"}, alias("admin", "network", "simmanager", "dashboard"), _("SIM Manager"), 16)
	entry({"admin", "network", "simmanager", "dashboard"}, template("simmanager/dashboard"), _("Dashboard"), 1)
	entry({"admin", "network", "simmanager", "profiles"}, cbi("simmanager/profiles"), _("SIM Profiles"), 2)
	entry({"admin", "network", "simmanager", "activation"}, template("simmanager/activation"), _("Activate / Roll Back"), 3)
	entry({"admin", "network", "simmanager", "automation"}, cbi("simmanager/automation"), _("Automatic Switching"), 4)
	entry({"admin", "network", "sim1sms"}, template("simmanager/sms"), _("SIM 1 SMS"), 17)
	entry({"admin", "network", "sim2sms"}, template("simmanager/sms"), _("SIM 2 SMS"), 18)
	entry({"admin", "network", "simmanager", "status"}, call("action_status")).leaf = true
	entry({"admin", "network", "simmanager", "control_status"}, call("action_control_status")).leaf = true
	entry({"admin", "network", "simmanager", "activate"}, post("action_activate")).leaf = true
	entry({"admin", "network", "simmanager", "rollback"}, post("action_rollback")).leaf = true
	entry({"admin", "network", "simmanager", "sms_summary"}, call("action_sms_summary")).leaf = true
	entry({"admin", "network", "simmanager", "sms_list"}, call("action_sms_list")).leaf = true
	entry({"admin", "network", "simmanager", "sms_sync"}, post("action_sms_sync")).leaf = true
	entry({"admin", "network", "simmanager", "sms_send"}, post("action_sms_send")).leaf = true
	entry({"admin", "network", "simmanager", "sms_mark"}, post("action_sms_mark")).leaf = true
	entry({"admin", "network", "simmanager", "sms_delete"}, post("action_sms_delete")).leaf = true
end

local function write_json(payload)
	local http = require "luci.http"
	local jsonc = require "luci.jsonc"
	http.prepare_content("application/json")
	http.write(jsonc.stringify(payload))
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
	local vendor_rsrp = radio_value(status.rsrp)

	local payload = {
		available = next(status) ~= nil or next(live) ~= nil,
		read_only = true,
		automation_enabled = uci:get("simmanager", "automation", "enabled") == "1",
		automation_default_sim = uci:get("simmanager", "automation", "default_sim") or "sim1",
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
		signal_quality = signal_quality(rsrp),
		signal_source = live.rsrp and "direct_modem_rsrp" or (vendor_rsrp and "vendor_rsrp" or "unavailable"),
		vendor_signal_percent = status.signal,
		vendor_rsrp = status.rsrp,
		vendor_signal_valid = vendor_rsrp ~= nil,
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
		supported_wcdma_bands = status.gwbandval,
		supported_lte_bands = status.ltebandval,
		supported_nsa_5g_bands = status.nsanr5gbandval,
		supported_sa_5g_bands = status.nr5gbandval,
		supported_bands = {
			wcdma = status.gwbandval,
			lte = status.ltebandval,
			nsa_5g = status.nsanr5gbandval,
			sa_5g = status.nr5gbandval
		}
	}

	local status_stable = persist_last_known(uci, active_sim, payload, stat and stat.mtime or nil)
	payload.status_stable = status_stable
	if not status_stable then
		for _, key in ipairs({
			"operator", "mccmnc", "registration", "signal_percent", "signal_quality",
			"signal_source", "rsrp", "rsrq", "rssi", "sinr", "nr_rsrp", "nr_rsrq",
			"nr_sinr", "current_band", "cell_id", "pci", "frequency", "nr_pci",
			"nr_frequency", "lte_band", "nr_band", "apn", "sim_status", "iccid"
		}) do payload[key] = nil end
	end

	local function sim_details(slot)
		local is_active = active_sim == slot
		local last_iccid = uci:get("simmanager", slot, "last_iccid")
		local has_last_known = last_iccid ~= nil and last_iccid ~= ""
		local details = {
			slot = slot,
			title = uci:get("hw_info", "cellular", slot == "sim2" and "s2_title" or "s_title") or string.upper(slot),
			active = is_active,
			profile_name = uci:get("simmanager", slot, "name"),
			phone_number = uci:get("simmanager", slot, "phone_number"),
			profile_apn = uci:get("simmanager", slot, "apn"),
			apn_auto = uci:get("simmanager", slot, "apn_auto") or "0",
			pdp_type = uci:get("simmanager", slot, "pdp_type") or "IPV4V6",
			auth_enabled = uci:get("simmanager", slot, "auth_enabled") or "0",
			auth_type = uci:get("simmanager", slot, "auth_type") or "3",
			network_mode = uci:get("simmanager", slot, "network_mode") or "AUTO",
			band_auto = uci:get("simmanager", slot, "band_auto") or "1",
			bands = uci:get("simmanager", slot, "bands"),
			last_known = has_last_known,
			last_seen = uci:get("simmanager", slot, "last_seen"),
			transitioning = is_active and not status_stable
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
		elseif has_last_known then
			details.operator = uci:get("simmanager", slot, "last_operator")
			details.mccmnc = uci:get("simmanager", slot, "last_mccmnc")
			details.sim_status = "READY"
			details.current_apn = uci:get("simmanager", slot, "last_apn")
			details.iccid = last_iccid
			details.network_type = uci:get("simmanager", slot, "last_network_type")
			details.signal_percent = uci:get("simmanager", slot, "last_signal_percent")
			details.rsrp = uci:get("simmanager", slot, "last_rsrp")
			details.current_band = uci:get("simmanager", slot, "last_band")
			details.cell_id = uci:get("simmanager", slot, "last_cell_id")
			details.pci = uci:get("simmanager", slot, "last_pci")
		end

		return details
	end

	payload.sims = {
		sim1 = sim_details("sim1"),
		sim2 = sim_details("sim2")
	}

	write_json(payload)
end

function action_control_status()
	local jsonc = require "luci.jsonc"
	local sys = require "luci.sys"
	local uci = require "luci.model.uci".cursor()
	local payload = jsonc.parse(sys.exec("/usr/sbin/simmanager-control status 2>/dev/null")) or {}
	local history = jsonc.parse(sys.exec("/usr/sbin/simmanager-control history 2>/dev/null")) or {}
	payload.active_sim = uci:get("cellular", "cellular", "hw_sim") or "unknown"
	payload.automation_enabled = uci:get("simmanager", "automation", "enabled") == "1"
	payload.automation_default_sim = uci:get("simmanager", "automation", "default_sim") or "sim1"
	payload.manual_backups = type(history.backups) == "table" and history.backups or {}
	write_json(payload)
end

function action_activate()
	local http = require "luci.http"
	local sys = require "luci.sys"
	local uci = require "luci.model.uci".cursor()
	local target = http.formvalue("target")
	local confirmation = http.formvalue("confirmation")
	local automation_action = http.formvalue("automation_action")

	if (target ~= "sim1" and target ~= "sim2") or
		(automation_action ~= "keep" and automation_action ~= "disable") or
		confirmation ~= ("SWITCH-" .. string.upper(target or "") .. "-" .. string.upper(automation_action or "")) then
		http.status(400, "Bad Request")
		write_json({ accepted = false, error = "Invalid target, automatic-switch choice, or confirmation" })
		return
	end

	if automation_action == "disable" then
		uci:set("simmanager", "automation", "enabled", "0")
		uci:commit("simmanager")
		sys.call("/etc/init.d/simmanager-auto stop >/dev/null 2>&1")
		sys.call("/etc/init.d/simmanager-auto disable >/dev/null 2>&1")
	end

	local request_mode = automation_action == "keep" and "manual-keep" or "manual-disable"
	local rc = sys.call("/usr/sbin/simmanager-control activate " .. target .. " " .. request_mode .. " >/dev/null 2>&1 &")
	write_json({ accepted = rc == 0, target = target, automation_action = automation_action })
end

function action_rollback()
	local http = require "luci.http"
	local sys = require "luci.sys"
	local backup_id = http.formvalue("backup_id") or ""
	local valid_id = backup_id:match("^%d%d%d%d%d%d%d%d%-%d%d%d%d%d%d%-%d+$") ~= nil

	if not valid_id or http.formvalue("confirmation") ~= ("ROLLBACK-" .. backup_id) then
		http.status(400, "Bad Request")
		write_json({ accepted = false, error = "Invalid manual rollback checkpoint or confirmation" })
		return
	end

	local rc = sys.call("/usr/sbin/simmanager-control rollback manual " .. backup_id .. " >/dev/null 2>&1 &")
	write_json({ accepted = rc == 0, backup_id = backup_id })
end

local function sms_command(arguments)
	local jsonc = require "luci.jsonc"
	local sys = require "luci.sys"
	local raw = sys.exec("/usr/sbin/simmanager-sms " .. arguments .. " 2>/dev/null")
	local payload = jsonc.parse(raw or "")
	if type(payload) ~= "table" then
		return { ok = false, error = "SMS service did not return a valid response" }
	end
	return payload
end

local function valid_sms_slot(slot)
	return slot == "sim1" or slot == "sim2"
end

local function valid_sms_ids(ids)
	return type(ids) == "string" and #ids <= 8192 and ids:match("^[%w,_%-]+$") ~= nil
end

function action_sms_summary()
	write_json(sms_command("summary"))
end

function action_sms_list()
	local http = require "luci.http"
	local slot = http.formvalue("slot")
	if not valid_sms_slot(slot) then
		http.status(400, "Bad Request")
		write_json({ ok = false, error = "Invalid SIM slot" })
		return
	end
	write_json(sms_command("list " .. slot))
end

function action_sms_sync()
	write_json(sms_command("sync"))
end

function action_sms_send()
	local http = require "luci.http"
	local fs = require "nixio.fs"
	local nixio = require "nixio"
	local slot = http.formvalue("slot")
	local number = trim(http.formvalue("number") or "")
	local message = http.formvalue("message") or ""

	if not valid_sms_slot(slot) or not number:match("^%+?%d%d%d+$") or #number > 20 or
		message == "" or #message > 4096 then
		http.status(400, "Bad Request")
		write_json({ ok = false, error = "Enter a valid phone number and message" })
		return
	end

	local path = string.format("/tmp/simmanager-sms-message-%d-%d", nixio.getpid(), os.time())
	if not fs.writefile(path, message) then
		http.status(500, "Internal Server Error")
		write_json({ ok = false, error = "Could not prepare the message" })
		return
	end
	local payload = sms_command(string.format("send %s %s %s", slot, number, path))
	fs.unlink(path)
	if payload.ok == false then http.status(409, "Conflict") end
	write_json(payload)
end

function action_sms_mark()
	local http = require "luci.http"
	local slot = http.formvalue("slot")
	local ids = http.formvalue("ids")
	local state = http.formvalue("state")
	if not valid_sms_slot(slot) or not valid_sms_ids(ids) or (state ~= "read" and state ~= "unread") then
		http.status(400, "Bad Request")
		write_json({ ok = false, error = "Invalid mark request" })
		return
	end
	write_json(sms_command(string.format("mark %s %s %s", slot, ids, state)))
end

function action_sms_delete()
	local http = require "luci.http"
	local slot = http.formvalue("slot")
	local ids = http.formvalue("ids")
	if not valid_sms_slot(slot) or not valid_sms_ids(ids) then
		http.status(400, "Bad Request")
		write_json({ ok = false, error = "Invalid delete request" })
		return
	end
	write_json(sms_command(string.format("delete %s %s", slot, ids)))
end

