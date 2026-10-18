local LOADER = "autoloads/level_loader/level_loader"
local GAME = "game/game"
local CLICK_BUTTON = "levels/menu_screen_background/prefabs/click_button/click_button"

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

local function script_path(base)
	for _, file in ipairs(GDPatch.get_pack().files) do
		if file == base .. ".gdc" or file == base .. ".gd" then
			return file
		end
	end
end

local click_path = script_path(CLICK_BUTTON)
if click_path then
	GDPatch.patch_script_as_text(click_path, function(_, src)
		return (
			src:gsub("Cursor%.bind%(self, Cursors%.POINTING_HAND%)", function()
				return "Cursor.bind_dynamic(self, func() -> CursorDefinition: return null if disabled else Cursors.POINTING_HAND)"
			end, 1)
		)
	end)
else
	print("[snapticbase] click_button not found in the pack, cursor bug unfixezd")
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

local path = script_path(LOADER)

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

local game_path = script_path(GAME)
if game_path then
	GDPatch.patch_script_as_text(game_path, function(_, src)
		return (
			src:gsub("(func%s+_ready%s*%([^)]*%)[^\n]*\n)", function(head)
				return head .. "\tstarting_level = LevelLoader.LevelName.MIRRAXIS\n"
			end, 1)
		)
	end)
else
	print("[snapticbase] game script not found in ther pack, couldn't force starting level")
end
