--[[=====================================================================
    RAGE HUB  ·  Steal An Egg  (v4)
    Tab: STEAL  ·  works on BOTH maps (main + Halloween event map)
    ------------------------------------------------------------------
    WHAT IS IN THIS TAB
    · Instant Steal (Manual) . hold delay removed from Steal prompts on
                              BOTH maps (CarryAreaEgg on the main map,
                              CarryHalloweenEgg in the event map). Buy /
                              sell / talk prompts keep normal timing.
    · Auto Steal ............. full auto farming loop. Scans the eggs on
                              your CURRENT map, applies the filters
                              below, walks to the best one, steals it,
                              secures it, then goes for the next.
    · Biome Filter ........... All (default) or one biome. The list is
                              read live from the game
                              (World.Areas.GuardAreas) and sorted the
                              way the map is actually laid out - the
                              LAST biome is Enchanted Forest. Main map
                              only (the event map has no biomes).
    · Pick Egg By ............ Most Value or Most Rarity. Pets are
                              resolved through the game's own data
                              (ReplicatedStorage.Data.Assets +
                              Data.Rarity + Data.HalloweenEggSettings).
                              Eggs whose pet cannot be read before the
                              steal are ranked after known ones.
    · Event Farm Loop ........ while the auto steal session is running
                              in the Halloween dimension, every stolen
                              egg is carried to the PortalHome pad in
                              the event safe zone and taken home
                              through the portal; the script then walks
                              back through the dimension portal next to
                              the spawn and keeps farming the event.
    · Auto Treadmill .......... keeps you on YOUR plot treadmill and
                              starts the game's own treadmill session
                              (RF/Treadmill/AskWearStill). Jump off,
                              drift off, get knocked away or die - as
                              long as the toggle is on you walk
                              straight back onto the belt. Pauses
                              automatically while a steal runs and idles
                              in the event map.
    · Auto Secure (Self Heal + Re-Steal) - no toggle, it is part of the
                              script and runs after EVERY steal:
                              MAIN MAP: healthy -> carry the egg
                              straight across the separation line.
                              Hurt -> park it just past the line, heal
                              at the spawn, come back and finish.
                              EVENT MAP: carry the egg to the PortalHome
                              pad (HalloweenDimension.ZonesAssets
                              ["Spawn/Safezone"]["Spawn Structures"]
                              .PortalHome["Cylinder.016"]) and step
                              into the portal to bring it home.
                              If a guard or another player knocks the
                              egg out of your hands ANYWHERE, or you die
                              mid-carry, the script finds THAT EXACT egg
                              again (uid tracking + world scan), moves
                              to it, re-steals it and repeats.
    ------------------------------------------------------------------
    MOVEMENT (v4)
    · The tween engine is GONE. The server kept rubber-banding the
      tweened character back and forth and killing it, so v4 moves ONLY
      with Humanoid:MoveTo - the game's own speed system - re-issued so
      it never hits the 8 second MoveTo timeout, with stuck detection
      and an auto-jump. One mover, zero fighting, zero deaths.
    ------------------------------------------------------------------
    MAP DETECTION
    · Polls the HalloweenDimension pivot + PlayRadius. Teleport through
      any portal and everything switches automatically: remotes, travel
      targets, filters and labels. A running flow ADAPTS to the new map
      instead of cancelling - event egg -> PortalHome -> main map spawn
      -> secured, all inside one flow.
    UI toggle key: RightShift (library default)
=====================================================================]]

-- ══════════════════════════════════════════════ services / constants
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local Workspace         = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer

local DROP_OFFSET  = 12     -- studs past the separation line (into the field)
local HEAL_MAX     = 8      -- max seconds to wait for a heal
local BELT_RETURN  = 5.5    -- studs off the belt center before we pull you back
local FLOW_PASSES  = 14     -- safety cap on the secure/re-steal loop
local WEAR_AGAIN   = 30     -- re-ask the treadmill session every 30s
local STEAL_WAIT   = 2.5    -- seconds to wait for a carry to register
local EGG_COOLDOWN = 12     -- skip a uid this long after a failed carry
local ENTER_WAIT   = 8      -- seconds to wait for a portal to fire
local RESCAN_WAIT  = 1.5    -- rescan delay when no egg matches

-- ══════════════════════════════════════════════ re-exec protection
if _G.__RAGE_SAE_CLEANUP then
    pcall(_G.__RAGE_SAE_CLEANUP)
    _G.__RAGE_SAE_CLEANUP = nil
end

local ALIVE       = true
local CONNECTIONS = {}
local EXTRA       = {}

local function bind(signal, fn)
    local c = signal:Connect(fn)
    CONNECTIONS[#CONNECTIONS + 1] = c
    return c
end
local function onUnloadExtra(fn) EXTRA[#EXTRA + 1] = fn end

-- ══════════════════════════════════════════════ small helpers
local function waitFor(cond, timeout)
    local deadline = os.clock() + (timeout or 3)
    while os.clock() < deadline do
        if cond() then return true end
        task.wait(0.05)
    end
    return cond() == true
end

local function waitChild(parent, name, t)
    if not parent then return nil end
    local got = parent:FindFirstChild(name)
    if got then return got end
    local deadline = os.clock() + (t or 8)
    while os.clock() < deadline do
        got = parent:FindFirstChild(name)
        if got then return got end
        task.wait(0.1)
    end
    return parent:FindFirstChild(name)
end

local UNITS = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }
local function fmtSpeed(n)
    n = tonumber(n) or 0
    if n < 1000 then return tostring(math.floor(n + 0.5)) end
    local i = 0
    while n >= 1000 and i < #UNITS - 1 do
        n = n / 1000
        i = i + 1
    end
    return string.format("%.2f%s", n, UNITS[i + 1])
end

-- ══════════════════════════════════════════════ library
local RageHub = loadstring(game:HttpGet("https://raw.githubusercontent.com/devnamegelo/Rage-Hub/main/RageHub.lua"))()

-- ══════════════════════════════════════════════ remote resolver
-- The game keeps every remote as a flat-named child of
-- Packages/Networking ("RF/EggWorld/...", "RF/HalloweenDimension/...",
-- "RF/Treadmill/...").
local Networking = nil
do
    local pkgs = waitChild(ReplicatedStorage, "Packages", 10)
    Networking = pkgs and waitChild(pkgs, "Networking", 10) or nil
end

local function remoteOk(r, kind)
    if typeof(r) ~= "Instance" then return false end
    if kind == "RF" then return r:IsA("RemoteFunction") end
    return r:IsA("RemoteEvent") or r:IsA("UnreliableRemoteEvent")
end

local function findRemote(kind, ns, name)
    local flat = kind .. "/" .. ns .. "/" .. name
    -- (1) current flat layout
    if Networking then
        local r = Networking:FindFirstChild(flat)
        if remoteOk(r, kind) then return r end
        -- (2) legacy nested layout: Networking.RF.<ns>.<name>
        local k = Networking:FindFirstChild(kind)
        local n = k and k:FindFirstChild(ns) or nil
        local r2 = n and n:FindFirstChild(name) or nil
        if remoteOk(r2, kind) then return r2 end
    end
    -- (3) one-time deep scan (in case the container moved again)
    for _, d in ipairs(ReplicatedStorage:GetDescendants()) do
        if d.Name == flat and remoteOk(d, kind) then
            return d
        end
    end
    return nil
end

local REMOTE_SPECS = {
    -- main map (EggWorld)
    { store = "EggWorld",         key = "AskFieldEggCarry",      kind = "RF", ns = "EggWorld",          name = "AskFieldEggCarry" },
    { store = "EggWorld",         key = "AskFieldEggDrop",       kind = "RF", ns = "EggWorld",          name = "AskFieldEggDrop" },
    { store = "EggWorld",         key = "FieldEggCarry",         kind = "RE", ns = "EggWorld",          name = "FieldEggCarry" },
    { store = "EggWorld",         key = "FieldEggShifted",       kind = "RE", ns = "EggWorld",          name = "FieldEggShifted" },
    { store = "EggWorld",         key = "FieldEggBatchShifted",  kind = "RE", ns = "EggWorld",          name = "FieldEggBatchShifted" },
    { store = "EggWorld",         key = "FieldEggGone",          kind = "RE", ns = "EggWorld",          name = "FieldEggGone" },
    { store = "EggWorld",         key = "FieldEggRedeemVerdict", kind = "RE", ns = "EggWorld",          name = "FieldEggRedeemVerdict" },
    -- halloween event map
    { store = "HalloweenDimension", key = "AskCarryEgg",         kind = "RF", ns = "HalloweenDimension", name = "AskCarryEgg" },
    { store = "HalloweenDimension", key = "AskDropEgg",          kind = "RF", ns = "HalloweenDimension", name = "AskDropEgg" },
    -- treadmill session
    { store = "Treadmill",        key = "WearStill",             kind = "RF", ns = "Treadmill",         name = "AskWearStill" },
    { store = "Treadmill",        key = "Doff",                  kind = "RF", ns = "Treadmill",         name = "AskDoff" },
}

local EggWorld, HDimension, TreadmillR = {}, {}, {}

do
    -- remotes can stream in a moment after join: retry for a few seconds
    local deadline = os.clock() + 8
    repeat
        for _, spec in ipairs(REMOTE_SPECS) do
            local store
            if spec.store == "EggWorld" then store = EggWorld
            elseif spec.store == "HalloweenDimension" then store = HDimension
            else store = TreadmillR end
            if not store[spec.key] then
                store[spec.key] = findRemote(spec.kind, spec.ns, spec.name)
            end
        end
        local n = 0
        for _, s in ipairs(REMOTE_SPECS) do
            local store
            if s.store == "EggWorld" then store = EggWorld
            elseif s.store == "HalloweenDimension" then store = HDimension
            else store = TreadmillR end
            if store[s.key] then n = n + 1 end
        end
        if n >= #REMOTE_SPECS then break end
        task.wait(0.5)
    until os.clock() >= deadline
end

local function remotesMain()
    local n = 0
    for _, k in ipairs({ "AskFieldEggCarry", "AskFieldEggDrop", "FieldEggCarry",
                         "FieldEggShifted", "FieldEggBatchShifted", "FieldEggGone",
                         "FieldEggRedeemVerdict" }) do
        if EggWorld[k] then n = n + 1 end
    end
    return n, 7
end

local function remotesEvent()
    local n = 0
    for _, k in ipairs({ "AskCarryEgg", "AskDropEgg" }) do
        if HDimension[k] then n = n + 1 end
    end
    return n, 2
end

local function remotesTread()
    local n = 0
    for _, k in ipairs({ "WearStill", "Doff" }) do
        if TreadmillR[k] then n = n + 1 end
    end
    return n, 2
end

-- ══════════════════════════════════════════════ game data modules
local Assets, RarityData, HalloweenSettings
do
    local data = waitChild(ReplicatedStorage, "Data", 6)
    if data then
        local function tryReq(childName)
            local c = waitChild(data, childName, 4)
            if not c then return nil end
            local ok, m = pcall(function() return require(c) end)
            if ok and type(m) == "table" then return m end
            return nil
        end
        Assets            = tryReq("Assets")
        RarityData        = tryReq("Rarity")
        HalloweenSettings = tryReq("HalloweenEggSettings")
    end
end

local function assetOf(category)
    if not (Assets and Assets.Directory and category) then return nil end
    local ok, a = pcall(function() return Assets.Directory[category] end)
    if ok then return a end
    return nil
end
local function petNameOf(category)
    local a = assetOf(category)
    return (a and a.DisplayName) or category or "?"
end
local function eggNameOf(category)
    local a = assetOf(category)
    if a and a.Egg and a.Egg.DisplayName then return a.Egg.DisplayName end
    return (category or "Egg") .. " Egg"
end

-- rarity ranking -------------------------------------------------------
local RARITY_FALLBACK = {
    "Common", "Uncommon", "Rare", "SuperRare", "Epic", "Legendary", "Mythic",
    "Divine", "Cosmic", "Titan", "Transcendent", "Eternal", "Secret",
    "Rainbow", "LightDark", "BrainrotGod", "Limited",
}
local function normRarity(s)
    return (tostring(s or ""):lower():gsub("[^%a]", ""))
end

local rarityRankMap = {}
do
    local function fromArray(arr)
        local n = 0
        if type(arr) ~= "table" then return 0 end
        for i, v in ipairs(arr) do
            local id = type(v) == "table" and (v._id or v.Id or v.Name or v.DisplayName) or v
            if type(id) == "string" and id ~= "" then
                n = n + 1
                rarityRankMap[normRarity(id)] = i
            end
        end
        return n
    end
    local built = false
    if RarityData then
        if fromArray(RarityData) > 0 then
            built = true
        else
            for _, key in ipairs({ "List", "Order", "Rarities", "All", "Configs" }) do
                local t = RarityData[key]
                if type(t) == "table" then
                    if fromArray(t) > 0 then built = true break end
                    -- dict of configs with a numeric tier field
                    local rows = {}
                    for name, cfg in pairs(t) do
                        if type(cfg) == "table" then
                            local num = tonumber(cfg.Order or cfg.Rank or cfg.Rarity
                                or cfg.Power or cfg.Tier or cfg.Weight)
                            if num then rows[#rows + 1] = { name = name, n = num } end
                        end
                    end
                    if #rows > 1 then
                        table.sort(rows, function(a, b) return a.n < b.n end)
                        for i, row in ipairs(rows) do
                            rarityRankMap[normRarity(row.name)] = i
                        end
                        built = true
                        break
                    end
                end
            end
        end
    end
    if not built then
        for i, name in ipairs(RARITY_FALLBACK) do
            rarityRankMap[normRarity(name)] = i
        end
    end
end

local function rarityRank(id)
    if type(id) ~= "string" then return nil end
    return rarityRankMap[normRarity(id)]
end

-- pet -> value / rarity (used by the Auto Steal filters) ---------------
local VALUE_KEYS = { "Value", "SellValue", "SellPrice", "Price", "Cash", "Cost",
                     "Worth", "BaseValue", "BaseCash" }

local function baseName(pet)
    if type(pet) ~= "string" then return nil end
    return pet:match("[^/\\]+$") or pet
end

local function assetEntry(pet)
    local name = baseName(pet)
    if not (name and name ~= "" and Assets and Assets.Directory) then return nil end
    local ok, e = pcall(function() return Assets.Directory[name] end)
    if ok and type(e) == "table" then return e end
    return nil
end

local function halloweenEntry(pet)
    local name = baseName(pet)
    if not (name and name ~= "" and HalloweenSettings) then return nil end
    for _, t in ipairs({ HalloweenSettings, HalloweenSettings.Eggs,
                         HalloweenSettings.Pets, HalloweenSettings.Pool }) do
        if type(t) == "table" and type(t[name]) == "table" then return t[name] end
    end
    return nil
end

local function numFrom(t)
    if type(t) ~= "table" then return nil end
    for _, k in ipairs(VALUE_KEYS) do
        local v = tonumber(t[k])
        if v then return v end
    end
    return nil
end

local function petValue(pet)
    local e = assetEntry(pet)
    return numFrom(e) or numFrom(e and e.Egg) or numFrom(halloweenEntry(pet))
end

local function petRarityId(pet)
    local e = assetEntry(pet)
    local r = e and e.Rarity
    if type(r) == "table" then
        return r._id or r.Name or r.DisplayName
    end
    local h = halloweenEntry(pet)
    if type(h) == "table" then
        local id = h.Rarity or h.RarityId or h.RarityName or h._id
        if type(id) == "string" then return id end
    end
    return nil
end

local function petRarityRank(pet)
    return rarityRank(petRarityId(pet))
end

local function petRarityName(pet)
    local e = assetEntry(pet)
    local r = e and e.Rarity
    if type(r) == "table" then return r.DisplayName or r._id end
    local id = petRarityId(pet)
    return id
end

-- the game's own carry request shapes (from the current dump):
--   FirstArea: { Uid = "FirstAreaEgg_<userId>_<modelId>_<AreaId>:<SlotId>",
--                FirstAreaSlotKey = "<AreaId>:<SlotId>" }
--   other areas: { Uid = "<guid>" }
--   event map:   "<guid>" (plain string)
local function carryArgs(uid)
    if type(uid) == "string" then
        local slot = uid:match("^FirstAreaEgg_%d+_%d+_(.+)$")   -- current form
            or uid:match("^FirstAreaEgg_%d+_(.+)$")             -- older single-number form
        if slot then
            return { Uid = uid, FirstAreaSlotKey = slot }
        end
    end
    return { Uid = uid }
end

-- ══════════════════════════════════════════════ runtime config
local cfg = {
    instant   = false,
    autoSteal = false,
    biome     = "All",
    pickBy    = "Most Value",
    treadmill = false,
    eventLoop = true,
}

-- ══════════════════════════════════════════════ character / world
local function getRoot()
    local char = LocalPlayer.Character
    if not char then return nil end
    local root = char:FindFirstChild("HumanoidRootPart")
    if root and root:IsA("BasePart") then return root end
    return nil
end
local function getHumanoid()
    local char = LocalPlayer.Character
    return char and char:FindFirstChildOfClass("Humanoid") or nil
end
local function flat(v) return Vector3.new(v.X, 0, v.Z) end

local function getSpeed()
    local ls = LocalPlayer:FindFirstChild("leaderstats")
    local v = ls and ls:FindFirstChild("Speed")
    if v == nil then return 0 end
    return tonumber(v.Value) or 0
end

-- ══════════════════════════════════════════════ map detection
local activeMap = "Main"   -- "Main" | "Halloween"

local function currentMap()
    local root = getRoot()
    if not root then return activeMap end
    local hd = Workspace:FindFirstChild("HalloweenDimension")
    if hd then
        local ok, pv = pcall(function() return hd:GetPivot().Position end)
        local radius = tonumber(hd:GetAttribute("PlayRadius")) or 3165
        if ok and pv and (root.Position - pv).Magnitude <= radius then
            return "Halloween"
        end
    end
    return "Main"
end

activeMap = currentMap()

-- ══════════════════════════════════════════════ main map geometry
local function getSeparationLine()
    local world = Workspace:FindFirstChild("World")
    local areas = world and world:FindFirstChild("Areas")
    local line  = areas and areas:FindFirstChild("SeparationLine")
    if line and line:IsA("BasePart") then return line end
    return nil
end

local function getSpawnGround()
    local sp = Workspace:FindFirstChild("SpawnLocation")
    if sp and sp:IsA("BasePart") then
        return sp.Position + Vector3.new(0, sp.Size.Y * 0.5, 0)
    end
    return Vector3.new(512.7, 68.6, -362.6) -- dump fallback
end

-- Drop spot: just past the separation line on the FIELD side (the side
-- away from the spawn), aligned with the spawn's Z.
local function getDropSpot()
    local line, spawn = getSeparationLine(), getSpawnGround()
    if not line then
        return Vector3.new(spawn.X + 45, spawn.Y, spawn.Z)
    end
    local dirX = (line.Position.X >= spawn.X) and 1 or -1
    return Vector3.new(
        line.Position.X + dirX * DROP_OFFSET,
        line.Position.Y + 1,
        spawn.Z
    )
end

-- ══════════════════════════════════════════════ event map geometry
-- The event safe zone return point (user-verified path):
--   HalloweenDimension.ZonesAssets["Spawn/Safezone"]
--     ["Spawn Structures"].PortalHome["Cylinder.016"]
local function portalHomeModel()
    local hd = Workspace:FindFirstChild("HalloweenDimension")
    if not hd then return nil end
    local za = hd:FindFirstChild("ZonesAssets")
    local sz = za and za:FindFirstChild("Spawn/Safezone")
    local ss = sz and sz:FindFirstChild("Spawn Structures")
    local ph = ss and ss:FindFirstChild("PortalHome")
    if ph then return ph end
    -- fallback: deep scan (renamed containers)
    local found = hd:FindFirstChild("PortalHome", true)
    if found and found:IsA("Model") then return found end
    return nil
end

local function portalHomePart(name)
    local ph = portalHomeModel()
    if not ph then return nil end
    local p = ph:FindFirstChild(name)
    if p and p:IsA("BasePart") then return p end
    return nil
end

-- the big pad in front of the home portal - THIS is where the character
-- walks to while carrying an event egg
local function getPortalHomePad()
    local p = portalHomePart("Cylinder.016")
    if p then return p.Position end
    return Vector3.new(-5808.73, -204.87, -7375.22) -- dump fallback
end

-- the portal wall itself (has the TouchInterest)
local function getPortalHomePortal()
    local p = portalHomePart("Portal")
    if p then return p.Position end
    return Vector3.new(-5808.76, -187.94, -7489.21) -- dump fallback
end

-- the event map safe zone (heal spot): average of the spawn pads,
-- falling back to the PortalHome pad (which sits inside the safe zone)
local function getEventSafeSpot()
    local hd = Workspace:FindFirstChild("HalloweenDimension")
    if hd then
        local spawns = hd:FindFirstChild("Spawns")
        if spawns then
            local sum, n = Vector3.zero, 0
            for _, p in ipairs(spawns:GetChildren()) do
                if p:IsA("BasePart") then
                    sum = sum + p.Position
                    n = n + 1
                end
            end
            if n > 0 then
                local avg = sum / n
                return Vector3.new(avg.X, avg.Y, avg.Z)
            end
        end
    end
    return getPortalHomePad()
end

-- the main-map portal INTO the event dimension (right next to the spawn)
local function getEventEnterPortal()
    local w = Workspace:FindFirstChild("World")
    local p = w and w:FindFirstChild("HalloweenDimensionPortal")
    if p then
        local hb = p:FindFirstChild("Hitbox")
        if hb and hb:IsA("BasePart") then return hb.Position end
        local any = p:FindFirstChildWhichIsA("BasePart")
        if any then return any.Position end
    end
    return Vector3.new(536.36, 74.08, -325.56) -- dump fallback
end

-- ══════════════════════════════════════════════ egg tracking state
local eggTrack = {}   -- [uid] = { pos = Vector3, at = os.clock() }
local goneEggs = {}   -- [uid] = true
local carryCooldown = {} -- [uid] = os.clock() until

local function noteShift(uid, cf)
    if type(uid) == "string" and typeof(cf) == "CFrame" then
        eggTrack[uid] = { pos = cf.Position, at = os.clock() }
        goneEggs[uid] = nil
    end
end

local function onCooldown(uid)
    return carryCooldown[uid] ~= nil and os.clock() < carryCooldown[uid]
end

-- ══════════════════════════════════════════════ egg finders (legacy uid paths)
local function findNearestEggUid(pos, radius)
    local names = { "AreaEggSlotsClient", "AreaEggsClient" }
    for _, n in ipairs(names) do
        local folder = Workspace:FindFirstChild(n)
        if folder then
            local best, bestD = nil, radius or 24
            for _, m in ipairs(folder:GetChildren()) do
                if m:IsA("Model") then
                    local ok, pv = pcall(function() return m:GetPivot().Position end)
                    if ok and pv then
                        local d = (flat(pv) - flat(pos)).Magnitude
                        if d <= bestD then best, bestD = m.Name, d end
                    end
                end
            end
            if best then return best end
        end
    end
    return nil
end

local function eggSlotPos(uid)
    local folder = Workspace:FindFirstChild("AreaEggSlotsClient")
    local m = folder and folder:FindFirstChild(uid)
    if m then
        local ok, pv = pcall(function() return m:GetPivot().Position end)
        if ok and pv then return pv end
    end
    return nil
end

-- event map: WorldEggs.HalloweenEgg models carry their uid in attributes
local function findNearestHalloweenEgg(aroundPos, radius, preferUid)
    local hd = Workspace:FindFirstChild("HalloweenDimension")
    local folder = hd and hd:FindFirstChild("WorldEggs")
    if not folder then return nil, nil, nil end
    if preferUid then
        for _, m in ipairs(folder:GetChildren()) do
            if m:IsA("Model") and m:GetAttribute("HalloweenEggUid") == preferUid then
                local ok, pv = pcall(function() return m:GetPivot().Position end)
                if ok and pv then return m, preferUid, pv end
            end
        end
    end
    if not aroundPos then return nil, nil, nil end
    local best, bu, bp, bd = nil, nil, nil, radius or 150
    for _, m in ipairs(folder:GetChildren()) do
        if m:IsA("Model") and m:GetAttribute("HalloweenEggCanPickUp") ~= false then
            local uid = m:GetAttribute("HalloweenEggUid")
            if type(uid) == "string" then
                local ok, pv = pcall(function() return m:GetPivot().Position end)
                if ok and pv then
                    local d = (flat(pv) - flat(aroundPos)).Magnitude
                    if d <= bd then best, bu, bp, bd = m, uid, pv, d end
                end
            end
        end
    end
    return best, bu, bp
end

-- ══════════════════════════════════════════════ egg metadata (filters)
-- best-effort pet identity of an egg model, from attributes / values
local function petOfModel(m)
    local v = m:GetAttribute("PreparedSourceName")
    if type(v) == "string" and v ~= "" then
        return baseName(v)
    end
    for _, key in ipairs({ "AssetCategory", "PetName", "Pet", "Category", "EggName" }) do
        local a = m:GetAttribute(key)
        if type(a) == "string" and a ~= "" then return a end
    end
    for _, key in ipairs({ "AssetCategory", "PetName", "Pet" }) do
        local c = m:FindFirstChild(key)
        if c and c:IsA("StringValue") and c.Value ~= "" then return c.Value end
    end
    -- runtime labels (the game can add a billboard with the pet name)
    local bb = m:FindFirstChildOfClass("BillboardGui")
    if bb then
        for _, d in ipairs(bb:GetDescendants()) do
            if d:IsA("TextLabel") and d.Text ~= "" and d.Text ~= "Egg" then
                return d.Text
            end
        end
    end
    return nil
end

-- biome of a main-map egg: embedded in FirstAreaEgg names, otherwise
-- resolved from the GuardAreas Bounds parts (eggs are laid out along X)
local function biomeOfEgg(modelName, pos)
    local embedded = tostring(modelName or ""):match("^FirstAreaEgg_%d+_%d+_(.+):")
    if embedded then return embedded end
    local world = Workspace:FindFirstChild("World")
    local areas = world and world:FindFirstChild("Areas")
    local ga = areas and areas:FindFirstChild("GuardAreas")
    if not (ga and pos) then return nil end
    local best, bw = nil, math.huge
    for _, biome in ipairs(ga:GetChildren()) do
        if biome:IsA("Model") then
            local b = biome:FindFirstChild("Bounds")
            if b and b:IsA("BasePart") then
                local dx = math.abs(pos.X - b.Position.X)
                local dz = math.abs(pos.Z - b.Position.Z)
                if dx <= b.Size.X * 0.5 + 25 and dz <= b.Size.Z * 0.5 + 80 then
                    if dx < bw then best, bw = biome.Name, dx end
                end
            end
        end
    end
    return best
end

-- biome list for the dropdown, in map order (last = Enchanted Forest)
local BIOME_FALLBACK = {
    "Forest", "Lake", "Desert", "Jungle", "Snow", "Volcano", "Abyss Ocean",
    "Prehistoric", "Cosmic", "Cherry Blossom", "Titan Temple", "Light Dark",
    "Enchanted Forest",
}

local function biomeNames()
    local out = {}
    local world = Workspace:FindFirstChild("World")
    local areas = world and world:FindFirstChild("Areas")
    local ga = areas and areas:FindFirstChild("GuardAreas")
    if ga then
        for _, biome in ipairs(ga:GetChildren()) do
            if biome:IsA("Model") then
                local x = nil
                local b = biome:FindFirstChild("Bounds")
                if b and b:IsA("BasePart") then
                    x = b.Position.X
                else
                    local ok, cf = pcall(function() return biome:GetBoundingBox() end)
                    if ok and cf then x = cf.Position.X end
                end
                out[#out + 1] = { name = biome.Name, x = x or 999999 }
            end
        end
    end
    if #out == 0 then
        for i, n in ipairs(BIOME_FALLBACK) do
            out[i] = { name = n, x = i }
        end
    else
        table.sort(out, function(a, b) return a.x < b.x end)
    end
    local names = {}
    for _, info in ipairs(out) do names[#names + 1] = info.name end
    return names
end

local function biomeOptions()
    local opts = { "All" }
    for _, n in ipairs(biomeNames()) do opts[#opts + 1] = n end
    return opts
end

-- ══════════════════════════════════════════════ egg scanners + picker
local function scanMainEggs()
    local out = {}
    local folder = Workspace:FindFirstChild("AreaEggSlotsClient")
    if not folder then return out end
    for _, m in ipairs(folder:GetChildren()) do
        if m:IsA("Model") then
            local uid = m.Name
            if not goneEggs[uid] and not onCooldown(uid) then
                local ok, pv = pcall(function() return m:GetPivot().Position end)
                if ok and pv then
                    out[#out + 1] = {
                        uid = uid, pos = pv, model = m, map = "Main",
                        pet = petOfModel(m),
                        biome = biomeOfEgg(uid, pv),
                    }
                end
            end
        end
    end
    return out
end

local function scanEventEggs()
    local out = {}
    local hd = Workspace:FindFirstChild("HalloweenDimension")
    local folder = hd and hd:FindFirstChild("WorldEggs")
    if not folder then return out end
    for _, m in ipairs(folder:GetChildren()) do
        if m:IsA("Model") and m:GetAttribute("HalloweenEggCanPickUp") ~= false then
            local uid = m:GetAttribute("HalloweenEggUid")
            if type(uid) == "string" and uid ~= "" and not onCooldown(uid) then
                local ok, pv = pcall(function() return m:GetPivot().Position end)
                if ok and pv then
                    out[#out + 1] = {
                        uid = uid, pos = pv, model = m, map = "Halloween",
                        pet = petOfModel(m),
                        zone = m:GetAttribute("Zone"),
                    }
                end
            end
        end
    end
    return out
end

local function scanEggs()
    if currentMap() == "Halloween" then return scanEventEggs() end
    return scanMainEggs()
end

-- pick the best egg for the current filters. Returns the egg table, or
-- nil + "filter" (biome filter matched nothing) / nil + nil (no eggs)
local function pickBestEgg()
    local list = scanEggs()
    if #list == 0 then return nil, nil end
    if currentMap() == "Main" and cfg.biome ~= "All" then
        local filtered = {}
        for _, e in ipairs(list) do
            if e.biome == cfg.biome then filtered[#filtered + 1] = e end
        end
        list = filtered
        if #list == 0 then return nil, "filter" end
    end
    local root = getRoot()
    local rp = root and root.Position or nil
    for _, e in ipairs(list) do
        e.value = e.pet and petValue(e.pet) or nil
        e.rank  = e.pet and petRarityRank(e.pet) or nil
        e.dist  = rp and (flat(e.pos) - flat(rp)).Magnitude or 0
    end
    table.sort(list, function(a, b)
        local av, bv = a.value or -1, b.value or -1
        local ar, br = a.rank or -1, b.rank or -1
        if cfg.pickBy == "Most Rarity" then
            if ar ~= br then return ar > br end
            if av ~= bv then return av > bv end
        else
            if av ~= bv then return av > bv end
            if ar ~= br then return ar > br end
        end
        return a.dist < b.dist
    end)
    return list[1], nil
end

local function eggLabel(e)
    local parts = {}
    if e.pet then
        parts[#parts + 1] = e.pet
        local rn = petRarityName(e.pet)
        if rn then parts[#parts + 1] = rn end
        if e.value then parts[#parts + 1] = fmtSpeed(e.value) end
    else
        parts[#parts + 1] = "egg"
    end
    if e.biome then parts[#parts + 1] = e.biome end
    if e.zone then parts[#parts + 1] = ("Zone " .. tostring(e.zone)) end
    return table.concat(parts, " · ")
end

-- ══════════════════════════════════════════════ instant steal engine
-- The game creates the Steal prompts client-side with a hold delay
-- (CarryAreaEgg 1.2s on the main map, CarryHalloweenEgg 0.35s in the
-- event map). We zero both.
local stealPrompts = {}   -- [prompt] = original HoldDuration

local function isStealPrompt(p)
    if not p:IsA("ProximityPrompt") then return false end
    if p.Name == "CarryAreaEgg" or p.Name == "CarryHalloweenEgg" then return true end
    return p.ActionText == "Steal"
end

local function applyZero(p)
    if p.Parent == nil then stealPrompts[p] = nil return end
    if stealPrompts[p] == nil then
        stealPrompts[p] = p.HoldDuration
    end
    if p.HoldDuration ~= 0 then
        p.HoldDuration = 0
    end
end

local function applyInstantScan()
    for _, d in ipairs(Workspace:GetDescendants()) do
        if isStealPrompt(d) then applyZero(d) end
    end
end

local function restorePrompts()
    for p, orig in pairs(stealPrompts) do
        if p.Parent then
            pcall(function() p.HoldDuration = orig end)
        end
    end
end

bind(Workspace.DescendantAdded, function(d)
    if cfg.instant and isStealPrompt(d) then
        task.defer(applyZero, d)
    end
end)

-- cheap sweep: re-assert cached prompts (the game may recreate them)
task.spawn(function()
    while ALIVE do
        task.wait(0.4)
        if cfg.instant then
            for p in pairs(stealPrompts) do
                if p.Parent == nil then
                    stealPrompts[p] = nil
                elseif p.HoldDuration ~= 0 then
                    p.HoldDuration = 0
                end
            end
        end
    end
end)

-- steal prompt near a position (used as a re-steal fallback)
local function findStealPromptNear(pos, radius)
    local best, bd = nil, radius or 12
    for _, d in ipairs(Workspace:GetChildren()) do
        if d:IsA("BasePart") and d.Name == "SmartPromptPart" then
            local p = d:FindFirstChildOfClass("ProximityPrompt")
            if p and isStealPrompt(p) then
                local dist = (flat(d.Position) - flat(pos)).Magnitude
                if dist <= bd then best, bd = p, dist end
            end
        end
    end
    return best
end

-- prompt attached to a known egg model (Hitbox child)
local function promptOfModel(m)
    if not m then return nil end
    local hb = m:FindFirstChild("Hitbox")
    if hb then
        local p = hb:FindFirstChildOfClass("ProximityPrompt")
        if p and isStealPrompt(p) then return p end
    end
    for _, d in ipairs(m:GetChildren()) do
        if d:IsA("BasePart") then
            local p = d:FindFirstChildOfClass("ProximityPrompt")
            if p and isStealPrompt(p) then return p end
        end
    end
    return nil
end

-- ══════════════════════════════════════════════ carry state
local carry = { IsCarrying = false, Uid = nil, AssetCategory = nil, AreaId = nil }
local lastCarryUid = nil
local lastCarryPos = nil   -- refreshed while carrying (used after death)
local expectingRecarry = false
local guiCarrySeen = false

local function findDropGui()
    local pg = LocalPlayer:FindFirstChild("PlayerGui")
    if not pg then return nil end
    local gui = pg:FindFirstChild("DropHeldEgg")
    if gui and gui:IsA("ScreenGui") and gui.Enabled then return gui end
    return nil
end

local function isCarryingNow()
    if carry.IsCarrying then return true end
    return findDropGui() ~= nil
end

-- keep a fresh "where was I when I had the egg" position
task.spawn(function()
    while ALIVE do
        task.wait(0.4)
        if isCarryingNow() then
            local r = getRoot()
            if r then lastCarryPos = r.Position end
        end
    end
end)

-- ══════════════════════════════════════════════ shared flow/treadmill/auto state
local flowToken     = nil
local flowActive    = false
local flowEggUid    = nil
local redeemedSeen  = false
local lossPos       = nil
local treadmillToken = nil
local autoToken     = nil
local autoBusy      = false    -- true while the auto-steal loop moves/steals
local eventSession  = false    -- true while the session farms the event map
local enterFails    = 0

-- treadmill session state
local beltPart     = nil
local beltNotified = false
local beltWearing  = false
local beltLastWear = 0

local function treadmillWear()
    local r = TreadmillR.WearStill
    if not r then return false end
    local ok = pcall(function() r:InvokeServer() end)
    if ok then
        beltWearing = true
        beltLastWear = os.clock()
    end
    return ok
end

local function treadmillDoff()
    beltWearing = false
    local r = TreadmillR.Doff
    if r then
        pcall(function() r:InvokeServer() end)
    end
end

-- called whenever a steal flow is about to move the character
local function treadmillPause()
    if beltWearing then
        treadmillDoff()
    end
end

-- ══════════════════════════════════════════════ window + Steal tab
local win = RageHub:CreateWindow({
    Name         = "Rage Hub",
    Subtitle     = "Steal An Egg · v4 · Auto Steal + MoveTo",
    ConfigFolder = "RageHub/StealAnEgg",
    Width        = 580,
    Height       = 460,
    OnUnload     = function()
        if _G.__RAGE_SAE_CLEANUP then pcall(_G.__RAGE_SAE_CLEANUP) end
    end,
})

local tab = win:CreateTab("Steal")

-- ══════════════════════════════════════════════ UI elements
local secMain = tab:CreateSection("Steal")

secMain:CreateToggle({
    Name        = "Instant Steal (Manual)",
    Description = "Manually steal any egg on BOTH maps - the hold delay on the Steal prompt is removed (main map + Halloween event map), so the steal registers the instant it is triggered. Buy, sell and talk prompts keep their normal timing.",
    Flag        = "Steal.Instant",
    Default     = false,
    Callback    = function(v)
        cfg.instant = v
        if v then applyInstantScan() else restorePrompts() end
    end,
})

secMain:CreateToggle({
    Name        = "Auto Steal",
    Description = "Full auto farming: scans the eggs on your CURRENT map, applies the Biome Filter and the Pick Egg By rule, walks to the best egg, steals it and secures it (self heal + re-steal included), then goes for the next one. Works on the main map and inside the Halloween dimension.",
    Flag        = "Steal.Auto",
    Default     = false,
    Callback    = function(v)
        cfg.autoSteal = v
        if not v then
            if autoToken then autoToken.cancelled = true end
            eventSession = false
            enterFails = 0
            autoBusy = false
        end
    end,
})

local ddBiome = secMain:CreateDropdown({
    Name        = "Biome Filter",
    Description = "Main map only: steal eggs from one biome. 'All' takes the best egg anywhere (nearest when the pet cannot be read before the steal). The list is read from the live game; the last biome is Enchanted Forest.",
    Options     = biomeOptions(),
    Default     = "All",
    Flag        = "Steal.Biome",
    Callback    = function(v)
        cfg.biome = (type(v) == "string" and v ~= "") and v or "All"
    end,
})

secMain:CreateSegmented({
    Name        = "Pick Egg By",
    Description = "How the auto steal ranks eggs: Most Value (pet sell value first) or Most Rarity (rarity tier first). Pet data comes from the game's own asset tables.",
    Options     = { "Most Value", "Most Rarity" },
    Default     = "Most Value",
    Flag        = "Steal.PickBy",
    Callback    = function(v) cfg.pickBy = v end,
})

secMain:CreateToggle({
    Name        = "Event Farm Loop",
    Description = "While the auto steal session is running in the Halloween dimension: after each egg is brought home through the event PortalHome, the script walks back through the dimension portal next to the spawn and keeps farming the event. Turn OFF to farm main-map biome eggs instead.",
    Flag        = "Steal.EventLoop",
    Default     = true,
    Callback    = function(v)
        cfg.eventLoop = v
        enterFails = 0
    end,
})

local secTread = tab:CreateSection("Treadmill")

local lblTreadStatus
secTread:CreateToggle({
    Name        = "Auto Treadmill",
    Description = "Keeps you on YOUR plot treadmill and starts the game's own treadmill session (AskWearStill). Jump off, drift off, get knocked away or die - you automatically walk back onto the belt and the session restarts. Pauses while a steal flow runs and idles in the event map.",
    Flag        = "Steal.Treadmill",
    Default     = false,
    Callback    = function(v)
        cfg.treadmill = v
        beltPart = nil
        beltNotified = false
        if not v then
            treadmillDoff()
            if treadmillToken then treadmillToken.cancelled = true end
        end
        if lblTreadStatus then
            lblTreadStatus:Set(v and "Treadmill: on - locking your plot..." or "Treadmill: off")
        end
        if v then
            win:Notify({
                Title   = "Auto Treadmill",
                Content = "On. Your plot is detected from the YourBase flag / the plot sign - or stand on your treadmill once if neither is readable.",
                Type    = "info",
                Duration = 5,
            })
        end
    end,
})
lblTreadStatus = secTread:CreateLabel("Treadmill: off")

local secStat  = tab:CreateSection("Status")
local lblMap     = secStat:CreateLabel("Map: -")
local lblRemotes = secStat:CreateLabel("Remotes: -")
local lblSpeed   = secStat:CreateLabel("Speed: -")
local lblPerf    = secStat:CreateLabel("FPS: -  |  Ping: -")
local lblCarry   = secStat:CreateLabel("Carrying: nothing")
local lblFlow    = secStat:CreateLabel("Flow: idle")
local lblAuto    = secStat:CreateLabel("Auto Steal: off")
local paraLast   = secStat:CreateParagraph({ Title = "Last Steal", Content = "Nothing yet." })
local paraAuto   = secStat:CreateParagraph({
    Title   = "Auto Secure + Re-Steal",
    Content = "Runs automatically after every steal - no toggle. MAIN MAP: healthy -> carry straight across the separation line; hurt -> park the egg by the line, heal at the spawn, recover it, finish. EVENT MAP: carry the egg to the PortalHome pad in the event safe zone and step through the portal back home. If the egg is ever knocked out of your hands (guard / slap) or you die mid-carry, the script finds that exact egg, moves to it, re-steals it and repeats.",
})

local function setFlowLabel(s) lblFlow:Set("Flow: " .. tostring(s)) end
local function setTreadLabel(s) lblTreadStatus:Set("Treadmill: " .. tostring(s)) end
local function setAutoLabel(s) lblAuto:Set("Auto Steal: " .. tostring(s)) end

local function updateCarryUI(info)
    if info then
        lblCarry:Set(string.format("Carrying: %s (%s) - Pet: %s", info.egg, info.rarity, info.pet))
    else
        lblCarry:Set("Carrying: nothing")
    end
end

-- ══════════════════════════════════════════════ movement engine (MoveTo only)
-- Walks using the game's own speed system; MoveTo is re-issued so it
-- never hits the 8-second timeout, with stuck detection + auto-jump.
-- The deadline scales with the trip length and your speed stat.
local function travel(target, token, arrive, abortIf)
    arrive = arrive or 4
    local root0 = getRoot()
    local dist0 = root0 and (flat(target) - flat(root0.Position)).Magnitude or 0
    local speed = math.max(getSpeed(), 16)
    local deadline = os.clock() + math.clamp(dist0 / speed * 1.6 + 20, 30, 420)
    local lastDist, stuckAt, jumped = math.huge, nil, false
    while os.clock() < deadline do
        if not ALIVE or token.cancelled then return false, "cancelled" end
        if abortIf and abortIf() then return false, "aborted" end
        local root, hum = getRoot(), getHumanoid()
        if not root or not hum then return false, "no character" end
        if hum.Health <= 0 then return false, "died" end
        local dist = (flat(target) - flat(root.Position)).Magnitude
        if dist <= arrive then return true, nil end
        if dist < lastDist - 0.25 then
            lastDist, stuckAt, jumped = dist, os.clock(), false
        elseif stuckAt then
            local stuckFor = os.clock() - stuckAt
            if stuckFor > 5 and not jumped then
                hum.Jump = true
                jumped = true
            elseif stuckFor > 12 then
                return false, "stuck"
            end
        end
        hum:MoveTo(Vector3.new(target.X, root.Position.Y, target.Z))
        task.wait(0.15)
    end
    return false, "timeout"
end

-- ══════════════════════════════════════════════ carry / drop helpers
local function eggLostWithRecord()
    if isCarryingNow() then return false end
    local r = getRoot()
    if r then lossPos = r.Position end
    return true
end

-- click the DropHeldEgg button as fast as possible
local function findDropButton(gui)
    local b = gui:FindFirstChild("Button")
    if b and b:IsA("GuiButton") then return b end
    for _, d in ipairs(gui:GetDescendants()) do
        if d:IsA("GuiButton") then return d end
    end
    return nil
end

local function clickDropButton()
    local gui = findDropGui()
    if not gui then return false end
    local btn = findDropButton(gui)
    if not btn then return false end
    if typeof(firesignal) == "function" then
        pcall(firesignal, btn.MouseButton1Click)
        pcall(firesignal, btn.Activated)
        task.delay(0.15, function()
            if ALIVE and isCarryingNow() and btn.Parent then
                pcall(firesignal, btn.MouseButton1Down)
                pcall(firesignal, btn.MouseButton1Up)
            end
        end)
        return true
    end
    return false
end

-- full drop routine: GUI click first, remote fallback right after
local function dropHeldEgg(token)
    clickDropButton()
    task.delay(0.3, function()
        if ALIVE and not token.cancelled and isCarryingNow() then
            if currentMap() == "Halloween" then
                if HDimension.AskDropEgg then
                    pcall(function() HDimension.AskDropEgg:InvokeServer() end)
                end
            elseif EggWorld.AskFieldEggDrop then
                pcall(function()
                    EggWorld.AskFieldEggDrop:InvokeServer({ Reason = "PlayerRequest" })
                end)
            end
        end
    end)
end

-- invoke the correct carry remote for the current map
local function invokeCarry(uid)
    if type(uid) ~= "string" then return false end
    if currentMap() == "Halloween" then
        if not HDimension.AskCarryEgg then return false end
        local ok = pcall(function()
            HDimension.AskCarryEgg:InvokeServer(uid)
        end)
        return ok
    end
    if not EggWorld.AskFieldEggCarry then return false end
    local ok = pcall(function()
        EggWorld.AskFieldEggCarry:InvokeServer(carryArgs(uid))
    end)
    return ok
end

-- locate the egg we lost: tracked shift position -> world scan
local function locateEgg(uid, fallbackPos)
    -- 1. freshest shift record for THAT uid
    if type(uid) == "string" and eggTrack[uid] and (os.clock() - eggTrack[uid].at) < 45 then
        return eggTrack[uid].pos, uid
    end
    if currentMap() == "Halloween" then
        local around = fallbackPos or lastCarryPos
        local _, u, p = findNearestHalloweenEgg(around, 150, uid)
        if p then return p, u end
        return nil, nil
    end
    -- 2. the egg slot folder (models are named by uid)
    if type(uid) == "string" and not goneEggs[uid] then
        local pos = eggSlotPos(uid)
        if pos then return pos, uid end
    end
    -- 3. nearest slot model around where we lost it
    if fallbackPos then
        local u = findNearestEggUid(fallbackPos, 45)
        if u and not goneEggs[u] then
            local pos = eggSlotPos(u)
            if pos then return pos, u end
            return fallbackPos, u
        end
    end
    -- 4. last known carrying position
    if lastCarryPos then
        local u = findNearestEggUid(lastCarryPos, 60)
        if u and not goneEggs[u] then
            local pos = eggSlotPos(u)
            if pos then return pos, u end
        end
    end
    -- 5. stale shift record as a last resort
    if type(uid) == "string" and eggTrack[uid] then
        return eggTrack[uid].pos, uid
    end
    return nil, nil
end

local function waitForRespawn(token)
    local deadline = os.clock() + 15
    while os.clock() < deadline do
        if not ALIVE or token.cancelled then return false end
        local root, hum = getRoot(), getHumanoid()
        if root and hum and hum.Health > 0 then
            task.wait(0.6)
            return true
        end
        task.wait(0.2)
    end
    return getRoot() ~= nil
end

-- steal attempt at a position: remote first, prompt fallback
-- suppressFlow = true while a flow is already running (re-steal)
local function tryStealAt(pos, uid, token, suppressFlow, model)
    if not (ALIVE and not token.cancelled) then return false end
    if uid then
        if suppressFlow then expectingRecarry = true end
        invokeCarry(uid)
    end
    if not isCarryingNow() then
        local p = promptOfModel(model) or findStealPromptNear(pos, 14)
        if p then
            if type(fireprompt) == "function" then
                pcall(fireprompt, p)
            end
            if not isCarryingNow() and typeof(firesignal) == "function" then
                pcall(firesignal, p.Triggered, LocalPlayer)
            end
        end
    end
    local t = os.clock() + STEAL_WAIT
    while os.clock() < t and not isCarryingNow() do
        if not ALIVE or token.cancelled then break end
        task.wait(0.1)
    end
    if suppressFlow then expectingRecarry = false end
    return isCarryingNow()
end

-- find the egg, move to it, steal it back
local function recoverEgg(token)
    if not (ALIVE and not token.cancelled) then return false end
    local around = lossPos or lastCarryPos

    for attempt = 1, 2 do
        if not (ALIVE and not token.cancelled) then return false end
        local pos, uid = locateEgg(flowEggUid, around)
        if pos then
            setFlowLabel(string.format("re-stealing the egg (try %d)", attempt))
            local ok = travel(pos, token, 4)
            if not (ALIVE and not token.cancelled) then return false end
            if ok then
                flowEggUid = uid or flowEggUid
                if tryStealAt(pos, flowEggUid, token, true) then
                    lossPos = nil
                    return true
                end
                -- egg may have shifted while we walked: re-locate and retry
                around = pos
            end
        else
            task.wait(0.4)
        end
    end

    if ALIVE and not token.cancelled then
        win:Notify({
            Title   = "Self Heal",
            Content = "Could not re-steal the egg - it was taken or despawned.",
            Type    = "error",
            Duration = 6,
        })
    end
    return false
end

-- ══════════════════════════════════════════════ auto secure / self heal flow
local function startFlow(info)
    -- per-map remote requirement
    if currentMap() == "Halloween" then
        if remotesEvent() == 0 then
            win:Notify({ Title = "Self Heal", Content = "HalloweenDimension remotes were not found - the event flow cannot run. Re-execute inside the event.", Type = "error", Duration = 7 })
            return
        end
    else
        local n = remotesMain()
        if n == 0 then
            win:Notify({ Title = "Self Heal", Content = "EggWorld remotes were not found - the automatic flow cannot run. Re-execute inside Steal An Egg.", Type = "error", Duration = 7 })
            return
        end
    end

    if flowToken then flowToken.cancelled = true end
    if treadmillToken then treadmillToken.cancelled = true end
    treadmillPause()
    local token = { cancelled = false }
    flowToken, flowActive = token, true
    flowEggUid  = (type(carry.Uid) == "string" and carry.Uid)
        or (type(info.uid) == "string" and info.uid)
        or (type(lastCarryUid) == "string" and lastCarryUid)
        or nil
    redeemedSeen = false
    lossPos = nil

    task.spawn(function()
        local function alive() return ALIVE and not token.cancelled end
        local function step(s) if alive() then setFlowLabel(s) end end

        local passes, done = 0, false
        while alive() and not done do
            passes = passes + 1
            if passes > FLOW_PASSES then
                win:Notify({ Title = "Self Heal", Content = "The steal flow ran too long and was stopped - finish this egg manually.", Type = "warning", Duration = 6 })
                break
            end

            -- not carrying? recover THAT egg first
            if not isCarryingNow() then
                if not recoverEgg(token) then break end
                if not alive() then break end
            end

            if currentMap() == "Halloween" then
                ------------------------------------------------------
                -- EVENT MAP: carry the egg to the PortalHome pad in
                -- the safe zone, then step through the portal home.
                ------------------------------------------------------
                step("carrying the egg to the portal home pad")
                local ok, why = travel(getPortalHomePad(), token, 10, eggLostWithRecord)
                if not alive() then break end

                if ok then
                    -- the pad may take you home by itself: give it a moment
                    local t = os.clock() + 1.5
                    while os.clock() < t and alive() and currentMap() == "Halloween" do task.wait(0.1) end

                    if currentMap() == "Halloween" and isCarryingNow() then
                        step("stepping into the home portal")
                        travel(getPortalHomePortal(), token, 4, eggLostWithRecord)
                        if alive() then
                            local t2 = os.clock() + ENTER_WAIT
                            while os.clock() < t2 and alive() and currentMap() == "Halloween" do task.wait(0.1) end
                        end
                    end
                    if not alive() then break end

                    if currentMap() ~= "Halloween" then
                        if isCarryingNow() then
                            -- loop continues into the MAIN branch below and
                            -- finishes the delivery at the spawn
                            step("back home - finishing the delivery")
                        else
                            done = true
                            setFlowLabel("event egg secured")
                            paraLast:Set("Last Steal", "Halloween egg\nBrought home through the event PortalHome.")
                            win:Notify({ Title = "Event Steal", Content = "Halloween egg brought home through the portal.", Type = "success", Duration = 6 })
                        end
                    else
                        -- portal did not fire (cooldown?) - retry next pass
                        if isCarryingNow() then
                            step("portal did not open - retrying")
                            task.wait(1)
                        end
                    end
                else
                    if why == "died" or why == "no character" then
                        step("respawning...")
                        waitForRespawn(token)
                        -- heal at the hub before going back out (the event
                        -- map monsters hit hard)
                        local hum2 = getHumanoid()
                        if hum2 and hum2.MaxHealth > 0 and (hum2.Health / hum2.MaxHealth) < 0.7 then
                            step("healing at the safe zone")
                            local root = getRoot()
                            local safe = getEventSafeSpot()
                            if root and (flat(safe) - flat(root.Position)).Magnitude > 40 then
                                travel(safe, token)
                            end
                            local th = os.clock() + HEAL_MAX
                            while os.clock() < th and alive() do
                                local h3 = getHumanoid()
                                if h3 and h3.MaxHealth > 0 and h3.Health >= h3.MaxHealth * 0.95 then break end
                                task.wait(0.15)
                            end
                        end
                        -- loop: recover the egg and go again
                    elseif why == "aborted" then
                        step("egg knocked out - going after it")
                    else
                        if isCarryingNow() then
                            setFlowLabel("travel failed (" .. tostring(why) .. ")")
                            win:Notify({ Title = "Event Steal", Content = "Could not reach the PortalHome pad (" .. tostring(why) .. ") - the egg is still in hand, deliver it manually.", Type = "warning", Duration = 6 })
                        end
                        break
                    end
                end
            else
                ------------------------------------------------------
                -- MAIN MAP: healthy -> carry straight home; hurt ->
                -- park the egg by the line, heal at the spawn,
                -- recover, finish. Any loss -> re-steal and repeat.
                ------------------------------------------------------
                local hum = getHumanoid()
                local healthy = hum and hum.MaxHealth > 0 and (hum.Health / hum.MaxHealth) >= 0.85

                if healthy then
                    step("carrying egg home")
                    local ok, why = travel(getSpawnGround(), token, nil, eggLostWithRecord)
                    if not alive() then break end
                    if ok then
                        done = true
                    elseif why == "died" or why == "no character" then
                        step("respawning...")
                        waitForRespawn(token)
                    elseif why == "aborted" then
                        step("egg knocked out - going after it")
                    else
                        if isCarryingNow() then
                            setFlowLabel("travel failed (" .. tostring(why) .. ")")
                            win:Notify({ Title = "Self Heal", Content = "Could not reach the safezone (" .. tostring(why) .. "). The egg is still in hand - deliver it manually.", Type = "warning", Duration = 6 })
                        end
                        break
                    end
                else
                    -- hurt: park the egg just past the line, heal, loop
                    step("carrying egg to the drop spot (healing first)")
                    local ok, why = travel(getDropSpot(), token, nil, eggLostWithRecord)
                    if not alive() then break end

                    if ok then
                        step("dropping egg")
                        if type(carry.Uid) == "string" then flowEggUid = carry.Uid end
                        dropHeldEgg(token)
                        local dropped = waitFor(function() return not isCarryingNow() end, 5)
                        if not alive() then break end
                        if not dropped then
                            -- never managed to drop it - bring it straight home
                            step("carrying egg home")
                            travel(getSpawnGround(), token, nil, eggLostWithRecord)
                            if not alive() then break end
                            done = true
                        else
                            step("healing at the safezone")
                            travel(getSpawnGround(), token)
                            if not alive() then break end
                            local t = os.clock() + HEAL_MAX
                            while os.clock() < t and alive() do
                                local h2 = getHumanoid()
                                if h2 and h2.MaxHealth > 0 and h2.Health >= h2.MaxHealth * 0.98 then break end
                                task.wait(0.15)
                            end
                        end
                    elseif why == "died" or why == "no character" then
                        step("respawning...")
                        waitForRespawn(token)
                    elseif why == "aborted" then
                        step("egg knocked out - going after it")
                    else
                        if isCarryingNow() then
                            setFlowLabel("travel failed (" .. tostring(why) .. ")")
                            win:Notify({ Title = "Self Heal", Content = "Could not reach the drop spot (" .. tostring(why) .. "). The egg is still in hand - deliver it manually.", Type = "warning", Duration = 6 })
                        end
                        break
                    end
                end
            end
        end

        if not alive() then flowActive = false return end

        -- confirm the steal
        step("finishing up")
        waitFor(function() return (not isCarryingNow()) or redeemedSeen end, 8)
        flowActive = false
        if redeemedSeen then
            setFlowLabel("steal complete")
        elseif isCarryingNow() then
            setFlowLabel("stopped - egg still in hand")
        else
            setFlowLabel("egg lost")
        end
    end)
end

-- ══════════════════════════════════════════════ game event wiring
local function safeBindEvent(remote, fn)
    if typeof(remote) ~= "Instance" then return false end
    local ok, c = pcall(function()
        local sig = remote.OnClientEvent -- errors (caught) on non-events
        if not sig then return nil end
        return sig:Connect(fn)
    end)
    if ok and c then
        CONNECTIONS[#CONNECTIONS + 1] = c
        return true
    end
    return false
end

if EggWorld.FieldEggCarry then
    safeBindEvent(EggWorld.FieldEggCarry, function(state)
        if type(state) ~= "table" then return end
        -- ignore carry states that clearly belong to another player
        if type(state.UserId) == "number" and state.UserId ~= LocalPlayer.UserId then return end
        local wasExpecting = expectingRecarry
        carry = state
        if state.IsCarrying then
            if type(state.Uid) == "string" then
                lastCarryUid = state.Uid
                if flowActive then flowEggUid = state.Uid end
            end
            expectingRecarry = false
            local info = {
                egg    = eggNameOf(state.AssetCategory),
                pet    = petNameOf(state.AssetCategory),
                rarity = tostring(petRarityId(state.AssetCategory) or "?"),
                biome  = state.AreaId or "?",
                uid    = state.Uid,
            }
            updateCarryUI(info)
            if not wasExpecting and not flowActive then
                win:Notify({
                    Title    = currentMap() == "Halloween" and "Event steal started" or "Steal started",
                    Content  = string.format("%s (%s) - Biome: %s - Pet: %s", info.egg, info.rarity, info.biome, info.pet),
                    Type     = "info",
                    Duration = 5,
                })
                startFlow(info)
            end
        else
            updateCarryUI(nil)
        end
    end)
end

if EggWorld.FieldEggShifted then
    safeBindEvent(EggWorld.FieldEggShifted, function(rec)
        if type(rec) == "table" then
            noteShift(rec.Uid, rec.BottomCFrame)
        end
    end)
end

if EggWorld.FieldEggBatchShifted then
    safeBindEvent(EggWorld.FieldEggBatchShifted, function(list)
        if type(list) ~= "table" then return end
        for _, rec in ipairs(list) do
            if type(rec) == "table" then
                noteShift(rec.Uid, rec.BottomCFrame)
            end
        end
    end)
end

if EggWorld.FieldEggGone then
    safeBindEvent(EggWorld.FieldEggGone, function(v)
        local uids = {}
        if type(v) == "string" then
            uids[#uids + 1] = v
        elseif type(v) == "table" then
            if type(v.Uid) == "string" then
                uids[#uids + 1] = v.Uid
            else
                for _, x in ipairs(v) do
                    if type(x) == "string" then
                        uids[#uids + 1] = x
                    elseif type(x) == "table" and type(x.Uid) == "string" then
                        uids[#uids + 1] = x.Uid
                    end
                end
            end
        end
        for _, u in ipairs(uids) do
            goneEggs[u] = true
            eggTrack[u] = nil
        end
    end)
end

if EggWorld.FieldEggRedeemVerdict then
    safeBindEvent(EggWorld.FieldEggRedeemVerdict, function(v)
        if type(v) ~= "table" then return end
        redeemedSeen = true
        local egg    = v.DisplayName or eggNameOf(v.AssetCategory)
        local rarity = (v.Rarity ~= nil and tostring(v.Rarity)) or tostring(petRarityId(v.AssetCategory) or "?")
        local pet    = petNameOf(v.AssetCategory)
        win:Notify({
            Title    = "Steal successful!",
            Content  = string.format("%s (%s) secured - Pet: %s", egg, rarity, pet),
            Type     = "success",
            Duration = 7,
        })
        paraLast:Set("Last Steal", string.format("%s (%s)\nPet: %s\nResult: redeemed (secured)", egg, rarity, pet))
        setFlowLabel("steal complete")
        task.delay(3, function()
            if ALIVE and not flowActive then setFlowLabel("idle") end
        end)
    end)
end

-- backup trigger: even if the carry event is missed (or got renamed in an
-- update), the DropHeldEgg HUD tells us we are carrying - the automatic
-- flow then still starts, and the carry state stays in sync. This is the
-- primary trigger in the event map.
task.spawn(function()
    while ALIVE do
        task.wait(0.2)
        if ALIVE then
            local g = findDropGui()
            if g and not guiCarrySeen then
                guiCarrySeen = true
                if not carry.IsCarrying then
                    local wasExpecting = expectingRecarry
                    expectingRecarry = false
                    carry = { IsCarrying = true, Uid = lastCarryUid, AssetCategory = nil, AreaId = nil, viaGui = true }
                    updateCarryUI({ egg = "Egg", rarity = "?", pet = "?" })
                    if not wasExpecting and not flowActive then
                        startFlow({ egg = "Egg", pet = "?", rarity = "?", biome = "?", uid = lastCarryUid })
                    end
                end
            elseif not g and guiCarrySeen then
                guiCarrySeen = false
                if carry.viaGui then
                    carry.IsCarrying = false
                    updateCarryUI(nil)
                end
            end
        end
    end
end)

-- seed carry state if the script is executed mid-carry (also restarts
-- the flow after a re-execute)
do
    if findDropGui() then
        guiCarrySeen = true
        carry = { IsCarrying = true, Uid = lastCarryUid, AssetCategory = nil, AreaId = nil, viaGui = true }
        updateCarryUI({ egg = "Egg", rarity = "?", pet = "?" })
        if not flowActive then
            task.delay(0.5, function()
                if ALIVE and isCarryingNow() and not flowActive then
                    startFlow({ egg = "Egg", pet = "?", rarity = "?", biome = "?", uid = lastCarryUid })
                end
            end)
        end
    end
end

-- ══════════════════════════════════════════════ map watcher
-- The flow ADAPTS to a map switch (event egg -> portal home -> main map
-- delivery happens inside one flow), so we only update labels here.
task.spawn(function()
    while ALIVE do
        task.wait(0.5)
        if ALIVE then
            local m = currentMap()
            if m ~= activeMap then
                activeMap = m
                lblMap:Set(m == "Halloween" and "Map: Halloween (event)" or "Map: Main (steal)")
                win:Notify({
                    Title   = "Map switch detected",
                    Content = m == "Halloween"
                        and "You are in the Halloween event map - instant steal, the auto flow and the filters switched to the event map automatically."
                        or "Back on the main map - everything switched back automatically.",
                    Type    = "info",
                    Duration = 6,
                })
            end
        end
    end
end)

-- ══════════════════════════════════════════════ auto treadmill
local function readPlotName(plot)
    local sign = plot:FindFirstChild("PlotSign")
    if not sign then return nil end
    -- (fixed) PlotSign.PlayerPlotSign.Frame.PlayerName
    local pps = sign:FindFirstChild("PlayerPlotSign")
    local frame = pps and pps:FindFirstChild("Frame")
    local pn = frame and frame:FindFirstChild("PlayerName")
    if pn and pn:IsA("TextLabel") then return pn.Text end
    local any = sign:FindFirstChild("PlayerName", true)
    if any and any:IsA("TextLabel") then return any.Text end
    return nil
end

local function resolveMyTreadmill()
    local plots = Workspace:FindFirstChild("Plots")
    if not plots then return nil end

    local function norm(s)
        return (tostring(s or ""):lower():gsub("%s+", ""))
    end
    local me1, me2 = norm(LocalPlayer.Name), norm(LocalPlayer.DisplayName)

    -- (fixed) the belt marker is a DIRECT child of the plot model
    local function beltOf(plot)
        if not plot:IsA("Model") then return nil end
        local belt = plot:FindFirstChild("TreadmillBottom")
        if belt and belt:IsA("BasePart") then return belt end
        local up = plot:FindFirstChild("ToUpdate")
        belt = up and up:FindFirstChild("TreadmillBottom")
        if belt and belt:IsA("BasePart") then return belt end
        local tm = plot:FindFirstChild("TreadmillUpgrade")
        if tm then
            local b = tm:FindFirstChild("TreadmillBottom", true)
            if b and b:IsA("BasePart") then return b end
        end
        return nil
    end

    -- (fixed) PlotSign.Attachment.YourBase billboard = your plot
    local function isMyPlot(plot)
        local sign = plot:FindFirstChild("PlotSign")
        if not sign then return false end
        local yb = sign:FindFirstChild("YourBase", true)
        if yb and yb:IsA("BillboardGui") and yb.Enabled then return true end
        return false
    end

    -- (1) the plot flagged YourBase
    for _, plot in ipairs(plots:GetChildren()) do
        local belt = beltOf(plot)
        if belt and isMyPlot(plot) then return belt end
    end

    -- (2) the plot whose sign carries my name
    for _, plot in ipairs(plots:GetChildren()) do
        local belt = beltOf(plot)
        if belt then
            local txt = norm(readPlotName(plot))
            if txt ~= "" and (txt == me1 or txt == me2) then
                return belt
            end
        end
    end

    -- (3) the belt I am standing on / next to (only when very close)
    local root = getRoot()
    if root then
        local best, bd = nil, 25
        for _, plot in ipairs(plots:GetChildren()) do
            local belt = beltOf(plot)
            if belt then
                local d = (flat(belt.Position) - flat(root.Position)).Magnitude
                if d < bd then best, bd = belt, d end
            end
        end
        if best then return best end
    end

    return nil
end

task.spawn(function()
    while ALIVE do
        task.wait(0.25)
        if cfg.treadmill and ALIVE then
            if flowActive or autoBusy or isCarryingNow() then
                setTreadLabel("paused - steal running")
                treadmillPause()
            elseif currentMap() ~= "Main" then
                setTreadLabel("event map - no treadmill")
                treadmillPause()
            else
                if not (beltPart and beltPart.Parent) then
                    beltPart = resolveMyTreadmill()
                    if beltPart and not beltNotified then
                        beltNotified = true
                        win:Notify({
                            Title   = "Auto Treadmill",
                            Content = "Locked your treadmill.",
                            Type    = "success",
                            Duration = 4,
                        })
                    end
                end
                if not beltPart then
                    setTreadLabel("plot not found - stand on your treadmill")
                else
                    local root, hum = getRoot(), getHumanoid()
                    if not root or not hum or hum.Health <= 0 then
                        setTreadLabel("waiting for respawn...")
                    else
                        local dist = (flat(beltPart.Position) - flat(root.Position)).Magnitude
                        if dist > BELT_RETURN then
                            setTreadLabel("returning to the treadmill")
                            local token = { cancelled = false }
                            treadmillToken = token
                            local ok = travel(beltPart.Position, token, 1.5, function()
                                return (not cfg.treadmill) or flowActive or autoBusy
                                    or isCarryingNow() or currentMap() ~= "Main"
                            end)
                            if treadmillToken == token then treadmillToken = nil end
                            if ok and cfg.treadmill and ALIVE then
                                treadmillWear()
                                setTreadLabel(beltWearing and "holding (session on)" or "holding")
                            elseif not (cfg.treadmill and ALIVE) then
                                setTreadLabel("off")
                            else
                                setTreadLabel("hold failed - retrying")
                            end
                        else
                            -- on the belt: keep the game session alive
                            if (not beltWearing) or (os.clock() - beltLastWear) > WEAR_AGAIN then
                                treadmillWear()
                            end
                            setTreadLabel(beltWearing and "holding (session on)" or "holding")
                        end
                    end
                end
            end
        end
    end
end)

-- ══════════════════════════════════════════════ auto steal loop
task.spawn(function()
    while ALIVE do
        task.wait(0.25)
        if cfg.autoSteal and ALIVE then
            if flowActive or isCarryingNow() then
                autoBusy = false
                setAutoLabel("waiting for the secure flow")
            else
                local map = currentMap()

                -- (re)enter the event dimension while session farming
                if map == "Main" and cfg.eventLoop and eventSession and enterFails < 3 then
                    setAutoLabel("entering the event dimension")
                    autoBusy = true
                    treadmillPause()
                    local token = { cancelled = false }
                    autoToken = token
                    local ok = travel(getEventEnterPortal(), token, 4, function()
                        return (not cfg.autoSteal) or flowActive or isCarryingNow()
                    end)
                    if autoToken == token then autoToken = nil end
                    if ok and ALIVE and cfg.autoSteal then
                        local t = os.clock() + ENTER_WAIT
                        while os.clock() < t and ALIVE and currentMap() == "Main" do task.wait(0.1) end
                        if currentMap() == "Main" then
                            enterFails = enterFails + 1
                            if enterFails >= 3 then
                                eventSession = false
                                win:Notify({
                                    Title   = "Auto Steal",
                                    Content = "Could not enter the event dimension (portal closed?) - staying on the main map.",
                                    Type    = "warning",
                                    Duration = 6,
                                })
                            end
                        else
                            enterFails = 0
                        end
                    end
                    autoBusy = false
                    map = currentMap()
                elseif map == "Halloween" then
                    eventSession = true
                end

                -- pick + steal the best egg for the filters
                if ALIVE and cfg.autoSteal and not flowActive and not isCarryingNow() then
                    local best, why = pickBestEgg()
                    if not best then
                        autoBusy = false
                        if why == "filter" then
                            setAutoLabel("no egg in " .. tostring(cfg.biome) .. " - waiting")
                        else
                            setAutoLabel("no egg available - waiting")
                        end
                        task.wait(RESCAN_WAIT)
                    else
                        setAutoLabel("going to " .. eggLabel(best))
                        autoBusy = true
                        treadmillPause()
                        local token = { cancelled = false }
                        autoToken = token
                        local ok, why = travel(best.pos, token, 6, function()
                            return (not cfg.autoSteal) or flowActive or isCarryingNow()
                        end)
                        if autoToken == token then autoToken = nil end
                        if ok then
                            if ALIVE and cfg.autoSteal and not isCarryingNow() and not flowActive then
                                if not tryStealAt(best.pos, best.uid, token, false, best.model) then
                                    -- carry refused: cooldown that uid and move on
                                    carryCooldown[best.uid] = os.clock() + EGG_COOLDOWN
                                    setAutoLabel("carry refused - skipping")
                                end
                            end
                            -- give the flow (just started via the carry event) the lead
                            if isCarryingNow() or flowActive then
                                local t = os.clock() + 6
                                while os.clock() < t and ALIVE and cfg.autoSteal
                                      and not flowActive and not isCarryingNow() do
                                    task.wait(0.1)
                                end
                            end
                        elseif why == "died" or why == "no character" then
                            setAutoLabel("waiting for respawn")
                            local t = os.clock() + 15
                            while os.clock() < t and ALIVE do
                                local h2 = getHumanoid()
                                if h2 and h2.Health > 0 then break end
                                task.wait(0.2)
                            end
                        end
                        autoBusy = false
                    end
                end
            end
        else
            autoBusy = false
        end
    end
end)

-- ══════════════════════════════════════════════ FPS / ping + status labels
local fps, pingMs = 60, 0
do
    local frames, t0 = 0, os.clock()
    bind(RunService.RenderStepped, function()
        frames = frames + 1
        local now = os.clock()
        local el = now - t0
        if el >= 1 then
            fps = frames / el
            frames, t0 = 0, now
        end
    end)
end

local lastBiomeCount = -1
task.spawn(function()
    while ALIVE do
        task.wait(1)
        pcall(function() pingMs = LocalPlayer:GetNetworkPing() * 1000 end)
        if ALIVE then
            lblPerf:Set(string.format("FPS: %d  |  Ping: %d ms", math.floor(fps + 0.5), math.floor(pingMs + 0.5)))
            -- prune stale egg tracks
            local now = os.clock()
            for u, rec in pairs(eggTrack) do
                if now - rec.at > 180 then eggTrack[u] = nil end
            end
            for u, at in pairs(carryCooldown) do
                if now > at + 5 then carryCooldown[u] = nil end
            end
        end
    end
end)

-- live speed / map / remote labels + biome dropdown refresh
task.spawn(function()
    while ALIVE do
        task.wait(0.5)
        if ALIVE then
            lblSpeed:Set(string.format("Speed: %s", fmtSpeed(getSpeed())))
            local nMain, tMain = remotesMain()
            local nEvent, tEvent = remotesEvent()
            local nTread = remotesTread()
            lblRemotes:Set(string.format("Remotes: main %d/%d · event %d/%d · tread %d/2", nMain, tMain, nEvent, tEvent, nTread))
            lblMap:Set(activeMap == "Halloween" and "Map: Halloween (event)" or "Map: Main (steal)")
            -- refresh the biome list once the game has streamed the areas
            local opts = biomeOptions()
            if #opts ~= lastBiomeCount then
                lastBiomeCount = #opts
                pcall(function()
                    ddBiome:Refresh(opts, true)
                    local cur = ddBiome:Get()
                    cfg.biome = (type(cur) == "string" and cur ~= "") and cur or "All"
                end)
            end
            if not cfg.autoSteal then
                setAutoLabel("off")
            end
        end
    end
end)

-- ══════════════════════════════════════════════ cleanup
_G.__RAGE_SAE_CLEANUP = function()
    ALIVE = false
    for _, c in ipairs(CONNECTIONS) do
        pcall(function() c:Disconnect() end)
    end
    for _, fn in ipairs(EXTRA) do
        pcall(fn)
    end
    if flowToken then flowToken.cancelled = true end
    if treadmillToken then treadmillToken.cancelled = true end
    if autoToken then autoToken.cancelled = true end
    if beltWearing then treadmillDoff() end
    flowActive = false
    autoBusy = false
    restorePrompts()
end
onUnloadExtra(function()
    if _G.__RAGE_SAE_CLEANUP then _G.__RAGE_SAE_CLEANUP = nil end
end)

-- ══════════════════════════════════════════════ boot
win:Notify({
    Title    = "Rage Hub - Steal An Egg",
    Content  = "v4 loaded. Tween engine removed - everything moves with MoveTo (no more rubber-banding deaths). Auto Steal with biome + value/rarity filters, event eggs go to the PortalHome pad, Auto Treadmill uses the game's own session remote, and the self-heal re-steal loop is built in. UI key: RightShift.",
    Type     = "info",
    Duration = 8,
})

do
    local nMain = remotesMain()
    local nEvent = remotesEvent()
    if nMain == 0 and nEvent == 0 then
        task.delay(1, function()
            win:Notify({
                Title = "Game mismatch",
                Content = "No EggWorld / HalloweenDimension remotes were found. Make sure you are in Steal An Egg, then re-execute.",
                Type = "error",
                Duration = 10,
            })
        end)
    end
end
