--[[
todo:
-make it review the unknown items each time it gets more connections! The reason why they're unknown is because it hasn't found the way to deliver
them, so we need to let that happen!
-refactor the code so the networking stuff that's needed for the storage side of things can be used there.
-save and load custom destinations? that's probably a good idea.
-crafting somehow
-storage clusters.
-storage warehouses
	- warehouse master
	- fetching robots
	- junk watcher to stop storing unstackable items etc. I need to also figure out which items are stackable and which aren't, which probably means asking if it's stackable when you import it the first time and maybe temporarily making a function to just review all the items we already know.
-storage master turtle that keeps track of everything
-convert all rednet into messages that include sender ids and reciever ids so it's compatible with rednet resenders. They also may need to store a table
of messages they've responded to to avoid responding multiple times.

-Processing Improvements:
	- Save recipies with the number and type of item output and allow players to chose them
		- this should be saved on the master and sent over network to everyone
	- Create a "machine monitor" which watches over a machine like the induction smelter or alloy smelter or crafting turtle to only send a single custom recipie until it gets a redstone signal after which it can send the next one
		- this also requires checking that furnaces etc. will send a redstone signal using a comparator when they have any item still being made, which I can then invert.
			- they do! so that's solid we can use that. It lit up even with a single item in it.
			- save the status of them? maybe not that's effort, but I should also just save everything so maybe at some point I can fix that
	- figure out if there's a better way to determine which computer has access to the Unknown chest not just the master. Maybe it's down the line? I'm not sure, not a priority
	- make a crafting turtle using the custom destinations! It's basically ready! If we have a monitor then we know that every item that goes into it is ready!


- Displays
	- return_custom_destinations and get_custom_destinations needs to be called by displays and actually displayed
	- storage displays when we have that working

	- storage ticker update display
		- need to handle actually receiving the item updates but after that we're pretty close to set. It should be subscribed automatically to them.

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
item_storage_updates = {} -- we only get these if we're subscribed to notifications

-- SORTING CONNECTIONS
connections = {} -- this is the graph of the network I guess?
local_connections = {}
local_directions = {} -- the inverse of local_connections, it's destination="up", destination="forwards", etc.
all_destinations = {"Player", "Storage", "Furnace", "Pulverizer"} -- every single destination just a string though. These are the default options

default_destinations = {} -- this is stored in a file and is used for regular operations
custom_destinations = {} -- this is used for crafting items!

item_display_names = {}
item_data = {} -- this will be item_key to a table of {damageable = true, max_stack_size = 64} etc, and whatever else I end up wanting like whether or not I want to store it.
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

-- rednet non-repeat stuff
local rednet_message_id = 0
local received_rednet_messages = {}

player_review_items = false -- this is true when it's time for the player to review items

terminal_commands = {}

verbose = false

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
		toggle_verbose=toggle_verbose_command,
		set_verbose=set_verbose_network_command,
		update_storage=update_storage_command,
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
	local fetch = false
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
		elseif input_lower == "fetch" then
			print("Fetch all items from storage if possible? y/n or t/f")
			local should_fetch = string.lower(read())
			if #should_fetch > 0 then
				fetch = string.find(should_fetch, "t") or string.find(should_fetch, "y")
				if fetch then
					fetch = true -- clean it up so it's not letters or numbers or whatever I guess
				else
					fetch = false
				end
			else
				-- do nothing just print the results
			end
			print("Fetch set to " .. tostring(fetch))
		elseif input_lower == "summary" then
			print("Here is the custom destination")
			textutils.pagedPrint(textutils.serialise(packet.data))
			if fetch then
				print("Will fetch items from storage")
			else
				print("Will NOT fetch items from storage")
			end
		elseif input_lower == "help" or input_lower == "?" then
			local commands = {help=true, summary=true, additem=true,  searchnames=true, send=true, nametoid=true, removeitem=true,
							addempty=true, destination=true, cancel=true, repeatitem=true, fetch=true}
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
			print("NOT IMPLEMENTED") -- FIX THIS
		elseif get_computer_type() == "turtle" and input_lower == "addcurritem" then
			-- add the item that's in the current slot, and ask how much of it
			if turtle.getItemCount() == 0 then
				print("No item to add")  -- it's possible you want to add an empty item but idk...
			else
				local item_t = turtle.getItemDetail()
				local item_key = get_item_key(item_t)
				item_t.key = item_key
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
			if fetch then
				-- fetch all the items! Yay! -- item_key, count, exact_number = false
				for i, v in ipairs(packet.data.items) do
					fetch_items_from_random_storage(v.key, v.count, false) -- don't require the exact number that's stupid.
				end
				print("Fetched all items if possible")
			end
			broadcast_including_self(packet)
			print("Sent!")
			return
		else
			print("Not a valid command. Type 'help'")
		end
	end
end

function get_next_word(text)
	local n, space, rest = string.match(text, "([^ ]+)( *)(.*)")
	return n, rest
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

function set_verbose_network_command(lower_command, command, rest)
	-- set verbose to something on the computer that you pass in!
	local val = true

	local id_text, rest = get_next_word(rest)
	if id_text ~= nil then
		local id = tonumber(id_text)
		if id ~= nil then
			-- parse the next word for the value
			local val_text, rest = get_next_word(rest)
			if val_text ~= nil then
				val = string.find(string.lower(val_text), "t") -- if it has a t in it it's true
				if val then
					val = true -- clean it up somewhat
				else
					val = false
				end
				send_correct(id, {packet = "set_verbose_setting", data = {value = val}})
			else
				print("Error parsing true/false text")
			end
		else
			print("Error parsing '" .. id_text .. "' to a number")
		end
	else
		print("Usage: command <rednet_id> <true/false>")
	end
end

function quit_self_command(lower_command, command, rest)
	running = false
	send_correct(os.getComputerID(), {packet = "quit_network"})
end

function quit_network_command(lower_command, command, rest)
	running = false
	local packet = {packet = "quit_network"}
	broadcast_including_self(packet)
end

function toggle_verbose_command(lower_command, command, rest)
	verbose = not verbose
	print("Set verbose to " .. tostring(verbose))
end

function get_random_storage_node()
	local all_nodes = {}
	for id, _ in pairs(storage_nodes) do
		all_nodes[#all_nodes + 1] = id
	end
	if #all_nodes == 0 then
		return nil
	else
		return all_nodes[math.random(#all_nodes)]
	end
end

function reboot_network_command(lower_command, command, rest)
	running = false
	reboot = true
	local packet = {packet = "reboot_network"}
	broadcast_including_self(packet)
end

function update_self_command(lower_command, command, rest)
	send_correct(os.getComputerID(), {packet = "update_network"})
end

function update_network_command(lower_command, command, rest)
	local packet = {packet = "update_network"}
	broadcast_including_self(packet)
end

function update_storage_command(lower_command, command, rest)
	local packet = {packet = "update_storage_network"}
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
	if not sorting_destination_settings.isMaster then
		broadcast_including_self({packet = "get_default_destinations"})
		broadcast_including_self({packet = "get_item_display_names"})
		get_default_destinations()
	end

	-- refresh storage things
	request_storage_masters()
	request_stored_items()
end

function slow_print_display_name_item_count_command(lower_command, command, rest)
	-- loop through the item list printing out how many of each item we have in each storage system.
	-- I should also support multiple storage systems and collect all the items but for now... no. I refuse to fall prey to that :P
	paged_print_all_stored_items()
end

function paged_print_all_stored_items(alphabetical)
	-- defaults to alphabetical
	local output = ""
	if alphabetical == nil or alphabetical == true then
		for display_name, item_key in itemKeyAlphabeticallyByDisplayName() do
			if items_stored[item_key] ~= nil then
				-- only display it if we have it in storage duh
				output = output .. display_name .. ": " .. items_stored[item_key].count .. "\n"
			end
		end
	else
		for k, v in pairs(items_stored) do
			output = output .. get_display_from_key(k) .. ": " .. v.count .. "\n"
		end
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

function fetch_items_from_random_storage(item_key, count, exact_number)
	local data = {item = {key = item_key, count = count, exact_number = exact_number}, requesting_computer = os.getComputerID()}
	local packet = {packet = "fetch_items", data = data}
	-- I don't have a good way to handle multiple storage systems at once so for now I'll just send it to one of them I guess? welp... FIX THIS
	local node_picked = get_random_storage_node()
	if node_picked == nil then
		print("ERROR, no known storage nodes")
	else
		print("Sending request to storagemaster at id "..node_picked)
		send_correct(node_picked, packet)
	end
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
	return {name = name, damage = damage, key = item_key}
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
	item_data = {}
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
				local name, dmg, max_stack_size, damageable, display_name = string.match(line, "([^,]+),([^,]+),([^,]+),([^,]+),\"(.+)\"")
				if name ~= nil then
					-- found it correctly!
					dmg = tonumber(dmg) or dmg  -- if it's not a number I guess we'll just deal???
					max_stack_size = tonumber(max_stack_size) or max_stack_size
					damageable = string.lower(damageable) == "true"
					local item = {name = name, damage = dmg}
					item_display_names[get_item_key(item)] = display_name
					item_data[get_item_key(item)] = {max_stack_size = max_stack_size, damageable = damageable} -- store the extra info we have!
					if display_names_to_keys[display_name] == nil then
						display_names_to_keys[display_name] = {}
						searchable_display_names_to_keys[remove_spaces(display_name)] = {}
					end
					table.insert(display_names_to_keys[display_name], get_item_key(item))
					table.insert(searchable_display_names_to_keys[remove_spaces(display_name)], get_item_key(item))
				else
					print("Error parsing line: '"..line .. "'")
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
	for dest, dir in pairs(local_connections) do
		all_destinations[#all_destinations + 1] = dest -- add the destinations to the all_destinations list!
	end
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
	broadcast_correct(packet)
end

function initialization()
	-- just holds all the functions that should be called before it initializes
	load_settings()
	initialize_terminal_commands()
	load_sorting_device_action()
	check_if_replace_prefix()

	print("ID: " ..os.getComputerID() .. " - Label: " .. os.getComputerLabel())
	print()
	-- now what we need to do is figure out destinations.
	-- either they have final destinations which have string names, or they have computer ids
	-- find all the known destinations that exist in the network by sending out a network request,
	-- that returns a dictionary with {id, {destinations...}}, which we can use to path our way to the goal I guess.

	-- initialize_known_destinations() -- not using known destinations at the moment
	initialize_network()
	broadcast_reset_message_id() -- tell everyone that we're resetting our message ID so they should delete our old messages
	-- fetch_networking_destinations() -- see if new destinations have been added to the network. I can't do that nicely here so we're not going to. The issue is everything is running this at the same time so nothing is responding
	
	if sorting_computer_type == "sorter" then
		-- initialize sorting things!
		load_sorting_destinations(first_initialization or edit_destinations)
		if sorting_destination_settings.isMaster then
			-- only load the display and destination files if you're a master. Everyone else will ask you for them.
			load_display_names()
			load_default_destinations()
		end
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
		broadcast_correct(packet)
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
		if a[i] == nil then
			return nil
		else
			return a[i], t[a[i]]
		end
	end
	return iter
end

function itemKeyAlphabeticallyByDisplayName()
	local a = {}
	for n in pairs(display_names_to_keys) do -- get the display_names into the table a
		table.insert(a, n)
	end
	table.sort(a)
	local i = 0      -- iterator variable
	local iter = function()   -- iterator function
		i = i + 1
		-- print(textutils.pagedPrint(textutils.serialise(display_names_to_keys[a[i]])))
		if a[i] == nil then
			return nil
		else
			return a[i], display_names_to_keys[a[i]][1], safe_get_item_count(display_names_to_keys[a[i]][1]) -- loops over display_name, item_key (which for some reason is in a table?)
		end
	end
	return iter
end

function alphabeticalItemKeyBothDirectionsManual()
	local a = {}
	for n in pairs(display_names_to_keys) do -- get the display_names into the table a
		table.insert(a, n)
	end
	table.sort(a)
	local i = 0      -- iterator variable
	local iter = function(step)   -- iterator function
		i = i + step
		if i < 0 then
			return nil
		elseif a[i] == nil then
			return nil
		else
			return a[i], display_names_to_keys[a[i]][1], safe_get_item_count(display_names_to_keys[a[i]][1]) -- loops over display_name, item_key (which for some reason is in a table?)
		end
	end
	return iter
end

function get_item_count_from_key_or_display_name(key_or_display_name)
	local count = safe_get_item_count(key_or_display_name) -- if it's an item key it'll work
	if count == 0 then
		-- it's possible it's a display name, in which case we should try to convert it to a item_key then return that value
		print("FIX THIS NOT IMPLEMENTED YET") -- I may actually be set without this function, but I'll leave it here for now. I guess this is how dead code gets made...
	end
	return count
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
	send_to_storage_nodes(packet)
	-- broadcast_correct(packet) -- request other connections in the network. Theoretically I should directly send to each of the masters rather than broadcast it but...
end

function request_storage_masters()
	-- send a message to all the storagemasters requesting that they reveal themselves
	-- This can't use send_to_storage_nodes because we don't know them yet
	packet = {packet = "get_storage_nodes"}
	broadcast_correct(packet)
end

function send_to_storage_nodes(packet)
	for rednet_id, node in pairs(storage_nodes) do
		send_correct(rednet_id, packet)
	end
end

function get_all_destinations()
	-- request the destinations from the master computer!
	packet = {packet = "get_all_destinations"}
	broadcast_correct(packet)
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

function safe_get_item_count(item_key)
	if items_stored[item_key] == nil then
		return 0
	end
	return items_stored[item_key].count
end

function receive_rednet_input()
	-- this function is used by the parallel api to manage the rednet side of things
	while running do
		local sender_computer_id, message, received_protocol = rednet.receive(network_prefix)
		if verbose then
			print("Recieved rednet input: " .. message.packet)
		end
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
			elseif message.packet == "update_network" then
				-- update from github!
				print("Updating")
				shell.run("github clone jordanfb/ComputercraftCode")
				-- copy the startup file into the main place
				if (settings.get(settings_prefix .. "initialize_startup_on_update", true)) then
					print("Copying startup file to startup.lua, can be disabled in settings")
					-- shell.run("copy ComputercraftCode/TriangleSort/sortingstartup.lua /startup.lua")
					fs.delete("/startup.lua")
					fs.copy("ComputercraftCode/TriangleSort/sortingstartup.lua", "/startup.lua")
					print("Copied!")
				end
				-- then reboot
				running = false
				reboot = true
				break
			elseif message.packet == "set_verbose_setting" then
				verbose = message.data.value
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
					send_correct(sender_id, packet)
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
					send_correct(sender_id, packet)
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
				if sorting_computer_type == "display" then
					request_stored_items()
				end
				if sorting_computer_type == "display" and display_type == "storageupdateticker" then
					-- subscribe to item changes so we can print them out!
					local packet = {packet = "subscribe_to_storage_changes"}
					send_correct(sender_id, packet)
				end
			elseif message.packet == "send_stored_items" then
				-- add the items stored to the lists
				-- data = {items = get_items_count_table(), id = ""..os.getComputerID(), label = os.getComputerLabel(), rednet_id = os.getComputerID()}
				storage_nodes[message.data.rednet_id] = message.data -- it has the items!
				if sorting_computer_type == "display" then
					print("Recieved item list")
				end
				UpdateStorageCount()
			elseif message.packet == "storage_change_update" then
				-- for the update ticker at the very least and possibly more types
				-- store the item change so we can display it or use it or whatever. The only reason why I have everyone store it is because you
				-- have to subscribe to this to get it
				item_storage_updates[#item_storage_updates + 1] = message.data
			elseif message.packet == "get_master_id" then
				-- if this is the master then it returns this ID
				if sorting_destination_settings.isMaster then
					-- tell them you're the master!
					local packet = {packet = "set_master_id", data = os.getComputerID()}
					send_correct(sender_id, packet)
				end
			elseif message.packet == "get_all_destinations" then
				-- if you're the master tell them what the destinations are!
				if sorting_destination_settings.isMaster then
					local packet = {packet = "set_all_destinations", data = all_destinations}
					send_correct(sender_id, packet)
				end
			elseif message.packet == "set_all_destinations" then
				-- we've learned what the destinations are! yay!
				all_destinations = message.data
			elseif message.packet == "set_master_id" then
				master_id = message.data
			elseif message.packet == "get_item_display_names" then
				if sorting_destination_settings.isMaster then
					-- give them your list of display names
					local packet = {packet = "set_item_display_names", data = {display_names = item_display_names, item_data = item_data}}
					send_correct(sender_id, packet)
				end
			elseif message.packet == "set_item_display_names" then
				item_display_names = message.data.display_names
				item_data = message.data.item_data
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
						local packet = {packet = "set_item_display_names", data = {display_names = item_display_names, item_data = item_data}}
						broadcast_correct(packet)
					end
				end
			elseif message.packet == "set_new_item_default_destination" then
				-- set an individual display name in the master, probably from a pocket computer or a special outside computer monitor idk...
				if sorting_destination_settings.isMaster then
					-- this was sent a packet {packet = "set_new_item_default_destination", data = {item = {ITEMTABLE}, destination=NEWNAME}}
					if add_item_default_destination(message.data.item, message.data.destination) then 
						-- tell everyone the new names
						local packet = {packet = "set_item_default_destinations", data = default_destinations}
						broadcast_correct(packet)
					end
				end
			elseif message.packet == "set_item_default_destinations" then
				default_destinations = message.data
			elseif message.packet == "get_item_default_destinations" then
				if sorting_destination_settings.isMaster then
					-- give them your list of destinations
					local packet = {packet = "set_item_default_destinations", data = default_destinations}
					send_correct(sender_id, packet)
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
				-- 		broadcast_correct(packet)
				-- 	end
				-- end
			end
		end
	end
end

function connect_to_sorting_network()
	-- this brodcasts to the network what this node has and then also asks what they have, which it builds into a map in the receive_rednet_input function
	local data = {id = ""..os.getComputerID(), label = os.getComputerLabel(), destinations = sorting_destination_settings.destinations}
	-- send it out to the sorting network!
	local packet = {packet = "update_network_connection", data = data}
	broadcast_correct(packet)  -- tell them who I am

	packet = {packet = "get_sorting_network_connections"}
	broadcast_correct(packet) -- request other connections in the network

	if sorting_destination_settings.isMaster then
		-- tell them you're the master!
		local packet = {packet = "set_master_id", data = os.getComputerID()}
		broadcast_correct(packet)
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
		for i = 2, 17 do
			if i == 17 then
				i = 1 -- this is so that we deal with custom destinations the nice way and stay organized!
				-- theoretically this should work fine, I tested it in pure lua, but I haven't tested it in computercraft so hopefully
				-- it won't infinite loop. If it does we can simply add a break statement at the end to exit if i == 1
			end
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
	display_type = input_from_set_of_choices("Is this a 'itemscroll', 'storageupdateticker', or 'fetchwindow'?", {"itemscroll", "storageupdateticker", "fetchwindow"}, true)
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
					broadcast_correct(packet)
					send_correct(os.getComputerID(), packet)
					-- that way whatever the master is can have it and we don't have to keep track of it.
				end
				local old_destination = default_destinations[item_key]
				if old_destination == nil then
					-- now figure out what the destination is, then put it in the origin chest!
					local new_destination = read_non_empty_string("Enter the destination of " .. currDisplayName)
					local packet = {packet = "set_new_item_default_destination", data = {item=item, destination=new_destination}}
					broadcast_correct(packet)
					send_correct(os.getComputerID(), packet)
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

	local monitor_side = getFirstPeripheralSide("monitor")
	local m = term.native()
	local monitor_found = true
	if monitor_side == "" then
		print("Monitor not found. Wrapping native term as monitor")
		monitor_found = false -- so that we don't call things like monitor.resizeText on it
	else
		print("Monitor found on side " .. monitor_side)
		m = peripheral.wrap(monitor_side)
	end
	local width, height = m.getSize()
	sleep(1) -- sleep for a second in the hopes that the masters and sorting systems will get their stuff figured out so we have a smooth ride

	refresh_all_network() -- so that we get display names and stored items etc.
	if display_type == "itemscroll" then
		local i = 60
		while running do
			for display_name, item_key in itemKeyAlphabeticallyByDisplayName() do
				if items_stored[item_key] ~= nil then

					-- only display it if we have it in storage duh
					m.scroll(1)
					m.setCursorPos(1, height)
					m.write(display_name .. ": " .. items_stored[item_key].count) -- print the line on the monitor, then live life happily!
					i = i + 1
					if not running then
						break -- so that we don't have to go through the entire loop to update etc.
					end
					sleep(1)
				end
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
	elseif display_type == "storageupdateticker" then
		print("Starting update ticker display")
		-- always subscribe to any new storage systems you hear about!
		-- now we just display updates as they come in? I'm not going to implement this yet but I'll leave this here
		local number_of_updates = 0
		while running do
			for i = number_of_updates+1, #item_storage_updates do
				-- we've got a new update and we should display it on our monitor!
				m.scroll(1)
				m.setCursorPos(1, height)
				local update = item_storage_updates[i]
				local change_text = update.change .. "" -- make it a string so we can add the +/- sign
				if update.change > 0 then
					-- make it green!
					m.setTextColor(colors.green)
					change_text = "+" .. change_text
				else
					-- make it red!
					m.setTextColor(colors.red)
					-- will already have the minus sign so we don't need to add it
				end
				-- write the latest update to storage
				m.write(get_display_from_key(update.key) .. " " .. change_text .. " => " .. update.count)
			end
			number_of_updates = #item_storage_updates
			sleep(1)
		end
	elseif display_type == "fetchwindow" then
		-- PRETTY GUI THINGS!
		-- top line should be A-Z and * filters! Assume that we always have at least 26 characters because otherwise is sad
		local fetch_settings = {destination = "Player", in_system = "In System", width = width, height = height, using_monitor = monitor_found}
		local sorted_items_function = get_sorted_items
		while running do
			local choice = draw_sorting_menu(m, sorted_items_function, fetch_settings)
			-- then go use that choice in a choice menu! Select how many to fetch probably! Magic stuff!
			-- print("Made choice! " .. tostring(choice))
			if choice.name ~= nil then
				local count = item_count_menu(m, choice, fetch_settings)
			end
			sleep(1)
		end
	end
end

function item_count_menu(m, choice, fetch_settings)
	-- draw the menu for how many of the item you want to get.
	-- show a back button, show a fetch button, show the names, and set the choice when you submit etc.
	-- +1  +8  +64 
	local myTimer = os.startTimer(5)
	local menu_settings = {exit = false, screen_middle_height = math.floor(fetch_settings.height/2),
				all_button_width = }
	while running do
		-- draw the current count! the max count, and the item name, and the buttons etc.

		m.setBackgroundColor(colors.white)
		m.clear() -- clear everything to light gray


		-- draw_rectangle(m, x, y, width, height, color)
		-- center_string_coords(m, s, x, y, width, height, bg_color, text_color)
		-- draw the item name!
		center_string_coords(m, "Fetching:", 1, math.floor(screen_middle_height/2)-1, fetch_settings.width, 1, colors.white, colors.black)
		center_string_coords(m, choice[1], 1, math.floor(screen_middle_height/2), fetch_settings.width, 1, colors.white, colors.black)
		local num_string = tostring(choice.count)
		-- fix DISPLAY AND USE MAX ITEMS AVAILABLE. FIX THIS. It's not worth it at the moment I don't want to deal with it :P
		center_string_coords(m, num_string, 1, menu_settings.screen_middle_height - 1, fetch_settings.width, 1, colors.white, colors.black)
		center_string_coords(m, " -64  -8  -1  +1  +8  +64 ", 1, menu_settings.screen_middle_height, fetch_settings.width, 1, colors.lightGray, colors.black)
		

		-- now draw the submit and the quit button!
		-- cancel button
		draw_rectangle(m, 1, fetch_settings.height - 5, math.floor((fetch_settings.width-1)/2), 5, colors.lightGray)
		center_string_coords(m, "Cancel", 1, fetch_settings.height - 5, math.floor((fetch_settings.width-1)/2), 5, colors.lightGray, colors.black)
		-- submit button
		draw_rectangle(m, fetch_settings.width - math.floor((fetch_settings.width-1)/2), fetch_settings.height - 5, math.floor((fetch_settings.width-1)/2), 5, colors.lightGray)
		center_string_coords(m, "Fetch", fetch_settings.width - math.floor((fetch_settings.width-1)/2), fetch_settings.height - 5, math.floor((fetch_settings.width-1)/2), 5, colors.lightGray, colors.black)


		local event, param1, param2, param3, param4, param5 = os.pullEvent()
		if event == "timer" then
			-- check if it's mine just for the fun of it? If it is, start a new one. In the meantime, refresh!
			if param1 == myTimer then
				print("Resetting my timer!")
				myTimer = os.startTimer(5)
				refresh_all_network() -- maybe just refresh items and destinations but shhh it works for now
			end
		elseif event == "monitor_touch" then
			-- deal with the button presses!
			handle_item_count_menu_event(m, param2, param3, choice, fetch_settings, menu_settings)
		elseif event == "mouse_click" and not fetch_settings.using_monitor then
			-- mouse click! may be useful if we're on a pocket computer etc.
			-- only use these clicks if we're displaying on our computer screen
			handle_item_count_menu_event(m, param2, param3, choice, fetch_settings, menu_settings)
		end

		if menu_settings.exit then
			os.cancelTimer(myTimer)
			return choice.count, choice
		end
		sleep(0)
	end
	os.cancelTimer(myTimer)
end

function handle_item_count_menu_event(m, x, y, choice, fetch_settings, menu_settings)
	--
end

function get_sorted_items(filter_characters, num_items, page_num, has_items_stored)
	-- sort the names alphabetically and have counts!
	-- if we don't have the display name just show the item_key!
	local iter = alphabeticalItemKeyBothDirectionsManual()
	-- loop through these to find the items that are in order that we can display!
	local display_items = {} -- indexed by number, starting at 1, and with a table of values to display left to right!
	local items_to_skip = (page_num - 1) * num_items -- skip however many pages of items!
	local filter_len = #filter_characters
	if string.sub(filter_characters, 1, 1) == "*" then
		-- it's a global match! Include everything!
		filter_len = 0
	end
	local filter_characters = string.lower(filter_characters) -- make it lowercase!
	local filter_check = filter_characters
	while #display_items < num_items do
		-- figure it out!
		-- loop until something matches your filter_characters!
		-- if we don't hit anything then skip it!
		local display_name, item_key, item_count = iter(1)
		if display_name == nil then
			-- exit out! We don't have anything more to show!
			break
		end
		-- otherwise we've at least found SOME item, so try to see if it's filterable!
		if filter_len > 0 then
			filter_check = string.sub(string.lower(display_name), 1, filter_len)
		end
		if filter_check == filter_characters and (not has_items_stored or item_count > 0) then
			-- it's a valid item to display!
			if items_to_skip > 0 then
				items_to_skip = items_to_skip - 1
			else
				-- add it to the list of items!
				display_items[#display_items + 1] = {display_name, item_key, item_count}
			end
		end
	end
	return display_items
end

function draw_sorting_menu(m, item_list_function, fetch_settings)
	-- return the selection index!
	local myTimer = os.startTimer(60)
	local side_button_width = math.floor(fetch_settings.width/3)
	local middle_button_width = math.floor(fetch_settings.width/3) + (fetch_settings.width % 3)

	local item_display_height = fetch_settings.height - 3
	-- get_sorted_items(filter_characters, num_items, page_num)

	local dest_int = 1
	for i = 1, #all_destinations do
		if all_destinations[i] == fetch_settings.destination then
			dest_int = i
			break -- set the dest int to be whatever destination there is then so we can change it nicely!
		end
	end


	local menu_settings = {middle_button_width = middle_button_width, side_button_width = side_button_width,
					filter_character = "*", exit = false, dest_int = dest_int, page = 1,
					item_list_function = item_list_function, item_display_height = item_display_height,
					item_current_page = 1, -- so that we can check if we've changed what page we're now on!
				}
	menu_settings.items = menu_settings.item_list_function(menu_settings.filter_character, menu_settings.item_display_height, menu_settings.page, menu_settings.in_system == "In System")

	m.setBackgroundColor(colors.lightGray)
	m.clear() -- clear everything to light gray

	while running do
		-- print the alphabet up top for filtering!
		-- if the filter letters are more then 1 then make a word entry box with a delete button!
		-- Typing it in adds characters, deleting (obviously) removes them, until it gets to zero characters i.e. the star, anything filter
		-- FIX THIS!
		if fetch_settings.width < 26 then
			-- oh dear. Probably error? I don't want to deal with this :P -- the correct way would be to have < and > on the sides to slide the window
			print("Error fitting it all in one screen please use a larger screen thanks!")
		else
			-- draw all of them! We have room!
			m.setCursorPos(1, 1)
			-- draw *A-Z! yay!
			for i = 0, 26 do
				local c = "*"
				if i > 0 then
					-- get the character from the alphabet!
					c = string.sub("ABCDEFGHIJKLMNOPQRSTUVWXYZ", i, i)
				end
				if c == menu_settings.filter_character and fetch_settings.width > 26 then
					m.setBackgroundColor(colors.green)
					m.setTextColor(colors.white)
					m.write(c) -- so that we don't print when it's not wide enough
				else
					m.setBackgroundColor(colors.lightGray)
					m.setTextColor(colors.black)
					m.write(c)
				end
			end
		end
		-- print the buttons on the bottom!
		-- leftmost buttons!
		-- prev button
		draw_rectangle(m, 1, fetch_settings.height-1, side_button_width, 1, colors.lightGray)
		center_string_coords(m, "Prev", 1, fetch_settings.height-1, side_button_width, 1, colors.lightGray, colors.black)
		-- exit button? maybe we don't want it, but we want it for pocket computers...
		draw_rectangle(m, 1, fetch_settings.height, side_button_width, 1, colors.gray)
		center_string_coords(m, "Exit", 1, fetch_settings.height, side_button_width, 1, colors.gray, colors.white)
		-- center buttons (alternate colors so they're clearer)
		-- in system
		draw_rectangle(m, side_button_width+1, fetch_settings.height-1, middle_button_width, 1, colors.gray)
		center_string_coords(m, tostring(fetch_settings.in_system), side_button_width+1, fetch_settings.height-1, middle_button_width, 1, colors.gray, colors.white)
		-- refresh? Maybe auto-refresh though, but it works
		draw_rectangle(m, side_button_width+1, fetch_settings.height, middle_button_width, 1, colors.lightGray)
		center_string_coords(m, "Refresh", side_button_width+1, fetch_settings.height, middle_button_width, 1, colors.lightGray, colors.black)
		-- right buttons
		-- next button
		draw_rectangle(m, side_button_width+middle_button_width+1, fetch_settings.height-1, side_button_width, 1, colors.lightGray)
		center_string_coords(m, "Next", side_button_width+middle_button_width+1, fetch_settings.height-1, side_button_width, 1, colors.lightGray, colors.black)
		-- Destination button (limited to the button width no matter the length of the destination
		draw_rectangle(m, side_button_width+middle_button_width+1, fetch_settings.height, side_button_width, 1, colors.gray)
		center_string_coords(m, string.sub(fetch_settings.destination, 1, side_button_width), side_button_width+middle_button_width+1, fetch_settings.height, side_button_width, 1, colors.gray, colors.white)

		-- then draw the items to pick from, page by page! Filter them by the filter characters obviously!
		-- have to sort them all as lowercase too because I don't want case sensitivity to mess things up
		-- FIX THIS (then add a number choosing screen and then hit send and it's done!) Return this pick to the main display function for it to call the number picker
		-- loop over the items to display!
		m.setBackgroundColor(colors.white)
		for i = 2, fetch_settings.height - 2 do
			m.setCursorPos(1, i)
			m.clearLine()
		end
		if #menu_settings.items == 0 and menu_settings.page == 1 then
			-- we don't have anything matching this query at all
			m.setCursorPos(1, 2)
			m.setBackgroundColor(colors.white)
			m.setTextColor(colors.black)
			m.write("No items matching "..tostring(menu_settings.filter_character))
		elseif #menu_settings.items == 0 then
			-- we're on the second page or something of this, so we have had some items, but now we're out!
			m.setCursorPos(1, 2)
			m.setBackgroundColor(colors.white)
			m.setTextColor(colors.black)
			m.write("No more items matching "..tostring(menu_settings.filter_character))
		else
			m.setBackgroundColor(colors.white)
			m.setTextColor(colors.black)
			for y = 1, #menu_settings.items do
				-- draw the items!
				m.setCursorPos(1, y+1)
				-- draw an index? Do we care? Maybe? It's handy I guess to give you an idea about how many items there are visible
				local index = (y) + (menu_settings.page- 1) * menu_settings.item_display_height
				m.write(tostring(index))
				m.setCursorPos(5, y+1)
				m.write(tostring(menu_settings.items[y][1])) -- the display name!
				m.setCursorPos(fetch_settings.width - 5, y+1)
				m.write(tostring(menu_settings.items[y][3])) -- the item count in the system
			end
		end

		-- then get events! If it's a timer event then probably update and set another timer! If it's a monitor_touch event or a screen touch event then figure out what happens!
		local event, param1, param2, param3, param4, param5 = os.pullEvent()
		if event == "timer" then
			-- check if it's mine just for the fun of it? If it is, start a new one. In the meantime, refresh!
			if param1 == myTimer then
				print("Resetting my timer!")
				myTimer = os.startTimer(60)
				refresh_all_network() -- maybe just refresh items and destinations but shhh it works for now
			end
		elseif event == "monitor_touch" then
			-- deal with the button presses!
			handle_mouse_press_on_sorting_menu(m, param2, param3, list_of_items, fetch_settings, menu_settings)
		elseif event == "mouse_click" and not fetch_settings.using_monitor then
			-- mouse click! may be useful if we're on a pocket computer etc.
			-- only use these clicks if we're displaying on our computer screen
			handle_mouse_press_on_sorting_menu(m, param2, param3, list_of_items, fetch_settings, menu_settings)
		end
		-- ignore the other events for now, but we may want to have it also handle key presses for filtering

		-- figure out the page of items to display!
		if menu_settings.item_current_page ~= menu_settings.page then
			menu_settings.item_current_page = menu_settings.page
			-- calculate the items!
			print("Generating items")
			menu_settings.items = menu_settings.item_list_function(menu_settings.filter_character, menu_settings.item_display_height, menu_settings.page, menu_settings.in_system == "In System")
		end

		if menu_settings.exit then
			-- return early
			-- print("EXIT NOT IMPLEMENTED YET I'M WORKING ON IT")
			os.cancelTimer(myTimer)
			if menu_settings.choice == nil then
				menu_settings.choice = {count = 0}
			else
				menu_settings.max_items = menu_settings.count
				menu_settings.count = 64 -- default number? perhaps we choose the max stack size? For now leave it as is. FIX THIS
			end
			menu_settings.choice.destination = fetch_settings.destination
			return menu_settings.choice  -- may be nil, but otherwise it's something!
		end
	end
	os.cancelTimer(myTimer)
end

function handle_mouse_press_on_sorting_menu(m, x, y, list_of_items, fetch_settings, menu_settings)
	-- figure out what was pressed and change things! also may need to return things but for now just edit the settings
	if y >= fetch_settings.height then
		-- bottom row of buttons
		if x <= menu_settings.side_button_width then
			-- exit button pressed
			print("Exit button pressed")
			menu_settings.exit = true
		elseif x <= menu_settings.side_button_width + menu_settings.middle_button_width then
			-- refresh!
			print("Refreshing!")
			refresh_all_network()
			menu_settings.item_current_page = -1
		else
			-- the destination button!
			if #all_destinations == 0 then
				-- we don't know anything so tell people to refresh?? IDK.
			else
				-- change the setting to the next one!
				menu_settings.dest_int = menu_settings.dest_int + 1
				if menu_settings.dest_int > #all_destinations then
					menu_settings.dest_int = 1
				end
				fetch_settings.destination = all_destinations[menu_settings.dest_int]
			end
		end
	elseif y >= fetch_settings.height - 1 then
		-- second to bottom row of buttons
		if x <= menu_settings.side_button_width then
			-- exit button pressed
			print("Prev button pressed")
			menu_settings.page = math.max(menu_settings.page - 1, 1) -- can't go below page 1! Unless you can and it wraps? FIX THIS
		elseif x <= menu_settings.side_button_width + menu_settings.middle_button_width then
			-- in system requirement changed!
			if fetch_settings.in_system == "In System" then
				fetch_settings.in_system = "All Items"
			else
				fetch_settings.in_system = "In System"
			end
			menu_settings.page = 1 -- also reset to the first page so we know that we should re-sort the items!
			menu_settings.item_current_page = -1 -- regenerate the page of items!
		else
			-- the destination button!
			print("Next button pressed")
			if #menu_settings.items > 0 then
				-- only go to the next page if you still have some items left to display!
				-- if you don't, then don't go to the page, duh!
				menu_settings.page = menu_settings.page + 1
			end
		end
	elseif y <= 1 then
		-- top row of settings! Choose a character!
		if fetch_settings.width > 26 then
			-- we have all of the possibilities including *
			if x < 28 then
				menu_settings.filter_character = string.sub("*ABCDEFGHIJKLMNOPQRSTUVWXYZ", x, x)
				menu_settings.page = 1
			else
				-- we pressed off to the side but that doesn't do anything
			end
		elseif fetch_settings.width < 26 then
			-- we have an error
			print("Error, monitor width is too small! Please make it larger?")
		else
			-- for pocket computers and random screens that are 26 characters wide!
			local current_x, end_x = string.find("*ABCDEFGHIJKLMNOPQRSTUVWXYZ", menu_settings.filter_character)
			if current_x <= x then
				-- adjust it by 1 so that it's avoiding the missing character!
				menu_settings.filter_character = string.sub("*ABCDEFGHIJKLMNOPQRSTUVWXYZ", x+1, x+1)
				menu_settings.page = 1
			else
				-- otherwise it's before the missing character so just go hog wild
				menu_settings.filter_character = string.sub("*ABCDEFGHIJKLMNOPQRSTUVWXYZ", x, x)
				menu_settings.page = 1
			end
		end
		menu_settings.item_current_page = -1 -- regenerate the page of items!
	else
		-- picked an item probably! Do stuff!
		-- print("Picked an item but not implemented yet, sorry!")
		if y - 1 <= #menu_settings.items then
			-- it's outside the number of items that we have displayed!
			menu_settings.choice = menu_settings.items[y-1]
			menu_settings.exit = true
		end
	end
end

function draw_rectangle(m, x, y, width, height, color)
	-- draw a rectangle of color here
	m.setBackgroundColor(color)
	for j = y, y + height - 1 do -- subtract 1 to include the starting y location
		m.setCursorPos(x, j)
		for i = 1, width do
			m.write(" ")
		end
	end
end

function center_string_coords(m, s, x, y, width, height, bg_color, text_color)
	-- write the string in the center of those coordinates
	s = tostring(s)
	m.setBackgroundColor(bg_color)
	m.setTextColor(text_color)
	local centered_x = math.floor((x+x+width)/2) - math.floor((#s+1) / 2)
	-- center the text horizontally! This gets the middle of the box, then subtracts half the text length
	m.setCursorPos(centered_x, math.floor((y+y+height)/2)) -- center vertically.
	m.write(string.sub(s, 1, width))
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