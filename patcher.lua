local LOADER = "autoloads/level_loader/level_loader"

local function custom_levels(mod_id)
	local dir = GDPatch.get_mod_directory(mod_id)
	local file = dir and io.open((dir:gsub("[/\\]+$", "")) .. "/gdpatch_mod.toml", "rb")
	if not file then
		return {}
	end

	local text = file:read("a")
	file:close()

	local levels = {}
	local array = text:match("%[snapticbase%].-custom_levels%s*=%s*(%b[])") or ""
	for name, scene in array:gmatch("%[%s*[\"']([%a_][%w_]*)[\"']%s*,%s*[\"']([^\"']*)[\"']") do
		--this wont break it wont come back to bite me surely
		-- but also like im not going to embed an entire toml library
		levels[#levels + 1] = { name = name, scene = scene }
	end
	return levels
end

local function loader_path()
	for _, file in ipairs(GDPatch.get_pack().files) do
		if file == LOADER .. ".gdc" or file == LOADER .. ".gd" then
			return file
		end
	end
end

local levels = {}
local seen = {}
for _, mod in ipairs(GDPatch.get_mods()) do
	for _, level in ipairs(custom_levels(mod.id)) do
		if not seen[level.name] then
			seen[level.name] = true
			levels[#levels + 1] = level
		end
	end
end

local path = loader_path()

if #levels == 0 then
	return
elseif not path then
	print("[snapticbase] level_loader not found in the pack, custom levels skipped")
	return
end

GDPatch.patch_script_as_text(path, function(_, src)
	local enum, paths = "", ""
	for _, level in ipairs(levels) do
		if not src:find("%f[%w_]" .. level.name .. "%f[^%w_]") then
			enum = enum .. "\n\t" .. level.name .. ","
			paths = paths .. ('\n\tLevelName.%s: "%s",'):format(level.name, level.scene)
		end
	end

	src = src:gsub("(enum%s+LevelName%s*{)", function(open)
		return open .. enum
	end, 1)
	src = src:gsub("(const%s+LEVEL_PATHS[^=]*=%s*{)", function(open)
		return open .. paths
	end, 1)
	return src
end)
