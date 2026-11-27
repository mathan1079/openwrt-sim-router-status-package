local profile_path = assert(arg[1], "profile model path is required")

function translate(value) return value end

NamedSection = {}
Value = {}
Flag = { enabled = "1", disabled = "0" }
ListValue = {}
DummyValue = {}
SimpleSection = {}
MultiValue = {}

function MultiValue.validate(self, value)
	local values = type(value) == "table" and value or { value }
	local allowed = {}
	for _, item in ipairs(self.keylist or {}) do allowed[item] = true end
	local accepted = {}
	for _, item in ipairs(values) do
		if allowed[item] then accepted[#accepted + 1] = item end
	end
	return #accepted > 0 and table.concat(accepted, self.delimiter or " ") or nil
end

local stored = { sim1 = { network_mode = "AUTO" }, sim2 = {} }
local options = {}
local map = {}

function map:get(section, option)
	return stored[section] and stored[section][option] or nil
end

function map:set(section, option, value)
	stored[section] = stored[section] or {}
	stored[section][option] = value
end

local section = {}
function section:option(_, name)
	local option = { map = map, option = name, keylist = {}, vallist = {} }
	function option:value(key, label)
		self.keylist[#self.keylist + 1] = key
		self.vallist[#self.vallist + 1] = label or key
	end
	function option:depends() end
	options[name] = option
	return option
end

function map:section()
	return section
end

function Map()
	return map
end

assert(loadfile(profile_path))()
local mode = assert(options.network_mode, "network mode option was not created")

local function expect(selection, expected)
	local validated, err = mode:validate(selection)
	assert(validated, err or "selection was rejected")
	mode:write("sim2", validated)
	assert(stored.sim2.network_mode == expected,
		string.format("expected %s, got %s", expected, tostring(stored.sim2.network_mode)))
end

assert(mode:cfgvalue("sim1") == "LTE NR5G-SA NR5G-NSA", "legacy AUTO was not expanded for LuCI rendering")
stored.sim1.network_mode = "NR5G-SA:LTE"
assert(mode:cfgvalue("sim1") == "NR5G-SA LTE", "mixed mode was not expanded for LuCI rendering")
assert(mode:validate({}) == nil, "empty selection was accepted")
expect({ "LTE" }, "LTE")
expect({ "NR5G-SA" }, "NR5G-SA")
expect({ "NR5G-NSA" }, "NR5G-NSA")
expect({ "NR5G-SA", "NR5G-NSA" }, "NR5G")
expect({ "LTE", "NR5G-SA" }, "NR5G-SA:LTE")
expect({ "LTE", "NR5G-NSA" }, "NR5G-NSA:LTE")
expect({ "LTE", "NR5G-SA", "NR5G-NSA" }, "NR5G:LTE")

print("Network mode UI tests passed")
