--// Rage Hub · Steal An Egg · v1
--// Tabs: Steal | Player | Others (+ Rage Hub's built-in Settings tab)
--//
--// CONFIG: Auto Save is ON by default. Your toggles, filters and sliders are saved and restored
--// automatically (this is what makes reconnect + auto execute bring everything back ON).
--// If a saved toggle ever causes trouble at startup: Others > Reset Saved Config.
--//
--// Game facts used (from your dump + remote spy):
--//   Steal prompt     : workspace.SmartPromptPart.<CarryAreaEgg>  (ActionText "Steal")
--//   Lake drop point  : workspace.World.Areas.GuardAreas.Lake.RequiredSpeedSign.Support
--//   Drop button      : PlayerGui.DropHeldEgg.Button
--//   Spawn            : workspace.SpawnLocation
--//   Your treadmill   : workspace.Plots.<your plot>.TreadmillBottom  (plot sign shows your name)
--//   Treadmill remotes: RF/Treadmill/AskWearStill, RF/Treadmill/AskDoff, RE/Treadmill/RenderStateShifted
--//   Egg data (live)  : RE/EggWorld/FieldEggShifted / FieldEggGone / FieldEggCarry (AreaId = biome)

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

local RARITIES = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Cosmic", "Secret", "Eternal", "Divine", "OG" }
local RARITY_RANK = {}
for i, name in ipairs(RARITIES) do RARITY_RANK[name] = i end

-- AreaId values seen in FieldEggShifted + the GuardAreas folder in your dump.
-- ("Enchanted Temple" in your message = "Enchanted Forest" here; "Titan Temple" is its own biome.)
local BIOMES = {
    "Forest", "Lake", "Desert", "Jungle", "Snow", "Volcano", "Abyss Ocean", "Prehistoric",
    "Cosmic", "Cherry Blossom", "Titan Temple", "Light Dark", "Enchanted Forest",
}

-- Only used if the game's own asset module can't be read.
-- Guard data from the game's own attributes (GuardEscapeSpeeds = speed stat needed, guard run speed)
local GUARD = {
    ["Forest"] = { need = 11, run = 11.6 }, ["Lake"] = { need = 900, run = 24.3 },
    ["Desert"] = { need = 10000, run = 48.4 }, ["Jungle"] = { need = 40000, run = 65.6 },
    ["Snow"] = { need = 170000, run = 83.8 }, ["Abyss Ocean"] = { need = 2500000, run = 117.4 },
    ["Volcano"] = { need = 700000, run = 102.0 }, ["Prehistoric"] = { need = 18000000, run = 143.2 },
    ["Cosmic"] = { need = 700000000, run = 187.9 }, ["Cherry Blossom"] = { need = 2500000000, run = 205.7 },
    ["Titan Temple"] = { need = 7000000000, run = 217.8 }, ["Light Dark"] = { need = 20000000000, run = 231.9 },
    ["Enchanted Forest"] = { need = 49999998976, run = 242.4 },
}

local NAME_RARITY_FALLBACK = {
    { "eternal lunar dragon", "Eternal" }, { "el maja", "Eternal" }, { "oni tiger", "Eternal" },
    { "gorilla king", "Eternal" }, { "pegasus", "Eternal" }, { "skeleton horse", "Eternal" },
    { "void dragon", "Eternal" }, { "equinox", "Eternal" },
    { "unicorn", "Divine" }, { "kitsune", "Divine" }, { "nightflame", "Divine" }, { "archangel", "Divine" },
    { "world burner", "Divine" }, { "aetheron", "Divine" },
}

--==============================================================
-- SETTINGS / STATE  (everything automation-related starts OFF)
--==============================================================

local CFG = {
    TravelSpeed = 500,        -- studs/s for tween trips
    SupportOffset = 3,        -- stand this many studs above the Lake drop point
    LakeTweenSeconds = 0.8,   -- MAX tween time to the drop area (far trips take this long at most)
    DropTweenSpeed = 1000,    -- studs/s: near trips are faster than the max time (adaptive)
    MinTween = 0.2,           -- never faster than this
    DropDelay = 0.5,          -- stop at the drop area this long before clicking Drop
    ApproachSpeed = 800,      -- one fast, uninterrupted tween toward an egg (studs/s)
    MaxRecoveries = 2,        -- times it goes back for an egg the guard returned to its nest
    EquipInterval = 30,
    ClaimInterval = 120,
    PlayerSpeed = 100,        -- Player tab walk speed (only used when its toggle is on)
}

local InstantSteal = false
local AutoSteal = false
local AutoTreadmill = false
local SpeedAdjust = false
local InfiniteJump = false
local Noclip = false
local AntiRagdoll = false
local AutoSaveOn = true
local CameraFocus = true         -- camera watches the egg area instead of following you during a steal
local UseDecoy = true            -- carry a Forest egg to the target, swap it for the target egg
local SkipDangerous = false      -- skip eggs whose guard you cannot outrun
local GetDropButton = function() return nil end
local CamLocked, CamCFrame = false, nil

local SelectedRarities = {}   -- set; empty or all = any
local SelectedBiomes = {}     -- set (normalized names); empty or all = any
local AllowUnknownRarity = false
local EggAlert = false
local AutoEquipBest = false
local AutoClaimAway = false
local OnEggSeen = function() end
local ScanLog
local Log = function() end
local EggPosition = function() return nil end
local PauseUntil = 0
local DropArea = "Forest"      -- Forest | Lake | Auto (nearest)
local CarriedUid = nil        -- uid of the egg you carry (from the server)
local CarriedUidAt = 0
local NestPos = {}               -- uid -> where that egg's nest is
local EggSeenAt = {}             -- uid -> when the server last updated that egg
local DescribeEgg = function() return "egg" end
local GuardDanger = function() return false end
local Priority = "Highest Rarity"

local Unloaded = false
local Busy = false
local Job = 0                 -- bump to cancel whatever is running
local Worn = false            -- true while you are on the treadmill (from RenderStateShifted)
local Carrying = false        -- true while holding an egg (from FieldEggCarry)
local LastTriggered = 0       -- os.clock() of your last prompt trigger
local SpeedOverride = false   -- true while the script is walking you to spawn
local TreadmillRetryAt = 0

local Window, StatusLabel
local Connections = {}
local OriginalHold = setmetatable({}, { __mode = "k" })
local Eggs = {}               -- Uid -> egg record from the server
local RarityCache = {}
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
-- MOVEMENT (TweenService CFrame tween, verified arrival)
--==============================================================

local ActiveTween = nil

local function StopTween()
    if ActiveTween then pcall(function() ActiveTween:Cancel() end); ActiveTween = nil end
end

-- Camera: stays on the egg area while your character moves, follows you again once it is safe
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

-- tween; with mustCarry it stops at once if the egg is taken from you (guard hit)
local function TweenTo(pos, id, duration, mustCarry)
    local r = Root()
    if not r then return false end
    local dist = (r.Position - pos).Magnitude
    if dist <= 2 then return true end

    local seconds = duration or math.max(0.15, dist / CFG.TravelSpeed)
    local tween = TweenService:Create(r, TweenInfo.new(seconds, Enum.EasingStyle.Linear), {
        CFrame = CFrame.new(pos) * r.CFrame.Rotation,
    })
    local finished = false
    tween.Completed:Connect(function() finished = true end)
    ActiveTween = tween
    tween:Play()

    local t0 = os.clock()
    while not finished do
        if Cancelled(id) or os.clock() - t0 > seconds + 5 then
            pcall(function() tween:Cancel() end)
            ActiveTween = nil
            return false, "cancelled"
        end
        if mustCarry and os.clock() - t0 > 0.35 and not GetDropButton() then
            pcall(function() tween:Cancel() end)
            ActiveTween = nil
            return false, "lost"
        end
        task.wait()
    end
    ActiveTween = nil

    local nr = Root()
    if nr then nr.AssemblyLinearVelocity = Vector3.zero end
    return nr ~= nil and (nr.Position - pos).Magnitude <= 4
end

-- "100%": re-tween until we really are at the target (up to 3 attempts)
local function TweenVerified(pos, id, duration, mustCarry)
    for attempt = 1, 3 do
        local ok, why = TweenTo(pos, id, attempt == 1 and duration or nil, mustCarry)
        if ok then return true end
        if why == "lost" then return false, "lost" end
        if Cancelled(id) then return false, "cancelled" end
    end
    return false
end

-- one fast tween without stopping (no stop-and-go)
local function ApproachTween(pos, id, mustCarry)
    local r = Root()
    if not r then return false end
    local seconds = math.max(0.12, (r.Position - pos).Magnitude / CFG.ApproachSpeed)
    return TweenVerified(pos, id, seconds, mustCarry)
end

local function DesiredWalkSpeed()
    return SpeedAdjust and CFG.PlayerSpeed or 16
end

--==============================================================
-- PROMPTS / GUI
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

local LastWideScan = 0
local function FindNearbyStealPrompt(range)
    local r = Root()
    if not r then return nil end
    local best, bestDist = nil, range
    for _, holder in ipairs(workspace:GetChildren()) do
        if holder.Name == "SmartPromptPart" then
            for _, p in ipairs(holder:GetChildren()) do
                if p:IsA("ProximityPrompt") and p.Enabled and IsStealPrompt(p) then
                    local pos = PromptPosition(p)
                    local d = pos and (pos - r.Position).Magnitude
                    if d and d < bestDist then best, bestDist = p, d end
                end
            end
        end
    end
    -- fallback (throttled): the prompt may live somewhere other than SmartPromptPart
    if not best and os.clock() - LastWideScan > 1 then
        LastWideScan = os.clock()
        for _, obj in ipairs(workspace:GetDescendants()) do
            if obj:IsA("ProximityPrompt") and obj.Enabled and IsStealPrompt(obj) then
                local pos = PromptPosition(obj)
                local d = pos and (pos - r.Position).Magnitude
                if d and d < bestDist then best, bestDist = obj, d end
            end
        end
    end
    return best
end

local function FirePrompt(p)
    if fireproximityprompt then
        if pcall(fireproximityprompt, p) then return true end
    end
    return pcall(function()
        p:InputHoldBegin()
        task.wait(math.max(0.1, p.HoldDuration) + 0.05)
        p:InputHoldEnd()
    end)
end

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

local function ClickGui(btn)
    if not btn or not btn.Parent then return false end
    if firesignal then
        local ok = pcall(function() firesignal(btn.Activated) end)
        if not ok then ok = pcall(function() firesignal(btn.MouseButton1Click) end) end
        if ok then return true end
    end
    return pcall(function()
        local vim = game:GetService("VirtualInputManager")
        local inset = GuiService:GetGuiInset()
        local c = btn.AbsolutePosition + btn.AbsoluteSize / 2 + inset
        vim:SendMouseButtonEvent(c.X, c.Y, 0, true, game, 0)
        task.wait(0.05)
        vim:SendMouseButtonEvent(c.X, c.Y, 0, false, game, 0)
    end)
end

--==============================================================
-- INSTANT STEAL: hold duration 0.1 (restored when turned off)
--==============================================================

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
-- LAKE DROP WORKFLOW (same tween as your working file: Lake Guard EggPoint)
--   Steal clicked -> tween to Lake EggPoint -> Drop -> wait for Steal -> click Steal -> walk to SpawnLocation
--   Stops (no spawn walk) if any step isn't confirmed. Polling is fast so the egg is re-stolen
--   before it can return to its nest.
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

local function AreaDropPoint(area)
    if not area then return nil end
    local guard = area:FindFirstChild("Guard")
    local point = guard and guard:FindFirstChild("EggPoint")
    if point then return point end
    local sign = area:FindFirstChild("RequiredSpeedSign")
    return sign and sign:FindFirstChild("Support")
end

local function GetDropPoint()
    local areas = GetGuardAreas()
    if not areas then return nil end

    if DropArea == "Auto (nearest)" then
        local r = Root()
        local best, bestDist
        for _, area in ipairs(areas:GetChildren()) do
            local point = AreaDropPoint(area)
            local pos = point and PositionOfObj(point)
            if pos and r then
                local d = (pos - r.Position).Magnitude
                if not bestDist or d < bestDist then best, bestDist = point, d end
            end
        end
        return best
    end

    return AreaDropPoint(areas:FindFirstChild(DropArea))
end

local function Fail(msg)
    SetStatus(msg)
    Log(msg)
    Notify("Steal", msg, "warning", 4)
    return false
end

local function DropTweenSeconds(dist)
    return math.clamp(dist / CFG.DropTweenSpeed, CFG.MinTween, CFG.LakeTweenSeconds)
end

-- the Steal prompt that belongs to ONE specific egg (matched by position, flat distance)
local LastWideScan2 = 0
local function FindPromptNearPos(pos, maxDist)
    local best, bestDist = nil, maxDist
    local flat = Vector3.new(pos.X, 0, pos.Z)

    local function consider(p)
        if p:IsA("ProximityPrompt") and p.Enabled and IsStealPrompt(p) then
            local pp = PromptPosition(p)
            if pp then
                local d = (Vector3.new(pp.X, 0, pp.Z) - flat).Magnitude
                if d < bestDist then best, bestDist = p, d end
            end
        end
    end

    for _, holder in ipairs(workspace:GetChildren()) do
        if holder.Name == "SmartPromptPart" then
            for _, p in ipairs(holder:GetChildren()) do consider(p) end
        end
    end

    if not best and os.clock() - LastWideScan2 > 1 then
        LastWideScan2 = os.clock()
        for _, obj in ipairs(workspace:GetDescendants()) do consider(obj) end
    end
    return best
end

-- which egg is at a nest position (used the moment you click Steal)
local function UidAtPos(pos)
    local bestUid, bestDist = nil, 5
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

local function CarrierIsMe(rec)
    return rec ~= nil and tonumber(rec.CarrierUserId) == LocalPlayer.UserId
end

-- only trusts an update that arrived AFTER `since` (old records can be stale)
local function EggWentBack(uid, since)
    local rec = uid and Eggs[uid]
    return rec ~= nil and (EggSeenAt[uid] or 0) >= since
        and (rec.State == "GuardCarried" or rec.State == "Slot")
end

-- wait until a ragdoll / knock-down is over
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

-- click the HUD Drop button until the egg is really gone from you
local function DropHeld(id)
    local btn = WaitFor(GetDropButton, 2, id, 0.03)
    if not btn then return false end
    for _ = 1, 10 do
        ClickGui(btn)
        task.wait(0.1)
        if not GetDropButton() then return true end
        btn = GetDropButton() or btn
    end
    return false
end

-- steal THE egg at `pos` (its own prompt only). true, or false + reason
local function StealAt(pos, uid, id)
    local prompt = WaitFor(function() return FindPromptNearPos(pos, 4) end, 2.5, id, 0.03)
    if not prompt then return false, "no prompt at that egg (gone?)" end

    for _ = 1, 8 do
        FirePrompt(prompt)
        local deadline = os.clock() + 0.5
        repeat
            if uid and CarrierIsMe(Eggs[uid]) then return true end
            if GetDropButton() and (not prompt.Parent or not prompt.Enabled) then return true end
            task.wait(0.02)
        until os.clock() > deadline or Cancelled(id)
        if Cancelled(id) then return false, "cancelled" end
        if GetDropButton() then return false, "picked a different egg" end
    end
    return false, "steal did not register"
end

-- nearest Forest egg that can be used as the carried "decoy"
local function PickForestDecoy(excludeUid)
    local r = Root()
    if not r then return nil end
    local best, bestDist
    for uid, rec in pairs(Eggs) do
        if uid ~= excludeUid and rec.State == "Slot" and tostring(rec.AreaId) == "Forest"
            and (AttemptedUntil[uid] or 0) < os.clock() then
            local pos = EggPosition(rec)
            if pos then
                local d = (pos - r.Position).Magnitude
                if not bestDist or d < bestDist then best, bestDist = { Uid = uid, Pos = pos }, d end
            end
        end
    end
    return best
end

-- Get a specific egg: (optional) take a Forest egg first, carry it to the target without stopping,
-- drop it there and steal the right egg.
local function GetEggBack(id, uid, origin)
    WaitStable(id, 1.0)
    if Cancelled(id) then return false end

    -- never start while holding something
    if GetDropButton() then DropHeld(id) end

    local rec = uid and Eggs[uid]
    local area = rec and tostring(rec.AreaId) or nil
    local targetStand = origin + Vector3.new(0, 3, 0)

    if UseDecoy and area ~= "Forest" then
        local decoy = PickForestDecoy(uid)
        if decoy then
            SetStatus("Taking a Forest egg first")
            Log("Decoy: taking a Forest egg first.")
            local okA = ApproachTween(decoy.Pos + Vector3.new(0, 3, 0), id, false)
            if okA then
                AttemptedUntil[decoy.Uid] = os.clock() + 25
                local okB = StealAt(decoy.Pos, decoy.Uid, id)
                if okB then
                    SetStatus("Carrying the Forest egg to the target")
                    -- one fast tween without stopping; land a few studs beside the target nest
                    local okC = ApproachTween(origin + Vector3.new(0, 3, 5), id, true)
                    if okC then
                        if DropHeld(id) then Log("Dropped the Forest egg at the target.") end
                    else
                        Log("Lost the Forest egg on the way; going straight to the target.")
                    end
                end
            end
        end
    end

    if Cancelled(id) then return false end

    local r = Root()
    if r and (r.Position - targetStand).Magnitude > 4 then
        SetStatus("Going to the target egg")
        if not ApproachTween(targetStand, id, false) then
            return Fail("Could not reach the target egg.")
        end
    end

    SetStatus("Stealing the target egg")
    local ok, why = StealAt(origin, uid, id)
    if not ok then return Fail("Target egg not stolen: " .. tostring(why)) end
    Log("Took the target egg.")
    return true
end

-- carry the egg to the drop area, stop, click Drop.
-- returns "dropped", "lost" (egg left you before the drop) or nil (hard failure)
local function DropAtArea(id)
    local point = GetDropPoint()
    local pos = PositionOfObj(point)
    if not pos then Fail("Drop point not found for " .. DropArea .. ". Stopped."); return nil end
    local target = pos + Vector3.new(0, CFG.SupportOffset, 0)

    local r = Root()
    if not r then return nil end
    local seconds = DropTweenSeconds((r.Position - target).Magnitude)
    SetStatus(string.format("Tweening to %s (%.2fs)", DropArea, seconds))
    Log(string.format("Tween to %s in %.2fs", DropArea, seconds))

    local ok, why = TweenVerified(target, id, seconds, true)
    if not ok then
        if why == "lost" then
            Log("The egg was taken from me on the way.")
            return "lost"
        end
        Fail("Could not reach the drop area. Stopped.")
        return nil
    end

    if not GetDropButton() then
        Log("The egg left me before the drop area.")
        return "lost"
    end

    Log(string.format("Arrived. Waiting %.2fs", CFG.DropDelay))
    SetStatus("Stopped at drop area")
    if CFG.DropDelay > 0 then task.wait(CFG.DropDelay) end
    if Cancelled(id) then return nil end
    if not GetDropButton() then
        Log("The egg left me while I waited.")
        return "lost"
    end

    if DropHeld(id) then
        Log("Dropped.")
        return "dropped"
    end
    if not GetDropButton() then return "lost" end
    Fail("Drop not confirmed. Stopped.")
    return nil
end

-- after the drop: take the dropped egg back before the guard does.
-- returns "stolen", "returned" (guard/monster took it back to its nest), "cancelled"
local function StealBackAtDrop(id, uid)
    SetStatus("Waiting for the dropped egg's Steal prompt")
    local prompt
    local t0 = os.clock()
    local dropAt = t0

    while os.clock() - t0 < 6 do
        if Cancelled(id) then return "cancelled" end

        local rec = uid and Eggs[uid]
        if EggWentBack(uid, dropAt) then
            Log("The egg went back to its nest (state " .. tostring(rec.State) .. ").")
            return "returned"
        end

        local eggPos = rec and rec.State == "Dropped" and EggPosition(rec)
        local me = Root()
        prompt = (eggPos and FindPromptNearPos(eggPos, 6)) or (me and FindPromptNearPos(me.Position, 14))
        if prompt then break end
        task.wait(0.03)
    end
    if not prompt then return "returned" end

    for _ = 1, 6 do
        SetStatus("Clicking Steal")
        FirePrompt(prompt)

        if WaitFor(GetDropButton, 0.6, id, 0.03) then return "stolen" end
        local rec = uid and Eggs[uid]
        if CarrierIsMe(rec) then return "stolen" end
        if EggWentBack(uid, dropAt) then return "returned" end

        local eggPos = rec and rec.State == "Dropped" and EggPosition(rec)
        prompt = (eggPos and FindPromptNearPos(eggPos, 6)) or prompt
    end
    return "returned"
end

-- final leg: tween to SpawnLocation (no walking). "arrived", "lost" (guard hit) or nil
local function TweenToSpawn(id)
    local spawn = workspace:FindFirstChild("SpawnLocation")
    local r = Root()
    if not spawn or not r then
        Fail("SpawnLocation not found.")
        return nil
    end
    local target = spawn.Position + Vector3.new(0, 3, 0)
    local seconds = DropTweenSeconds((r.Position - target).Magnitude)
    SetStatus("Tweening to SpawnLocation")
    Log(string.format("Tween to SpawnLocation in %.2fs", seconds))

    local ok, why = TweenVerified(target, id, seconds, true)
    if ok then
        if GetDropButton() then return "arrived" end
        return "lost"
    end
    if why == "lost" then return "lost" end
    return nil
end

-- Steal (manual or auto) -> drop area -> Drop -> steal back -> spawn.
-- If the egg is taken (guard hit / returned to its nest), it goes back for it with the
-- Forest-egg trick (max CFG.MaxRecoveries times).
local function RunDropWorkflow(id, originHint, uidHint, lockCamera)
    local started = os.clock()

    -- the steal must really be registered BEFORE we move
    if not WaitFor(GetDropButton, 3, id, 0.02) then
        return Fail("Steal not registered (no Drop button). Not moving.")
    end

    -- which egg is this?
    local uid = ((CarriedUidAt >= started - 1) and CarriedUid) or uidHint
    local rec = uid and Eggs[uid]
    if rec then
        Log("Egg: " .. DescribeEgg(rec))
        SetStatus("Carrying " .. tostring(rec.AssetCategory))
    end
    local origin = (uid and NestPos[uid]) or originHint

    -- camera stays where you stole it while the character moves
    if origin and lockCamera ~= false then CamLock(origin) end

    local recoveries = 0
    while true do
        local dropped = DropAtArea(id)
        if dropped == nil then return false end

        if dropped == "dropped" then
            local outcome = StealBackAtDrop(id, uid)
            if outcome == "cancelled" then return false end
            if outcome == "stolen" then
                Log("Stole it back.")
                CamRelease()                       -- secured: camera follows you again
                local leg = TweenToSpawn(id)
                if leg == "arrived" then
                    SetStatus("Done: reached SpawnLocation")
                    Log("Reached SpawnLocation.")
                    Notify("Steal", "Cycle complete.", "success", 2)
                    return true
                elseif leg == nil then
                    return false
                end
                Log("The guard took the egg on the way to spawn.")
            end
        end

        -- the egg is gone from me: go back for it
        if not origin or recoveries >= CFG.MaxRecoveries then
            return Fail("Egg delivery failed (it keeps returning to its nest).")
        end
        recoveries += 1
        Log("Recovery " .. recoveries .. " of " .. CFG.MaxRecoveries)
        CamLock(origin)
        if not GetEggBack(id, uid, origin) then
            return Fail("Egg delivery failed (could not take the egg back).")
        end
        CamRelease()
    end
end

--==============================================================
-- TREADMILL (your own plot only)
--==============================================================

local function GetMyPlot()
    local plots = workspace:FindFirstChild("Plots")
    if not plots then return nil end

    local n1, n2 = Lower(LocalPlayer.Name), Lower(LocalPlayer.DisplayName)

    for _, plot in ipairs(plots:GetChildren()) do
        local sign = plot:FindFirstChild("PlotSign")
        local label = sign and sign:FindFirstChild("PlayerName", true)
        if label and label:IsA("TextLabel") then
            local t = Lower(label.Text)
            if t == n1 or t == n2 then return plot end
        end
    end

    -- fallback: this model only exists in your own plot
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

local function GetOffTreadmill()
    if not Worn then return end
    local rf = Net("RF/Treadmill/AskDoff")
    if rf and rf:IsA("RemoteFunction") then
        pcall(function() rf:InvokeServer() end)
    end
    Worn = false
end

local function GoToTreadmill(id)
    local spot = GetTreadmillSpot()
    if not spot then
        Notify("Auto Treadmill", "Could not find your plot/treadmill.", "error", 4)
        return false
    end

    SetStatus("Tweening to your treadmill")
    if not TweenVerified(spot, id) then return false end
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
-- LIVE EGG DATA (passive listeners, connected only when needed)
--==============================================================

local ListenersOn = false

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
            if type(data) == "table" then Carrying = data.IsCarrying == true end
        end))
    end

    local shifted = Net("RE/EggWorld/FieldEggShifted")
    if shifted then Track(shifted.OnClientEvent:Connect(function(rec) IngestEgg(rec, 0) end)) end

    local batch = Net("RE/EggWorld/FieldEggBatchShifted")
    if batch then Track(batch.OnClientEvent:Connect(function(data) IngestEgg(data, 0) end)) end

    local verdict = Net("RE/EggWorld/FieldEggRedeemVerdict")
    if verdict then
        Track(verdict.OnClientEvent:Connect(function(data)
            if type(data) == "table" and type(data.AssetCategory) == "string" and type(data.Rarity) == "string" then
                local name
                for _, n in ipairs(RARITIES) do if Lower(n) == Lower(data.Rarity) then name = n end end
                if name then RarityCache[data.AssetCategory] = name end
            end
        end))
    end

    local gone = Net("RE/EggWorld/FieldEggGone")
    if gone then
        Track(gone.OnClientEvent:Connect(function(uid)
            if type(uid) == "string" then Eggs[uid] = nil end
        end))
    end

    Track(ProximityPromptService.PromptTriggered:Connect(function(prompt, plr)
        if plr ~= LocalPlayer then return end
        LastTriggered = os.clock()

        -- Instant Steal: one click on a Steal prompt runs the Lake workflow
        if InstantSteal and not Busy and IsStealPrompt(prompt) then
            Busy = true
            local id = NewJob()
            local origin = PromptPosition(prompt)
            local uid0 = origin and UidAtPos(origin)
            task.spawn(function()
                local ok, err = pcall(RunDropWorkflow, id, origin, uid0, true)
                if not ok then Notify("Steal", "Workflow error: " .. tostring(err), "error", 4) end
                CamRelease()
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
-- EGG RARITY / FILTERS
--==============================================================

local function MatchRarityName(value)
    local v = Lower(value)
    for _, name in ipairs(RARITIES) do
        if Lower(name) == v then return name end
    end
    return nil
end

local function Norm(text)
    return (Lower(text):gsub("[%s_%-]", ""))
end

local function SetSize(set)
    local n = 0
    for _ in pairs(set) do n += 1 end
    return n
end

local function DeepFindRarity(t, depth, seen)
    if type(t) ~= "table" or depth > 3 or seen[t] then return nil end
    seen[t] = true
    for k, v in pairs(t) do
        if type(v) == "string" then
            local key = Lower(k)
            if string.find(key, "rarity", 1, true) or string.find(key, "tier", 1, true) then
                local r = MatchRarityName(v)
                if r then return r end
            end
        end
    end
    for _, v in pairs(t) do
        if type(v) == "table" then
            local r = DeepFindRarity(v, depth + 1, seen)
            if r then return r end
        end
    end
    for _, v in pairs(t) do
        if type(v) == "string" then
            local r = MatchRarityName(v)
            if r then return r end
        end
    end
    return nil
end

local function GetAssetModule(category)
    local data = ReplicatedStorage:FindFirstChild("Data")
    local assets = data and data:FindFirstChild("Assets")
    local configs = assets and assets:FindFirstChild("Configs")
    local mod = configs and configs:FindFirstChild(category)
    if mod and mod:IsA("ModuleScript") then return mod end
    mod = assets and assets:FindFirstChild(category)
    if mod and mod:IsA("ModuleScript") then return mod end
    return nil
end

-- returns rarity (or nil) and a short note about where it came from
local function ResolveRarity(rec)
    if type(rec.Rarity) == "string" then
        local r = MatchRarityName(rec.Rarity)
        if r then return r, "record" end
    end

    local category = rec.AssetCategory
    if type(category) ~= "string" then return nil, "no AssetCategory" end
    if RarityCache[category] then return RarityCache[category], "cache" end

    local note = "no module"
    local found
    pcall(function()
        local mod = GetAssetModule(category)
        if mod then
            local ok, t = pcall(require, mod)
            if ok and type(t) == "table" then
                found = DeepFindRarity(t, 0, {})
                note = found and "module" or "module has no rarity"
            else
                note = "module not readable"
            end
        end

        -- fallback: the Assets catalog itself may be keyed by category
        if not found then
            local data = ReplicatedStorage:FindFirstChild("Data")
            local catalog = data and data:FindFirstChild("Assets")
            if catalog and catalog:IsA("ModuleScript") then
                local ok, root = pcall(require, catalog)
                if ok and type(root) == "table" and type(root[category]) == "table" then
                    found = DeepFindRarity(root[category], 0, {})
                    if found then note = "catalog" end
                end
            end
        end
    end)

    if not found then
        local n = Lower(category)
        for _, pair in ipairs(NAME_RARITY_FALLBACK) do
            if string.find(n, pair[1], 1, true) then found = pair[2]; note = "name list"; break end
        end
    end

    if found then RarityCache[category] = found end
    return found, note
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

GuardDanger = function(area)
    local g = GUARD[area]
    return g ~= nil and MySpeed() < g.need
end

local function RarityFilterOn()
    local n = SetSize(SelectedRarities)
    return n > 0 and n < #RARITIES
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

    local rarity, note = ResolveRarity(rec)

    if RarityFilterOn() then
        if rarity then
            if not SelectedRarities[rarity] then return nil, "rarity " .. rarity end
        elseif not AllowUnknownRarity then
            return nil, "rarity unknown (" .. tostring(note) .. ")"
        end
    end

    if BiomeFilterOn() and not SelectedBiomes[Norm(rec.AreaId)] then
        return nil, "biome " .. tostring(rec.AreaId)
    end

    if SkipDangerous and GuardDanger(tostring(rec.AreaId)) then
        return nil, "guard too strong"
    end

    return {
        Uid = rec.Uid, Pos = pos, Rarity = rarity, Rank = rarity and RARITY_RANK[rarity] or 0,
        Area = tostring(rec.AreaId), Category = tostring(rec.AssetCategory), Size = tonumber(rec.AssetScale) or 0,
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
    local moduleNote

    for _, rec in pairs(Eggs) do
        total += 1
        local st = tostring(rec.State)
        states[st] = (states[st] or 0) + 1

        local egg, reason = EvaluateEgg(rec)
        if egg then passed += 1 else reasons[reason] = (reasons[reason] or 0) + 1 end

        local rarity, note = ResolveRarity(rec)
        if not rarity and not moduleNote and type(rec.AssetCategory) == "string" then
            local mod = GetAssetModule(rec.AssetCategory)
            if mod then
                local ok, t = pcall(require, mod)
                if ok and type(t) == "table" then
                    local keys = {}
                    for k in pairs(t) do table.insert(keys, tostring(k)) if #keys >= 14 then break end end
                    moduleNote = rec.AssetCategory .. " module keys: " .. table.concat(keys, ", ")
                end
            end
        end

        if #samples < 6 then
            table.insert(samples, string.format("%s | %s | %s | %s | %s | %s",
                tostring(rec.AssetCategory), tostring(rec.AreaId), st, rarity or "rarity?",
                GuardDanger(tostring(rec.AreaId)) and "guard chases" or "guard safe", egg and "MATCH" or reason))
        end
    end

    local head = string.format("%d tracked, %d match", total, passed)
    Log("---- Scan: " .. head)
    Log("my speed stat: " .. tostring(MySpeed()))
    Log("states: " .. JoinCounts(states))
    Log("skipped: " .. JoinCounts(reasons))
    for _, line in ipairs(samples) do Log(line) end
    if moduleNote then Log(moduleNote) end

    Notify("Scan", head, passed > 0 and "success" or "warning", 5)
end

OnEggSeen = function(rec, isNew)
    if not EggAlert or not isNew or rec.State ~= "Slot" then return end
    local egg = EvaluateEgg(rec)
    if egg then
        Notify("Egg Alert", string.format("%s · %s · %s", egg.Rarity or "?", egg.Category, egg.Area), "success", 5)
    end
end

--==============================================================
-- AUTO STEAL (filtered)
--==============================================================

local function RunAutoSteal(egg, id)
    -- never start while already carrying something
    if GetDropButton() then
        PauseUntil = os.clock() + 3
        Log("Already carrying an egg; Auto Steal waits.")
        return false
    end

    local guard = GUARD[egg.Area]
    SetStatus(string.format("Going to %s egg (%s, %s)", egg.Rarity or "?", egg.Category, egg.Area))
    Log(string.format("Target: %s | %s | %s%s", egg.Category, egg.Area, egg.Rarity or "rarity?",
        guard and (GuardDanger(egg.Area) and " | guard will chase you" or " | guard can't catch you") or ""))
    Notify("Auto Steal", string.format("%s · %s · %s", egg.Rarity or "?", egg.Category, egg.Area), "info", 3)

    AttemptedUntil[egg.Uid] = os.clock() + 25

    GetOffTreadmill()

    -- camera shows the egg's area; it follows you again once the egg is stolen
    CamLock(egg.Pos)
    local ok = GetEggBack(id, egg.Uid, egg.Pos)
    CamRelease()
    if not ok then return false end
    Log("Stole the target egg.")

    return RunDropWorkflow(id, egg.Pos, egg.Uid, false)
end

--==============================================================
-- MAIN LOOP (starts the first time an automation toggle is turned on)
--==============================================================

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
                local egg = PickBestEgg()
                if egg then
                    Busy = true
                    local id = NewJob()
                    local ok, err = pcall(RunAutoSteal, egg, id)
                    if not ok then Notify("Auto Steal", "Error: " .. tostring(err), "error", 4) end
                    CamRelease()
                    Busy = false
                    continue
                end
            end

            -- 2) treadmill: go there, wear it, stay; come back if you jump/walk off
            if AutoTreadmill then
                local spot = GetTreadmillSpot()
                local r = Root()
                local away = spot and r and (r.Position - spot).Magnitude > 8
                if (not Worn or away) and os.clock() >= TreadmillRetryAt then
                    Busy = true
                    local id = NewJob()
                    local ok, result = pcall(GoToTreadmill, id)
                    if not ok or result ~= true then TreadmillRetryAt = os.clock() + 6 end
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
    StopTween()
    CamRelease()
    Busy = false
    SpeedOverride = false
    local h = Hum()
    if h and h.Parent then h.WalkSpeed = DesiredWalkSpeed() end
    if reason then SetStatus(reason) end
end

--==============================================================
-- PLAYER FEATURES
--==============================================================

local function ApplySpeed()
    local h = Hum()
    if h and not SpeedOverride then h.WalkSpeed = DesiredWalkSpeed() end
end

-- Anti Ragdoll (also stops knockback/flinging): several layers, because the game's bats,
-- monsters and traps can push you in different ways.
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

            -- the script's own tweens/walks are skipped
            if not Busy and not SpeedOverride then
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
    if Noclip then
        local c = Char()
        if c then
            for _, part in ipairs(c:GetChildren()) do
                if part:IsA("BasePart") and part.CanCollide then part.CanCollide = false end
            end
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
local AUTO_EXECUTE_URL = "https://raw.githubusercontent.com/DevNameGelo/rap-rage/refs/heads/main/script.lua"
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
            -- the queue is used up when a teleport starts
            OnTeleportConn = LocalPlayer.OnTeleport:Connect(function(state)
                if state == Enum.TeleportState.Started or state == Enum.TeleportState.InProgress then
                    QueuedThisSession = true
                end
            end)
        end
        if not TeleportFailConn then
            -- teleport failed: we're still here, so queue again
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

    -- 1) the game shows an error message (kick / disconnect)
    table.insert(ReconnectConns, GuiService.ErrorMessageChanged:Connect(function(msg)
        if msg and msg ~= "" then task.spawn(TryRejoin) end
    end))

    -- 2) Roblox's error prompt appears
    pcall(function()
        local overlay = game:GetService("CoreGui").RobloxPromptGui.promptOverlay
        table.insert(ReconnectConns, overlay.ChildAdded:Connect(function(child)
            if child.Name == "ErrorPrompt" then task.spawn(TryRejoin) end
        end))
    end)

    -- 3) the connection to the server is lost
    pcall(function()
        local client = game:GetService("NetworkClient")
        table.insert(ReconnectConns, client.ChildRemoved:Connect(function()
            task.spawn(TryRejoin)
        end))
    end)

    -- 4) a teleport failed
    table.insert(ReconnectConns, TeleportService.TeleportInitFailed:Connect(function()
        task.spawn(TryRejoin)
    end))
end

--==============================================================
-- WINDOW
--==============================================================

Window = RageHub:CreateWindow({
    Name = "Rage Hub",
    Subtitle = "Steal An Egg",
    Theme = "Rage",
    Features = { Notifications = true },
    ConfigFolder = "RageHub/StealAnEgg",
    AutoSave = "autosave",
    Splash = true,
    OnUnload = function()
        Unloaded = true
        CamRelease()
        InstantSteal, AutoSteal, AutoTreadmill = false, false, false
        SpeedAdjust, InfiniteJump, Noclip = false, false, false
        SetAntiRagdoll(false)
        EggAlert, AutoEquipBest, AutoClaimAway = false, false, false
        Job += 1
        StopTween()
        SpeedOverride = false
        RestoreHolds()
        SetAntiAfk(false)
        SetAutoReconnect(false)
        SetAutoExecute(false)
        for _, c in ipairs(Connections) do pcall(function() c:Disconnect() end) end
        table.clear(Connections)
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
    Description = "One click on Steal, then the drop-area workflow",
    Callback = function(on)
        InstantSteal = on
        if on then
            EnsureListeners()
            ApplyFastToAll()
            Notify("Instant Steal", "ON: Steal hold = 0.1s. Click Steal to start the drop-area workflow.", "success", 3)
        else
            RestoreHolds()
            Notify("Instant Steal", "OFF: original hold time restored, no tween.", "info", 3)
        end
    end,
})

InstantSection:CreateParagraph({
    Title = "Workflow",
    Content = "Click Steal (camera stays on the egg) > tween to the drop area > stop > Drop > steal it back > tween to SpawnLocation. If the guard takes the egg it goes back with the Forest-egg trick: take a Forest egg, carry it to the target without stopping, drop it, steal the right egg.",
})

InstantSection:CreateDropdown({
    Name = "Drop Area", Flag = "DropArea",
    Options = { "Forest", "Lake", "Auto (nearest)" }, Default = "Forest",
    Description = "Where it stops to drop. Forest = first biome, weakest guard",
    Callback = function(v) if v then DropArea = v end end,
})

local TreadmillSection = StealTab:CreateSection("Auto Treadmill")

TreadmillSection:CreateToggle({
    Name = "Auto Treadmill", Flag = "AutoTreadmill", Default = false,
    Description = "Finds YOUR treadmill, stays on it, returns if you leave",
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

local AutoSection = StealTab:CreateSection("Auto Steal + Filter")

AutoSection:CreateToggle({
    Name = "Auto Steal (Filtered)", Flag = "AutoSteal", Default = false,
    Description = "Tween to a matching egg, steal it, same workflow",
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
    Options = RARITIES, Default = {},
    Description = "e.g. Divine + Eternal. Empty = any rarity",
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

AutoSection:CreateButton({
    Name = "Scan Eggs", ButtonText = "Scan",
    Description = "Fills the report below (why eggs match or not)",
    Callback = function() task.spawn(RunScan) end,
})

ScanLog = AutoSection:CreateLog({ Name = "Scan Report", Height = 150, MaxLines = 60 })

local WorkflowSection = StealTab:CreateSection("Workflow")

WorkflowSection:CreateToggle({
    Name = "Forest Decoy", Flag = "ForestDecoy", Default = true,
    Description = "Carry a Forest egg to the target, swap it for the target egg",
    Callback = function(on) UseDecoy = on end,
})

WorkflowSection:CreateToggle({
    Name = "Camera Focus", Flag = "CameraFocus", Default = true,
    Description = "Camera watches the egg area; follows you after the steal",
    Callback = function(on) CameraFocus = on; if not on then CamRelease() end end,
})

WorkflowSection:CreateToggle({
    Name = "Skip Strong Guards", Flag = "SkipStrongGuards", Default = false,
    Description = "Auto Steal ignores eggs whose guard you can't outrun",
    Callback = function(on) SkipDangerous = on end,
})

local MoveSection = StealTab:CreateSection("Movement")

MoveSection:CreateSlider({
    Name = "Treadmill Travel Speed", Flag = "TravelSpeed", Range = { 50, 1500 }, Increment = 25, Default = CFG.TravelSpeed,
    Suffix = " studs/s", Callback = function(v) CFG.TravelSpeed = v end,
})

MoveSection:CreateSlider({
    Name = "Approach Speed", Flag = "ApproachSpeed", Range = { 200, 3000 }, Increment = 50, Default = CFG.ApproachSpeed,
    Suffix = " studs/s", Description = "One fast tween toward an egg (no stopping)",
    Callback = function(v) CFG.ApproachSpeed = v end,
})

MoveSection:CreateSlider({
    Name = "Max Drop Tween Time", Flag = "LakeTween", Range = { 0.2, 3 }, Increment = 0.1, Default = CFG.LakeTweenSeconds,
    Suffix = " s", Description = "Far trips take at most this long",
    Callback = function(v) CFG.LakeTweenSeconds = v end,
})

MoveSection:CreateSlider({
    Name = "Drop Tween Speed", Flag = "DropTweenSpeed", Range = { 200, 3000 }, Increment = 50, Default = CFG.DropTweenSpeed,
    Suffix = " studs/s", Description = "Near trips are faster (adaptive)",
    Callback = function(v) CFG.DropTweenSpeed = v end,
})

MoveSection:CreateSlider({
    Name = "Drop Delay", Flag = "DropDelay", Range = { 0, 1 }, Increment = 0.05, Default = CFG.DropDelay,
    Suffix = " s", Description = "Stop at the drop area before clicking Drop",
    Callback = function(v) CFG.DropDelay = v end,
})

MoveSection:CreateButton({
    Name = "Stop Everything", ButtonText = "Stop",
    Description = "Cancels the current job and movement",
    Callback = function() CancelAll("Stopped") ; Notify("Rage Hub", "Stopped.", "info", 2) end,
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
    Description = "Blocks ragdoll, knockback and flinging",
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
-- OTHERS TAB (only actions the game itself already uses, from your spy log)
--==============================================================

local FarmSection = OthersTab:CreateSection("Auto Farm (game's own actions)")

local MaintLoopStarted = false
local LastEquip, LastClaim = 0, 0

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
        end
    end)
end

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

OthersTab:CreateSection("Needs a spy log"):CreateParagraph({
    Title = "Auto Place Egg / Hatch / Fuse / Race / Butterfly",
    Content = "Your logs have no calls for these, and guessing remote arguments is how you get kicked (this game has an anti-cheat that probes the client). Record a spy log while you do each one once and they can be added.",
})

Notify("Rage Hub", "Loaded.", "success", 3)

-- restore your saved config (filters + any toggles that were ON turn back on by themselves)
task.delay(1.2, function()
    if Unloaded then return end
    local ok, loaded = pcall(function() return Window:LoadConfig() end)
    if ok and loaded then
        Notify("Config", "Saved config restored.", "success", 3)
    end
end)