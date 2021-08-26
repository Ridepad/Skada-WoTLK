assert(Skada, "Skada not found!")

local Enemies = Skada:NewModule("Enemies")
local L = LibStub("AceLocale-3.0"):GetLocale("Skada", false)

-- frequently used globals --
local pairs, ipairs, select = pairs, ipairs, select
local format, min, max = string.format, math.min, math.max
local UnitClass, GetSpellInfo = Skada.UnitClass, Skada.GetSpellInfo
local tContains = tContains
local _

function Skada:find_enemy(set, name)
	if set and name then
		set._enemyidx = set._enemyidx or {}

		local enemy = set._enemyidx[name]
		if enemy then
			return enemy
		end

		for _, e in pairs(set.enemies) do
			if e.name == name then
				set._enemyidx[name] = e
				return e
			end
		end
	end
end

function Skada:get_enemy(set, guid, name, flags)
	if set then
		local enemy = self:find_enemy(set, name)
		local now = time()

		if not enemy then
			if not name then return end

			enemy = {id = guid or name, name = name}

			if guid or flags then
				enemy.class = select(2, UnitClass(guid, flags, set))
			else
				enemy.class = "ENEMY"
			end

			tinsert(set.enemies, enemy)
		end

		self.changed = true
		return enemy
	end
end

function Skada:IterateEnemies(set)
	return ipairs(set and set.enemies or {})
end

local function EnemyClass(name, set)
	local class = "UNKNOWN"
	local e = Skada:find_enemy(set, name)
	if e and e.class then
		class = e.class
	end
	return class
end

function Enemies:CreateSet(_, set)
	if set and set.name == L["Current"] then
		set.enemies = set.enemies or {}
	end
end

function Enemies:ClearIndexes(_, set)
	if set then
		set._enemyidx = nil
	end
end

function Enemies:OnEnable()
	Skada.RegisterCallback(self, "SKADA_DATA_SETCREATED", "CreateSet")
	Skada.RegisterCallback(self, "SKADA_DATA_CLEARSETINDEX", "ClearIndexes")
end

function Enemies:OnDisable()
	Skada.UnregisterAllCallbacks(self)
end

---------------------------------------------------------------------------
-- Enemy Damage Taken

Skada:AddLoadableModule("Enemy Damage Taken", function(Skada, L)
	if Skada:IsDisabled("Enemy Damage Taken") then return end

	local mod = Skada:NewModule(L["Enemy Damage Taken"])
	local enemymod = mod:NewModule(L["Damage taken per player"])
	local spellmod = mod:NewModule(L["Damage spell details"])

	local type, newTable, delTable = type, Skada.newTable, Skada.delTable
	local LBB = LibStub("LibBabble-Boss-3.0"):GetLookupTable()

	local instanceDiff, customUnitsTable

	-- this table holds the units to which the damage done is
	-- collected into a new fake unit.
	local customGroups = {
		-- The Lich King: Useful targets
		[LBB["The Lich King"]] = L["Useful targets"],
		[LBB["Raging Spirit"]] = L["Useful targets"],
		[LBB["Ice Sphere"]] = L["Useful targets"],
		[LBB["Val'kyr Shadowguard"]] = L["Useful targets"],
		[L["Wicked Spirit"]] = L["Useful targets"],
		-- Professor Putricide: Oozes
		[L["Gas Cloud"]] = L["Oozes"],
		[L["Volatile Ooze"]] = L["Oozes"],
		-- Blood Prince Council: Princes overkilling
		[LBB["Prince Valanar"]] = L["Princes overkilling"],
		[LBB["Prince Taldaram"]] = L["Princes overkilling"],
		[LBB["Prince Keleseth"]] = L["Princes overkilling"],
		-- Lady Deathwhisper: Adds
		[L["Cult Adherent"]] = L["Adds"],
		[L["Empowered Adherent"]] = L["Adds"],
		[L["Reanimated Adherent"]] = L["Adds"],
		[L["Cult Fanatic"]] = L["Adds"],
		[L["Deformed Fanatic"]] = L["Adds"],
		[L["Reanimated Fanatic"]] = L["Adds"],
		[L["Darnavan"]] = L["Adds"],
		-- Halion: Halion and Inferno
		[LBB["Halion"]] = L["Halion and Inferno"],
		[L["Living Inferno"]] = L["Halion and Inferno"]
	}

	-- this table holds units that should create a fake unit
	-- at certain health percentage. Useful in case you want
	-- to collect damage done to the units at certain phases.
	local customUnits = {
		-- Icecrown Citadel:
		[36855] = {start = 0, text = L["%s - Phase 2"], power = 0}, -- Lady Deathwhisper
		[36678] = {start = 0.35, text = L["%s - Phase 3"]}, -- Professor Putricide
		[36853] = {start = 0.35, text = L["%s - Phase 2"]}, -- Sindragosa
		[36980] = {start = 0.15}, -- Ice Tomb (Sindragosa)
		[36609] = {name = L["Valkyrs overkilling"], diff = {"10h", "25h"}, start = 0.5, useful = true}, -- Valkyrs overkilling
		[36597] = {start = 0.4, text = L["%s - Phase 3"]}, -- The Lich King
		-- Trial of the Crusader
		[34564] = {start = 0.3, text = L["%s - Phase 2"]}, -- Anub'arak
		-- The Ruby Sanctum (works only if you're inside or remain outisde because of GUIDs)
		-- [39863] = {start = 0.5, text = L["%s - Phase 3"]}, -- Halion
		-- [40142] = {start = 0.5, text = L["%s - Phase 3"]}, -- Halion (twilight realm)
	}

	local function GetRaidDiff()
		if not instanceDiff then
			local _, instanceType, difficulty, _, _, dynamicDiff, isDynamic = GetInstanceInfo()
			if instanceType == "raid" and isDynamic then
				if difficulty == 1 or difficulty == 3 then -- 10man raid
					instanceDiff = (dynamicDiff == 0) and "10n" or ((dynamicDiff == 1) and "10h" or "unknown")
				elseif difficulty == 2 or difficulty == 4 then -- 25main raid
					instanceDiff = (dynamicDiff == 0) and "25n" or ((dynamicDiff == 1) and "25h" or "unknown")
				end
			else
				local insDiff = GetInstanceDifficulty()
				if insDiff == 1 then
					instanceDiff = "10n"
				elseif insDiff == 2 then
					instanceDiff = "25n"
				elseif insDiff == 3 then
					instanceDiff = "10h"
				elseif insDiff == 4 then
					instanceDiff = "25h"
				end
			end
		end

		return instanceDiff
	end

	local function IsCustomUnit(guid, name)
		if customUnitsTable and customUnitsTable[guid] then
			return true
		end

		local id = Skada:GetCreatureId(guid)

		local unit = id and customUnits[id]
		if unit then
			-- difficulty check.
			if unit.diff ~= nil then
				if type(unit.diff) == "table" and not tContains(unit.diff, GetRaidDiff()) then
					return false
				elseif type(unit.diff) == "string" and GetRaidDiff() ~= unit.diff then
					return false
				end
			end

			customUnitsTable = customUnitsTable or newTable()
			customUnitsTable[guid] = {}

			if unit.name == nil then
				customUnitsTable[guid].name = format(unit.text or L["%s below %s%%"], name or UNKNOWN, unit.start * 100)
			else
				customUnitsTable[guid].name = unit.name
			end

			if unit.power ~= nil then
				customUnitsTable[guid].curr, customUnitsTable[guid].max = select(2, Skada:UnitPowerInfo(nil, guid, unit.power))
			else
				customUnitsTable[guid].curr, customUnitsTable[guid].max = select(2, Skada:UnitHealthInfo(nil, guid))
			end
			customUnitsTable[guid].watch = floor(customUnitsTable[guid].max * (unit.start or 0.5))

			customUnitsTable[guid].useful = unit.useful
			return true
		end

		return false
	end

	local function log_custom_damage(set, name, playerid, playername, spellid, amount)
		local e = Skada:get_enemy(set, nil, name, nil)
		if e then
			e.damagetaken = (e.damagetaken or 0) + amount

			-- spell
			if spellid then
				e.damagetaken_spells = e.damagetaken_spells or {}
				e.damagetaken_spells[spellid] = (e.damagetaken_spells[spellid] or 0) + amount
			end

			-- source
			if playername then
				e.damagetaken_sources = e.damagetaken_sources or {}
				if not e.damagetaken_sources[playername] then
					e.damagetaken_sources[playername] = {id = playerid, amount = amount}
				else
					e.damagetaken_sources[playername].id = e.damagetaken_sources[playername].id or playerid -- GUID fix
					e.damagetaken_sources[playername].amount = e.damagetaken_sources[playername].amount + amount
				end
			end
		end
	end

	-- spells in the following table will be ignored.
	local ignoredSpells = {}

	local function log_damage(set, dmg)
		if dmg.spellid and tContains(ignoredSpells, dmg.spellid) then return end

		local e = Skada:get_enemy(set, dmg.enemyid, dmg.enemyname, dmg.enemyflags)
		if e then
			e.damagetaken = (e.damagetaken or 0) + dmg.amount
			set.edamagetaken = (set.edamagetaken or 0) + dmg.amount

			-- spell
			if dmg.spellid then
				e.damagetaken_spells = e.damagetaken_spells or {}
				e.damagetaken_spells[dmg.spellid] = (e.damagetaken_spells[dmg.spellid] or 0) + dmg.amount
			end

			if dmg.srcName then
				e.damagetaken_sources = e.damagetaken_sources or {}
				if not e.damagetaken_sources[dmg.srcName] then
					e.damagetaken_sources[dmg.srcName] = {id = dmg.srcGUID, amount = dmg.amount}
				else
					e.damagetaken_sources[dmg.srcName].id = e.damagetaken_sources[dmg.srcName].id or dmg.srcGUID -- GUID fix
					e.damagetaken_sources[dmg.srcName].amount = e.damagetaken_sources[dmg.srcName].amount + dmg.amount
				end

				-- the rest is dne only for raids, sorry.
				if GetRaidDiff() == nil or GetRaidDiff() == "unknown" then return end

				-- custom units
				if IsCustomUnit(dmg.enemyid, dmg.enemyname) then
					local unit = customUnitsTable[dmg.enemyid]
					-- started with less than max?
					if unit.max and unit.curr <= unit.max then
						if unit.useful then
							e.damagetaken_useful = (e.damagetaken_useful or 0) + unit.max - unit.curr
							e.damagetaken_sources[dmg.srcName].useful = (e.damagetaken_sources[dmg.srcName].useful or 0) + unit.max - unit.curr
						end
						unit.max = nil
					elseif unit.curr >= unit.watch then
						unit.curr = unit.curr - dmg.amount

						if unit.curr < unit.watch then
							local amount = unit.watch - unit.curr - dmg.overkill
							log_custom_damage(set, unit.name, dmg.srcGUID, dmg.srcName, dmg.spellid, amount)

							if unit.useful then
								e.damagetaken_useful = (e.damagetaken_useful or 0) + dmg.amount - dmg.overkill - amount
								e.damagetaken_sources[dmg.srcName].useful = (e.damagetaken_sources[dmg.srcName].useful or 0) + dmg.amount - dmg.overkill - amount
							end
						elseif unit.useful then
							e.damagetaken_useful = (e.damagetaken_useful or 0) + dmg.amount - dmg.overkill
							e.damagetaken_sources[dmg.srcName].useful = (e.damagetaken_sources[dmg.srcName].useful or 0) + dmg.amount - dmg.overkill
						end
					elseif not unit.max then
						log_custom_damage(set, unit.name, dmg.srcGUID, dmg.srcName, dmg.spellid, dmg.amount - dmg.overkill)
					end
				end

				if customGroups[dmg.enemyname] and customGroups[dmg.enemyname] ~= dmg.enemyname then
					if customGroups[dmg.enemyname] == L["Halion and Inferno"] and GetRaidDiff() ~= "25h" then return end

					local amount = (customGroups[dmg.enemyname] == L["Princes overkilling"]) and dmg.overkill or dmg.amount
					log_custom_damage(set, customGroups[dmg.enemyname], dmg.srcGUID, dmg.srcName, dmg.spellid, amount)
				end
			end
		end
	end

	local dmg = {}

	local function SpellDamage(timestamp, eventtype, srcGUID, srcName, srcFlags, dstGUID, dstName, dstFlags, ...)
		local spellid, _, spellschool, amount, overkill = ...
		if srcName and dstName then
			srcGUID, srcName = Skada:FixMyPets(srcGUID, srcName)

			dmg.enemyid = dstGUID
			dmg.enemyname = dstName
			dmg.enemyflags = dstFlags
			dmg.srcGUID = srcGUID
			dmg.srcName = srcName

			dmg.spellid = spellid
			dmg.amount = amount
			dmg.overkill = overkill or 0

			log_damage(Skada.current, dmg)
		end
	end

	local function SwingDamage(timestamp, eventtype, srcGUID, srcName, srcFlags, dstGUID, dstName, dstFlags, ...)
		SpellDamage(timestamp, eventtype, srcGUID, srcName, srcFlags, dstGUID, dstName, dstFlags, 6603, nil, nil, ...)
	end

	local function getDTPS(set, enemy)
		local amount = enemy.damagetaken or 0
		return amount / max(1, Skada:GetSetTime(set)), amount
	end

	local function getEnemiesDTPS(set)
		return (set.edamagetaken or 0) / max(1, Skada:GetSetTime(set)), (set.edamagetaken or 0)
	end

	local function enemymod_tooltip(win, id, label, tooltip)
		local set = win:get_selected_set()
		local p = Skada:find_player(set, id, label)
		local e = Skada:find_enemy(set, win.targetname)
		if p and e and e.damagetaken_sources and e.damagetaken_sources[p.name] then
			tooltip:AddLine(format(L["%s's damage breakdown"], p.name))

			local total = e.damagetaken_sources[p.name].amount
			tooltip:AddDoubleLine(L["Damage Done"], Skada:FormatNumber(total), 1, 1, 1)

			local useful = e.damagetaken_sources[p.name].useful or 0
			if useful > 0 then
				tooltip:AddDoubleLine(L["Useful Damage"], format("%s (%.1f%%)", Skada:FormatNumber(useful), 100 * useful / total), 1, 1, 1)
			end
		end
	end

	function enemymod:Enter(win, id, label)
		win.targetname = label
		win.title = format(L["Damage on %s"], label)
	end

	function enemymod:Update(win, set)
		win.title = format(L["Damage on %s"], win.targetname or UNKNOWN)
		local enemy = Skada:find_enemy(set, win.targetname)
		local total = enemy and select(2, getDTPS(set, enemy)) or 0

		if total > 0 and enemy.damagetaken_sources then
			local maxvalue, nr = 0, 1

			for playername, player in pairs(enemy.damagetaken_sources) do
				local d = win.dataset[nr] or {}
				win.dataset[nr] = d

				d.id = player.id or playername
				d.label = playername
				d.text = Skada:FormatName(playername, d.id)
				d.class, d.role, d.spec = select(2, UnitClass(d.id, nil, set))

				d.value = player.amount
				d.valuetext = Skada:FormatValueText(
					Skada:FormatNumber(d.value),
					mod.metadata.columns.Damage,
					format("%.1f%%", 100 * d.value / total),
					mod.metadata.columns.Percent
				)

				if d.value > maxvalue then
					maxvalue = d.value
				end
				nr = nr + 1
			end

			win.metadata.maxvalue = maxvalue
		end
	end

	function spellmod:Enter(win, id, label)
		win.targetname = label
		win.title = format(L["Damage on %s"], label)
	end

	function spellmod:Update(win, set)
		win.title = format(L["Damage on %s"], win.targetname or UNKNOWN)
		local enemy = Skada:find_enemy(set, win.targetname)
		local total = enemy and select(2, getDTPS(set, enemy)) or 0

		if total > 0 and enemy.damagetaken_spells then
			local maxvalue, nr = 0, 1

			for spellid, amount in pairs(enemy.damagetaken_spells) do
				local d = win.dataset[nr] or {}
				win.dataset[nr] = d

				d.id = spellid
				d.spellid = spellid
				d.label, _, d.icon = GetSpellInfo(spellid)

				d.value = amount
				d.valuetext = Skada:FormatValueText(
					Skada:FormatNumber(d.value),
					mod.metadata.columns.Damage,
					format("%.1f%%", 100 * d.value / total),
					mod.metadata.columns.Percent
				)

				if d.value > maxvalue then
					maxvalue = d.value
				end
				nr = nr + 1
			end

			win.metadata.maxvalue = maxvalue
		end
	end

	function mod:Update(win, set)
		win.title = L["Enemy Damage Taken"]
		local total = select(2, getEnemiesDTPS(set))
		if total > 0 then
			local maxvalue, nr = 0, 1

			for _, enemy in ipairs(set.enemies) do
				local dtps, amount = getDTPS(set, enemy)
				if amount > 0 then
					local d = win.dataset[nr] or {}
					win.dataset[nr] = d

					d.id = enemy.name
					d.label = enemy.name
					d.class = enemy.class

					d.value = amount
					d.valuetext = Skada:FormatValueText(
						Skada:FormatNumber(amount),
						self.metadata.columns.Damage,
						Skada:FormatNumber(dtps),
						self.metadata.columns.DTPS,
						format("%.1f%%", 100 * amount / total),
						self.metadata.columns.Percent
					)

					if amount > maxvalue then
						maxvalue = amount
					end
					nr = nr + 1
				end
			end

			win.metadata.maxvalue = maxvalue
		end
	end

	function mod:OnEnable()
		enemymod.metadata = {showspots = true, tooltip = enemymod_tooltip}
		self.metadata = {
			click1 = enemymod,
			click2 = spellmod,
			columns = {Damage = true, DTPS = false, Percent = true},
			icon = "Interface\\Icons\\spell_fire_felflamebolt"
		}

		local damagemod = Skada:GetModule(L["Damage"], true)
		if damagemod then
			enemymod.metadata.click1 = damagemod:GetModule(L["Damage target list"], true)
		end

		Skada:RegisterForCL(SpellDamage, "DAMAGE_SHIELD", {src_is_interesting = true, dst_is_not_interesting = true})
		Skada:RegisterForCL(SpellDamage, "DAMAGE_SPLIT", {src_is_interesting = true, dst_is_not_interesting = true})
		Skada:RegisterForCL(SpellDamage, "RANGE_DAMAGE", {src_is_interesting = true, dst_is_not_interesting = true})
		Skada:RegisterForCL(SpellDamage, "SPELL_DAMAGE", {src_is_interesting = true, dst_is_not_interesting = true})
		Skada:RegisterForCL(SpellDamage, "SPELL_EXTRA_ATTACKS", {src_is_interesting = true, dst_is_not_interesting = true})
		Skada:RegisterForCL(SpellDamage, "SPELL_PERIODIC_DAMAGE", {src_is_interesting = true, dst_is_not_interesting = true})
		Skada:RegisterForCL(SwingDamage, "SWING_DAMAGE", {src_is_interesting = true, dst_is_not_interesting = true})

		Skada:AddMode(self, L["Enemies"])
	end

	function mod:OnDisable()
		Skada:RemoveMode(self)
	end

	function mod:SetComplete(set)
		customUnitsTable, instanceDiff = delTable(customUnitsTable), nil
	end
end)

---------------------------------------------------------------------------
-- Enemy Damage Done

Skada:AddLoadableModule("Enemy Damage Done", function(Skada, L)
	if Skada:IsDisabled("Enemy Damage Done") then return end

	local mod = Skada:NewModule(L["Enemy Damage Done"])
	local enemymod = mod:NewModule(L["Damage taken per player"])
	local spellmod = mod:NewModule(L["Damage spell list"])

	-- spells in the following table will be ignored.
	local ignoredSpells = {}

	local function log_damage(set, dmg)
		if dmg.spellid and tContains(ignoredSpells, dmg.spellid) then return end

		local e = Skada:get_enemy(set, dmg.enemyid, dmg.enemyname, dmg.enemyflags)
		if e then
			e.damage = (e.damage or 0) + dmg.amount
			set.edamage = (set.edamage or 0) + dmg.amount

			-- spell
			if dmg.spellid then
				e.damage_spells = e.damage_spells or {}
				e.damage_spells[dmg.spellid] = (e.damage_spells[dmg.spellid] or 0) + dmg.amount
			end

			if dmg.dstName then
				e.damage_targets = e.damage_targets or {}
				if not e.damage_targets[dmg.dstName] then
					e.damage_targets[dmg.dstName] = {id = dmg.dstGUID, amount = dmg.amount}
				else
					e.damage_targets[dmg.dstName].id = e.damage_targets[dmg.dstName].id or dmg.dstGUID -- GUID fix
					e.damage_targets[dmg.dstName].amount = e.damage_targets[dmg.dstName].amount + dmg.amount
				end
			end
		end
	end

	local dmg = {}

	local function SpellDamage(timestamp, eventtype, srcGUID, srcName, srcFlags, dstGUID, dstName, dstFlags, ...)
		local spellid, _, _, amount = ...
		if srcName and dstName then
			dmg.enemyid = srcGUID
			dmg.enemyname = srcName
			dmg.enemyflags = srcFlags

			dmg.dstGUID = dstGUID
			dmg.dstName = dstName
			dmg.spellid = spellid
			dmg.amount = amount

			log_damage(Skada.current, dmg)
		end
	end

	local function SwingDamage(timestamp, eventtype, srcGUID, srcName, srcFlags, dstGUID, dstName, dstFlags, ...)
		SpellDamage(nil, nil, srcGUID, srcName, nil, dstGUID, dstName, dstFlags, 6603, nil, nil, ...)
	end

	local function getDPS(set, enemy)
		local amount = enemy.damage or 0
		return amount / max(1, Skada:GetSetTime(set)), amount
	end

	local function getEnemiesDPS(set)
		return (set.edamage or 0) / max(1, Skada:GetSetTime(set)), (set.edamage or 0)
	end

	function enemymod:Enter(win, id, label)
		win.targetname = label
		win.title = format(L["Damage from %s"], label)
	end

	function enemymod:Update(win, set)
		win.title = format(L["Damage from %s"], win.targetname or UNKNOWN)
		local enemy = Skada:find_enemy(set, win.targetname)
		local total = enemy and select(2, getDPS(set, enemy)) or 0

		if total > 0 and enemy.damage_targets then
			local maxvalue, nr = 0, 1

			for targetname, target in pairs(enemy.damage_targets) do
				local d = win.dataset[nr] or {}
				win.dataset[nr] = d

				d.id = target.id or targetname
				d.label = targetname
				d.text = Skada:FormatName(targetname, d.id)
				d.class, d.role, d.spec = select(2, UnitClass(d.id, nil, set))

				d.value = target.amount
				d.valuetext = Skada:FormatValueText(
					Skada:FormatNumber(d.value),
					mod.metadata.columns.Damage,
					format("%.1f%%", 100 * d.value / total),
					mod.metadata.columns.Percent
				)

				if d.value > maxvalue then
					maxvalue = d.value
				end
				nr = nr + 1
			end

			win.metadata.maxvalue = maxvalue
		end
	end

	function spellmod:Enter(win, id, label)
		win.targetname = label
		win.title = format(L["%s's damage"], label)
	end

	function spellmod:Update(win, set)
		win.title = format(L["%s's damage"], win.targetname or UNKNOWN)
		local enemy = Skada:find_enemy(set, win.targetname)
		local total = enemy and select(2, getDPS(set, enemy)) or 0

		if total > 0 and enemy.damage_spells then
			local maxvalue, nr = 0, 1

			for spellid, amount in pairs(enemy.damage_spells) do
				local d = win.dataset[nr] or {}
				win.dataset[nr] = d

				d.id = spellid
				d.spellid = spellid
				d.label, _, d.icon = GetSpellInfo(spellid)

				d.value = amount
				d.valuetext = Skada:FormatValueText(
					Skada:FormatNumber(d.value),
					mod.metadata.columns.Damage,
					format("%.1f%%", 100 * d.value / total),
					mod.metadata.columns.Percent
				)

				if d.value > maxvalue then
					maxvalue = d.value
				end
				nr = nr + 1
			end

			win.metadata.maxvalue = maxvalue
		end
	end

	function mod:Update(win, set)
		win.title = L["Enemy Damage Done"]
		local total = select(2, getEnemiesDPS(set))
		if total > 0 then
			local maxvalue, nr = 0, 1

			for _, enemy in ipairs(set.enemies) do
				local dtps, amount = getDPS(set, enemy)
				if amount > 0 then
					local d = win.dataset[nr] or {}
					win.dataset[nr] = d

					d.id = enemy.name
					d.label = enemy.name
					d.class = enemy.class

					d.value = amount
					d.valuetext = Skada:FormatValueText(
						Skada:FormatNumber(amount),
						self.metadata.columns.Damage,
						Skada:FormatNumber(dtps),
						self.metadata.columns.DPS,
						format("%.1f%%", 100 * amount / total),
						self.metadata.columns.Percent
					)

					if amount > maxvalue then
						maxvalue = amount
					end
					nr = nr + 1
				end
			end

			win.metadata.maxvalue = maxvalue
		end
	end

	function mod:OnEnable()
		self.metadata = {
			click1 = enemymod,
			click2 = spellmod,
			columns = {Damage = true, DPS = false, Percent = true},
			icon = "Interface\\Icons\\spell_shadow_shadowbolt"
		}

		local damagemod = Skada:GetModule(L["Damage Taken"], true)
		if damagemod then
			enemymod.metadata = {click1 = damagemod:GetModule(L["Damage source list"], true)}
		end

		Skada:RegisterForCL(SpellDamage, "DAMAGE_SHIELD", {dst_is_interesting_nopets = true, src_is_not_interesting = true})
		Skada:RegisterForCL(SpellDamage, "DAMAGE_SPLIT", {dst_is_interesting_nopets = true, src_is_not_interesting = true})
		Skada:RegisterForCL(SpellDamage, "RANGE_DAMAGE", {dst_is_interesting_nopets = true, src_is_not_interesting = true})
		Skada:RegisterForCL(SpellDamage, "SPELL_DAMAGE", {dst_is_interesting_nopets = true, src_is_not_interesting = true})
		Skada:RegisterForCL(SpellDamage, "SPELL_EXTRA_ATTACKS", {dst_is_interesting_nopets = true, src_is_not_interesting = true})
		Skada:RegisterForCL(SpellDamage, "SPELL_PERIODIC_DAMAGE", {dst_is_interesting_nopets = true, src_is_not_interesting = true})
		Skada:RegisterForCL(SwingDamage, "SWING_DAMAGE", {dst_is_interesting_nopets = true, src_is_not_interesting = true})

		Skada:AddMode(self, L["Enemies"])
	end

	function mod:OnDisable()
		Skada:RemoveMode(self)
	end
end)

---------------------------------------------------------------------------
-- Enemy Healing Done

Skada:AddLoadableModule("Enemy Healing Done", function(Skada, L)
	if Skada:IsDisabled("Enemy Healing Done") then return end

	local mod = Skada:NewModule(L["Enemy Healing Done"])
	local targetmod = mod:NewModule(L["Healed target list"])
	local spellmod = mod:NewModule(L["Healing spell list"])

	-- spells in the following table will be ignored.
	local ignoredSpells = {}

	local function log_heal(set, data)
		if data.spellid and tContains(ignoredSpells, data.spellid) then return end

		local e = Skada:get_enemy(set, data.enemyid, data.enemyname, data.enemyflags)
		if e then
			e.heal = (e.heal or 0) + data.amount
			set.eheal = (set.eheal or 0) + data.amount

			-- spell
			if data.spellid then
				e.heal_spells = e.heal_spells or {}
				e.heal_spells[data.spellid] = (e.heal_spells[data.spellid] or 0) + data.amount
			end

			-- target
			if data.dstName then
				e.heal_targets = e.heal_targets or {}
				e.heal_targets[data.dstName] = (e.heal_targets[data.dstName] or 0) + data.amount
			end
		end
	end

	local heal = {}

	local function SpellHeal(timestamp, eventtype, srcGUID, srcName, srcFlags, dstGUID, dstName, dstFlags, ...)
		local spellid, _, _, amount, overheal = ...

		heal.enemyid = srcGUID
		heal.enemyname = srcName
		heal.enemyflags = srcFlags

		heal.dstName = dstName
		heal.spellid = spellid
		heal.amount = max(0, amount - overheal)

		log_heal(Skada.current, heal)
	end

	local function getHPS(set, enemy)
		local amount = enemy.heal or 0
		return amount / max(1, Skada:GetSetTime(set)), amount
	end

	local function getEnemiesHPS(set)
		return (set.eheal or 0) / max(1, Skada:GetSetTime(set)), (set.eheal or 0)
	end

	function targetmod:Enter(win, id, label)
		win.targetname = label
		win.title = format(L["%s's healed targets"], label)
	end

	function targetmod:Update(win, set)
		win.title = format(L["%s's healed targets"], win.targetname or UNKNOWN)
		local enemy = Skada:find_enemy(set, win.targetname)
		local total = enemy and select(2, getHPS(set, enemy)) or 0

		if total > 0 and enemy.heal_targets then
			local maxvalue, nr = 0, 1

			for targetname, amount in pairs(enemy.heal_targets) do
				local d = win.dataset[nr] or {}
				win.dataset[nr] = d

				d.id = targetname
				d.label = targetname
				d.class = EnemyClass(targetname, set)

				d.value = amount
				d.valuetext = Skada:FormatValueText(
					Skada:FormatNumber(amount),
					mod.metadata.columns.Healing,
					format("%.1f%%", 100 * amount / total),
					mod.metadata.columns.Percent
				)

				if amount > maxvalue then
					maxvalue = amount
				end
				nr = nr + 1
			end

			win.metadata.maxvalue = maxvalue
		end
	end

	function spellmod:Enter(win, id, label)
		win.targetname = label
		win.title = format(L["%s's healing spells"], label)
	end

	function spellmod:Update(win, set)
		win.title = format(L["%s's healing spells"], win.targetname or UNKNOWN)
		local enemy = Skada:find_enemy(set, win.targetname)
		local total = enemy and select(2, getHPS(set, enemy)) or 0

		if total > 0 and enemy.heal_spells then
			local maxvalue, nr = 0, 1

			for spellid, amount in pairs(enemy.heal_spells) do
				local d = win.dataset[nr] or {}
				win.dataset[nr] = d

				d.id = spellid
				d.spellid = spellid
				d.label, _, d.icon = GetSpellInfo(spellid)

				d.value = amount
				d.valuetext = Skada:FormatValueText(
					Skada:FormatNumber(amount),
					mod.metadata.columns.Healing,
					format("%.1f%%", 100 * amount / total),
					mod.metadata.columns.Percent
				)

				if amount > maxvalue then
					maxvalue = amount
				end
				nr = nr + 1
			end

			win.metadata.maxvalue = maxvalue
		end
	end

	function mod:Update(win, set)
		win.title = L["Enemy Healing Done"]
		local total = select(2, getEnemiesHPS(set))

		if total > 0 then
			local maxvalue, nr = 0, 1

			for _, enemy in ipairs(set.enemies) do
				local hps, amount = getHPS(set, enemy)
				if amount > 0 then
					local d = win.dataset[nr] or {}
					win.dataset[nr] = d

					d.id = enemy.id
					d.label = enemy.name
					d.class = enemy.class

					d.value = amount
					d.valuetext = Skada:FormatValueText(
						Skada:FormatNumber(amount),
						self.metadata.columns.Healing,
						Skada:FormatNumber(hps),
						self.metadata.columns.HPS,
						format("%.1f%%", 100 * amount / total),
						self.metadata.columns.Percent
					)

					if amount > maxvalue then
						maxvalue = amount
					end
					nr = nr + 1
				end
			end

			win.metadata.maxvalue = maxvalue
		end
	end

	function mod:OnEnable()
		self.metadata = {
			showspots = true,
			click1 = spellmod,
			click2 = targetmod,
			nototalclick = {spellmod, targetmod},
			columns = {Healing = true, HPS = false, Percent = true},
			icon = "Interface\\Icons\\spell_nature_healingtouch"
		}

		Skada:RegisterForCL(SpellHeal, "SPELL_HEAL", {src_is_not_interesting = true, dst_is_not_interesting = true})
		Skada:RegisterForCL(SpellHeal, "SPELL_PERIODIC_HEAL", {src_is_not_interesting = true, dst_is_not_interesting = true})

		Skada:AddMode(self, L["Enemies"])
	end

	function mod:OnDisable()
		Skada:RemoveMode(self)
	end
end)