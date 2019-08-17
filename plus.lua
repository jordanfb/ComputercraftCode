args = {...}

-- setup: put torches in 1, and chest in 16, 

local facing = 0
local x = 0
local y = 0
local z = 0

local recursiveLimit = 200
local moveLeft = true
reps = 1
if #args == 2 then
  -- theoretically it should be correct?
  reps = args[2]
  moveLeft = true
elseif #args == 3 then
  reps = args[2]
  moveLeft = args[3] == "left"
elseif #args ~= 1 then
  print("Usage: plus [distance] <repetitions> <left/right>")
  print("Please insert torches into slot 1")
  print("Put torches in 1, and an ender chest in 16")
  return
end

dist = args[1]
torch = 10

local avoidList = { -- a list of the blocks the turtle shouldn't mine.
  {"minecraft:grass", 0}, -- block name and block metadata
  {"minecraft:dirt", 0},
  {"minecraft:stone", 0},
  {"minecraft:cobblestone", 0},
  {"minecraft:gravel", 0},
  {"minecraft:bedrock", 0}
}

function emptyInventory()
  turtle.select(16)
  while not turtle.placeUp() do
    turtle.digUp()
  end
  for i = 2, 16 do -- start at 2 because 1 is the torches
    turtle.select(i)
    turtle.dropUp()
  end
  turtle.select(16)
  turtle.digUp()
  turtle.select(1)
end

function emptyIfNecessary()
  if turtle.getItemCount(15) > 0 then
    emptyInventory()
  end
end

function avoidDig()
  local bool, block = turtle.inspect()
  local avoid = false
  for i = 1, #avoidList do
    if block.name == avoidList[i][1] and block.metadata == avoidList[i][2] then
      avoid = true
    end
  end
  if not avoid then
    turtle.dig()
    emptyIfNecessary()
  end
end

function goUp()
  while not turtle.up() do
    turtle.digUp()
    emptyIfNecessary()
  end
  z = z + 1
end

function goDown()
  while not turtle.down() do
    turtle.digDown()
    emptyIfNecessary()
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
    turtle.dig()
    emptyIfNecessary()
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
  if not turtle.back() then
    left()
    left()
    goForward()
  else
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
end

function recursiveDig(originFacing, originMove, recursiveLevel) -- move is up, down, forwards, so it un-turns and then un moves.
  emptyIfNecessary()
  if originMove == 3 then -- try digging in front of you
    local bool, block = turtle.inspect()
    local avoid = not bool -- if it doesn't exist, avoid it.
    for i = 1, #avoidList do
      if block.name == avoidList[i][1] and block.metadata == avoidList[i][2] then
        avoid = true
      end
    end
    if not avoid then
      while turtle.detect() do
        turtle.dig()
        emptyIfNecessary()
      end
    else
      return -- not an ore to mine so return
    end
    goForward()
  end
  if originMove == 1 then -- try digging up
    local bool, block = turtle.inspectUp()
    local avoid = not bool -- if it doesn't exist, avoid it.
    for i = 1, #avoidList do
      if block.name == avoidList[i][1] and block.metadata == avoidList[i][2] then
        avoid = true
      end
    end
    if not avoid then
      while turtle.detectUp() do
        turtle.digUp()
        emptyIfNecessary()
      end
    else
      return-- not an ore to mine so return
    end
    goUp()
  end
  if originMove == 2 then -- try digging up
    local bool, block = turtle.inspectDown()
    local avoid = not bool -- if it doesn't exist, avoid it.
    for i = 1, #avoidList do
      if block.name == avoidList[i][1] and block.metadata == avoidList[i][2] then
        avoid = true
      end
    end
    if not avoid then
      while turtle.detectDown() do
        turtle.digDown()
        emptyIfNecessary()
      end
    else
      return -- not an ore to mine so return
    end
    goDown()
  end
  if recursiveLevel >= recursiveLimit - 1 then
    -- skip the recursive calls
  else
    -- otherwise run the recursive calls
    left()
    recursiveDig(facing, 3, recursiveLevel+1)
    right() -- facing forwards
    recursiveDig(facing, 3, recursiveLevel+1)
    right()
    recursiveDig(facing, 3, recursiveLevel+1)
    if originMove ~= 1 then
      -- check down
      recursiveDig(facing, 2, recursiveLevel+1)
    end
    if originMove ~= 2 then
      recursiveDig(facing, 1, recursiveLevel+1)
    end
    if originMove ~= 3 then
      right()
      recursiveDig(facing, 3, recursiveLevel+1)
    end
  end

  -- back to the original facing when it came to this space.
  while facing ~= originFacing do
    left()
  end
  -- then move back to the place where it came from
  if originMove == 1 then -- it moved up, so move down
    goDown()
  elseif originMove == 2 then -- then it moved down, so move up
    goUp()
  elseif originMove == 3 then -- then it moved forwards, so move backwards
    goBackwards()
  end
end

function sureDig()
  while turtle.detect() do
    turtle.dig()
    emptyIfNecessary()
  end
end

function main()
  for j = 1, reps do
    for i = 0, dist do
      sureDig()
      goForward()
      recursiveDig(facing, 1, 1) -- dig up
      while turtle.detectUp() do
        turtle.digUp()
      end
      recursiveDig(facing, 2, 1) -- dig down
      turtle.digDown()
      left()
      -- do the left side
      recursiveDig(facing, 3, 1)
      sureDig()
      right()
      right()
      -- do the right side
      recursiveDig(facing, 3, 1)
      sureDig()
      left()
      if i % torch == 0 then
        turtle.select(1)
        turtle.placeDown()
      end
    end
    -- then go back to the start, and do it over again
    if (true) then
      -- go back to the start and start over again!
      right()
      right()
      for k = 0, dist do
        goForward()
      end
      -- now back at start, so turn left, then move over
      if moveLeft then
        right()
      else
        left()
      end
      goForward()
      goForward()
      goForward()
      if moveLeft then
        right()
      else
        left()
      end
    end
  end
end

main()
