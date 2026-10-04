--[[
    Rage Hub - Steal An Egg v6
    AFK Auto Steal + Auto Treadmill + Instant Steal
    Fixed flight: speed 300, height 0 (no movement UI)

    v6 changelog
    - Rebuilt egg detection (live data first, DB is fallback only, exact DB match only)
    - Live value / rarity / biome / KG detection from attributes, value objects, labels
    - Fixed filter logic (AND chain, unknown data only fails when a filter needs it)
    - Best-visible-value fallback when no filter is configured
    - Signal based steal confirmation (snapshot/diff) with one controlled retry
    - Rebuilt delivery: dynamic target, dwell, VerifyDelivery, 3 staged retries, recovery
    - Treadmill state machine with verification, retry delay and cache invalidation
    - Generation tokens: toggles, respawn and cleanup really cancel running tasks
    - Mission watchdog (45s), real self-healing, respawn recovery
    - Event driven weak-key prompt cache, throttled scanning, info cache
    - Debug mode, Inspect Nearest Egg, Dump Nearby Prompts
    - New config name StealAnEggV6, single-instance cleanup
]]

----------------------------------------------------------------
-- SERVICES
----------------------------------------------------------------

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer

----------------------------------------------------------------
-- SINGLE INSTANCE
----------------------------------------------------------------

local ENV = (getgenv and getgenv()) or _G
local CLEANUP_KEY = "__RageHubStealAnEggCleanup"

for _, key in ipairs({ CLEANUP_KEY, "__RageHubStealAnEggV5Cleanup" }) do
    local fn = ENV[key]
    if type(fn) == "function" then
        local ok, err = pcall(fn)
        if not ok then
            warn("[Rage Hub] Old instance cleanup error: " .. tostring(err))
        end
        ENV[key] = nil
    end
end

----------------------------------------------------------------
-- LOAD RAGE HUB UI
----------------------------------------------------------------

local okLib, RageHub = pcall(function()
    return loadstring(game:HttpGet(
        "https://raw.githubusercontent.com/devnamegelo/Rage-Hub/main/RageHub.lua"
    ))()
end)

if not okLib or not RageHub then
    warn("[Rage Hub] Failed to load the UI library: " .. tostring(RageHub))
    return
end

----------------------------------------------------------------
-- CONSTANTS
----------------------------------------------------------------

local FLY_SPEED = 300
local FLY_HEIGHT = 0

local CONFIG_NAME = "StealAnEggV6"
local MISSION_TIMEOUT = 45        -- seconds without progress
local MISSION_HARD_CAP = 150      -- absolute mission length
local INFO_TTL = 4                -- egg info cache lifetime
local CONFIRM_TIMEOUT = 2.5       -- steal confirmation window
local TREADMILL_RADIUS = 25
local TREADMILL_RETRY = 8
local TICK_INTERVAL = 0.4

----------------------------------------------------------------
-- MODULE TABLES (kept in tables to stay under the local limit)
----------------------------------------------------------------

local UI = { T = {} }
local U, Log, Prompts, EggDB, Eggs, Filter = {}, {}, {}, {}, {}, {}
local Confirm, Carry, Flight, Delivery, Tread = {}, {}, {}, {}, {}
local Auto, Manual, Mission, Controller, Heal, Char = {}, {}, {}, {}, {}, {}

----------------------------------------------------------------
-- SETTINGS
----------------------------------------------------------------

local Cfg = {
    AutoSteal = false,
    AutoTreadmill = false,
    InstantSteal = true,
    SelfHealing = true,

    RarityMode = "Any",
    CustomRarities = {},
    SelectedBiomes = {},
    ExtraBiomeKeyword = "",

    Priority = "Highest Value",
    MinKG = 0,

    AllowUnknownRarity = false,
    OnlyStealPrompts = true,

    Debug = false,
    TrustTrigger = false,
}

----------------------------------------------------------------
-- STATE
----------------------------------------------------------------

local St = {
    Unloaded = false,

    Char = nil,
    Humanoid = nil,
    Root = nil,
    HomePos = nil,
    DiedConn = nil,

    Busy = false,
    MissionId = 0,
    Mission = nil,
    MissionStart = 0,
    Beat = 0,

    State = "IDLE",
    PauseUntil = 0,

    Carry = nil,
    NeedDelivery = false,
    DeliveryFailures = 0,
    CurrentSnap = nil,

    Tread = { On = false, Info = nil, RetryAt = 0, LastScan = 0, LastFoundPath = nil },
}

-- Generation tokens. Incrementing one invalidates every task that captured it.
local Gen = {
    Master = 0,
    Char = 0,
    AutoSteal = 0,
    Treadmill = 0,
    Instant = 0,
    Heal = 0,
    Flight = 0,
    Mission = 0,
    Controller = 0,
}

----------------------------------------------------------------
-- CONNECTIONS
----------------------------------------------------------------

local Connections = {}

local function AddConnection(Connection)
    if Connection then
        Connections[#Connections + 1] = Connection
    end
    return Connection
end

local function DisconnectAll()
    for i = #Connections, 1, -1 do
        local c = Connections[i]
        Connections[i] = nil
        if c then
            pcall(function()
                c:Disconnect()
            end)
        end
    end
end

----------------------------------------------------------------
-- RARITY / BIOME DATA
----------------------------------------------------------------

local RARITY_LIST = {
    "Common", "Uncommon", "Rare", "Epic", "Legendary",
    "Mythic", "Cosmic", "Secret", "Eternal", "Divine",
}

local RARITY_RANK = {}
local RARITY_LOOKUP = {}
for i, r in ipairs(RARITY_LIST) do
    RARITY_RANK[r] = i
    RARITY_LOOKUP[r:lower()] = r
end

local BIOME_LIST = {
    "Forest", "Lake", "Desert", "Jungle", "Snow", "Volcano",
    "Abyss Ocean", "Prehistoric", "Cosmic", "Cherry Blossom",
    "Titan Temple", "Angels & Demons", "Enchanted Forest",
}

-- Ordered: more specific names first.
local BIOME_ALIASES = {
    { Name = "Enchanted Forest", Aliases = { "enchantedforest", "enchanted" } },
    { Name = "Angels & Demons", Aliases = { "angelsanddemons", "angelsdemons", "angelvsdemons", "angelsvsdemons", "angels", "demons" } },
    { Name = "Cherry Blossom", Aliases = { "cherryblossom", "cherry" } },
    { Name = "Titan Temple", Aliases = { "titantemple", "titan" } },
    { Name = "Abyss Ocean", Aliases = { "abyssocean", "abyss" } },
    { Name = "Prehistoric", Aliases = { "prehistoric" } },
    { Name = "Volcano", Aliases = { "volcano", "lavaridge" } },
    { Name = "Jungle", Aliases = { "jungle" } },
    { Name = "Desert", Aliases = { "desert" } },
    { Name = "Snow", Aliases = { "snow", "tundra" } },
    { Name = "Lake", Aliases = { "lake" } },
    { Name = "Cosmic", Aliases = { "cosmic" } },
    { Name = "Forest", Aliases = { "forest" } },
}

----------------------------------------------------------------
-- UTILITIES
----------------------------------------------------------------

function U.Norm(Value)
    return (tostring(Value or ""):lower():gsub("[^%w]", ""))
end

local SUFFIX = {
    k = 1e3, m = 1e6, b = 1e9, t = 1e12,
    q = 1e15, qa = 1e15, qi = 1e18,
    sx = 1e21, sp = 1e24, oc = 1e27, no = 1e30, dc = 1e33,
}

function U.ParseNumber(Value)
    if type(Value) == "number" then
        return Value
    end
    if Value == nil then
        return nil
    end

    local s = tostring(Value):gsub(",", "")
    local num, suf = s:match("(%d+%.?%d*)%s*(%a*)")

    if not num then
        return nil
    end

    local n = tonumber(num)
    if not n then
        return nil
    end

    return n * (SUFFIX[suf:lower()] or 1)
end

-- "$500K/s", "1.2B /s", "25M/sec" -> number. Returns the largest match.
function U.ParseIncome(Text)
    Text = tostring(Text or "")

    local best
    for num, suf in Text:gmatch("([%d%.,]+)%s*(%a*)%s*/%s*[sS]") do
        local v = U.ParseNumber(num .. suf)
        if v and (not best or v > best) then
            best = v
        end
    end

    return best
end

function U.ParseWeight(Text)
    local num, suf = tostring(Text or ""):match(
        "([%d%.,]+)%s*([KkMmBbTt]?)%s*[Kk][Gg]"
    )

    if not num then
        return nil
    end

    return U.ParseNumber(num .. suf)
end

function U.FormatNumber(Number)
    Number = tonumber(Number) or 0

    if Number >= 1e15 then
        return string.format("%.2fQ", Number / 1e15)
    elseif Number >= 1e12 then
        return string.format("%.2fT", Number / 1e12)
    elseif Number >= 1e9 then
        return string.format("%.2fB", Number / 1e9)
    elseif Number >= 1e6 then
        return string.format("%.2fM", Number / 1e6)
    elseif Number >= 1e3 then
        return string.format("%.2fK", Number / 1e3)
    end

    return tostring(math.floor(Number + 0.5))
end

function U.Path(Object)
    local ok, path = pcall(function()
        return Object:GetFullName()
    end)
    return ok and path or tostring(Object)
end

function U.InChar(Object)
    local c = St.Char
    return c ~= nil and Object ~= nil and Object:IsDescendantOf(c)
end

function U.InBackpack(Object)
    local b = LocalPlayer:FindFirstChildOfClass("Backpack")
    return b ~= nil and Object ~= nil and Object:IsDescendantOf(b)
end

function U.PosOf(Object)
    if not Object then
        return nil
    end

    if Object:IsA("BasePart") then
        return Object.Position
    end

    if Object:IsA("Attachment") then
        return Object.WorldPosition
    end

    if Object:IsA("ProximityPrompt") then
        return U.PosOf(Object.Parent)
    end

    if Object:IsA("Model") then
        local ok, pos = pcall(function()
            return Object:GetPivot().Position
        end)
        if ok and pos then
            return pos
        end
    end

    local part = Object:FindFirstChildWhichIsA("BasePart", true)
    return part and part.Position or nil
end

function U.ToSet(Value)
    local set = {}

    if type(Value) == "table" then
        for k, v in pairs(Value) do
            if type(k) == "number" then
                set[tostring(v)] = true
            elseif v then
                set[tostring(k)] = true
            end
        end
    elseif type(Value) == "string" and Value ~= "" then
        set[Value] = true
    end

    return set
end

function U.KeyHas(Key, Words)
    for _, w in ipairs(Words) do
        if Key:find(w, 1, true) then
            return true
        end
    end
    return false
end

----------------------------------------------------------------
-- LOGGING / STATUS
----------------------------------------------------------------

Log.Last = ""
Log.LastAt = 0
Log.LastNotify = 0

function Log.Handler(Err)
    return tostring(Err) .. "\n" .. tostring(debug.traceback())
end

function Log.Add(Message, Color)
    Message = tostring(Message)

    local now = tick()
    if Message == Log.Last and now - Log.LastAt < 2 then
        return
    end
    Log.Last = Message
    Log.LastAt = now

    if UI.Log and not St.Unloaded then
        pcall(function()
            if Color then
                UI.Log:Add(Message, Color)
            else
                UI.Log:Add(Message)
            end
        end)
    end
end

function Log.Notify(Title, Content, Kind, Duration)
    if not UI.Window or St.Unloaded then
        return
    end

    pcall(function()
        UI.Window:Notify({
            Title = Title,
            Content = Content,
            Type = Kind or "info",
            Duration = Duration or 4,
        })
    end)
end

function Log.Info(Message)
    print("[Rage Hub] " .. tostring(Message))
    Log.Add(Message)
end

function Log.Warn(Message)
    warn("[Rage Hub] " .. tostring(Message))
    Log.Add("WARN: " .. tostring(Message), Color3.fromRGB(240, 190, 80))
end

function Log.Error(Message)
    Message = tostring(Message)
    warn("[Rage Hub] " .. Message)

    local first = Message:match("^[^\n]*") or Message
    Log.Add("ERROR: " .. first, Color3.fromRGB(248, 95, 115))

    if tick() - Log.LastNotify > 4 then
        Log.LastNotify = tick()
        Log.Notify("Rage Hub Error", first, "error", 4)
    end
end

function Log.Debug(Message)
    if not Cfg.Debug then
        return
    end
    print("[Rage Hub][debug] " .. tostring(Message))
    Log.Add("[dbg] " .. tostring(Message), Color3.fromRGB(140, 160, 255))
end

local STATE_TEXT = {
    IDLE = "Idle",
    RECOVERING = "Recovering",
    WAITING_FOR_EGG = "Waiting for eggs",
    TARGET_FOUND = "Egg found",
    GOING_TO_EGG = "Going to egg",
    STEALING = "Stealing",
    VERIFYING_STEAL = "Verifying steal",
    RETURNING = "Returning to spawn/base",
    DELIVERING = "Delivering",
    VERIFYING_DELIVERY = "Verifying delivery",
    SEARCHING_TREADMILL = "Searching treadmill",
    GOING_TO_TREADMILL = "Going to treadmill",
    ACTIVATING_TREADMILL = "Activating treadmill",
    ON_TREADMILL = "On treadmill - waiting for eggs",
    LEAVING_TREADMILL = "Leaving treadmill",
}

local function SetStatus(Text)
    if Text == UI.LastStatus then
        return
    end
    UI.LastStatus = Text

    if UI.Status and not St.Unloaded then
        pcall(function()
            UI.Status:Set("Status: " .. tostring(Text))
        end)
    end
end

local function SetState(State, Extra)
    St.State = State
    St.Beat = tick()

    local text = STATE_TEXT[State] or State
    if Extra then
        text = text .. " - " .. tostring(Extra)
    end
    SetStatus(text)
end

----------------------------------------------------------------
-- TASK CONTEXT (generation validation)
----------------------------------------------------------------

local function NewCtx(Need)
    local ctx = {
        Need = Need,
        Master = Gen.Master,
        Char = Gen.Char,
        Mission = Gen.Mission,
        AS = Gen.AutoSteal,
        TM = Gen.Treadmill,
        IN = Gen.Instant,
    }

    function ctx.Ok()
        if St.Unloaded
            or ctx.Master ~= Gen.Master
            or ctx.Char ~= Gen.Char
            or ctx.Mission ~= Gen.Mission then
            return false
        end

        local n = ctx.Need
        if n == "AutoSteal" then
            return Cfg.AutoSteal and ctx.AS == Gen.AutoSteal
        elseif n == "Treadmill" then
            return Cfg.AutoTreadmill and ctx.TM == Gen.Treadmill
        elseif n == "Instant" then
            return Cfg.InstantSteal and ctx.IN == Gen.Instant
        end

        return true
    end

    return ctx
end

local function WaitCtx(Ctx, Seconds)
    local untilT = tick() + Seconds

    repeat
        if Ctx and not Ctx.Ok() then
            return false
        end
        task.wait(math.clamp(untilT - tick(), 0.01, 0.1))
        St.Beat = tick()
    until tick() >= untilT

    return not Ctx or Ctx.Ok()
end

----------------------------------------------------------------
-- FALLBACK EGG DATABASE (fallback data only - live data always wins)
----------------------------------------------------------------

EggDB.List = {}
EggDB.ByName = {}
EggDB.ByPet = {}

local function AddBiome(Biome, Rows)
    for _, r in ipairs(Rows) do
        local pet = r[1]
        local entry = {
            Name = pet .. " Egg",
            Pet = pet,
            Biome = Biome,
            Rarity = r[2],
            Value = r[3] or 0,
        }
        EggDB.List[#EggDB.List + 1] = entry
        EggDB.ByName[U.Norm(entry.Name)] = entry
        EggDB.ByPet[U.Norm(pet)] = entry
    end
end

AddBiome("Forest", {
    { "Chicken", "Common", 1 }, { "Dog", "Common", 2 }, { "Bird", "Uncommon", 8 },
    { "Burrowing Owl", "Rare", 35 }, { "Raccoon", "Rare", 45 }, { "Fox", "Epic", 180 },
    { "Bear", "Epic", 240 }, { "Brr Brr Patapim", "Legendary", 1800 },
})
AddBiome("Lake", {
    { "Frog", "Common", 3 }, { "Duckling", "Common", 4 }, { "Catfish", "Uncommon", 12 },
    { "Turtle", "Rare", 60 }, { "Trulimero Trulicina", "Epic", 260 }, { "Swan", "Epic", 320 },
    { "Axolotl", "Legendary", 2800 }, { "Leviathan", "Cosmic", 220000 },
})
AddBiome("Desert", {
    { "Jerboa", "Common", 6 }, { "Fennec", "Uncommon", 18 }, { "Camel", "Rare", 75 },
    { "Tob Tobi Tob Tob", "Epic", 325 }, { "Snake", "Legendary", 3600 },
    { "Sand Spider", "Mythic", 16000 }, { "Scorpion", "Mythic", 18500 },
    { "Royal Sphinx", "Cosmic", 280000 },
})
AddBiome("Jungle", {
    { "Chimpanzee", "Rare", 90 }, { "Toucan", "Rare", 110 }, { "Crocodile", "Epic", 420 },
    { "Gorilla", "Legendary", 4800 }, { "Orangutini Ananassini", "Legendary", 5500 },
    { "Spider", "Mythic", 22000 }, { "Tiger", "Mythic", 28000 },
    { "King Snake", "Secret", 3500000 },
})
AddBiome("Snow", {
    { "Penguin", "Rare", 140 }, { "Walrus", "Epic", 600 }, { "Polar Bear", "Legendary", 7000 },
    { "Sabertooth Tiger", "Mythic", 35000 }, { "Mammoth", "Mythic", 42000 },
    { "King Mammoth", "Cosmic", 400000 }, { "Yeti", "Secret", 5000000 },
    { "Ice Dragon", "Eternal", 65000000 },
})
AddBiome("Volcano", {
    { "Lava Gecko", "Rare", 180 }, { "Lava Frog", "Epic", 850 }, { "Flaming Bull", "Legendary", 9500 },
    { "Lava Iguana", "Legendary", 11000 }, { "Chillin Chilli", "Mythic", 55000 },
    { "Cerberus", "Secret", 8000000 }, { "Phoenix", "Eternal", 85000000 },
    { "Lava Dragon", "Eternal", 100000000 },
})
AddBiome("Abyss Ocean", {
    { "Parrotfish", "Rare", 220 }, { "Swordfish", "Epic", 1100 }, { "Shark", "Legendary", 15000 },
    { "Orca", "Mythic", 80000 }, { "Whale Shark", "Cosmic", 700000 },
    { "Beluga Whale", "Cosmic", 850000 }, { "Kraken", "Secret", 15000000 },
    { "El Maja", "Eternal", 130000000 },
})
AddBiome("Prehistoric", {
    { "Dodo", "Rare", 280 }, { "Pterodactyl", "Legendary", 22000 }, { "Ankylosaurus", "Mythic", 120000 },
    { "Triceratops", "Cosmic", 1200000 }, { "Bronto", "Cosmic", 1500000 },
    { "T-Rex", "Secret", 25000000 }, { "Tralaledon", "Secret", 32000000 },
    { "Mosasaurus", "Eternal", 180000000 },
})
AddBiome("Cosmic", {
    { "Centapede", "Epic", 1500 }, { "Cosmic Gecko", "Legendary", 30000 },
    { "Cosmic Gorilla", "Mythic", 180000 }, { "La Vacca Saturno Saturnita", "Cosmic", 2200000 },
    { "Cosmic Skeleton Boss", "Secret", 45000000 }, { "Cosmic Dragon", "Secret", 60000000 },
    { "Eternal Lunar Dragon", "Eternal", 250000000 }, { "Unicorn", "Divine", 1000000000 },
})
AddBiome("Cherry Blossom", {
    { "Crane", "Epic", 4000 }, { "Salamander", "Legendary", 74000 }, { "Red Panda", "Mythic", 450000 },
    { "Snowy Owl", "Cosmic", 7500000 }, { "Koi", "Cosmic", 12000000 }, { "Stag", "Secret", 145000000 },
    { "Oni Tiger", "Eternal", 600000000 }, { "Kitsune", "Divine", 1800000000 },
})
AddBiome("Titan Temple", {
    { "Spideron", "Legendary", 95000 }, { "Crustacia", "Legendary", 130000 },
    { "Bladehide", "Mythic", 750000 }, { "Mantaris", "Cosmic", 11000000 },
    { "Rhinotaur", "Cosmic", 17500000 }, { "Mutant Shark", "Secret", 215000000 },
    { "Gorilla King", "Eternal", 880000000 }, { "Nightflame", "Divine", 3000000000 },
})
AddBiome("Angels & Demons", {
    { "Flame Sprite", "Legendary", 225000 }, { "Light Dove", "Legendary", 225000 },
    { "Toro", "Mythic", 1250000 }, { "Winged Lamb", "Mythic", 1250000 },
    { "Imp", "Cosmic", 16000000 }, { "Sacred Moth", "Cosmic", 16000000 },
    { "Demon Hound", "Cosmic", 25000000 }, { "Holy Peacock", "Cosmic", 25000000 },
    { "Gargoyle", "Secret", 225000000 }, { "Pure Jellyfish", "Secret", 225000000 },
    { "Centaur", "Secret", 350000000 }, { "RazorFang", "Secret", 350000000 },
    { "Pegasus", "Eternal", 1300000000 }, { "Skeleton Horse", "Eternal", 1300000000 },
    { "ArchAngel", "Divine", 5000000000 }, { "World Burner", "Divine", 5000000000 },
})
AddBiome("Enchanted Forest", {
    { "Prism Gecko", nil, 0 }, { "Petal Beetle", nil, 0 }, { "Astral Jackalope", nil, 0 },
})

-- Exact normalized match only. Partial matches caused wrong eggs in v5.
function EggDB.Lookup(Text)
    local n = U.Norm(Text)
    if n == "" then
        return nil
    end

    return EggDB.ByName[n] or EggDB.ByPet[n] or EggDB.ByName[n .. "egg"]
end

----------------------------------------------------------------
-- PROMPT CACHE (event driven, weak keys)
----------------------------------------------------------------

Prompts.Set = setmetatable({}, { __mode = "k" })
Prompts.Hooks = setmetatable({}, { __mode = "k" })
Prompts.Black = setmetatable({}, { __mode = "k" })
Prompts.BaseSnap = setmetatable({}, { __mode = "k" })
Prompts.Spawns = setmetatable({}, { __mode = "k" })
Prompts.LastScan = 0

local EXCLUDED_WORDS = {
    "treadmill", "deliver", "deposit", "hatch", "buy", "sell",
    "purchase", "shop", "upgrade", "rebirth", "robux", "claim",
}

function Prompts.Text(Prompt)
    return (tostring(Prompt.ActionText or "") .. " " .. tostring(Prompt.ObjectText or "")):lower()
end

function Prompts.IsSteal(Prompt)
    if not Prompt or not Prompt:IsA("ProximityPrompt") then
        return false
    end
    return Prompts.Text(Prompt):find("steal", 1, true) ~= nil
end

function Prompts.IsExcluded(Prompt)
    local text = Prompts.Text(Prompt)
    for _, w in ipairs(EXCLUDED_WORDS) do
        if text:find(w, 1, true) then
            return true
        end
    end
    return false
end

-- Cheap pre-filter. Egg context is checked later in Filter.Passes.
function Prompts.Eligible(Prompt)
    if Prompt.Enabled == false then
        return false
    end

    if Prompts.IsSteal(Prompt) then
        return true
    end

    if Cfg.OnlyStealPrompts then
        return false
    end

    return not Prompts.IsExcluded(Prompt)
end

function Prompts.List()
    local list = {}
    for p in pairs(Prompts.Set) do
        list[#list + 1] = p
    end
    return list
end

function Prompts.IsBlacklisted(Prompt)
    local untilT = Prompts.Black[Prompt]
    if not untilT then
        return false
    end
    if tick() >= untilT then
        Prompts.Black[Prompt] = nil
        return false
    end
    return true
end

function Prompts.Blacklist(Prompt, Seconds)
    if Prompt then
        Prompts.Black[Prompt] = tick() + (Seconds or 6)
    end
end

function Prompts.RestoreInstant(Prompt)
    local hook = Prompts.Hooks[Prompt]
    if not hook then
        return
    end
    Prompts.Hooks[Prompt] = nil

    pcall(function()
        hook.Connection:Disconnect()
    end)

    if Prompt and Prompt.Parent then
        pcall(function()
            if Prompt.HoldDuration == 0 then
                Prompt.HoldDuration = hook.Original
            end
        end)
    end
end

function Prompts.MakeInstant(Prompt)
    if not Cfg.InstantSteal or St.Unloaded then
        return
    end
    if not Prompt or not Prompt.Parent or not Prompts.IsSteal(Prompt) then
        return
    end

    local hook = Prompts.Hooks[Prompt]
    if hook then
        if Prompt.HoldDuration ~= 0 then
            pcall(function()
                Prompt.HoldDuration = 0
            end)
        end
        return
    end

    local original = Prompt.HoldDuration

    local connection = Prompt:GetPropertyChangedSignal("HoldDuration"):Connect(function()
        if St.Unloaded or not Cfg.InstantSteal then
            return
        end
        if Prompt.Parent and Prompt.HoldDuration ~= 0 then
            pcall(function()
                Prompt.HoldDuration = 0
            end)
        end
    end)

    Prompts.Hooks[Prompt] = { Original = original, Connection = connection }

    pcall(function()
        Prompt.HoldDuration = 0
    end)
end

function Prompts.ApplyInstantAll()
    for _, p in ipairs(Prompts.List()) do
        if p.Parent then
            Prompts.MakeInstant(p)
        end
    end
end

function Prompts.RestoreAll()
    local list = {}
    for p in pairs(Prompts.Hooks) do
        list[#list + 1] = p
    end
    for _, p in ipairs(list) do
        Prompts.RestoreInstant(p)
    end
end

function Prompts.Register(Prompt)
    if typeof(Prompt) ~= "Instance" or not Prompt:IsA("ProximityPrompt") then
        return
    end

    Prompts.Set[Prompt] = true

    if Cfg.InstantSteal then
        Prompts.MakeInstant(Prompt)
    end
end

function Prompts.Unregister(Prompt)
    Prompts.Set[Prompt] = nil
    Prompts.Black[Prompt] = nil
    Prompts.BaseSnap[Prompt] = nil
    Eggs.Cache[Prompt] = nil
    Prompts.RestoreInstant(Prompt)
end

function Prompts.Scan()
    local count = 0

    for _, d in ipairs(Workspace:GetDescendants()) do
        if St.Unloaded then
            return
        end

        if d:IsA("ProximityPrompt") then
            Prompts.Register(d)
        elseif d:IsA("SpawnLocation") then
            Prompts.Spawns[d] = true
        end

        count += 1
        if count % 600 == 0 then
            task.wait()
        end
    end

    Prompts.LastScan = tick()
end

function Prompts.Purge()
    for _, p in ipairs(Prompts.List()) do
        if not p.Parent or not p:IsDescendantOf(Workspace) then
            Prompts.Unregister(p)
        end
    end
end

-- Fires a prompt once. Does NOT imply the steal succeeded.
function Prompts.Fire(Prompt)
    if not Prompt or not Prompt.Parent then
        return false, "prompt missing"
    end

    if Cfg.InstantSteal and Prompts.IsSteal(Prompt) then
        pcall(function()
            Prompt.HoldDuration = 0
        end)
    end

    local lastErr

    if type(fireproximityprompt) == "function" then
        local ok, err = pcall(fireproximityprompt, Prompt)
        if ok then
            return true
        end
        lastErr = err
        Log.Debug("fireproximityprompt failed: " .. tostring(err))
    end

    local ok, err = pcall(function()
        Prompt:InputHoldBegin()
        task.wait((Prompt.HoldDuration or 0) + 0.1)
        Prompt:InputHoldEnd()
    end)

    if ok then
        return true
    end

    return false, tostring(err or lastErr)
end

----------------------------------------------------------------
-- EGG DETECTION
----------------------------------------------------------------

Eggs.Cache = setmetatable({}, { __mode = "k" })
Eggs.RootCache = setmetatable({}, { __mode = "k" })
Eggs.DebugSeen = setmetatable({}, { __mode = "k" })

function Eggs.OwnerMatch(Value)
    if type(Value) == "number" then
        return Value == LocalPlayer.UserId
    end
    if typeof(Value) == "Instance" then
        return Value == LocalPlayer
    end

    local s = tostring(Value or ""):lower()
    if s == "" then
        return false
    end

    return s == LocalPlayer.Name:lower()
        or s == LocalPlayer.DisplayName:lower()
        or s == tostring(LocalPlayer.UserId)
end

-- True if the instance (or one of its nearest ancestors) belongs to the local player.
function Eggs.OwnedByMe(Instance_, Depth)
    local name = U.Norm(LocalPlayer.Name)
    local display = U.Norm(LocalPlayer.DisplayName)
    local cur = Instance_

    for _ = 1, Depth or 6 do
        if not cur or cur == Workspace then
            break
        end

        if cur == St.Char then
            return true
        end

        local cn = U.Norm(cur.Name)
        if (#name >= 3 and cn:find(name, 1, true))
            or (#display >= 3 and cn:find(display, 1, true)) then
            return true
        end

        local ok, attrs = pcall(cur.GetAttributes, cur)
        if ok and attrs then
            for k, v in pairs(attrs) do
                local kl = tostring(k):lower()
                if kl:find("owner", 1, true)
                    or kl == "player" or kl == "user"
                    or kl == "userid" or kl == "username" then
                    if Eggs.OwnerMatch(v) then
                        return true
                    end
                end
            end
        end

        cur = cur.Parent
    end

    return false
end

function Eggs.CountSteal(Model)
    local n, seen = 0, 0

    for _, d in ipairs(Model:GetDescendants()) do
        seen += 1
        if d:IsA("ProximityPrompt") and Prompts.IsSteal(d) then
            n += 1
            if n > 1 then
                return n
            end
        end
        if seen > 700 then
            return 99
        end
    end

    return n
end

-- Smallest model that contains exactly one steal prompt.
function Eggs.FindRoot(Prompt)
    local cached = Eggs.RootCache[Prompt]
    if cached and cached.Parent then
        return cached
    end

    local base = Prompt.Parent
    if base and base:IsA("Attachment") then
        base = base.Parent
    end

    local model
    local cur = Prompt.Parent
    while cur and cur ~= Workspace do
        if cur:IsA("Model") then
            model = cur
            break
        end
        cur = cur.Parent
    end

    local root

    if model and Eggs.CountSteal(model) <= 1 then
        root = model
        for _ = 1, 6 do
            local parent = root.Parent
            if not parent or parent == Workspace or not parent:IsA("Model") then
                break
            end
            if Eggs.CountSteal(parent) > 1 then
                break
            end
            root = parent
        end
    else
        root = base or Prompt
    end

    Eggs.RootCache[Prompt] = root
    return root
end

function Eggs.MatchRarityWord(Text)
    local low = " " .. (tostring(Text):lower():gsub("[^%a]+", " ")) .. " "

    for _, r in ipairs(RARITY_LIST) do
        if low:find(" " .. r:lower() .. " ", 1, true) then
            return r
        end
    end

    return nil
end

function Eggs.MatchRarityValue(Value)
    if type(Value) == "number" and RARITY_LIST[Value] then
        return RARITY_LIST[Value]
    end
    return Eggs.MatchRarityWord(Value)
end

function Eggs.MatchBiome(Text)
    local n = U.Norm(Text)
    if n == "" then
        return nil
    end

    for _, biome in ipairs(BIOME_ALIASES) do
        for _, alias in ipairs(biome.Aliases) do
            if n:find(alias, 1, true) then
                return biome.Name
            end
        end
    end

    return nil
end

-- Collects attributes, value objects and label texts under the egg root.
function Eggs.Gather(Root, Prompt)
    local D = { Attrs = {}, Labels = {} }

    local function addAttrs(inst)
        local ok, attrs = pcall(inst.GetAttributes, inst)
        if ok and attrs then
            for k, v in pairs(attrs) do
                D.Attrs[#D.Attrs + 1] = { Key = tostring(k):lower(), Value = v }
            end
        end
    end

    addAttrs(Root)
    addAttrs(Prompt)
    if Prompt.Parent and Prompt.Parent ~= Root then
        addAttrs(Prompt.Parent)
    end

    local visited = 0
    for _, d in ipairs(Root:GetDescendants()) do
        visited += 1
        if visited > 300 then
            break
        end

        if d:IsA("TextLabel") or d:IsA("TextButton") or d:IsA("TextBox") then
            local text = tostring(d.Text or ""):gsub("<[^>]+>", "")
            D.Labels[#D.Labels + 1] = {
                Name = d.Name:lower(),
                Parent = d.Parent and d.Parent.Name:lower() or "",
                Text = text,
            }
        elseif d:IsA("ValueBase") then
            local ok, val = pcall(function()
                return d.Value
            end)
            if ok then
                D.Attrs[#D.Attrs + 1] = { Key = d.Name:lower(), Value = val }
            end
        end

        addAttrs(d)
    end

    return D
end

local VALUE_KEYS = { "income", "persec", "earn", "worth", "cps", "production", "value" }
local VALUE_BAD = { "price", "cost", "buy", "sell", "robux", "cooldown", "timer", "speed", "level", "luck" }
local WEIGHT_KEYS = { "weight", "kg", "mass" }
local BIOME_KEYS = { "biome", "zone", "area", "region", "habitat" }

function Eggs.BuildInfo(Prompt)
    if not Prompt or not Prompt.Parent then
        return nil
    end

    local root = Eggs.FindRoot(Prompt)
    if not root or not root.Parent then
        return nil
    end
    if U.InChar(root) then
        return nil
    end

    local D = Eggs.Gather(root, Prompt)
    local info = { Prompt = Prompt, EggRoot = root, At = tick() }

    ------------------------------------------------------------
    -- Name candidates -> fallback DB (exact match only)
    ------------------------------------------------------------
    local cands = {}

    local function addCand(s)
        s = tostring(s or "")
        if s == "" then
            return
        end
        cands[#cands + 1] = s

        local cleaned = s:gsub("%b[]", ""):gsub("%b()", ""):gsub("^%s+", ""):gsub("%s+$", "")
        if cleaned ~= "" and cleaned ~= s then
            cands[#cands + 1] = cleaned
        end
    end

    for _, a in ipairs(D.Attrs) do
        if type(a.Value) == "string" and (a.Key == "eggname" or a.Key == "egg" or a.Key == "petname"
            or a.Key == "pet" or a.Key == "itemname" or a.Key == "displayname" or a.Key == "name") then
            addCand(a.Value)
        end
    end
    for _, l in ipairs(D.Labels) do
        if l.Name:find("name", 1, true) or l.Name:find("egg", 1, true)
            or l.Name:find("title", 1, true) or l.Name:find("pet", 1, true) then
            addCand(l.Text)
        end
    end
    addCand(Prompt.ObjectText)
    addCand(root.Name)
    for _, l in ipairs(D.Labels) do
        if #l.Text <= 40 and l.Text:lower():find("egg", 1, true) then
            addCand(l.Text)
        end
    end

    local db
    for _, c in ipairs(cands) do
        db = EggDB.Lookup(c)
        if db then
            break
        end
    end

    local eggName
    if db then
        eggName = db.Name
    else
        for _, c in ipairs(cands) do
            if c:lower():find("egg", 1, true) then
                eggName = c
                break
            end
        end
        if not eggName then
            if tostring(Prompt.ObjectText or "") ~= "" then
                eggName = Prompt.ObjectText
            else
                eggName = root.Name
            end
        end
    end

    info.EggName = eggName
    info.PetName = db and db.Pet or (tostring(eggName):gsub("%s*[Ee]gg%s*$", ""))

    ------------------------------------------------------------
    -- Rarity (live -> database fallback)
    ------------------------------------------------------------
    local rarity, raritySource

    for _, a in ipairs(D.Attrs) do
        if a.Key:find("rarity", 1, true) then
            local r = Eggs.MatchRarityValue(a.Value)
            if r then
                rarity, raritySource = r, "attribute"
                break
            end
        end
    end

    if not rarity then
        for _, l in ipairs(D.Labels) do
            if l.Name:find("rarity", 1, true) or l.Parent:find("rarity", 1, true) then
                local r = Eggs.MatchRarityWord(l.Text)
                if r then
                    rarity, raritySource = r, "label"
                    break
                end
            end
        end
    end

    if not rarity then
        for _, l in ipairs(D.Labels) do
            if #l.Text <= 20 and not l.Text:find("%d") then
                local stripped = l.Text:gsub("[^%a]", ""):lower()
                if RARITY_LOOKUP[stripped] then
                    rarity, raritySource = RARITY_LOOKUP[stripped], "label"
                    break
                end
            end
        end
    end

    if not rarity then
        local cur = root.Parent
        for _ = 1, 5 do
            if not cur or cur == Workspace then
                break
            end
            local r = RARITY_LOOKUP[U.Norm(cur.Name)]
            if r then
                rarity, raritySource = r, "container"
                break
            end
            cur = cur.Parent
        end
    end

    if not rarity and db and db.Rarity then
        rarity, raritySource = db.Rarity, "fallback"
    end

    info.Rarity, info.RaritySource = rarity, raritySource

    ------------------------------------------------------------
    -- Biome (live -> database fallback)
    ------------------------------------------------------------
    local biome, biomeSource

    for _, a in ipairs(D.Attrs) do
        if U.KeyHas(a.Key, BIOME_KEYS) then
            local b = Eggs.MatchBiome(a.Value)
            if b then
                biome, biomeSource = b, "attribute"
                break
            end
        end
    end

    if not biome then
        for _, l in ipairs(D.Labels) do
            if U.KeyHas(l.Name, BIOME_KEYS) or U.KeyHas(l.Parent, BIOME_KEYS) then
                local b = Eggs.MatchBiome(l.Text)
                if b then
                    biome, biomeSource = b, "label"
                    break
                end
            end
        end
    end

    local pathParts = {}
    do
        local cur = root.Parent
        for _ = 1, 8 do
            if not cur or cur == Workspace then
                break
            end

            pathParts[#pathParts + 1] = cur.Name

            if not biome then
                local ok, attrs = pcall(cur.GetAttributes, cur)
                if ok and attrs then
                    for k, v in pairs(attrs) do
                        if U.KeyHas(tostring(k):lower(), BIOME_KEYS) then
                            local b = Eggs.MatchBiome(v)
                            if b then
                                biome, biomeSource = b, "container attribute"
                                break
                            end
                        end
                    end
                end
            end

            if not biome then
                local b = Eggs.MatchBiome(cur.Name)
                if b then
                    biome, biomeSource = b, "container"
                end
            end

            cur = cur.Parent
        end
    end

    if not biome and db and db.Biome then
        biome, biomeSource = db.Biome, "fallback"
    end

    info.Biome, info.BiomeSource = biome, biomeSource
    info.PathText = table.concat(pathParts, " ")

    ------------------------------------------------------------
    -- Value / income (live -> database fallback)
    ------------------------------------------------------------
    local value, valueSource

    for _, a in ipairs(D.Attrs) do
        if U.KeyHas(a.Key, VALUE_KEYS) and not U.KeyHas(a.Key, VALUE_BAD) then
            local v = U.ParseNumber(a.Value)
            if v and v > 0 and (not value or v > value) then
                value, valueSource = v, "attribute"
            end
        end
    end

    if not value then
        for _, l in ipairs(D.Labels) do
            local v = U.ParseIncome(l.Text)
            if v and v > 0 and (not value or v > value) then
                value, valueSource = v, "label"
            end
        end
    end

    if not value then
        for _, l in ipairs(D.Labels) do
            if (l.Name:find("income", 1, true) or l.Name:find("earn", 1, true))
                and not U.KeyHas(l.Name, VALUE_BAD) then
                local v = U.ParseNumber(l.Text)
                if v and v > 0 then
                    value, valueSource = v, "label"
                    break
                end
            end
        end
    end

    if not value and db and (db.Value or 0) > 0 then
        value, valueSource = db.Value, "fallback"
    end

    info.Value, info.ValueSource = value or 0, valueSource or "none"

    ------------------------------------------------------------
    -- Weight (nil when unknown)
    ------------------------------------------------------------
    local weight

    for _, a in ipairs(D.Attrs) do
        if U.KeyHas(a.Key, WEIGHT_KEYS) then
            local w = U.ParseNumber(a.Value)
            if w then
                weight = w
                break
            end
        end
    end

    if not weight then
        for _, l in ipairs(D.Labels) do
            local w = U.ParseWeight(l.Text)
            if w then
                weight = w
                break
            end
        end
    end

    info.Weight = weight

    ------------------------------------------------------------
    -- Misc
    ------------------------------------------------------------
    info.IsEgg = db ~= nil
        or tostring(eggName):lower():find("egg", 1, true) ~= nil
        or raritySource == "attribute" or raritySource == "label"
        or valueSource == "attribute" or valueSource == "label"

    info.Position = U.PosOf(root)
    info.PromptPosition = U.PosOf(Prompt)

    return info
end

function Eggs.Describe(Info)
    return string.format(
        "%s | Biome: %s | Rarity: %s | Value: %s/s | KG: %s",
        tostring(Info.EggName),
        tostring(Info.Biome or "Unknown"),
        tostring(Info.Rarity or "Unknown"),
        U.FormatNumber(Info.Value),
        Info.Weight and tostring(Info.Weight) or "Unknown"
    )
end

function Eggs.DebugLine(Info)
    return string.format(
        "Egg: %s | Biome: %s (%s) | Rarity: %s (%s) | Value: %s/s (%s) | KG: %s | Prompt: %s | Distance: %s | Root: %s",
        tostring(Info.EggName),
        tostring(Info.Biome or "?"), tostring(Info.BiomeSource or "-"),
        tostring(Info.Rarity or "?"), tostring(Info.RaritySource or "-"),
        U.FormatNumber(Info.Value), tostring(Info.ValueSource),
        Info.Weight and tostring(Info.Weight) or "?",
        U.Path(Info.Prompt),
        Info.Dist and string.format("%.0f", Info.Dist) or "?",
        U.Path(Info.EggRoot)
    )
end

function Eggs.GetInfo(Prompt, ForceFresh)
    local cached = Eggs.Cache[Prompt]
    if cached and not ForceFresh and tick() - cached.At < INFO_TTL then
        return cached.Info
    end

    local ok, info = pcall(Eggs.BuildInfo, Prompt)
    if not ok then
        Log.Debug("GetEggInfo error: " .. tostring(info))
        return nil
    end

    if info then
        Eggs.Cache[Prompt] = { Info = info, At = tick() }
    end

    return info
end

----------------------------------------------------------------
-- FILTERS
----------------------------------------------------------------

function Filter.RarityOk(Rarity)
    local mode = Cfg.RarityMode

    if mode == "Any" then
        return true
    end

    if mode == "Custom" then
        if next(Cfg.CustomRarities) == nil then
            return true
        end
        if not Rarity then
            return Cfg.AllowUnknownRarity
        end
        return Cfg.CustomRarities[Rarity] == true
    end

    if not Rarity then
        return Cfg.AllowUnknownRarity
    end

    return Rarity == mode
end

function Filter.BiomeOk(Info)
    if next(Cfg.SelectedBiomes) ~= nil then
        if not Info.Biome then
            return false
        end
        if not Cfg.SelectedBiomes[Info.Biome] then
            return false
        end
    end

    local keyword = U.Norm(Cfg.ExtraBiomeKeyword)
    if keyword ~= "" then
        local hay = U.Norm(
            tostring(Info.Biome or "") .. " "
            .. tostring(Info.EggName or "") .. " "
            .. tostring(Info.PetName or "") .. " "
            .. tostring(Info.PathText or "")
        )
        if not hay:find(keyword, 1, true) then
            return false
        end
    end

    return true
end

-- Returns ok, rejectReason
function Filter.Passes(Info)
    if not Info or not Info.Prompt or not Info.Prompt.Parent then
        return false, "prompt missing"
    end

    local prompt = Info.Prompt

    if prompt.Enabled == false then
        return false, "prompt disabled"
    end

    if Eggs.OwnedByMe(Info.EggRoot, 6) then
        return false, "already owned"
    end

    local isSteal = Prompts.IsSteal(prompt)

    if not isSteal then
        if Cfg.OnlyStealPrompts then
            return false, "not a steal prompt"
        end
        if Prompts.IsExcluded(prompt) or not Info.IsEgg then
            return false, "no egg context"
        end
    end

    if not Filter.RarityOk(Info.Rarity) then
        return false, "rarity filter"
    end

    if not Filter.BiomeOk(Info) then
        return false, "biome filter"
    end

    if Cfg.MinKG > 0 then
        if Info.Weight == nil then
            return false, "weight unknown (Minimum KG is set)"
        end
        if Info.Weight < Cfg.MinKG then
            return false, "below minimum KG"
        end
    end

    return true
end

----------------------------------------------------------------
-- EGG COLLECTION / PICKING
----------------------------------------------------------------

-- Yields briefly while refreshing. Call from a task, never from an event.
function Eggs.Collect(MaxFresh)
    local results = {}
    local stats = { Total = 0, Passed = 0, Reasons = {} }
    local fresh = 0
    local ref = St.Root and St.Root.Position or Vector3.zero

    for _, prompt in ipairs(Prompts.List()) do
        if St.Unloaded then
            break
        end

        if not prompt.Parent or not prompt:IsDescendantOf(Workspace) then
            Prompts.Unregister(prompt)
        elseif Prompts.Eligible(prompt) and not Prompts.IsBlacklisted(prompt) then
            stats.Total += 1

            local cached = Eggs.Cache[prompt]
            local info

            if cached and tick() - cached.At < INFO_TTL then
                info = cached.Info
            elseif fresh < (MaxFresh or 10) then
                info = Eggs.GetInfo(prompt, true)
                fresh += 1
                if fresh % 8 == 0 then
                    task.wait()
                end
            elseif cached then
                info = cached.Info
            end

            if info then
                local pos = U.PosOf(prompt) or info.PromptPosition
                info.PromptPosition = pos
                info.Dist = pos and (pos - ref).Magnitude or math.huge

                if Cfg.Debug then
                    local fingerprint = Eggs.DebugLine(info)
                    if Eggs.DebugSeen[prompt] ~= fingerprint then
                        Eggs.DebugSeen[prompt] = fingerprint
                        Log.Debug(fingerprint)
                    end
                end

                local ok, why = Filter.Passes(info)
                if ok then
                    stats.Passed += 1
                    results[#results + 1] = info
                else
                    stats.Reasons[why] = (stats.Reasons[why] or 0) + 1
                end
            end
        end
    end

    return results, stats
end

local function CompareKeys(Pairs)
    for _, p in ipairs(Pairs) do
        local a, b, descending = p[1], p[2], p[3]
        if a ~= b then
            if descending then
                return a > b
            end
            return a < b
        end
    end
    return false
end

function Eggs.Better(A, B)
    local av, bv = tonumber(A.Value) or 0, tonumber(B.Value) or 0
    local ar, br = RARITY_RANK[A.Rarity] or 0, RARITY_RANK[B.Rarity] or 0
    local aw, bw = tonumber(A.Weight) or 0, tonumber(B.Weight) or 0
    local ad, bd = A.Dist or math.huge, B.Dist or math.huge

    local p = Cfg.Priority

    if p == "Nearest" then
        return CompareKeys({ { ad, bd, false }, { av, bv, true }, { ar, br, true } })
    elseif p == "Highest KG" then
        return CompareKeys({ { aw, bw, true }, { av, bv, true }, { ar, br, true }, { ad, bd, false } })
    elseif p == "Highest Rarity" then
        return CompareKeys({ { ar, br, true }, { av, bv, true }, { aw, bw, true }, { ad, bd, false } })
    end

    -- Highest Value: live income, then DB income fallback (already merged in Value),
    -- then rarity, weight and distance.
    return CompareKeys({ { av, bv, true }, { ar, br, true }, { aw, bw, true }, { ad, bd, false } })
end

function Eggs.PickBest(MaxFresh)
    local list = Eggs.Collect(MaxFresh)

    if #list == 0 then
        return nil
    end

    table.sort(list, Eggs.Better)
    return list[1]
end

----------------------------------------------------------------
-- STEAL CONFIRMATION (snapshot / diff)
----------------------------------------------------------------

local HINT_KEYS = { "egg", "carry", "hold", "stolen", "steal", "inventory", "backpack", "equipped" }

local function SnapAttrs(Inst)
    local out = {}
    if Inst then
        local ok, attrs = pcall(Inst.GetAttributes, Inst)
        if ok and attrs then
            for k, v in pairs(attrs) do
                out[tostring(k)] = v
            end
        end
    end
    return out
end

local function IsEggish(Name, PetName)
    local low = tostring(Name):lower()
    if low:find("egg", 1, true) then
        return true
    end

    local pet = U.Norm(PetName or "")
    if #pet >= 4 and U.Norm(Name):find(pet, 1, true) then
        return true
    end

    return false
end

function Confirm.Snapshot(Prompt, Info)
    local char = St.Char
    local hum = St.Humanoid

    local s = {
        At = tick(),
        Prompt = Prompt,
        Chars = {},
        Pack = {},
        Triggered = false,
        Late = false,
        PromptParent = Prompt and Prompt.Parent or nil,
        Enabled = Prompt and Prompt.Enabled,
        Action = Prompt and tostring(Prompt.ActionText) or "",
        WalkSpeed = hum and hum.WalkSpeed or 0,
        Attrs = {
            { Inst = LocalPlayer, Map = SnapAttrs(LocalPlayer) },
            { Inst = char, Map = SnapAttrs(char) },
            { Inst = hum, Map = SnapAttrs(hum) },
        },
    }

    if char then
        for _, d in ipairs(char:GetDescendants()) do
            s.Chars[d] = true
        end
    end

    local pack = LocalPlayer:FindFirstChildOfClass("Backpack")
    if pack then
        for _, d in ipairs(pack:GetChildren()) do
            s.Pack[d] = true
        end
    end

    local root = Info and Info.EggRoot or (Prompt and Eggs.FindRoot(Prompt))
    s.EggRoot = root
    s.EggRootParent = root and root.Parent or nil
    s.PetName = Info and Info.PetName or nil

    return s
end

function Confirm.Evaluate(S)
    local R = {
        Strong = 0,
        EggSide = false,
        PlayerSide = false,
        Reasons = {},
        Objects = {},
        AttrRecs = {},
        Root = nil,
        Confirmed = false,
    }

    local function reason(t)
        R.Reasons[#R.Reasons + 1] = t
    end

    local char = St.Char
    local knownChars = S.Late and {} or S.Chars
    local knownPack = S.Late and {} or S.Pack

    -- New objects on the character
    if char and char.Parent then
        for _, d in ipairs(char:GetDescendants()) do
            if not knownChars[d] and (d:IsA("Tool") or d:IsA("Model") or d:IsA("BasePart")) then
                if IsEggish(d.Name, S.PetName) then
                    R.Strong += 1
                    R.Objects[d] = true
                    reason("egg object attached to character: " .. d.Name)
                elseif d:IsA("Tool") or d:IsA("Model") then
                    R.PlayerSide = true
                    R.Objects[d] = true
                    reason("new object on character: " .. d.Name)
                end
            end
        end
    end

    -- New tools in the backpack
    local pack = LocalPlayer:FindFirstChildOfClass("Backpack")
    if pack then
        for _, d in ipairs(pack:GetChildren()) do
            if not knownPack[d] then
                if IsEggish(d.Name, S.PetName) then
                    R.Strong += 1
                    R.Objects[d] = true
                    reason("egg tool in backpack: " .. d.Name)
                else
                    R.PlayerSide = true
                    R.Objects[d] = true
                    reason("new backpack item: " .. d.Name)
                end
            end
        end
    end

    -- The egg root itself ended up on us
    if S.EggRoot and S.EggRoot.Parent and char and S.EggRoot:IsDescendantOf(char) then
        R.Strong += 1
        R.Root = S.EggRoot
        reason("egg model moved into character")
    end

    -- Attribute changes on player / character / humanoid
    for _, rec in ipairs(S.Attrs) do
        if rec.Inst then
            local now = SnapAttrs(rec.Inst)
            for k, v in pairs(now) do
                if rec.Map[k] ~= v then
                    local kl = tostring(k):lower()
                    if U.KeyHas(kl, HINT_KEYS) then
                        R.Strong += 1
                        R.AttrRecs[#R.AttrRecs + 1] = { Inst = rec.Inst, Key = k, Value = v, Old = rec.Map[k] }
                        reason("attribute '" .. tostring(k) .. "' changed")
                    else
                        R.PlayerSide = true
                        R.AttrRecs[#R.AttrRecs + 1] = { Inst = rec.Inst, Key = k, Value = v, Old = rec.Map[k] }
                        reason("attribute '" .. tostring(k) .. "' changed")
                    end
                end
            end
        end
    end

    -- Walk speed change (carrying often slows the player)
    if St.Humanoid and S.WalkSpeed > 0 and math.abs(St.Humanoid.WalkSpeed - S.WalkSpeed) > 0.5 then
        R.PlayerSide = true
        reason("walk speed changed")
    end

    -- Egg-side signals (counted as ONE correlated signal)
    local prompt = S.Prompt
    if prompt then
        if not prompt.Parent or not prompt:IsDescendantOf(Workspace) then
            R.EggSide = true
            reason("steal prompt removed")
        elseif S.Enabled ~= false and prompt.Enabled == false then
            R.EggSide = true
            reason("steal prompt disabled")
        elseif S.Action:lower():find("steal", 1, true) and not Prompts.IsSteal(prompt) then
            R.EggSide = true
            reason("prompt text no longer says steal")
        end
    end
    if S.EggRoot and S.EggRootParent and S.EggRoot.Parent ~= S.EggRootParent then
        R.EggSide = true
        reason("egg moved/removed from its slot")
    end

    local confirmed = R.Strong > 0 or (R.EggSide and R.PlayerSide)

    if not confirmed and S.Triggered and Cfg.TrustTrigger then
        confirmed = true
        reason("trusting prompt trigger (Trust Prompt Trigger is on)")
    end

    R.Confirmed = confirmed
    return R
end

-- Returns last evaluation, or nil when the context was cancelled.
function Confirm.Wait(Ctx, Snap, Timeout)
    local untilT = tick() + Timeout
    local R

    repeat
        if not Ctx.Ok() then
            return nil
        end

        R = Confirm.Evaluate(Snap)
        if R.Confirmed then
            return R
        end

        task.wait(0.12)
        St.Beat = tick()
    until tick() >= untilT

    return Confirm.Evaluate(Snap)
end

-- Remember what "carrying" looks like so delivery can verify it later.
function Confirm.Record(Snap, R)
    St.Carry = {
        Baseline = Snap,
        Objects = R.Objects,
        AttrRecs = R.AttrRecs,
        Root = R.Root,
        EggRoot = Snap.EggRoot,
        PetName = Snap.PetName,
        Observable = next(R.Objects) ~= nil or #R.AttrRecs > 0 or R.Root ~= nil,
        At = tick(),
    }
end

----------------------------------------------------------------
-- CARRY STATE
----------------------------------------------------------------

function Carry.IsCarrying()
    local c = St.Carry
    if not c then
        return false
    end

    for obj in pairs(c.Objects) do
        if obj.Parent and (U.InChar(obj) or U.InBackpack(obj)) then
            return true
        end
    end

    for _, r in ipairs(c.AttrRecs) do
        local ok, cur = pcall(r.Inst.GetAttribute, r.Inst, r.Key)
        if ok and cur == r.Value and cur ~= r.Old then
            return true
        end
    end

    if c.Root and c.Root.Parent and U.InChar(c.Root) then
        return true
    end

    local base = c.Baseline
    if base and St.Char then
        for _, d in ipairs(St.Char:GetDescendants()) do
            if not base.Chars[d] and (d:IsA("Tool") or d:IsA("Model") or d:IsA("BasePart"))
                and IsEggish(d.Name, c.PetName) then
                return true
            end
        end

        local pack = LocalPlayer:FindFirstChildOfClass("Backpack")
        if pack then
            for _, d in ipairs(pack:GetChildren()) do
                if not base.Pack[d] and IsEggish(d.Name, c.PetName) then
                    return true
                end
            end
        end
    end

    return false
end

----------------------------------------------------------------
-- CHARACTER
----------------------------------------------------------------

function Char.Ready()
    local root, hum = St.Root, St.Humanoid
    return root ~= nil and root.Parent ~= nil and hum ~= nil and hum.Health > 0
end

local function ResetMissionState()
    Gen.Char += 1
    Gen.Flight += 1
    Gen.Mission += 1
    St.MissionId += 1

    St.Busy = false
    St.Mission = nil
    St.MissionStart = 0
    St.Carry = nil
    St.NeedDelivery = false
    St.CurrentSnap = nil

    St.Tread.On = false
    St.Tread.RetryAt = 0
end

function Char.Setup(Character, First)
    if St.Unloaded then
        return
    end

    ResetMissionState()

    St.Root = nil
    St.Humanoid = nil
    St.Char = Character

    if St.DiedConn then
        pcall(function()
            St.DiedConn:Disconnect()
        end)
        St.DiedConn = nil
    end

    local hum = Character:WaitForChild("Humanoid", 10)
    local root = Character:WaitForChild("HumanoidRootPart", 10)

    if St.Unloaded or St.Char ~= Character then
        return
    end

    St.Humanoid = hum
    St.Root = root

    if hum then
        St.DiedConn = hum.Died:Connect(function()
            if St.Char == Character and not St.Unloaded then
                ResetMissionState()
                Log.Info("Character died - state reset, waiting for respawn.")
            end
        end)
    end

    if not root then
        Log.Error("HumanoidRootPart was not found.")
        return
    end

    if not First then
        task.wait(0.4)
        if St.Char == Character and root.Parent then
            St.HomePos = root.Position
        end
    end

    SetState("IDLE")

    if Cfg.AutoSteal or Cfg.AutoTreadmill then
        Log.Info("Respawn recovered - automation resumed.")
    else
        Log.Info("Character ready.")
    end
end

----------------------------------------------------------------
-- FLIGHT (fixed speed 300 / height 0)
----------------------------------------------------------------

function Flight.Stop()
    local root = St.Root
    if root and root.Parent then
        pcall(function()
            root.AssemblyLinearVelocity = Vector3.zero
            root.AssemblyAngularVelocity = Vector3.zero
        end)
    end
end

function Flight.Cancel()
    Gen.Flight += 1
    Flight.Stop()
end

-- Target: Vector3 or function returning Vector3 (nil = target lost).
-- Returns ok, reason
function Flight.To(Target, Ctx, Opts)
    Opts = Opts or {}

    if not Char.Ready() then
        return false, "character unavailable"
    end

    Gen.Flight += 1
    local id = Gen.Flight
    local deadline = tick() + (Opts.Timeout or 25)
    local arrive = Opts.Arrive or 1.5
    local lastInterrupt = tick()

    while true do
        local dt = math.min(RunService.Heartbeat:Wait(), 0.1)
        St.Beat = tick()

        if id ~= Gen.Flight then
            return false, "flight superseded"
        end
        if Ctx and not Ctx.Ok() then
            Flight.Stop()
            return false, "cancelled"
        end
        if not Char.Ready() then
            return false, "character unavailable"
        end

        local root = St.Root

        local dest = Target
        if type(Target) == "function" then
            dest = Target()
        end
        if typeof(dest) ~= "Vector3" then
            Flight.Stop()
            return false, "target position lost"
        end
        dest = dest + Vector3.new(0, FLY_HEIGHT, 0)

        local cur = root.Position
        local diff = dest - cur
        local dist = diff.Magnitude

        if dist <= arrive then
            Flight.Stop()
            return true
        end

        if tick() > deadline then
            Flight.Stop()
            return false, "flight timed out"
        end

        if Opts.Interrupt and tick() - lastInterrupt >= 1 then
            lastInterrupt = tick()
            local okI, hit = pcall(Opts.Interrupt)
            if okI and hit then
                Flight.Stop()
                return false, "interrupted"
            end
        end

        local step = FLY_SPEED * dt
        local nextPos = (step >= dist) and dest or (cur + diff.Unit * step)

        root.CFrame = CFrame.new(nextPos) * (root.CFrame - root.CFrame.Position)
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
    end
end

----------------------------------------------------------------
-- MISSION LOCK
----------------------------------------------------------------

function Mission.Begin(Name, Need)
    if St.Busy then
        return nil
    end

    St.Busy = true
    St.MissionId += 1
    St.Mission = Name
    St.MissionStart = tick()
    St.Beat = tick()

    local ctx = NewCtx(Need)
    ctx.Id = St.MissionId
    ctx.Name = Name

    return ctx
end

function Mission.End(Ctx)
    if Ctx and Ctx.Id == St.MissionId then
        St.Busy = false
        St.Mission = nil
        St.MissionStart = 0
        Flight.Stop()
    end
end

function Mission.Abort()
    Gen.Mission += 1
    St.MissionId += 1
    St.Busy = false
    St.Mission = nil
    St.MissionStart = 0
    Flight.Cancel()
end

-- Runs Fn(ctx, ...) under the mission lock with protected error logging.
function Mission.Run(Name, Need, Fn, ...)
    local ctx = Mission.Begin(Name, Need)
    if not ctx then
        return false
    end

    local ok, a, b = xpcall(Fn, Log.Handler, ctx, ...)
    Mission.End(ctx)

    if not ok then
        Log.Error(Name .. " crashed: " .. tostring(a))
        Flight.Cancel()
        return false
    end

    return true, a, b
end

----------------------------------------------------------------
-- DELIVERY
----------------------------------------------------------------

local DELIVERY_WORDS = {
    { "deliver", 100 }, { "deposit", 90 }, { "secure", 80 }, { "store", 70 },
    { "drop", 60 }, { "place", 50 }, { "return", 40 }, { "submit", 40 },
}
local DELIVERY_BAD = {
    "steal", "treadmill", "hatch", "buy", "purchase", "sell",
    "shop", "upgrade", "rebirth", "robux", "unlock",
}
local ZONE_HINTS = { "safe", "zone", "deliver", "deposit", "base", "plot", "pad", "spawn" }

Delivery.Cache = nil

function Delivery.Home()
    if St.HomePos then
        return St.HomePos
    end

    local rl = LocalPlayer.RespawnLocation
    if rl and rl.Parent then
        return U.PosOf(rl)
    end

    local ref = St.Root and St.Root.Position
    local best, bestDist

    for s in pairs(Prompts.Spawns) do
        if s.Parent then
            local p = U.PosOf(s)
            if p then
                local d = ref and (p - ref).Magnitude or 0
                if not bestDist or d < bestDist then
                    best, bestDist = p, d
                end
            end
        end
    end

    return best or ref
end

function Delivery.FromPrompt(Home)
    local best

    for _, p in ipairs(Prompts.List()) do
        if p.Parent and p.Enabled ~= false and not Prompts.IsSteal(p) then
            local text = Prompts.Text(p)
            local score = 0

            for _, w in ipairs(DELIVERY_WORDS) do
                if text:find(w[1], 1, true) then
                    score = math.max(score, w[2])
                end
            end

            if score > 0 then
                local bad = false
                for _, w in ipairs(DELIVERY_BAD) do
                    if text:find(w, 1, true) then
                        bad = true
                        break
                    end
                end

                if not bad then
                    local pos = U.PosOf(p)
                    if pos then
                        local near = Home and (pos - Home).Magnitude <= 150
                        local mine = Eggs.OwnedByMe(p, 6)

                        -- Context check: it must be near our spawn or belong to us.
                        if near or mine then
                            if near then score += 10 end
                            if mine then score += 25 end
                            if text:find("egg", 1, true) then score += 10 end

                            local d = Home and (pos - Home).Magnitude or 0
                            if not best or score > best.Score
                                or (score == best.Score and d < best.D) then
                                best = {
                                    Kind = "prompt",
                                    Label = "delivery prompt (" .. tostring(p.ActionText ~= "" and p.ActionText or p.Name) .. ")",
                                    Prompt = p,
                                    Score = score,
                                    D = d,
                                }
                            end
                        end
                    end
                end
            end
        end
    end

    return best
end

function Delivery.FromBase(Home)
    local base

    for _, top in ipairs(Workspace:GetChildren()) do
        if top ~= St.Char and not top:IsA("Terrain") and not top:IsA("Camera") then
            if Eggs.OwnedByMe(top, 1) then
                base = top
                break
            end

            if top:IsA("Folder") or top:IsA("Model") then
                for _, sub in ipairs(top:GetChildren()) do
                    if sub ~= St.Char and Eggs.OwnedByMe(sub, 1) then
                        base = sub
                        break
                    end
                end
                if base then
                    break
                end
            end
        end
    end

    if not base then
        return nil
    end

    local pivot = U.PosOf(base)
    if Home and pivot and (pivot - Home).Magnitude > 400 then
        return nil
    end

    local zone, zoneDist
    local seen = 0
    for _, d in ipairs(base:GetDescendants()) do
        seen += 1
        if seen > 800 then
            break
        end
        if d:IsA("BasePart") and U.KeyHas(d.Name:lower(), ZONE_HINTS) then
            local dd = Home and (d.Position - Home).Magnitude or 0
            if not zoneDist or dd < zoneDist then
                zone, zoneDist = d, dd
            end
        end
    end

    return {
        Kind = "base",
        Label = "your base (" .. base.Name .. ")",
        Part = zone,
        Fixed = pivot,
    }
end

function Delivery.FromSpawn(Home)
    local best, bestDist

    for s in pairs(Prompts.Spawns) do
        if s.Parent then
            local p = U.PosOf(s)
            if p then
                local d = Home and (p - Home).Magnitude or 0
                if (not Home or d <= 120) and (not bestDist or d < bestDist) then
                    best, bestDist = s, d
                end
            end
        end
    end

    if best then
        return { Kind = "spawn", Label = "spawn pad (" .. best.Name .. ")", Part = best }
    end

    return nil
end

function Delivery.Valid(T)
    if not T then
        return false
    end
    if T.Prompt and not T.Prompt.Parent then
        return false
    end
    if T.Part and not T.Part.Parent then
        return false
    end
    return true
end

function Delivery.Resolve(Force)
    if not Force and Delivery.Cache and tick() - Delivery.Cache.At < 15 and Delivery.Valid(Delivery.Cache) then
        return Delivery.Cache
    end

    local home = Delivery.Home()
    local T = Delivery.FromPrompt(home)

    if not T then
        local base = Delivery.FromBase(home)
        local spawn = Delivery.FromSpawn(home)

        if base and base.Part then
            T = base
        elseif spawn then
            T = spawn
        elseif base then
            T = base
        elseif home then
            T = { Kind = "home", Label = "spawn position", Fixed = home }
        end
    end

    if T then
        T.At = tick()
    end
    Delivery.Cache = T

    return T
end

function Delivery.TargetPos(T)
    if not T then
        return nil
    end

    if T.Kind == "prompt" then
        if not T.Prompt.Parent then
            return nil
        end
        return U.PosOf(T.Prompt)
    end

    if T.Part then
        if not T.Part.Parent then
            return nil
        end
        return T.Part.Position + Vector3.new(0, T.Part.Size.Y / 2 + 3, 0)
    end

    return T.Fixed
end

function Delivery.Radius(T)
    if T and T.Part then
        local s = T.Part.Size
        return math.clamp(math.min(s.X, s.Z) / 2 - 1, 1.5, 5)
    end
    return 4
end

-- "confirmed" | "carrying" | "unknown"
function Delivery.Check()
    local c = St.Carry
    if not c then
        return "unknown"
    end

    if Carry.IsCarrying() then
        return "carrying"
    end

    if c.Observable then
        return "confirmed"
    end

    if c.EggRoot and c.EggRoot.Parent and Eggs.OwnedByMe(c.EggRoot, 6) then
        return "confirmed"
    end

    return "unknown"
end

-- Polls Check() for Seconds. nil = cancelled.
function Delivery.Settle(Ctx, Seconds)
    local untilT = tick() + Seconds
    local last = "unknown"

    repeat
        if not Ctx.Ok() then
            return nil
        end

        last = Delivery.Check()
        if last == "confirmed" then
            return last
        end

        task.wait(0.15)
        St.Beat = tick()
    until tick() >= untilT

    return last
end

-- Returns "confirmed" | "unknown" | "failed", reason
function Delivery.Run(Ctx)
    local T = Delivery.Resolve(false)
    if not T then
        return "failed", "no delivery point, base or spawn could be located"
    end

    SetState("RETURNING")
    Log.Info("Returning to " .. T.Label)

    local function fly(Target)
        return Flight.To(function()
            return Delivery.TargetPos(Target)
        end, Ctx, { Timeout = 30, Arrive = 1.5 })
    end

    local ok, why = fly(T)
    if not ok then
        return "failed", "flight to delivery point failed (" .. tostring(why) .. ")"
    end

    local promptsFired = 0
    local function usePrompt(Target)
        if Target.Prompt and Target.Prompt.Parent and promptsFired < 2 then
            promptsFired += 1
            Log.Info("Using delivery prompt: " .. tostring(Target.Label))

            local fok, ferr = Prompts.Fire(Target.Prompt)
            if not fok then
                Log.Warn("Delivery prompt could not be fired: " .. tostring(ferr))
            end
        end
    end

    SetState("DELIVERING")
    usePrompt(T)

    SetState("VERIFYING_DELIVERY")
    local s = Delivery.Settle(Ctx, 1.8)
    if s == nil then
        return "failed", "cancelled"
    end
    if s ~= "carrying" then
        return s
    end

    ----------------------------------------------------------------
    -- Retry 1: move slightly around the valid delivery area
    ----------------------------------------------------------------
    Log.Warn("Delivery not confirmed - retry 1/3: moving around the delivery area")

    local center = Delivery.TargetPos(T)
    local r = Delivery.Radius(T)

    if center then
        local offsets = {
            Vector3.new(r, 0, 0), Vector3.new(-r, 0, 0),
            Vector3.new(0, 0, r), Vector3.new(0, 0, -r),
        }

        for _, o in ipairs(offsets) do
            local fok = Flight.To(center + o, Ctx, { Timeout = 8, Arrive = 1 })
            if not Ctx.Ok() then
                return "failed", "cancelled"
            end
            if fok then
                s = Delivery.Settle(Ctx, 0.5)
                if s == nil then
                    return "failed", "cancelled"
                end
                if s ~= "carrying" then
                    return s
                end
            end
        end
    end

    ----------------------------------------------------------------
    -- Retry 2: re-detect the actual delivery point
    ----------------------------------------------------------------
    Delivery.Cache = nil
    T = Delivery.Resolve(true)

    if T then
        Log.Warn("Delivery not confirmed - retry 2/3: re-detected " .. T.Label)

        SetState("RETURNING")
        local fok, fwhy = fly(T)
        if not fok then
            if not Ctx.Ok() then
                return "failed", "cancelled"
            end
            Log.Warn("Retry 2 flight problem: " .. tostring(fwhy))
        else
            SetState("DELIVERING")
            usePrompt(T)

            SetState("VERIFYING_DELIVERY")
            s = Delivery.Settle(Ctx, 1.8)
            if s == nil then
                return "failed", "cancelled"
            end
            if s ~= "carrying" then
                return s
            end
        end
    end

    ----------------------------------------------------------------
    -- Retry 3: wait for server synchronization
    ----------------------------------------------------------------
    Log.Warn("Delivery not confirmed - retry 3/3: waiting for server synchronization")

    SetState("VERIFYING_DELIVERY")
    s = Delivery.Settle(Ctx, 3)
    if s == nil then
        return "failed", "cancelled"
    end
    if s ~= "carrying" then
        return s
    end

    return "failed", "carried egg still detected after 3 verification attempts"
end

-- Logs the outcome, updates counters and starts recovery on failure.
-- Returns true when the flow may continue.
function Delivery.Report(Ctx, Status, Why)
    if Status == "confirmed" then
        Log.Info("Delivery confirmed")
        St.DeliveryFailures = 0
        St.NeedDelivery = false
        St.Carry = nil
        return true
    end

    if Status == "unknown" then
        Log.Warn("Delivery unverified: no carried-egg signal could be observed, so delivery cannot be proven. Continuing.")
        St.NeedDelivery = false
        St.Carry = nil
        return true
    end

    if Why == "cancelled" then
        return false, "cancelled"
    end

    St.DeliveryFailures += 1
    Log.Error("Delivery failed: " .. tostring(Why))

    SetState("RECOVERING")
    Log.Info("Recovery started")

    Flight.Stop()
    local carrying = Carry.IsCarrying()
    St.NeedDelivery = carrying

    WaitCtx(Ctx, 2)

    if St.DeliveryFailures >= 3 then
        St.NeedDelivery = false
        Cfg.AutoSteal = false
        Gen.AutoSteal += 1

        pcall(function()
            if UI.T.AutoSteal then
                UI.T.AutoSteal:Set(false)
            end
        end)

        Log.Error("Auto Steal disabled after 3 consecutive delivery failures. Check the delivery area and re-enable it.")
    end

    Log.Info("Recovery complete")
    return false, "delivery failed"
end

----------------------------------------------------------------
-- TREADMILL
----------------------------------------------------------------

function Tread.Remote()
    local packages = ReplicatedStorage:FindFirstChild("Packages")
    local networking = packages and packages:FindFirstChild("Networking")
    local direct = networking and networking:FindFirstChild("RF/Treadmill/AskWearStill")

    if direct and direct:IsA("RemoteFunction") then
        return direct
    end

    local recursive = ReplicatedStorage:FindFirstChild("RF/Treadmill/AskWearStill", true)
    if recursive and recursive:IsA("RemoteFunction") then
        return recursive
    end

    return nil
end

function Tread.Pos(Info)
    if not Info or not Info.Object or not Info.Object.Parent then
        return nil
    end

    local pos = U.PosOf(Info.Object)
    if not pos then
        return nil
    end

    -- Stand slightly above model/part centres so we do not clip into the belt.
    if not Info.Object:IsA("ProximityPrompt") then
        pos += Vector3.new(0, 3, 0)
    end

    return pos
end

function Tread.Invalidate()
    St.Tread.Info = nil
    St.Tread.LastScan = 0
end

function Tread.Find(Ctx)
    local cur = St.Tread.Info
    if cur and cur.Object and cur.Object.Parent and cur.Object:IsDescendantOf(Workspace) then
        return cur
    end

    if tick() - St.Tread.LastScan < 4 then
        return nil
    end
    St.Tread.LastScan = tick()
    St.Tread.Info = nil

    local origin = Delivery.Home() or (St.Root and St.Root.Position) or Vector3.zero
    local best, bestScore

    local function consider(Obj, Score)
        local pos = U.PosOf(Obj)
        if not pos then
            return
        end
        local s = Score - (pos - origin).Magnitude * 0.01
        if not best or s > bestScore then
            best, bestScore = Obj, s
        end
    end

    for _, p in ipairs(Prompts.List()) do
        if p.Parent and Prompts.Text(p):find("treadmill", 1, true) then
            consider(p, 200)
        end
    end

    local n = 0
    for _, d in ipairs(Workspace:GetDescendants()) do
        n += 1
        if (d:IsA("Model") or d:IsA("BasePart") or d:IsA("Folder"))
            and d.Name:lower():find("treadmill", 1, true)
            and not U.InChar(d) then
            consider(d, d:IsA("Model") and 150 or 100)
        end

        if n % 1500 == 0 then
            task.wait()
            if Ctx and not Ctx.Ok() then
                return nil
            end
        end
    end

    if not best then
        return nil
    end

    local prompt
    if best:IsA("ProximityPrompt") then
        prompt = best
    else
        prompt = best:FindFirstChildWhichIsA("ProximityPrompt", true)
    end

    St.Tread.Info = { Object = best, Prompt = prompt }

    local path = U.Path(best)
    if St.Tread.LastFoundPath ~= path then
        St.Tread.LastFoundPath = path
        Log.Info("Treadmill found: " .. path)
    end

    return St.Tread.Info
end

-- "yes" | "no" | "unknown"
function Tread.Probe()
    local info = St.Tread.Info
    local root = St.Root

    if not info or not info.Object or not info.Object.Parent or not root or not root.Parent then
        return "no"
    end

    local pos = U.PosOf(info.Object)
    if not pos or (root.Position - pos).Magnitude > TREADMILL_RADIUS then
        return "no"
    end

    local answer = "unknown"
    local words = { "treadmill", "running", "wearstill", "still" }

    for _, inst in ipairs({ St.Char, St.Humanoid, LocalPlayer }) do
        if inst then
            local ok, attrs = pcall(inst.GetAttributes, inst)
            if ok and attrs then
                for k, v in pairs(attrs) do
                    if U.KeyHas(tostring(k):lower(), words) then
                        if v == true or (type(v) == "number" and v ~= 0) or (type(v) == "string" and v ~= "") then
                            return "yes"
                        end
                        answer = "no"
                    end
                end
            end
        end
    end

    local hum = St.Humanoid
    if hum and hum.SeatPart then
        local seat = hum.SeatPart
        if seat.Parent and (seat.Name:lower():find("tread", 1, true)
            or (info.Object:IsA("Model") and seat:IsDescendantOf(info.Object))) then
            return "yes"
        end
    end

    return answer
end

function Tread.Leave()
    local t = St.Tread
    local was = t.On
    t.On = false

    if St.Humanoid then
        pcall(function()
            St.Humanoid.Sit = false
        end)
    end

    if was then
        SetState("LEAVING_TREADMILL")
        Log.Debug("Left treadmill state.")
    end
end

-- Invokes the remote with a timeout. Returns ok, result/err
function Tread.Invoke(Remote)
    local done, ok, result = false, false, nil

    task.spawn(function()
        ok, result = pcall(function()
            return Remote:InvokeServer()
        end)
        done = true
    end)

    local deadline = tick() + 6
    while not done and tick() < deadline do
        task.wait(0.1)
        St.Beat = tick()
    end

    if not done then
        return false, "AskWearStill did not answer within 6s"
    end

    return ok, result
end

function Tread.Activate(Ctx)
    SetState("SEARCHING_TREADMILL")

    local info = Tread.Find(Ctx)
    if not Ctx.Ok() then
        return false, "cancelled"
    end

    if not info then
        St.Tread.RetryAt = tick() + TREADMILL_RETRY
        Log.Error("Treadmill failed: no treadmill object or prompt was found in Workspace; retrying in " .. TREADMILL_RETRY .. "s.")
        return false, "not found"
    end

    SetState("GOING_TO_TREADMILL")
    Log.Info("Going to treadmill")

    local ok, why = Flight.To(function()
        return Tread.Pos(info)
    end, Ctx, {
        Timeout = 30,
        Arrive = 2,
        Interrupt = function()
            if not Cfg.AutoSteal then
                return false
            end
            return Eggs.PickBest(6) ~= nil
        end,
    })

    if not ok then
        if why == "interrupted" then
            St.Tread.RetryAt = 0
            Log.Debug("Treadmill trip interrupted: an egg is available.")
            return false, "interrupted"
        end
        if why == "target position lost" then
            Tread.Invalidate()
            St.Tread.RetryAt = tick() + 3
            Log.Error("Treadmill failed: the treadmill disappeared during the trip; rescanning.")
            return false, why
        end
        if why ~= "cancelled" then
            St.Tread.RetryAt = tick() + TREADMILL_RETRY
            Log.Error("Treadmill failed: could not reach it (" .. tostring(why) .. ").")
        end
        return false, why
    end

    SetState("ACTIVATING_TREADMILL")

    local usedPrompt = false
    if info.Prompt and info.Prompt.Parent and info.Prompt.Enabled ~= false then
        local pok, perr = Prompts.Fire(info.Prompt)
        usedPrompt = pok
        if not pok then
            Log.Warn("Treadmill prompt could not be fired: " .. tostring(perr))
        end
        if not WaitCtx(Ctx, 0.4) then
            return false, "cancelled"
        end
    end

    local remote = Tread.Remote()
    local remoteResult

    if remote then
        local rok, res = Tread.Invoke(remote)
        if not Ctx.Ok() then
            return false, "cancelled"
        end

        if not rok then
            St.Tread.RetryAt = tick() + TREADMILL_RETRY
            Log.Error("Treadmill failed: AskWearStill errored: " .. tostring(res))
            return false, "remote error"
        end

        if res == false then
            St.Tread.RetryAt = tick() + TREADMILL_RETRY
            Log.Error("Treadmill failed: AskWearStill remote returned false.")
            return false, "remote returned false"
        end

        remoteResult = res
    else
        Log.Warn("AskWearStill RemoteFunction was not found (checked Packages.Networking and a recursive lookup).")
    end

    if not WaitCtx(Ctx, 0.6) then
        return false, "cancelled"
    end

    local probe = Tread.Probe()

    if probe == "no" then
        St.Tread.RetryAt = tick() + TREADMILL_RETRY
        Log.Error("Treadmill failed: activation was sent but the player is not in a treadmill state (moved away or state flag is off).")
        return false, "probe failed"
    end

    if probe == "unknown" and not remote and not usedPrompt then
        St.Tread.RetryAt = tick() + TREADMILL_RETRY
        Log.Error("Treadmill failed: neither a prompt nor the remote could activate it.")
        return false, "nothing to activate"
    end

    St.Tread.On = true

    if probe == "yes" then
        Log.Info("Treadmill activated (verified).")
    else
        Log.Info("Treadmill activated (position verified; the game exposes no treadmill state flag). Remote returned: " .. tostring(remoteResult))
    end

    SetState("ON_TREADMILL")
    Log.Info("Waiting for eggs")

    return true
end

-- Called by the controller whenever Auto Treadmill should be active.
function Tread.Step()
    if St.Tread.On then
        local probe = Tread.Probe()

        if probe == "no" then
            Log.Warn("Treadmill state lost - recovering.")
            St.Tread.On = false
            St.Tread.RetryAt = 0

            local info = St.Tread.Info
            if not info or not info.Object or not info.Object.Parent then
                Tread.Invalidate()
            end
        else
            SetState("ON_TREADMILL")
            return
        end
    end

    if tick() < St.Tread.RetryAt then
        return
    end

    Mission.Run("Treadmill", "Treadmill", Tread.Activate)
end

----------------------------------------------------------------
-- AUTO STEAL MISSION
----------------------------------------------------------------

function Auto.Run(Ctx, Info)
    local prompt = Info.Prompt

    SetState("TARGET_FOUND")
    Log.Info("Egg found: " .. Eggs.Describe(Info))

    if St.Tread.On then
        Tread.Leave()
    end

    SetState("GOING_TO_EGG")
    Log.Info("Going to egg: " .. tostring(Info.EggName))

    local ok, why = Flight.To(function()
        if not prompt.Parent or not prompt:IsDescendantOf(Workspace) then
            return nil
        end
        return U.PosOf(prompt)
    end, Ctx, { Timeout = 30, Arrive = 2 })

    if not ok then
        if why == "cancelled" then
            return false, "cancelled"
        end
        Prompts.Blacklist(prompt, 8)
        if why == "target position lost" then
            return false, "Steal failed: prompt was destroyed before confirmation."
        end
        return false, "Steal failed: could not reach the egg (" .. tostring(why) .. ")."
    end

    if not prompt.Parent or prompt.Enabled == false or not Prompts.IsSteal(prompt) then
        Prompts.Blacklist(prompt, 8)
        return false, "Steal failed: prompt became unavailable on arrival (someone else may have taken it)."
    end

    local snap = Confirm.Snapshot(prompt, Info)
    St.CurrentSnap = snap

    local result

    for attempt = 1, 2 do
        SetState("STEALING")
        Log.Info(attempt == 1 and "Steal triggered" or "Steal retry triggered")

        local fired, ferr = Prompts.Fire(prompt)
        if not fired then
            St.CurrentSnap = nil
            Prompts.Blacklist(prompt, 10)
            return false, "Steal failed: prompt could not be fired (" .. tostring(ferr) .. ")."
        end

        SetState("VERIFYING_STEAL")
        result = Confirm.Wait(Ctx, snap, CONFIRM_TIMEOUT)

        if result == nil then
            St.CurrentSnap = nil
            return false, "cancelled"
        end

        if result.Confirmed then
            break
        end

        if attempt == 1 then
            if not prompt.Parent or not prompt:IsDescendantOf(Workspace) then
                break
            end

            Log.Warn("Steal not confirmed after the first trigger - one controlled retry")

            Flight.To(function()
                if not prompt.Parent then
                    return nil
                end
                return U.PosOf(prompt)
            end, Ctx, { Timeout = 6, Arrive = 2 })

            if not WaitCtx(Ctx, 0.3) then
                St.CurrentSnap = nil
                return false, "cancelled"
            end
        end
    end

    St.CurrentSnap = nil

    if not (result and result.Confirmed) then
        Prompts.Blacklist(prompt, 20)

        if not prompt.Parent or not prompt:IsDescendantOf(Workspace) then
            return false, "Steal failed: prompt was destroyed before confirmation."
        end

        return false, "Steal failed: no confirmation signal (carried egg / prompt / character change) after 2 triggers."
    end

    Confirm.Record(snap, result)
    Prompts.Blacklist(prompt, 6)

    -- Egg is ours now: finish delivery even if Auto Steal is switched off.
    Ctx.Need = nil

    Log.Info("Steal confirmed (" .. table.concat(result.Reasons, "; ") .. ")")

    local status, dwhy = Delivery.Run(Ctx)
    local cont, msg = Delivery.Report(Ctx, status, dwhy)

    if cont then
        if Cfg.AutoTreadmill then
            Log.Info("Returning to treadmill")
        end
        return true
    end

    return false, msg
end

function Auto.Steal(Info)
    local ran, success, msg = Mission.Run("Auto Steal", "AutoSteal", Auto.Run, Info)

    if ran and not success and msg and msg ~= "cancelled" then
        Log.Warn(msg)
    end

    St.PauseUntil = tick() + 0.4
end

----------------------------------------------------------------
-- MANUAL INSTANT STEAL
----------------------------------------------------------------

Manual.Last = 0

function Manual.Run(Ctx, Prompt)
    SetState("VERIFYING_STEAL")
    Log.Info("Manual steal triggered - verifying")

    local snap = Prompts.BaseSnap[Prompt]
    if not snap or tick() - snap.At > 45 then
        snap = Confirm.Snapshot(Prompt, nil)
        snap.Late = true
    end
    snap.Triggered = true

    local result = Confirm.Wait(Ctx, snap, 3)
    if result == nil then
        return
    end

    Prompts.BaseSnap[Prompt] = nil

    if not result.Confirmed then
        Log.Warn("Manual steal not confirmed: no carried egg or prompt change was detected within 3s. If your game shows no such signal, enable 'Trust Prompt Trigger'.")
        return
    end

    Log.Info("Steal confirmed (" .. table.concat(result.Reasons, "; ") .. ")")
    Confirm.Record(snap, result)

    Tread.Leave()

    local status, why = Delivery.Run(Ctx)
    Delivery.Report(Ctx, status, why)

    St.PauseUntil = tick() + 0.5
end

function Manual.Start(Prompt)
    if tick() - Manual.Last < 0.5 then
        return
    end

    if St.Busy then
        if St.Mission == "Treadmill" then
            Mission.Abort()
        else
            return
        end
    end

    local ctx = Mission.Begin("Manual Steal", "Instant")
    if not ctx then
        return
    end

    Manual.Last = tick()

    task.spawn(function()
        local ok, err = xpcall(Manual.Run, Log.Handler, ctx, Prompt)
        Mission.End(ctx)

        if not ok then
            Log.Error("Manual steal crashed: " .. tostring(err))
            Flight.Cancel()
        end
    end)
end

----------------------------------------------------------------
-- CONTROLLER (single loop, generation guarded)
----------------------------------------------------------------

Controller.Running = false

function Controller.Tick()
    St.Beat = tick()

    if St.Busy then
        return
    end

    if not Cfg.AutoSteal and not Cfg.AutoTreadmill then
        if St.State ~= "IDLE" then
            SetState("IDLE")
        end
        return
    end

    if not Char.Ready() then
        SetState("RECOVERING", "waiting for character")
        return
    end

    if tick() < St.PauseUntil then
        return
    end

    -- Resume delivery of an egg we still carry (after timeout / failed delivery).
    if St.NeedDelivery then
        if St.DeliveryFailures >= 3 then
            St.NeedDelivery = false
            Log.Warn("Giving up on the carried egg after repeated delivery failures.")
        else
            Mission.Run("Deliver Carried Egg", nil, function(Ctx)
                local status, why = Delivery.Run(Ctx)
                Delivery.Report(Ctx, status, why)
            end)
            return
        end
    end

    if Cfg.AutoSteal then
        local target = Eggs.PickBest(10)

        if target then
            Auto.Steal(target)
            return
        end

        if not Cfg.AutoTreadmill then
            SetState("WAITING_FOR_EGG")
            return
        end
    end

    if Cfg.AutoTreadmill then
        Tread.Step()
    end
end

function Controller.Start()
    Gen.Controller += 1
    local mine = Gen.Controller

    Controller.Running = true
    St.Beat = tick()

    task.spawn(function()
        while not St.Unloaded and mine == Gen.Controller do
            local ok, err = xpcall(Controller.Tick, Log.Handler)

            if not ok then
                Log.Error("Controller error: " .. tostring(err))
                task.wait(1)
            end

            task.wait(TICK_INTERVAL)
        end

        if mine == Gen.Controller then
            Controller.Running = false
        end
    end)
end

function Controller.Ensure()
    if not Controller.Running and not St.Unloaded then
        Controller.Start()
    end
end

----------------------------------------------------------------
-- SELF HEALING
----------------------------------------------------------------

Heal.Passes = 0

function Heal.RecoverStuck(Reason)
    Log.Error("Mission timeout: '" .. tostring(St.Mission) .. "' " .. Reason .. " (state: " .. tostring(St.State) .. "). Cancelling.")

    Mission.Abort()
    SetState("RECOVERING")

    St.Tread.On = false
    St.CurrentSnap = nil

    if Carry.IsCarrying() then
        St.NeedDelivery = true
        Log.Warn("Egg is still carried - delivery will resume.")
    end

    if Cfg.AutoSteal or Cfg.AutoTreadmill then
        Controller.Start()
    end
end

function Heal.Pass(Force)
    if St.Unloaded then
        return
    end
    if not Force and not Cfg.SelfHealing then
        return
    end

    Heal.Passes += 1

    -- Character
    local liveChar = LocalPlayer.Character
    if liveChar and liveChar.Parent and St.Char ~= liveChar then
        Log.Warn("Self-healing: character mismatch, re-attaching.")
        task.spawn(Char.Setup, liveChar, false)
    elseif St.Char and St.Char.Parent then
        if not St.Root or not St.Root.Parent then
            St.Root = St.Char:FindFirstChild("HumanoidRootPart")
        end
        if not St.Humanoid or not St.Humanoid.Parent then
            St.Humanoid = St.Char:FindFirstChildOfClass("Humanoid")
        end
    end

    -- Prompt cache + Instant Steal hooks
    Prompts.Purge()

    if Cfg.InstantSteal then
        Prompts.ApplyInstantAll()
    end

    if (Cfg.AutoSteal or Force) and next(Prompts.Set) == nil and tick() - Prompts.LastScan > 30 then
        Log.Warn("Self-healing: prompt cache is empty, rescanning.")
        Prompts.LastScan = tick()
        task.spawn(Prompts.Scan)
    end

    -- Controller
    if Cfg.AutoSteal or Cfg.AutoTreadmill then
        if not Controller.Running then
            Log.Warn("Self-healing: controller was not running, restarting.")
            Controller.Start()
        elseif not St.Busy and tick() - St.Beat > 20 then
            Log.Warn("Self-healing: controller stalled, restarting.")
            Controller.Start()
        end
    end

    -- Treadmill
    if Cfg.AutoTreadmill and St.Tread.On then
        local info = St.Tread.Info
        if not info or not info.Object or not info.Object.Parent then
            Log.Warn("Self-healing: treadmill disappeared, invalidating cache.")
            Tread.Invalidate()
            St.Tread.On = false
            St.Tread.RetryAt = 0
        elseif Tread.Probe() == "no" then
            Log.Warn("Self-healing: treadmill state is stale, resetting.")
            St.Tread.On = false
            St.Tread.RetryAt = 0
        end
    end

    -- Mission watchdog
    if St.Busy and St.MissionStart > 0 then
        if tick() - St.Beat > MISSION_TIMEOUT then
            Heal.RecoverStuck("made no progress for " .. MISSION_TIMEOUT .. "s")
        elseif tick() - St.MissionStart > MISSION_HARD_CAP then
            Heal.RecoverStuck("exceeded " .. MISSION_HARD_CAP .. "s")
        end
    end

    -- Carrying state consistency
    if not St.Busy and St.Carry and St.Carry.Observable and not Carry.IsCarrying() and not St.NeedDelivery then
        St.Carry = nil
    end
end

function Heal.Start()
    Gen.Heal += 1
    local mine = Gen.Heal

    task.spawn(function()
        while not St.Unloaded and mine == Gen.Heal and Cfg.SelfHealing do
            local ok, err = xpcall(Heal.Pass, Log.Handler, false)
            if not ok then
                Log.Error("Self-heal error: " .. tostring(err))
            end
            task.wait(3)
        end
    end)
end

----------------------------------------------------------------
-- DEBUG / DISCOVERY TOOLS
----------------------------------------------------------------

function Eggs.Inspect(Prompt)
    local root = Eggs.FindRoot(Prompt)
    local info = Eggs.GetInfo(Prompt, true)

    print("==== Rage Hub: egg inspection ====")
    print("Prompt:", U.Path(Prompt), "| Action:", Prompt.ActionText, "| Object:", Prompt.ObjectText)
    print("Root:", root and U.Path(root) or "nil")

    if info then
        print(Eggs.DebugLine(info))
        Log.Info(Eggs.DebugLine(info))
    end

    if root then
        local D = Eggs.Gather(root, Prompt)
        print("-- attributes / value objects --")
        for i, a in ipairs(D.Attrs) do
            if i > 60 then break end
            print("  ", a.Key, "=", tostring(a.Value))
        end
        print("-- text labels --")
        for i, l in ipairs(D.Labels) do
            if i > 60 then break end
            print("  ", l.Parent .. "/" .. l.Name, "=", l.Text)
        end
    end

    print("==== end inspection ====")
    Log.Info("Inspection printed to the developer console (F9).")
end

function Eggs.NearestPrompt(OnlyEggs)
    local ref = St.Root and St.Root.Position
    if not ref then
        return nil
    end

    local best, bestDist
    for _, p in ipairs(Prompts.List()) do
        if p.Parent then
            local ok = (not OnlyEggs) or Prompts.IsSteal(p)
            if ok then
                local pos = U.PosOf(p)
                if pos then
                    local d = (pos - ref).Magnitude
                    if not bestDist or d < bestDist then
                        best, bestDist = p, d
                    end
                end
            end
        end
    end

    return best
end

function Eggs.DumpNearby()
    local ref = St.Root and St.Root.Position
    if not ref then
        Log.Warn("No character - cannot dump prompts.")
        return
    end

    local list = {}
    for _, p in ipairs(Prompts.List()) do
        if p.Parent then
            local pos = U.PosOf(p)
            if pos then
                local d = (pos - ref).Magnitude
                if d <= 60 then
                    list[#list + 1] = { P = p, D = d }
                end
            end
        end
    end

    table.sort(list, function(a, b)
        return a.D < b.D
    end)

    Log.Info("Prompts within 60 studs: " .. #list)
    print("==== Rage Hub: nearby prompts ====")

    for i, e in ipairs(list) do
        local line = string.format(
            "[%s | %s] steal=%s dist=%.0f %s",
            tostring(e.P.ActionText), tostring(e.P.ObjectText),
            tostring(Prompts.IsSteal(e.P)), e.D, U.Path(e.P)
        )
        print(line)
        if i <= 10 then
            Log.Add(line)
        end
    end

    print("==== end ====")
end

----------------------------------------------------------------
-- CLEANUP
----------------------------------------------------------------

local function Cleanup()
    if St.Unloaded then
        return
    end

    St.Unloaded = true

    for k, v in pairs(Gen) do
        Gen[k] = v + 1
    end

    Cfg.AutoSteal = false
    Cfg.AutoTreadmill = false
    Cfg.InstantSteal = false

    pcall(Flight.Cancel)

    St.Busy = false
    St.Carry = nil
    St.CurrentSnap = nil
    St.Tread.On = false

    if St.Humanoid then
        pcall(function()
            St.Humanoid.Sit = false
        end)
    end

    if St.DiedConn then
        pcall(function()
            St.DiedConn:Disconnect()
        end)
        St.DiedConn = nil
    end

    pcall(Prompts.RestoreAll)
    DisconnectAll()

    if ENV[CLEANUP_KEY] == Cleanup then
        ENV[CLEANUP_KEY] = nil
    end

    local w = UI.Window
    UI.Window = nil
    if w then
        for _, method in ipairs({ "Destroy", "Unload" }) do
            if type(w[method]) == "function" then
                if pcall(w[method], w) then
                    break
                end
            end
        end
    end
end

ENV[CLEANUP_KEY] = Cleanup

----------------------------------------------------------------
-- UI
----------------------------------------------------------------

local okWin, winOrErr = pcall(function()
    return RageHub:CreateWindow({
        Name = "Rage Hub",
        Subtitle = "Steal An Egg - v6 AFK",
        Theme = "Midnight",
        ToggleKey = Enum.KeyCode.RightControl,
        ConfigFolder = "RageHub",
        AutoSave = CONFIG_NAME,

        OnUnload = function()
            Cleanup()
        end,
    })
end)

if not okWin or not winOrErr then
    warn("[Rage Hub] CreateWindow failed: " .. tostring(winOrErr))
    Cleanup()
    return
end

UI.Window = winOrErr

------------------------------------
