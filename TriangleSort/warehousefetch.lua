-- This is my attempt at a warehouse fetching robot, this is my secondish try, so I'm not sure how amazingly it'll go but we'll see what happens!
-- multi-layer, but single robot? Probably. It may make sense to have a fetching robot which simply rotates in place to fetch the most common items such as
-- cobble, we'll see I guess.

--[[


Example warehouse that this turtle can fetch from:

5x5
0th layer:
 -----
|     |
|     |
|     |
|     |
F0    |
 -----

0 = 0,0,0 coordinate (underneath this is the output chest)
F = refueling spot, interact with it by going to 0,0,0 and facing towards 3 (west)

side view:
 -----
|     |
| ####|
| PPPPPP
| ####|P
|     |P
| ####|P
| PPPPPP
| ####|P
F0    |PI
 E----

0 = 0,0,0 coordinate (underneath this is the output chest)
F = refueling spot, interact with it by going to 0,0,0 and facing towards 3 (west)
# = cache of items
P = refilling pipe
E = output/egress chest
I = input chest/source

Alternatively if the turtle is refilling the caches as well then simply remove the rows with P and the turtle can simply store items as well.

Do we want to support it putting them away too? That would be pretty cool I'll give you that...
May as well? It's not the priority though. We'll support scanning the vertical slice to figure that out

]]--

-- Settings:
local goalFuelLevel = 6000
local minimumFuelLevel = 1000
local zGoesUp = true -- if +z goes up then true. If +z goes down then false


-- Runtime variables:

local storageWidth = 0 -- x
local storageLength = 0 -- y
local storageHeight = 0 -- z
local storageHeightPerLayer = 0 -- z height between access layers for the turtle
-- possible heights per layer = 1:
-- 2, which is an inefficient single layer of caches that the turtle fills
-- 3, which is a effecient double layer of caches that the turtle fills
-- 4, which is a efficient 2 layer of caches and 1 of pipes that are automatically refilled

local facing = 3
local x = 0
local y = 0
local z = 0

readyForService = false

function ZeroPosition()
	readyForService = false
	if not turtle.detectUp() and not turtle.detectDown() do
		-- it's in the shaft!
		ZeroPositionFromShaft()
	end
	while turtle.detectUp() and turtle.detectDown() do
		turtle.turnRight()
		while turtle.forward() do
			-- go forward into the wall
		end
	end
	-- now we know that it's at the vertical shaft at (0,0)
	if zGoesUp then
		while turtle.down() do
			-- head to the bottom layer!
		end
	else
		-- the tower is inverted!
		while turtle.up() do
		end
	end

	facing = 3
	x = 0
	y = 0
	z = 0
	readyForService = true
end

function ZeroPositionFromShaft()
	-- if the turtle is in the vertical shaft already then it needs to zero in a special way. It first has to go to the bottom, then zero again
	readyForService = false
	if zGoesUp then
		while turtle.down() do
			-- head to the bottom layer!
		end
	else
		-- the tower is inverted!
		while turtle.up() do
		end
	end
	while not turtle.detect() do
		-- turn until it's facing the corner
	end
	while turtle.detect() do
		-- turn until it's facing open air
		turtle.turnRight()
	end
	turtle.turnLeft() -- then turn back one so we know it's facing the right way

	facing = 3
	x = 0
	y = 0
	z = 0
	readyForService = true
end

function ScanStorageDimensions()
	-- scan the width and height of the zeroth level, and also scan the height of each layer so we know where to go.
	-- this is because the setups could either be setups where turtles both store and retrieve or it could be a setup where pipes store and turtles retrieve
	-- and that changes the y levels of the passageways
	ScanStorageLevel()
	ScanStorageHeight()

	print("Scanned storage dimensions: x = " .. storageWidth .. ", y = " .. storageLength .. ", z = " .. storageHeight .. ". Height per layer is = " .. storageHeightPerLayer)
end

function ScanStorageLevel()
	-- scan the width and length of a storage level
	pathfindToFacing(0, 0, 0, 0) -- look north
	-- then count how far forward (y) you can go
	storageWidth = 0 -- x
	storageLength = 0 -- y
	while not turtle.detect() do
		goForward()
		storageLength = storageLength + 1
	end
	-- then measure width
	turnRight()
	while not turtle.detect() do
		goForward()
		storageWidth = storageWidth + 1
	end
end

function ScanStorageHeight()
	-- scan the storage height and space between layers
	pathfindToFacing(0, 0, 0, 0) -- face north so we can see where the passageways are
	storageHeight = 0
	storageHeightPerLayer = 0
	local scanningHeightPerLayer = 0
	while not turtle.detectUp() do
		goUp()
		storageHeight = storageHeight + 1
		scanningHeightPerLayer = scanningHeightPerLayer + 1
		if (not turtle.detect())
			-- then we've found a passage!
			if storageHeightPerLayer != 0 then
				-- only compare it and print out if we have an error
				if scanningHeightPerLayer != storageHeightPerLayer then
					-- the heights are wrong!
					print("ERROR! Wrong sized scanningHeightPerLayer: "..scanningHeightPerLayer .. " instead of correct: " ..storageHeightPerLayer)
				end
			else
				-- we've found out the height per layer! set it!
				storageHeightPerLayer = scanningHeightPerLayer
			end
			scanningHeightPerLayer = 0
		end
	end
end

function ScanAllItems()
	-- go through all items in the setup and record where they are, then tell the storage master or whoever wants to know
	-- this is VERY SLOW
end

function goUp()
	if zGoesUp then
		while not turtle.up() do
		end
	else
		-- the tower is inverted
		while not turtle.down() do
		end
	end
	z = z + 1
end

function goDown()
	if (zGoesUp) then
		while not turtle.down() do
		end
	else
		-- the tower is inverted
		while not turtle.up() do
		end
	end
	z = z - 1
end

function left()
	turtle.turnLeft()
	facing = facing - 1
	if facing < 0 then
		facing = 3
	end
end

function right()
	turtle.turnRight()
	facing = facing + 1
	facing = facing % 4
end

function goForward()
	while not turtle.forward() do
	end
	if facing == 0 then -- north
		y = y + 1
	elseif facing == 1 then -- east
		x = x + 1
	elseif facing == 2 then -- south
		y = y - 1
	elseif facing == 3 then -- west
		x = x - 1
	end
end

function goBackwards()
	while not turtle.back() then
	end

	if facing == 0 then -- north
		y = y - 1
	elseif facing == 1 then -- east
		x = x - 1
	elseif facing == 2 then -- south
		y = y + 1
	elseif facing == 3 then -- west
		x = x + 1
	end
end

function pathfindToFacing(goalx, goaly, goalz, goalf)
	pathfindTo(goalx, goaly, goalz)
	-- then turn to face the correct direction!
	turnToFacing(goalF)
end

function pathfindTo(goalx, goaly, goalz)
	-- move to this position.
	if (goalz != z) then
		-- move to the vertical path to go up or down levels
		pathfind2D(0, 0)
	end
	-- fix the height!
	pathfindZ(goalz)
	-- then go to the correct x and y
	pathfind2D(goalx, goaly)
	-- then we're there!
end

function pathfindZ(goalZ)
	while goalZ < z do
		goDown()
	end
	while goalZ > z do
		goUp()
	end
end

function turnToFacing(goalF)
	-- turn to face this direction!
	if (goalF == 0 and facing == 3) then
		right()
	elseif (goalF == 3 and facing == 0) then
		left()
	else
		-- otherwise just compare the numbers and turn!
		local deltaF = goalF - facing
		while (deltaF > 0) do
			right()
			deltaF = goalF - facing
		end
		while (deltaF < 0) do
			left()
			deltaF = goalF - facing
		end
	end
end

function pathfind2D(goalx, goaly)
	-- first move x then y? it doesn't really matter in the end
	local deltaX = goalx - x
	if deltaX != 0 then
		-- turn so that we can move that way!
		turnToFacing()
	end
	local deltaY = goaly - y
end

function returnToBase()
	-- return to refueling station
	pathfindToFacing(0, 0, 0, 3)
end

function checkRefuel()
	-- do this before any mission to get or store items
	if turtle.getFuelLevel() < minimumFuelLevel then
		refuel()
	end
end

function refuel()
	returnToBase()
	turtle.select(0) -- where the bucket is
	while turtle.getFuelLevel() < goalFuelLevel do
		turtle.place()
		turtle.refuel()
	end
end





-- additional helper functions
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









function startup()
	load_settings()
	ZeroPosition()
end

function main()
	startup()

	-- then go into your main loop!

end


main()