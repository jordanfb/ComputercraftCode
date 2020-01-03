--[[
Keeps track of what's in storage and where it goes, and saves it all! Also sends off turtles to fetch items!
This one may also sort between useful and non-useful items? Or maybe that should just be its own turtle so we can have several warehouses, probably that one.


version goals:
v0.1
only load items and store where they're loaded in the item table (only put in items that we don't need because manual removal will mess up the system)
v1.1
retrieve items from a 2d plane
also need to filter out unstackable items

we're going to have some difficulty with retrieval when we're removing items too unless we make a point to not remove the last item, which is legitimate and
probably the simplest option, because otherwise it's a race condition between the fetching robots and the pipes

]]--



local settingsSaveFile = "storagesettings.txt"
local currentActivitySaveFile = "currentActivity.txt"
local itemStorageDataSaveFile = "itemsStored.txt"

local settings = {rednetPrefix = "JORDANSORT", }
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
	for i, v in ipairs(itemsStoredBySlot) do
		-- add them to the itemsStored table, but for now just print them
		print(i .. ": " .. v.item .. " count: " .. v.count .. " max: " .. v.max)
	end
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
	local modded = cache_num
	while modded > fake_caches_per_level do
		modded = modded - fake_caches_per_level -- this is ugly but I don't want to think about mods and off by one errors at the moment
	end
	local cache_width = 0
	if ((modded-1) % (width * 2)) < width then
		-- then it's on the first half of the pipe which goes +x
		cache_width = ((modded-1)%width) + 1
	else
		-- it's on the second half of the pipe that goes -x
		cache_width = width - (((modded-1)%width) + 1)
	end
	local cache_height = 1 -- for now we know it's on the first level FIX
	local cache_depth = math.floor(modded/width)

	-- now we know the coordinates, so we can convert that to index
	return cache_depth * width    +    (cache_height-1) * fake_caches_per_level    +    cache_width
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
			stored_locations[#stored_locations + 1] = {cache_index = cache_index, count = stored}
			amount_left = amount_left - stored
			if amount_left == 0 then
				-- we've stored it all!
				break
			end
		end
	end
	if amount_left > 0 then
		print("MORE LEFT OH NO FIX") -- FIX this please
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

function receive_rednet_input()
	-- for now just return
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
	while true do
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


function main()
	-- main loop
	parallel.waitForAll(receive_rednet_input, sort_input)
end



initialize()
main()