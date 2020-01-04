--[[
warehousemasterstartup.lua
for use on warehouse masters. Duh.
]]--

local tArgs = {...}

print(os.getComputerID() ..  " " .. os.getComputerLabel())
-- shell.run("TriangleSort.lua")

if tArgs[1] == "update" then
	-- update it!
	shell.run("github clone jordanfb/ComputercraftCode")
else
	-- run the default code!
	shell.run("ComputercraftCode/TriangleSort/warehousemaster.lua") -- this works if I've cloned the repo onto the turtle
end
