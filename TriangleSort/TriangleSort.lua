--[[
todo:
-make it review the unknown items each time it gets more connections! The reason why they're unknown is because it hasn't found the way to deliver
them, so we need to let that happen!
-refactor the code so the networking stuff that's needed for the storage side of things can be used there.
-save and load custom destinations? that's probably a good idea.
-crafting somehow
-storage clusters.
-storage warehouses
-storage master turtle that keeps track of everything
-convert all rednet into messages that include sender ids and reciever ids so it's compatible with rednet resenders. They also may need to store a table
of messages they've responded to to avoid responding multiple times.

-Processing Improvements:
	- Save recipies with the number and type of item output and allow players to chose them
		- this should be saved on the master and sent over network to everyone
	- Create a "machine monitor" which watches over a machine like the induction smelter or alloy smelter or crafting turtle to only send a single custom recipie until it gets a redstone signal after which it can send the next one
		- this also requires checking that furnaces etc. will send a redstone signal using a comparator when they have any item still being made, which I can then invert.
			- save the status of them? maybe not that's effort, but I should also just save everything so maybe at some point I can fix that
	- figure out if there's a better way to determine which computer has access to the Unknown chest not just the master. Maybe it's down the line? I'm not sure, not a priority
	- make a crafting turtle using the custom destinations! It's basically ready! If we have a monitor then we know that every item that goes into it is ready!


- Displays
	- return_custom_destinations and get_custom_destinations needs to be called by displays and actually displayed
	- storage displays when we have that working

- Faster custom recipie additions
	- include a turtle that can add an item that gets passed in? probably.
		- I could also make it add everything in the shape of a crafting turtle so it knows what has to be empty etc. that works fine for even machines with fewer ports because it only cares about leading empty spaces

]]--


local tArgs = {...}

settings_path = "sorting_network_settings.txt"
settings_prefix = "sorting."
item_names_path = "item_names.txt" -- a csv of minecraft:dirt,0,Dirt
default_destinations_path = "default_destinations.txt"



-- don't touch these they won't change anything
network_prefix = "REPLACE_THIS"
sorting_destination_settings = {destinations = {}} -- is a map from destination=direction
known_destinations = {Player=true, Unknown=true, Storage=true} -- the default locations

-- STORAGE NODES AND ITEMS STORED
storage_nodes = {} -- connected storage nodes
items_stored = {}

-- SORTING CONNECTIONS
connections = {} -- this is the graph of the network I guess?
local_connections = {}
local_directions = {} -- the inverse of local_connections, it's destination="up", destination="forwards", etc.

default_destinations = {} -- this is stored in a file and is used for regular operations
custom_destinations = {} -- this is used for crafting items!

item_display_names = {}
display_names_to_keys = {}
searchable_display_names_to_keys = {}

sorting_computer_type = "sorter" -- sorter, display, terminal
display_type = "itemscroll" -- if it's a display, what will it display?

master_id = -1
modem_side = ""
reboot = false -- this is used to reboot everything after recieving this from the network
running = true
first_initialization = false -- this is true when the human should initialize things
edit_destinations = false

player_review_items = false -- this is true when it's time for the player to review items

terminal_commands = {}

function initialize_terminal_commands()
	terminal_commands = {help=help_command,
		update_all=update_network_command,
		update=update_self_command,
		quit=quit_self_command,
		quit_all=quit_network_command,
		reboot_all=reboot_network_command,
		refresh_all_network=refresh_all_network,
		["?"]=help_command,
		display_knowledge=display_knowledge,
		print_display_names=print_all_display_names,
		search_names=search_item_names_command,
		slow_custom=set_custom_destination_command,
		sort_unknown_items=sort_unknown_items_command,
		all_items_stored=slow_print_display_name_item_count_command,
		}
end

function add_turtle_terminal_commands()
	-- add commands to add recipies/custom_destinations here probably? Or just customize other commands idk.
end

function set_custom_destination_command(lower_command, command, rest)
	-- set_new_item_custom_destination
	slow_custom_command_entry()
end

function slow_custom_command_entry()
	-- this is my first attempt, just for rough info
	packet = {packet="set_new_item_custom_destination", data={items={}, destination=""}}
	-- loop through adding new items etc, our little own set of commands here :P
	local input = ""
	local input_lower = ""
	while true do
		io.write("custom direction > ")
		input = read()
		input_lower = string.lower(input)
		if input_lower == "destination" or input_lower == "des" then
			print("Enter destination: ")
			local destination = read()
			packet.data.destination = destination
		elseif input_lower == "summary" then
			print("Here is the custom destination")
			textutils.pagedPrint(textutils.serialise(packet.data))
		elseif input_lower == "help" or input_lower == "?" then
			local commands = {help=true, summary=true, additem=true,  searchnames=true, send=true, nametoid=true, removeitem=true,
							addempty=true, destination=true, cancel=true, repeatitem=true}
			if get_computer_type() == "turtle" then
				-- add special commands
				commands.addcurritem = true
			end
			display_commands(commands)
		elseif input_lower == "additem" then
			-- get id, get number, add it to the end
			print("Enter item ID. enter nothing to cancel")
			local id = read()
			if #id > 0 then
				local item_t = item_key_to_item_table(id)
				if item_t ~= nil then
					print("Enter item count, enter nothing to cancel")
					local count = read()
					if #count > 0 then
						count = tonumber(count)
						if count ~= nil then
							-- it's a valid number. Add it.
							item_t.count = count
							table.insert(packet.data.items, item_t)
							print("Succeeded in adding item")
						else
							print("Invalid number for count")
						end
					end
				else
					print("Invalid item id")
				end
			end
		elseif input_lower == "repeatitem" then
			-- repeat the last item in the direction
			if #packet.data.items > 0 then
				local last = packet.data.items[#packet.data.items]
				local item_t = {name = last.name, count = last.count, damage = last.damage}
				table.insert(packet.data.items, item_t)
			else
				print("No item to repeat")
			end
		elseif input_lower == "addempty" then
			-- add an empty count!
			print("NOT IMPLEMENTED")
		elseif get_computer_type() == "turtle" and input_lower == "addcurritem" then
			-- add the item that's in the current slot, and ask how much of it
			if turtle.getItemCount() == 0 then
				print("No item to add")  -- it's possible you want to add an empty item but idk...
			else
				local item_t = turtle.getItemDetail()
				print("Enter item count, enter nothing to cancel")
				local count = read()
				if #count > 0 then
					count = tonumber(count)
					if count ~= nil then
						-- it's a valid number. Add it.
						item_t.count = count
						table.insert(packet.data.items, item_t)
						print("Succeeded in adding item")
					else
						print("Invalid number for count")
					end
				end
			end
		elseif input_lower == "removeitem" then
			-- remove the last item :P
			table.remove(packet.data.items)
		elseif input_lower == "nametoid" then
			io.write("Enter name to search id: ")
			local t = item_name_to_keys(read())
			if t == nil then
				print("No ids for that name")
			else
				local s = ""
				for i, v in ipairs(t) do
					s = s .. v .. "\n"
				end
				print("Result IDs:")
				textutils.pagedPrint(s)
			end
		elseif input_lower == "searchnames" then
			local t = search_item_names(read_non_empty_string("Enter partial name to search: "))
			print("Results:")
			local s = ""
			for i, v in ipairs(t) do
				s = s .. v .. "\n"
			end
			textutils.pagedPrint(s)
		elseif input_lower == "cancel" or input_lower == "quit" then
			return
		elseif input_lower == "send" then
			broadcast_including_self(packet)
			print("Sent!")
			return
		else
			print("Not a valid command. Type 'help'")
		end
	end
end

function display_commands(command_table)
	print("Here are the commands:")
	local s = ""
	for k,v in pairs(command_table) do
		s = s .. k .. "\n"
	end
	textutils.pagedPrint(s)
end

function help_command(lower_command, command, rest)
	display_commands(terminal_commands)
end

function quit_self_command(lower_command, command, rest)
	running = false
	rednet.send(os.getComputerID(), {packet = "quit_network"}, network_prefix)
end

function quit_network_command(lower_command, command, rest)
	running = false
	local packet = {packet = "quit_network"}
	broadcast_including_self(packet)
end

function reboot_network_command(lower_command, command, rest)
	running = false
	reboot = true
	local packet = {packet = "reboot_network"}
	broadcast_including_self(packet)
end

function update_self_command(lower_command, command, rest)
	rednet.send(os.getComputerID(), {packet = "update_network"}, network_prefix)
end

function update_network_command(lower_command, command, rest)
	local packet = {packet = "update_network"}
	broadcast_including_self(packet)
end

function sort_unknown_items_command(lower_command, command, rest)
	local packet = {packet = "sort_unknown_items"}
	broadcast_including_self(packet)
end

function search_item_names_command(lower_command, command, rest)
	local t = search_item_names(rest)
	local s = ""
	for i, v in ipairs(t) do
		s = s .. v .. "\n"
	end
	print("Results:")
	textutils.pagedPrint(s)
end

function refresh_all_network(lower_command, command, rest)
	get_master_id_function()
	broadcast_including_self({packet = "get_default_destinations"})
	broadcast_including_self({packet = "get_item_display_names"})

	-- refresh storage things
	request_storage_masters()
	request_stored_items()
end

function slow_print_display_name_item_count_command(lower_command, command, rest)
	-- loop through the item list printing out how many of each item we have in each storage system.
	-- I should also support multiple storage systems and collect all the items but for now... no. I refuse to fall prey to that :P
	paged_print_all_stored_items()
end

function paged_print_all_stored_items()
	local output = ""
	for k, v in pairs(items_stored) do
		output = output .. get_display_from_key(k) .. ": " .. v.count .. "\n"
	end
	textutils.pagedPrint(output)
end

function print_all_display_names(lower_command, command, rest)
	textutils.pagedPrint(textutils.serialise(item_display_names))
end

function get_master_id_function()
	broadcast_including_self({packet = "get_master_id"})
end

function display_knowledge(lower_command, command, rest)
	print("Master id: " .. master_id)
	print("Number of display names: " .. count_display_names())
end

function count_display_names()
	-- simply counts and returns the number of display names to get an idea the size of the info tables
	local size = 0
	for k, v in pairs(item_display_names) do
		size = size + 1
	end
	return size
end

function broadcast_including_self(packet)
	rednet.broadcast(packet, network_prefix)
	rednet.send(os.getComputerID(), packet, network_prefix)
end

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

function item_key_to_item_table(item_key)
	local a, b, name, damage = string.find(item_key, "(.+)-(.+)")
	damage = tonumber(damage)
	if damage == nil or name == nil then
		return nil
	end
	return {name = name, damage = damage}
end

function item_name_to_keys(item_name)
	-- search through all the items with that name and return all the keys I guess?
	return display_names_to_keys[item_name]
end

function search_item_names(partial_name)
	local t = textutils.complete(partial_name, searchable_display_names_to_keys)
	for i, v in ipairs(t) do
		t[i] = partial_name .. v
		t[i] = string.gsub(t[i], "_", " ") -- replace the underscore back out!
	end
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
	if display_names_to_keys[name] == nil then
		display_names_to_keys[name] = {}
		searchable_display_names_to_keys[remove_spaces(name)] = {}
	end
	table.insert(display_names_to_keys[name], t)
	table.insert(searchable_display_names_to_keys[remove_spaces(name)], t)

	local f = fs.open(item_names_path, "a")
	f.write(item_table.name..","..item_table.damage..","..name.."\n")
	f.close()
	return true -- it's a new name!
end

function remove_spaces(s)
	return string.gsub(s, " ", "_")
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

function add_item_custom_destination(data)
	local direction = find_direction(data.destination) -- if it's 'unknown' we don't care about it
	if direction == "unknown" then
		if sorting_computer_type == "storage" then
			-- terminals and monitors don't need to print that they don't care it's obvious. They may want to make a log of it though...
			print("Didn't care about custom destination to " .. data.destination)
		end
		return false -- don't need to care about it
	end
	-- {packet = "set_new_item_custom_destination", data = {items = {LIST_OF_ITEMTABLES_WITH_QUANTITIES}, destination=NEWNAME}}
	-- can include empty tables of no items for some machines (i.e. crafting)
	-- this is basically a crafting recipie just doesn't say how much it makes (and recepies should)

	-- add it to the list I guess?
	table.insert(custom_destinations, data)
	print("Cared about custom destination to " .. data.destination)
	-- use table.remove() to remove it and decrement the list elements
	return true -- we need to care about it!
end

function load_display_names()
	-- loads the item display names from the file if it exists
	item_display_names = {}
	display_names_to_keys = {}
	searchable_display_names_to_keys = {}
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
					if display_names_to_keys[t[3]] == nil then
						display_names_to_keys[t[3]] = {}
						searchable_display_names_to_keys[remove_spaces(t[3])] = {}
					end
					table.insert(display_names_to_keys[t[3]], get_item_key(item))
					table.insert(searchable_display_names_to_keys[remove_spaces(t[3])], get_item_key(item))
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

function input_from_set_of_choices(prompt, choices, force_lowercase)
	force_lowercase = force_lowercase or false
	local input = ""
	while true do
		print(prompt)
		input = read()
		if force_lowercase then
			input = string.lower(input)
		end
		for k, v in pairs(choices) do
			if force_lowercase then
				v = string.lower(v)
			end
			if v == input then
				return input
			end
		end
	end
	return input
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
		local update_startup = read_non_empty_string("Enter 'y' if this should initialize the startup on update:") == "y"
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

		-- update startup
		sorting_destination_settings.initialize_startup_on_update = update_startup

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

-- function initialize_known_destinations()
-- 	-- get them from settings if they exist
-- 	known_destinations = settings.get(settings_prefix .. "known_destinations", known_destinations)
-- 	known_destinations[""..os.getComputerID()] = true -- it knows that it exists!
-- end

-- function add_destination(destination, direction)
-- 	-- add a known destination, if direction is not nil then it knows it can send things to that destination that direction
-- 	if is_known_destination(destination) then
-- 		return -- already known so exit early
-- 	end
-- 	known_destinations[destination] = true
-- 	if direction ~= nil then
-- 		-- it can be reached by this sorter!
-- 		sorting_destination_settings[destination] = direction
-- 	end
-- end

-- function is_known_destination(destination)
-- 	return known_destinations[destination] ~= nil
-- end

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
	if not rednet.isOpen(modem_side) then
		-- if rednet isn't open, try opening it and then see if that works
		rednet.open(modem_side)
		if not rednet.isOpen(modem_side) then
			print("Error opening rednet, this will likely cause errors")
		end
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
	initialize_terminal_commands()
	load_sorting_device_action()
	load_display_names()
	load_default_destinations()
	check_if_replace_prefix()

	print("ID: " ..os.getComputerID() .. " - Label: " .. os.getComputerLabel())
	print()
	-- now what we need to do is figure out destinations.
	-- either they have final destinations which have string names, or they have computer ids
	-- find all the known destinations that exist in the network by sending out a network request,
	-- that returns a dictionary with {id, {destinations...}}, which we can use to path our way to the goal I guess.

	-- initialize_known_destinations() -- not using known destinations at the moment
	initialize_network()
	-- fetch_networking_destinations() -- see if new destinations have been added to the network. I can't do that nicely here so we're not going to. The issue is everything is running this at the same time so nothing is responding
	
	if sorting_computer_type == "sorter" then
		-- initialize sorting things!
		load_sorting_destinations(first_initialization or edit_destinations)
		find_local_connections()
		drop_all_items_into_origin()
	elseif sorting_computer_type == "terminal" then
		refresh_all_network(1, 2, 3) -- gather all the info from the network please and thanks
		-- check what type of computer this is. If it's a turtle add the commands to add recipies/directions with items in the
		-- inventory.
		if get_computer_type() == "turtle" then
			add_turtle_terminal_commands()
		end
	elseif sorting_computer_type == "display" then
		refresh_all_network()
	end
	-- now it knows where it sorts to.
	-- now it should tell everyone where it goes and also find out from everyone else where they go from. It now has to initialize everything.
	if sorting_destination_settings.isMaster then
		-- give them your list of destinations
		local packet = {packet = "set_item_default_destinations", data = default_destinations}
		rednet.broadcast(packet, network_prefix)
	else
		-- find the list of destinations
		get_default_destinations()
	end
end

function get_display_name(item_table)
	local k = get_item_key(item_table)
	return item_display_names[k] or k -- if it doesn't know the name then return the default item name
end

function get_display_from_key(item_key)
	return item_display_names[item_key] or item_key -- if it doesn't know the name then return the default item name
end

function alphabetical_key_sort(table)
	local t = {}
	for n in pairs(lines) do
		table.insert(t, n)
	end
		table.sort(t)
		return t
	end

function pairsByKeys(t, f)
	local a = {}
	for n in pairs(t) do
		table.insert(a, n)
	end
	table.sort(a, f)
	local i = 0      -- iterator variable
	local iter = function ()   -- iterator function
		i = i + 1
		if a[i] == nil then return nil
		else return a[i], t[a[i]]
		end
	end
	return iter
end

function itemKeyAlphabeticallyByDisplayName()
	local a = {}
	for n in pairs(display_names_to_keys) do -- get the display_names
		table.insert(a, n)
	end
	table.sort(a)
	local i = 0      -- iterator variable
	local iter = function()   -- iterator function
		i = i + 1
		if a[i] == nil then return nil
		else return a[i], display_names_to_keys[a[i]] -- loops over display_name, item_key
		end
	end
	return iter
end

function get_item_key(item_table)
	return item_table.name .. "-"..item_table.damage
end

function has_display_name(item_table)
	local k = get_item_key(item_table)
	return item_display_names[k] ~= nil
end

function request_stored_items()
	-- ask all the storage_masters you know to send you their contents
	packet = {packet = "get_stored_items"}
	rednet.broadcast(packet, network_prefix) -- request other connections in the network. Theoretically I should directly send to each of the masters rather than broadcast it but...
end

function request_storage_masters()
	-- send a message to all the storagemasters requesting that they reveal themselves
	packet = {packet = "get_storage_nodes"}
	rednet.broadcast(packet, network_prefix) -- request other connections in the network
end

function UpdateStorageCount()
	-- update the master count of items
	items_stored = {}
	for rednet_id, node in pairs(storage_nodes) do
		-- item data:
		for item, storage_data in pairs(node.items) do
			-- add the item to our master list!
			if items_stored[item] == nil then
				items_stored[item] = {count = 0, locations = {}}
			end
			items_stored[item].count = items_stored[item].count + storage_data.count
			-- also add the locations but not at the moment because I don't care about that at the moment FIX THIS
		end
	end
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
			if (settings.get(settings_prefix .. "initialize_startup_on_update", true)) then
				print("Copying startup file to startup.lua, can be disabled in settings")
				-- shell.run("copy ComputercraftCode/TriangleSort/sortingstartup.lua /startup.lua")
				fs.delete("/startup.lua")
				fs.copy("ComputercraftCode/TriangleSort/sortingstartup.lua", "/startup.lua")
				print("Copied")
			end
			-- then reboot
			running = false
			reboot = true
			break
		elseif message.packet == "sort_unknown_items" then
			-- tell the main sorter to sort the unknown items!
			if sorting_computer_type == "sorter" and sorting_destination_settings.isMaster then
				-- we should also make a remote version of this which sends the information to a PDA but that's not worth it atm.
				-- now since we're the master sorter we know where Unknown goes? Perhaps we should instead just check if our destinations include Unknown
				print("Reviewing items. Please do not leave until this is finished or the system will get stuck")
				player_review_items = true -- tell us to review items now! This will pause everything so hopefully people are smarter than that :P
			end
		elseif message.packet == "quit_network" then
			-- quit this loop
			running = false
			reboot = false
			break
		elseif message.packet == "get_custom_destinations" then
			-- tell them what your custom destinations are!
			if sorting_computer_type == "sorter" then
				-- only sorters respond to this one
				local data = {id = ""..os.getComputerID(), label = os.getComputerLabel(), destinations = custom_destinations}
				local packet = {packet = "return_custom_destinations", data = data}
				rednet.send(sender_id, packet, network_prefix)
			end
		elseif message.packet == "return_custom_destinations" then
			-- someone has told us what their destinations are!
			if sorting_computer_type == "display" then
				-- if we're a custom_destination display then update stuff!
				print("Not handled yet!")
			end
		elseif message.packet == "get_sorting_network_connections" then
			-- a new computer has joined the network, tell it what we are connected to!
			-- tell them who we are!
			if sorting_computer_type == "sorter" then
				-- only sorters respond to this one
				local data = {id = ""..os.getComputerID(), label = os.getComputerLabel(), destinations = sorting_destination_settings.destinations}
				local packet = {packet = "update_network_connection", data = data}
				rednet.send(sender_id, packet, network_prefix)
			end
		elseif message.packet == "update_network_connection" then
			connections[message.data.id] = message.data.destinations
			if sorting_computer_type == "sorter" then
				print("Finding local connections")
				find_local_connections()
			end
		elseif message.packet == "add_storage_node" then
			-- add the storage node to the master's list of storage nodes!
			-- local data = {id = ""..os.getComputerID(), label = os.getComputerLabel(), rednet_id = os.getComputerID()}
			if storage_nodes[message.data.rednet_id] == nil then
				storage_nodes[message.data.rednet_id] = message.data
			else
				-- otherwise just update what we know about it? This may not be necessary
				storage_nodes[message.data.rednet_id].label = message.data.label
				storage_nodes[message.data.rednet_id].id = message.data.id
			end
		elseif message.packet == "send_stored_items" then
			-- add the items stored to the lists
			-- data = {items = get_items_count_table(), id = ""..os.getComputerID(), label = os.getComputerLabel(), rednet_id = os.getComputerID()}
			storage_nodes[message.data.rednet_id] = message.data -- it has the items!
			if sorting_computer_type == "display" then
				print("Got items sent to me!")
			end
			UpdateStorageCount()
		elseif message.packet == "get_master_id" then
			-- if this is the master then it returns this ID
			if sorting_destination_settings.isMaster then
				-- tell them you're the master!
				local packet = {packet = "set_master_id", data = os.getComputerID()}
				rednet.send(sender_id, packet, network_prefix)
			end
		elseif message.packet == "set_master_id" then
			master_id = message.data
		elseif message.packet == "get_item_display_names" then
			if sorting_destination_settings.isMaster then
				-- give them your list of display names
				local packet = {packet = "set_item_display_names", data = item_display_names}
				rednet.send(sender_id, packet, network_prefix)
			end
		elseif message.packet == "set_item_display_names" then
			item_display_names = message.data
			display_names_to_keys = {}
			searchable_display_names_to_keys = {}
			for k, v in pairs(item_display_names) do
				if display_names_to_keys[v] == nil then
					display_names_to_keys[v] = {}
					searchable_display_names_to_keys[remove_spaces(v)] = {}
				end
				table.insert(display_names_to_keys[v], k)
				table.insert(searchable_display_names_to_keys[remove_spaces(v)], k)
			end
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
		elseif message.packet == "set_new_item_custom_destination" then
			-- set a custom direction for crafting/machining something
			-- packet looks like this:
			-- {packet = "set_new_item_custom_destination", data = {items = {LIST_OF_ITEMTABLES_WITH_QUANTITIES}, destination=NEWNAME}}
			-- can include empty item slots, this is the order in which it is fed to the machines in question.
			-- this will kinda suck for large numbers of items for crafting since it'll clog up the machines but that's okay I guess?
			-- possibly more information will get sent for crafting things or whatever? We'll see I guess
			add_item_custom_destination(message.data) -- message.data.items, message.data.destination

			-- if sorting_destination_settings.isMaster then
			-- 	-- this was sent a packet {packet = "set_new_item_custom_destination", data = {item = {ITEMTABLE}, destination=NEWNAME}}
			-- 	if add_item_custom_destination(message.data.items, message.data.destination) then 
			-- 		-- tell everyone the new names
			-- 		local packet = {packet = "set_item_default_destinations", data = default_destinations}
			-- 		rednet.broadcast(packet, network_prefix)
			-- 	end
			-- end
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

function store_unknown_item(count)
	-- this stores the item in the turtle since it's lost and needs help from a human
	-- for now just transfer it to the last open space. Perhaps light up redstone too? If there are no open spaces then god help us...
	count = count or turtle.getItemCount()
	for i = 16, 2, -1 do
		if turtle.getItemCount(i) == 0 then
			turtle.transferTo(i, count)
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

function handle_custom_destinations(item_key, count)
	-- return true if it's handled, false if there aren't any relevant custom destinations or if there are leftover items
	for i, custom in ipairs(custom_destinations) do
		-- check if that recipie uses the item
		-- custom = {destination = "dest", items = {ITEMTABLE_Including_quantity, ITEMTABLE_Including_quantity, ITEMTABLE_Including_quantity}}
		if not custom.delivered then
			for item_num, item_table in ipairs(custom.items) do
				local possible_item_key = get_item_key(item_table)
				if possible_item_key == item_key then
					-- it's a match! We must do something with it! Figure out the item counts necessary and store it somehow...
					local already_found = item_table.already_found or 0 -- if we've already stored some of the items then keep them!
					if already_found < item_table.count then
						-- we need to save more!
						-- transfer it to a storage slot! If we can't do that then we're kinda boned, it's one of the limitations of the system with only suck/drop
						item_table.already_found = already_found + store_current_item(item_table.count - already_found)
						print("Stored item for custom destination")
						-- this works fine even if item_table.already_found is nil, which is perfect
						already_found = item_table.already_found
						-- now check if that's all we needed for the item!
						if check_custom_direction_complete(custom) then
							break -- if it's complete then it's going to remove it probably so we don't care about any of the other items for this delivery
							-- since they can't match
						end
					end
				end
			end
		end
	end
	-- check for any delivered custom deliveries and remove them
	for i = #custom_destinations, 1, -1 do
		if custom_destinations[i].delivered then
			print("Delivered a custom destination to "..custom_destinations[i].destination)
			table.remove(custom_destinations, i)
		end
	end
	return false -- basically just always return false since the turtle should deal with the leftovers I guess...
end

function check_custom_direction_complete(custom)
	for item_num, item_table in ipairs(custom.items) do
		-- find it and check if count == already_found
		local found = item_table.already_found or 0
		if found < item_table.count then
			return false -- it's not ready to send
		end
	end
	drop_custom_direction(custom) -- send it off!
	return true
end

function drop_custom_direction(custom)
	-- this is when we know the custom direction is complete, this function will send off the items
	local direction_export = {up=turtle.dropUp, down=turtle.dropDown, forwards = turtle.drop, unknown=store_unknown_item}
	local direction = find_direction(custom.destination)
	if direction == "unknown" then
		-- hopefully this'll never happen :P
		print("ERROR WITH CUSTOM DIRECTION UNKNOWN: " .. custom.destination)
	end

	for item_num, item_table in ipairs(custom.items) do
		-- find it and drop that amount in that direction
		-- go from 2 to 16 then check 1 as a last chance so that the turtle stays organized. lol that's not going to happen for now...
		local to_deliver = item_table.count
		local delivered = 0
		local item_key = get_item_key(item_table)
		for i = 1, 16 do
			if turtle.getItemCount(i) > 0 then
				local i_item_key = get_item_key(turtle.getItemDetail(i))
				if i_item_key == item_key then
					-- keep trying to dump it up to the top until it's all dumped
					turtle.select(i)
					local original_count = turtle.getItemCount(i)
					local current_delivered = 0
					while not direction_export[direction](math.min(64, to_deliver - delivered- current_delivered)) do
						-- keep trying forever I guess? This can cause problems if the stack size is too large but I hope it'll deal for most cases
						-- have to re-evaluate how much to push out though
						current_delivered = original_count - turtle.getItemCount()
						if current_delivered + delivered >= to_deliver then
							break -- in the off chance that this failed yet succeeded somehow
						end
					end
					current_delivered = original_count - turtle.getItemCount()
					delivered = delivered + current_delivered -- update what's been delivered
					if delivered >= to_deliver then
						-- break out of the loop so we can deal with the next item!
						break
					end
				end
			end
		end
		if delivered < to_deliver then
			print("ERROR, CUSTOM DELIVERED TOO FEW " ..item_key)
		end
	end
	custom.delivered = true
	return true
end

function drop_all_items_into_origin()
	-- part of initialization, store all the items in an origin chest
	local direction = find_direction("Origin")
	if direction == "unknown" then
		direction = find_direction("origin")
	end
	local direction_export = {up=turtle.dropUp, down=turtle.dropDown, forwards = turtle.drop, unknown=store_unknown_item}
	for i = 1, 16 do
		if turtle.getItemCount(i) > 0 then
			turtle.select(i)
			direction_export[direction]()
		end
	end
	turtle.select(1)
end

function store_current_item(count)
	local original_number = turtle.getItemCount()
	if count > original_number then
		count = original_number -- we can't store more than we have in the first place
	end

	local num_transfered = 0

	for i = 16, 2, -1 do
		-- loop backwards and try to store count items
		if count <= num_transfered then
			-- then we've transfered all of it
			break
		end
		if turtle.transferTo(i, count - num_transfered) then
			-- check how many we really transfered total
			num_transfered = original_number - turtle.getItemCount()
		end
	end
	return num_transfered -- let the calling function know how much was saved
end

function get_computer_type()
	if pocket then
		return "pda"
	elseif turtle then
		return "turtle"
	end
	return "computer"
end

function load_sorting_device_action()
	-- is this a terminal?
	-- is this a sorter?
	-- is this a display?
	-- who knows? hopefully us...
	sorting_computer_type = settings.get(settings_prefix.."sorting_purpose", "REPLACE_THIS")
	display_type = settings.get(settings_prefix.."display_type", "itemscroll")
	if sorting_computer_type == "REPLACE_THIS" then
		sorting_computer_type = input_from_set_of_choices("Is this a 'sorter', 'display', or 'terminal'?", {"sorter", "display", "terminal"}, true)
		settings.set(settings_prefix.."sorting_purpose", sorting_computer_type)
		if sorting_computer_type == "display" then
			-- edit display initial settings
			edit_display_initial_settings()
		end
		save_settings()
	end
end

function edit_display_initial_settings()
	-- what display types do we have? for now, just start with scrolling stored items, and move from there probably...
	display_type = input_from_set_of_choices("Is this a 'itemscroll', 'notimplemented', or 'chooseitemscroll'?", {"itemscroll"}, true)
	settings.set(settings_prefix.."display_type", display_type)
end

function sort_currently_selected()
	if turtle.getItemCount() == 0 then
		return -- it's already dealt with for whatever reason
	end
	local item = turtle.getItemDetail()
	local item_count = turtle.getItemCount()
	local sterile_item = steralize_item_table(item)
	local item_key = get_item_key(item)
	local destination = "Unknown"
	local selected = turtle.getSelectedSlot()
	handle_custom_destinations(item_key, item_count)
	turtle.select(selected)
	if turtle.getItemCount() == 0 then
		return -- we dealt with it because of a custom direction
	end
	if default_destinations[item_key] ~= nil then
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
			-- sleep(1)
		end
		if sleepNow then
			-- print("sleeping")
			sleep(5)
		end
	end
end

function terminal_input()
	-- this handles computer input from humans! This could probably also be run from sorters since they're all parallel... hmmm...
	refresh_all_network() -- one last refresh so that we get item names and sorting systems and whatever.
	while running do
		io.write("> ")
		local human_input = read()
		local valid_command = false
		if #human_input > 0 then
			local c, space, rest = string.match(human_input, "([^ ]+)( *)(.*)")
			if c ~= nil then
				local lower_c = string.lower(c)
				-- print("lower c: "..lower_c)
				if terminal_commands[lower_c] ~= nil then
					terminal_commands[lower_c](lower_c, c, rest)
					valid_command = true
				-- else
				-- 	print("ere")
				-- 	print(terminal_commands)
				-- 	textutils.pagedPrint(textutils.serialise(terminal_commands))
				end
			end
		end
		if not valid_command then
			print("Not a valid command. Type 'help' for help")
		end
	end
end

function getFirstPeripheralSide(peripheral_type)
	for i, v in ipairs(peripheral.getNames()) do
		if peripheral.getType(v) == peripheral_type then
			return v
		end
	end
	return ""
end

function display_display()
	-- display whatever you're set to display!
	-- display_type could be "itemscroll" or other things that aren't implemented yet!
	-- I should really make it so that one computer can display multiple things but that's not ready yet :P
	-- for now I'm just going to make a computer that updates every minute or so to fetch items and slowly scolls through items

	refresh_all_network() -- so that we get display names and stored items etc.
	if display_type == "itemscroll" then
		local monitor_side = getFirstPeripheralSide("monitor")
		if monitor_side == "" then
			print("Monitor not found. Exiting")
			running = false
			return
		end
		print("Monitor found on side " .. monitor_side)
		local m = peripheral.wrap(monitor_side)
		local width, height = m.getSize()
		local i = 60
		while running do
			for display_name, item_key in itemKeyAlphabeticallyByDisplayName() do
			-- for k, v in pairs(items_stored) do
				-- print("Displaying item stored")
				m.scroll(1)
				m.setCursorPos(1, height)
				-- m.write(get_display_from_key(k) .. ": " .. v.count) -- print the line on the monitor, then live life happily!
				m.write(display_name .. ": " .. items_stored[item_key].count) -- print the line on the monitor, then live life happily!
				i = i + 1
				if not running then
					break -- so that we don't have to go through the entire loop to update etc.
				end
				sleep(1)
			end
			-- print("Done displaying items stored")
			i = i + 1
			m.scroll(1) -- to show we've made it to the end
			sleep(1)
			if i > 60 then
				-- every minute request an update on the item list! Is this a good idea? I'm not sure...
				-- now at least it's not going to change it when looping over it hopefully...
				i = 0
				request_stored_items()
				print("Requested item update")
				sleep(1) -- give it time to respond I guess? Hopefully that will be enough
			end
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
	if sorting_computer_type == "sorter" then
		parallel.waitForAll(receive_rednet_input, sort_input)
	elseif sorting_computer_type == "terminal" then
		parallel.waitForAll(receive_rednet_input, terminal_input)
	elseif sorting_computer_type == "display" then
		-- print("Monitors/displays are not yet supported, sorry!")
		parallel.waitForAll(receive_rednet_input, display_display)
	end

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