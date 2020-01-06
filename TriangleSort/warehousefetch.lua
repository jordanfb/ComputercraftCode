-- This is my attempt at a warehouse fetching robot, this is my secondish try, so I'm not sure how amazingly it'll go but we'll see what happens!
-- multi-layer, but single robot? Probably. It may make sense to have a fetching robot which simply rotates in place to fetch the most common items such as
-- cobble, we'll see I guess.

--[[


Example warehouse that this turtle can fetch from:

5x5
0th layer:
 -----
|     |
|     |
|     |
|     |
F0    |
 -----

0 = 0,0,0 coordinate (underneath this is the output chest)
F = refueling spot, interact with it by going to 0,0,0 and facing towards 3 (west)

side view:
 -----
| PPPPPP
| ####|P
|     |P
| ####|P
| PPPPPP
| ####|P
|     |P
| ####|P
| PPPPPP
| ####|P
F0    |PI
 E####

0 = 0,0,0 coordinate (underneath this is the output chest)
F = refueling spot, interact with it by going to 0,0,0 and facing towards 3 (west)
# = cache of items
P = refilling pipe
E = output/egress chest
I = input chest/source

Alternatively if the turtle is refilling the caches as well then simply remove the rows with P and the turtle can simply store items as well.

Do we want to support it putting them away too? That would be pretty cool I'll give you that...
May as well? It's not the priority though. We'll support scanning the vertical slice to figure that out




This turtle gets placed by a warehousemaster and is given a mission. that mission can be:
fetch, put, refuel, update, return
and have data associated with it.
when fetch and put end they go to refuel or update or die, and slowly move along the chain to the right because they all eventually return/die.
We're just going to save and load a table on startup from a file (if the file doesn't exist, ask the master for help/a mission)
data = {
		position = {x = 1, y = 1, z = 1, f = 2},
		mission = "fetch", item = {x=4, y=5, z=8, f="up", key="minecraft:stone-0", count = 128, index = cache_index},
		min_refuel_level = 1000, refuel_to_level = 5000
		update_after = false,
		output_coords = {x = 100, y = 100, z = 100, f = "down"},
		refuel_coords = {x = 100, y = 100, z = 100, f = "down"},
		die_coords = {x = 101, y = 100, z = 100, f = 1,2,3,4(north, east south west)}
		}
When asking for help (and initializing) this entire table gets sent to the turtle so that we can update settings easier on the master.
The master will have to keep track of which turtles have been updated after it gets told to update and which haven't, which is a bit of a pain
but it just goes in the status table which gets saved.

it should update in front of the die/return coords since it can just ask to be eaten. No need to restart since it'll get forcefully restarted once placed.
Die also has to delete the table keeping track of current mission.


-- Important rednet things:
"fetch_turtle_request_mission" -- send this to your storage master to get a new mission
"fetch_turtle_assign_mission" -- receive this from your storage master to know what to do


]]--

-- Settings:
local goalFuelLevel = 6000
local minimumFuelLevel = 1000
local zGoesUp = true -- if +z goes up then true. If +z goes down then false
local settings_path = "fetch_turtle_settings.txt"
local position_file_path = "position_file.txt"
local mission_filepath = "mission_file.txt"
local time_between_mission_requests = 10 -- ask every 10 seconds if we don't have a mission
local network_prefix = "JORDANSORT"

-- Runtime variables:

local storageWidth = 0 -- x
local storageLength = 0 -- y
local storageHeight = 0 -- z
local storageHeightPerLayer = 0 -- z height between access layers for the turtle
-- possible heights per layer = 1:
-- 2, which is an inefficient single layer of caches that the turtle fills
-- 3, which is a effecient double layer of caches that the turtle fills
-- 4, which is a efficient 2 layer of caches and 1 of pipes that are automatically refilled

local facing = 2
local x = 1
local y = 1
local z = 1
local mission = {}

readyForService = false


-- if we don't get told where they are these are the defaults
local width = 8
local depth = 16
local fetch_bot_start_position = {x = 1, y = 1, z = 1, f = 2} -- depends on how you place the fetch bots into the world. My current method places them facing south (N=0, E=1, S=2, W=3)
local output_coords = {x = width, y = depth, z = 1, f = "down"}
local refuel_coords = {x = width+1, y = depth, z = 1, f = "down"}
local die_coords = {x = width+3, y = depth, z = 1, f = 1} -- die coords are currently facing east


-- function ZeroPosition()
-- 	readyForService = false
-- 	if not turtle.detectUp() and not turtle.detectDown() do
-- 		-- it's in the shaft!
-- 		ZeroPositionFromShaft()
-- 	end
-- 	while turtle.detectUp() and turtle.detectDown() do
-- 		turtle.turnRight()
-- 		while turtle.forward() do
-- 			-- go forward into the wall
-- 		end
-- 	end
-- 	-- now we know that it's at the vertical shaft at (0,0) -- EXCEPT THAT THERE ARE GOING TO BE TWO VERTICAL SHAFTS NOW FIX THIS
-- 	if zGoesUp then
-- 		while turtle.down() do
-- 			-- head to the bottom layer!
-- 		end
-- 	else
-- 		-- the tower is inverted!
-- 		while turtle.up() do
-- 		end
-- 	end

-- 	facing = 3
-- 	x = 0
-- 	y = 0
-- 	z = 0
-- 	readyForService = true
-- end

-- function ZeroPositionFromShaft()
-- 	-- if the turtle is in the vertical shaft already then it needs to zero in a special way. It first has to go to the bottom, then zero again
-- 	readyForService = false
-- 	if zGoesUp then
-- 		while turtle.down() do
-- 			-- head to the bottom layer!
-- 		end
-- 	else
-- 		-- the tower is inverted!
-- 		while turtle.up() do
-- 		end
-- 	end
-- 	while not turtle.detect() do
-- 		-- turn until it's facing the corner
-- 	end
-- 	while turtle.detect() do
-- 		-- turn until it's facing open air
-- 		turtle.turnRight()
-- 	end
-- 	turtle.turnLeft() -- then turn back one so we know it's facing the right way

-- 	facing = 2
-- 	x = 0
-- 	y = 0
-- 	z = 0
-- 	readyForService = true
-- end

-- function ScanStorageDimensions()
-- 	-- scan the width and height of the zeroth level, and also scan the height of each layer so we know where to go.
-- 	-- this is because the setups could either be setups where turtles both store and retrieve or it could be a setup where pipes store and turtles retrieve
-- 	-- and that changes the y levels of the passageways
-- 	ScanStorageLevel()
-- 	ScanStorageHeight()

-- 	print("Scanned storage dimensions: x = " .. storageWidth .. ", y = " .. storageLength .. ", z = " .. storageHeight .. ". Height per layer is = " .. storageHeightPerLayer)
-- end

-- function ScanStorageLevel()
-- 	-- scan the width and length of a storage level
-- 	pathfindToFacing(0, 0, 0, 0) -- look north
-- 	-- then count how far forward (y) you can go
-- 	storageWidth = 0 -- x
-- 	storageLength = 0 -- y
-- 	while not turtle.detect() do
-- 		goForward()
-- 		storageLength = storageLength + 1
-- 	end
-- 	-- then measure width
-- 	turnRight()
-- 	while not turtle.detect() do
-- 		goForward()
-- 		storageWidth = storageWidth + 1
-- 	end
-- end

-- function ScanStorageHeight()
-- 	-- scan the storage height and space between layers
-- 	pathfindToFacing(0, 0, 0, 0) -- face north so we can see where the passageways are
-- 	storageHeight = 0
-- 	storageHeightPerLayer = 0
-- 	local scanningHeightPerLayer = 0
-- 	while not turtle.detectUp() do
-- 		goUp()
-- 		storageHeight = storageHeight + 1
-- 		scanningHeightPerLayer = scanningHeightPerLayer + 1
-- 		if (not turtle.detect())
-- 			-- then we've found a passage!
-- 			if storageHeightPerLayer ~= 0 then
-- 				-- only compare it and print out if we have an error
-- 				if scanningHeightPerLayer ~= storageHeightPerLayer then
-- 					-- the heights are wrong!
-- 					print("ERROR! Wrong sized scanningHeightPerLayer: "..scanningHeightPerLayer .. " instead of correct: " ..storageHeightPerLayer)
-- 				end
-- 			else
-- 				-- we've found out the height per layer! set it!
-- 				storageHeightPerLayer = scanningHeightPerLayer
-- 			end
-- 			scanningHeightPerLayer = 0
-- 		end
-- 	end
-- end

-- function ScanAllItems()
-- 	-- go through all items in the setup and record where they are, then tell the storage master or whoever wants to know
-- 	-- this is VERY SLOW
-- end

function SaveTableToFile(table, filename)
	if filename == nil or table == nil then
		print("Error can't save file something is nil")
		return -- can't save nothing
	end
	local f = fs.open(filename, 'w');
	if f == nil then
		print("Error opening file " .. tostring(filename))
		return -- error opening the file
	end
	f.write(textutils.serialize(table));
	f.close();
end

function LoadTableFromFile(filename)
	-- loads the table or nil if there's no file
	if filename == nil or not fs.exists(filename) then
		return {} -- can't load nothing
	end
	local f = fs.open(filename, 'r')
	if f == nil then
		return {} -- error opening file
	end
	local serializedTable = f.readAll()
	f.close()
	return textutils.unserialize( serializedTable )
end

function goUp()
	if zGoesUp then
		while not turtle.up() do
		end
	else
		-- the tower is inverted
		while not turtle.down() do
		end
	end
	z = z + 1
	save_position()
end

function goDown()
	if (zGoesUp) then
		while not turtle.down() do
		end
	else
		-- the tower is inverted
		while not turtle.up() do
		end
	end
	z = z - 1
	save_position()
end

function left()
	turtle.turnLeft()
	facing = facing - 1
	if facing < 0 then
		facing = 3
	end
	save_position()
end

function right()
	turtle.turnRight()
	facing = facing + 1
	facing = facing % 4
	save_position()
end

function goForward()
	while not turtle.forward() do
	end
	if facing == 0 then -- north
		y = y + 1
	elseif facing == 1 then -- east
		x = x + 1
	elseif facing == 2 then -- south
		y = y - 1
	elseif facing == 3 then -- west
		x = x - 1
	end
	save_position()
end

function goBackwards()
	while not turtle.back() do
	end

	if facing == 0 then -- north
		y = y - 1
	elseif facing == 1 then -- east
		x = x - 1
	elseif facing == 2 then -- south
		y = y + 1
	elseif facing == 3 then -- west
		x = x + 1
	end
	save_position()
end

function pathfindToFacing(goalx, goaly, goalz, goalf)
	pathfindTo(goalx, goaly, goalz)
	-- then turn to face the correct direction!
	turnToFacing(goalf)
end

function pathfindTo(goalx, goaly, goalz)
	-- move to this position.
	if (goalz ~= z) then
		-- move to the vertical path to go up or down levels
		pathfind2D(1, 1)
	end
	-- fix the height!
	pathfindZ(goalz)
	-- then go to the correct x and y
	pathfind2D(goalx, goaly)
	-- then we're there!
end

function pathfindZ(goalZ)
	while goalZ < z do
		goDown()
	end
	while goalZ > z do
		goUp()
	end
end

function turnToFacing(goalF)
	-- turn to face this direction!
	if (goalF == "up" or goalF == "down" or goalF == 4 or goalF == 5) then
		return -- you're always facing up and down so ignore that
	end
	if (goalF == 0 and facing == 3) then
		right()
	elseif (goalF == 3 and facing == 0) then
		left()
	else
		-- otherwise just compare the numbers and turn!
		local deltaF = goalF - facing
		while (deltaF > 0) do
			right()
			deltaF = goalF - facing
		end
		while (deltaF < 0) do
			left()
			deltaF = goalF - facing
		end
	end
end

function pathfind2D(goalx, goaly)
	-- first move x then y? it doesn't really matter in the end
	local deltaX = goalx - x
	while deltaX > 0 do
		turnToFacing(1) -- go east
		goForward()
		deltaX = goalx - x
	end
	while deltaX < 0 do
		turnToFacing(3) -- go west
		goForward()
		deltaX = goalx - x
	end
	local deltaY = goaly - y
	while deltaY > 0 do
		turnToFacing(0) -- go north
		goForward()
		deltaY = goaly - y
	end
	while deltaY < 0 do
		turnToFacing(2) -- go south
		goForward()
		deltaY = goaly - y
	end
end

function returnToBase()
	-- return to refueling station
	pathfindToFacing(0, 0, 0, 3)
end

function checkRefuel()
	-- do this before any mission to get or store items
	if turtle.getFuelLevel() == "unlimited" then
		return -- unlimited fuel we're set
	end
	if turtle.getFuelLevel() < minimumFuelLevel then
		refuel()
	end
end

function suck_direction(direction, amount)
	turnToFacing(direction)
	-- then suck!
	if direction == 4 or direction == "up" then
		return turtle.suckUp(amount)
	elseif direction == 5 or direction == "down" then
		return turtle.suckDown(amount)
	else
		return turtle.suck(amount)
	end
end

function drop_direction(direction, amount)
	turnToFacing(direction)
	-- then suck!
	if direction == 4 or direction == "up" then
		return turtle.dropUp(amount)
	elseif direction == 5 or direction == "down" then
		return turtle.dropDown(amount)
	else
		return turtle.drop(amount)
	end
end

function select_first_empty_slot()
	for i = 1, 16 do
		if turtle.getItemCount(i) == 0 then
			turtle.select(i)
			return
		end
	end
end

function refuel()
	if (turtle.getFuelLimit() == "unlimited") then
		return -- we're all set
	end
	pathfindToFacing(refuel_coords.x, refuel_coords.y, refuel_coords.z, refuel_coords.f)
	select_first_empty_slot()
	while turtle.getFuelLevel() < math.min(goalFuelLevel, turtle.getFuelLimit()) do
		suck_direction(refuel_coords.f, 1)
		turtle.refuel()
		drop_direction(refuel_coords.f, 1)
	end
end





-- additional helper functions
function load_settings()
	if fs.exists(settings_path) then
		settings.load(settings_path)
		print("Found settings")
	else
		first_initialization = true
		print("Entering Initial Configuration")
		-- copy over the startup file
		fs.delete("/startup.lua")
		fs.copy("ComputercraftCode/TriangleSort/warehousefetchstartup.lua", "/startup.lua")
		print("Copied over startup file")

		save_settings()
	end
end

function save_settings()
	settings.save(settings_path)
end

function load_position()
	-- load the position from the position file
	local pos_t = LoadTableFromFile(position_file_path)
	if pos_t.x == nil then
		-- we don't know where we are
		print("Unable to load position from file")
		return
	end
	x = pos_t.x
	y = pos_t.y
	z = pos_t.z
	facing = pos_t.facing
	print("Position Loaded: <" .. tostring(x) .. ", " .. tostring(y) .. ", " .. tostring(z) .. "> facing " .. tostring(facing))
end

function save_position()
	local pos_t = {x = x, y = y, z = z, facing = facing}
	SaveTableToFile(pos_t, position_file_path)
end

function initialize_network()
	-- check what network connection we have.
	-- it's either a wired modem behind it (in which case it shouldn't turn because it'll lose the network) or a wireless modem
	-- on it in which case it can turn just fine
	print("Initializing Rednet network")
	local peripherals = peripheral.getNames()
	for i = 1, #peripherals do
		-- check if one of them is a modem of some type and if so use it
		local currname = peripherals[i]
		local currtype = peripheral.getType(currname)
		if currtype == "wired_modem" or currtype == "wireless_modem" or currtype == "ender_modem" or currtype == "modem" then
			-- chose it!
			print("Found " .. currtype .. " at " .. currname)
			modem_side = currname
			break
		end
	end
	if not rednet.isOpen(modem_side) then
		-- if rednet isn't open, try opening it and then see if that works
		rednet.open(modem_side)
		if not rednet.isOpen(modem_side) then
			print("Error opening rednet, this will likely cause errors")
		end
	end
end

function connect_to_master()
	-- should probably connect to the master no matter what, but you have to figure out if you have a mission or not
	local time_since_request = time_between_mission_requests
	while true do
		if time_since_request >= time_between_mission_requests then
			-- send a request!
			request_mission()
			time_since_request = 0
		end
		sleep(1)
		if mission ~= nil and mission.mission ~= nil then
			-- we have a mission!
			break
		end
		time_since_request = time_since_request + 1
	end
end

function request_mission()
	print("Requesting mission. Currently broadcasting because unsure what id the master is")
	local packet = {packet = "fetch_turtle_request_mission"}
	rednet.broadcast(packet, network_prefix)
end


--[[
mission = {
		position = {x = 1, y = 1, z = 1, f = 1},
		mission = "fetch",
		item = {x=4, y=5, z=8, f="up", key="minecraft:stone-0", count = 128},
		min_refuel_level = 1000, refuel_to_level = 5000
		update_after = false,
		refuel_coords = {x = 100, y = 100, z = 100, f = "down"},
		die_coords = {x = 101, y = 100, z = 100, f = 1,2,3,4(north, east south west)}
		}

]]--
function load_mission_from_file()
	-- if you have a mission saved then load it!
	if not fs.exists(mission_filepath) then
		-- no mission file! return
		print("No mission saved")
		return
	end
	local t = LoadTableFromFile(mission_filepath)
	if t.mission == nil then
		-- we don't know where we are
		print("Unable to load mission from file")
		return
	end
	-- now set our mission table to be this table probably?
	mission = t
	parse_mission_variables()
end

function save_mission_to_file()
	-- save the mission to a file so you can resume it later
	SaveTableToFile(mission, mission_filepath)
end

function destroy_mission_file()
	-- delete the mission file
	fs.delete(mission_filepath)
end

function test_pathfinding()
	-- for now just pathfind around!
	print("Testing pathfinding!")
	local goalx = 1
	local goaly = 1
	local goalz = 1
	local goalf = 0
	while true do
		local x = read_in_number("Enter x coordinate or 'quit'", true)
		if x == "quit" then
			break
		else
			goalx = tonumber(x)
			goaly = tonumber(read_in_number("Enter y coordinate", false))
			goalz = tonumber(read_in_number("Enter z coordinate", false))
			goalf = tonumber(read_in_number("Enter facing direction 0-3", false))
			-- now go to the coordinates!
			pathfindToFacing(goalx, goaly, goalz, goalf)
		end
	end
end

function read_in_number(prompt, allow_quit)
	local input = "no"
	while tonumber(input) == nil do
		print(prompt)
		input = string.lower(read())
		if allow_quit then
			if input == "quit" or input == "q" then
				return "quit"
			end
		end
	end
	return input
end

function update_code()
	shell.run("github clone jordanfb/ComputercraftCode")
	fs.delete("/startup.lua")
	fs.copy("ComputercraftCode/TriangleSort/warehousefetchstartup.lua", "/startup.lua")
end

function kill_self()
	-- delete your mission file then die!
	if (y ~= die_coords.y and x ~= die_coords.x) then
		-- pathfind to the output station since we could hit something by accident
		pathfindToFacing(output_coords.x, output_coords.y, output_coords.z, output_coords.f)
	end
	checkRefuel() -- check whether or not we need to refuel
	if (y ~= die_coords.y and x ~= die_coords.x) then
		-- pathfind to the output station since we could hit something by accident
		pathfindToFacing(output_coords.x, output_coords.y, output_coords.z, output_coords.f)
	end
	pathfindToFacing(die_coords.x, die_coords.y, die_coords.z, die_coords.f)
	if mission.update_after then
		-- update your code!
		update_code()
	end
	destroy_mission_file()
	-- probably should message the warehousemaster that we're dying but idk...
	redstone.setOutput("front", true)
end

function startup()
	load_position()
	load_settings()
	load_mission_from_file()
	-- ZeroPosition() -- don't do this anymore because it's not working and it's not necessary we know where we are
	initialize_network()
	connect_to_master()
end

function output_items()
	-- go to the output chest and empty everything into it
	pathfindToFacing(output_coords.x, output_coords.y, output_coords.z, output_coords.f)
	for i = 1, 16 do
		turtle.select(i)
		drop_direction(output_coords.f) -- drop them to the output chest
	end
	-- after you're done outputing then you go die
	mission.mission = "die"
	save_mission_to_file()
end

function fetch_items()
	-- go to the item coordinates then get the items you're told to get! Tell the master if you can't find the right items
	if mission.item == nil or mission.item.key == nil then
		-- we don't know what we're getting and something has gone wrong! Tell the master this but for now just print I guess
		print("ERROR FETCHING MISSION DOESN'T HAVE DATA")
		return
	end
	pathfindToFacing(mission.item.x, mission.item.y, mission.item.z, mission.item.f)
	organize_inventory() -- so there's space to input the items
	while mission.item.count > 0 do
		local amount_in_inventory = count_items_of_key(mission.item.key)
		suck_direction(mission.item.f, math.min(mission.item.count, 64))
		local amount_gathered = count_items_of_key(mission.item.key) - amount_in_inventory
		mission.item.count = mission.item.count - amount_gathered
		save_mission_to_file()
		organize_inventory()
		if amount_gathered == 0 and mission.item.count > 0 then
			-- ERROR the number gathered isn't what was expected somehow... ooops
			-- eventually I should error and tell the sorting machine that this errored but for now just don't and accept this fact?
			-- fix
			break -- since we likely won't be able to finish extracting this many items without waiting forever.
		end
	end
	mission.mission = "output"
	save_mission_to_file()
end

function get_item_key(item_table)
	return item_table.name .. "-"..item_table.damage
end

function count_items_of_key(item_key)
	-- need to figure out how many items you have of the type
	local count = 0
	for i = 1, 16 do
		local i_item_key = get_item_key(turtle.getItemDetail(i))
		if i_item_key == item_key then
			count = count + turtle.getItemCount(i)
		end
	end
	return count
end

function organize_inventory()
	for i = 16, 1, -1 do
		-- move things towards the beginning
		if turtle.getItemCount(i) > 0 then
			turtle.select(i)
			for j = 1, i-1 do
				turtle.transferTo(j)
			end
		end
	end
end


--[[
mission = {
		position = {x = 1, y = 1, z = 1, f = 1},
		mission = "fetch",
		item = {x=4, y=5, z=8, f="up", key="minecraft:stone-0", count = 128},
		min_refuel_level = 1000, refuel_to_level = 5000
		update_after = false,
		refuel_coords = {x = 100, y = 100, z = 100, f = "down"},
		die_coords = {x = 101, y = 100, z = 100, f = 1,2,3,4(north, east south west)}
		}

]]--


function store_items()
	-- -- go to the item coordinates then get the items you're told to get! Tell the master if you can't find the right items
	-- if mission.item == nil or mission.item.x == nil then
	-- 	-- we don't know what we're getting and something has gone wrong! Tell the master this but for now just print I guess
	-- 	print("ERROR STORING MISSION DOESN'T HAVE DATA")
	-- 	return
	-- end
	-- pathfindToFacing(mission.item.x, mission.item.y, mission.item.z, mission.item.f)
	print("ERROR STORING ITEMS NOT HANDLED YET")
	mission.mission = "die"
end

function handle_mission()
	while true do
		if mission == nil or mission.mission == nil then
			-- try to figure out what mission you have from the master.
			connect_to_master()
		elseif mission.mission == "die" then
			-- go die!
			kill_self()
		elseif mission.mission == "output" then
			-- dump what you have in the inventory to the output chest
			output_items()
		elseif mission.mission == "store" then
			-- go store items
			store_items()
		elseif mission.mission == "fetch" then
			-- go get items
			fetch_items()
		end
	end
end

--[[
mission = {
		position = {x = 1, y = 1, z = 1, f = 1},
		mission = "fetch",
		item = {x=4, y=5, z=8, f="up", key="minecraft:stone-0", count = 128},
		min_refuel_level = 1000, refuel_to_level = 5000
		update_after = false,
		refuel_coords = {x = 100, y = 100, z = 100, f = "down"},
		die_coords = {x = 101, y = 100, z = 100, f = 1,2,3,4(north, east south west)}
		}

]]--
function parse_mission_variables()
	-- copy the positions and variables and settings from the mission table to our variables
	if mission == nil then
		return -- don't have any data
	end
	if mission.die_coords ~= nil then
		die_coords = mission.die_coords
	end
	if mission.refuel_coords ~= nil then
		refuel_coords = mission.refuel_coords
	end
	if mission.output_coords ~= nil then
		output_coords = mission.output_coords
	end
	if mission.fetch_bot_start_position ~= nil then
		fetch_bot_start_position = mission.position
		-- also copy the position directly over probably?
		x = fetch_bot_start_position.x
		y = fetch_bot_start_position.y
		z = fetch_bot_start_position.z
		facing = fetch_bot_start_position.f
	end
	if mission.min_refuel_level ~= nil then
		minimumFuelLevel = mission.min_refuel_level
	end
	if mission.refuel_to_level ~= nil then
		goalFuelLevel = mission.refuel_to_level
	end
end

function receive_rednet_input()
	-- this function is used by the parallel api to manage the rednet side of things
	while running do
		local sender_id, message, received_protocol = rednet.receive(network_prefix)
		if verbose then
			print("Recieved rednet input: " .. message.packet)
		end
		-- figure out what to do with that message
		if message.packet == "fetch_turtle_assign_mission" then
			-- you've gotten a mission! Yay!
			print("Recieved mission!")
			mission = message.data
			save_mission_to_file()
			parse_mission_variables()
		end
	end
end

function main()
	startup()
	-- then go into your main loop!
	-- if you know your mission then just carry it out!
	parallel.waitForAll(receive_rednet_input, handle_mission)
end


main()