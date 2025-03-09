-- board.lua
local config = require("config")

local board = {}

for x = 1, config.GRID_SIZE do
    board[x] = {}
    for y = 1, config.GRID_SIZE do
        board[x][y] = "floor"
    end
end

function board.setTileAsWall(x, y)
    board[x][y] = "wall"
end

function board.setTileType(x, y, tileType)
    board[x][y] = tileType
end

function board.isPassable(x, y)
    if x < 1 or x > config.GRID_SIZE or y < 1 or y > config.GRID_SIZE then
        return false, "outOfBounds"
    end

    local tileType = board[x][y]
    if tileType == "wall" then
        return false, "wall"
    elseif tileType == "pit" then
        return false, "pit"
    end
    return true, tileType
end

return board