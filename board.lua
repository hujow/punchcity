-- board.lua  – record-based grid with per-edge walls
--------------------------------------------------------
local config = require("config")

local board = {}

-- initialise once so other modules can query size during love.load()
board.width  = config.GRID_SIZE
board.height = config.GRID_SIZE

function board.getTileType(x,y)
    local rec = board[x] and board[x][y]
    return rec and rec.type
end

------------------------------------------------------------
-- low-level helper: create a blank record
------------------------------------------------------------
local function newRecord(tileType)
    return {
        type  = tileType or "floor",
        walls = {L=false, R=false, U=false, D=false}
    }
end

------------------------------------------------------------
-- guarantee board[x][y] exists and is a *record* table
------------------------------------------------------------
local function ensureSlot(x, y)
    if not board[x] then board[x] = {} end
    local rec = board[x][y]
    if type(rec) ~= "table" then
        rec = newRecord(rec)          -- rec may be "wall"/"pit"/nil
        board[x][y] = rec
    end
    return rec
end

------------------------------------------------------------
-- public: board.init(w, h)
-- rebuild the 2-D array for a new level
------------------------------------------------------------
function board.init(gridW, gridH)
    board.width, board.height = gridW, gridH

    -- 1. allocate/keep column tables
    for x = 1, gridW do
        board[x] = board[x] or {}
        for y = 1, gridH do
            board[x][y] = newRecord()         -- fresh blank record
        end
        -- trim extra rows if the board shrank
        for y = gridH+1, #board[x] do board[x][y] = nil end
    end
    -- 2. drop columns past the new width
    for x = gridW+1, #board do board[x] = nil end
end

------------------------------------------------------------
-- mutators
------------------------------------------------------------
function board.setTileType(x, y, tileType)
    assert(x and y, "setTileType got nil coord ("..tostring(x)..","..tostring(y)..")")
    local rec       = ensureSlot(x, y)
    rec.type        = tileType or "floor"
end

function board.addWallEdge(x, y, edge)   -- edge = "L","R","U","D"
    local rec      = ensureSlot(x, y)
    rec.walls[edge]= true
end

------------------------------------------------------------
-- legacy predicate (still used by a lot of code)
------------------------------------------------------------
function board.isPassable(x, y)
    if x < 1 or x > board.width or y < 1 or y > board.height then
        return false, "outOfBounds"
    end
    local rec = ensureSlot(x, y)
    if rec.type == "wall" then return false, "wall"
    elseif rec.type == "pit" then return true,  "pit"
    end
    return true, rec.type
end

------------------------------------------------------------
-- NEW: edge-aware movement test
------------------------------------------------------------
function board.canMove(x, y, dx, dy)
    -- neighbour coords
    local nx, ny = x + dx, y + dy

    -- 0. out of bounds / full-wall check
    local ok, tileType = board.isPassable(nx, ny)
    if not ok then return false, tileType end

    -- 1. ensure both tiles are records
    local here  = ensureSlot(x , y )
    local there = ensureSlot(nx, ny)

    -- 2. pick opposite edges
    local sideOut, sideIn
    if   dx== 1 then sideOut, sideIn="R","L"
    elseif dx==-1 then sideOut, sideIn="L","R"
    elseif dy== 1 then sideOut, sideIn="D","U"
    elseif dy==-1 then sideOut, sideIn="U","D"
    end

    -- 3. allowed only if *both* edges are open
    return (not here.walls[sideOut]) and (not there.walls[sideIn]), tileType
end

------------------------------------------------------------
-- helpers for drawing
------------------------------------------------------------
function board.toPixelCentre(gx, gy)
    local T = config.TILE_SIZE
    return  config.GRID_START_X + (gx - 0.5) * T,
            config.GRID_START_Y + (gy - 0.5) * T
end

return board
