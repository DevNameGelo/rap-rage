--// Rage Hub · Steal An Egg · UI placeholder (no working features)

local RageHub = loadstring(game:HttpGet(
    "https://raw.githubusercontent.com/devnamegelo/Rage-Hub/main/RageHub.lua"
))()

local Window = RageHub:CreateWindow({
    Name = "Rage Hub",
    Subtitle = "Steal An Egg",
    Theme = "Rage",
    Features = { Notifications = true },
    ConfigFolder = "RageHub/StealAnEgg",
    Splash = true,
})

--// Tabs
local AutoTab     = Window:CreateTab("Automation", "⚡")
local FilterTab   = Window:CreateTab("Filters", "🎯")
local SettingsTab = Window:CreateTab("Settings", "⚙")

--// Automation
local AutoSection = AutoTab:CreateSection("Automation")

AutoSection:CreateToggle({
    Name = "Auto Steal",
    Flag = "AutoSteal",
    Default = false,
    Description = "Placeholder",
    Callback = function(on)
        -- TODO
    end,
})

AutoSection:CreateToggle({
    Name = "Instant Steal",
    Flag = "InstantSteal",
    Default = false,
    Description = "Placeholder",
    Callback = function(on)
        -- TODO
    end,
})

AutoSection:CreateToggle({
    Name = "Auto Treadmill",
    Flag = "AutoTreadmill",
    Default = false,
    Description = "Placeholder",
    Callback = function(on)
        -- TODO
    end,
})

--// Filters
local EggSection = FilterTab:CreateSection("Eggs")

EggSection:CreateDropdown({
    Name = "Egg Rarity",
    Flag = "EggRarity",
    Multi = true,
    Options = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Cosmic", "Secret", "Eternal", "Divine" },
    Default = {},
    Description = "Placeholder",
    Callback = function(selected)
        -- TODO
    end,
})

local BiomeSection = FilterTab:CreateSection("Biomes")

BiomeSection:CreateDropdown({
    Name = "Biome Filter",
    Flag = "BiomeFilter",
    Multi = true,
    Options = {
        "Forest", "Lake", "Desert", "Jungle", "Snow", "Volcano", "Abyss Ocean",
        "Prehistoric", "Cosmic", "Cherry Blossom", "Titan Temple",
        "Angels and Demons", "Enchanted Forest",
    },
    Default = {},
    Description = "Placeholder",
    Callback = function(selected)
        -- TODO
    end,
})

--// Settings (built-in Rage Hub settings tab: theme, config, unload)
Window:CreateSettingsTab()