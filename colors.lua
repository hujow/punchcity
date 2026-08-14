-- colors.lua
local colors = {}

colors.white = {0.97, 0.97, 0.97}
colors.black = {0,0,0}

colors.wall         = {155/255, 58/255, 54/255}
colors.floorOutline = {51/255, 68/255, 68/255}
colors.floorFill    = {99/255, 111/255, 111/255}
colors.edgeWall     = {0,0,0}
--colors.floorOutline = {15/255, 34/255, 45/255}
--colors.floorFill    = {46/255, 60/255, 67/255}
colors.pit = {0,0,0}
colors.scoreDoubleTile = {  0/255, 200/255,   0/255 }   -- green
colors.scoreBonusTile  = {255/255, 215/255,   0/255 }   -- gold-ish
colors.goldText = {1.00, 0.84, 0.00}   -- warm yellow


-- old color: colors.uiPanelBackground = {210/255, 212/255, 191/255}
colors.uiPanelBackground = {106/255, 78/255, 70/255}

colors.scoreColorPanel        = {0.97, 0.97, 0.97}
colors.scoreColorCenter        = {255/255, 255/255, 255/255}
colors.comboActive       = {0.97, 0.97, 0.97}
colors.comboInactive     = {0.97, 0.97, 0.97}
colors.invincibleText    = {196/255, 63/255, 49/255}
colors.PlayerHealthFull  = {83/255, 218/255, 83/255}
colors.PlayerHealthEmpty = {0.5, 0.5, 0.5}

colors.previewPath    = {251/255, 235/255, 185/255}
colors.previewDamage  = {221/255, 100/255, 87/255}
colors.Damage         = {196/255, 63/255, 49/255}
colors.SuperKnockback = {196/255, 63/255, 49/255}
colors.comboGaugeEmpty = {0.55, 0.55, 0.55}  

colors.turnBlue       = {  69/255, 182/255, 180/255 }  -- player is choosing
colors.turnGreen      = {  0/255, 180/255,  80/255 }  -- choice validated / player moving
colors.turnRedSoft    = { 220/255,  64/255,  64/255 } -- enemy pause
colors.turnRedHard    = { 150/255,   0/255,   0/255 } -- enemy movement

colors.enemyHealth = {
    grunt = {
        [10] = {46/255, 39/255, 15/255},
        [9]  = {60/255, 50/255, 30/255},
        [8]  = {73/255, 72/255, 50/255},
        [7]  = {90/255, 85/255, 65/255},
        [6]  = {126/255, 125/255, 94/255},
        [5]  = {140/255, 135/255, 105/255},
        [4]  = {166/255, 165/255, 132/255},
        [3]  = {188/255, 187/255, 160/255},
        [2]  = {200/255, 199/255, 172/255},
        [1]  = {209/255, 208/255, 179/255},
    },
    knight = {
        [10] = {15/255, 25/255, 45/255},
        [9]  = {20/255, 35/255, 60/255},
        [8]  = {30/255, 45/255, 75/255},
        [7]  = {40/255, 60/255, 90/255},
        [6]  = {50/255, 75/255, 105/255},
        [5]  = {60/255, 90/255, 120/255},
        [4]  = {95/255, 120/255, 145/255},
        [3]  = {120/255, 145/255, 165/255},
        [2]  = {150/255, 170/255, 190/255},
        [1]  = {180/255, 200/255, 220/255},
    },
    bishop = {
        [10] = {10/255, 45/255, 15/255},
        [9]  = {15/255, 55/255, 25/255},
        [8]  = {20/255, 70/255, 35/255},
        [7]  = {30/255, 85/255, 45/255},
        [6]  = {40/255, 100/255, 55/255},
        [5]  = {50/255, 115/255, 65/255},
        [4]  = {70/255, 130/255, 80/255},
        [3]  = {90/255, 155/255, 100/255},
        [2]  = {110/255, 185/255, 125/255},
        [1]  = {140/255, 220/255, 160/255},
    },
}

colors.rarityBorder = {
    common     = {1,1,1},          -- white
    rare       = {0,0.6,1},        -- blue‑ish
    epic       = {0.6,0,1},        -- purple
    legendary  = {1,0.6,0},        -- orange
}


return colors
