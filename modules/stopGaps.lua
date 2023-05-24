stopGap = {}
stopGap.version = "1.0.4"
stopGap.verbose = false 
stopGap.ssbEnabled = true  
stopGap.ignoreMe = "-sg"
stopGap.requiredLibs = {
	"dcsCommon",
	"cfxZones", 
	"cfxMX",
}
--[[--
	Written and (c) 2023 by Christian Franz 

	Replace all player units with static aircraft until the first time 
	that a player slots into that plane. Static is then replaced with live player unit. 
	
	For aircraft/helo carriers, no player planes are replaced with statics
	
	For multiplayer, StopGapGUI must run on the server (only server)

	STRONGLY RECOMMENDED FOR MISSION DESIGNERS:
	- Use single-unit player groups.
	- Use 'start from ground hot/cold' to be able to control initial aircraft orientation

	To selectively exempt player units from stopGap, add a '-sg' to their name. Alternatively, use stopGap zones 
	
	Version History
	1.0.0 - Initial version
    1.0.1 - update / replace statics after slots become free again
	1.0.2 - DML integration 
	      - SSB integration 
		  - on? 
		  - off?
		  - onStart
		  - stopGap Zones 
	1.0.3 - server plug-in logic
	1.0.4 - player units or groups that end in '-sg' are not stop-gapped
--]]--

stopGap.standInGroups = {}
stopGap.myGroups = {} -- for fast look-up of mx orig data 
stopGap.stopGapZones = {} -- DML only 

--
-- one-time start-up processing
--
-- in DCS, a group with one or more players only allocates when 
-- the first player in the group enters the game. 
--

function stopGap.staticMXFromUnitMX(theGroup, theUnit)
	-- enter with MX data blocks
	-- build a static object from mx unit data 
	local theStatic = {}
	theStatic.x = theUnit.x 
	theStatic.y = theUnit.y 
	theStatic.livery_id = theUnit.livery_id -- if exists 
	theStatic.heading = theUnit.heading -- may need some attention
	theStatic.type = theUnit.type 
	theStatic.name = theUnit.name  -- will magically be replaced with player unit 
	theStatic.cty = cfxMX.countryByName[theGroup.name]
	return theStatic 
end

function stopGap.isGroundStart(theGroup)
	-- look at route 
	if not theGroup.route then return false end 
	local route = theGroup.route 
	local points = route.points 
	if not points then return false end
	local ip = points[1]
	if not ip then return false end 
	local action = ip.action 
	if action == "Fly Over Point" then return false end 
	if action == "Turning Point" then return false end 	
	if action == "Landing" then return false end 	
	-- looks like aircraft is on the ground
	-- but is it in water (carrier)? 
	local u1 = theGroup.units[1]
	local sType = land.getSurfaceType(u1) -- has fields x and y
	if sType == 3 then return false	end 
	if stopGap.verbose then 
		trigger.action.outText("StopG: Player Group <" .. theGroup.name .. "> GROUND BASED: " .. action .. ", land type " .. sType, 30)
	end 
	return true
end

function stopGap.ignoreMXUnit(theUnit)
	local p = {x=theUnit.x, y=0, z=theUnit.y}
	for idx, theZone in pairs(stopGap.stopGapZones) do 
		if theZone.sgIgnore and cfxZones.pointInZone(p, theZone) then 
			return true
		end
	end
	return false
end

function stopGap.createStandInsForMXGroup(group)
	local allUnits = group.units
	if group.name:sub(-#stopGap.ignoreMe) == stopGap.ignoreMe then 
		if stopGap.verbose then 
			trigger.action.outText("+++StopG: <<skipping group " .. group.name .. ">>", 30)
		end
		return nil 
	end
	
	local theStaticGroup = {}
	for idx, theUnit in pairs (allUnits) do 
		if (theUnit.skill == "Client" or theUnit.skill == "Player") 
		   and (theUnit.name:sub(-#stopGap.ignoreMe) ~= stopGap.ignoreMe)
		   and (not stopGap.ignoreMXUnit(theUnit))
		then 
			local theStaticMX = stopGap.staticMXFromUnitMX(group, theUnit)
			local theStatic = coalition.addStaticObject(theStaticMX.cty, theStaticMX)
			theStaticGroup[theUnit.name] = theStatic -- remember me
			if stopGap.verbose then 
				trigger.action.outText("+++StopG: adding static for <" .. theUnit.name .. ">", 30)
			end
		else 
			if stopGap.verbose then 
				trigger.action.outText("+++StopG: <<skipping unit " .. theUnit.name .. ">>", 30)
			end
		end 
	end
	return theStaticGroup
end

function stopGap.initGaps()
	-- turn on. May turn on any time, even during game 
	-- when we enter, all slots should be emptry 
	-- and we populate all slots. If slot in use, don't populate
	-- with their static representations 
	for name, group in pairs (cfxMX.playerGroupByName) do 
		-- check to see if this group is on the ground at parking 
		-- by looking at the first waypoint 
		if stopGap.isGroundStart(group) then 
			-- this is one of ours!
			group.sgName = "SG"..group.name -- flag name for MP
			trigger.action.setUserFlag(group.sgName, 0) -- mark unengaged
			stopGap.myGroups[name] = group

			-- see if this group exists in-game already 
			local existing = Group.getByName(name)
			if existing and Group.isExist(existing) then 
				if stopGap.verbose then 
					trigger.action.outText("+++stopG: group <" .. name .. "> already slotted, skipping", 30)
				end
			else 
				-- replace all groups entirely with static objects 
				---local allUnits = group.units
				local theStaticGroup = stopGap.createStandInsForMXGroup(group)
				-- remember this static group by its real name 
				stopGap.standInGroups[group.name] = theStaticGroup
			end
		end -- if groundtstart
	end
end

function stopGap.turnOff()
	-- remove all stand-ins
	for gName, standIn in pairs (stopGap.standInGroups) do 
		for name, theStatic in pairs(standIn) do 
			StaticObject.destroy(theStatic)
		end
	end
	stopGap.standInGroups = {}
end

function stopGap.turnOn()
	-- populate all empty (non-taken) slots with stand-ins
	stopGap.initGaps()
end
-- 
-- event handling 
--
function stopGap.removeStaticGapGroupNamed(gName)
	for name, theStatic in pairs(stopGap.standInGroups[gName]) do 
		StaticObject.destroy(theStatic)
	end
	stopGap.standInGroups[gName] = nil
end

function stopGap:onEvent(event)
	if not event then return end 
	if not event.id then return end 
	if not event.initiator then return end 
	local theUnit = event.initiator 

	if event.id == 15 then 
		if (not theUnit.getPlayerName) or (not theUnit:getPlayerName()) then 
			return 
		end -- no player unit.
		local uName = theUnit:getName()
		local theGroup = theUnit:getGroup() 
		local gName = theGroup:getName()
		
		if stopGap.myGroups[gName] then
			-- in case there were more than one units in this group, 
			-- also clear out the others. better safe than sorry
			if stopGap.standInGroups[gName] then 
				stopGap.removeStaticGapGroupNamed(gName)
			end
		end
		
		-- erase stopGapGUI flag, no longer required, unit 
		-- is now slotted into 
		trigger.action.setUserFlag("SG"..gName, 0)
	end
end

--
-- update, includes MP client check code
--
function stopGap.update()
	-- check every second. 
	timer.scheduleFunction(stopGap.update, {}, timer.getTime() + 1)
	
	-- check if signal for on? or off? 
	if stopGap.turnOn and cfxZones.testZoneFlag(stopGap, stopGap.turnOnFlag, "change", "lastTurnOnFlag") then
		if not stopGap.enabled then 
			stopGap.turnOn()
		end
		stopGap.enabled = true 
	end
	
	if stopGap.turnOff and cfxZones.testZoneFlag(stopGap, stopGap.turnOffFlag, "change", "lastTurnOffFlag") then
		if stopGap.enabled then 
			stopGap.turnOff()
		end
		stopGap.enabled = false 
	end
	
	if not stopGap.enabled then return end 
	
	-- check if slots can be refilled or need to be vacated (MP) 
	for name, theGroup in pairs(stopGap.myGroups) do 
		if not stopGap.standInGroups[name] then 
			-- if there is no stand-in group, that group was slotted
			-- or removed for ssb
			local busy = true 
			local pGroup = Group.getByName(name)
			if pGroup then 
				if Group.isExist(pGroup) then 
				else
					busy = false -- no longer exists
				end
			else 
				busy = false -- nil group 
			end 
			
			-- now conduct ssb checks if enabled 
			if stopGap.ssbEnabled then 
				local ssbState = trigger.misc.getUserFlag(name)
				if ssbState > 0 then 
					busy = true -- keep busy 
				end
			end
			
			-- check if StopGapGUI wants a word 
			local sgState = trigger.misc.getUserFlag(theGroup.sgName)
			if sgState < 0 then 
				busy = true 
				-- count up for auto-release after n seconds
				trigger.action.setUserFlag(theGroup.sgName, sgState + 1)
			end
			
			if busy then 
				-- players active in this group 
			else 
				local theStaticGroup = stopGap.createStandInsForMXGroup(theGroup)
				stopGap.standInGroups[name] = theStaticGroup
			end	
		else 
			-- plane is currently static and visible
			-- check if this needs to change			
			local removeMe = false 
			if stopGap.ssbEnabled then 
				local ssbState = trigger.misc.getUserFlag(name)
				if ssbState > 0 then removeMe = true end 
			end
			local sgState = trigger.misc.getUserFlag(theGroup.sgName)
			if sgState < 0 then removeMe = true end 
			if removeMe then 
				stopGap.removeStaticGapGroupNamed(name) -- also nils entry
				if stopGap.verbose then 
					trigger.action.outText("+++StopG: [server command] remove static group <" .. name .. "> for SSB/SG server", 30)
				end 				
			end
		end
	end
end

-- 
-- read stopGapZone 
--
function stopGap.createStopGapZone(theZone)
	local sg = cfxZones.getBoolFromZoneProperty(theZone, "stopGap", true)
	if sg then theZone.sgIgnore = false else theZone.sgIgnore = true end 
end

--
-- Read Config Zone
--
stopGap.name = "stopGapConfig" -- cfxZones compatibility here 
function stopGap.readConfigZone(theZone)
	-- currently nothing to do 
	stopGap.verbose = theZone.verbose 
	stopGap.ssbEnabled = cfxZones.getBoolFromZoneProperty(theZone, "sbb", true)
	stopGap.enabled = cfxZones.getBoolFromZoneProperty(theZone, "onStart", true)
	if cfxZones.hasProperty(theZone, "on?") then 
		stopGap.turnOnFlag = cfxZones.getStringFromZoneProperty(theZone, "on?", "*<none>")
		stopGap.lastTurnOnFlag = trigger.misc.getUserFlag(stopGap.turnOnFlag)
	end
	if cfxZones.hasProperty(theZone, "off?") then 
		stopGap.turnOffFlag = cfxZones.getStringFromZoneProperty(theZone, "off?", "*<none>")
		stopGap.lastTurnOffFlag = trigger.misc.getUserFlag(stopGap.turnOffFlag)
	end
	
	if stopGap.verbose then 
		trigger.action.outText("+++StopG: config read, verbose = YES", 30)
		if stopGap.enabled then 
			trigger.action.outText("+++StopG: enabled", 30)
		else 
			trigger.action.outText("+++StopG: turned off", 30)		
		end 
	end
end

--
-- get going 
--
function stopGap.start()
	if not dcsCommon.libCheck("cfx StopGap", 
							  stopGap.requiredLibs) 
	then return false end
	
	local theZone = cfxZones.getZoneByName("stopGapConfig") 
	if not theZone then 
		theZone = cfxZones.createSimpleZone("stopGapConfig")
	end
	stopGap.readConfigZone(theZone)
	
	-- collect exclusion zones
	local pZones = cfxZones.zonesWithProperty("stopGap")
	for k, aZone in pairs(pZones) do
		stopGap.createStopGapZone(aZone)
		stopGap.stopGapZones[aZone.name] = aZone
	end
	
	-- fill player slots with static objects 
	if stopGap.enabled then 
		stopGap.initGaps()
	end 
	
	-- connect event handler
	world.addEventHandler(stopGap)
	
	-- start update in 10 seconds 
	timer.scheduleFunction(stopGap.update, {}, timer.getTime() + 1)
	
	-- say hi!
	trigger.action.outText("stopGap v" .. stopGap.version .. "  running", 30)	
	return true 
end

if not stopGap.start() then 
	trigger.action.outText("+++ aborted stopGap v" .. stopGap.version .. "  -- startup failed", 30)
	stopGap = nil 
end
