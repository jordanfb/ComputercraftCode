--[[
Keeps track of what's in storage and where it goes, and saves it all! Also sends off turtles to fetch items!
This one may also sort between useful and non-useful items? Or maybe that should just be its own turtle so we can have several warehouses, probably that one.


version goals:
v0.1
DONE: only load items and store where they're loaded in the item table (only put in items that we don't need because manual removal will mess up the system)
v1.0
DONE: code to set up turtles and fetch requests on warehousemaster side
DONE: code to request a fetch of something on the terminal side
retrieve items from a 2d plane when requested and can handle restarts apart from terrible edge cases
retrieval bots refuel when needed
retrieval bots update when told to
DONE: rednet connection to other computers and ability to send what we have in storage
DONE: rednet request items fetched
v1.1
also need to figure out what to do if something goes wrong and the items aren't where you expect them, but maybe we'll just accept that for now
		-- it's simple enough to just have the fetcher say "I tried to fetch this many of this but I got this many of that instead" and then the master can just
			update the tallys of both and add the request back to the stack? That'll likely fuck up item prediction though...
			maybe a v1.1 issue :P
need to filter out unstackable items presumably in a earlier turtle that goes to the "junk" storage. Alternatively I need to be able to empty caches better
	so we can store it then remove it. But we still don't want things like used shovels etc. going into storage so we do need it at some point yeah.
	-- maybe we just ignore it for now and say "don't put things in/be very careful?" We can push this back to a v1.1 issue after which we'll be able to empty
		caches and the problem kinda goes away... but still yeah the used tool side which is kinda junk...
code to fetch something on the display side (perhaps integrate it with the scrolling item display? That would be simple enough and make sense and be awesome)
be able to empty caches and still predict where items will go
integration with custom orders (have an option to fetch the items as well)
v1.2
error handling, perhaps worst case scenario I have it empty all the items from a cache so we know it's empty or move them to another cache
swapping item caches on request of an operator
	-- what happens when an item is moving towards a cache but the cache gets filled? What happens when there's an alternative? What happens when there isn't one?



we're going to have some difficulty with retrieval when we're removing items too unless we make a point to not remove the last item, which is legitimate and
probably the simplest option, because otherwise it's a race condition between the fetching robots and the pipes.
That said it's a sucky condition and I don't like it. Perhaps have a temporary chest where I can wait for all the turtles to stop going and then go send them out
so we know exactly where they are? That may be the nicest since I do want to be able to empty caches... It's a pain.

I really do need some preliminary junk sorting that gets sent a list of items that are in the storage system and everything else by default gets ignored.
That's simple enough although it does require some rednet but that's not terrible. There already is an unused chest underneath it, so I can use it for that if
I want to. Estimated 1 block per second for the pipe, and it's 128 blocks per level for the worst case scenario. waiting 3 minutes for the items to settle 
should be good for any number of levels really, which means that if we want to empty a cache you need to freeze items for three minutes then get it then
release all the items. Which kinda sucks. Arguably items that will go earlier than that emptied cache can still be released actually so that's not terrible.
Plus, we can still retrieve items as long as we don't empty other caches... Really cache emptying sucks.
For now I guess it's just "sleep three minutes then go empty the cache then wait a minute for the turtle to get there then release the items?" It'll slow down
inputting items into the system but for the vast majority of cases we care about retrieval times more. We'll be running those in parallel so should
automatically keep fetching items as long as we have a boolean to check about emptying the cache so we only empty one cache at once.

Honestly just start with not emptying it and the unstackable/unsortable/junk sorting and work from there. Then go to crafting turtles, then monitoring turtles!
Then you have basically everything.
]]--


--[[
Current todo as of 1/5/2020 12:38 pm
-- DONE: need to subtract the items from our stored item table that we've told the turtle to retrieve
-- DONE: need to add a secondary fetch for all the items that we weren't able to fit in that cache/that turtle/whatever so it can send another turtle.
need to make the turtle go fetch the items
need to make the turtle tell the master if it hasn't been able to extract all those items so the master can make another fetch request
make it account for time for item travel. Can we assume that after the computer/server restarted it was long enough for the items to traverse?
	I'm not sure, maybe hold all the fetching for a minute or so? That'll be annoying to test. I guess we should just continue on as though time never
	stopped to make sure.
make it account for emptying caches with item travel! :P



check the version plan :P
Test out the update ticker display display and see if it works!
]]--


local cache_sizes = {20000, 80000, 180000, 320000, 500000} -- basic, hardened, reinforced, signalium, resonant
local noncaches = {1, 128} -- where we have holes in the cache levels and no caches, so these indices can't be used

local width = 8
local depth = 16
local height = 1


local settingsSaveFile = "storagesettings.txt"
local currentActivitySaveFile = "currentActivity.txt"
local itemStorageDataSaveFile = "itemsStored.txt"
local fetchRequestsFilename = "fetchRequests.txt"
local fetchBotStatusFilename = "fetchBotsStatus.txt"

local tunnel_separation = 4 -- spaces between tunnel holes, for pipe filled things it should be 4, for turtle filled it should be 3

local fetch_bot_start_position = {x = 1, y = 1, z = 1, f = 2} -- depends on how you place the fetch bots into the world. My current method places them facing south (N=0, E=1, S=2, W=3)
local output_coords = {x = width, y = depth, z = 1, f = "down"}
local refuel_coords = {x = width+1, y = depth, z = 1, f = "down"}
local die_coords = {x = width+2, y = depth, z = 1, f = 1} -- die coords are currently facing east


local max_items_stored_in_turtle = 64 * 16
-- an idea about the maximum number of stacks we can store in a turtle. This is obviously higher than plenty of cases but we need to have a maximum.
-- if it turns out a turtle doesn't have space for it then it'll create a new fetch request for another turtle to handle it. This is just to ensure that if
-- we have truly massive orders that we deal with them semi-efficiently

local settings = {network_prefix = "JORDANSORT", }
network_prefix = "JORDANSORT"
local spawn_turtle_redstone_side = "right"
local currentActivity = {}
local itemsStoredBySlot = {} -- look up what's in what slot, stored by cache index NOT PIPE INDEX
--[[
1={item = item_key, count = 100, max=20000}
]]--
local itemsStored = {} -- look up if we have an item stored and if so, which slots and how much

local fetch_requests = {}
-- fetch requests numeric_key = {item = {key=item_key, count = 10000, exact_number=true}, requesting_computer = rednet_id, status= "waiting","assigned","done"}
-- there's no way to get rid of fetch_requests, with the idea that if we no longer need iron ingots for instance it'll get sent back to storage anyways
-- that's not quite true in special cases like fetching iron ore from storage because it'll get processed automatically but I don't think we'll be storing that anyways :P
-- the only real issue with that is if I create a fetch request for some item we don't have and it sits and waits for ages. Maybe we do need a timeout on requests.
-- at the same time if the system is down then I don't want to lose things per say? But it's not too big a deal if it's keeping track of what minecraft day it was
-- requested in and times out after like a minecraft week.
-- exact number being false means that if there are fewer then that many items in storage currently it'll just get all that it can then remove the mission.
-- if it needs the exact number then it'll keep this fetch mission here until it gets the exact values requested, the idea is that if you're requesting
-- iron or something it'll likely get processed and snagged by the custom order directly without actually going to storage, so it'll solve the problem itself and
-- we don't have to wait for storage to fetch slowly.
local fetch_bot_status = {} -- status of fetch bots, rednet_id = {updated = true, mission=fetch_request[whatevermission]}

local subscribed_to_storage_changes = {} -- gets reset every update so when a machine sees that you exist it'll ask, so we don't need to save this
-- just a list of rednet_ids

-- calculated during initialization
local num_caches = 0
local num_fake_caches = 0
local fake_caches_per_level = 0

master_id = -1
modem_side = ""
reboot = false -- this is used to reboot everything after recieving this from the network
running = true


function initialize()
	print("Starting Warehouse Master v0.1")
	loadFiles()
	if settings == nil then
		-- initialize a new setup!
		-- for now v0.1 there is no setup I guess?
	end
	num_caches = getCacheCount()
	num_fake_caches = getFakeCacheCount()
	fake_caches_per_level = width * depth
	print(num_caches .. " caches. " .. num_fake_caches .. " fake caches.")
	initialize_network()
	broadcast_existence()
	updateTurtleSpawning() -- check if there are unresolved fetch requests and spawn turtles if there are!
end

function loadFiles()
	-- load all the files
	if fs.exists(settingsSaveFile) then
		settings.load(settingsSaveFile)
		print("Found settings")
	else
		first_initialization = true
		print("Entering Initial Configuration")
	end
	loadItemsStored()
	load_fetch_status()
end

function save_fetch_status()
	-- save fetch_requests and fetch_bot_status
	SaveTableToFile(fetch_requests, fetchRequestsFilename)
	SaveTableToFile(fetch_bot_status, fetchBotStatusFilename)
end

function load_fetch_status()
	-- load fetch_requests and fetch_bot_status
	fetch_requests = LoadTableFromFile(fetchRequestsFilename)
	fetch_bot_status = LoadTableFromFile(fetchBotStatusFilename)
end

function saveItemsStored()
	if itemStorageDataSaveFile == nil or itemsStoredBySlot == nil then
		return -- can't save nothing
	end
	local f = fs.open(itemStorageDataSaveFile, 'w');
	if f == nil then
		return -- error opening the file
	end
	f.write(textutils.serialize(itemsStoredBySlot));
	f.close();
end

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

function getCacheCount()
	-- calculate the number of caches we can use!
	return (width * depth - #noncaches) * height
end

function getFakeCacheCount()
	-- calculate the number of caches we can use!
	return (width * depth) * height
end

function loadItemsStored()
	-- loads the table or nil if there's no file
	if itemStorageDataSaveFile == nil or not fs.exists(itemStorageDataSaveFile) then
		return {} -- can't load nothing
	end
	local f = fs.open(itemStorageDataSaveFile, 'r')
	if f == nil then
		return {} -- error opening file
	end
	local serializedTable = f.readAll()
	f.close()
	itemsStoredBySlot = textutils.unserialize( serializedTable )
	BuildItemsStoredToSlotTable()
end

function BuildItemsStoredToSlotTable()
	-- when loading files we load using this
	itemsStored = {}
	-- print("Should be printing all the items now")
	for i, v in pairs(itemsStoredBySlot) do
		-- add them to the itemsStored table, but for now just print them
		-- print(i .. ": " .. v.item .. " count: " .. v.count .. " max: " .. v.max)
		if itemsStored[v.item] == nil then
			itemsStored[v.item] = {count = 0, locations = {}}
		end
		-- now add the item stored to the table
		itemsStored[v.item].count = itemsStored[v.item].count + v.count
		itemsStored[v.item].locations[#itemsStored[v.item].locations + 1] = {index = i, max = v.max, count = v.count}
	end
	return itemsStored
end





-- function GetFirstEmptySlot()
-- 	-- return the first empty slot
-- 	for i = 1, #itemsStoredBySlot do
-- 		--
-- 		if itemsStoredBySlot[i] == nil then
-- 			-- we don't like this it's not valid
-- 			print("Nil slot in items stored by slot")
-- 		else
-- 			--
-- 		end
-- 	end
-- end

function is_real_cache(cache_num)
	local modded = cache_num
	while modded > fake_caches_per_level do
		modded = modded - fake_caches_per_level -- this is ugly but I don't want to think about mods and off by one errors at the moment
	end
	for i, v in ipairs(noncaches) do
		if v == modded then
			return false -- it's not a cache
		end
	end
	return true -- it's a real boy
end

function unit_test_pipe_conversions()
  local correct = true
  for i = 1, 10000 do
    local converted = convert_pipe_to_index(i)
    local converted_back = convert_index_to_pipe(converted)
    if converted_back ~= i then
      print("ERROR CONVERTING ".. i)
      print(i .. ": " .. converted .. " " .. converted_back)
      correct = false
    end
  end
  if correct then
    print("Completed without errors!")
  else
    print("ERRORED")
  end
  return correct
end

function convert_pipe_to_index(pipe_number)
	local modded = pipe_number
	while modded > fake_caches_per_level do
		modded = modded - fake_caches_per_level -- this is ugly but I don't want to think about mods and off by one errors at the moment
	end
	local cache_width = 0
	if ((modded-1) % (width * 2)) < width then
		-- then it's on the first half of the pipe which goes +x
		cache_width = ((modded-1)%width) + 1
	else
		-- it's on the second half of the pipe that goes -x
		cache_width = width - (((modded-1)%width))
	end
	local cache_height = math.floor((pipe_number-1) /fake_caches_per_level)+1
	local cache_depth = math.floor((modded-1)/width) + 1 -- 1 indexed

	-- now we know the 1 indexed coordinates, so we can convert that to actual index
	return (cache_depth-1) * width    +    (cache_height-1) * fake_caches_per_level    +    cache_width
end

function convert_index_to_pipe(cache_index)
	-- cache index is the nicely ordered, left to right, front to back, bottom to top
	-- pipe_order is the snakey method that zigzags all over the place
	local modded = cache_index
	while modded > fake_caches_per_level do
		modded = modded - fake_caches_per_level -- this is ugly but I don't want to think about mods and off by one errors at the moment
	end
	local cache_width = 0
	if ((modded-1) % (width * 2)) < width then
		-- then it's on the first half of the pipe which goes +x
		cache_width = ((modded-1)%width) + 1
	else
		-- it's on the second half of the pipe that goes -x
		cache_width = width - (((modded-1)%width))
	end
	local cache_height = math.floor((cache_index-1) /fake_caches_per_level)+1
	local cache_depth = math.floor((modded-1)/width) + 1 -- 1 indexed

	-- now we know the 1 indexed coordinates, so we can convert that to actual index
	return (cache_depth-1) * width    +    (cache_height-1) * fake_caches_per_level    +    cache_width
end

function convert_index_to_cache_coordinates(cache_index)
	-- this is the index that goes left to right front to back then bottom to top. NOT PIPE ORDER
	local modded = cache_index
	while modded > fake_caches_per_level do
		modded = modded - fake_caches_per_level -- this is ugly but I don't want to think about mods and off by one errors at the moment
	end
	local cache_width = ((modded-1)%width) + 1
	local cache_height = math.floor((cache_index-1) /fake_caches_per_level)+1
	local cache_depth = math.floor((modded-1)/width) + 1 -- 1 indexed

	return {x = cache_width, y = cache_depth, z = cache_height, count = itemsStoredBySlot[cache_index].count}
end

function convert_index_to_physical_coordinates(cache_index)
	-- this is the index that goes left to right front to back then bottom to top. NOT PIPE ORDER
	local modded = cache_index
	while modded > fake_caches_per_level do
		modded = modded - fake_caches_per_level -- this is ugly but I don't want to think about mods and off by one errors at the moment
	end
	local cache_width = ((modded-1)%width) + 1
	local cache_height = math.floor((cache_index-1) /fake_caches_per_level)+1
	local cache_depth = math.floor((modded-1)/width) + 1 -- 1 indexed

	local tunnel_height = math.floor((cache_height-1)/2) * tunnel_separation + 1 -- add the 1 because 1,1,1 is the starting position
	local cache_is_on_bottom = (cache_height - 1) % 2
	local facing = "up"
	if (cache_is_on_bottom) then
		-- go one up and face down.
		facing = "down"
	end

	return {x = cache_width, y = cache_depth, z = tunnel_height, f = facing, count = itemsStoredBySlot[cache_index].count}
end

function how_much_stored_here(cache_index, item, count)
	-- returns the amount stored
	local item_in_slot = itemsStoredBySlot[cache_index]
	if item_in_slot == nil then
		-- it's probable that we can store here so do so
		itemsStoredBySlot[cache_index] = {} -- new empty table
		-- for now just make it a default cache... FIX
		itemsStoredBySlot[cache_index].max = cache_sizes[1]
		itemsStoredBySlot[cache_index].count = 0
		itemsStoredBySlot[cache_index].item = ""
		item_in_slot = itemsStoredBySlot[cache_index]
	end
	if item_in_slot.item == nil or item_in_slot.item == "" or item_in_slot.item == item then
		-- figure out how much can be stored here and return that
		local space_left = item_in_slot.max - item_in_slot.count
		return math.min(space_left, count)
	end
	return 0 -- can't store it here!
end

function WhereWillItemsEndUp(item, count)
	-- figure out where this item will end up
	local amount_left = count
	local stored_locations = {}
	for i = 1, num_fake_caches do
		-- if it's a real cache, check if we can store in it
		if is_real_cache(i) then
			local cache_index = convert_pipe_to_index(i)
			-- can it fit there? if so, how much?
			local stored = how_much_stored_here(cache_index, item, amount_left)
			if (stored > 0) then
				stored_locations[#stored_locations + 1] = {cache_index = cache_index, count = stored}
				amount_left = amount_left - stored
				if amount_left == 0 then
					-- we've stored it all!
					break
				end
			end
		end
	end
	if amount_left > 0 then
		print("MORE LEFT OH NO FIX ERROR") -- FIX this please, this will happen if we run out of caches
	end
	return stored_locations
end

function steralize_item_table(item_table)
	-- if item_table == nil then -- I'd kinda prefer it to error out which is why I'm commenting this out
	-- 	return {}
	-- end
	local t = {name=item_table.name, damage=item_table.damage}
	return t
end

function get_item_key(item_table)
	return item_table.name .. "-"..item_table.damage
end

function get_items_count_table()
	-- gets a clean table of just the items we have and their quantities wait maybe not it includes other things but that's not terrible
	-- it'll work just don't edit this only send it places :P
	BuildItemsStoredToSlotTable()
	-- local t = {}
	-- for k, v in pairs(itemsStored) do
	-- 	-- build this table with just the count. Or do we include locations? fuck it, may as well
	-- end
	return itemsStored
end

function receive_rednet_input()
	-- this function is used by the parallel api to manage the rednet side of things
	while running do
		local sender_id, message, received_protocol = rednet.receive(network_prefix)
		-- figure out what to do with that message
		if message.packet == "reboot_network" then
			-- quit this loop
			running = false
			reboot = true
			break
		elseif message.packet == "update_network" then
			-- update from github!
			shell.run("github clone jordanfb/ComputercraftCode")
			-- copy the startup file into the main place
			fs.delete("/startup.lua")
			fs.copy("ComputercraftCode/TriangleSort/warehousemasterstartup.lua", "/startup.lua")
			-- then reboot
			running = false
			reboot = true
			break
		elseif message.packet == "quit_network" then
			-- quit this loop
			running = false
			reboot = false
			break
		elseif message.packet == "get_stored_items" then
			-- tell that sender what items we have stored and what quantities but strip out the boring stuff.
			local data = {items = get_items_count_table(), id = ""..os.getComputerID(), label = os.getComputerLabel(), rednet_id = os.getComputerID()}
			local packet = {packet = "send_stored_items", data = data}
			rednet.send(sender_id, packet, network_prefix)
		elseif message.packet == "get_storage_nodes" then
			-- a new computer has joined the network, tell it what we are connected to!
			-- tell them who we are!
			-- tell them that you're a storage master machine!
			local data = {id = ""..os.getComputerID(), label = os.getComputerLabel(), rednet_id = os.getComputerID()}
			local packet = {packet = "add_storage_node", data = data}
			rednet.send(sender_id, packet, network_prefix)  -- tell them who I am
		elseif message.packet == "set_master_id" then
			master_id = message.data
		elseif message.packet == "fetch_items" then
			-- message.data = {item = {key=item_key, count = 10000, exact_number=false}, requesting_computer = rednet_id}
			print("Recieved fetch request")
			print("Fetch request for: ")
			print(message.data.item.key)
			print(message.data.item.count)
			message.data.status = "waiting" -- it's not done so make it wait!
			fetch_requests[#fetch_requests+1] = message.data
			-- then save it, and also update whether or not we're spawning more turtles!
			save_fetch_status()
			updateTurtleSpawning()
		elseif message.packet == "fetch_turtle_request_mission" then
			-- a fetch turtle is requesting its mission. Assign it to a mission or tell it to return if there are no missions.
			assign_fetch_turtle(sender_id)
			updateTurtleSpawning()
		elseif message.packet == "update_storage_network" then
			-- go through all the turtles and tell them to update when they get released!
			for k, v in pairs(fetch_bot_status) do
				v.updated = false
			end
			save_fetch_status()
		elseif message.packet == "subscribe_to_storage_changes" then
			-- this is a message so that I can send that computer changes in item storage amounts so we can display them etc.
			-- it's meant to be used for a ticker etc. that displays storage changes.
			local already_subscribed = false
			for i, v in ipairs(subscribed_to_storage_changes) do
				if v == sender_id then
					already_subscribed = true
					break
				end
			end
			if not already_subscribed then
				print("New subscriber to storage changes with id: " .. sender_id)
				subscribed_to_storage_changes[#subscribed_to_storage_changes + 1] = sender_id -- so we can send it item storage updates!
			end
		end
	end
end

function send_item_storage_updates(item_key, change, total_count)
	-- tell them that things changed!
	-- also tell them who we are
	local data = {key = item_key, change = change, count = total_count, storage_master_id = os.getComputerID()}
	local packet = {packet = "storage_change_update", data = data}
	for i, id in ipairs(subscribed_to_storage_changes) do
		-- send it to them
		rednet.send(id, packet, network_prefix)
	end
end

function get_cache_coords(item_key, amount_requested)
	-- return nil if it's not valid
	-- {x = 0, y = 1, z = 1, f = fasljkd, count = amount_in_this_cache}
	-- prioritize the farthest away cache that has enough items to fufil the request? That way when we eventually empty caches we'll move things towards
	-- if none of them can handle it then it should take the farthest one that's larger than 1? I guess?
	-- the front of the sorting machine which makes sense to me.
	-- FIX this will require 1 extra item over the amount requested because we can't handle emptying caches at the moment
	amount_requested = amount_requested + 1
	print("Finding cache coords for " .. tostring(item_key))
	local items = itemsStored[item_key]
	if items == nil then
		-- we don't have any stored, return nil
		print("Don't have any of the item somehow")
		return nil
	end
--[[
		if itemsStored[v.item] == nil then
			itemsStored[v.item] = {count = 0, locations = {}}
		end
		-- now add the item stored to the table
		itemsStored[v.item].count = itemsStored[v.item].count + v.count
		itemsStored[v.item].locations[#itemsStored[v.item].locations + 1] = {index = i, max = v.max, count = v.count}
]]--
	-- loop over all the locations and check which ones are the best!
	local bestLocation = {count = -1, index = -1}

	for k, v in pairs(items.locations) do
		if bestLocation.count >= amount_requested then
			-- we've found a cache that can handle the request, so don't give up on that
			if v.count >= amount_requested and convert_index_to_pipe(v.index) > convert_index_to_pipe(bestLocation.index) then
				-- replace it we've found a better canidate
				bestLocation = v
			end
		else
			-- otherwise just take the latest cache that's larger than 1
			if v.count > 1 and convert_index_to_pipe(v.index) > convert_index_to_pipe(bestLocation.index) then
				-- replace it we've found a better canidate, although it still doesn't store all the items we want it to
				bestLocation = v
			end
		end
	end

	if bestLocation.count <= 1 then
		-- we don't have enough of the item
		-- FIX this when we allow clearing caches
		print("Best location has 1 or fewer items")
		return nil
	end

	-- otherwise we have our location! now figure out the coordinates!
	local location = convert_index_to_physical_coordinates(bestLocation.index)
	location.index = bestLocation.index
	print("Found viable location")
	return location
end

function assign_fetch_turtle(rednet_id)
	-- assign the turtle to a mission or tell it to return to base
	-- if we aren't tracking that bot already then add it to our list of bots to track
	-- local fetch_bot_status = {} -- rednet_id = {updated = true, current_mission=fetch_request[whatevermission]}
	if fetch_bot_status[rednet_id] == nil then
		-- add it to the list!
		fetch_bot_status[rednet_id] = {updated = true, mission = nil, rednet_id = rednet_id}
		save_fetch_status()
	end

	-- now that we've added it to the list, give it a mission if we have any missions
	for i, v in ipairs(fetch_requests) do
		-- check if they're unresolved and can be fetched
-- fetch requests numeric_key = {item = {key=item_key, count = 10000, exact_number=true}, requesting_computer = rednet_id, status= "waiting","assigned","done"}
		if v.status == "waiting" then
			-- check if we have the items to return!
			-- if we have the items then spawn a turtle. If we don't have the items and exact_number = false then we delete this request.
			print("Found possible waiting mission")
			if v.item == nil or v.item.count == nil or v.item.count <= 0 then
				-- skip it! it's a done or a bad thing!
				-- fetching_requests_to_remove[#fetching_requests_to_remove + 1] = i
			else
				-- if there are positive items requested and we have some of its type in the storage system then spawn turtles!
				local amount_stored = safe_get_item_count(v.item.key)
				if amount_stored > 0 then
					print("Storing > 0 of the item")
					-- here's where we're able to assign it to the turtle!
					-- send this fetch_request to the turtle along with other data to help it on its way.
--[[
data = {
		position = {x = 1, y = 1, z = 1, f = 1}, mission = "fetch", item = {x=4, y=5, z=8, f="up", key="minecraft:stone-0", count = 128},
		min_refuel_level = 1000, refuel_to_level = 5000
		update_after = false,
		refuel_coords = {x = 100, y = 100, z = 100, f = "down"},
		die_coords = {x = 101, y = 100, z = 100, f = 1,2,3,4(north, east south west)}
		}
]]--
					-- then add the items coordinates to this!
					local cache_coords = get_cache_coords(v.item.key, v.item.count)
					if cache_coords ~= nil then
						print("Cache coords is not nil")
						local data = {position = fetch_bot_start_position,
									update_after = not fetch_bot_status[rednet_id].updated,
									min_refuel_level = 1000,
									refuel_to_level = 5000,
									output_coords = output_coords,
									refuel_coords = refuel_coords,
									die_coords = die_coords,

									mission = "fetch",
									item = v.item,
								}
						data.item.x = cache_coords.x
						data.item.y = cache_coords.y
						data.item.z = cache_coords.z
						data.item.f = cache_coords.f
						data.item.index = cache_coords.index
						data.item.count = math.min(math.min(v.item.count, cache_coords.count - 1), max_items_stored_in_turtle)
						-- for now just don't allow removing items entirely so we don't
						-- run into the problem of race conditions. I'll have to FIX it later
						local amount_left_to_fetch = v.item.count - data.item.count -- that's how many left to fetch

						-- v.status = "assigned"
						v.status = "done" -- it'll just delete it now which is fine I think. later I want status though FIX THIS

						-- now tell the turtle to do this! and create another fetch item to deal with the remnants that we weren't able to fetch this time
						local packet = {packet = "fetch_turtle_assign_mission", data = data}
						rednet.send(rednet_id, packet, network_prefix)
						print("Sent to " .. tostring(rednet_id))
						fetch_bot_status[rednet_id].mission = data -- assign the current mission
						-- subtract the items that we're fetching from the items stored
						-- FIX to allow for emptying caches!
						if itemsStoredBySlot[data.item.index] == nil then
							print("ERROR items not in slot somehow oh god this is terrible")
							itemsStoredBySlot[data.item.index] = {count = 0, max = cache_sizes[1], item=""} -- made it a default cache FIX
						end
						itemsStoredBySlot[data.item.index].count = itemsStoredBySlot[data.item.index].count - data.item.count
						BuildItemsStoredToSlotTable() -- update the table!
						saveItemsStored() -- save the item changes!
						send_item_storage_updates(data.item.key, -data.item.count, itemsStored[data.item.key].count) -- send an update to computers that are subscribed!

						-- -- save the fetch bot status
						-- save_fetch_status()

						if amount_left_to_fetch > 0 then
							print("Creating secondary fetch request to deal with large request")
							-- create another fetching request that asks for the rest and insert it into the table right after this current element so it's prioritized
							-- {item = {key=item_key, count = 10000, exact_number=true}, requesting_computer = rednet_id, status= "waiting","assigned","done"}
							local new_request = {item = {key = v.item.key, count = amount_left_to_fetch, exact_number = v.item.exact_number}, requesting_computer = v.requesting_computer, status = "waiting"}
							table.insert(fetch_requests, new_request, i+1)
						end
						-- save fetchbot status and new request!
						save_fetch_status()
						return true -- we've found what it should do so we've told it what to do!
					end
				elseif amount_stored == 0 and v.item.exact_number == false then
					-- skip it because we don't have it so it's accounted for!
					-- add it to the list of things to remove
					-- fetching_requests_to_remove[#fetching_requests_to_remove + 1] = i
					print("Amount stored is 0")
				end
			end
		end
	end

	-- if we get here we wern't able to find what the turtle should do, so I guess the turtle should go destroy itself and this should print an error?
	print("ERROR: Fetch turtle has no task")
	local data = {
		position = fetch_bot_start_position,
		update_after = not fetch_bot_status[rednet_id].updated,
		min_refuel_level = 1000,
		refuel_to_level = 5000,
		output_coords = output_coords,
		refuel_coords = refuel_coords,
		die_coords = die_coords,

		mission = "die", -- just immediately go die I guess to clear the way :P
	}
	local packet = {packet = "fetch_turtle_assign_mission", data = data}
	rednet.send(rednet_id, packet, network_prefix)
	fetch_bot_status[rednet_id].mission = data -- assign the current mission
	save_fetch_status()
	return false -- didn't give a good mission
end

function safe_get_item_count(item_key)
	if itemsStored[item_key] == nil then
		return 0
	end
	return itemsStored[item_key].count
end

function updateTurtleSpawning()
	-- if there are unresolved missions that we can fetch then keep spawning turtles so that it'll eventually spawn!
	local spawning = false
	local fetching_requests_to_remove = {}
	for i, v in ipairs(fetch_requests) do
		-- check if they're unresolved and can be fetched
-- fetch requests numeric_key = {item = {key=item_key, count = 10000, exact_number=true}, requesting_computer = rednet_id, status= "waiting","assigned","done"}
		if v.status == "waiting" then
			-- check if we have the items to return!
			-- if we have the items then spawn a turtle. If we don't have the items and exact_number = false then we delete this request.
			if v.item == nil or v.item.count == nil or v.item.count <= 0 then
				-- remove it! it's a done or a bad thing!
				fetching_requests_to_remove[#fetching_requests_to_remove + 1] = i
			else
				-- if there are positive items requested and we have some of its type in the storage system then spawn turtles!
				local amount_stored = safe_get_item_count(v.item.key)
				if amount_stored > 0 then
					spawning = true
				elseif amount_stored <= 1 and v.item.exact_number == false then
					-- remove it because we don't have it so it's accounted for!
					-- add it to the list of things to remove
					-- FIX when we update it to support cleaning out caches we have to make this a 0 not a 1
					fetching_requests_to_remove[#fetching_requests_to_remove + 1] = i
				end
			end
		elseif v.status == "done" then
			-- remove it! it's done!
			fetching_requests_to_remove[#fetching_requests_to_remove + 1] = i
		end
	end

	redstone.setOutput(spawn_turtle_redstone_side, spawning)

	for i = #fetching_requests_to_remove, 1, -1 do
		-- remove it from the fetching_requests table! this will be from highest index to lowest, so the indices stay correct
		table.remove(fetch_requests, fetching_requests_to_remove[i])
	end
	if #fetching_requests_to_remove > 0 then
		save_fetch_status() -- save it after removing fetched items
	end
end

function connect_to_sorting_network()
	-- tell everyone you're a sorting robot
	local data = {id = ""..os.getComputerID(), label = os.getComputerLabel()}
	-- send it out to the sorting network!
	local packet = {packet = "add_storage_node", data = data}
	rednet.broadcast(packet, network_prefix)  -- tell them who I am
end

function add_item_to_storage(item_key, item_count)
	local cache_ids = WhereWillItemsEndUp(item_key, item_count)
	-- now add it to those caches
	for k, v in ipairs(cache_ids) do
		-- apply those changes to the stored items!
		if itemsStoredBySlot[v.cache_index] == nil then
			itemsStoredBySlot[v.cache_index] = {count = 0, max = cache_sizes[1], item=""} -- made it a default cache FIX
		end
		itemsStoredBySlot[v.cache_index].item = item_key
		itemsStoredBySlot[v.cache_index].count = itemsStoredBySlot[v.cache_index].count + v.count
		print("item: " ..item_key .. " added to cache " .. v.cache_index .. " with count " .. itemsStoredBySlot[v.cache_index].count)
	end
	BuildItemsStoredToSlotTable()
	send_item_storage_updates(item_key, item_count, itemsStored[item_key].count) -- send an update to computers that are subscribed!
end

function sort_current()
	if turtle.getItemCount() == 0 then
		return false -- it's already dealt with for whatever reason
	end
	local item = turtle.getItemDetail()
	local item_count = turtle.getItemCount()
	local sterile_item = steralize_item_table(item)
	local item_key = get_item_key(item)

	-- if it's in the system somewhere then add it to this
	add_item_to_storage(item_key, item_count)
	turtle.dropUp()
	return true
end

function sort_input()
	while running do
		-- input items from the chest in front of it, then if they deserve to go into storage store them. If they don't then don't
		-- turtle.select(1)
		while turtle.suck() do
			-- it's sorting time!
			if (sort_current()) then
				saveItemsStored() -- save the changes you've made!
			end
			-- turtle.select(1)
		end
		sleep(2)
	end
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

function broadcast_existence()
	local data = {id = ""..os.getComputerID(), label = os.getComputerLabel(), rednet_id = os.getComputerID()}
	local packet = {packet = "add_storage_node", data = data}
	rednet.broadcast(packet, network_prefix)  -- tell everyone who I am
end

function shut_down_network()
	rednet.close(modem_side)
	print("Shut down Rednet network")
end

function deinitialization()
	shut_down_network()
end


function main()
	initialize()

	-- main loop
	parallel.waitForAll(receive_rednet_input, sort_input)


	deinitialization() -- I don't know if this will get run so who knows....
	if reboot then
		-- restart the computer
		print("Restarting computer")
		os.reboot()
	else
		print("Quitting sorting program")
	end
end


main()