-- deck.lua  –  pattern-draw manager (7-bag shuffle)
local patterns = require("patterns")

local deck = {
    cards = {},   -- *master* list        (may hold duplicates)
    bag   = {},   -- current shuffled bag (empties out, then we reshuffle)
}

--------------------------------------------------------------
-- helpers
--------------------------------------------------------------
local function refillBag()
    -- 1)  copy the current master deck
    deck.bag = {}
    for i, key in ipairs(deck.cards) do
        deck.bag[i] = key
    end

    -- 2)  Fisher-Yates shuffle in-place
    for i = #deck.bag, 2, -1 do
        local j = math.random(i)
        deck.bag[i], deck.bag[j] = deck.bag[j], deck.bag[i]
    end
end

--------------------------------------------------------------
-- public API
--------------------------------------------------------------
function deck.init(startKeys)
    deck.cards = {}                       -- reset master list
    for _, k in ipairs(startKeys) do
        table.insert(deck.cards, k)
    end
    refillBag()                           -- prime the very first bag
end

function deck.draw()
    assert(#deck.cards > 0, "Deck is empty!")
    if #deck.bag == 0 then                -- bag exhausted? → reshuffle
        refillBag()
    end
    local key = table.remove(deck.bag, 1) -- pop from the *front*
    return patterns[key], key
end

function deck.add(key)
    -- OPTION B (Tetris-99): new card joins the *next* bag only.
    table.insert(deck.cards, key)
    -- Do NOT touch the current bag – keeps draws predictable this cycle.
end

return deck
