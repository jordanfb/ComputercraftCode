--[[
A library of important code for all of Jordan's computercraft programs

Includes things like simple navigation scripts, saving and loading position and facing and mission, and a few other things.
Hopefully this will include networking things as well to work with the TriangleSort network.
]]



function savetable(filename, table)
	-- saves tables with string keys (doesn't like numeric keys)
	if filename == nil or table == nil then
		return -- can't save nothing
	end
	local f = fs.open(filename, 'w');
	if f == nil then
		return -- error opening the file
	end
	f.write(textutils.serialize(table));
	f.close();
end

function loadtable(filename)
	-- loads the table or nil if there's no file
	if filename == nil or not fs.exists(filename) then
		return nil -- can't load nothing
	end
	local f = fs.open(filename, 'r')
	if f == nil then
		return nil -- error opening file
	end
	local serializedTable = f.readAll()
	f.close()
	return textutils.unserialize( serializedTable )
end


-- function saveposition(filename, x, y, z, facing)
-- 	-- saves to filename
-- 	local output = ""
-- 	output = output .. x .. "\n"
-- 	output = output .. y .. "\n"
-- 	output = output .. z .. "\n"
-- 	output = output .. facing .. "\n"
-- 	local f = io.open(filename, 'w');
-- 	f:write(output);
-- 	f:close();
-- end


-- function loadposition(filename)
-- 	-- return a table of {x = x, y = y, z = z, facing = facing}
-- 	-- if no file is found then it returns nil? or something like that
-- 	file = io.open('save', 'r');
-- 	X = file:read('*l');
-- 	Y = file:read('*l');
-- 	d = file:read('*l');
-- 	x = file:read('*l');
-- 	y = file:read('*l');
-- 	z = file:read('*l');
-- 	s = file:read('*l');
-- 	r = file:read('*l');
-- 	auto = file:read('*l');
-- 	avoid = file:read('*l');
-- 	autofuel = file:read('*l');
-- 	top = file:read('*l');
-- end