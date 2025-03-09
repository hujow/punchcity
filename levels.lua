-- levels.lua
local levels = {

    -- Level 1
    {
        gridSize = 8,
        boardLayout = {
            -- A small example: let’s define some walls at row 1 & row 8, col 1 & col 8
            -- We'll store them as a list of {x,y} for walls
            walls = {
                {1,1}, {2,1}, {3,1}, {4,1}, {5,1}, {6,1}, {7,1}, {8,1},  -- top row
                {1,8}, {2,8}, {3,8}, {4,8}, {5,8}, {6,8}, {7,8}, {8,8},  -- bottom row
                {1,2}, {1,3}, {1,4}, {1,5}, {1,6}, {1,7},               -- left column
                {8,2}, {8,3}, {8,4}, {8,5}, {8,6}, {8,7},               -- right column
            },
            pits = {}  -- for future expansions, e.g. { {4,4}, {4,5} }
        },

        waves = {
            { grunt = 2, knight = 1 },  -- wave #1
            --{ grunt = 3, bishop = 1 },  -- wave #2
        },

        winCondition = {
            -- Means: after wave #2 is defeated & no enemies remain => level is won
            type = "waveCount",
            wavesNeeded = 1
        }
    },

    -- Level 2
    {
        gridSize = 10,
        boardLayout = {
            walls = {
                -- Some random arrangement
                {1,1}, {10,10}, {5,5}
            },
            pits = {
                {2,2}, {9,9}
            }
        },
        waves = {
            { grunt = 3, knight = 1 },
            { grunt = 2, bishop = 2 },
            { grunt = 1, knight = 1, bishop = 1 },
        },
        winCondition = {
            type = "waveCount",
            wavesNeeded = 3
        }
    },

    -- Add more levels as needed...
}

return levels
