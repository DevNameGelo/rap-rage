--// Rage Hub · Steal An Egg · v2 "Flight Edition"
--// Tabs: Steal | Player | Others (+ Rage Hub's built-in Settings tab)
--//
--// WHAT'S NEW IN v2 (rebuilt from your Rage Dump - Dex tree + remote spy log):
--//  * FLIGHT instead of tweens: every trip lifts you +50 studs, cruises at 500 studs/s,
--//    then descends and stops exactly on the target. No stop-and-go, no walking.
--//  * DIRECT REMOTES: stealing and dropping now call the game's own remotes
--//    (RF/EggWorld/AskFieldEggCarry / RF/EggWorld/AskFieldEggDrop) exactly like the
--//    game client does - no prompt holding, no Drop GUI clicking. Faster and cleaner.
--//  * DELIVERY: steal -> fly to the FOREST guard's EggPoint -> land -> stop -> Drop ->
--//    re-steal -> fly back to spawn. Crossing into the SafeZone redeems the egg into
--//    your inventory (the server does this by itself - verified in your dump).
--//    "Direct Flight" strategy skips the Forest stop and just flies home (fastest).
--//  * REAL RARITIES: read live from the game's own Data.Assets catalog (17 tiers with
--//    the game's own Rank numbers) - no more guessing from egg names.
--//  * RARE SPAWN ALERTS: listens to the server's own "A Secret ... spawned" broadcasts.
--//  * RECOVERY: if a guard slaps the egg out of you, it chases the egg's live position
--//    (the record updates while the guard walks) and steals it back.
--//  * Guard data read live from each area's GuardEscapeSpeeds attribute.
--//  * Experimental: Auto Place new eggs into your pen + Auto Hatch grown eggs
--//    (both use the game's own remotes, shapes taken from your spy log).
--//
--// CONFIG: Auto Save is ON by default. Your toggles, filters and sliders are saved and
--// restored automatically (this is what makes reconnect + auto execute bring everything
--// back ON). If a saved toggle ever causes trouble at startup: Others > Reset Saved Config.
--//
--// Game facts used (verified in RageDump, 2026-10-17):
--//   Steal remote   : RF/EggWorld/AskFieldEggCarry   { Uid, FirstAreaSlotKey? }  -> ok, err
--//   Drop remote    : RF/EggWorld/AskFieldEggDrop    { Reason = "PlayerRequest" } -> ok, err
--//   Egg snapshot   : RF/EggWorld/AskFieldEggSnapshot -> { Records, ServerTime }
--//   Egg events     : RE/EggWorld/FieldEggShifted / FieldEggBatchShifted / FieldEggGone /
--//                    FieldEggCarry { IsCarrying, SpeedMultiplier, Uid, AreaId } /
--//                    FieldEggRedeemVerdict { DisplayName, Rarity, ... } /
--//                    FieldEggRaritiesShown { RareSpawns = { { EggUid, Message, RarityId } } }
--//   Redeem rule    : carry the egg into World.Areas.EggCarryBounds.SafeZone (the spawn
--//                    side of the SeparationLine) -> the carry is cancelled and the egg
--//                    is added to your inventory (OwnerShifted + RedeemVerdict).
--//   Forest EggPoint: workspace.World.Areas.GuardAreas.Forest.Guard.EggPoint (weakest
--//                    guard: needs speed 11, runs 11.6 - it can never catch you).
--//   Spawn          : workspace.SpawnLocation (inside the SafeZone footprint).
--//   Your plot      : workspace.Plots.* - the one whose PlotSign has the "YourBase"
--//                    billboard; treadmill part is TreadmillBottom.
--//   Anti-cheat note: the client "ObbyAntiTP" check is only armed inside monster-event
--//                    regions (workspace.MonsterEventMap / AnticheatSuspendedRegion) -
--//                    normal-world flight is not checked by it. Keep speeds sane anyway.

local RageHub = loadstring(game:HttpGet(
    "https://raw.githubusercontent.com/devnamegelo/Rage-Hub/main/RageHub.lua"
))()

--==============================================================
-- SERVICES
--==============================================================

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local TeleportService = game:GetService("TeleportService")
local GuiService = game:GetService("GuiService")
local ProximityPromptService = game:GetService("ProximityPromptService")

local LocalPlayer = Players.LocalPlayer

--==============================================================
-- CONSTANTS
--==============================================================

-- The game's real rarity tiers (ReplicatedStorage.Data.Rarity.Configs), with their Rank
-- numbers read from the game. Live values are loaded at startup; this is the fallback.
local RARITY_LIST = {
    "Common", "SuperRare", "Uncommon", "Rare", "Epic", "Legendary", "BrainrotGod",
    "Mythic", "Rainbow", "Cosmic", "Secret", "Eternal", "Limited", "Divine",
    "Transcendent", "Titan", "LightDark",
}
local FALLBACK_RANKS = {
    Common = 1, Uncommon = 2, SuperRare = 2, Rare = 3, Epic = 4, Legendary = 5,
    BrainrotGod = 6, Mythic = 6, Rainbow = 6, Cosmic = 7, Secret = 8, Eternal = 9,
    Limited = 9, Divine = 10, Transcendent = 10, Titan = 11, LightDark = 12,
}

-- AreaId values seen in FieldEggShifted + the GuardAreas folder in your dump.
local BIOMES = {
    "Forest", "Lake", "Desert", "Jungle", "Snow", "Volcano", "Abyss Ocean", "Prehistoric",
    "Cosmic", "Cherry Blossom", "Titan Temple", "Light Dark", "Enchanted Forest",
}

-- Only used if an area's GuardEscapeSpeeds attribute can't be read.
-- need = speed stat needed, run = guard run speed (studs/s)
local GUARD = {
    ["Forest"] = { need = 11, run = 11.6 }, ["Lake"] = { need = 900, run = 24.3 },
    ["Desert"] = { need = 10000, run = 48.4 }, ["Jungle"] = { need = 40000, run = 65.6 },
    ["Snow"] = { need = 170000, run = 83.8 }, ["Abyss Ocean"] = { need = 2500000, run = 117.4 },
    ["Volcano"] = { need = 700000, run = 102.0 }, ["Prehistoric"] = { need = 18000000, run = 143.2 },
    ["Cosmic"] = { need = 700000000, run = 187.9 }, ["Cherry Blossom"] = { need = 2500000000, run = 205.7 },
    ["Titan Temple"] = { need = 7000000000, run = 217.8 }, ["Light Dark"] = { need = 20000000000, run = 231.9 },
    ["Enchanted Forest"] = { need = 49999998976, run = 242.4 },
}

-- Last-resort rarity guess from the egg's name (the Assets catalog handles almost all).
local NAME_RARITY_FALLBACK = {
    { "eternal lunar dragon", "Eternal" }, { "el maja", "Eternal" }, { "oni tiger", "Eternal" },
    { "gorilla king", "Eternal" }, { "pegasus", "Eternal" }, { "skeleton horse", "Eternal" },
    { "void dragon", "Eternal" }, { "equinox", "Eternal" },
    { "unicorn", "Divine" }, { "kitsune", "Divine" }, { "nightflame", "Divine" }, { "archangel", "Divine" },
    { "world burner", "Divine" }, { "aetheron", "Divine" },
}

-- Auto Execute: re-runs this script (from your hosted URL) in the next server
local AUTO_EXECUTE_URL = "https://raw.githubusercontent.com/DevNameGelo/rap-rage/refs/heads/main/script.lua"

--==============================================================
-- SETTINGS / STATE  (everything automation-related starts OFF)
--==============================================================

local CFG = {
    FlySpeed = 500,         -- studs/s cruise speed
    FlyOffset = 50,         -- studs above the higher endpoint while cruising
    DescendRadius = 25,     -- start descending when this close (flat) to the target
    HoverHeight = 3,        -- stop this far above the target point
    StopDelay = 0.15,       -- stop at the drop area this long before dropping
    MaxRecoveries = 3,      -- times it goes back for an egg a guard took from you
    EquipInterval = 30,
    ClaimInterval = 120,
    PlayerSpeed = 100,      -- Player tab walk speed (only used when its toggle is on)
    PlaceInterval = 8,      -- experimental: auto place check interval (s)
    HatchInterval = 45,     -- experimental: auto hatch check interval (s)
}

local InstantSteal = false
local AutoSteal = false
local AutoTreadmill = false
local SpeedAdjust = false
local InfiniteJump = false
local Noclip = false
local AntiRagdoll = false
local AutoSaveOn = true
local CameraFocus = true         -- camera watches the egg while stealing it
local SkipDangerous = false      -- skip eggs whose guard you cannot outrun
local FlightNoclip = true        -- pass through walls/trees while flying
local Strategy = "Forest Drop + Re-Steal"
local EggAlert = false
local RareSpawnAlert = true
local AllowUnknownRarity = false
local AutoEquipBest = false
local AutoClaimAway = false
local AutoPlaceEggs = false
local AutoHatchEggs = false

local GetDropButton = function() return nil end
local CamLocked, CamCFrame = false, nil

local SelectedRarities = {}   -- set; empty or all = any
local SelectedBiomes = {}     -- set (normalized names); empty or all = any
local Priority = "Highest Rarity"

local OnEggSeen = function() end
local ScanLog
local Log = function() end
local EggPosition = function() return nil end
local DescribeEgg = function() return "egg" end
local GuardDanger = function() return false end

local PauseUntil = 0             -- auto steal cooldown (e.g. satchel full)
local CarriedUid = nil           -- uid of the egg you carry (from the server)
local CarriedUidAt = 0
local NestPos = {}               -- uid -> where that egg's nest is
local EggSeenAt = {}             -- uid -> when the server last updated that egg
local LastVerdict = nil          -- last RedeemVerdict payload
local LastVerdictAt = 0
local MyEggRecords = {}          -- uid -> your owned egg records (OwnerShifted)
local SessionStats = { stolen = 0, redeemed = 0, recovered = 0 }

local Unloaded = false
local Busy = false
local Flying = false
local Job = 0                 -- bump to cancel whatever is running
local Worn = false            -- true while you are on the treadmill
local Carrying = false        -- true while holding an egg (from FieldEggCarry)
local LastTriggered = 0       -- os.clock() of your last prompt trigger
local SpeedOverride = false   -- true while the script is walking you to spawn
local TreadmillRetryAt = 0

local Window, StatusLabel
local Connections = {}
local OriginalHold = setmetatable({}, { __mode = "k" })
local Eggs = {}               -- Uid -> egg record from the server
local RarityCache = {}        -- AssetCategory -> { id, rank }
local AttemptedUntil = {}     -- Uid -> os.clock() until which we skip that egg

local function Track(conn)
    if conn then table.insert(Connections, conn) end
    return conn
end

--==============================================================
-- UI HELPERS
--==============================================================

local function Notify(title, content, kind, duration)
    pcall(function()
        if Window then
            Window:Notify({ Title = title, Content = content, Type = kind or "info", Duration = duration or 3 })
        end
    end)
end

local function SetStatus(text)
    if StatusLabel then
        pcall(function() StatusLabel:Set("Status: " .. tostring(text)) end)
    end
end

--==============================================================
-- CHARACTER HELPERS
--==============================================================

local function Char() return LocalPlayer.Character end
local function Root()
    local c = Char()
    return c and c:FindFirstChild("HumanoidRootPart")
end
local function Hum()
    local c = Char()
    return c and c:FindFirstChildOfClass("Humanoid")
end

local function Lower(s) return string.lower(tostring(s or "")) end

local function Cancelled(id)
    return Unloaded or id ~= Job
end

local function NewJob()
    Job += 1
    return Job
end

local function Net(name)
    local pk = ReplicatedStorage:FindFirstChild("Packages")
    local nw = pk and pk:FindFirstChild("Networking")
    return nw and nw:FindFirstChild(name)
end

local function WaitFor(fn, timeout, id, interval)
    local t0 = os.clock()
    repeat
        if Cancelled(id) then return nil end
        local v = fn()
        if v then return v end
        task.wait(interval or 0.1)
    until os.clock() - t0 >= timeout
    return nil
end

--==============================================================
-- CARRYING (GUI indicator + server state)
--==============================================================

local function GuiVisible(obj)
    local cur = obj
    while cur and cur ~= game do
        if cur:IsA("GuiObject") and not cur.Visible then return false end
        if cur:IsA("ScreenGui") and not cur.Enabled then return false end
        cur = cur.Parent
    end
    return obj and obj.AbsoluteSize.X > 0
end

GetDropButton = function()
    local pg = LocalPlayer:FindFirstChild("PlayerGui")
    local gui = pg and pg:FindFirstChild("DropHeldEgg")
    local btn = gui and gui:FindFirstChild("Button")
    if btn and GuiVisible(btn) then return btn end
    return nil
end

-- are we holding an egg right now? (the game shows the Drop button while carrying)
local function IsCarryingNow()
    if GetDropButton() then return true end
    return Carrying == true
end

local function WaitForCarry(timeout, id)
    return WaitFor(IsCarryingNow, timeout, id, 0.03) ~= nil
end

--==============================================================
-- FLIGHT CONTROLLER  (velocity-based, no tweens)
--   Lift to cruise height (offset above the higher endpoint), cruise at FlySpeed,
--   descend near the target, stop dead on it. Works at any speed; the character's
--   collisions can be disabled while flying (Flight Noclip) so trees never stop you.
--==============================================================

local function EndFlight()
    Flying = false
    local r = Root()
    if r then
        pcall(function()
            r.AssemblyLinearVelocity = Vector3.zero
            r.AssemblyAngularVelocity = Vector3.zero
        end)
    end
end

-- Fly to pos. opts: { Speed, Offset, DescendRadius, HoverY, MustCarry }
-- returns: true | false, "cancelled" | "lost" | "timeout" | "noreply"
local function FlyTo(pos, id, opts)
    opts = opts or {}
    local r = Root()
    if not r then return false, "noreply" end
    if typeof(pos) ~= "Vector3" then return false, "noreply" end

    pos = Vector3.new(pos.X, pos.Y, pos.Z)
    local speed = math.max(60, opts.Speed or CFG.FlySpeed)
    local offset = math.max(5, opts.Offset or CFG.FlyOffset)
    local descendR = math.max(6, opts.DescendRadius or CFG.DescendRadius)
    local hoverY = opts.HoverY ~= nil and opts.HoverY or CFG.HoverHeight
    local mustCarry = opts.MustCarry == true
    local vSpeed = math.min(speed, 320)   -- climb cap
    local dSpeed = math.min(speed, 300)   -- descend cap
    local cruiseY = math.max(r.Position.Y, pos.Y) + offset
    local timeout = os.clock() + math.max(6, ((r.Position - pos).Magnitude / speed) * 2.5 + 6)

    Flying = true
    local ok, why = false, nil

    while true do
        if Cancelled(id) then why = "cancelled"; break end
        if os.clock() > timeout then why = "timeout"; break end

        r = Root()
        if not r then why = "noreply"; break end

        local p = r.Position
        local flat = Vector3.new(pos.X - p.X, 0, pos.Z - p.Z)
        local flatDist = flat.Magnitude
        local goalY = (flatDist > descendR) and cruiseY or (pos.Y + hoverY)
        local dy = goalY - p.Y

        if flatDist <= 1.25 and math.abs(dy) <= 1.25 then
            r.AssemblyLinearVelocity = Vector3.zero
            r.AssemblyAngularVelocity = Vector3.zero
            ok = true
            break
        elseif flatDist > descendR then
            local horiz = flatDist > 0.05 and (flat / flatDist) * speed or Vector3.zero
            local vert = math.clamp(dy, -dSpeed, vSpeed)
            r.AssemblyLinearVelocity = Vector3.new(horiz.X, vert, horiz.Z)
        else
            -- final approach: slow down proportionally so we stop dead on the point
            local to = Vector3.new(pos.X, pos.Y + hoverY, pos.Z) - p
            local dist3 = to.Magnitude
            if dist3 > 0.05 then
                local eff = math.min(dSpeed, math.max(30, dist3 * 6))
                r.AssemblyLinearVelocity = to.Unit * eff
            else
                r.AssemblyLinearVelocity = Vector3.zero
            end
        end
        pcall(function() r.AssemblyAngularVelocity = Vector3.zero end)

        if mustCarry and not IsCarryingNow() then
            why = "lost"
            break
        end

        RunService.Heartbeat:Wait()
    end

    local fr = Root()
    if fr then
        pcall(function()
            fr.AssemblyLinearVelocity = Vector3.zero
            fr.AssemblyAngularVelocity = Vector3.zero
        end)
    end
    return ok, why
end

--==============================================================
-- CAMERA (stays on the egg while you steal it, follows you again after)
--==============================================================

local function CamLock(pos)
    if not CameraFocus or not pos then return end
    local cam = workspace.CurrentCamera
    if not cam then return end
    CamCFrame = CFrame.lookAt(pos + Vector3.new(0, 16, 24), pos)
    CamLocked = true
    cam.CameraType = Enum.CameraType.Scriptable
    cam.CFrame = CamCFrame
end

local function CamRelease()
    if not CamLocked then return end
    CamLocked, CamCFrame = false, nil
    local cam = workspace.CurrentCamera
    if cam then
        local h = Hum()
        if h then cam.CameraSubject = h end
        cam.CameraType = Enum.CameraType.Custom
    end
end

--==============================================================
-- PROMPTS (Instant Steal convenience: 0.1s hold on Steal prompts)
--==============================================================

local function IsStealPrompt(p)
    if not p or not p:IsA("ProximityPrompt") then return false end
    return string.find(Lower(p.ActionText), "steal", 1, true) ~= nil
        or string.find(Lower(p.Name), "carryareaegg", 1, true) ~= nil
end

local function PromptPosition(p)
    local parent = p.Parent
    if parent and parent:IsA("BasePart") then return parent.Position end
    if parent and parent:IsA("Attachment") then return parent.WorldPosition end
    return nil
end

local function ApplyFast(p)
    if not InstantSteal or not IsStealPrompt(p) then return end
    if OriginalHold[p] == nil then OriginalHold[p] = p.HoldDuration end
    if p.HoldDuration ~= 0.1 then p.HoldDuration = 0.1 end
end

local function ApplyFastToAll()
    for _, holder in ipairs(workspace:GetChildren()) do
        if holder.Name == "SmartPromptPart" then
            for _, p in ipairs(holder:GetChildren()) do
                if p:IsA("ProximityPrompt") then ApplyFast(p) end
            end
        end
    end
end

local function RestoreHolds()
    for p, old in pairs(OriginalHold) do
        if p and p.Parent then pcall(function() p.HoldDuration = old end) end
        OriginalHold[p] = nil
    end
end

--==============================================================
-- DIRECT REMOTES (the game's own steal / drop calls - from your spy log)
--==============================================================

-- FirstArea eggs (your own base nests) need the slot key, world eggs just the Uid.
local function CarryArgs(rec)
    if type(rec.Uid) == "string" and string.find(rec.Uid, "FirstAreaEgg_", 1, true) == 1 then
        return { Uid = rec.Uid, FirstAreaSlotKey = tostring(rec.AreaId) .. ":" .. tostring(rec.NestId) }
    end
    return { Uid = rec.Uid }
end

-- returns ok, err (never throws)
local function CarryEggRemote(rec)
    local rf = Net("RF/EggWorld/AskFieldEggCarry")
    if not rf or not rf:IsA("RemoteFunction") then
        return false, "AskFieldEggCarry not found"
    end
    local ok, a, b = pcall(function() return rf:InvokeServer(CarryArgs(rec)) end)
    if not ok then return false, tostring(a) end
    if a ~= true then
        if type(b) ~= "string" then b = "denied" end
        return false, b
    end
    return true, nil
end

local function DropEggRemote()
    local rf = Net("RF/EggWorld/AskFieldEggDrop")
    if not rf or not rf:IsA("RemoteFunction") then
        return false, "AskFieldEggDrop not found"
    end
    local ok, a, b = pcall(function() return rf:InvokeServer({ Reason = "PlayerRequest" }) end)
    if not ok then return false, tostring(a) end
    if a ~= true then
        if type(b) ~= "string" then b = "denied" end
        return false, b
    end
    return true, nil
end

--==============================================================
-- WORLD POINTS
--==============================================================

local function PositionOfObj(obj)
    if not obj then return nil end
    if obj:IsA("BasePart") then return obj.Position end
    if obj:IsA("Attachment") then return obj.WorldPosition end
    if obj:IsA("Model") then
        local ok, cf = pcall(function() return obj:GetPivot() end)
        if ok then return cf.Position end
    end
    return nil
end

local function GetGuardAreas()
    local ok, folder = pcall(function() return workspace.World.Areas.GuardAreas end)
    return ok and folder or nil
end

local function AreaDropPoint(areas, name)
    if not areas then return nil end
    local area = areas:FindFirstChild(name)
    if not area then return nil end
    local guard = area:FindFirstChild("Guard")
    local point = guard and (guard:FindFirstChild("EggPoint") or guard:FindFirstChild("HumanoidRootPart"))
    if point then return point, area end
    local sign = area:FindFirstChild("RequiredSpeedSign")
    local support = sign and (sign:FindFirstChild("Support") or sign:FindFirstChild("Main"))
    if support then return support, area end
    return nil, area
end

-- The Forest guard's EggPoint: the weakest guard in the game, and the closest drop
-- spot to the SafeZone. Falls back to the sign, then to Lake, then to any area.
local function DropPointPos()
    local areas = GetGuardAreas()
    if not areas then return nil, nil end

    if Strategy == "Nearest Area Drop" then
        local r = Root()
        local best, bestDist, bestName
        for _, area in ipairs(areas:GetChildren()) do
            local point = AreaDropPoint(areas, area.Name)
            local pos = point and PositionOfObj(point)
            if pos and r then
                local d = (pos - r.Position).Magnitude
                if not bestDist or d < bestDist then best, bestDist, bestName = pos, d, area.Name end
            end
        end
        return best, bestName
    end

    local primary = (Strategy == "Direct Flight Home") and nil or "Forest"
    if primary then
        local point = AreaDropPoint(areas, primary)
        local pos = point and PositionOfObj(point)
        if pos then return pos, primary end
        Log("Forest EggPoint not found; trying Lake.")
        point = AreaDropPoint(areas, "Lake")
        pos = point and PositionOfObj(point)
        if pos then return pos, "Lake" end
    end
    return nil, nil
end

-- Where "home" is: spawn (inside the SafeZone footprint - carrying the egg here
-- redeems it). Your plot's SpawnPoint is the deeper fallback.
local function HomePoint()
    local spawn = workspace:FindFirstChild("SpawnLocation")
    if spawn and spawn:IsA("BasePart") then
        return spawn.Position + Vector3.new(0, 3, 0)
    end
    local r = Root()
    if r then return r.Position end
    return Vector3.new(512, 71, -362)
end

local function PlotSpawnPoint()
    local plots = workspace:FindFirstChild("Plots")
    if not plots then return nil end
    for _, plot in ipairs(plots:GetChildren()) do
        local sign = plot:FindFirstChild("PlotSign")
        if sign and sign:FindFirstChild("YourBase", true) then
            local sp = plot:FindFirstChild("SpawnPoint")
            local pos = sp and PositionOfObj(sp)
            if pos then return pos + Vector3.new(0, 3, 0) end
        end
    end
    return nil
end

local function GetMyPlot()
    local plots = workspace:FindFirstChild("Plots")
    if not plots then return nil end

    -- 1) your own sign carries the "YourBase" billboard (client-side marker)
    for _, plot in ipairs(plots:GetChildren()) do
        local sign = plot:FindFirstChild("PlotSign")
        if sign and sign:FindFirstChild("YourBase", true) then return plot end
    end

    -- 2) sign label shows your name
    local n1, n2 = Lower(LocalPlayer.Name), Lower(LocalPlayer.DisplayName)
    for _, plot in ipairs(plots:GetChildren()) do
        local sign = plot:FindFirstChild("PlotSign")
        local label = sign and sign:FindFirstChild("PlayerName", true)
        if label and label:IsA("TextLabel") then
            local t = Lower(label.Text)
            if t == n1 or t == n2 then return plot end
        end
    end

    -- 3) this model only exists in your own plot
    for _, plot in ipairs(plots:GetChildren()) do
        if plot:FindFirstChild("LocalOfflineMoneyClaim") then return plot end
    end
    return nil
end

local function GetTreadmillSpot()
    local plot = GetMyPlot()
    local part = plot and plot:FindFirstChild("TreadmillBottom")
    if part and part:IsA("BasePart") then
        return part.Position + Vector3.new(0, 3.1, 0)
    end
    return nil
end

--==============================================================
-- LIVE EGG DATA (passive listeners, connected only when needed)
--==============================================================

local ListenersOn = false
local DeliverPhase   -- forward declared (used by the Instant Steal prompt hook)
local UidAtPos       -- forward declared

local function IngestEgg(rec, depth)
    if type(rec) ~= "table" or (depth or 0) > 3 then return end
    if type(rec.Uid) == "string" then
        local isNew = Eggs[rec.Uid] == nil
        Eggs[rec.Uid] = rec
        EggSeenAt[rec.Uid] = os.clock()
        if tonumber(rec.CarrierUserId) == LocalPlayer.UserId then
            CarriedUid, CarriedUidAt = rec.Uid, os.clock()
        end
        if rec.State == "Slot" then
            local np = EggPosition(rec)
            if np then NestPos[rec.Uid] = np end
        end
        pcall(OnEggSeen, rec, isNew)
        return
    end
    for _, v in pairs(rec) do
        if type(v) == "table" then IngestEgg(v, (depth or 0) + 1) end
    end
end

local function StripRichText(s)
    return tostring(s or ""):gsub("<[^>]->", "")
end

local function EnsureListeners()
    if ListenersOn then return end
    ListenersOn = true

    local render = Net("RE/Treadmill/RenderStateShifted")
    if render then
        Track(render.OnClientEvent:Connect(function(plr, worn)
            if plr == LocalPlayer then Worn = worn == true end
        end))
    end

    local carry = Net("RE/EggWorld/FieldEggCarry")
    if carry then
        Track(carry.OnClientEvent:Connect(function(data)
            if type(data) ~= "table" then return end
            Carrying = data.IsCarrying == true
            if Carrying and type(data.Uid) == "string" then
                CarriedUid, CarriedUidAt = data.Uid, os.clock()
            end
        end))
    end

    local shifted = Net("RE/EggWorld/FieldEggShifted")
    if shifted then Track(shifted.OnClientEvent:Connect(function(rec) IngestEgg(rec, 0) end)) end

    local batch = Net("RE/EggWorld/FieldEggBatchShifted")
    if batch then
        Track(batch.OnClientEvent:Connect(function(data)
            if type(data) ~= "table" then return end
            if type(data.UpdatedRecords) == "table" then
                for _, rec in ipairs(data.UpdatedRecords) do IngestEgg(rec, 0) end
            end
            if type(data.RemovedUids) == "table" then
                for _, uid in ipairs(data.RemovedUids) do
                    if type(uid) == "string" then Eggs[uid] = nil end
                end
            end
        end))
    end

    -- the egg you carried made it into your inventory
    local verdict = Net("RE/EggWorld/FieldEggRedeemVerdict")
    if verdict then
        Track(verdict.OnClientEvent:Connect(function(data)
            if type(data) == "table" then
                LastVerdict, LastVerdictAt = data, os.clock()
                SessionStats.redeemed += 1
                Log(string.format("REDEEMED: %s (%s)", tostring(data.DisplayName), tostring(data.Rarity)))
            end
        end))
    end

    -- your owned egg records (for Auto Place / Auto Hatch)
    local owner = Net("RE/EggWorld/OwnerShifted")
    if owner then
        Track(owner.OnClientEvent:Connect(function(data)
            if type(data) == "table" and tonumber(data.OwnerUserId) == LocalPlayer.UserId
                and type(data.Records) == "table" then
                MyEggRecords = data.Records
            end
        end))
    end

    local gone = Net("RE/EggWorld/FieldEggGone")
    if gone then
        Track(gone.OnClientEvent:Connect(function(uid)
            if type(uid) == "string" then
                Eggs[uid] = nil
                if CarriedUid == uid then CarriedUid = nil end
            end
        end))
    end

    -- the server's own rare-spawn announcements ("A Secret ... spawned in ...!")
    local shown = Net("RE/EggWorld/FieldEggRaritiesShown")
    if shown then
        Track(shown.OnClientEvent:Connect(function(data)
            if not RareSpawnAlert or type(data) ~= "table" then return end
            local spawns = type(data.RareSpawns) == "table" and data.RareSpawns or {}
            for _, entry in ipairs(spawns) do
                if type(entry) == "table" then
                    Notify("Rare Spawn", StripRichText(entry.Message), "success", 6)
                    Log("RARE SPAWN: " .. StripRichText(entry.Message))
                end
            end
        end))
    end

    Track(ProximityPromptService.PromptTriggered:Connect(function(prompt, plr)
        if plr ~= LocalPlayer then return end
        LastTriggered = os.clock()

        -- Instant Steal: you clicked Steal; the game asks the server itself, then we
        -- take over and fly the egg home (Forest drop -> re-steal -> spawn).
        if InstantSteal and not Busy and IsStealPrompt(prompt) then
            Busy = true
            local id = NewJob()
            local origin = PromptPosition(prompt)
            task.spawn(function()
                local ok, err = pcall(function()
                    if not WaitForCarry(2.5, id) then
                        Notify("Instant Steal", "The steal did not register (satchel full?).", "warning", 4)
                        return
                    end
                    local uid = CarriedUid or (origin and UidAtPos(origin, 14))
                    SessionStats.stolen += 1
                    DeliverPhase(id, uid, origin)
                end)
                if not ok then Notify("Steal", "Workflow error: " .. tostring(err), "error", 5) end
                CamRelease()
                EndFlight()
                Busy = false
            end)
        end
    end))

    -- Instant Steal: shorten hold time on prompts as they appear
    Track(ProximityPromptService.PromptShown:Connect(function(prompt)
        if InstantSteal then ApplyFast(prompt) end
    end))
end

local function RefreshSnapshot()
    local rf = Net("RF/EggWorld/AskFieldEggSnapshot")
    if not rf or not rf:IsA("RemoteFunction") then return false end
    local ok, result = pcall(function() return rf:InvokeServer() end)
    if ok then IngestEgg(result, 0) end
    return ok
end

--==============================================================
-- RARITY (live from the game's own asset catalog)
--==============================================================

local RarityRanks = {}
local AssetDirectory = nil

pcall(function()
    local assets = require(ReplicatedStorage.Data.Assets)
    if type(assets) == "table" and type(assets.Directory) == "table" then
        AssetDirectory = assets.Directory
    end
end)
pcall(function()
    local rarities = require(ReplicatedStorage.Data.Rarity)
    if type(rarities) == "table" and type(rarities.Rarities) == "table" then
        for name, cfg in pairs(rarities.Rarities) do
            if type(cfg) == "table" and type(cfg.Rank) == "number" then
                RarityRanks[name] = cfg.Rank
            end
        end
    end
end)
if next(RarityRanks) == nil then
    RarityRanks = table.clone(FALLBACK_RANKS)
end

local function RankOf(name)
    return RarityRanks[name] or FALLBACK_RANKS[name] or 0
end

-- returns rarity id (or nil)
local function ResolveRarity(rec)
    local cat = rec.AssetCategory
    if type(cat) ~= "string" or cat == "" then return nil end
    if RarityCache[cat] then return RarityCache[cat] end

    local found = nil
    if AssetDirectory then
        local entry = AssetDirectory[cat]
        local rar = type(entry) == "table" and entry.Rarity
        if type(rar) == "table" and type(rar._id) == "string" then
            found = rar._id
        end
    end
    if not found then
        local n = Lower(cat)
        for _, pair in ipairs(NAME_RARITY_FALLBACK) do
            if string.find(n, pair[1], 1, true) then found = pair[2]; break end
        end
    end
    if found == "Prismatic" then found = "Rainbow" end
    if found then RarityCache[cat] = found end
    return found
end

DescribeEgg = function(rec)
    local rarity = ResolveRarity(rec)
    return string.format("%s | %s | %s", tostring(rec.AssetCategory), tostring(rec.AreaId), rarity or "rarity?")
end

local function MySpeed()
    local ls = LocalPlayer:FindFirstChild("leaderstats")
    local sp = ls and ls:FindFirstChild("Speed")
    return sp and tonumber(sp.Value) or 0
end

-- guard danger read live from the area's GuardEscapeSpeeds attribute (Vector2: need, run)
GuardDanger = function(area)
    if type(area) ~= "string" then return false end
    local need
    local ok, areas = pcall(function() return workspace.World.Areas.GuardAreas end)
    if ok and areas then
        local model = areas:FindFirstChild(area)
        local attr = model and model:GetAttribute("GuardEscapeSpeeds")
        if typeof(attr) == "Vector2" then need = attr.X end
    end
    if not need then
        local g = GUARD[area]
        need = g and g.need
    end
    return need ~= nil and MySpeed() < need
end

--==============================================================
-- EGG FILTERS / SELECTION
--==============================================================

local function Norm(text)
    return (Lower(text):gsub("[%s_%-]", ""))
end

local function SetSize(set)
    local n = 0
    for _ in pairs(set) do n += 1 end
    return n
end

local function RarityFilterOn()
    local n = SetSize(SelectedRarities)
    return n > 0 and n < #RARITY_LIST
end

local function BiomeFilterOn()
    local n = SetSize(SelectedBiomes)
    return n > 0 and n < #BIOMES
end

EggPosition = function(rec)
    local cf = rec.BottomCFrame or rec.BoundsCFrame
    if typeof(cf) == "CFrame" then return cf.Position end
    return nil
end

-- returns egg-info or nil, plus a reason string
local function EvaluateEgg(rec)
    local state = rec.State
    if state ~= nil and state ~= "Slot" and state ~= "Dropped" then return nil, "state " .. tostring(state) end

    local pos = EggPosition(rec)
    if not pos then return nil, "no position" end

    local rarity = ResolveRarity(rec)

    if RarityFilterOn() then
        if rarity then
            if not SelectedRarities[rarity] then return nil, "rarity " .. rarity end
        elseif not AllowUnknownRarity then
            return nil, "rarity unknown"
        end
    end

    if BiomeFilterOn() and not SelectedBiomes[Norm(rec.AreaId)] then
        return nil, "biome " .. tostring(rec.AreaId)
    end

    if SkipDangerous and GuardDanger(tostring(rec.AreaId)) then
        return nil, "guard too strong"
    end

    return {
        Uid = rec.Uid, Pos = pos, Rarity = rarity, Rank = rarity and RankOf(rarity) or 0,
        Area = tostring(rec.AreaId), Category = tostring(rec.AssetCategory),
        Size = tonumber(rec.AssetScale) or 0,
    }, "ok"
end

local function PickBestEgg()
    local r = Root()
    if not r then return nil end

    local best, count = nil, 0
    for uid, rec in pairs(Eggs) do
        if (AttemptedUntil[uid] or 0) < os.clock() then
            local e = EvaluateEgg(rec)
            if e then
                count += 1
                e.Dist = (e.Pos - r.Position).Magnitude
                local better
                if not best then
                    better = true
                elseif Priority == "Nearest" then
                    better = e.Dist < best.Dist
                elseif Priority == "Biggest Size" then
                    better = e.Size > best.Size or (e.Size == best.Size and e.Dist < best.Dist)
                else
                    better = e.Rank > best.Rank or (e.Rank == best.Rank and e.Dist < best.Dist)
                end
                if better then best = e end
            end
        end
    end
    return best, count
end

Log = function(text, color)
    if ScanLog then pcall(function() ScanLog:Add(text, color) end) end
end

local function JoinCounts(t)
    local parts = {}
    for k, v in pairs(t) do table.insert(parts, tostring(k) .. "=" .. tostring(v)) end
    table.sort(parts)
    return #parts > 0 and table.concat(parts, ", ") or "-"
end

local function RunScan()
    EnsureListeners()
    RefreshSnapshot()

    local total, passed = 0, 0
    local states, reasons, samples = {}, {}, {}

    for _, rec in pairs(Eggs) do
        total += 1
        local st = tostring(rec.State)
        states[st] = (states[st] or 0) + 1

        local egg, reason = EvaluateEgg(rec)
        if egg then passed += 1 else reasons[reason] = (reasons[reason] or 0) + 1 end

        if #samples < 8 then
            table.insert(samples, string.format("%s | %s | %s | %s | %s",
                tostring(rec.AssetCategory), tostring(rec.AreaId), st,
                egg and "MATCH" or reason,
                GuardDanger(tostring(rec.AreaId)) and "guard chases" or "guard safe"))
        end
    end

    local head = string.format("%d tracked, %d match", total, passed)
    Log("---- Scan: " .. head)
    Log("my speed stat: " .. tostring(MySpeed()))
    Log("states: " .. JoinCounts(states))
    Log("skipped: " .. JoinCounts(reasons))
    for _, line in ipairs(samples) do Log(line) end

    Notify("Scan", head, passed > 0 and "success" or "warning", 5)
end

OnEggSeen = function(rec, isNew)
    if not EggAlert or not isNew or rec.State ~= "Slot" then return end
    local egg = EvaluateEgg(rec)
    if egg then
        Notify("Egg Alert", string.format("%s · %s · %s", egg.Rarity or "?", egg.Category, egg.Area), "success", 5)
    end
end

-- which egg is at a position (used when a manual steal prompt fires)
UidAtPos = function(pos, maxDist)
    local bestUid, bestDist = nil, maxDist or 8
    local flat = Vector3.new(pos.X, 0, pos.Z)
    for uid, rec in pairs(Eggs) do
        local p = NestPos[uid] or EggPosition(rec)
        if p then
            local d = (Vector3.new(p.X, 0, p.Z) - flat).Magnitude
            if d < bestDist then bestUid, bestDist = uid, d end
        end
    end
    return bestUid
end

-- wait until a ragdoll / knock-down is over (after a guard hit)
local function WaitStable(id, extra)
    local t0 = os.clock()
    while os.clock() - t0 < 4 do
        if Cancelled(id) then return end
        local h, r = Hum(), Root()
        if not h or not r then return end
        local st = h:GetState()
        local down = h.PlatformStand or st == Enum.HumanoidStateType.Ragdoll
            or st == Enum.HumanoidStateType.FallingDown or st == Enum.HumanoidStateType.Physics
            or r.AssemblyLinearVelocity.Magnitude > 150
        if not down then break end
        task.wait(0.1)
    end
    task.wait(extra or 0.2)
end

--==============================================================
-- STEAL WORKFLOW (flight + direct remotes)
--   TryCarry      : fly to the egg (live position) and steal it via the remote
--   DeliverPhase  : fly it home - optionally dropping at the Forest EggPoint first,
--                   re-stealing, then crossing into the SafeZone (redeem)
--==============================================================

-- fly to the egg's current position and steal it. true, or false + reason
local function TryCarry(uid, id)
    WaitStable(id, 0.2)

    local lastErr = "no record"
    for attempt = 1, 4 do
        if Cancelled(id) then return false, "cancelled" end

        local rec = Eggs[uid]
        if rec == nil then return false, "egg gone" end
        local pos = EggPosition(rec) or NestPos[uid]
        if not pos then return false, "no position" end

        CamLock(pos)
        local ok = FlyTo(pos, id, { HoverY = 3 })
        CamRelease()
        if Cancelled(id) then return false, "cancelled" end
        if ok then
            -- ask the server; retry a few times, re-approaching if it moved
            for _ = 1, 6 do
                if Cancelled(id) then return false, "cancelled" end
                local r2 = Eggs[uid]
                if r2 == nil then return false, "egg gone" end
                local carried, err = CarryEggRemote(r2)
                if carried and WaitForCarry(0.8, id) then
                    SessionStats.stolen += 1
                    return true
                end
                lastErr = err or lastErr
                if string.find(Lower(lastErr), "satchel") then
                    PauseUntil = os.clock() + 15
                    return false, "satchel full"
                end
                local p2 = EggPosition(r2)
                if p2 and (p2 - pos).Magnitude > 6 then
                    pos = p2
                    FlyTo(p2, id, { HoverY = 3 })
                else
                    task.wait(0.15)
                end
            end
        else
            lastErr = "could not reach the egg"
        end
        task.wait(0.2)
    end
    return false, lastErr
end

-- after the drop at the Forest EggPoint: take the dropped egg back before the guard
-- carries it away. true, or false + reason
local function ReStealAtDrop(uid, id)
    local t0 = os.clock()
    while os.clock() - t0 < 6 do
        if Cancelled(id) then return false, "cancelled" end

        local rec = Eggs[uid]
        if rec == nil then return false, "egg gone" end

        if rec.State == "GuardCarried" then
            -- the guard got it: recovery will chase the guard's live position
            Log("The guard picked the egg up.")
            return false, "guard has it"
        end

        local carried, err = CarryEggRemote(rec)
        if carried and WaitForCarry(0.6, id) then
            Log("Re-stole the egg.")
            return true
        end
        if err and string.find(Lower(err), "satchel") then
            PauseUntil = os.clock() + 15
            return false, "satchel full"
        end
        task.wait(0.15)
    end
    return false, "re-steal window passed"
end

-- wait for the SafeZone redeem (FieldEggGone / RedeemVerdict). "redeemed" | "lost" | "still"
local function WaitRedeemed(id, uid, started)
    local function check()
        if LastVerdictAt >= started then return "redeemed" end
        local rec = uid and Eggs[uid]
        if uid and rec == nil then return "redeemed" end
        if rec and rec.State == "Claimed" then return "redeemed" end
        if not IsCarryingNow() then
            if rec == nil then return "redeemed" end
            if rec.State ~= "Carried" or tonumber(rec.CarrierUserId) ~= LocalPlayer.UserId then
                return "lost"
            end
        end
        return nil
    end

    local t0 = os.clock()
    while os.clock() - t0 < 8 do
        if Cancelled(id) then return "cancelled" end
        local v = check()
        if v then return v end
        task.wait(0.1)
    end

    -- still carrying? fly deeper into the safe zone (your plot) and wait again
    local plot = PlotSpawnPoint()
    if plot then
        FlyTo(plot, id, { MustCarry = true, Offset = 12 })
        local t1 = os.clock()
        while os.clock() - t1 < 4 do
            if Cancelled(id) then return "cancelled" end
            local v = check()
            if v then return v end
            task.wait(0.1)
        end
    end

    if not IsCarryingNow() then return "redeemed" end
    Log("WARNING: still carrying at home - the redeem did not trigger.")
    return "still"
end

-- You are carrying. Fly it home. Returns "redeemed" | "lost" | "cancelled" | "failed".
local function DeliverCarriedHome(id, uid, started)
    SetStatus("Flying home")
    local ok, why = FlyTo(HomePoint(), id, { MustCarry = true })
    if not ok then
        if why == "lost" then return "lost" end
        if why == "cancelled" then return "cancelled" end
        return "failed"
    end
    SetStatus("Waiting for the redeem")
    return WaitRedeemed(id, uid, started)
end

DeliverPhase = function(id, uid, originHint)
    local started = os.clock()
    local recoveries = 0

    while true do
        if Cancelled(id) then return "cancelled" end
        if not IsCarryingNow() then return "lost" end

        local rec = uid and Eggs[uid]
        if rec then
            Log("Carrying: " .. DescribeEgg(rec))
            SetStatus("Carrying " .. tostring(rec.AssetCategory))
        end

        -- strategy: stop at the Forest EggPoint, drop, re-steal, then fly home.
        -- the Forest guard is the weakest in the game and can never catch you, and
        -- the EggPoint is the closest drop spot to the SafeZone.
        local dropPos, dropName = DropPointPos()

        if Strategy == "Direct Flight Home" or not dropPos then
            local res = DeliverCarriedHome(id, uid, started)
            if res == "lost" or res == "redeemed" or res == "cancelled" or res == "still" then return res end
            return res
        end

        SetStatus("Flying to the " .. tostring(dropName) .. " drop point")
        local ok, why = FlyTo(dropPos, id, { MustCarry = true })
        if not ok then
            if why == "lost" then
                Log("The egg was taken from me on the way.")
            elseif why == "cancelled" then
                return "cancelled"
            else
                Log("Could not reach the drop point (" .. tostring(why) .. "); flying home directly.")
                local res = DeliverCarriedHome(id, uid, started)
                if res ~= "failed" then return res end
            end
        else
            if CFG.StopDelay > 0 then task.wait(CFG.StopDelay) end
            if Cancelled(id) then return "cancelled" end
            if not IsCarryingNow() then
                Log("The egg left me at the drop point.")
            else
                SetStatus("Dropping")
                local dropped, derr = DropEggRemote()
                if not dropped then
                    dropped, derr = DropEggRemote()
                end
                if not WaitFor(function() return not IsCarryingNow() end, 1.2, id, 0.05) then
                    if not IsCarryingNow() then
                        Log("Dropped (late confirmation).")
                    else
                        Log("Drop not confirmed (" .. tostring(derr) .. ").")
                        return "failed"
                    end
                else
                    Log("Dropped at the " .. tostring(dropName) .. " EggPoint.")
                end

                if not ReStealAtDrop(uid, id) and not IsCarryingNow() then
                    Log("Re-steal failed; going to recovery.")
                end
            end
        end

        if IsCarryingNow() then
            local res = DeliverCarriedHome(id, uid, started)
            if res == "redeemed" or res == "cancelled" or res == "still" then return res end
            if res ~= "lost" then return res end
        end

        -- the egg is gone from us: go back for it
        recoveries += 1
        if recoveries > CFG.MaxRecoveries then
            return "lost"
        end
        SessionStats.recovered += 1
        Log("Recovery " .. recoveries .. " of " .. CFG.MaxRecoveries)
        SetStatus("Going back for the egg")

        WaitStable(id, 0.5)
        local carried, err = TryCarry(uid, id)
        if not carried then
            Log("Could not take the egg back: " .. tostring(err))
            return "lost"
        end
    end
end

-- full cycle: pick target is done by the caller; fly there, steal, deliver.
-- returns true, "redeemed"/"gone" | false, reason
local function RunStealCycle(id, egg)
    AttemptedUntil[egg.Uid] = os.clock() + 30
    local uid = egg.Uid

    Log(string.format("Target: %s | %s | %s%s", egg.Category, egg.Area, egg.Rarity or "rarity?",
        GuardDanger(egg.Area) and " | guard will chase" or ""))
    Notify("Steal", string.format("%s · %s · %s", egg.Rarity or "?", egg.Category, egg.Area), "info", 3)

    -- Phase 1: approach and steal
    local carried, err = TryCarry(uid, id)
    if not carried then
        return false, err
    end
    Log("Stole the egg.")

    -- Phase 2: deliver (with recovery)
    local res = DeliverPhase(id, uid, egg.Pos)
    if res == "redeemed" or res == "still" then
        SetStatus(string.format("Done (redeemed %d this session)", SessionStats.redeemed))
        if LastVerdict and LastVerdictAt >= (os.clock() - 12) then
            Notify("Steal", string.format("Redeemed: %s (%s)",
                tostring(LastVerdict.DisplayName), tostring(LastVerdict.Rarity)), "success", 5)
        else
            Notify("Steal", "Cycle complete.", "success", 3)
        end
        return true, res
    end
    return false, res
end

--==============================================================
-- AUTO STEAL LOOP + TREADMILL LOOP
--==============================================================

local GetOffTreadmillSafe, GoToTreadmill, DesiredWalkSpeedSafe  -- forward declared

local LoopStarted = false

local function StartLoop()
    if LoopStarted then return end
    LoopStarted = true

    task.spawn(function()
        while not Unloaded do
            task.wait(0.5)
            if Unloaded then break end
            if Busy or os.clock() < PauseUntil then continue end
            if not Root() then continue end

            -- 1) filtered auto steal
            if AutoSteal then
                if IsCarryingNow() then
                    -- already holding something: deliver it before taking more
                    Busy = true
                    local id = NewJob()
                    local ok, err = pcall(DeliverPhase, id, CarriedUid, nil)
                    if not ok then Notify("Auto Steal", "Error: " .. tostring(err), "error", 4) end
                    CamRelease(); EndFlight(); Busy = false
                    continue
                end
                local egg = PickBestEgg()
                if egg then
                    Busy = true
                    local id = NewJob()
                    GetOffTreadmillSafe()
                    local ok, result, why = pcall(RunStealCycle, id, egg)
                    if not ok then Notify("Auto Steal", "Error: " .. tostring(result), "error", 4) end
                    CamRelease(); EndFlight(); Busy = false
                    continue
                end
            end

            -- 2) treadmill: fly there, wear it, stay; come back if you leave
            if AutoTreadmill then
                local spot = GetTreadmillSpot()
                local r = Root()
                local away = spot and r and (r.Position - spot).Magnitude > 8
                if (not Worn or away) and os.clock() >= TreadmillRetryAt then
                    Busy = true
                    local id = NewJob()
                    local ok, result = pcall(GoToTreadmill, id)
                    if not ok or result ~= true then TreadmillRetryAt = os.clock() + 6 end
                    EndFlight()
                    Busy = false
                elseif AutoSteal then
                    SetStatus("On treadmill, waiting for a matching egg")
                end
            elseif AutoSteal then
                SetStatus("Scanning for matching eggs")
            end
        end
    end)
end

local function CancelAll(reason)
    Job += 1
    EndFlight()
    CamRelease()
    Busy = false
    SpeedOverride = false
    local h = Hum()
    if h and h.Parent then h.WalkSpeed = DesiredWalkSpeedSafe() end
    if reason then SetStatus(reason) end
end

--==============================================================
-- TREADMILL (your own plot only, reached by flight)
--==============================================================

local function GetOffTreadmill()
    if not Worn then return end
    local rf = Net("RF/Treadmill/AskDoff")
    if rf and rf:IsA("RemoteFunction") then
        pcall(function() rf:InvokeServer() end)
    end
    Worn = false
end

GetOffTreadmillSafe = function()
    pcall(GetOffTreadmill)
end

GoToTreadmill = function(id)
    local spot = GetTreadmillSpot()
    if not spot then
        Notify("Auto Treadmill", "Could not find your plot/treadmill.", "error", 4)
        return false
    end

    SetStatus("Flying to your treadmill")
    if not FlyTo(spot, id, { HoverY = 3.1 }) then return false end
    task.wait(0.4)
    if Cancelled(id) then return false end

    local rf = Net("RF/Treadmill/AskWearStill")
    if not rf or not rf:IsA("RemoteFunction") then
        Notify("Auto Treadmill", "RF/Treadmill/AskWearStill not found.", "error", 4)
        return false
    end

    local ok, result = pcall(function() return rf:InvokeServer() end)
    if not ok then
        Notify("Auto Treadmill", "AskWearStill failed: " .. tostring(result), "error", 4)
        return false
    end

    Worn = true
    SetStatus("On treadmill, waiting")
    return true
end

--==============================================================
-- PLAYER FEATURES
--==============================================================

DesiredWalkSpeedSafe = function()
    return SpeedAdjust and CFG.PlayerSpeed or 16
end

local function ApplySpeed()
    local h = Hum()
    if h and not SpeedOverride then h.WalkSpeed = DesiredWalkSpeedSafe() end
end

-- Anti Ragdoll (also stops knockback/flinging): several layers, because the game's
-- bats, monsters and traps can push you in different ways.
local BAD_MOVERS = {
    "BodyVelocity", "BodyForce", "BodyAngularVelocity", "BodyThrust", "RocketPropulsion",
    "LinearVelocity", "VectorForce", "AngularVelocity", "Torque", "BallSocketConstraint",
}

local function IsBadMover(inst)
    for _, className in ipairs(BAD_MOVERS) do
        if inst:IsA(className) then return true end
    end
    return false
end

local RagdollAddedConn

local function SetRagdollStates(h, enabled)
    for _, st in ipairs({ Enum.HumanoidStateType.Ragdoll, Enum.HumanoidStateType.FallingDown }) do
        pcall(function() h:SetStateEnabled(st, enabled) end)
    end
end

local function CleanCharacter(c)
    for _, d in ipairs(c:GetDescendants()) do
        if IsBadMover(d) then
            pcall(function() d:Destroy() end)
        elseif d:IsA("Motor6D") and not d.Enabled then
            pcall(function() d.Enabled = true end)
        end
    end
end

local function HookRagdoll()
    if RagdollAddedConn then RagdollAddedConn:Disconnect(); RagdollAddedConn = nil end
    local c = Char()
    if not c then return end
    local h = Hum()
    if h then SetRagdollStates(h, false) end
    CleanCharacter(c)
    RagdollAddedConn = c.DescendantAdded:Connect(function(d)
        if AntiRagdoll and IsBadMover(d) then
            task.defer(function() pcall(function() d:Destroy() end) end)
        end
    end)
end

local function SetAntiRagdoll(on)
    AntiRagdoll = on
    if on then
        HookRagdoll()
    else
        if RagdollAddedConn then RagdollAddedConn:Disconnect(); RagdollAddedConn = nil end
        local h = Hum()
        if h then SetRagdollStates(h, true) end
    end
end

Track(RunService.Heartbeat:Connect(function()
    -- everything here is a no-op until you switch the matching toggle on
    if CamLocked and CamCFrame then
        local cam = workspace.CurrentCamera
        if cam then
            if cam.CameraType ~= Enum.CameraType.Scriptable then cam.CameraType = Enum.CameraType.Scriptable end
            cam.CFrame = CamCFrame
        end
    end

    if SpeedAdjust and not SpeedOverride then
        local h = Hum()
        if h and h.WalkSpeed ~= CFG.PlayerSpeed then h.WalkSpeed = CFG.PlayerSpeed end
    end

    if AntiRagdoll then
        local h, r = Hum(), Root()
        if h and r then
            local st = h:GetState()
            if st == Enum.HumanoidStateType.Ragdoll or st == Enum.HumanoidStateType.FallingDown
                or st == Enum.HumanoidStateType.Physics then
                h:ChangeState(Enum.HumanoidStateType.GettingUp)
            end
            if h.PlatformStand then h.PlatformStand = false end

            -- the script's own flights are skipped
            if not Busy and not Flying then
                local v = r.AssemblyLinearVelocity
                local limit = math.max(150, h.WalkSpeed * 1.5)
                local flat = Vector3.new(v.X, 0, v.Z)
                if flat.Magnitude > limit then
                    local dir = flat.Unit
                    r.AssemblyLinearVelocity = Vector3.new(dir.X * limit, math.min(v.Y, 60), dir.Z * limit)
                elseif v.Y > 90 then
                    r.AssemblyLinearVelocity = Vector3.new(v.X, 0, v.Z)
                end
                if r.AssemblyAngularVelocity.Magnitude > 25 then
                    r.AssemblyAngularVelocity = Vector3.zero
                end
            end
        end
    end
end))

Track(RunService.Stepped:Connect(function()
    local noclipNow = Noclip or (FlightNoclip and Flying)
    if noclipNow then
        local c = Char()
        if c then
            for _, part in ipairs(c:GetChildren()) do
                if part:IsA("BasePart") and part.CanCollide then part.CanCollide = false end
            end
        end
    elseif not Noclip and not Flying then
        -- restore collisions once after a flight ends
        local c = Char()
        if c and c:GetAttribute("__RHRestoreCol") then
            c:SetAttribute("__RHRestoreCol", nil)
            for _, part in ipairs(c:GetChildren()) do
                if part:IsA("BasePart") and not part:IsA("HumanoidRootPart") then
                    pcall(function() part.CanCollide = true end)
                end
            end
        end
    end
    if Flying then
        local c = Char()
        if c and not c:GetAttribute("__RHRestoreCol") then
            c:SetAttribute("__RHRestoreCol", true)
        end
    end

    -- other players can't push you: their bodies stop colliding with yours
    if AntiRagdoll then
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= LocalPlayer and plr.Character then
                for _, part in ipairs(plr.Character:GetChildren()) do
                    if part:IsA("BasePart") and part.CanCollide then part.CanCollide = false end
                end
            end
        end
    end
end))

Track(UserInputService.JumpRequest:Connect(function()
    if InfiniteJump then
        local h = Hum()
        if h then h:ChangeState(Enum.HumanoidStateType.Jumping) end
    end
end))

Track(LocalPlayer.CharacterAdded:Connect(function()
    CamRelease()
    Worn = false
    Carrying = false
    Busy = false
    Flying = false
    Job += 1
    SpeedOverride = false
    task.wait(1)
    ApplySpeed()
    if AntiRagdoll then HookRagdoll() end
end))

-- Anti AFK (connected only while its toggle is on)
local AntiAfkConn
local function SetAntiAfk(on)
    if on and not AntiAfkConn then
        AntiAfkConn = LocalPlayer.Idled:Connect(function()
            pcall(function()
                local vu = game:GetService("VirtualUser")
                vu:CaptureController()
                vu:ClickButton2(Vector2.new())
            end)
        end)
    elseif not on and AntiAfkConn then
        AntiAfkConn:Disconnect()
        AntiAfkConn = nil
    end
end

-- Auto Execute: re-runs this script (from your hosted URL) in the next server
local AutoExecuteOn = false
local QueuedThisSession = false
local OnTeleportConn, TeleportFailConn

local function QueueAutoExecute()
    if QueuedThisSession then return true end
    local queue = queue_on_teleport or (syn and syn.queue_on_teleport) or (fluxus and fluxus.queue_on_teleport)
    if not queue then
        Notify("Auto Execute", "Your executor has no queue_on_teleport.", "error", 4)
        return false
    end
    local code = string.format(
        "if not game:IsLoaded() then game.Loaded:Wait() end task.wait(2) loadstring(game:HttpGet(%q))()",
        AUTO_EXECUTE_URL
    )
    local ok = pcall(queue, code)
    if ok then QueuedThisSession = true end
    return ok
end

local function SetAutoExecute(on)
    AutoExecuteOn = on
    if on then
        if QueueAutoExecute() then Notify("Auto Execute", "Queued for the next teleport / rejoin.", "success", 3) end
        if not OnTeleportConn then
            OnTeleportConn = LocalPlayer.OnTeleport:Connect(function(state)
                if state == Enum.TeleportState.Started or state == Enum.TeleportState.InProgress then
                    QueuedThisSession = true
                end
            end)
        end
        if not TeleportFailConn then
            TeleportFailConn = TeleportService.TeleportInitFailed:Connect(function()
                QueuedThisSession = false
                if AutoExecuteOn then pcall(QueueAutoExecute) end
            end)
        end
    else
        if OnTeleportConn then OnTeleportConn:Disconnect(); OnTeleportConn = nil end
        if TeleportFailConn then TeleportFailConn:Disconnect(); TeleportFailConn = nil end
    end
end

-- Auto Reconnect (connected only while its toggle is on)
local ReconnectConns = {}
local Rejoining = false

local function TryRejoin()
    if Unloaded or Rejoining then return end
    Rejoining = true
    for attempt = 1, 8 do
        if Unloaded then break end
        task.wait(attempt == 1 and 2 or 5)
        if AutoExecuteOn then pcall(QueueAutoExecute) end
        pcall(function() TeleportService:Teleport(game.PlaceId, LocalPlayer) end)
        task.wait(10)   -- still here? try again
    end
    Rejoining = false
end

local function SetAutoReconnect(on)
    for _, c in ipairs(ReconnectConns) do pcall(function() c:Disconnect() end) end
    table.clear(ReconnectConns)
    if not on then return end

    table.insert(ReconnectConns, GuiService.ErrorMessageChanged:Connect(function(msg)
        if msg and msg ~= "" then task.spawn(TryRejoin) end
    end))

    pcall(function()
        local overlay = game:GetService("CoreGui").RobloxPromptGui.promptOverlay
        table.insert(ReconnectConns, overlay.ChildAdded:Connect(function(child)
            if child.Name == "ErrorPrompt" then task.spawn(TryRejoin) end
        end))
    end)

    pcall(function()
        local client = game:GetService("NetworkClient")
        table.insert(ReconnectConns, client.ChildRemoved:Connect(function()
            task.spawn(TryRejoin)
        end))
    end)

    table.insert(ReconnectConns, TeleportService.TeleportInitFailed:Connect(function()
        task.spawn(TryRejoin)
    end))
end

--==============================================================
-- EXPERIMENTAL: AUTO PLACE + AUTO HATCH (game's own remotes)
--   AskPlaceEgg      { Uid, LocalCFrame }   -> true
--   AskHatch         (uid)                  -> true, nil, nil
--   AskFinishHatch   (uid)                  -> true, nil, grantedPetUid
--   (shapes taken straight from your remote spy log)
--==============================================================

local PLACE_SPOTS = {
    Vector3.new(-3, -0.5, -7), Vector3.new(3, -0.5, -7), Vector3.new(0, -0.5, -12),
    Vector3.new(-5, -0.5, -13), Vector3.new(5, -0.5, -13), Vector3.new(-6, -0.5, -8),
    Vector3.new(6, -0.5, -8), Vector3.new(0, -0.5, -17), Vector3.new(-4, -0.5, -18),
    Vector3.new(4, -0.5, -18), Vector3.new(-7, -0.5, -16), Vector3.new(7, -0.5, -16),
    Vector3.new(-2, -0.5, -22), Vector3.new(2, -0.5, -22),
}

local function AskPlaceEgg(uid, offset)
    local rf = Net("RF/EggWorld/AskPlaceEgg")
    if not rf or not rf:IsA("RemoteFunction") then return false end
    local ok, a = pcall(function() return rf:InvokeServer({ Uid = uid, LocalCFrame = CFrame.new(offset) }) end)
    return ok and a == true
end

local function BeginHatchRemote(uid)
    local rf = Net("RF/EggWorld/AskHatch")
    if not rf or not rf:IsA("RemoteFunction") then return false end
    local ok, a = pcall(function() return rf:InvokeServer(uid) end)
    return ok and a == true
end

local function FinishHatchRemote(uid)
    local rf = Net("RF/EggWorld/AskFinishHatch")
    if not rf or not rf:IsA("RemoteFunction") then return false, nil end
    local ok, a, b = pcall(function() return rf:InvokeServer(uid) end)
    if ok and a == true then
        return true, (type(b) == "string" and b or nil)
    end
    return false, nil
end

local PlaceCooldown = {}   -- uid -> os.clock() until which we skip
local HatchCooldown = {}
local HatchBusy = {}

local function AutoPlacePass()
    local placed = 0
    for uid, rec in pairs(MyEggRecords) do
        if type(rec) == "table" and rec.Placement == nil and (PlaceCooldown[uid] or 0) < os.clock() then
            local done = false
            for _, off in ipairs(PLACE_SPOTS) do
                if AskPlaceEgg(uid, off) then
                    done = true
                    placed += 1
                    Log("Placed egg " .. tostring(rec.AssetCategory) .. " into the pen.")
                    break
                end
                task.wait(0.1)
            end
            if not done then
                PlaceCooldown[uid] = os.clock() + 60
            end
        end
    end
    return placed
end

local function AutoHatchPass()
    for uid, rec in pairs(MyEggRecords) do
        if type(rec) == "table" and rec.Placement ~= nil and not HatchBusy[uid]
            and (HatchCooldown[uid] or 0) < os.clock() then
            HatchBusy[uid] = true
            task.spawn(function()
                local ok = BeginHatchRemote(uid)
                if ok then
                    task.wait(6.5)
                    local done, petUid = FinishHatchRemote(uid)
                    if done then
                        Log("Hatched " .. tostring(rec.AssetCategory) .. (petUid and (" (pet " .. petUid .. ")") or ""))
                        Notify("Auto Hatch", "Hatched: " .. tostring(rec.AssetCategory), "success", 4)
                        HatchCooldown[uid] = os.clock() + 300
                    else
                        HatchCooldown[uid] = os.clock() + 60
                    end
                else
                    HatchCooldown[uid] = os.clock() + CFG.HatchInterval
                end
                HatchBusy[uid] = nil
            end)
        end
    end
end

local MaintLoopStarted = false
local LastEquip, LastClaim, LastPlace, LastHatch = 0, 0, 0, 0

local function DoEquipBest()
    local rf = Net("RF/Haul/WearBest")
    if not rf or not rf:IsA("RemoteFunction") then return false, "remote not found" end
    return pcall(function() return rf:InvokeServer() end)
end

local function DoClaimAway()
    local rf = Net("RF/AwayEarnings/AskCollect")
    if not rf or not rf:IsA("RemoteFunction") then return false, "remote not found" end
    return pcall(function() return rf:InvokeServer({ Kind = "Claim" }) end)
end

local function StartMaintLoop()
    if MaintLoopStarted then return end
    MaintLoopStarted = true
    task.spawn(function()
        while not Unloaded do
            task.wait(1)
            if Unloaded then break end
            if AutoEquipBest and os.clock() - LastEquip >= CFG.EquipInterval then
                LastEquip = os.clock()
                pcall(DoEquipBest)
            end
            if AutoClaimAway and os.clock() - LastClaim >= CFG.ClaimInterval then
                LastClaim = os.clock()
                pcall(DoClaimAway)
            end
            if AutoPlaceEggs and os.clock() - LastPlace >= CFG.PlaceInterval then
                LastPlace = os.clock()
                pcall(AutoPlacePass)
            end
            if AutoHatchEggs and os.clock() - LastHatch >= CFG.HatchInterval then
                LastHatch = os.clock()
                pcall(AutoHatchPass)
            end
        end
    end)
end

--==============================================================
-- WINDOW
--==============================================================

Window = RageHub:CreateWindow({
    Name = "Rage Hub",
    Subtitle = "Steal An Egg · v2 Flight",
    Theme = "Rage",
    Features = { Notifications = true },
    ConfigFolder = "RageHub/StealAnEgg",
    AutoSave = "autosave",
    Splash = true,
    OnUnload = function()
        Unloaded = true
        CamRelease()
        EndFlight()
        InstantSteal, AutoSteal, AutoTreadmill = false, false, false
        SpeedAdjust, InfiniteJump, Noclip = false, false, false
        SetAntiRagdoll(false)
        EggAlert, AutoEquipBest, AutoClaimAway = false, false, false
        AutoPlaceEggs, AutoHatchEggs = false, false
        Job += 1
        SpeedOverride = false
        RestoreHolds()
        SetAntiAfk(false)
        SetAutoReconnect(false)
        SetAutoExecute(false)
        for _, c in ipairs(Connections) do pcall(function() c:Disconnect() end) end
        table.clear(Connections)
        local c = Char()
        if c then
            for _, part in ipairs(c:GetChildren()) do
                if part:IsA("BasePart") and not part:IsA("HumanoidRootPart") then
                    pcall(function() part.CanCollide = true end)
                end
            end
        end
        local h = Hum()
        if h and h.Parent then h.WalkSpeed = 16 end
    end,
})

-- only one copy at a time (re-executing replaces the old one)
local Env = (getgenv and getgenv()) or _G
if Env.__RageHubStealAnEgg and Env.__RageHubStealAnEgg ~= Window then
    pcall(function() Env.__RageHubStealAnEgg:Destroy() end)
end
Env.__RageHubStealAnEgg = Window

local StealTab = Window:CreateTab("Steal", "🥚")
local PlayerTab = Window:CreateTab("Player", "🏃")
local OthersTab = Window:CreateTab("Others", "🧰")

--==============================================================
-- STEAL TAB
--==============================================================

local StatusSection = StealTab:CreateSection("Status")
StatusLabel = StatusSection:CreateLabel("Status: Idle (everything is OFF)")

local InstantSection = StealTab:CreateSection("Instant Steal")

InstantSection:CreateToggle({
    Name = "Instant Steal", Flag = "InstantSteal", Default = false,
    Description = "Click Steal once (0.1s hold) - the script flies the egg home for you",
    Callback = function(on)
        InstantSteal = on
        if on then
            EnsureListeners()
            ApplyFastToAll()
            Notify("Instant Steal", "ON: click Steal and the flight delivery takes over.", "success", 3)
        else
            RestoreHolds()
            Notify("Instant Steal", "OFF: original hold time restored.", "info", 3)
        end
    end,
})

InstantSection:CreateDropdown({
    Name = "Delivery Strategy", Flag = "DeliveryStrategy",
    Options = { "Forest Drop + Re-Steal", "Direct Flight Home", "Nearest Area Drop" },
    Default = "Forest Drop + Re-Steal",
    Description = "Forest Drop = land at the Forest EggPoint, drop, re-steal, fly home (safest). Direct = straight home (fastest)",
    Callback = function(v) if v then Strategy = v end end,
})

InstantSection:CreateButton({
    Name = "Steal Best Egg Now", ButtonText = "Steal",
    Description = "One full cycle: fly to the best matching egg, steal it, deliver it",
    Callback = function()
        if Busy then Notify("Rage Hub", "Already busy - press Stop first.", "warning", 3) return end
        EnsureListeners()
        task.spawn(function()
            RefreshSnapshot()
            local egg = PickBestEgg()
            if not egg then
                Notify("Steal", "No egg matches your filters right now.", "warning", 4)
                return
            end
            Busy = true
            local id = NewJob()
            GetOffTreadmillSafe()
            local ok, err = pcall(RunStealCycle, id, egg)
            if not ok then Notify("Steal", "Error: " .. tostring(err), "error", 4) end
            CamRelease(); EndFlight(); Busy = false
        end)
    end,
})

InstantSection:CreateParagraph({
    Title = "Workflow",
    Content = "Steal (you or Auto Steal) -> lift off +50 -> fly 500 studs/s to the Forest EggPoint -> land -> Drop -> re-steal -> fly back to spawn. Crossing into the SafeZone redeems the egg into your inventory. If a guard slaps it out of you, it chases the egg and takes it back.",
})

local AutoSection = StealTab:CreateSection("Auto Steal + Filter")

AutoSection:CreateToggle({
    Name = "Auto Steal (Filtered)", Flag = "AutoSteal", Default = false,
    Description = "Fly to a matching egg, steal it, deliver it, repeat",
    Callback = function(on)
        AutoSteal = on
        if on then
            EnsureListeners()
            task.spawn(RefreshSnapshot)
            StartLoop()
            Notify("Auto Steal", "ON. With Auto Treadmill on, it leaves the treadmill when a match spawns.", "success", 3)
        else
            if Busy then CancelAll("Auto Steal stopped") end
            Notify("Auto Steal", "OFF.", "info", 2)
        end
    end,
})

AutoSection:CreateDropdown({
    Name = "Rarities", Flag = "Rarities", Multi = true, SelectAll = true, Search = true,
    Options = RARITY_LIST, Default = {},
    Description = "e.g. Divine + Eternal. Empty = any rarity (live from the game's catalog)",
    Callback = function(list)
        SelectedRarities = {}
        for _, name in ipairs(list or {}) do SelectedRarities[tostring(name)] = true end
    end,
})

AutoSection:CreateDropdown({
    Name = "Biomes", Flag = "Biomes", Multi = true, SelectAll = true, Search = true,
    Options = BIOMES, Default = {},
    Description = "e.g. Enchanted Forest only. Empty = any biome",
    Callback = function(list)
        SelectedBiomes = {}
        for _, name in ipairs(list or {}) do SelectedBiomes[Norm(name)] = true end
    end,
})

AutoSection:CreateDropdown({
    Name = "Pick Order", Flag = "PickOrder",
    Options = { "Highest Rarity", "Biggest Size", "Nearest" }, Default = "Highest Rarity",
    Callback = function(v) if v then Priority = v end end,
})

AutoSection:CreateToggle({
    Name = "Allow Unknown Rarity", Flag = "AllowUnknownRarity", Default = false,
    Description = "Also take eggs whose rarity can't be read",
    Callback = function(on) AllowUnknownRarity = on end,
})

AutoSection:CreateToggle({
    Name = "Egg Alert", Flag = "EggAlert", Default = false,
    Description = "Notify when a matching egg spawns (no moving)",
    Callback = function(on)
        EggAlert = on
        if on then EnsureListeners(); task.spawn(RefreshSnapshot) end
    end,
})

AutoSection:CreateToggle({
    Name = "Rare Spawn Alert", Flag = "RareSpawnAlert", Default = true,
    Description = "The server's own 'Secret ... spawned' broadcasts",
    Callback = function(on) RareSpawnAlert = on; if on then EnsureListeners() end end,
})

AutoSection:CreateButton({
    Name = "Scan Eggs", ButtonText = "Scan",
    Description = "Fills the report below (why eggs match or not)",
    Callback = function() task.spawn(RunScan) end,
})

ScanLog = AutoSection:CreateLog({ Name = "Report", Height = 170, MaxLines = 80 })

local WorkflowSection = StealTab:CreateSection("Workflow")

WorkflowSection:CreateToggle({
    Name = "Camera Focus", Flag = "CameraFocus", Default = true,
    Description = "Camera watches the egg while stealing it; follows your flight after",
    Callback = function(on) CameraFocus = on; if not on then CamRelease() end end,
})

WorkflowSection:CreateToggle({
    Name = "Skip Strong Guards", Flag = "SkipStrongGuards", Default = false,
    Description = "Auto Steal ignores eggs whose guard you can't outrun (uses each area's live speed requirement)",
    Callback = function(on) SkipDangerous = on end,
})

WorkflowSection:CreateSlider({
    Name = "Max Recoveries", Flag = "MaxRecoveries", Range = { 0, 6 }, Increment = 1, Default = CFG.MaxRecoveries,
    Description = "Times it goes back for an egg a guard took from you",
    Callback = function(v) CFG.MaxRecoveries = v end,
})

WorkflowSection:CreateSlider({
    Name = "Drop Stop Delay", Flag = "StopDelay", Range = { 0, 1 }, Increment = 0.05, Default = CFG.StopDelay,
    Suffix = " s", Description = "How long it stands at the drop point before dropping",
    Callback = function(v) CFG.StopDelay = v end,
})

local FlightSection = StealTab:CreateSection("Flight")

FlightSection:CreateSlider({
    Name = "Fly Speed", Flag = "FlySpeed", Range = { 100, 1500 }, Increment = 25, Default = CFG.FlySpeed,
    Suffix = " studs/s", Description = "Cruise speed for every flight",
    Callback = function(v) CFG.FlySpeed = v end,
})

FlightSection:CreateSlider({
    Name = "Fly Offset", Flag = "FlyOffset", Range = { 10, 150 }, Increment = 5, Default = CFG.FlyOffset,
    Suffix = " studs", Description = "Cruise this high above the higher endpoint",
    Callback = function(v) CFG.FlyOffset = v end,
})

FlightSection:CreateSlider({
    Name = "Descend Radius", Flag = "DescendRadius", Range = { 8, 80 }, Increment = 1, Default = CFG.DescendRadius,
    Suffix = " studs", Description = "Start descending when this close to the target",
    Callback = function(v) CFG.DescendRadius = v end,
})

FlightSection:CreateSlider({
    Name = "Hover Height", Flag = "HoverHeight", Range = { 2, 12 }, Increment = 1, Default = CFG.HoverHeight,
    Suffix = " studs", Description = "Stop this high above the target point",
    Callback = function(v) CFG.HoverHeight = v end,
})

FlightSection:CreateToggle({
    Name = "Noclip During Flight", Flag = "FlightNoclip", Default = true,
    Description = "Pass through trees/walls while flying (restored after)",
    Callback = function(on) FlightNoclip = on end,
})

FlightSection:CreateButton({
    Name = "Stop Everything", ButtonText = "Stop",
    Description = "Cancels the current job and kills all movement",
    Callback = function()
        CancelAll("Stopped")
        Notify("Rage Hub", "Stopped.", "info", 2)
    end,
})

--==============================================================
-- PLAYER TAB
--==============================================================

local MovementSection = PlayerTab:CreateSection("Movement")

MovementSection:CreateToggle({
    Name = "Speed Adjust", Flag = "SpeedAdjust", Default = false,
    Description = "Sets your WalkSpeed to the slider value",
    Callback = function(on) SpeedAdjust = on; ApplySpeed() end,
})

MovementSection:CreateSlider({
    Name = "Walk Speed", Flag = "PlayerSpeed", Range = { 16, 500 }, Increment = 2, Default = CFG.PlayerSpeed,
    Callback = function(v) CFG.PlayerSpeed = v; if SpeedAdjust then ApplySpeed() end end,
})

MovementSection:CreateToggle({
    Name = "Infinite Jump", Flag = "InfiniteJump", Default = false,
    Callback = function(on) InfiniteJump = on end,
})

MovementSection:CreateToggle({
    Name = "Noclip", Flag = "Noclip", Default = false,
    Callback = function(on) Noclip = on end,
})

local ProtectSection = PlayerTab:CreateSection("Protection")

ProtectSection:CreateToggle({
    Name = "Anti Ragdoll", Flag = "AntiRagdoll", Default = false,
    Description = "Blocks ragdoll, knockback and flinging (skipped while flying)",
    Callback = function(on) SetAntiRagdoll(on) end,
})

local SessionSection = PlayerTab:CreateSection("Session")

SessionSection:CreateToggle({
    Name = "Anti AFK", Flag = "AntiAFK", Default = false,
    Callback = function(on) SetAntiAfk(on) end,
})

SessionSection:CreateToggle({
    Name = "Auto Reconnect", Flag = "AutoReconnect", Default = false,
    Description = "Rejoins if you get disconnected",
    Callback = function(on) SetAutoReconnect(on) end,
})

SessionSection:CreateToggle({
    Name = "Auto Execute", Flag = "AutoExecute", Default = false,
    Description = "Re-runs the script after teleport / rejoin",
    Callback = function(on) SetAutoExecute(on) end,
})

SessionSection:CreateButton({
    Name = "Rejoin Server", ButtonText = "Rejoin",
    Callback = function()
        pcall(function() TeleportService:Teleport(game.PlaceId, LocalPlayer) end)
    end,
})

--==============================================================
-- OTHERS TAB
--==============================================================

local FarmSection = OthersTab:CreateSection("Auto Farm (game's own actions)")

FarmSection:CreateToggle({
    Name = "Auto Equip Best", Flag = "AutoEquipBest", Default = false,
    Description = "Calls the game's Equip Best every interval",
    Callback = function(on) AutoEquipBest = on; LastEquip = 0; if on then StartMaintLoop() end end,
})

FarmSection:CreateSlider({
    Name = "Equip Best Interval", Flag = "EquipInterval", Range = { 5, 300 }, Increment = 5, Default = CFG.EquipInterval,
    Suffix = " s", Callback = function(v) CFG.EquipInterval = v end,
})

FarmSection:CreateToggle({
    Name = "Auto Claim Away Earnings", Flag = "AutoClaimAway", Default = false,
    Description = "Claims offline earnings every interval",
    Callback = function(on) AutoClaimAway = on; LastClaim = 0; if on then StartMaintLoop() end end,
})

FarmSection:CreateSlider({
    Name = "Claim Interval", Flag = "ClaimInterval", Range = { 30, 600 }, Increment = 10, Default = CFG.ClaimInterval,
    Suffix = " s", Callback = function(v) CFG.ClaimInterval = v end,
})

local TreadmillSection = OthersTab:CreateSection("Treadmill")

TreadmillSection:CreateToggle({
    Name = "Auto Treadmill", Flag = "AutoTreadmill", Default = false,
    Description = "Flies to YOUR treadmill, wears it, returns if you leave",
    Callback = function(on)
        AutoTreadmill = on
        if on then
            EnsureListeners()
            StartLoop()
            TreadmillRetryAt = 0
            Notify("Auto Treadmill", "ON.", "success", 2)
        else
            if Busy then CancelAll() end
            Notify("Auto Treadmill", "OFF: no more returning to the treadmill.", "info", 3)
        end
    end,
})

local LabSection = OthersTab:CreateSection("Experimental (game's own remotes)")

LabSection:CreateToggle({
    Name = "Auto Place New Eggs", Flag = "AutoPlaceEggs", Default = false,
    Description = "Places eggs you haven't placed yet into your pen (AskPlaceEgg)",
    Callback = function(on)
        AutoPlaceEggs = on
        if on then
            EnsureListeners()
            StartMaintLoop()
            Notify("Auto Place", "ON: new eggs get placed into your pen.", "success", 3)
        end
    end,
})

LabSection:CreateToggle({
    Name = "Auto Hatch Placed Eggs", Flag = "AutoHatchEggs", Default = false,
    Description = "Tries AskHatch + AskFinishHatch on placed eggs; the server only allows grown ones",
    Callback = function(on)
        AutoHatchEggs = on
        if on then
            EnsureListeners()
            StartMaintLoop()
            Notify("Auto Hatch", "ON: grown eggs get hatched automatically.", "success", 3)
        end
    end,
})

LabSection:CreateSlider({
    Name = "Hatch Check Interval", Flag = "HatchInterval", Range = { 15, 300 }, Increment = 5, Default = CFG.HatchInterval,
    Suffix = " s", Callback = function(v) CFG.HatchInterval = v end,
})

local QuickSection = OthersTab:CreateSection("Quick Actions")

QuickSection:CreateButton({
    Name = "Equip Best Now", ButtonText = "Equip",
    Callback = function()
        task.spawn(function()
            local ok, r = DoEquipBest()
            Notify("Equip Best", ok and "Done." or ("Failed: " .. tostring(r)), ok and "success" or "error", 3)
        end)
    end,
})

QuickSection:CreateButton({
    Name = "Claim Away Earnings Now", ButtonText = "Claim",
    Callback = function()
        task.spawn(function()
            local ok, r = DoClaimAway()
            Notify("Away Earnings", ok and "Claimed (or nothing to claim)." or ("Failed: " .. tostring(r)), ok and "success" or "error", 3)
        end)
    end,
})

QuickSection:CreateButton({
    Name = "Deliver Carried Egg", ButtonText = "Deliver",
    Description = "If you are holding an egg, fly it home now",
    Callback = function()
        if Busy then Notify("Rage Hub", "Already busy - press Stop first.", "warning", 3) return end
        if not IsCarryingNow() then
            Notify("Deliver", "You are not carrying an egg.", "warning", 3)
            return
        end
        EnsureListeners()
        Busy = true
        local id = NewJob()
        task.spawn(function()
            local ok, err = pcall(DeliverPhase, id, CarriedUid, nil)
            if not ok then Notify("Deliver", "Error: " .. tostring(err), "error", 4) end
            CamRelease(); EndFlight(); Busy = false
        end)
    end,
})

local ScriptSection = OthersTab:CreateSection("Script")

ScriptSection:CreateToggle({
    Name = "Auto Save Config", Flag = "AutoSaveConfig", Default = true,
    Description = "Saves everything; restored on rejoin / auto execute",
    Callback = function(on)
        AutoSaveOn = on
        pcall(function() Window.AutoSaveName = on and "autosave" or nil end)
    end,
})

ScriptSection:CreateButton({
    Name = "Reset Saved Config", ButtonText = "Reset",
    Description = "Deletes the saved config (toggles start OFF next time)",
    Callback = function()
        pcall(function() Window:DeleteConfig("autosave") end)
        Notify("Config", "Saved config deleted.", "success", 3)
    end,
})

ScriptSection:CreateButton({
    Name = "Unload Script", ButtonText = "Unload",
    Description = "Stops everything and removes the UI",
    Callback = function() pcall(function() Window:Destroy() end) end,
})

OthersTab:CreateSection("Notes"):CreateParagraph({
    Title = "Delivery strategies",
    Content = "Forest Drop + Re-Steal: the Forest guard is the weakest (needs speed 11, runs 11.6) and its EggPoint is the closest spot to the SafeZone - dropping there and re-stealing hands the chase to a guard that can never catch you. Direct Flight Home skips the stop and is fastest. Nearest Area Drop behaves like the old Auto option.",
})

Notify("Rage Hub", "v2 Flight Edition loaded.", "success", 3)
SetStatus("Idle (everything is OFF)")

-- restore your saved config (filters + any toggles that were ON turn back on by themselves)
task.delay(1.2, function()
    if Unloaded then return end
    local ok, loaded = pcall(function() return Window:LoadConfig() end)
    if ok and loaded then
        Notify("Config", "Saved config restored.", "success", 3)
    end
end)
