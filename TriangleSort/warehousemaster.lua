--[[
Keeps track of what's in storage and where it goes, and saves it all! Also sends off turtles to fetch items!
This one may also sort between useful and non-useful items? Or maybe that should just be its own turtle so we can have several warehouses, probably that one.


version goals:
v0.1
DONE: only load items and store where they're loaded in the item table (only put in items that we don't need because manual removal will mess up the system)
v1.1
need to filter out unstackable items presumably in a earlier turtle that goes to the "junk" storage. Alternatively I need to be able to empty caches better
so we can store it then remove it. But we still don't want things like used shovels etc. going into storage so we do need it at some point yeah.
retrieve items from a 2d plane when requested
retrieval bots refuel when needed
also need to figure out what to do if something goes wrong and the items aren't where you expect them, but maybe we'll just accept that for now
rednet connection to other computers and ability to send what we have in storage

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



local settingsSaveFile = "storagesettings.txt"
local currentActivitySaveFile = "currentActivity.txt"
local itemStorageDataSaveFile = "itemsStored.txt"

local settings = {network_prefix = "JORDANSORT", }
network_prefix = "JORDANSORT"
local currentActivity = {}
local itemsStoredBySlot = {} -- look up what's in what slot, stored by cache index NOT PIPE INDEX
--[[
1={item = item_key, count = 100, max=20000}
]]--
local itemsStored = {} -- look up if we have an item stored and if so, which slots and how much


local cache_sizes = {20000, 80000, 180000, 320000, 500000} -- basic, hardened, reinforced, signalium, resonant
local noncaches = {1, 128} -- where we have holes in the cache levels and no caches, so these indices can't be used

local width = 8
local depth = 16
local height = 1

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
	local cache_height = 1 -- for now we know it's on the first level FIX
	local cache_depth = math.floor((modded-1)/width) + 1 -- 1 indexed

	-- now we know the 1 indexed coordinates, so we can convert that to actual index
	return (cache_depth-1) * width    +    (cache_height-1) * fake_caches_per_level    +    cache_width
end

function convert_index_to_coordinates(cache_index)
	-- this is the index that goes left to right front to back then bottom to top. NOT PIPE ORDER

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
		elseif message.packet == "get_sorting_network_connections" or message.packet == "get_storage_nodes" then
			-- a new computer has joined the network, tell it what we are connected to!
			-- tell them who we are!
			-- tell them that you're a storage master machine!
			local data = {id = ""..os.getComputerID(), label = os.getComputerLabel(), rednet_id = os.getComputerID()}
			local packet = {packet = "add_storage_node", data = data}
			rednet.send(sender_id, packet, network_prefix)  -- tell them who I am
		elseif message.packet == "set_master_id" then
			master_id = message.data
		end
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


function main()
	-- main loop
	parallel.waitForAll(receive_rednet_input, sort_input)
end



initialize()
main()