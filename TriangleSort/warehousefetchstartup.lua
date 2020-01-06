-- warehousefetchstartup.lua

local tArgs = {...}

print(os.getComputerID() ..  " " .. os.getComputerLabel())

if tArgs[1] == "update" then
	-- update it!
	shell.run("github clone jordanfb/ComputercraftCode")
else
	-- run the default code!
	shell.run("ComputercraftCode/TriangleSort/warehousefetch.lua") -- this works if I've cloned the repo onto the turtle
end
