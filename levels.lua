-- levels.lua
local levels = {


    --Level 00a
    {
        
        gridW = 10, gridH = 5,
        playerSpawn  = { 2, 3 }, 
        enemySpawns = {            -- ← NEW
        {4,2}, {6,2}, {4,4}, {6,4}},
       
        boardLayout = {
            crates = { {3,3}},
            edgeMap = {
                ". . . . . . . . . .",
                ". . . . . . . . L .",
                ". . . . . . . . L .",
                ". . . . . . . . L .",
                ". . . . . . . . L .",

            },            
        },
        waves = {
            {grunt = 4},

        },
        winCondition = {
            type = "waveCount",
            score  = 1
        }
    }, 


    --Level 00a
    {
        
        gridW = 10, gridH = 5,
        playerSpawn  = { 2, 3 }, 
        enemySpawns = {            -- ← NEW
        {4,2}, {6,2}, {4,4}, {6,3}},
       
        boardLayout = {
            crates = { {3,3}, {3,4}},
            edgeMap = {

            },            
        },
        waves = {
            {grunt = 4},

        },
        winCondition = {
            type = "waveCount",
            score  = 1
        }
    }, 


    --Level 00a
    {
        
        gridW = 8, gridH = 5,
        playerSpawn  = { 2, 3 }, 
       
        boardLayout = {

            edgeMap = {
                "UL U U U U U U UR",
                "L . . . . . . R",
                "L . . . . . . R",
                "L . . . . . . R",
                "LD D D D D D D DR",
            },            
        },
        waves = {
            {grunt = 4},

        },
        winCondition = {
            type = "waveCount",
            score  = 1
        }
    }, 


    -- Level 00a
    {
        
        gridW = 16, gridH = 8,
        gridSize = 8,
        playerSpawn  = { 6, 8 }, 
        boardLayout = {

            -- pits = {{5,5}},
            scoreDouble  = { {3,3}, {4,4}, {7,7}  },   -- green “count double” tiles
            scoreBonus   = { {2,5}, {3,5}, {5,4}  },           -- gold  “+5 per HP” tiles  
            crates = { {3,4}, {2,2,2}, {5,7}, {6,7}, {7,7}, {8,7} }, 
            edgeMap = {
                "UL U UR U U U U U UR U U UR U U U UR",
                "L . R . . . . . R . . R . . . R",
                "LD D D . . . . . R . D RD . . . R",
                "L . . . . . . . . . . R . . . R",
                "LD D DR . . . . . . . . R . . . R",
                "L . . . . . . . . . . R . . . R",
                "L . R . . . . . . . . . . . . R",
                "LD D DR D D D D D D D D D D D D DR ",
            },
        },
        waves = {
            {grunt = 10},
            {grunt = 10}, 
        },
        
        winCondition = {
            type = "scoreThreshold",
            score  = 2000
        }
    }, 


    -- Level 01

    {
        
        gridW = 16, gridH = 9,
        gridSize = 9,
        playerSpawn  = { 3, 3 }, 
       
        boardLayout = {
            walls = {
                {9,4}, {10,4}, {9,5}
            },
            -- pits = {{5,5}},
            scoreDouble  = { {3,3}, {4,4}, {7,7}  },   -- green “count double” tiles
            scoreBonus   = { {2,6}, {2,7}, {11,4}  }           -- gold  “+5 per HP” tiles            
        },
        waves = {
            {grunt = 10},
            {grunt = 10}, 
        },
        winCondition = {
            type = "scoreThreshold",
            score  = 5000
        }
    }, 


-- Level 02

    {
        gridSize = 9,
        playerSpawn  = { 3, 3 }, 
        boardLayout = {
            walls = {
                {1,1}, {2,1}, {3,1}, {4,1}, {5,1}, {6,1}, {7,1}, {8,1}, {9,1},  -- top row
                {1,9}, {2,9}, {3,9}, {4,9}, {5,9}, {6,9}, {7,9}, {8,9}, {9,9},  -- bottom row
                {1,2}, {1,3}, {1,4}, {1,5}, {1,6}, {1,7}, {1,8},              -- left column
                {9,2}, {9,3}, {9,4}, {9,5}, {9,6}, {9,7}, {9,8},              -- right column
            },
            -- pits = {{5,5}},    
        },
        waves = {
            {grunt = 5}, 
            {grunt = 4, bishop = 1},
            {grunt = 4, knight = 1},

        },
        winCondition = {
            type = "scoreThreshold",
            score  = 1000
        }
    },


    -- Level 1
    {
        gridSize = 8,
        playerSpawn  = { 3, 3 }, 
        boardLayout = {
            -- A small example: let’s define some walls at row 1 & row 8, col 1 & col 8
            -- We'll store them as a list of {x,y} for walls
            walls = {
                {1,1}, {2,1}, {3,1}, {4,1}, {5,1}, {6,1}, {7,1}, {8,1},  -- top row
                {1,8}, {2,8}, {3,8}, {4,8}, {5,8}, {6,8}, {7,8}, {8,8},  -- bottom row
                {1,2}, {1,3}, {1,4}, {1,5}, {1,6}, {1,7},               -- left column
                {8,2}, {8,3}, {8,4}, {8,5}, {8,6}, {8,7},               -- right column
            },
            -- pits = {{5,5}},    
        },

        waves = {
            { grunt = 0, knight = 1 },  -- wave #1
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
        playerSpawn  = { 3, 3 }, 
        boardLayout = {
            walls = {
                -- Some random arrangement
                {1,1},{2,1}, {10,10}, {5,5}
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
