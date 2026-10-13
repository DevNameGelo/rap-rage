--// Rage Hub · Steal An Egg · v9
--// Tabs: Steal | Player | Others (+ Rage Hub's built-in Settings tab)
--//
--// SAFE STARTUP: when you execute this, it only builds the UI. Nothing moves, nothing connects
--// to game remotes, and every toggle is OFF. Each feature starts working only when YOU turn it on,
--// and toggles are never saved/restored.
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
    SpawnWalkSpeed = 200,     -- WalkSpeed while walking to SpawnLocation (same as your working file; slider goes higher)
    SupportOffset = 3,        -- stand this many studs above the Lake drop point
    LakeTweenSeconds = 0.8,   -- MAX tween time to the drop area (far trips take this long at most)
    DropTweenSpeed = 1000,    -- studs/s: near trips are faster than the max time (adaptive)
    MinTween = 0.2,           -- never faster than this
    DropDelay = 0.5,          -- stop at the drop area this long before clicking Drop
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
local AntiFling = false

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

local function TweenTo(pos, id, duration)
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
            return false
        end
        task.wait()
    end
    ActiveTween = nil

    local nr = Root()
    if nr then nr.AssemblyLinearVelocity = Vector3.zero end
    return nr ~= nil and (nr.Position - pos).Magnitude <= 4
end

-- "100%": re-tween until we really are at the target (up to 3 attempts)
local function TweenVerified(pos, id, duration)
    for attempt = 1, 3 do
        if TweenTo(pos, id, attempt == 1 and duration or nil) then return true end
        if Cancelled(id) then return false end
    end
    return false
end

local function DesiredWalkSpeed()
    return SpeedAdjust and CFG.PlayerSpeed or 16
end

local function WalkToSpawn(id)
    local spawn = workspace:FindFirstChild("SpawnLocation")
    local hum = Hum()
    if not spawn or not hum then
        Notify("Steal", "SpawnLocation or Humanoid not found.", "error")
        return false
    end

    local original = hum.WalkSpeed
    SpeedOverride = true
    hum.WalkSpeed = CFG.SpawnWalkSpeed
    SetStatus("Walking to SpawnLocation (" .. CFG.SpawnWalkSpeed .. ")")

    local target = Vector3.new(spawn.Position.X, spawn.Position.Y + 2, spawn.Position.Z)
    local arrived = false
    local t0 = os.clock()

    while os.clock() - t0 < 45 do
        if Cancelled(id) then break end
        local r, h = Root(), Hum()
        if not r or not h then break end
        if (r.Position - target).Magnitude <= 6 then arrived = true; break end
        h:MoveTo(target)       -- re-issued; MoveTo times out after a few seconds
        task.wait(0.2)
    end

    SpeedOverride = false
    local h = Hum()
    if h then
        h.WalkSpeed = SpeedAdjust and CFG.PlayerSpeed or original
    end
    return arrived
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

local function GetDropButton()
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

local function RunDropWorkflow(id)
    -- 0) the steal must really be registered BEFORE we move (Drop button = you carry an egg)
    local uid = (os.clock() - CarriedUidAt < 30) and CarriedUid or nil
    if not WaitFor(GetDropButton, 3, id, 0.03) then
        return Fail("Steal not registered (no Drop button). Not moving.")
    end
    uid = ((os.clock() - CarriedUidAt < 30) and CarriedUid) or uid

    local point = GetDropPoint()
    local pos = PositionOfObj(point)
    if not pos then return Fail("Drop point not found for " .. DropArea .. ". Stopped.") end
    local target = pos + Vector3.new(0, CFG.SupportOffset, 0)

    -- 1) tween to the drop area (adaptive time: near = fast, far = capped)
    local r = Root()
    if not r then return false end
    local seconds = DropTweenSeconds((r.Position - target).Magnitude)
    SetStatus(string.format("Tweening to %s (%.2fs)", DropArea, seconds))
    Log(string.format("Tween to %s in %.2fs", DropArea, seconds))
    if not TweenVerified(target, id, seconds) then
        return Fail("Could not reach the drop area. Stopped.")
    end

    -- arrival check: if the egg is already gone, something else dropped it
    if not GetDropButton() then
        return Fail("Egg was already dropped before arriving (not by the script). Stopped.")
    end

    -- 2) stop, then Drop
    Log(string.format("Arrived. Waiting %.2fs", CFG.DropDelay))
    SetStatus("Stopped at drop area")
    if CFG.DropDelay > 0 then task.wait(CFG.DropDelay) end
    if Cancelled(id) then return false end

    local btn = WaitFor(GetDropButton, 3, id, 0.03)
    if not btn then return Fail("Drop button vanished before clicking. Stopped (no spawn walk).") end

    local dropped = false
    for _ = 1, 10 do
        SetStatus("Clicking Drop")
        ClickGui(btn)
        task.wait(0.1)
        if not GetDropButton() then dropped = true; break end
        btn = GetDropButton() or btn
    end
    if not dropped then return Fail("Drop not confirmed. Stopped (no spawn walk).") end
    Log("Dropped.")

    -- 3) pick the dropped egg up again: its own prompt, not just any prompt
    SetStatus("Waiting for the dropped egg's Steal prompt")
    local prompt = WaitFor(function()
        local rec = uid and Eggs[uid]
        local eggPos = rec and rec.State == "Dropped" and EggPosition(rec)
        if eggPos then return FindPromptNearPos(eggPos, 6) end
        local me = Root()
        return me and FindPromptNearPos(me.Position, 14) or nil
    end, 6, id, 0.03)
    if not prompt then return Fail("Steal prompt did not show after Drop. Stopped (no spawn walk).") end

    local stolen = false
    for _ = 1, 6 do
        SetStatus("Clicking Steal")
        FirePrompt(prompt)
        -- carrying again = the Drop button is back
        if WaitFor(GetDropButton, 0.6, id, 0.03) then stolen = true; break end
        local rec = uid and Eggs[uid]
        if rec and tonumber(rec.CarrierUserId) == LocalPlayer.UserId then stolen = true; break end
        local eggPos = rec and rec.State == "Dropped" and EggPosition(rec)
        prompt = (eggPos and FindPromptNearPos(eggPos, 6)) or prompt
    end
    if not stolen then return Fail("Second Steal not confirmed. Stopped (no spawn walk).") end
    Log("Stole it back.")

    -- 4) walk to SpawnLocation
    local arrived = WalkToSpawn(id)
    if arrived then
        SetStatus("Done: reached SpawnLocation")
        Log("Reached SpawnLocation.")
        Notify("Steal", "Cycle complete.", "success", 2)
    else
        SetStatus("Spawn walk interrupted")
    end
    return arrived
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
        if tonumber(rec.CarrierUserId) == LocalPlayer.UserId then
            CarriedUid, CarriedUidAt = rec.Uid, os.clock()
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
            task.spawn(function()
                local ok, err = pcall(RunDropWorkflow, id)
                if not ok then Notify("Steal", "Workflow error: " .. tostring(err), "error", 4) end
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
            table.insert(samples, string.format("%s | %s | %s | %s | %s",
                tostring(rec.AssetCategory), tostring(rec.AreaId), st, rarity or "rarity?", egg and "MATCH" or reason))
        end
    end

    local head = string.format("%d tracked, %d match", total, passed)
    Log("---- Scan: " .. head)
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

    SetStatus(string.format("Going to %s egg (%s, %s)", egg.Rarity or "?", egg.Category, egg.Area))
    Log(string.format("Target: %s | %s | %s", egg.Category, egg.Area, egg.Rarity or "rarity?"))
    Notify("Auto Steal", string.format("%s · %s · %s", egg.Rarity or "?", egg.Category, egg.Area), "info", 3)

    AttemptedUntil[egg.Uid] = os.clock() + 25

    GetOffTreadmill()

    -- 1) tween to the egg
    if not TweenVerified(egg.Pos + Vector3.new(0, 3, 0), id) then return false end

    -- 2) the prompt that belongs to THIS egg only
    local prompt = WaitFor(function() return FindPromptNearPos(egg.Pos, 4) end, 3, id, 0.05)
    if not prompt then return Fail("No Steal prompt at that egg (it may be gone).") end

    local live = Eggs[egg.Uid]
    if not live or (live.State ~= "Slot" and live.State ~= "Dropped") then
        return Fail("Someone took that egg first.")
    end

    -- 3) steal it, and confirm it is THAT egg before going anywhere
    local stolen = false
    for _ = 1, 6 do
        SetStatus("Clicking Steal on the target egg")
        FirePrompt(prompt)

        local ok = WaitFor(function()
            local rec = Eggs[egg.Uid]
            return rec and tonumber(rec.CarrierUserId) == LocalPlayer.UserId
        end, 0.8, id, 0.03)
        if ok then stolen = true; break end

        if GetDropButton() then
            local rec = Eggs[egg.Uid]
            if not prompt.Parent or not prompt.Enabled or (rec and rec.State ~= "Slot") then
                stolen = true; break          -- target left its nest and we carry something
            end
            return Fail("Picked a different egg than the target. Stopped (drop it manually).")
        end
    end
    if not stolen then return Fail("Steal did not register on the target egg.") end
    Log("Stole the target egg.")

    -- 4) same workflow as Instant Steal: drop area -> stop -> Drop -> steal back -> spawn
    return RunDropWorkflow(id)
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

Track(RunService.Heartbeat:Connect(function()
    -- everything here is a no-op until you switch the matching toggle on
    if SpeedAdjust and not SpeedOverride then
        local h = Hum()
        if h and h.WalkSpeed ~= CFG.PlayerSpeed then h.WalkSpeed = CFG.PlayerSpeed end
    end

    if AntiRagdoll then
        local h = Hum()
        if h then
            local s = h:GetState()
            if s == Enum.HumanoidStateType.Ragdoll or s == Enum.HumanoidStateType.FallingDown
                or s == Enum.HumanoidStateType.Physics then
                h:ChangeState(Enum.HumanoidStateType.GettingUp)
            end
            if h.PlatformStand then h.PlatformStand = false end
        end
    end

    if AntiFling and not Busy then
        local r = Root()
        if r then
            local v = r.AssemblyLinearVelocity
            if v.Magnitude > math.max(150, CFG.PlayerSpeed * 2.5) then
                r.AssemblyLinearVelocity = Vector3.zero
                r.AssemblyAngularVelocity = Vector3.zero
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

    if AntiFling then
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
    Worn = false
    Carrying = false
    Busy = false
    Job += 1
    SpeedOverride = false
    task.wait(1)
    ApplySpeed()
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

-- Auto Reconnect (connected only while its toggle is on)
local ReconnectConns = {}
local ReconnectAttempts = 0
local function TryRejoin()
    if ReconnectAttempts >= 5 or Unloaded then return end
    ReconnectAttempts += 1
    task.wait(2)
    pcall(function() TeleportService:Teleport(game.PlaceId, LocalPlayer) end)
end

local function SetAutoReconnect(on)
    for _, c in ipairs(ReconnectConns) do pcall(function() c:Disconnect() end) end
    table.clear(ReconnectConns)
    ReconnectAttempts = 0
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
end

-- Auto Execute (re-runs a hosted copy of this script after you teleport/rejoin)
local ScriptUrl = ""
local AutoExecuteOn = false
local OnTeleportConn

local function QueueAutoExecute()
    local queue = queue_on_teleport or (syn and syn.queue_on_teleport) or (fluxus and fluxus.queue_on_teleport)
    if not queue then
        Notify("Auto Execute", "Your executor has no queue_on_teleport.", "error", 4)
        return false
    end
    if ScriptUrl == "" then
        Notify("Auto Execute", "Paste a raw script URL first.", "warning", 4)
        return false
    end
    queue(string.format("loadstring(game:HttpGet(%q))()", ScriptUrl))
    return true
end

local function SetAutoExecute(on)
    AutoExecuteOn = on
    if on then
        if QueueAutoExecute() then Notify("Auto Execute", "Queued for the next teleport.", "success", 3) end
        if not OnTeleportConn then
            OnTeleportConn = LocalPlayer.OnTeleport:Connect(function()
                if AutoExecuteOn then pcall(QueueAutoExecute) end
            end)
        end
    elseif OnTeleportConn then
        OnTeleportConn:Disconnect()
        OnTeleportConn = nil
    end
end

--==============================================================
-- WINDOW
--==============================================================

Window = RageHub:CreateWindow({
    Name = "Rage Hub",
    Subtitle = "Steal An Egg",
    Theme = "Rage",
    Features = { Notifications = true },
    ConfigFolder = "RageHub/StealAnEgg_v7",
    Splash = true,
    OnUnload = function()
        Unloaded = true
        InstantSteal, AutoSteal, AutoTreadmill = false, false, false
        SpeedAdjust, InfiniteJump, Noclip, AntiRagdoll, AntiFling = false, false, false, false, false
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
    Name = "Instant Steal", Default = false,
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
    Content = "Click Steal > (steal must register) > tween to the drop area > stop > click Drop > click the dropped egg's Steal > walk to SpawnLocation. If a step is not confirmed it stops and does not walk.",
})

InstantSection:CreateDropdown({
    Name = "Drop Area", Flag = "DropArea",
    Options = { "Forest", "Lake", "Auto (nearest)" }, Default = "Forest",
    Description = "Where it stops to drop. Forest = first biome, weakest guard",
    Callback = function(v) if v then DropArea = v end end,
})

local TreadmillSection = StealTab:CreateSection("Auto Treadmill")

TreadmillSection:CreateToggle({
    Name = "Auto Treadmill", Default = false,
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
    Name = "Auto Steal (Filtered)", Default = false,
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
    Name = "Allow Unknown Rarity", Default = false,
    Description = "Also take eggs whose rarity can't be read",
    Callback = function(on) AllowUnknownRarity = on end,
})

AutoSection:CreateToggle({
    Name = "Egg Alert", Default = false,
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

local MoveSection = StealTab:CreateSection("Movement")

MoveSection:CreateSlider({
    Name = "Travel Speed", Flag = "TravelSpeed", Range = { 50, 1500 }, Increment = 25, Default = CFG.TravelSpeed,
    Suffix = " studs/s", Callback = function(v) CFG.TravelSpeed = v end,
})

MoveSection:CreateSlider({
    Name = "Spawn Walk Speed", Flag = "SpawnWalkSpeed", Range = { 16, 500 }, Increment = 4, Default = CFG.SpawnWalkSpeed,
    Callback = function(v) CFG.SpawnWalkSpeed = v end,
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
    Name = "Speed Adjust", Default = false,
    Description = "Sets your WalkSpeed to the slider value",
    Callback = function(on) SpeedAdjust = on; ApplySpeed() end,
})

MovementSection:CreateSlider({
    Name = "Walk Speed", Flag = "PlayerSpeed", Range = { 16, 500 }, Increment = 2, Default = CFG.PlayerSpeed,
    Callback = function(v) CFG.PlayerSpeed = v; if SpeedAdjust then ApplySpeed() end end,
})

MovementSection:CreateToggle({
    Name = "Infinite Jump", Default = false,
    Callback = function(on) InfiniteJump = on end,
})

MovementSection:CreateToggle({
    Name = "Noclip", Default = false,
    Callback = function(on) Noclip = on end,
})

local ProtectSection = PlayerTab:CreateSection("Protection")

ProtectSection:CreateToggle({
    Name = "Anti Ragdoll", Default = false,
    Description = "Gets you back up when you are knocked down",
    Callback = function(on) AntiRagdoll = on end,
})

ProtectSection:CreateToggle({
    Name = "Anti Fling", Default = false,
    Description = "Stops other players from pushing/flinging you",
    Callback = function(on) AntiFling = on end,
})

local SessionSection = PlayerTab:CreateSection("Session")

SessionSection:CreateToggle({
    Name = "Anti AFK", Default = false,
    Callback = function(on) SetAntiAfk(on) end,
})

SessionSection:CreateToggle({
    Name = "Auto Reconnect", Default = false,
    Description = "Rejoins if you get disconnected",
    Callback = function(on) SetAutoReconnect(on) end,
})

SessionSection:CreateInput({
    Name = "Script URL (for Auto Execute)", Default = "", Width = 300,
    Placeholder = "https://raw.githubusercontent.com/you/repo/main/script.lua", Clearable = true,
    Description = "Host this script first, then paste its raw link",
    Callback = function(v)
        ScriptUrl = tostring(v or "")
        if AutoExecuteOn then QueueAutoExecute() end
    end,
})

SessionSection:CreateToggle({
    Name = "Auto Execute", Default = false,
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
    Name = "Auto Equip Best", Default = false,
    Description = "Calls the game's Equip Best every interval",
    Callback = function(on) AutoEquipBest = on; LastEquip = 0; if on then StartMaintLoop() end end,
})

FarmSection:CreateSlider({
    Name = "Equip Best Interval", Flag = "EquipInterval", Range = { 5, 300 }, Increment = 5, Default = CFG.EquipInterval,
    Suffix = " s", Callback = function(v) CFG.EquipInterval = v end,
})

FarmSection:CreateToggle({
    Name = "Auto Claim Away Earnings", Default = false,
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

ScriptSection:CreateButton({
    Name = "Unload Script", ButtonText = "Unload",
    Description = "Stops everything and removes the UI",
    Callback = function() pcall(function() Window:Destroy() end) end,
})

OthersTab:CreateSection("Needs a spy log"):CreateParagraph({
    Title = "Auto Place Egg / Hatch / Fuse / Race / Butterfly",
    Content = "Your logs have no calls for these, and guessing remote arguments is how you get kicked (this game has an anti-cheat that probes the client). Record a spy log while you do each one once and they can be added.",
})

Notify("Rage Hub", "Loaded. Everything is OFF until you turn it on.", "success", 4)