local tArgs = {...}

settings_path = "sorting_network_settings.txt"
settings_prefix = "sorting."
item_names_path = "item_names.txt" -- a csv of minecraft:dirt,0,Dirt
default_destinations_path = "default_destinations.txt"



-- don't touch these they won't change anything
network_prefix = "REPLACE_THIS"
sorting_destination_settings = {destinations = {}} -- is a map from destination=direction
known_destinations = {Player=true, Unknown=true, Storage=true} -- the default locations

connections = {} -- this is the graph of the network I guess?
local_connections = {}
local_directions = {} -- the inverse of local_connections, it's destination="up", destination="forwards", etc.

default_destinations = {} -- this is stored in a file and is used for regular operations
custom_destinations = {} -- this is used for crafting items!

item_display_names = {}

master_id = -1
modem_side = ""
reboot = false -- this is used to reboot everything after recieving this from the network
running = true
first_initialization = false -- this is true when the human should initialize things
edit_destinations = false

player_review_items = false -- this is true when it's time for the player to review items

function check_if_replace_prefix()
	-- if the prefix needs to be replaced this function will do it. This function is called as part of initialization each time
	network_prefix = settings.get(settings_prefix .. "network_prefix", "REPLACE_THIS")
	if network_prefix == "REPLACE_THIS" then
		-- replace it
		local tempPrefix = ""
		while #tempPrefix == 0 do
			print("Enter your sorting rednet network prefix:")
			tempPrefix = read()
		end
		network_prefix = tempPrefix
		settings.set(settings_prefix .. "network_prefix", network_prefix)
		print("Network prefix: " ..network_prefix)
		save_settings()
	end
end

function steralize_item_table(item_table)
	-- if item_table == nil then -- I'd kinda prefer it to error out which is why I'm commenting this out
	-- 	return {}
	-- end
	local t = {name=item_table.name, damage=item_table.damage}
	return t
end

function add_item_name(item_table, name)
	-- item_table = {count = number, name = "minecraft:cobblestone", damage = 0}
	-- from turtle.getItemDetail()
	-- check if it already exists
	local t = get_item_key(item_table)
	if item_display_names[t] == name then
		return false -- this will have duplicates when we rename things but we can deal with that fine
	end
	item_display_names[t] = name -- add it to the table, then to the file
	local f = fs.open(item_names_path, "a")
	f.write(item_table.name..","..item_table.damage..","..name.."\n")
	f.close()
	return true -- it's a new name!
end

function add_item_default_destination(item_table, destination)
	-- item_table = {count = number, name = "minecraft:cobblestone", damage = 0}
	-- from turtle.getItemDetail()
	-- check if it already exists
	local t = get_item_key(item_table)
	if default_destinations[t] == destination then
		return false -- this will have duplicates when we rename things but we can deal with that fine
	end
	default_destinations[t] = destination -- add it to the table, then to the file
	local f = fs.open(default_destinations_path, "a")
	f.write(item_table.name..","..item_table.damage..","..destination.."\n")
	f.close()
	return true -- it's a new name!
end

function load_display_names()
	-- loads the item display names from the file if it exists
	item_display_names = {}
	if fs.exists(item_names_path) then
		local f = fs.open(item_names_path, "r")
		-- read the lines! They're tab separated
		local line = f.readLine()
		while line ~= nil do
			-- add it to the list!
			if #line > 1 then
				-- it's not a blank line I guess
				local t = {}
				for word in string.gmatch(line, '([^,]+)') do
				    t[#t+1] = word
				end
				if #t ~= 3 then
					print("Error parsing line: '"..line.."' got "..#t.." values")
				else
					local dmg = tonumber(t[2]) or t[2] -- if it's not a number I guess we'll just deal???
					local item = {name = t[1], damage = dmg}
					item_display_names[get_item_key(item)] = t[3]
				end
			end
			line = f.readLine()
		end
		f.close()
		-- print("Item names:")
		-- textutils.pagedPrint(textutils.serialise(item_display_names))
	end
end

function load_default_destinations()
	-- loads the item display names from the file if it exists
	default_destinations = {}
	if fs.exists(default_destinations_path) then
		local f = fs.open(default_destinations_path, "r")
		-- read the lines! They're tab separated
		local line = f.readLine()
		while line ~= nil do
			-- add it to the list!
			if #line > 1 then
				-- it's not a blank line I guess
				local t = {}
				for word in string.gmatch(line, '([^,]+)') do
				    t[#t+1] = word
				end
				if #t ~= 3 then
					print("Error parsing destination line: '"..line.."' got "..#t.." values")
				else
					local dmg = tonumber(t[2]) or t[2] -- if it's not a number I guess we'll just deal???
					local item = {name = t[1], damage = dmg}
					default_destinations[get_item_key(item)] = t[3]
				end
			end
			line = f.readLine()
		end
		f.close()
		-- print("default directions:")
		-- textutils.pagedPrint(textutils.serialise(default_destinations))
	end
end

function find_local_connections()
	-- print("COnnections")
	-- textutils.pagedPrint(textutils.serialise(connections))
	-- print("Local connections")
	local frontier = {}
	for og_direction, og_direction_connection in pairs(sorting_destination_settings.destinations) do
		frontier = {}
		frontier[1] = og_direction_connection
		local_connections[og_direction] = {}
		local i = 1
		while i <= #frontier do
			-- add more!
			-- search for connections with the current
			local currloc = frontier[i]
			local_connections[og_direction][#local_connections[og_direction]+1] = currloc
			local_directions[currloc] = og_direction

			if connections[currloc] ~= nil then
				-- add the new connected things to the frontier
				for currlocDirection, newLoc in pairs(connections[currloc]) do
					-- add the new locations if they aren't already in the list
					local found = false
					for j = 1, #frontier do
						if frontier[j] == newLoc then
							found = true
							break
						end
					end
					if not found then
						-- add it to the list
						frontier[#frontier + 1] = newLoc
					end
				end
			end
			i = i + 1
		end
	end
	-- textutils.pagedPrint(textutils.serialise(local_connections))
	-- print("Local connections")
	-- print(textutils.serialise(local_connections))
end

function load_sorting_destinations(edit)
	-- loads the sorting settings from settings or initialies it with questions from the user
	sorting_destination_settings = settings.get(settings_prefix .. "sorting_settings", sorting_destination_settings)
	-- {"up"=nil, "down"=nil, "left"=nil, "right"=nil, "forwards"=nil}
	-- sorting_destination_settings.id
	if edit then
		-- edit them!
		local master = read_non_empty_string("Enter 'y' if this is the top of the sorting tree:") == "y"
		print("Enter the destinations for the following directions, at least one of which should be 'origin' which means it's the origin of items to this sorter")
		print("-1 for no connection")
		local up = read_non_empty_string("Enter Up destination:")
		local down = read_non_empty_string("Enter Down destination:")
		local forwards = read_non_empty_string("Enter Forwards destination:")
		if up == "-1" then
			up = nil
		end
		if down == "-1" then
			down = nil
		end
		if forwards == "-1" then
			forwards = nil
		end
		-- local left = read_non_empty_string("Enter origin sorting ID:")
		-- local right = read_non_empty_string("Enter origin sorting ID:")
		sorting_destination_settings.destinations.up = up
		sorting_destination_settings.destinations.down = down
		sorting_destination_settings.destinations.forwards = forwards

		sorting_destination_settings.isMaster = master

		settings.set(settings_prefix .. "sorting_settings", sorting_destination_settings)
		save_settings()
	end
end

function read_non_empty_string(prompt)
	-- this is a helper function that will repeat the prompt until the user enters a non-empty string
	local temp = ""
	while #temp == 0 do
		print(prompt)
		temp = read()
	end
	return temp
end

function load_settings()
	if fs.exists(settings_path) then
		settings.load(settings_path)
		print("Found settings")
	else
		first_initialization = true
		print("Entering Initial Configuration")
	end
end

function save_settings()
	settings.save(settings_path)
end

function initialize_known_destinations()
	-- get them from settings if they exist
	known_destinations = settings.get(settings_prefix .. "known_destinations", known_destinations)
	known_destinations[""..os.getComputerID()] = true -- it knows that it exists!
end

function add_destination(destination, direction)
	-- add a known destination, if direction is not nil then it knows it can send things to that destination that direction
	if is_known_destination(destination) then
		return -- already known so exit early
	end
	known_destinations[destination] = true
	if direction ~= nil then
		-- it can be reached by this sorter!
		sorting_destination_settings[destination] = direction
	end
end

function is_known_destination(destination)
	return known_destinations[destination] ~= nil
end

function add_sorting_direction(destination, direction)
	-- this is just a helper function to add a sorting direction
	if sorting_destination_settings[direction] == nil then
		sorting_destination_settings[direction] = {}
	end
	sorting_destination_settings[direction][#sorting_destination_settings[direction] + 1] = destination
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
	if not rednet.open(modem_side) then
		print("Error opening rednet, this will likely cause errors")
	end
end

function shut_down_network()
	rednet.close(modem_side)
	print("Shut down Rednet network")
end

-- function fetch_networking_destinations()
-- 	-- tries to fetch destinations, is also useful when you add new destinations to the network and then reboot
-- 	rednet.broadcast("request_destinations", network_prefix)
-- 	print("Fetching known network destinations")

-- 	local network_destinations = {}
-- 	while true do
-- 		local sender_id, message, received_protocol = rednet.receive(network_prefix, 3) -- three second timeout I guess? The issue is others may be waiting as well...
-- 		if sender_id ~= nil then
-- 			-- received something
-- 			print("received destinations from network")
-- 		else
-- 			break
-- 		end
-- 	end
-- end

function determine_forwards()
	return -- for now we aren't going to turn since this is complicated and can be dealt with later

	-- -- figure out which way is forwards since the turtle may have turned. Forwards is the center-most chest, or the right one,
	-- local facing_blocks = {}
	-- local last_empty = 1
	-- local wired_modem_side = -1
	-- for i = 1, 4 do
	-- 	facing_blocks[i] = turtle.inspect()
	-- 	if facing_blocks[i] == nil then
	-- 		last_empty = i -- the last empty space
	-- 	end
	-- 	turtle.turnRight()
	-- end
	-- -- back is either the last empty slot or the wired modem block, whichever exists
	-- for i = 1, 4 do
	-- 	--
	-- end
end

function get_default_destinations()
	-- this just asks the master to send us the default destinations
	local packet = {packet = "get_item_default_destinations"}
	rednet.broadcast(packet, network_prefix)
end

function initialization()
	-- just holds all the functions that should be called before it initializes
	load_settings()
	load_display_names()
	load_default_destinations()
	check_if_replace_prefix()

	print("ID: " ..os.getComputerID() .. " - Label: " .. os.getComputerLabel())
	print()
	-- now what we need to do is figure out destinations.
	-- either they have final destinations which have string names, or they have computer ids
	-- find all the known destinations that exist in the network by sending out a network request,
	-- that returns a dictionary with {id, {destinations...}}, which we can use to path our way to the goal I guess.
	initialize_known_destinations()
	initialize_network()
	-- fetch_networking_destinations() -- see if new destinations have been added to the network. I can't do that nicely here so we're not going to. The issue is everything is running this at the same time so nothing is responding
	load_sorting_destinations(first_initialization or edit_destinations)
	find_local_connections()
	-- now it knows where it sorts to.
	-- now it should tell everyone where it goes and also find out from everyone else where they go from. It now has to initialize everything.
	get_default_destinations()
end

function get_display_name(item_table)
	local k = get_item_key(item_table)
	return item_display_names[k] or k -- if it doesn't know the name then return the default item name
end

function get_item_key(item_table)
	return item_table.name .. "-"..item_table.damage
end

function has_display_name(item_table)
	local k = get_item_key(item_table)
	return item_display_names[k] ~= nil
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
		elseif message.packet == "quit_network" then
			-- quit this loop
			running = false
			reboot = false
			break
		elseif message.packet == "get_sorting_network_connections" then
			-- a new computer has joined the network, tell it what we are connected to!
			-- tell them who we are!
			local data = {id = ""..os.getComputerID(), label = os.getComputerLabel(), destinations = sorting_destination_settings.destinations}
			local packet = {packet = "update_network_connection", data = data}
			rednet.send(sender_id, packet, network_prefix)
		elseif message.packet == "update_network_connection" then
			connections[message.data.id] = message.data.destinations
			print("Finding local connections")
			find_local_connections()
		elseif message.packet == "get_master_id" then
			-- if this is the master then it returns this ID
			if sorting_destination_settings.isMaster then
				-- tell them you're the master!
				local packet = {packet = "set_master_id", data = os.getComputerID()}
				rednet.send(sender_id, packet, network_prefix)
			end
		elseif message.packet == "set_master_id" then
			master_id = message.data
		-- elseif message.packet == "" then
		-- 	-- 
		elseif message.packet == "get_item_display_names" then
			if sorting_destination_settings.isMaster then
				-- give them your list of display names
				local packet = {packet = "set_item_display_names", data = item_display_names}
				rednet.send(sender_id, packet, network_prefix)
			end
		elseif message.packet == "set_item_display_names" then
			item_display_names = message.data
		elseif message.packet == "set_new_item_display_name" then
			-- set an individual display name in the master, probably from a pocket computer or a special outside computer monitor idk...
			if sorting_destination_settings.isMaster then
				-- this was sent a packet {packet = "set_new_item_display_name", data = {item = {ITEMTABLE}, name=NEWNAME}}
				-- textutils.pagedPrint(textutils.serialise(message))
				if add_item_name(message.data.item, message.data.name) then
					-- tell everyone the new names
					local packet = {packet = "set_item_display_names", data = item_display_names}
					rednet.broadcast(packet, network_prefix)
				end
			end
		elseif message.packet == "set_new_item_default_destination" then
			-- set an individual display name in the master, probably from a pocket computer or a special outside computer monitor idk...
			if sorting_destination_settings.isMaster then
				-- this was sent a packet {packet = "set_new_item_default_destination", data = {item = {ITEMTABLE}, destination=NEWNAME}}
				if add_item_default_destination(message.data.item, message.data.destination) then 
					-- tell everyone the new names
					local packet = {packet = "set_item_default_destinations", data = default_destinations}
					rednet.broadcast(packet, network_prefix)
				end
			end
		elseif message.packet == "set_item_default_destinations" then
			default_destinations = message.data
		elseif message.packet == "get_item_default_destinations" then
			if sorting_destination_settings.isMaster then
				-- give them your list of destinations
				local packet = {packet = "set_item_default_destinations", data = default_destinations}
				rednet.send(sender_id, packet, network_prefix)
			end
		end
	end
end

function connect_to_sorting_network()
	-- this brodcasts to the network what this node has and then also asks what they have, which it builds into a map in the receive_rednet_input function
	local data = {id = ""..os.getComputerID(), label = os.getComputerLabel(), destinations = sorting_destination_settings.destinations}
	-- send it out to the sorting network!
	local packet = {packet = "update_network_connection", data = data}
	rednet.broadcast(packet, network_prefix)  -- tell them who I am

	packet = {packet = "get_sorting_network_connections"}
	rednet.broadcast(packet, network_prefix) -- request other connections in the network

	if sorting_destination_settings.isMaster then
		-- tell them you're the master!
		local packet = {packet = "set_master_id", data = os.getComputerID()}
		rednet.broadcast(packet, network_prefix)
	end
end

function find_direction(destination)
	-- returns the direction to go to to get to the destination in question,
	-- includes the option of "unknown" which means it should store it and ask for help
	local direction = local_directions[destination]
	-- unknown means it should store it and ask a human about it
	return direction or "unknown" -- if it knows the direction then send it to the direction
end

function store_unknown_item()
	-- this stores the item in the turtle since it's lost and needs help from a human
	-- for now just transfer it to the last open space. Perhaps light up redstone too? If there are no open spaces then god help us...
	for i = 16, 2, -1 do
		if turtle.getItemCount(i) == 0 then
			turtle.transferTo(i)
			print("STORED UNKNOWN ITEM")
			-- should probable broadcast the error too, just so a human can see it...
			turtle.select(1)
			return true
		end
	end
	print("ERROR: NO MORE EMPTY SLOTS FOR UNKNOWN ITEM")
	turtle.select(1)
	return false
end

function sort_currently_selected()
	local item = turtle.getItemDetail()
	local sterile_item = steralize_item_table(item)
	local item_key = get_item_key(item)
	local destination = "Unknown"
	if custom_destinations[item] ~= nil then
		-- ~~~custom oooOOoOoO~~~
		-- this is going to be custom amounts and directions so for now lets just ignore it ehh?
		return
	elseif default_destinations[item_key] ~= nil then
		destination = default_destinations[item_key]
	end
	local direction = find_direction(destination)
	if destination == "Unknown" then
		print("Found Unknown Item: ".. get_display_name(item) .. " direction is " .. direction)
	end
	local direction_export = {up=turtle.dropUp, down=turtle.dropDown, forwards = turtle.drop, unknown=store_unknown_item}
	while not direction_export[direction]() do
		-- coroutine.yield() -- just wait while it tries to push things out of the way I guess
		sleep(1)
	end
	if turtle.getItemCount(1) > 0 then
		-- recursively call this I guess? that can't go wrong :P
		sort_currently_selected()
	end
end

function import_unknown()
	-- this is called when a human wants to sort everything
	local direction_import = {up=turtle.suckUp, down=turtle.suckDown, forwards = turtle.suck}

	-- first figure out which direction has the "Unknown" destination
	for direction, destination in pairs(sorting_destination_settings.destinations) do
		-- if that destination is "Unknown" then suck from it
		if string.lower(destination) == "unknown" then
			turtle.select(1)
			while direction_import[direction]() do
				-- ask the player what it is and where to put it!
				-- then output it to an origin chest?
				local item = steralize_item_table(turtle.getItemDetail())
				local item_key = get_item_key(item)
				local currDisplayName = get_display_name(item)
				if not has_display_name(item) then
					-- ask the human for a display name
					local new_name = read_non_empty_string("Enter the display name of " .. currDisplayName)
					currDisplayName = new_name
					-- set it!
					-- {packet = "set_new_item_display_name", data = {item = {ITEMTABLE}, name=NEWNAME}}
					local packet = {packet = "set_new_item_display_name", data={item=item, name=new_name}}
					rednet.broadcast(packet, network_prefix)
					rednet.send(os.getComputerID(), packet, network_prefix)
					-- that way whatever the master is can have it and we don't have to keep track of it.
				end
				local old_destination = default_destinations[item_key]
				if old_destination == nil then
					-- now figure out what the destination is, then put it in the origin chest!
					local new_destination = read_non_empty_string("Enter the destination of " .. currDisplayName)
					local packet = {packet = "set_new_item_default_destination", data = {item=item, destination=new_destination}}
					rednet.broadcast(packet, network_prefix)
					rednet.send(os.getComputerID(), packet, network_prefix)
				end
				-- now deal with it!
				sort_currently_selected() -- hopefully this won't go wrong... welp :P
			end
		end
	end
	-- we should also loop over all the items which are in the unknown direction i.e. the "HELP ME I'M SCARED" direction for the computer
end

function sort_input()
	-- this is the other half of the parallel function that runs the sorting side of things
	-- takes a list of custom changes from the rednet side of things and deals with them
	connect_to_sorting_network() -- one last initialization step
	local direction_import = {up=turtle.suckUp, down=turtle.suckDown, forwards = turtle.suck} -- possibly include other functions that turn for those directions
	while running do
		-- loop through all the input faces and suck from them, then deal with sorting the output!
		if player_review_items then
			import_unknown()
			player_review_items = false
		end
		local sleepNow = true
		for direction, destination in pairs(sorting_destination_settings.destinations) do
			if not running then
				break -- in case it gets changed in the middle of a cycle
			end
			-- if that destination is "origin" then suck from it
			if string.lower(destination) == "origin" then
				-- it's an origin so suck from it!
				turtle.select(1)
				if direction_import[direction]() then
					-- don't sleep just yet
					sleepNow = false
					-- sort it!
					sort_currently_selected()
				end
			end
			-- sleep(5)
			-- coroutine.yield()
			sleep(1)
		end
		if sleepNow then
			-- print("sleeping")
			sleep(5)
		end
	end
end

function deinitialization()
	shut_down_network()
end

function main()
	if tArgs[1] == "reset" then
		-- reset your settings by deleting the settings file
		fs.delete(settings_path)
	end
	if tArgs[1] == "edit" then
		edit_destinations = true
	end
	if tArgs[1] == "review" then
		player_review_items = true
	end
	initialization()

	-- run the main program!
	parallel.waitForAll(receive_rednet_input, sort_input)

	deinitialization() -- I don't know if this will get run so who knows....
	if reboot then
		-- restart the computer
		print("Restarting computer")
		computer.reboot()
	else
		print("Quitting sorting program")
	end
end


main()
