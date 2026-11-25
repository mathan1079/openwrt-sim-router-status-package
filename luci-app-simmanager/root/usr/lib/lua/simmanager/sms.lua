local fs = require "nixio.fs"
local jsonc = require "luci.jsonc"

local M = {}

M.root = os.getenv("SIMMANAGER_SMS_ROOT") or "/etc/simmanager/sms"
M.limit = tonumber(os.getenv("SIMMANAGER_SMS_LIMIT")) or 150

local function now()
	return os.time()
end

local function valid_slot(slot)
	return slot == "sim1" or slot == "sim2"
end

local function path_for(slot)
	assert(valid_slot(slot), "invalid SIM slot")
	return M.root .. "/" .. slot .. ".json"
end

local function copy_table(value)
	local result = {}
	for key, item in pairs(value or {}) do result[key] = item end
	return result
end

local function atomic_write(path, value)
	fs.mkdirr(M.root)
	local temporary = path .. ".new"
	local encoded = jsonc.stringify(value)
	if not encoded or not fs.writefile(temporary, encoded .. "\n") then
		return nil, "Could not write SMS storage"
	end
	local handle = io.open(temporary, "r")
	if handle then handle:close() end
	if not os.rename(temporary, path) then
		fs.unlink(temporary)
		return nil, "Could not replace SMS storage"
	end
	return true
end

function M.load(slot)
	local path = path_for(slot)
	local raw = fs.readfile(path)
	local data = raw and jsonc.parse(raw) or nil
	if type(data) ~= "table" then data = {} end
	if type(data.messages) ~= "table" then data.messages = {} end
	data.version = 1
	data.slot = slot
	data.limit = M.limit
	return data
end

function M.save(slot, data)
	data.version = 1
	data.slot = slot
	data.limit = M.limit
	data.updated_at = now()
	return atomic_write(path_for(slot), data)
end

local function hash(value)
	local result = 5381
	for index = 1, #value do
		result = (result * 33 + value:byte(index)) % 4294967296
	end
	-- OpenWrt's Lua 5.1 build stores arithmetic results as floating-point
	-- numbers and rejects them with the integer-only %x formatter.
	return string.format("%010.0f", result)
end

function M.fingerprint(...)
	local parts = { ... }
	for index = 1, #parts do parts[index] = tostring(parts[index] or "") end
	return hash(table.concat(parts, "\31"))
end

local function can_prune(message)
	if message.direction == "received" then return message.read == true end
	return message.delivery_status ~= "sending" and message.delivery_status ~= "sent"
end

local function make_room(data)
	if #data.messages < M.limit then return true end
	local candidate
	for index, message in ipairs(data.messages) do
		if can_prune(message) and (not candidate or (tonumber(message.timestamp) or 0) < candidate.time) then
			candidate = { index = index, time = tonumber(message.timestamp) or 0 }
		end
	end
	if not candidate then return false end
	table.remove(data.messages, candidate.index)
	return true
end

function M.can_add(slot)
	local data = M.load(slot)
	if #data.messages < M.limit then return true end
	for _, message in ipairs(data.messages) do if can_prune(message) then return true end end
	return false
end

function M.add(slot, message)
	local data = M.load(slot)
	for _, existing in ipairs(data.messages) do
		if existing.fingerprint == message.fingerprint then
			return true, existing, false
		end
	end
	if not make_room(data) then return nil, "SMS storage is full. Read or delete messages before synchronizing." end
	message.created_at = tonumber(message.created_at) or now()
	message.updated_at = tonumber(message.updated_at) or message.created_at
	message.timestamp = tonumber(message.timestamp) or message.created_at
	message.id = message.id or (tostring(message.timestamp) .. "-" .. hash(message.fingerprint or tostring(message.created_at)))
	table.insert(data.messages, message)
	data.iccid = message.iccid or data.iccid
	local ok, err = M.save(slot, data)
	if not ok then return nil, err end
	return true, message, true
end

function M.list(slot)
	local data = M.load(slot)
	table.sort(data.messages, function(left, right)
		return (tonumber(left.timestamp) or 0) > (tonumber(right.timestamp) or 0)
	end)
	local unread = 0
	local inbox = 0
	local sent = 0
	for _, message in ipairs(data.messages) do
		if message.direction == "received" then
			inbox = inbox + 1
			if message.read ~= true then unread = unread + 1 end
		else
			sent = sent + 1
		end
	end
	return data, { unread = unread, inbox = inbox, sent = sent, total = #data.messages }
end

local function ids_to_set(ids)
	local wanted = {}
	for id in tostring(ids or ""):gmatch("[^,]+") do wanted[id] = true end
	return wanted
end

function M.mark(slot, ids, is_read)
	local data = M.load(slot)
	local wanted = ids_to_set(ids)
	local changed = 0
	for _, message in ipairs(data.messages) do
		if wanted[message.id] and message.direction == "received" then
			message.read = is_read == true
			message.updated_at = now()
			changed = changed + 1
		end
	end
	local ok, err = M.save(slot, data)
	return ok, err, changed
end

function M.delete(slot, ids)
	local data = M.load(slot)
	local wanted = ids_to_set(ids)
	local kept = {}
	local removed = 0
	for _, message in ipairs(data.messages) do
		if wanted[message.id] then removed = removed + 1 else kept[#kept + 1] = message end
	end
	data.messages = kept
	local ok, err = M.save(slot, data)
	return ok, err, removed
end

function M.update_delivery(slot, reference, status, report_time)
	local data = M.load(slot)
	local selected
	for _, message in ipairs(data.messages) do
		if message.direction == "sent" and type(message.references) == "table" then
			for _, item in ipairs(message.references) do
				if tonumber(item) == tonumber(reference) and
					(not selected or (tonumber(message.timestamp) or 0) > (tonumber(selected.timestamp) or 0)) then
					selected = message
				end
			end
		end
	end
	if not selected then return false end
	selected.reference_status = type(selected.reference_status) == "table" and selected.reference_status or {}
	selected.reference_status[tostring(reference)] = status
	local delivered = 0
	local failed = false
	local expected = type(selected.references) == "table" and #selected.references or 0
	for _, item in ipairs(selected.references or {}) do
		local part_status = selected.reference_status[tostring(item)]
		if part_status == "delivered" then delivered = delivered + 1 end
		if part_status == "failed" then failed = true end
	end
	selected.delivery_status = failed and "failed" or (expected > 0 and delivered == expected and "delivered" or "sent")
	selected.delivery_updated_at = report_time or now()
	selected.updated_at = now()
	M.save(slot, data)
	return true
end

local function hex_bytes(hex)
	local bytes = {}
	hex = tostring(hex or ""):gsub("%s+", "")
	if #hex % 2 ~= 0 or hex:find("[^%x]") then return nil end
	for index = 1, #hex, 2 do bytes[#bytes + 1] = tonumber(hex:sub(index, index + 1), 16) end
	return bytes
end

local function bytes_hex(bytes)
	local parts = {}
	for _, value in ipairs(bytes) do parts[#parts + 1] = string.format("%02X", value) end
	return table.concat(parts)
end

local function swapped_digits(bytes, position, digits)
	local output = {}
	for offset = 0, math.ceil(digits / 2) - 1 do
		local value = bytes[position + offset] or 0
		output[#output + 1] = string.format("%X", value % 16)
		if #table.concat(output) < digits and math.floor(value / 16) ~= 15 then
			output[#output + 1] = string.format("%X", math.floor(value / 16))
		end
	end
	return table.concat(output):sub(1, digits)
end

local function decode_address(bytes, position, digits, toa)
	local value = swapped_digits(bytes, position, digits)
	if toa == 145 and value:sub(1, 1) ~= "+" then value = "+" .. value end
	return value, position + math.ceil(digits / 2)
end

local gsm7 = {
	[0]="@", [1]="£", [2]="$", [3]="¥", [4]="è", [5]="é", [6]="ù", [7]="ì",
	[8]="ò", [9]="Ç", [10]="\n", [11]="Ø", [12]="ø", [13]="\r", [14]="Å", [15]="å",
	[16]="Δ", [17]="_", [18]="Φ", [19]="Γ", [20]="Λ", [21]="Ω", [22]="Π", [23]="Ψ",
	[24]="Σ", [25]="Θ", [26]="Ξ", [27]="", [28]="Æ", [29]="æ", [30]="ß", [31]="É",
	[32]=" ", [33]="!", [34]='"', [35]="#", [36]="¤", [37]="%", [38]="&", [39]="'",
	[40]="(", [41]=")", [42]="*", [43]="+", [44]=",", [45]="-", [46]=".", [47]="/",
	[48]="0", [49]="1", [50]="2", [51]="3", [52]="4", [53]="5", [54]="6", [55]="7",
	[56]="8", [57]="9", [58]=":", [59]=";", [60]="<", [61]="=", [62]=">", [63]="?",
	[64]="¡", [65]="A", [66]="B", [67]="C", [68]="D", [69]="E", [70]="F", [71]="G",
	[72]="H", [73]="I", [74]="J", [75]="K", [76]="L", [77]="M", [78]="N", [79]="O",
	[80]="P", [81]="Q", [82]="R", [83]="S", [84]="T", [85]="U", [86]="V", [87]="W",
	[88]="X", [89]="Y", [90]="Z", [91]="Ä", [92]="Ö", [93]="Ñ", [94]="Ü", [95]="§",
	[96]="¿", [97]="a", [98]="b", [99]="c", [100]="d", [101]="e", [102]="f", [103]="g",
	[104]="h", [105]="i", [106]="j", [107]="k", [108]="l", [109]="m", [110]="n", [111]="o",
	[112]="p", [113]="q", [114]="r", [115]="s", [116]="t", [117]="u", [118]="v", [119]="w",
	[120]="x", [121]="y", [122]="z", [123]="ä", [124]="ö", [125]="ñ", [126]="ü", [127]="à"
}

local gsm7_ext = { [10]="\f", [20]="^", [40]="{", [41]="}", [47]="\\", [60]="[", [61]="~", [62]="]", [64]="|", [101]="€" }

local function decode_gsm7(bytes, septets, bit_offset)
	local output = {}
	local escaped = false
	bit_offset = bit_offset or 0
	for index = 0, septets - 1 do
		local bit = bit_offset + index * 7
		local byte_index = math.floor(bit / 8) + 1
		local shift = bit % 8
		local value = math.floor((bytes[byte_index] or 0) / (2 ^ shift))
		if shift > 1 then value = value + ((bytes[byte_index + 1] or 0) * (2 ^ (8 - shift))) end
		value = value % 128
		if escaped then
			output[#output + 1] = gsm7_ext[value] or "?"
			escaped = false
		elseif value == 27 then
			escaped = true
		else
			output[#output + 1] = gsm7[value] or "?"
		end
	end
	return table.concat(output)
end

local function utf8_character(codepoint)
	if codepoint <= 0x7f then return string.char(codepoint) end
	if codepoint <= 0x7ff then
		return string.char(0xc0 + math.floor(codepoint / 64), 0x80 + codepoint % 64)
	end
	if codepoint <= 0xffff then
		return string.char(0xe0 + math.floor(codepoint / 4096), 0x80 + math.floor(codepoint / 64) % 64, 0x80 + codepoint % 64)
	end
	return string.char(0xf0 + math.floor(codepoint / 262144), 0x80 + math.floor(codepoint / 4096) % 64,
		0x80 + math.floor(codepoint / 64) % 64, 0x80 + codepoint % 64)
end

local function decode_ucs2(bytes, position, length)
	local output = {}
	local finish = math.min(#bytes, position + length - 1)
	local index = position
	while index + 1 <= finish do
		local value = bytes[index] * 256 + bytes[index + 1]
		index = index + 2
		if value >= 0xd800 and value <= 0xdbff and index + 1 <= finish then
			local low = bytes[index] * 256 + bytes[index + 1]
			if low >= 0xdc00 and low <= 0xdfff then
				value = 0x10000 + (value - 0xd800) * 0x400 + (low - 0xdc00)
				index = index + 2
			end
		end
		output[#output + 1] = utf8_character(value)
	end
	return table.concat(output)
end

local function bcd_pair(value)
	return string.format("%d%d", value % 16, math.floor(value / 16))
end

local function decode_timestamp(bytes, position)
	local values = {}
	for offset = 0, 5 do values[#values + 1] = bcd_pair(bytes[position + offset] or 0) end
	local year = tonumber(values[1]) or 0
	return string.format("20%02d-%s-%s %s:%s:%s", year, values[2], values[3], values[4], values[5], values[6])
end

local function parse_concat(bytes, position, header_length)
	local finish = position + header_length - 1
	local cursor = position + 1
	while cursor + 1 <= finish do
		local identifier = bytes[cursor]
		local length = bytes[cursor + 1] or 0
		if identifier == 0 and length == 3 and cursor + 4 <= finish then
			return bytes[cursor + 2], bytes[cursor + 3], bytes[cursor + 4]
		elseif identifier == 8 and length == 4 and cursor + 5 <= finish then
			return bytes[cursor + 2] * 256 + bytes[cursor + 3], bytes[cursor + 4], bytes[cursor + 5]
		end
		cursor = cursor + length + 2
	end
	return nil
end

function M.decode_pdu(hex)
	local bytes = hex_bytes(hex)
	if not bytes or #bytes < 3 then return nil, "Invalid SMS PDU" end
	local smsc_length = bytes[1] or 0
	local position = 2 + smsc_length
	local first = bytes[position]
	if not first then return nil, "Incomplete SMS PDU" end
	position = position + 1
	local mti = first % 4

	if mti == 0 then
		local digits = bytes[position] or 0; position = position + 1
		local toa = bytes[position] or 129; position = position + 1
		local sender; sender, position = decode_address(bytes, position, digits, toa)
		position = position + 1
		local dcs = bytes[position] or 0; position = position + 1
		local service_time = decode_timestamp(bytes, position); position = position + 7
		local udl = bytes[position] or 0; position = position + 1
		local udhi = math.floor(first / 64) % 2 == 1
		local header_bytes = 0
		local concat_ref, concat_total, concat_seq
		if udhi then
			header_bytes = (bytes[position] or 0) + 1
			concat_ref, concat_total, concat_seq = parse_concat(bytes, position, header_bytes)
		end
		local text
		if math.floor(dcs / 4) % 4 == 2 then
			text = decode_ucs2(bytes, position + header_bytes, math.max(0, udl - header_bytes))
		elseif math.floor(dcs / 4) % 4 == 1 then
			local payload = {}
			for offset = header_bytes, udl - 1 do payload[#payload + 1] = bytes[position + offset] or 0 end
			text = "[Binary SMS: " .. bytes_hex(payload) .. "]"
		else
			local header_septets = udhi and math.ceil(header_bytes * 8 / 7) or 0
			text = decode_gsm7({ unpack(bytes, position, #bytes) }, math.max(0, udl - header_septets), header_septets * 7)
		end
		return {
			type = "received", number = sender, text = text, service_time = service_time,
			concat_ref = concat_ref, concat_total = concat_total, concat_seq = concat_seq,
			pdu = hex:upper()
		}
	elseif mti == 2 then
		local reference = bytes[position] or 0; position = position + 1
		local digits = bytes[position] or 0; position = position + 1
		local toa = bytes[position] or 129; position = position + 1
		local recipient; recipient, position = decode_address(bytes, position, digits, toa)
		local submitted = decode_timestamp(bytes, position); position = position + 7
		local delivered = decode_timestamp(bytes, position); position = position + 7
		local code = bytes[position] or 255
		local status = code < 0x20 and "delivered" or (code < 0x40 and "sent" or "failed")
		return { type = "report", reference = reference, number = recipient, status = status,
			report_code = code, submitted_time = submitted, service_time = delivered, pdu = hex:upper() }
	end
	return nil, "Unsupported SMS PDU type"
end

local function utf8_codepoints(value)
	local result = {}
	local index = 1
	while index <= #value do
		local first = value:byte(index)
		local codepoint, length
		if first < 0x80 then codepoint, length = first, 1
		elseif first < 0xe0 then codepoint, length = first % 0x20, 2
		elseif first < 0xf0 then codepoint, length = first % 0x10, 3
		else codepoint, length = first % 0x08, 4 end
		for offset = 2, length do
			local continuation = value:byte(index + offset - 1)
			if not continuation or continuation < 0x80 or continuation >= 0xc0 then return nil, "Invalid UTF-8 message" end
			codepoint = codepoint * 64 + continuation % 0x40
		end
		result[#result + 1] = codepoint
		index = index + length
	end
	return result
end

local function ucs2_units(value)
	local codepoints, err = utf8_codepoints(value)
	if not codepoints then return nil, err end
	local units = {}
	for _, codepoint in ipairs(codepoints) do
		if codepoint <= 0xffff and not (codepoint >= 0xd800 and codepoint <= 0xdfff) then
			units[#units + 1] = { math.floor(codepoint / 256), codepoint % 256 }
		elseif codepoint <= 0x10ffff then
			local adjusted = codepoint - 0x10000
			local high = 0xd800 + math.floor(adjusted / 0x400)
			local low = 0xdc00 + adjusted % 0x400
			units[#units + 1] = { math.floor(high / 256), high % 256, math.floor(low / 256), low % 256 }
		else
			return nil, "Message contains an unsupported character"
		end
	end
	return units
end

local function encode_number(number)
	local digits = number:gsub("^%+", "")
	local toa = number:sub(1, 1) == "+" and 145 or 129
	local output = {}
	for index = 1, #digits, 2 do
		local first = tonumber(digits:sub(index, index)) or 0
		local second = tonumber(digits:sub(index + 1, index + 1))
		output[#output + 1] = (second or 15) * 16 + first
	end
	return digits, toa, output
end

function M.encode_submit(number, text)
	if not tostring(number):match("^%+?%d%d%d+$") or #number > 20 then return nil, "Invalid destination number" end
	local units, err = ucs2_units(text)
	if not units then return nil, err end
	if #units == 0 then return nil, "Message is empty" end
	local chunks = {}
	local current = {}
	local bytes = 0
	local total_bytes = 0
	for _, unit in ipairs(units) do total_bytes = total_bytes + #unit end
	local maximum = total_bytes > 140 and 134 or 140
	for _, unit in ipairs(units) do
		if bytes + #unit > maximum then chunks[#chunks + 1] = current; current = {}; bytes = 0 end
		current[#current + 1] = unit; bytes = bytes + #unit
	end
	if #current > 0 then chunks[#chunks + 1] = current end
	if #chunks > 10 then return nil, "Message is too long (maximum 10 SMS parts)" end
	local reference = math.random(0, 255)
	local digits, toa, address = encode_number(number)
	local pdus = {}
	for sequence, chunk in ipairs(chunks) do
		local user_data = {}
		if #chunks > 1 then
			user_data = { 5, 0, 3, reference, #chunks, sequence }
		end
		for _, unit in ipairs(chunk) do for _, value in ipairs(unit) do user_data[#user_data + 1] = value end end
		local first = #chunks > 1 and 0x71 or 0x31
		local tpdu = { first, 0, #digits, toa }
		for _, value in ipairs(address) do tpdu[#tpdu + 1] = value end
		tpdu[#tpdu + 1] = 0
		tpdu[#tpdu + 1] = 8
		tpdu[#tpdu + 1] = 0xaa
		tpdu[#tpdu + 1] = #user_data
		for _, value in ipairs(user_data) do tpdu[#tpdu + 1] = value end
		pdus[#pdus + 1] = { hex = "00" .. bytes_hex(tpdu), length = #tpdu, sequence = sequence, total = #chunks }
	end
	return pdus
end

function M.merge_parts(parts)
	local groups = {}
	local complete = {}
	for _, part in ipairs(parts) do
		if part.decoded.concat_ref and part.decoded.concat_total and part.decoded.concat_total > 1 then
			local key = table.concat({ part.decoded.number or "", part.decoded.concat_ref, part.decoded.concat_total, part.decoded.service_time or "" }, "|")
			groups[key] = groups[key] or { total = part.decoded.concat_total, segments = {} }
			groups[key].segments[part.decoded.concat_seq] = part
		else
			complete[#complete + 1] = { decoded = part.decoded, records = { part } }
		end
	end
	for _, group in pairs(groups) do
		local text = {}
		local records = {}
		local first
		local ready = true
		for sequence = 1, group.total do
			local part = group.segments[sequence]
			if not part then ready = false; break end
			first = first or part.decoded
			text[#text + 1] = part.decoded.text or ""
			records[#records + 1] = part
		end
		if ready then
			local decoded = copy_table(first)
			decoded.text = table.concat(text)
			local pdu_parts = {}
			for _, record in ipairs(records) do pdu_parts[#pdu_parts + 1] = record.decoded.pdu end
			decoded.pdu = table.concat(pdu_parts, ":")
			complete[#complete + 1] = { decoded = decoded, records = records }
		end
	end
	return complete
end

return M
