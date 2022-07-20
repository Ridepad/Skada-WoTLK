local Skada = Skada
Skada:RegisterModule("Comparison", function(L, P)
	local parent = Skada:GetModule("Damage", true)
	if not parent then return end

	local mod = parent:NewModule("Comparison")
	local spellmod = mod:NewModule("Damage spell list")
	local dspellmod = spellmod:NewModule("Damage spell details")
	local bspellmod = spellmod:NewModule("Damage Breakdown")
	local targetmod = mod:NewModule("Damage target list")
	local dtargetmod = targetmod:NewModule("Damage spell list")
	local C = Skada.cacheTable2

	local pairs, max = pairs, math.max
	local format, pformat = string.format, Skada.pformat
	local GetSpellInfo = Skada.GetSpellInfo or GetSpellInfo
	local spellschools = Skada.spellschools
	local COLOR_GOLD = {r = 1, g = 0.82, b = 0, colorStr = "ffffd100"}
	local _

	-- damage miss types
	local missTypes = Skada.missTypes

	-- percentage colors
	local red = "\124cffffaaaa-%s\124r"
	local green = "\124cffaaffaa+%s\124r"
	local grey = "\124cff808080%s\124r"

	local function format_percent(value1, value2, cond)
		if cond == false then return end

		value1, value2 = value1 or 0, value2 or 0
		if value1 == value2 then
			return format(grey, Skada:FormatPercent(0))
		elseif value1 > value2 then
			return format(green, Skada:FormatPercent(value1 - value2, value2))
		else
			return format(red, Skada:FormatPercent(value2 - value1, value1))
		end
	end

	local function format_value_percent(val, myval, disabled)
		return Skada:FormatValueCols(
			mod.metadata.columns.Damage and Skada:FormatPercent(val),
			(mod.metadata.columns.Comparison and not disabled) and Skada:FormatPercent(myval),
			(mod.metadata.columns.Percent and not disabled) and format_percent(myval, val)
		)
	end

	local function format_value_number(val, myval, fmt, disabled)
		val, myval = val or 0, myval or 0 -- sanity check
		return Skada:FormatValueCols(
			mod.metadata.columns.Damage and (fmt and Skada:FormatNumber(val) or val),
			(mod.metadata.columns.Comparison and not disabled) and (fmt and Skada:FormatNumber(myval) or myval),
			format_percent(myval, val, mod.metadata.columns.Percent and not disabled)
		)
	end

	local function can_compare(actor)
		return (actor and actor.class == mod.userClass and actor.role == "DAMAGER")
	end

	local function spellmod_tooltip(win, id, label, tooltip)
		if label == L["Critical Hits"] or label == L["Normal Hits"] or label == L["Glancing"] then
			local set = win:GetSelectedSet()
			local actor = set and set:GetActor(win.actorname, win.actorid)
			local spell = actor.damagespells and actor.damagespells[win.spellname]

			if actor.id == mod.userGUID then
				if spell then
					tooltip:AddLine(actor.name .. " - " .. win.spellname)
					if spell.school and spellschools[spell.school] then
						tooltip:AddLine(spellschools(spell.school))
					end

					if label == L["Critical Hits"] and spell.c_amt then
						if spell.c_min then
							tooltip:AddDoubleLine(L["Minimum"], Skada:FormatNumber(spell.c_min), 1, 1, 1)
						end
						if spell.c_max then
							tooltip:AddDoubleLine(L["Maximum"], Skada:FormatNumber(spell.c_max), 1, 1, 1)
						end
						tooltip:AddDoubleLine(L["Average"], Skada:FormatNumber(spell.c_amt / spell.c_num), 1, 1, 1)
					elseif label == L["Normal Hits"] and spell.n_amt then
						if spell.n_min then
							tooltip:AddDoubleLine(L["Minimum"], Skada:FormatNumber(spell.n_min), 1, 1, 1)
						end
						if spell.n_max then
							tooltip:AddDoubleLine(L["Maximum"], Skada:FormatNumber(spell.n_max), 1, 1, 1)
						end
						tooltip:AddDoubleLine(L["Average"], Skada:FormatNumber(spell.n_amt / spell.n_num), 1, 1, 1)
					elseif label == L["Glancing"] and spell.g_amt then
						if spell.g_min then
							tooltip:AddDoubleLine(L["Minimum"], Skada:FormatNumber(spell.g_min), 1, 1, 1)
						end
						if spell.g_max then
							tooltip:AddDoubleLine(L["Maximum"], Skada:FormatNumber(spell.g_max), 1, 1, 1)
						end
						tooltip:AddDoubleLine(L["Average"], Skada:FormatNumber(spell.g_amt / spell.g_num), 1, 1, 1)
					end
				end
				return
			end

			local myspells = set:GetActorDamageSpells(mod.userGUID, mod.userName)
			local myspell = myspells and myspells[win.spellname]

			if spell or myspell then
				tooltip:AddLine(pformat(L["%s vs %s: %s"], actor and actor.name, mod.userName, win.spellname))
				if (spell.school and spellschools[spell.school]) or (myspell.school and spellschools[myspell.school]) then
					tooltip:AddLine(spellschools(spell and spell.school or myspell.school))
				end

				if label == L["Critical Hits"] and (spell and spell.c_amt or myspell.c_amt) then
					local num = spell and spell.c_num and (100 * spell.c_num / spell.count) or 0
					local mynum = myspell and myspell.c_num and (100 * myspell.c_num / myspell.count) or 0

					tooltip:AddDoubleLine(L["Critical"], format_value_percent(mynum, num, actor.id == mod.userGUID), 1, 1, 1)

					num = (spell and spell.c_amt) and (spell.c_amt / spell.c_num) or 0
					mynum = (myspell and myspell.c_amt) and (myspell.c_amt / myspell.c_num) or 0

					if (spell and spell.c_min) or (myspell and myspell.c_min) then
						tooltip:AddDoubleLine(L["Minimum"], format_value_number(spell and spell.c_min, myspell and myspell.c_min, true), 1, 1, 1)
					end

					if (spell and spell.c_max) or (myspell and myspell.c_max) then
						tooltip:AddDoubleLine(L["Maximum"], format_value_number(spell and spell.c_max, myspell and myspell.c_max, true), 1, 1, 1)
					end

					tooltip:AddDoubleLine(L["Average"], format_value_number(num, mynum, true), 1, 1, 1)
				elseif label == L["Normal Hits"] and ((spell and spell.n_amt) or (myspell and myspell.n_amt)) then
					local num = (spell and spell.n_amt) and (spell.n_amt / spell.n_num) or 0
					local mynum = (myspell and myspell.n_amt) and (myspell.n_amt / myspell.n_num) or 0

					if (spell and spell.n_min) or (myspell and myspell.n_min) then
						tooltip:AddDoubleLine(L["Minimum"], format_value_number(spell and spell.n_min, myspell and myspell.n_min, true), 1, 1, 1)
					end

					if (spell and spell.n_max) or (myspell and myspell.n_max) then
						tooltip:AddDoubleLine(L["Maximum"], format_value_number(spell and spell.n_max, myspell and myspell.n_max, true), 1, 1, 1)
					end

					tooltip:AddDoubleLine(L["Average"], format_value_number(num, mynum, true), 1, 1, 1)
				elseif label == L["Glancing"] and ((spell and spell.g_amt) or (myspell and myspell.g_amt)) then
					local num = (spell and spell.g_amt) and (spell.g_amt / spell.g_num) or 0
					local mynum = (myspell and myspell.g_amt) and (myspell.g_amt / myspell.g_num) or 0

					if (spell and spell.g_min) or (myspell and myspell.g_min) then
						tooltip:AddDoubleLine(L["Minimum"], format_value_number(spell and spell.g_min, myspell and myspell.g_min, true), 1, 1, 1)
					end

					if (spell and spell.g_max) or (myspell and myspell.g_max) then
						tooltip:AddDoubleLine(L["Maximum"], format_value_number(spell and spell.g_max, myspell and myspell.g_max, true), 1, 1, 1)
					end

					tooltip:AddDoubleLine(L["Average"], format_value_number(num, mynum, true), 1, 1, 1)
				end
			end
		end
	end

	local function activity_tooltip(win, id, label, tooltip)
		local set = win:GetSelectedSet()
		local actor = set and set:GetActor(label, id)
		if actor then
			local totaltime = set:GetTime()
			local activetime = actor:GetTime(true)
			local mytime = set:GetActorTime(mod.userGUID, mod.userName, true)

			tooltip:AddDoubleLine(L["Activity"], format_value_percent(100 * activetime / totaltime, 100 * mytime / totaltime, actor.id == mod.userGUID), 1, 1, 1)
			tooltip:AddDoubleLine(L["Active Time"], format(actor.id ~= mod.userGUID and "%s (%s)" or "%s", Skada:FormatTime(activetime), Skada:FormatTime(mytime)), 1, 1, 1)
		end
	end

	-- local nr = add_detail_bar(win, 0, L["Hits"], spell.count, myspell.count)
	local function add_detail_bar(win, nr, title, value, myvalue, fmt, disabled)
		nr = nr + 1
		local d = win:nr(nr)

		d.id = title
		d.label = title

		if value then
			d.value = value
			myvalue = myvalue or 0
		elseif myvalue then
			d.value = myvalue
			value = value or 0
		else
			d.value = value or 0
			myvalue = myvalue or 0
		end

		d.valuetext = format_value_number(value, myvalue, fmt, disabled)

		if win.metadata and (not win.metadata.maxvalue or d.value > win.metadata.maxvalue) then
			win.metadata.maxvalue = d.value
		end

		return nr
	end

	function dspellmod:Enter(win, id, label)
		win.spellname = label
		win.title = pformat(L["%s vs %s: %s"], win.actorname, mod.userName, pformat(L["%s's damage breakdown"], label))
	end

	function dspellmod:Update(win, set)
		win.title = pformat(L["%s vs %s: %s"], win.actorname, mod.userName, pformat(L["%s's damage breakdown"], win.spellname))
		if not set or not win.spellname then return end

		local actor = set:GetActor(win.actorname, win.actorid)
		if not actor then return end

		local spell = actor and actor.damagespells and actor.damagespells[win.spellname]

		-- same actor?
		if actor.id == mod.userGUID then
			win.title = format("%s: %s", actor.name, format(L["%s's damage breakdown"], win.spellname))

			if spell then
				if win.metadata then
					win.metadata.maxvalue = spell.count
				end

				local nr = add_detail_bar(win, 0, L["Hits"], spell.count, nil, nil, true)
				win.dataset[nr].value = win.dataset[nr].value + 1 -- to be always first

				if spell.casts and spell.casts > 0 then
					nr = add_detail_bar(win, nr, L["Casts"], spell.casts, nil, nil, true)
					win.dataset[nr].value = win.dataset[nr].value * 1e3 -- to be always first
				end

				if spell.n_num and spell.n_num > 0 then
					nr = add_detail_bar(win, nr, L["Normal Hits"], spell.n_num, nil, nil, true)
				end

				if spell.c_num and spell.c_num > 0 then
					nr = add_detail_bar(win, nr, L["Critical Hits"], spell.c_num, nil, nil, true)
				end

				if spell.g_num and spell.g_num > 0 then
					nr = add_detail_bar(win, nr, L["Glancing"], spell.g_num, nil, nil, true)
				end

				for k, v in pairs(missTypes) do
					if spell[v] then
						nr = add_detail_bar(win, nr, L[k], spell[v], nil, nil, true)
					end
				end
			end

			return
		end

		local myspells = set:GetActorDamageSpells(mod.userGUID, mod.userName)
		local myspell = myspells and myspells[win.spellname]

		if spell or myspell then
			if win.metadata then
				win.metadata.maxvalue = spell and spell.count or myspell.count
			end

			local nr = add_detail_bar(win, 0, L["Hits"], spell and spell.count, myspell and myspell.count)
			win.dataset[nr].value = win.dataset[nr].value + 1 -- to be always first

			if (spell and spell.casts and spell.casts > 0) or (myspell and myspell.casts and myspell.casts > 0) then
				nr = add_detail_bar(win, nr, L["Casts"], spell and spell.casts, myspell and myspell.casts)
				win.dataset[nr].value = win.dataset[nr].value * 1e3 -- to be always first
			end

			if (spell and spell.n_num and spell.n_num > 0) or (myspell and myspell.n_num and myspell.n_num > 0) then
				nr = add_detail_bar(win, nr, L["Normal Hits"], spell and spell.n_num, myspell and myspell.n_num)
			end

			if (spell and spell.c_num and spell.c_num > 0) or (myspell and myspell.c_num and myspell.c_num > 0) then
				nr = add_detail_bar(win, nr, L["Critical Hits"], spell and spell.c_num, myspell and myspell.c_num)
			end

			if (spell and spell.g_num and spell.g_num > 0) or (myspell and myspell.g_num and myspell.g_num > 0) then
				nr = add_detail_bar(win, nr, L["Glancing"], spell and spell.g_num, myspell and myspell.g_num)
			end

			for k, v in pairs(missTypes) do
				if (spell and spell[v]) or (myspell and myspell[v]) then
					nr = add_detail_bar(win, nr, L[k], spell and spell[v], myspell and myspell[v])
				end
			end
		end
	end

	function bspellmod:Enter(win, id, label)
		win.spellname = label
		win.title = pformat(L["%s vs %s: %s"], win.actorname, mod.userName, L["actor damage"](label))
	end

	function bspellmod:Update(win, set)
		win.title = pformat(L["%s vs %s: %s"], win.actorname, mod.userName, L["actor damage"](win.spellname or L["Unknown"]))
		if not set or not win.spellname then return end

		local actor = set:GetActor(win.actorname, win.actorid)
		if not actor then return end

		local spell = actor and actor.damagespells and actor.damagespells[win.spellname]

		if actor.id == mod.userGUID then
			win.title = pformat(L["%s's <%s> damage"], actor.name, win.spellname)

			if spell then
				local absorbed = spell.total and max(0, spell.total - spell.amount) or 0
				local blocked, resisted = spell.b_amt or 0, spell.r_amt or 0
				local total = spell.amount + absorbed + blocked + resisted

				-- total damage
				local nr = add_detail_bar(win, 0, L["Total"], total, nil, true, true)
				win.dataset[nr].value = win.dataset[nr].value + 1 -- to be always first

				-- real damage
				if total ~= spell.amount then
					nr = add_detail_bar(win, nr, L["Damage"], spell.amount, nil, true, true)
				end

				-- absorbed damage
				if absorbed > 0 then
					nr = add_detail_bar(win, nr, L["Overkill"], absorbed, nil, true, true)
				end

				-- overkill damage
				if spell.o_amt and spell.o_amt > 0 then
					nr = add_detail_bar(win, nr, L["Overkill"], spell.o_amt, nil, true, true)
				end

				-- blocked damage
				if spell.b_amt and spell.b_amt > 0 then
					nr = add_detail_bar(win, nr, L["BLOCK"], spell.b_amt, nil, true, true)
				end

				-- resisted damage
				if spell.r_amt and spell.r_amt > 0 then
					nr = add_detail_bar(win, nr, L["RESIST"], spell.r_amt, nil, true, true)
				end
			end

			return
		end

		local myspells = set:GetActorDamageSpells(mod.userGUID, mod.userName)
		local myspell = myspells and myspells[win.spellname]

		if spell or myspell then
			local absorbed = (spell and spell.total) and max(0, spell.total - spell.amount) or 0
			local myabsorbed = (myspell and myspell.total) and max(0, myspell.total - myspell.amount) or 0
			local blocked, myblocked = spell and spell.b_amt or 0, myspell and myspell.b_amt or 0
			local resisted, myresisted = spell and spell.r_amt or 0, myspell and myspell.r_amt or 0

			local total = (spell and spell.amount or 0) + absorbed + blocked + resisted
			local mytotal = (myspell and myspell.amount or 0) + myabsorbed + myblocked + myresisted

			-- total damage
			local nr = add_detail_bar(win, 0, L["Total"], total, mytotal, true)
			win.dataset[nr].value = (spell and total or mytotal) + 1 -- to be always first

			-- real damage
			if (spell and total ~= spell.amount) or (myspell and mytotal ~= myspell.amount) then
				nr = add_detail_bar(win, nr, L["Damage"], spell and spell.amount, myspell and myspell.amount, true)
			end

			-- absorbed damage
			if absorbed > 0 or myabsorbed > 0 then
				nr = add_detail_bar(win, nr, L["ABSORB"], absorbed, myabsorbed, true)
			end

			-- overkill damage
			if (spell and spell.o_amt and spell.o_amt > 0) or (myspell and myspell.o_amt and myspell.o_amt > 0) then
				nr = add_detail_bar(win, nr, L["Overkill"], spell and spell.o_amt, myspell and myspell.o_amt, true)
			end

			-- blocked damage
			if (spell and spell.b_amt and spell.b_amt > 0) or (myspell and myspell.b_amt and myspell.b_amt > 0) then
				nr = add_detail_bar(win, nr, L["BLOCK"], spell and spell.b_amt, myspell and myspell.b_amt, true)
			end

			-- resisted damage
			if (spell and spell.r_amt and spell.r_amt > 0) or (myspell and myspell.r_amt and myspell.r_amt > 0) then
				nr = add_detail_bar(win, nr, L["RESIST"], spell and spell.r_amt, myspell and myspell.r_amt, true)
			end
		end
	end

	function dtargetmod:Enter(win, id, label)
		win.targetname = label
		win.title = pformat(L["%s vs %s: Damage on %s"], win.actorname, mod.userName, label)
	end

	function dtargetmod:Update(win, set)
		win.title = pformat(L["%s vs %s: Damage on %s"], win.actorname, mod.userName, win.targetname)
		if not set or not win.targetname then return end

		local targets, actor = set:GetActorDamageTargets(win.actorid, win.actorname)
		if not targets then return end

		if actor.id == mod.userGUID then
			win.title = L["actor damage"](actor.name, win.targetname)

			local total = 0
			if targets[win.targetname] then
				total = targets[win.targetname].amount or total
				if P.absdamage and targets[win.targetname].total then
					total = targets[win.targetname].total or total
				end
			end

			if total > 0 and actor.damagespells then
				if win.metadata then
					win.metadata.maxvalue = 0
				end

				local nr = 0
				for spellname, spell in pairs(actor.damagespells) do
					if spell.targets and spell.targets[win.targetname] then
						nr = nr + 1
						local d = win:spell(nr, spellname, spell)

						d.value = spell.targets[win.targetname].amount or 0
						if P.absdamage and spell.targets[win.targetname].total then
							d.value = spell.targets[win.targetname].total
						end

						d.valuetext = Skada:FormatValueCols(mod.metadata.columns.Damage and Skada:FormatNumber(d.value))

						if win.metadata and d.value > win.metadata.maxvalue then
							win.metadata.maxvalue = d.value
						end
					end
				end
			end

			return
		end

		local mytargets, myself = set:GetActorDamageTargets(mod.userGUID, mod.userName, C)

		-- the compared actor
		local total = 0
		if targets[win.targetname] then
			total = targets[win.targetname].amount or total
			if P.absdamage and targets[win.targetname].total then
				total = targets[win.targetname].total or total
			end
		end

		-- existing targets.
		if total > 0 and actor.damagespells then
			if win.metadata then
				win.metadata.maxvalue = 0
			end

			local nr = 0
			for spellname, spell in pairs(actor.damagespells) do
				if spell.targets and spell.targets[win.targetname] then
					nr = nr + 1
					local d = win:spell(nr, spellname, spell)

					d.value = spell.targets[win.targetname].amount or 0
					local myamount = 0
					if
						myself and
						myself.damagespells and
						myself.damagespells[spellname] and
						myself.damagespells[spellname].targets and
						myself.damagespells[spellname].targets[win.targetname]
					then
						myamount = myself.damagespells[spellname].targets[win.targetname].amount or myamount
					end

					if P.absdamage then
						if spell.targets[win.targetname].total then
							d.value = spell.targets[win.targetname].total
						end
						if
							myself and
							myself.damagespells and
							myself.damagespells[spellname] and
							myself.damagespells[spellname].targets and
							myself.damagespells[spellname].targets[win.targetname] and
							myself.damagespells[spellname].targets[win.targetname].total
						then
							myamount = myself.damagespells[spellname].targets[win.targetname].total
						end
					end

					d.valuetext = format_value_number(d.value, myamount, true)

					if win.metadata and d.value > win.metadata.maxvalue then
						win.metadata.maxvalue = d.value
					end
				end
			end

			return
		end

		-- unexisting targets.
		if mytargets then
			local mytotal = 0
			if mytargets[win.targetname] then
				mytotal = mytargets[win.targetname].amount or mytotal
				if P.absdamage and mytargets[win.targetname].total then
					mytotal = mytargets[win.targetname].total or mytotal
				end
			end

			if mytotal > 0 then
				if win.metadata then
					win.metadata.maxvalue = 0
				end

				local nr = 0
				for spellname, spell in pairs(myself.damagespells) do
					if spell.targets and spell.targets[win.targetname] then
						nr = nr + 1
						local d = win:spell(nr, spellname, spell)

						local myamount = spell.targets[win.targetname].amount or 0
						if P.absdamage and spell.targets[win.targetname].total then
							myamount = spell.targets[win.targetname].total
						end

						d.value = myamount
						d.valuetext = format_value_number(0, myamount, true)

						if win.metadata and d.value > win.metadata.maxvalue then
							win.metadata.maxvalue = d.value
						end
					end
				end
			end
		end
	end

	function spellmod:Enter(win, id, label)
		win.actorid, win.actorname = id, label
		win.title = pformat(L["%s vs %s: Spells"], label, mod.userName)
	end

	function spellmod:Update(win, set)
		win.title = pformat(L["%s vs %s: Spells"], win.actorname, mod.userName)
		if not set or not win.actorname then return end

		local spells, actor = set:GetActorDamageSpells(win.actorid, win.actorname)
		if actor and spells then
			if win.metadata then
				win.metadata.maxvalue = 0
			end

			local nr = 0

			-- same actor?
			if actor.id == mod.userGUID then
				win.title = L["actor damage"](actor.name)

				for spellname, spell in pairs(spells) do
					nr = nr + 1
					local d = win:spell(nr, spellname, spell)

					d.value = spell.amount or 0
					if P.absdamage and spell.total then
						d.value = spell.total
					end

					d.valuetext = Skada:FormatValueCols(mod.metadata.columns.Damage and Skada:FormatNumber(d.value))

					if win.metadata and d.value > win.metadata.maxvalue then
						win.metadata.maxvalue = d.value
					end
				end

				return
			end

			-- collect compared actor's spells.
			local myspells = set:GetActorDamageSpells(mod.userGUID, mod.userName)

			-- iterate comparison actor's spells.
			for spellname, spell in pairs(spells) do
				nr = nr + 1
				local d = win:spell(nr, spellname, spell)

				d.value = spell.amount or 0
				local myamount = 0
				if myspells and myspells[spellname] then
					myamount = myspells[spellname].amount or myamount
				end

				if P.absdamage then
					if spell.total then
						d.value = spell.total
					end
					if myspells and myspells[spellname] and myspells[spellname].total then
						myamount = myspells[spellname].total
					end
				end

				d.valuetext = format_value_number(d.value, myamount, true)

				if win.metadata and d.value > win.metadata.maxvalue then
					win.metadata.maxvalue = d.value
				end
			end

			-- any other left spells.
			if myspells then
				for spellname, spell in pairs(myspells) do
					if not spells[spellname] then
						nr = nr + 1
						local d = win:spell(nr, spellname, spell)

						d.value = spell.amount or 0
						if P.absdamage and spell.total then
							d.value = spell.total or d.value
						end

						d.valuetext = format_value_number(0, d.value, true)

						if win.metadata and d.value > win.metadata.maxvalue then
							win.metadata.maxvalue = d.value
						end
					end
				end
			end
		end
	end

	function targetmod:Enter(win, id, label)
		win.actorid, win.actorname = id, label
		win.title = pformat(L["%s vs %s: Targets"], label, mod.userName)
	end

	function targetmod:Update(win, set)
		win.title = pformat(L["%s vs %s: Targets"], win.actorname, mod.userName)
		if not set or not win.actorname then return end

		local targets, actor = set:GetActorDamageTargets(win.actorid, win.actorname)
		if targets then
			if win.metadata then
				win.metadata.maxvalue = 0
			end

			local nr = 0

			-- same actor?
			if actor.id == mod.userGUID then
				win.title = format(L["%s's targets"], actor.name)

				for targetname, target in pairs(targets) do
					nr = nr + 1
					local d = win:actor(nr, target, true, targetname)

					d.value = target.amount or 0
					if P.absdamage and target.total then
						d.value = target.total or d.value
					end

					d.valuetext = Skada:FormatValueCols(mod.metadata.columns.Damage and Skada:FormatNumber(d.value))

					if win.metadata and d.value > win.metadata.maxvalue then
						win.metadata.maxvalue = d.value
					end
				end
				return
			end

			-- collect compared actor's targets.
			local mytargets = set:GetActorDamageTargets(mod.userGUID, mod.userName, C)

			-- iterate comparison actor's targets.
			for targetname, target in pairs(targets) do
				nr = nr + 1
				local d = win:actor(nr, target, true, targetname)

				d.value = target.amount or 0
				local myamount = 0
				if mytargets and mytargets[targetname] then
					myamount = mytargets[targetname].amount or myamount
				end

				if P.absdamage then
					if target.total then
						d.value = target.total
					end
					if mytargets and mytargets[targetname] and mytargets[targetname].total then
						myamount = mytargets[targetname].total
					end
				end

				d.valuetext = format_value_number(d.value, myamount, true, actor.id == mod.userGUID)

				if win.metadata and d.value > win.metadata.maxvalue then
					win.metadata.maxvalue = d.value
				end
			end

			-- any other left targets.
			if mytargets then
				for targetname, target in pairs(mytargets) do
					if not targets[targetname] then
						nr = nr + 1
						local d = win:actor(nr, target, true, targetname)

						d.value = target.amount or 0
						if P.absdamage and target.total then
							d.value = target.total
						end

						d.valuetext = format_value_number(0, d.value, true, actor.id == mod.userGUID)

						if win.metadata and d.value > win.metadata.maxvalue then
							win.metadata.maxvalue = d.value
						end
					end
				end
			end
		end
	end

	function mod:Update(win, set)
		win.title = format("%s: %s", L["Comparison"], self.userName)

		if set and set:GetDamage() > 0 then
			if win.metadata then
				win.metadata.maxvalue = 0
			end

			local myamount = set:GetActorDamage(mod.userGUID, mod.userName)
			local nr = 0

			for i = 1, #set.players do
				local player = set.players[i]
				if can_compare(player) then
					local dps, amount = player:GetDPS()
					if amount > 0 then
						nr = nr + 1
						local d = win:actor(nr, player)

						d.value = amount
						d.valuetext = Skada:FormatValueCols(
							mod.metadata.columns.Damage and Skada:FormatNumber(d.value),
							mod.metadata.columns.DPS and Skada:FormatNumber(dps),
							format_percent(myamount, d.value, mod.metadata.columns.Percent and player.id ~= mod.userGUID)
						)

						-- a valid window, not a tooltip
						if win.metadata then
							-- color the selected player's bar.
							if player.id == mod.userGUID then
								d.color = COLOR_GOLD
							elseif d.color then
								d.color = nil
							end

							-- order bars.
							if not win.metadata.maxvalue or d.value > win.metadata.maxvalue then
								win.metadata.maxvalue = d.value
							end
						end
					end
				end
			end
		end
	end

	local function set_actor(_, win, id, label)
		-- no DisplayMode func?
		if not win or not win.DisplayMode then return end

		-- same actor or me? reset to the player
		if id == Skada.userGUID or (id == mod.userGUID and win.selectedmode == mod) then
			mod.userGUID = Skada.userGUID
			mod.userName = Skada.userName
			mod.userClass = Skada.userClass
			win:DisplayMode(mod)
		elseif win.GetSelectedSet then
			local set = win:GetSelectedSet()
			local actor = set and set:GetActor(label, id)
			if actor then
				mod.userGUID = actor.id
				mod.userName = actor.name
				mod.userClass = actor.class
				win:DisplayMode(mod)
			end
		end
	end

	function mod:OnEnable()
		dspellmod.metadata = {tooltip = spellmod_tooltip}
		targetmod.metadata = {click1 = dtargetmod}
		spellmod.metadata = {click1 = dspellmod, click2 = bspellmod}
		self.metadata = {
			showspots = true,
			post_tooltip = activity_tooltip,
			click1 = spellmod,
			click2 = targetmod,
			click3 = set_actor,
			click3_label = L["Damage Comparison"],
			columns = {Damage = true, DPS = true, Comparison = true, Percent = true},
			icon = [[Interface\Icons\Ability_Warrior_OffensiveStance]]
		}

		-- no total click.
		self.nototal = true
		spellmod.nototal = true
		targetmod.nototal = true

		self.category = parent.category or L["Damage Done"]
		Skada:AddColumnOptions(self)

		parent.metadata.click3 = set_actor
		parent.metadata.click3_label = L["Damage Comparison"]
		parent:Reload()
	end
end, "Damage")
