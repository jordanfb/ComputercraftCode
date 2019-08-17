i = 0
while not turtle.detect() do
  turtle.forward()
  turtle.placeDown()
  turtle.refuel()
  i = i + 1
end
turtle.turnRight()
turtle.turnRight()
while i > 0 do
  turtle.forward()
  i = i - 1
end
print("Fuel Level: " .. turtle.getFuelLevel())