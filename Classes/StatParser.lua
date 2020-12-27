local name, addon = ...

--[[----------------------------------------------------------------------------
	Stat conversion factors (data taken from simc)
	https://github.com/simulationcraft/simc/blob/bfa-dev/engine/dbc/generated/sc_scale_data.inc
------------------------------------------------------------------------------]]
local hst_cnv = {
	18.22129252,
	20.11723583,
	22.21045389,
	24.52147334,
	33.00000009
}

local crt_cnv = {
	19.32561328,
	21.33646224,
	23.55654201,
	26.00762324,
	35.00000009
}

local mst_cnv = {
	19.32561328,
	21.33646224,
	23.55654201,
	26.00762324,
	35.00000009
}

local vrs_cnv = {
	22.08641518,
	24.38452828,
	26.92176229,
	29.72299799,
	40.0000001
}

local lee_cnv = {
	11.59536797,
	12.80187735,
	14.1339252,
	15.60457394,
	21.00000006
}

local mna_cnv = {
	5253,
	6170,
	7247,
	8513,
	10000
}

function addon:SetupConversionFactors()
	addon.IntConv = 1.05 --int to SP conversion factor

	local mastery_factor = 1

	if (self:IsRestoDruid()) then
		mastery_factor = 20 / 11
	elseif (self:IsRestoShaman()) then
		mastery_factor = 1 / 3
	elseif (self:IsHolyPriest()) then
		mastery_factor = 4 / 5
	elseif (self:IsHolyPaladin()) then
		mastery_factor = 2 / 3
	elseif (self:IsMistweaverMonk()) then
		mastery_factor = 1 / 3
	elseif (self:IsDiscPriest()) then
		mastery_factor = 5 / 6
	end

	local level = UnitLevel("Player")
	level = math.max(level, 56)
	addon.CritConv = crt_cnv[level - 56 + 1] * 100
	addon.HasteConv = hst_cnv[level - 56 + 1] * 100
	addon.VersConv = vrs_cnv[level - 56 + 1] * 100
	addon.MasteryConv = mst_cnv[level - 56 + 1] * 100 * mastery_factor
	addon.LeechConv = lee_cnv[level - 56 + 1] * 100
	addon.ManaPool = mna_cnv[level - 56 + 1] * 5
end

--[[----------------------------------------------------------------------------
	UpdatePlayerStats - Update stats for current player.
------------------------------------------------------------------------------]]
function addon:UpdatePlayerStats()
	self.ply_sp = GetSpellBonusDamage(4)
	self.ply_crt = GetCritChance() / 100
	self.ply_hst = UnitSpellHaste("Player") / 100
	self.ply_vrs =
		(GetCombatRatingBonus(CR_VERSATILITY_DAMAGE_DONE) + GetVersatilityBonus(CR_VERSATILITY_DAMAGE_DONE)) / 100
	self.ply_mst = GetMasteryEffect() / 100
	self.ply_lee = GetLifesteal() / 100

	--Adjust for haste multiplier effects
	local haste_multiplier = 1
	if
		(addon.BuffTracker:Get(addon.BloodlustId) > 0 or addon.BuffTracker:Get(addon.HeroismId) > 0 or
			addon.BuffTracker:Get(addon.TimewarpId) > 0 or
			addon.BuffTracker:Get(addon.PrimalRageId) > 0)
	 then
		haste_multiplier = haste_multiplier * 1.30
	elseif addon.BuffTracker:Get(addon.DrumsofDeathlyFerocityId) > 0 then
		haste_multiplier = haste_multiplier * 1.15
	end

	if (addon.BuffTracker:Get(addon.BerserkingId) > 0) then
		haste_multiplier = haste_multiplier * 1.15
	end
	if (addon.BuffTracker:Get(addon.Paladin.HolyAvenger) > 0) then
		haste_multiplier = haste_multiplier * 1.30
	end
	self.ply_hst = math.max((1 + self.ply_hst) / haste_multiplier - 1, 0)

	--adjust for intellect multiplier effects
	if (addon.BuffTracker:Get(addon.ArcaneIntellectId) > 0) then
		self.IntConv = 1.05 * 1.1
	else
		self.IntConv = 1.05
	end

	if (addon.BuffTracker:Get(addon.CelestialGuidance) > 0) then
		self.IntConv = self.IntConv * 1.05
	end

	--Adjust for crit bonus effects
	local race = UnitRace("Player")
	self.ply_crtbonus = 1
	if (race == "Tauren") then
		self.ply_crtbonus = self.ply_crtbonus * 1.04 --yes 1.04, not 1.02
	end
	if (addon.critBonus) then
		self.ply_crtbonus = self.ply_crtbonus * (1 + addon.critBonus)
	end
end

--[[----------------------------------------------------------------------------
Basic Stat Derivative Calculations
------------------------------------------------------------------------------]]
--Int
local function _Intellect(ev, s, heal, destUnit, SP, f)
	if (f and f.Intellect) then
		return f.Intellect(ev, s, heal, destUnit, SP)
	end

	if (s.int) then
		return (heal / SP) * addon.IntConv
	end

	return 0
end

--Crit
--CB is a bonus to critical strike healing (Drape of Shame, Tauren Racial, etc)
local function _CriticalStrike(ev, s, heal, destUnit, C, CB, f)
	if (f and f.CriticalStrike) then
		return f.CriticalStrike(ev, s, heal, destUnit, C, CB)
	end

	C = math.min(C, 1.00) --caps crit chance at 100%

	if (s.crt) then
		return heal * CB / (1 + C * CB) / addon.CritConv
	end

	return 0
end

--Haste (returns hpm and hpct values)
local function _Haste(ev, s, heal, destUnit, H, f)
	if (f and f.Haste) then
		return f.Haste(ev, s, heal, destUnit, H)
	end
	if not H then
		return 0
	end
	local canHPM = s.hstHPM or (s.hstHPMPeriodic and ev == "SPELL_PERIODIC_HEAL")
	local canHPCT2 = canHPM and s.hstHPCT
	local canHPCT1 = canHPM or s.hstHPCT

	local hpm = 0
	local hpct = 0

	if (canHPM) then
		hpm = heal / (1 + H) / addon.HasteConv
	end

	if (canHPCT2) then
		hpct = 2 * heal / (1 + H) / addon.HasteConv
	elseif (canHPCT1) then
		hpct = heal / (1 + H) / addon.HasteConv
	end

	if (s.hstHPMequalsHPCT) then
		hpm = hpct
	end

	return hpm, hpct
end

--Vers
local function _Versatility(ev, s, heal, destUnit, V, f)
	if (f and f.Versatility) then
		return f.Versatility(ev, s, heal, destUnit, V)
	end

	if (s.vrs) then
		return heal / (1 + V) / addon.VersConv
	end

	return 0
end

--Mastery
local function _Mastery(ev, s, heal, destUnit, M, ME, f)
	if (f and f.Mastery) then
		return f.Mastery(ev, s, heal, destUnit, M, ME)
	end

	if (s.mst) then
		return heal / (1 + M) / addon.MasteryConv
	end

	return 0
end

--Leech
local function _Leech(ev, s, heal, destUnit, L, f)
	if (f and f.Leech) then
		return f.Leech(ev, s, heal, destUnit, L)
	end

	if s.lee and destUnit ~= "player" and (UnitHealth("player") + (heal * L)) < UnitHealthMax("player") then
		return heal / (1 + L) / addon.LeechConv
	end

	return 0
end

local BaseParsers = {
	Intellect = _Intellect,
	CriticalStrike = _CriticalStrike,
	Haste = _Haste,
	Versatility = _Versatility,
	Mastery = _Mastery,
	Leech = _Leech
}

--[[----------------------------------------------------------------------------
	StatParser - Create & Get combat log parsers for each spec
------------------------------------------------------------------------------]]
local StatParser = {}

--[[----------------------------------------------------------------------------
	Create - add a new stat parser to be used by the addon.
------------------------------------------------------------------------------]]
function StatParser:Create(id, func_I, func_C, func_H, func_V, func_M, func_L, func_HealEvent, func_DamageEvent)
	self[id] = {}
	if (func_HealEvent) then
		self[id].HealEvent = func_HealEvent
	end
	if (func_DamageEvent) then
		self[id].DamageEvent = func_DamageEvent
	end
	if (func_I) then
		self[id].Intellect = func_I
	end
	if (func_C) then
		self[id].CriticalStrike = func_C
	end
	if (func_H) then
		self[id].Haste = func_H
	end
	if (func_V) then
		self[id].Versatility = func_V
	end
	if (func_M) then
		self[id].Mastery = func_M
	end
	if (func_L) then
		self[id].Leech = func_L
	end
end

--[[----------------------------------------------------------------------------
	GetParserForCurrentSpec
------------------------------------------------------------------------------]]
function StatParser:GetParserForCurrentSpec()
	local i = GetSpecialization()
	local specId = GetSpecializationInfo(i)
	return self[specId and tonumber(specId) or 0], specId
end

function StatParser:IncFillerHealing(heal)
	local cur_seg = addon.SegmentManager:Get(0)
	local ttl_seg = addon.SegmentManager:Get("Total")
	if (cur_seg) then
		cur_seg:IncFillerHealing(heal)
	end
	if (ttl_seg) then
		ttl_seg:IncFillerHealing(heal)
	end
end

function StatParser:IncBucket(key, amount)
	local cur_seg = addon.SegmentManager:Get(0)
	local ttl_seg = addon.SegmentManager:Get("Total")

	if (cur_seg) then
		cur_seg:IncBucket(key, amount)
	end
	if (ttl_seg) then
		ttl_seg:IncBucket(key, amount)
	end
end

function StatParser:IncChainSpellCast(spellID)
	local cur_seg = addon.SegmentManager:Get(0)
	local ttl_seg = addon.SegmentManager:Get("Total")

	if (cur_seg) then
		cur_seg:IncChainSpellCast(spellID)
	end
	if (ttl_seg) then
		ttl_seg:IncChainSpellCast(spellID)
	end
end

function StatParser:IncHealing(heal, updateFiller, updateTotal)
	local cur_seg = addon.SegmentManager:Get(0)
	local ttl_seg = addon.SegmentManager:Get("Total")
	if (cur_seg) then
		if (updateFiller) then
			cur_seg:IncFillerHealing(heal)
		end
		if (updateTotal) then
			cur_seg:IncTotalHealing(heal)
		end
	end
	if (ttl_seg) then
		if (updateFiller) then
			ttl_seg:IncFillerHealing(heal)
		end
		if (updateTotal) then
			ttl_seg:IncTotalHealing(heal)
		end
	end
end

function StatParser:Allocate(ev, spellInfo, heal, overhealing, destUnit, f, SP, C, CB, H, V, M, ME, L, intScalar)
	local cur_seg = addon.SegmentManager:Get(0)
	local ttl_seg = addon.SegmentManager:Get("Total")
	local OH = overhealing > 0
	local _I, _C, _Hhpm, _Hhpct, _M, _V, _L = 0, 0, 0, 0, 0, 0, 0

	if (HSW_ENABLE_FOR_TESTING) then
		addon:Msg("allocate spellid=" .. (spellInfo.spellID or "unknown") .. " destunit=" .. destUnit .. " amount=" .. heal)
	end

	if (not OH) then --allocate effective healing
		_I = _Intellect(ev, spellInfo, heal, destUnit, SP, f)
		_C = _CriticalStrike(ev, spellInfo, heal, destUnit, C, CB, f)
		_Hhpm, _Hhpct = _Haste(ev, spellInfo, heal, destUnit, H, f)
		_M = _Mastery(ev, spellInfo, heal, destUnit, M, ME, f)
		_V = _Versatility(ev, spellInfo, heal, destUnit, V, f)
		_L = _Leech(ev, spellInfo, heal, destUnit, L, f)
	else --overhealing with no velens buff, so only possible to attribute leech
		_L = _Leech(ev, spellInfo, heal, destUnit, L, f)
	end

	if (cur_seg) then
		cur_seg:AllocateHeal(_I, _C, _Hhpm, _Hhpct, _V, _M, _L, spellInfo.spellID)
	end
	if (ttl_seg) then
		ttl_seg:AllocateHeal(_I, _C, _Hhpm, _Hhpct, _V, _M, _L, spellInfo.spellID)
	end
	--update display to user
	addon:UpdateDisplayStats()
end

function StatParser:AllocateDamageLeech(ev, spellInfo, amount, L)
	local _L = _Leech(ev, spellInfo, amount, nil, L, nil)
	local cur_seg = addon.SegmentManager:Get(0)
	local ttl_seg = addon.SegmentManager:Get("Total")

	--Track healing amount of filler spells vs overall healing. (For mp5 calculations)
	if (cur_seg) then
		cur_seg:AllocateHeal(0, 0, 0, 0, 0, 0, _L)
	end
	if (ttl_seg) then
		cur_seg:AllocateHeal(0, 0, 0, 0, 0, 0, _L)
	end
end

--[[----------------------------------------------------------------------------
	DecompHealingForCurrentSpec
------------------------------------------------------------------------------]]
function StatParser:DecompHealingForCurrentSpec(ev, destGUID, spellID, critFlag, heal, overhealing)
	local f, specId = self:GetParserForCurrentSpec()

	--check if parser exist for current spec
	if (f) then
		--check if spellInfo is valid for current spec.
		local spellInfo = addon.Spells:Get(spellID)
		if (spellInfo and (spellInfo.spellType == specId or spellInfo.spellType == addon.SpellType.SHARED)) then
			--make sure destGUID describes a valid unit (Exclude healing to pets/npcs)
			local destUnit = addon.UnitManager:Find(destGUID)
			if destUnit then
				--Reduce crit heals down to the non-crit amount
				local OH = overhealing and overhealing > 0
				local orig_heal = heal
				if (critFlag) then
					heal = heal / (1 + addon.ply_crtbonus)
					overhealing = OH and overhealing / (1 + addon.ply_crtbonus) or 0
				end

				--Allow the class parser to do pre-computations on this heal event
				local skipAllocate = false
				if (f.HealEvent) then
					skipAllocate = f.HealEvent(ev, spellInfo, heal, overhealing, destUnit, f, orig_heal)
				end

				--filter out raid cooldowns if we are excluding them
				if (addon.hsw.db.global.excludeRaidHealingCooldowns and spellInfo.cd) then
					return
				end

				--Track healing amount of filler spells vs overall healing. (For mp5 calculations)
				self:IncHealing(orig_heal, spellInfo.filler, true)

				--Allocate healing derivatives for each stat
				if (not skipAllocate) then
					self:Allocate(
						ev,
						spellInfo,
						heal,
						overhealing,
						destUnit,
						f,
						addon.ply_sp,
						addon.ply_crt,
						addon.ply_crtbonus,
						addon.ply_hst,
						addon.ply_vrs,
						addon.ply_mst,
						nil,
						addon.ply_lee
					)
				end
			end
		elseif (not spellInfo) then
			addon:DiscoverIgnoredSpell(spellID)
		end
	end
end

--[[----------------------------------------------------------------------------
	DecompDamageDone
------------------------------------------------------------------------------]]
function StatParser:DecompDamageDone(amt, spellID, critFlag)
	local f, specId = self:GetParserForCurrentSpec()

	local spellInfo = addon.Spells:Get(spellID)
	if (spellInfo and (spellInfo.spellType == specId or spellInfo.spellType == addon.SpellType.SHARED)) then
		if (f and f.DamageEvent) then
			f.DamageEvent(spellInfo, amt, critFlag)
		end

		self:AllocateDamageLeech("SPELL_DAMAGE", spellInfo, amt, addon.ply_lee)
	end
end

--[[----------------------------------------------------------------------------
	DecompDamageTaken
------------------------------------------------------------------------------]]
function StatParser:DecompDamageTaken(amt, dontClamp)
	amt = amt or 0

	if not dontClamp then
		amt = math.min(UnitHealthMax("Player"), amt)
	end

	local V = addon.ply_vrs / 2
	if (V >= 1) then
		return 0
	end

	amt = amt / (1 - V) / (addon.VersConv * 2)

	--Add derivatives to current & total segments
	local cur_seg = addon.SegmentManager:Get(0)
	local ttl_seg = addon.SegmentManager:Get("Total")
	if (cur_seg) then
		cur_seg:AllocateHealDR(amt)
	end
	if (ttl_seg) then
		ttl_seg:AllocateHealDR(amt)
	end
end

--[[----------------------------------------------------------------------------
	IsCurrentSpecSupported - Check if current spec is supported
------------------------------------------------------------------------------]]
function StatParser:IsCurrentSpecSupported()
	local f = self:GetParserForCurrentSpec()

	if (f) then
		return true
	else
		return false
	end
end

addon.BaseParsers = BaseParsers
addon.StatParser = StatParser
