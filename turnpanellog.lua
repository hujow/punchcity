-- turnpanellog.lua  ----------------------------------------------
local ComicStrip = require("comicstrip")
local PanelValues = require("panelvalues")

local Log = { events = {} }

function Log.reset()
    Log.events = {}
end

-- tag = "enemyHit" / "playerHurt" / … ;  tileType may be nil
function Log.record(tag, tileType)
    Log.events[#Log.events+1] = { tag = tag, tile = tileType }
end

-- Read the current event list *without* clearing it.
function Log.peek()
    return Log.events          -- treat as read-only from the outside!
end

-----------------------------------------------------------
-- Pick the “better” bonus tile between two candidates
-----------------------------------------------------------
local PRIORITY = {              -- ↑ number == ↑ priority
    scoreDouble = 30,           -- green   (highest)
    scoreBonus  = 20,           -- gold
    -- add more here if you invent new tile types
    __DEFAULT__ = 0             -- nil / unknown
}

local function tileWeight(t)
    return PRIORITY[t] or PRIORITY.__DEFAULT__
end

local function bestTile(old, new)
    -- returns whichever of the two is strictly better
    return (tileWeight(new) > tileWeight(old)) and new or old
end


function Log.flush(immediate)                       -- uniqueEnemiesHit no longer needed
    immediate = (immediate ~= false)

    if #Log.events == 0 then return {} end

    ----------------------------------------------------------------
    -- 1) Gather events *per tag*  ➜  { tag, tile, count }
    ----------------------------------------------------------------
    local tally = {}
    for _, ev in ipairs(Log.events) do
        local key = ev.tag
        tally[key]       = tally[key] or { tag = key, tile = ev.tile, count = 0 }
        tally[key].count = tally[key].count + 1
    end

    local sequence = {}
    for _, rec in pairs(tally) do sequence[#sequence+1] = rec end
    table.sort(sequence, function(a, b)
        local pa, pb = PanelValues.priority(a.tag), PanelValues.priority(b.tag)
        if pa ~= pb then
            return pa < pb                       -- lower number first
        end
        return a.tag < b.tag                     -- deterministic tie-break
    end)


    ----------------------------------------------------------------
    -- 2) Immediate feedback?
    ----------------------------------------------------------------
    if immediate then
        for _, ev in ipairs(sequence) do
            for _ = 1, ev.count do          -- trigger the bounce each time
                ComicStrip.add(ev.tag)
            end
        end
    end

    Log.reset()
    return sequence
end

return Log
