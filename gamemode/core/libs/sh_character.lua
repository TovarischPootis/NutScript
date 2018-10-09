nut.char = nut.char or {}
nut.char.loaded = nut.char.loaded or {}
nut.char.vars = nut.char.vars or {}
nut.char.cache = nut.char.cache or {}

nut.util.include("nutscript/gamemode/core/meta/sh_character.lua")
nut.util.include("character/cl_networking.lua")
nut.util.include("character/sv_networking.lua")
nut.util.include("character/sv_character.lua")

function nut.char.new(data, id, client, steamID)
	if (data.name) then
		data.name = data.name:gsub("#", "#​")
	end

	if (data.desc) then
		data.desc = data.desc:gsub("#", "#​")
	end
	
	local character = setmetatable({vars = {}}, nut.meta.character)
		for k, v in pairs(data) do
			if (v != nil) then
				character.vars[k] = v
			end
		end

		character.id = id or 0
		character.player = client

		if (IsValid(client) or steamID) then
			character.steamID = IsValid(client) and client:SteamID64() or steamID
		end
	return character
end

nut.char.varHooks = nut.char.varHooks or {}
function nut.char.hookVar(varName, hookName, func)
	nut.char.varHooks[varName] = nut.char.varHooks[varName] or {}

	nut.char.varHooks[varName][hookName] = func
end

-- Registration of default variables go here.
do
	nut.char.registerVar("name", {
		field = "_name",
		default = "John Doe",
		index = 1,
		onValidate = function(value, data, client)
			if (!value or !value:find("%S")) then
				return false, "invalid", "name"
			end

			return hook.Run("GetDefaultCharName", client, data.faction) or value:sub(1, 70)
		end,
		onPostSetup = function(panel, faction, payload)
			local name, disabled = hook.Run("GetDefaultCharName", LocalPlayer(), faction)

			if (name) then
				panel:SetText(name)
				payload.name = name
			end

			if (disabled) then
				panel:SetDisabled(true)
				panel:SetEditable(false)
			end
		end
	})

	nut.char.registerVar("desc", {
		field = "_desc",
		default = "",
		index = 2,
		onValidate = function(value, data)
			if (noDesc) then return true end

			local minLength = nut.config.get("minDescLen", 16)

			if (!value or #value:gsub("%s", "") < minLength) then
				return false, "descMinLen", minLength
			end
		end
	})

	local gradient = nut.util.getMaterial("vgui/gradient-d")

	nut.char.registerVar("model", {
		field = "_model",
		default = "models/error.mdl",
		onSet = function(character, value)
			local client = character:getPlayer()

			if (IsValid(client) and client:getChar() == character) then
				client:SetModel(value)
			end

			character.vars.model = value
		end,
		onGet = function(character, default)
			return character.vars.model or default
		end,
		index = 3,
		onDisplay = function(panel, y)
			local scroll = panel:Add("DScrollPanel")
			scroll:SetSize(panel:GetWide(), 260)
			scroll:SetPos(0, y)

			local layout = scroll:Add("DIconLayout")
			layout:Dock(FILL)
			layout:SetSpaceX(1)
			layout:SetSpaceY(1)

			local faction = nut.faction.indices[panel.faction]

			if (faction) then
				for k, v in SortedPairs(faction.models) do
					local icon = layout:Add("SpawnIcon")
					icon:SetSize(64, 128)
					icon:InvalidateLayout(true)
					icon.DoClick = function(this)
						panel.payload.model = k
					end
					icon.PaintOver = function(this, w, h)
						if (panel.payload.model == k) then
							local color = nut.config.get("color", color_white)

							surface.SetDrawColor(color.r, color.g, color.b, 200)

							for i = 1, 3 do
								local i2 = i * 2

								surface.DrawOutlinedRect(i, i, w - i2, h - i2)
							end

							surface.SetDrawColor(color.r, color.g, color.b, 75)
							surface.SetMaterial(gradient)
							surface.DrawTexturedRect(0, 0, w, h)
						end
					end

					if (type(v) == "string") then
						icon:SetModel(v)
					else
						icon:SetModel(v[1], v[2] or 0, v[3])
					end
				end
			end

			return scroll
		end,
		onValidate = function(value, data)
			local faction = nut.faction.indices[data.faction]

			if (faction) then
				if (!data.model or !faction.models[data.model]) then
					return false, "needModel"
				end
			else
				return false, "needModel"
			end
		end,
		onAdjust = function(client, data, value, newData)
			local faction = nut.faction.indices[data.faction]

			if (faction) then
				local model = faction.models[value]

				if (type(model) == "string") then
					newData.model = model
				elseif (type(model) == "table") then
					newData.model = model[1]
					newData.data = newData.data or {}
					newData.data.skin = model[2] or 0
					newData.data.bodyGroups = model[3]
				end
			end
		end
	})

	nut.char.registerVar("class", {
		noDisplay = true,
	})

	nut.char.registerVar("faction", {
		field = "_faction",
		default = "Citizen",
		onSet = function(character, value)
			local client = character:getPlayer()
			local faction = character.vars.faction
			local limit = nut.faction.indices[value].limit
			
			if (IsValid(client)) then
				if (limit and limit > 0) then
					nut.faction.indices[value].limit = limit - 1
					nut.faction.teams[faction].limit = limit - 1
					client:SetTeam(value)
					return true
				elseif (!limit) then
					client:SetTeam(value)
					return true
				end
			end

			return false
		end,
		onGet = function(character, default)
			local faction = nut.faction.teams[character.vars.faction]

			return faction and faction.index or 0
		end,
		noDisplay = true,
		onValidate = function(value, data, client)
			local limit = nut.faction.indices[value].limit
			if (value) then
				if (client:hasWhitelist(value)) then
					if ((limit and limit > 0) or !limit) then
						return true
					end
				end
			end

			return false, "limitFaction"
		end,
		onAdjust = function(client, data, value, newData)
			newData.faction = nut.faction.indices[value].uniqueID
		end
	})

	nut.char.registerVar("attribs", {
		field = "_attribs",
		default = {},
		isLocal = true,
		index = 4,
		onDisplay = function(panel, y)
			local container = panel:Add("DPanel")
			container:SetPos(0, y)
			container:SetWide(panel:GetWide() - 16)

			local y2 = 0
			local total = 0
			local maximum = hook.Run("GetStartAttribPoints", LocalPlayer(), panel.payload) or nut.config.get("maxAttribs", 30)

			panel.payload.attribs = {}

			for k, v in SortedPairsByMemberValue(nut.attribs.list, "name") do
				if (v.noStartBonus) then
					continue
				end

				panel.payload.attribs[k] = 0

				local bar = container:Add("nutAttribBar")
				bar:setMax(maximum)
				bar:Dock(TOP)
				bar:DockMargin(2, 2, 2, 2)
				bar:setText(L(v.name))
				bar.onChanged = function(this, difference)
					if ((total + difference) > maximum) then
						return false
					end

					total = total + difference
					panel.payload.attribs[k] = panel.payload.attribs[k] + difference
				end

				y2 = y2 + bar:GetTall() + 4
			end

			container:SetTall(y2)
			return container
		end,
		onValidate = function(value, data, client)
			if (value != nil) then
				if (type(value) == "table") then
					local count = 0

					for k, v in pairs(value) do
						count = count + v
					end

					if (count > (hook.Run("GetStartAttribPoints", client, count) or nut.config.get("maxAttribs", 30))) then
						return false, "unknownError"
					end
				else
					return false, "unknownError"
				end
			end
		end,
		shouldDisplay = function(panel) return table.Count(nut.attribs.list) > 0 end
	})

	nut.char.registerVar("money", {
		field = "_money",
		default = 0,
		isLocal = true,
		noDisplay = true
	})

	nut.char.registerVar("data", {
		default = {},
		isLocal = true,
		noDisplay = true,
		field = "_data",
		onSet = function(character, key, value, noReplication, receiver)
			local data = character:getData()
			local client = character:getPlayer()

			data[key] = value

			if (!noReplication and IsValid(client)) then
				netstream.Start(receiver or client, "charData", character:getID(), key, value)
			end

			character.vars.data = data
		end,
		onGet = function(character, key, default)
			local data = character.vars.data or {}

			if (key) then
				if (!data) then
					return default
				end

				local value = data[key]

				return value == nil and default or value
			else
				return default or data
			end
		end
	})

	nut.char.registerVar("var", {
		default = {},
		noDisplay = true,
		onSet = function(character, key, value, noReplication, receiver)
			local data = character:getVar()
			local client = character:getPlayer()

			data[key] = value

			if (!noReplication and IsValid(client)) then
				local id

				if (client:getChar() and client:getChar():getID() == character:getID()) then
					id = client:getChar():getID()
				else
					id = character:getID()
				end

				netstream.Start(receiver or client, "charVar", key, value, id)
			end

			character.vars.vars = data
		end,
		onGet = function(character, key, default)
			character.vars.vars = character.vars.vars or {}
			local data = character.vars.vars or {}

			if (key) then
				if (!data) then
					return default
				end

				local value = data[key]

				return value == nil and default or value
			else
				return default or data
			end
		end
	})
end

-- Additions to the player metatable here.
do
	local playerMeta = FindMetaTable("Player")
	playerMeta.steamName = playerMeta.steamName or playerMeta.Name
	playerMeta.SteamName = playerMeta.steamName

	function playerMeta:getChar()
		return nut.char.loaded[self.getNetVar(self, "char")]
	end

	function playerMeta:Name()
		local character = self.getChar(self)
		
		return character and character.getName(character) or self.steamName(self)
	end

	playerMeta.Nick = playerMeta.Name
	playerMeta.GetName = playerMeta.Name
end
