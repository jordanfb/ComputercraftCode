-- This is for a refueling station where it can just stay stationary and refuel until it's full. This was necesarry because it
-- kept running out of fuel (that's a lie, it just happened once but it was a pain)

f = turtle.getFuelLevel()
print("Fuel Level: " .. turtle.getFuelLevel())
max = turtle.getFuelLimit()
print("Max Fuel: " .. max)
while turtle.getFuelLevel() < max - 1000 do
  -- place a bucket and get lava from the well
  turtle.placeDown()
  turtle.refuel()
end
print("New Fuel Level: " .. turtle.getFuelLevel())
