



function display_commands(command_table)
	print("Here are the commands:")
	local s = ""
	for k,v in pairs(command_table) do
		s = s .. k .. "\n"
	end
	textutils.pagedPrint(s)
end


function broadcast_including_self(packet)
	rednet.broadcast(packet, network_prefix)
	rednet.send(os.getComputerID(), packet, network_prefix)
end

function boadcast(packet)
	rednet.broadcast(packet, network_prefix)
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

function remove_spaces(s)
	return string.gsub(s, " ", "_")
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
