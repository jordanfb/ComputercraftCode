args = {...}

if #args ~= 1 then
  print("Usage: plus [distance]")
  print("Please insert torches into slot 1")
  return
end

dist = args[1]
torch = 10

function sureDig()
  while turtle.detect() do
    turtle.dig()
  end
end

for i = 0, dist do
  sureDig()
  turtle.forward()
  turtle.digUp()
  turtle.digDown()
  turtle.turnLeft()
  sureDig()
  turtle.turnRight()
  turtle.turnRight()
  sureDig()
  turtle.turnLeft()
  if i % torch == 0 then
    turtle.select(1)
    turtle.placeDown()
  end
end