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
-- DONE: need to make the turtle go fetch the items
need to make the turtle tell the master if it hasn't been able to extract all those items so the master can make another fetch request
make it account for time for item travel. Can we assume that after the computer/server restarted it was long enough for the items to traverse?
	I'm not sure, maybe hold all the fetching for a minute or so? That'll be annoying to test. I guess we should just continue on as though time never
	stopped to make sure.
make it account for emptying caches with item travel! :P


Cache emptying plan:
rednet thread receives request that would empty cache.
It calculates the amount of time to reach that cache and then pauses inputting items for that long.
This also needs to handle rebooting unfortunately, which means if it reboots it waits the whole amount of time all over again just to be sure.
Before it waits that amount of time it spawns a turtle, and tells that turtle it has to request permission to empty items.
If the turtle asks before that time is up the turtle must wait until we are ready and then ask again.
When we are ready and the turtle asks us if we're ready we tell it yes. We are. Then we wait until it tells us it's done before allowing items
to flow again. That is the point at which we empty the cache in our calculations.

We need to be able to interupt the other thread when it's sucking in items so we don't suck one in when we don't mean to.
We also need to recover if we reboot in the middle, so we have to both keep track of the time we need to wait and store that in a file somewhere.
We also need to store a list of all the caches we're emptying at this particular point so that we can empty multiple caches at once but not exit early.
If we wanted to speed things up slightly we can store the last time an item was input to the system so we know we can wait that amount less time.
Obviously if it reboots it still has to wait the full amount of time since we don't know when we rebooted.
That's pretty solid and pretty easy all things considered.
It means that we'd stop inputting items for about two minutes every once in a while, so we should probably make a couple chests of space in front of the
storagemaster I'm forgetting the word but like places to store backlog? Like the area of storage before a machine that's its buildup? Like a cache? or a queue?
I'm not sure... But extra chests before the warehousemaster so that we can empty the main sorting system and not develop a backlog there.


Cache emptying steps:
-- DONE: calculate time for items to their caches
-- DONE: test turtles that need to check in with the master before getting items by implementing the rednet and having it wait a few seconds before saying yes
		in order to test this part quickly
-- DONE: figure out which fetch requests are going to empty a cache
-- DONE: save and load that you're going to empty a cache and the amount of time and time started waiting etc. and start waiting and whether or not you should be inputting items (interupting the other thread to make sure it stops)
-- DONE: wait that amount of time before saying that you're good to gather the items. Perhaps this is handled by the input_item thread starting a timer and waiting for it in a different function?
		that would be very handy and give that thread something to do. Plus then we know for sure that we've stopped inputting items and in a nice way too.
-- DONE: Then when the turtle reports back that it's finished we check to make sure we aren't waiting for any other turtles to empty caches, and if so, we go back to normal sorting!
-- DONE: Should we gather all our emptying cache requests to handle at once? If we have to empty two caches and we only have one turtle do we wait until the turtle
		gets placed in the world to pause items? Or do we have two requests that will empty the cache so we start pausing and don't stop until we have both requests.
		The second one makes more sense to me (where we handle them all as soon as they come in) because otherwise we're going to need to wait the full two minutes all over again. As it is that may happen
		but only if we get one order right after the other one ends, and that would still be an issue if we waited for the turtle to be in the world before pausing the items again.
		This means that we have to save the list of caches that are going to be emptied, but at this point we may be having a file dedicated to saving and loading cache the cache empty status.

Possible Improvements:
Make a "special machine monitor" which waits for no redstone signal (and probably an extra couple seconds or so in the case of the crafting machine) from the machine before inserting a custom order.
Use the special machine monitor in conjunction with a crafting turtle that recieves custom destinations and crafts items!
Save and load the custom destinations on the main sorting line between restarts. I'm not sure why I haven't done that yet.
Make a multi-computer rednet system for storing and retreiving data and use it for item names and recipes. Perhaps depending on if there's only a file size limit and not a ram limit but we could load files from different floppy disks to get around the storage limit.
Recursive recipe requesting/crafting
Add a crafting button to the fetch GUI program for turtles and for the monitors
	add a simple line or two on the display for how many items will be fetched and how many will be crafted
Add a "max amount stored" button and item count display to the fetch item screen
Speed up the cache emptying by splitting up which cache needs to wait for how long.
Speed up the cache emptying by figuring out ACTUALLY how long the warehouse fetchbot needs to wait inbetween checking because as it is it's waiting extra long adding delays
Speed up cache emptying by accounting for the additional time that we haven't put anything into the system for (doesn't work and has to reset when restarted but that's no biggie)
Add more turtles to the fetch system
Make a "fetch only" portable pocket computer for the average consumer. Perhaps make it check in with the master computer and update if the master computer says it should? Similar to the warehouse fetch bot updates
Make those pocket computers and ender pouches for everyone on the server!
Make physical setups for a couple places around the server. Nick's house, Spawn, and Schuyler's setup?
Add systems that can be turned on when certain item counts get too low. They could either subscribe to sorting updates and monitor a certain item then when it gets too low update or simply request the item list every once in a while.
		that would be handy for glass and cobblestone and wood!
Add systems that will automatically request an item gets crafted when the count of an item gets too low i.e. torches or itemducts or food items.

]]--


local cache_sizes = {20000, 80000, 180000, 320000, 500000} -- basic, hardened, reinforced, signalium, resonant
local noncaches = {1, 128} -- where we have holes in the cache levels and no caches, so these indices can't be used

local width = 8
local depth = 16
local height = 1

local item_speed_per_pipe_block = 1 -- for the advanced servos I have it's 1, for simpler servos it's .5 (in regular itemducts)
local extra_pipes_into_the_system = 5 -- how many pipes an item will encounter from the turtle before reaching 1,1,1
local pipes_per_layer_change = 5 -- the number of extra pipes an item will encounter when going up a layer to get to 1,1 of its layer. This is a guess since I haven't built it yet...

local settingsSaveFile = "storagesettings.txt"
local currentActivitySaveFile = "currentActivity.txt"
local itemStorageDataSaveFile = "itemsStored.txt"
local fetchRequestsFilename = "fetchRequests.txt"
local fetchBotStatusFilename = "fetchBotsStatus.txt"
local clearing_cache_filename = "clearingCacheStatus.txt"

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

local item_data = {} -- item_key = {max_stack_size = 64, damageable = true}. You need to fetch this one from the sorting system master!

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

-- rednet non-repeat stuff
local rednet_message_id = 0
local received_rednet_messages = {}

-- this is used when emptying caches!
-- used to pause inputing chests while emptying a cache so that we don't have race conditions!
-- we're going to need to calculate the amount of time to let the pipes clear then also how much time for a fetchbot to get there
local original_clearing_cache_settings = {input_items = true, pause_input_until_time = 0, pause_input_from_time = 0, caches_to_clear = {}}
local clearing_cache_settings = original_clearing_cache_settings

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
	SaveTableToFile(clearing_cache_settings, clearing_cache_filename)
end

function load_fetch_status()
	-- load fetch_requests and fetch_bot_status
	fetch_requests = LoadTableFromFile(fetchRequestsFilename)
	fetch_bot_status = LoadTableFromFile(fetchBotStatusFilename)
	clearing_cache_settings = LoadTableFromFile(clearing_cache_filename)
	if clearing_cache_settings.input_items == nil then
		-- we weren't able to load it so replace it with the defaults
		clearing_cache_settings = original_clearing_cache_settings
		print("Replaced clearing cache settings with defaults")
	end
	-- check the clearing cache settings and see if we rebooted while we were waiting for something to clear!
	-- simply move the time to now!
	if clearing_cache_settings.pause_input_from_time > os.clock() then
		-- we rebooted in the middle of it! oh no!
		local wait_time = clearing_cache_settings.pause_input_until_time - clearing_cache_settings.pause_input_from_time
		clearing_cache_settings.pause_input_until_time = os.clock() + wait_time
		clearing_cache_settings.pause_input_from_time = os.clock()
		print("Fixed clearing cache timers after reboot!")
		save_fetch_status() -- save these changes!
	end
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

function calculate_time_to_cache_index(cache_index)
	-- calculate the time in seconds it will take for an item to get to the cache
	-- at its simplest this will be used to pause inputting items until we can clear a cache, then continue afterwards!
	local t = extra_pipes_into_the_system + pipes_per_layer_change + convert_index_to_pipe_on_layer(cache_index) -- the number of pipes it has to go through
	return t * item_speed_per_pipe_block
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

function convert_index_to_pipe_on_layer(cache_index)
	-- cache index is the nicely ordered, left to right, front to back, bottom to top
	-- pipe_order is the snakey method that zigzags all over the place
	-- this is the pipe order on its particular layer, used for calculating time for items to travel
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
	return (cache_depth-1) * width    +    cache_width
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

function ShouldSendToCrypt(item)
	-- are we trying to store this item? If not, SEND IT TO THE CRYPPTTTTT
	-- for now don't store any items that are damageable or have a max stack size of 1 since we're assuming those are the tools
	-- theoretically they could stack, but we don't want to fill our storage too too quickly especially since we're gonna have trouble
	-- getting rid of them. Err on the side of caution and don't store things that we don't know about. We should send an update to a display
	-- turtle somewhere saying that we're storing things in the crypt so that we know, as it is we don't really have any way of knowing
	if master_id == -1 then
		while master_id == -1 do
			-- wait because you have no clue what to do
			get_master_id_function()
			print("ERROR! UNABLE TO CONNECT TO MASTER SORTER")
			sleep(5)
		end
		print("Found sorting leader. Sleeping an extra second for the item data")
		sleep(1)
	end
	-- now we arguably have a item list so we should go for it!
	local i_dat = item_data[item]
	if i_dat == nil then
		-- send it to the CRYYYPT
		-- we don't know what it is but no-one does so play it safe.
		return true
	else
		-- maybe send it to the CRYYSDPPPT
		-- for now check if it's stackable or takes damage then SEND IT TO THE CRRRRYYYYYYPPPPPPPPPPPTTTT
		return i_dat.max_stack_size == 1 or i_dat.damageable
	end
end

function WhereWillItemsEndUp(item, count)
	-- figure out where this item will end up
	local amount_left = count
	local stored_locations = {}
	
	if ShouldSendToCrypt(item) then
		stored_locations[#stored_locations + 1] = {cache_index = -1, count = count}
		amount_left = 0
	end

	if amount_left > 0 then
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
	end
	if amount_left > 0 then
		print("RAN OUT OF CACHE SPACE! STORING "..tostring(amount_left).." ITEMS IN THE CRYPT")
		stored_locations[#stored_locations + 1] = {cache_index = -1, count = amount_left}
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

function broadcast_including_self(packet)
	broadcast_correct(packet)
	send_correct(os.getComputerID(), packet)
end

function broadcast_correct(packet)
	packet.from = os.getComputerID()
	packet.to = -1 -- to everyone!
	packet.id = rednet_message_id
	rednet_message_id = rednet_message_id + 1
	rednet.broadcast(packet, network_prefix)
end

function send_correct(to, packet)
	packet.from = os.getComputerID()
	packet.to = to -- to everyone!
	packet.id = rednet_message_id
	rednet_message_id = rednet_message_id + 1
	rednet.send(to, packet, network_prefix)
end

function broadcast_reset_message_id()
	local packet = {packet = "reset_message_id"}
	broadcast_including_self(packet)
end

function receive_rednet_input()
	-- this function is used by the parallel api to manage the rednet side of things
	while running do
		local sender_computer_id, message, received_protocol = rednet.receive(network_prefix)
		-- first check if we've already received the message. If so, ignore it!
		local sender_id = message.from
		local destination_id = message.to
		local message_id = message.id

		if ((received_rednet_messages[sender_id] == nil or received_rednet_messages[sender_id][message_id] == nil) and (destination_id == -1 or destination_id == os.getComputerID())) or message.packet == "reset_message_id" then
			if received_rednet_messages[sender_id] == nil then
				received_rednet_messages[sender_id] = {}
			end
			-- then it's a new message and we should pay attention to it!
			-- figure out what to do with that message
			received_rednet_messages[sender_id][message_id] = true -- we've gotten the message so ignore future versions!

			-- figure out what to do with that message
			if message.packet == "reboot_network" then
				-- quit this loop
				running = false
				reboot = true
				break
			elseif message.packet == "reset_message_id" then
				-- reset the message ids for that computer
				received_rednet_messages[sender_id] = {}
				if verbose then
					print("Reset rednet messages for "..tostring(sender_id))
				end
			elseif message.packet == "request_permission_empty_cache" then
				-- a fetch turtle is requesting permission to empty a cache. Do we give it to them?
				-- this whole thing could be made more efficient. FIX THIS
				print("Recieved request for permission to empty cache")
				-- should probably double check that we're actually pausing input... shhhh FIX THIS
				if os.clock() > clearing_cache_settings.pause_input_until_time then
					-- say yes!
					local data = {has_permission = true, extra_time = 0}
					local packet = {packet = "send_permission_empty_cache", data = data}
					send_correct(sender_id, packet)
				else
					-- say no! not enough time has passed
					local extra = clearing_cache_settings.pause_input_until_time - os.clock() + 1 -- extra time
					local data = {extra_time = extra, has_permission = false}
					local packet = {packet = "send_permission_empty_cache", data = data}
					send_correct(sender_id, packet)
				end
			elseif message.packet == "finished_emptying_cache" then
				-- a fetch turtle emptied their cache, so we can let the pipes run again if that's the only turtle that's waiting for it
				-- this could be made more efficient FIX THIS
				print("Recieved confirmation fetch turtle emptied cache")
				local index = message.data.index
				local found = false
				for i, v in ipairs(clearing_cache_settings.caches_to_clear) do
					if v == index then
						table.remove(clearing_cache_settings.caches_to_clear, i)
						found = true
						break
					end
				end
				if not found then
					print("ERROR! Emptied cache request not found!") -- oh dear this would be bad...
				end
				if #clearing_cache_settings.caches_to_clear == 0 then
					-- we're ready to resume normal operations
					print("Resumed inputting items")
					clearing_cache_settings.input_items = true
				end
				save_fetch_status()
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
			elseif message.packet == "set_item_display_names" then
				-- then the master is telling us what's up with the display names and item_data!
				print("Received item data")
				item_data = message.data.item_data
			elseif message.packet == "get_stored_items" then
				-- tell that sender what items we have stored and what quantities but strip out the boring stuff.
				local data = {items = get_items_count_table(), id = ""..os.getComputerID(), label = os.getComputerLabel(), rednet_id = os.getComputerID()}
				local packet = {packet = "send_stored_items", data = data}
				send_correct(sender_id, packet)
			elseif message.packet == "get_storage_nodes" then
				-- a new computer has joined the network, tell it what we are connected to!
				-- tell them who we are!
				-- tell them that you're a storage master machine!
				local data = {id = ""..os.getComputerID(), label = os.getComputerLabel(), rednet_id = os.getComputerID()}
				local packet = {packet = "add_storage_node", data = data}
				send_correct(sender_id, packet)  -- tell them who I am
			elseif message.packet == "set_master_id" then
				master_id = message.data
				-- also request the item display names and item data!
				broadcast_including_self({packet = "get_item_display_names"})
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
				print("Updating fetch bots")
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
end

function send_item_storage_updates(item_key, change, total_count)
	-- tell them that things changed!
	-- also tell them who we are
	local data = {key = item_key, change = change, count = total_count, storage_master_id = os.getComputerID()}
	local packet = {packet = "storage_change_update", data = data}
	for i, id in ipairs(subscribed_to_storage_changes) do
		-- send it to them
		send_correct(id, packet)
	end
end

function get_cache_coords(item_key, amount_requested)
	-- return nil if it's not valid
	-- {x = 0, y = 1, z = 1, f = fasljkd, count = amount_in_this_cache}
	-- prioritize the farthest away cache that has enough items to fufil the request? That way when we eventually empty caches we'll move things towards
	-- if none of them can handle it then it should take the farthest one that's larger than 1? I guess?
	-- the front of the sorting machine which makes sense to me.
	amount_requested = amount_requested
	local items = itemsStored[item_key]
	if items == nil then
		-- we don't have any stored, return nil
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

	if bestLocation.count <= 0 then
		-- we don't have enough of the item
		return nil
	end

	-- otherwise we have our location! now figure out the coordinates!
	local location = convert_index_to_physical_coordinates(bestLocation.index)
	location.index = bestLocation.index
	return location
end

function assign_fetch_turtle(rednet_id)
	-- assign the turtle to a mission or tell it to return to base
	-- if we aren't tracking that bot already then add it to our list of bots to track
	-- local fetch_bot_status = {} -- rednet_id = {updated = true, current_mission=fetch_request[whatevermission]}
	if fetch_bot_status[rednet_id] == nil then
		-- add it to the list!
		fetch_bot_status[rednet_id] = {updated = false, mission = nil, rednet_id = rednet_id}
		print("Got here 1")
		save_fetch_status()
	end

	-- now that we've added it to the list, give it a mission if we have any missions
	for i, v in ipairs(fetch_requests) do
		-- check if they're unresolved and can be fetched
-- fetch requests numeric_key = {item = {key=item_key, count = 10000, exact_number=true}, requesting_computer = rednet_id, status= "waiting","assigned","done"}
		if v.status == "waiting" then
			-- check if we have the items to return!
			-- if we have the items then spawn a turtle. If we don't have the items and exact_number = false then we delete this request.
			if v.item == nil or v.item.count == nil or v.item.count <= 0 then
				-- skip it! it's a done or a bad thing!
				-- fetching_requests_to_remove[#fetching_requests_to_remove + 1] = i
			else
				-- if there are positive items requested and we have some of its type in the storage system then spawn turtles!
				local amount_stored = safe_get_item_count(v.item.key)
				if amount_stored > 0 then
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
						data.item.count = math.min(math.min(v.item.count, cache_coords.count), max_items_stored_in_turtle)
						-- for now just don't allow removing items entirely so we don't
						-- run into the problem of race conditions. I'll have to FIX it later
						local amount_left_to_fetch = v.item.count - data.item.count -- that's how many left to fetch

						local empties_cache = data.item.count == cache_coords.count
						-- if it empties the cache then the turtle needs to ask the master for confirmation that the pipes are empty before gathering the item
						data.item.wait_for_confirmation = empties_cache
						if empties_cache then
							print("Recieved a request that will empty the cache!")
							-- we need to stop inputting items!!!
							-- calculate the amount of time it'll take for the last possible item to reach its destination then reset
							-- FIX THIS
							local time_to_clear = calculate_time_to_cache_index(cache_coords.index) + 1
							if clearing_cache_settings.input_items then
								-- give it the full amount of time to clear items!
								clearing_cache_settings.pause_input_from_time = os.clock()
								clearing_cache_settings.pause_input_until_time = os.clock() + time_to_clear
								clearing_cache_settings.input_items = false
								print("Stopping items")
							else
								-- we're already pausing for someone else so figure out how much more time we need to pause than this then add it on
								local paused_amount = os.clock() - clearing_cache_settings.pause_input_from_time
								if paused_amount >= time_to_clear then
									-- we're set and we can just add the item on as valid to clear!
								else
									-- add on extra time probably?
									-- this means that it'll delay the other items too, which I don't want :( I guess that means that I should FIX THIS
									-- but for now I don't care enough :/
									clearing_cache_settings.pause_input_until_time = clearing_cache_settings.pause_input_from_time + time_to_clear
									-- wait longer!
								end
								print("We've already stopped items so now we're just waiting a bit longer")
							end
							clearing_cache_settings.caches_to_clear[#clearing_cache_settings.caches_to_clear+1] = cache_coords.index
							-- add the location to the list of caches that we're emptying so we know not to allow items until it's time
							print("Got here 2")
							save_fetch_status()
						end

						-- v.status = "assigned"
						v.status = "done" -- it'll just delete it now which is fine I think. later I want status though FIX THIS

						-- now tell the turtle to do this! and create another fetch item to deal with the remnants that we weren't able to fetch this time
						local packet = {packet = "fetch_turtle_assign_mission", data = data}
						send_correct(rednet_id, packet)
						-- print("Sent to " .. tostring(rednet_id))
						fetch_bot_status[rednet_id].updated = true -- you told them to update!
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
						print("Got here 3")
						save_fetch_status()
						return true -- we've found what it should do so we've told it what to do!
					end
				elseif amount_stored == 0 and v.item.exact_number == false then
					-- skip it because we don't have it so it's accounted for!
					-- add it to the list of things to remove
					-- fetching_requests_to_remove[#fetching_requests_to_remove + 1] = i
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
	send_correct(rednet_id, packet)
	fetch_bot_status[rednet_id].updated = true -- you told them to update!
	fetch_bot_status[rednet_id].mission = data -- assign the current mission
	print("Got here 4")
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
		print("Got here 5")
		save_fetch_status() -- save it after removing fetched items
	end
end

function connect_to_sorting_network()
	-- tell everyone you're a sorting robot
	local data = {id = ""..os.getComputerID(), label = os.getComputerLabel()}
	-- send it out to the sorting network!
	local packet = {packet = "add_storage_node", data = data}
	broadcast_correct(packet)  -- tell them who I am
end

function add_item_to_storage(item_key, item_count)
	local cache_ids = WhereWillItemsEndUp(item_key, item_count)
	local amount_not_stored = 0
	-- now add it to those caches
	for k, v in ipairs(cache_ids) do
		if v.cache_index == -1 then
			-- it's not able to store this one! send it to the crypt!
			amount_not_stored = amount_not_stored + v.count
			turtle.dropDown(v.count)
			print("Sent items to THE CRYPT")
		else
			-- apply those changes to the stored items!
			if itemsStoredBySlot[v.cache_index] == nil then
				itemsStoredBySlot[v.cache_index] = {count = 0, max = cache_sizes[1], item=""} -- made it a default cache FIX
			end
			itemsStoredBySlot[v.cache_index].item = item_key
			itemsStoredBySlot[v.cache_index].count = itemsStoredBySlot[v.cache_index].count + v.count
			print("item: " ..item_key .. " added to cache " .. v.cache_index .. " with count " .. itemsStoredBySlot[v.cache_index].count)
			-- temporary print how long it'll take to get there!
			print("Storing " .. item_key .. " will take " .. tostring(calculate_time_to_cache_index(v.cache_index)) .. " seconds")
		end
	end
	BuildItemsStoredToSlotTable()
	if itemsStored[item_key] ~= nil then
		-- if we're actually storing it and not just sending it to the crypt
		send_item_storage_updates(item_key, item_count, itemsStored[item_key].count) -- send an update to computers that are subscribed!
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
	turtle.dropUp() -- send whatever's not been sent to the crypt to storage!
	return true
end

function sort_input()
	while running do
		-- input items from the chest in front of it, then if they deserve to go into storage store them. If they don't then don't
		-- turtle.select(1)
		while clearing_cache_settings.input_items and turtle.suck() do
			-- it's sorting time!
			if (sort_current()) then
				saveItemsStored() -- save the changes you've made!
			end
			-- turtle.select(1)
			sleep(0) -- just make sure it pauses in here
		end
		if not clearing_cache_settings.input_items then
			-- time yourself until you're ready to empty the cache!
			while os.clock() < clearing_cache_settings.pause_input_until_time do
				local length = clearing_cache_settings.pause_input_from_time - clearing_cache_settings.pause_input_until_time
				sleep(math.max(5, length/2))
			end
			-- if os.clock() > clearing_cache_settings.pause_input_until_time then
			-- 	-- set the allowed to clear cache flag to true!
			-- end
			while not clearing_cache_settings.input_items do
				sleep(5) -- sleep 5 seconds while waiting to empty the cache I guess?
			end
			sleep(0)
		else
			sleep(2) -- wait some time for more items to come in
		end
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

function get_master_id_function()
	broadcast_including_self({packet = "get_master_id"})
end

function broadcast_existence()
	local data = {id = ""..os.getComputerID(), label = os.getComputerLabel(), rednet_id = os.getComputerID()}
	local packet = {packet = "add_storage_node", data = data}
	broadcast_correct(packet)  -- tell everyone who I am
	print("Requesting Master ID")
	get_master_id_function()
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