turtle.select(1)
while true do
  turtle.place()
  turtle.select(2)
  for i = 1, 10 do
    turtle.place()
  end
  turtle.select(1)
  turtle.dig()
end
