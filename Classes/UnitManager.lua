local name,addon=...;

local UnitManager = {
	units = {}
};



--[[----------------------------------------------------------------------------
	Stored Strings
------------------------------------------------------------------------------]]
local party = {};
local raid = {};
local ply = "player";

do
	for i=1,5,1 do party[i] = "party"..i end
	for i=1,40,1 do raid[i] = "raid"..i end
end
	


--[[----------------------------------------------------------------------------
	Cache() - Setup a mapping of Guid to UnitIDs
------------------------------------------------------------------------------]]
function UnitManager:Cache()
	self.units = {};
	
	if ( UnitInRaid(ply) ) then
		local n = GetNumGroupMembers();
		for i=1,n,1 do
			local g = UnitGUID(raid[i]);
			if g then
				self.units[g] = raid[i];
			end
		end	
	elseif ( UnitInParty(ply) ) then
		local n = GetNumGroupMembers();
		for i=1,n,1 do
			local g = UnitGUID(party[i]);
			if g then
				self.units[g] = party[i];
			end
		end
	end
	
	local g = UnitGUID(ply);
	if ( g ) then
		self.units[g] = ply;
	end		
end



--[[----------------------------------------------------------------------------
	Find(guid) - Retrieve UnitID corresponding to the given Guid.
------------------------------------------------------------------------------]]
function UnitManager:Find(guid)
	return self.units[guid];
end



addon.UnitManager = UnitManager;
