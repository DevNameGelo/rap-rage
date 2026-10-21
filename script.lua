--//==============================================================
--//  Rage Hub · Steal An Egg · alpha  (Flight Edition)
--//==============================================================
--//  Target: Delta (mobile executor), Rage Hub v1.0.0 UI library.
--//
--//  MOVEMENT : CFrame-stepped glide (the method that already worked
--//             for you), 500 studs/s cruise, +50 studs offset, climb
--//             and cruise together, vertical descent only inside the
--//             last 25 studs, stop 3 studs above the target. Velocity
--//             is zeroed every frame so nothing fights the humanoid.
--//             Takeoff ramps up from standstill and the final studs
--//             brake to a stop, so every replicated position delta
--//             stays smooth - no teleport-like spikes.
--//
--//  ANTI-DETECTION (honest scope - there is no bypass code here):
--//             * loading moves NOTHING and calls NO remotes. The
--//               first seconds only build the UI and attach passive
--//               read-only listeners, exactly like any game UI.
--//             * nothing hooks, blocks, fakes or races the anti-cheat
--//               or RigSync. Armed anti-TP regions (MonsterEventMap /
--//               AnticheatSuspendedRegion) are READ, then flown over,
--//               flown around, or the egg is refused.
--//             * glides ramp in and brake out, so replication sees
--//               continuous motion instead of jumps.
--//             * what cannot be promised: a server that started
--//               checking raw speed could still flag 500 studs/s.
--//               No honest script can guarantee invisibility - this
--//               one refuses to fake its way around that.
--//
--//  HONESTY  : nothing in this file was executed inside Roblox. It
--//             passes luau-compile + luau-analyze only. Remotes are
--//             called with the exact shapes the game's own client
--//             sends (shapes taken from your RageDump). Nothing is
--//             hooked, blocked, faked or replayed - no firesignal on
--//             server events, no RigSync / anti-cheat tampering.
--//==============================================================

local LibraryOk, RageHub = pcall(function()
    local chunk = loadstring(game:HttpGet("https://raw.githubusercontent.com/devnamegelo/Rage-Hub/main/RageHub.lua"))
    if type(chunk) ~= "function" then return nil end
    return chunk()
end)
if not LibraryOk or type(RageHub) ~= "table" then
    warn("[RageHub] could not load the UI library - aborting.")
    return
end

--==============================================================
-- SERVICES
--==============================================================

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")
local GuiService       = game:GetService("GuiService")
local HttpService      = game:GetService("HttpService")

local LocalPlayer = Players.LocalPlayer

--==============================================================
-- CONSTANTS  (all numbers live here - no sliders in the UI)
--==============================================================

local VERSION            = "alpha"
local AUTO_EXECUTE_URL   = "https://raw.githubusercontent.com/DevNameGelo/rap-rage/refs/heads/main/script.lua"
local PREFS_PATH         = "RageHub/StealAnEgg/_prefs.json"

local FLIGHT_SPEED       = 500     -- studs/s cruise + climb speed
local RAMP_TIME          = 0.5     -- s takeoff acceleration (smooth replication deltas)
local BRAKE_RANGE        = 14      -- studs of proportional braking before the stop
local CRUISE_OFFSET      = 50      -- glide this far above max(start, target)
local GROUND_CLEARANCE   = 60      -- never cruise lower than ground + 60
local DESCEND_RANGE      = 25      -- horizontal studs where descent begins
local STOP_ABOVE         = 3       -- stop this far above the target
local GROUND_WAIT_MAX    = 2.5     -- s to hover waiting for terrain to stream
local GROUND_RAY_DEPTH   = 90      -- studs of downward raycast at descent
local JOB_TIMEOUT        = 45      -- s hard timeout per glide
local PRESTREAM_DISTANCE = 1500    -- studs: target farther than this gets pre-streamed
local TWOLEG_DISTANCE    = 1500    -- farther than this = glide in two legs
local TWOLEG_BACKOFF     = 900     -- first leg stops this far before the target
local REGION_INFLATE     = 35      -- extra margin around armed anti-TP regions
local REGION_OVER_CLEAR  = 25      -- clearance above a region we fly over

local CARRY_RETRIES      = 3       -- AskFieldEggCarry attempts
local CARRY_RETRY_GAP    = 0.05    -- s between attempts
local SATCHEL_PAUSE      = 15      -- s pause when the satchel is full
local VERDICT_WAIT       = 3       -- s to wait for FieldEggRedeemVerdict
local JOB_COOLDOWN       = 1.5     -- s between steal jobs
local MAX_RECOVERIES     = 2       -- recovery attempts per egg
local BLACKLIST_GROUND   = 30      -- s blacklist when terrain never loads
local BLACKLIST_FAIL     = 60      -- s blacklist after 2 failed jobs on one uid
local RAGDOLL_WAIT_MAX   = 4       -- s to wait a ragdoll out during recovery
local EGG_RECOVER_WAIT   = 8       -- s to wait for a guard to return an egg

local TREADMILL_UNWORN   = 1.5     -- s unworn before re-wearing
local TREADMILL_GAP      = 3       -- s minimum between wear attempts

local SELL_INTERVAL      = 5       -- s between Auto Sell passes
local PLACE_INTERVAL     = 2       -- s between Auto Place eggs
local HATCH_TIME         = 6.2     -- s between AskHatch and AskFinishHatch
local BESTPET_INTERVAL   = 30      -- s between WearBest checks
local CLAIM_INTERVAL     = 120     -- s between money claims
local UPGRADE_INTERVAL   = 10      -- s between treadmill upgrade checks
local BUYTRAIL_INTERVAL  = 60      -- s between trail purchase checks
local AFK_INTERVAL       = 45      -- s between virtual input heartbeats
local REMOTE_FAIL_LIMIT  = 5       -- consecutive transport failures -> auto-disable
local RECONNECT_MAX      = 8       -- rejoin attempts

-- The only field-egg rarities that exist (fallback if Data.Assets can't be read)
local FALLBACK_RARITIES = {
    "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Cosmic", "Secret", "Eternal", "Divine",
}
local FALLBACK_RANKS = {
    Common = 1, Uncommon = 2, Rare = 3, Epic = 4, Legendary = 5, Mythic = 6,
    Cosmic = 7, Secret = 8, Eternal = 9, Divine = 10,
}
-- Real areas (fallback if GuardAreas can't be walked; Enchanted Forest is WIP and excluded)
local FALLBACK_BIOMES = {
    "Forest", "Lake", "Desert", "Jungle", "Snow", "Volcano", "Abyss Ocean",
    "Prehistoric", "Cosmic", "Cherry Blossom", "Titan Temple", "Light Dark",
}
local SAFEZONE_FALLBACK = { X = 457.0, Z = -364.2, HX = 95.3, HZ = 219.4 }

--==============================================================
-- PREFS  (read before the window exists so Auto Load = off works)
--==============================================================

local Prefs = { AutoSave = true, AutoLoad = true }
do
    local okPrefs = pcall(function()
        if type(isfile) ~= "function" or type(readfile) ~= "function" then return end
        if not isfile(PREFS_PATH) then return end
        local decoded = HttpService:JSONDecode(readfile(PREFS_PATH))
        if type(decoded) == "table" then
            if decoded.AutoSave == false then Prefs.AutoSave = false end
            if decoded.AutoLoad == false then Prefs.AutoLoad = false end
        end
    end)
    if not okPrefs then Prefs.AutoSave, Prefs.AutoLoad = true, true end
end

local function SavePrefs()
    pcall(function()
        if type(makefolder) ~= "function" or type(writefile) ~= "function" then return end
        makefolder("RageHub")
        makefolder("RageHub/StealAnEgg")
        writefile(PREFS_PATH, HttpService:JSONEncode({ AutoSave = Prefs.AutoSave, AutoLoad = Prefs.AutoLoad }))
    end)
end

--==============================================================
-- FORWARD DECLARATIONS  (window + elements are built at the end)
--==============================================================

local Window, StatusLabel
local RarityDropdown, BiomeDropdown

--==============================================================
-- RUNTIME  (one table for every piece of transient state)
--==============================================================

local Runtime = {
    Alive = true, Token = 0, Busy = false, Gliding = false, JobMode = nil,
    CooldownUntil = 0, PauseUntil = 0, LastStatus = "",
    Carry = { IsCarrying = false, Uid = nil, Redeemed = false, LostAt = 0 },
    LastVerdictUid = nil,
    Eggs = {}, Blacklist = {}, JobFailures = {},
    RarityByUid = {}, KnownRarities = {},
    CamFocus = nil, ReplicationPart = nil,
    Conns = {},
    Treadmill = { Worn = false, UnwornAt = 0, LastWear = 0, TierId = nil },
    MyPlotSlot = nil,
    Profile = { Money = nil, EggInventory = {}, Inventory = {}, EquippedAssets = nil },
    HatchQueue = {}, HatchStarted = {}, HatchRetryAt = {},
    TrailAttempted = {}, TrailFalseCount = {},
    Butterfly = { Fails = 0, LastSwing = 0, NetReach = 25, Cooldown = 1.5, Connected = false },
    MotorBase = {}, KnownPhysics = {}, SavedCollide = {}, AntiRagdollOn = false,
    AutoExecuteQueued = false, Rejoining = false, ReconnectRetries = 0,
    LastTeleport = nil, HopBusy = false,
    RemoteFails = {},
    PlaceFalseStreak = 0, PlacePauseUntil = 0, LastOthersApply = 0,
    HatchFinFails = {}, LastHatchStart = 0, LastPetSig = "",
}

local function SetStatus(text)
    if Runtime.LastStatus == text then return end
    Runtime.LastStatus = text
    if StatusLabel then pcall(function() StatusLabel:Set(text) end) end
end

local function Notify(title, content, kind, duration)
    if not Window then return end
    pcall(function()
        Window:Notify({ Title = title, Content = content, Type = kind or "info", Duration = duration or 4 })
    end)
end

-- Config loads fire every element callback synchronously (that is how
-- the library applies values). Without a guard, loading a saved
-- "Auto Load Config = true" fires that toggle's callback, which loads
-- the config again, which fires the callback again... an infinite loop
-- that spammed "Saved config restored" notifications forever. One
-- guard breaks the cycle: callbacks echoed from a load in progress are
-- ignored, so only a real tap on the toggle ever loads again.
local ConfigLoading = false
local function SafeLoadConfig()
    if ConfigLoading or not Window then return false end
    ConfigLoading = true
    local ok, applied = pcall(function() return Window:LoadConfig() end)
    ConfigLoading = false
    return ok and applied == true
end

local function NewToken()
    Runtime.Token += 1
    return Runtime.Token
end

local function TokenAlive(token)
    return Runtime.Alive and Runtime.Token == token
end

local function BlacklistUid(uid, seconds)
    Runtime.Blacklist[uid] = os.clock() + seconds
end

local function Blacklisted(uid)
    local until_ = Runtime.Blacklist[uid]
    if until_ and os.clock() < until_ then return true end
    Runtime.Blacklist[uid] = nil
    return false
end

--==============================================================
-- REMOTE LAYER  (cache + pcall + per-feature failure counter)
--==============================================================

local NetRoot do
    local packages = ReplicatedStorage:WaitForChild("Packages", 20)
    NetRoot = packages and packages:WaitForChild("Networking", 20) or nil
end

local RemoteCache = {}
local function Net(kind, path)
    local key = kind .. "/" .. path
    local cached = RemoteCache[key]
    if cached ~= nil then return cached end
    local node = NetRoot
    if node then
        for segment in path:gmatch("[^/]+") do
            node = node:WaitForChild(segment, 8)
            if not node then break end
        end
    end
    if node and not node:IsA("RemoteFunction") and not node:IsA("RemoteEvent") then node = nil end
    RemoteCache[key] = node
    return node
end

local function InvokeRemote(node, ...)
    if not node then return false, "no-remote" end
    local packed = table.pack(...)
    local ok, a, b, c = pcall(function()
        return node:InvokeServer(table.unpack(packed, 1, packed.n))
    end)
    if ok then return true, a, b, c end
    return false, tostring(a)
end

local function FireRemote(node, ...)
    if not node then return false, "no-remote" end
    local packed = table.pack(...)
    local ok, err = pcall(function()
        node:FireServer(table.unpack(packed, 1, packed.n))
    end)
    return ok, err
end

-- Calls InvokeRemote but counts consecutive transport failures per feature
-- flag; after REMOTE_FAIL_LIMIT it switches that toggle off and tells you once.
local function FeatureInvoke(flagName, node, ...)
    local ok, a, b, c = InvokeRemote(node, ...)
    if ok then
        Runtime.RemoteFails[flagName] = 0
        return true, a, b, c
    end
    Runtime.RemoteFails[flagName] = (Runtime.RemoteFails[flagName] or 0) + 1
    if Runtime.RemoteFails[flagName] >= REMOTE_FAIL_LIMIT and Window then
        local element = Window:GetElement(flagName)
        if element and element.Set and element.Get and element:Get() == true then
            Notify(flagName, "Disabled after " .. tostring(Runtime.RemoteFails[flagName]) .. " remote failures in a row.", "warning", 5)
            pcall(function() element:Set(false) end)
        end
    end
    return false, a
end

local function Track(conn)
    Runtime.Conns[#Runtime.Conns + 1] = conn
    return conn
end

--==============================================================
-- FLAG READERS  (Rage Hub keeps Window.Flags live: creation,
-- user input and config load all go through Commit)
--==============================================================

local function FlagOn(name)
    if not Window then return false end
    return Window.Flags[name] == true
end

local function FlagSet(name)
    local list = Window and Window.Flags[name]
    local set = {}
    if type(list) == "table" then
        for _, item in ipairs(list) do set[tostring(item)] = true end
    elseif type(list) == "string" then
        set[list] = true
    end
    return set
end

local function CancelJobs()
    NewToken()
    Runtime.Busy = false
    Runtime.Gliding = false
end

--==============================================================
-- SUPERVISORS  (a loop that can never die: pcall + heartbeat +
-- watchdog restart; character respawn does NOT restart them)
--==============================================================

local Supervisors = {}
local function Supervisor(name, interval, fn)
    local entry = { Name = name, Interval = interval, Fn = fn, HB = os.clock(), Gen = 0 }
    Supervisors[name] = entry
    local function run()
        local gen = entry.Gen
        while Runtime.Alive and entry.Gen == gen do
            entry.HB = os.clock()
            local ok, err = pcall(fn)
            if not ok then warn("[RageHub:" .. name .. "] " .. tostring(err)) end
            task.wait(interval)
        end
    end
    function entry.Restart()
        entry.Gen += 1
        task.spawn(run)
    end
    entry.Restart()
    return entry
end

--==============================================================
-- CHARACTER HELPERS  (re-fetched every use: cached rigs are stale
-- after RigSync/AskRigWipe respawns)
--==============================================================

local function Char()
    local char = LocalPlayer.Character
    if not char or not char.Parent then return nil end
    local hum = char:FindFirstChildOfClass("Humanoid")
    local root = char:FindFirstChild("HumanoidRootPart")
    if not hum or not root or hum.Health <= 0 then return nil end
    return char, hum, root
end

local function IsRagdolled()
    local ragEnd = LocalPlayer:GetAttribute("RagdollEndTime")
    local char = LocalPlayer.Character
    if not ragEnd and char then ragEnd = char:GetAttribute("RagdollEndTime") end
    if ragEnd and workspace:GetServerTimeNow() < ragEnd then return true end
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if hum then
        local state = hum:GetState()
        if state == Enum.HumanoidStateType.Ragdoll or state == Enum.HumanoidStateType.FallingDown then
            return true
        end
    end
    return false
end

local function Cam()
    return workspace.CurrentCamera
end

local RayParams = RaycastParams.new()
RayParams.FilterType = Enum.RaycastFilterType.Exclude
local function RayDown(fromPos, range)
    local char = LocalPlayer.Character
    RayParams.FilterDescendantsInstances = char and { char } or {}
    return workspace:Raycast(fromPos, Vector3.new(0, -range, 0), RayParams)
end

local function FindPartNear(pos, radius)
    local params = OverlapParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    local char = LocalPlayer.Character
    params.FilterDescendantsInstances = char and { char } or {}
    local parts = workspace:GetPartBoundsInRadius(pos, radius, params)
    return parts[1]
end

--==============================================================
-- ARMED ANTI-TP REGIONS  (read-only: avoid, never bypass)
--==============================================================

local function ArmedRegion()
    if workspace:GetAttribute("ClientObbyAntiTp") == false then return nil end
    local box = workspace:FindFirstChild("MonsterEventMap")
    if box and box:IsA("Model") then
        local okCF, cf, size = pcall(function() return box:GetBoundingBox() end)
        if okCF and typeof(cf) == "CFrame" and typeof(size) == "Vector3" then
            return { Min = cf.Position - size / 2, Max = cf.Position + size / 2 }
        end
        return nil
    end
    local attr = workspace:GetAttribute("AnticheatSuspendedRegion")
    if type(attr) == "string" then
        local nums = {}
        for token in attr:gmatch("[^,]+") do
            local value = tonumber(token)
            if value then nums[#nums + 1] = value end
        end
        if #nums >= 6 then
            local minV = Vector3.new(nums[1], nums[2], nums[3])
            local maxV = Vector3.new(nums[4], nums[5], nums[6])
            if maxV.X >= minV.X and maxV.Y >= minV.Y and maxV.Z >= minV.Z then
                return { Min = minV, Max = maxV }
            end
        end
    end
    return nil
end

local function PosInBox(pos, minV, maxV)
    return pos.X >= minV.X and pos.X <= maxV.X
       and pos.Y >= minV.Y and pos.Y <= maxV.Y
       and pos.Z >= minV.Z and pos.Z <= maxV.Z
end

-- Liang-Barsky clip of the XZ projection of a segment against a rectangle.
local function SegmentHitsRectXZ(a, b, minV, maxV)
    local t0, t1 = 0, 1
    local dx, dz = b.X - a.X, b.Z - a.Z
    local edges = {
        { -dx, a.X - minV.X }, { dx, maxV.X - a.X },
        { -dz, a.Z - minV.Z }, { dz, maxV.Z - a.Z },
    }
    for i = 1, 4 do
        local p, q = edges[i][1], edges[i][2]
        if p == 0 then
            if q < 0 then return false end
        else
            local r = q / p
            if p < 0 then
                if r > t1 then return false end
                if r > t0 then t0 = r end
            else
                if r < t0 then return false end
                if r < t1 then t1 = r end
            end
        end
    end
    return true
end

--==============================================================
-- CAMERA + STREAMING  (the game's own cutscene pattern: camera on
-- the target, ReplicationFocus on a real part near it)
--==============================================================

local function SetReplicationTarget(part)
    if Runtime.ReplicationPart == part then return end
    Runtime.ReplicationPart = part
    pcall(function() LocalPlayer.ReplicationFocus = part end)
end

local function ReleaseCamera()
    Runtime.CamFocus = nil
    SetReplicationTarget(nil)
    pcall(function()
        local camera = Cam()
        if camera and camera.CameraType == Enum.CameraType.Scriptable then
            camera.CameraType = Enum.CameraType.Custom
        end
        local _, humNow = Char()
        if humNow and camera then camera.CameraSubject = humNow end
    end)
end

local function FocusOn(pos)
    Runtime.CamFocus = { Pos = pos }
end

-- one permanent draw loop: while a focus is set, the camera sits behind
-- the character and looks at the focus point (egg visible, you visible)
Track(RunService.RenderStepped:Connect(function()
    local okDraw, errDraw = pcall(function()
        local focus = Runtime.CamFocus
        if not focus then return end
        local _, _, rootNow = Char()
        if not rootNow then return end
        local camera = Cam()
        if not camera then return end
        local targetPos = focus.Pos
        local myPos = rootNow.Position
        local backX, backZ = myPos.X - targetPos.X, myPos.Z - targetPos.Z
        local backMag = math.sqrt(backX * backX + backZ * backZ)
        local dirX, dirZ = 0, 1
        if backMag > 2 then
            dirX, dirZ = backX / backMag, backZ / backMag
        end
        local camPos = Vector3.new(myPos.X + dirX * 16, myPos.Y + 10, myPos.Z + dirZ * 16)
        if camera.CameraType ~= Enum.CameraType.Scriptable then
            camera.CameraType = Enum.CameraType.Scriptable
        end
        camera.CFrame = CFrame.lookAt(camPos, targetPos)
    end)
    if not okDraw then warn("[RageHub:Cam] " .. tostring(errDraw)) end
end))

local function PreStream(targetPos)
    if not workspace.StreamingEnabled then return end
    local _, _, rootNow = Char()
    if not rootNow then return end
    if (rootNow.Position - targetPos).Magnitude <= PRESTREAM_DISTANCE then return end
    pcall(function() LocalPlayer:RequestStreamAroundAsync(targetPos, 2) end)
    local deadline = os.clock() + 2.5
    local found = nil
    while os.clock() < deadline and Runtime.Alive do
        found = FindPartNear(targetPos, 40)
        if found then break end
        task.wait(0.15)
    end
    if found then SetReplicationTarget(found) end
end

--==============================================================
-- RESET  (death / respawn: clear transient state, keep knowledge)
--==============================================================

local function ResetRuntime()
    NewToken()
    Runtime.Busy = false
    Runtime.Gliding = false
    Runtime.JobMode = nil
    Runtime.Carry = { IsCarrying = false, Uid = nil, Redeemed = false, LostAt = 0 }
    Runtime.Treadmill.Worn = false
    Runtime.Treadmill.UnwornAt = os.clock()
    ReleaseCamera()
end

--==============================================================
-- GLIDE  (one continuous CFrame-stepped flight per leg)
--   climb+cruise at 500 studs/s toward the point above the target,
--   descend only inside the last 25 studs, stop 3 studs above it.
--   Takeoff ramps up from standstill and the final studs brake to a
--   stop (smooth deltas: nothing looks like a teleport spike).
--   Returns: true  |  false, reason  (cancelled / dead / ragdoll /
--   region / ground / timeout / busy / error)
--==============================================================

local function Glide(targetPos, token, opts)
    opts = opts or {}
    local checkFn = opts.Check
    local timeout = opts.Timeout or JOB_TIMEOUT
    if Runtime.Gliding then return false, "busy" end

    local _, _, root = Char()
    if not root then return false, "dead" end
    if IsRagdolled() then return false, "ragdoll" end

    local startPos = root.Position

    -- armed anti-TP regions: never glide through, never start/end inside
    local region = ArmedRegion()
    local overY = nil
    if region then
        if PosInBox(startPos, region.Min, region.Max) then return false, "region" end
        if PosInBox(targetPos, region.Min, region.Max) then return false, "region" end
        local infMin = region.Min - Vector3.new(REGION_INFLATE, REGION_INFLATE, REGION_INFLATE)
        local infMax = region.Max + Vector3.new(REGION_INFLATE, REGION_INFLATE, REGION_INFLATE)
        if SegmentHitsRectXZ(startPos, targetPos, infMin, infMax) then
            overY = region.Max.Y + REGION_OVER_CLEAR
        end
    end

    local cruiseY = math.max(startPos.Y, targetPos.Y) + CRUISE_OFFSET
    if overY then cruiseY = math.max(cruiseY, overY + 15) end

    Runtime.Gliding = true
    local done, reason = false, nil
    local startedAt = os.clock()
    local groundHold, streamedRetry = 0, false
    local traveled, nextSample = 0, 0
    local climbing = overY ~= nil

    local function step(dt)
        if done then return end
        if not TokenAlive(token) then reason = "cancelled"; done = true; return end
        local char2, _, root2 = Char()
        if not char2 then reason = "dead"; done = true; return end
        if IsRagdolled() then reason = "ragdoll"; done = true; return end
        if os.clock() - startedAt > timeout then reason = "timeout"; done = true; return end
        if checkFn then
            local abort, why = checkFn(root2.Position)
            if abort then reason = why or "cancelled"; done = true; return end
        end

        root2.AssemblyLinearVelocity = Vector3.zero
        root2.AssemblyAngularVelocity = Vector3.zero

        local pos = root2.Position
        local flatDist = math.sqrt((pos.X - targetPos.X) ^ 2 + (pos.Z - targetPos.Z) ^ 2)

        -- sample the ground every 150 studs and keep 60 studs of clearance
        if traveled >= nextSample then
            nextSample = traveled + 150
            local hit = RayDown(Vector3.new(pos.X, pos.Y + 5, pos.Z), 260)
            if hit then
                local floorY = hit.Position.Y + GROUND_CLEARANCE
                if floorY > cruiseY then cruiseY = floorY end
            end
        end

        local aim = nil
        if climbing then
            if math.abs(pos.Y - cruiseY) < 2 then
                climbing = false
            else
                aim = Vector3.new(pos.X, cruiseY, pos.Z)
            end
        end
        if not aim then
            if flatDist > DESCEND_RANGE then
                aim = Vector3.new(targetPos.X, cruiseY, targetPos.Z)
            else
                aim = Vector3.new(targetPos.X, targetPos.Y + STOP_ABOVE, targetPos.Z)
            end
        end

        local delta = aim - pos
        local dist = delta.Magnitude
        if dist <= 0.75 then
            if not climbing then done = true end
            return
        end

        -- descent gate: only descend where a raycast finds ground
        if not climbing and flatDist <= DESCEND_RANGE and pos.Y > targetPos.Y + STOP_ABOVE + 2 then
            local ground = RayDown(pos, GROUND_RAY_DEPTH + math.max(pos.Y - targetPos.Y, 0))
            if not ground then
                groundHold += dt
                if not streamedRetry then
                    streamedRetry = true
                    pcall(function() LocalPlayer:RequestStreamAroundAsync(targetPos, 2) end)
                end
                if groundHold > GROUND_WAIT_MAX then
                    reason = "ground"
                    done = true
                end
                return
            else
                groundHold = 0
            end
        end

        -- smooth takeoff + landing: speed ramps up from standstill and
        -- brakes near the target, so the server never sees a teleport
        -- spike where motion starts or stops at full speed
        local speed = FLIGHT_SPEED
        local elapsed = os.clock() - startedAt
        if elapsed < RAMP_TIME then
            local ramp = math.clamp(elapsed / RAMP_TIME, 0, 1)
            speed = FLIGHT_SPEED * (0.25 + 0.75 * ramp * ramp)
        end
        if dist < BRAKE_RANGE then
            speed = math.min(speed, math.max(70, FLIGHT_SPEED * dist / BRAKE_RANGE))
        end
        local stepDist = math.min(speed * dt, dist)
        local newPos = pos + (delta / dist) * stepDist
        traveled += stepDist
        root2.CFrame = CFrame.new(newPos) * root2.CFrame.Rotation
    end

    local conn = RunService.Heartbeat:Connect(function(dt)
        local okStep, errStep = pcall(step, dt)
        if not okStep then
            reason = "error"
            done = true
            warn("[RageHub:Glide] " .. tostring(errStep))
        end
    end)

    while not done and Runtime.Alive do
        if os.clock() - startedAt > timeout + 3 then
            reason = reason or "timeout"
            done = true
        end
        task.wait(0.05)
    end
    pcall(function() conn:Disconnect() end)
    Runtime.Gliding = false

    if reason then return false, reason end
    if not Runtime.Alive then return false, "cancelled" end
    return true
end

--==============================================================
-- EGG DATA  (snapshot + live events; carry state comes ONLY from
-- the server, never from the Drop GUI)
--==============================================================

local AssetsDir, RarityDir
pcall(function()
    local dataFolder = ReplicatedStorage:WaitForChild("Data", 10)
    local assetsModule = dataFolder and dataFolder:WaitForChild("Assets", 5)
    local rarityModule = dataFolder and dataFolder:WaitForChild("Rarity", 5)
    if assetsModule then AssetsDir = require(assetsModule).Directory end
    if rarityModule then RarityDir = require(rarityModule).Rarities end
end)

local CategoryRarity = {}
local function RarityOf(category)
    if type(category) ~= "string" then return nil end
    local known = CategoryRarity[category]
    if known ~= nil then return known end
    if type(AssetsDir) == "table" then
        local asset = AssetsDir[category]
        if type(asset) == "table" and type(asset.Rarity) == "table" and type(asset.Rarity._id) == "string" then
            CategoryRarity[category] = asset.Rarity._id
            return asset.Rarity._id
        end
    end
    return nil
end

local function RankOf(rarity)
    if type(rarity) ~= "string" then return 0 end
    if type(RarityDir) == "table" then
        local info = RarityDir[rarity]
        if type(info) == "table" and type(info.Rank) == "number" then return info.Rank end
    end
    return FALLBACK_RANKS[rarity] or 0
end

local function ForEachRecord(container, fn)
    if type(container) ~= "table" then return end
    for _, rec in container do
        if type(rec) == "table" then fn(rec) end
    end
end

local function ApplyRecord(rec)
    if type(rec) ~= "table" then return end
    local uid = rec.Uid
    if type(uid) ~= "string" then return end
    if rec.State == "Claimed" or rec.State == "Gone" then
        Runtime.Eggs[uid] = nil
    else
        Runtime.Eggs[uid] = rec
    end
end

local function RecordPos(rec)
    local cf = rec.BottomCFrame
    if typeof(cf) ~= "CFrame" then cf = rec.BoundsCFrame end
    if typeof(cf) == "CFrame" then return cf.Position end
    return nil
end

local function RefreshSnapshot()
    local ok, result = InvokeRemote(Net("RF", "EggWorld/AskFieldEggSnapshot"))
    if ok and type(result) == "table" and type(result.Records) == "table" then
        Runtime.Eggs = {}
        ForEachRecord(result.Records, ApplyRecord)
        return true
    end
    return false
end

local function BuildRarityOptions()
    local seen, list = {}, {}
    if type(AssetsDir) == "table" then
        for _, asset in AssetsDir do
            if type(asset) == "table" and type(asset.Rarity) == "table" then
                local rid = asset.Rarity._id
                if type(rid) == "string" and (tonumber(asset.DropWeight) or 0) > 0 and not seen[rid] then
                    seen[rid] = true
                    list[#list + 1] = rid
                end
            end
        end
    end
    for _, rec in Runtime.Eggs do
        local rid = RarityOf(rec.AssetCategory)
        if rid and not seen[rid] then
            seen[rid] = true
            list[#list + 1] = rid
        end
    end
    for uid, rid in Runtime.RarityByUid do
        if Runtime.Eggs[uid] and rid and not seen[rid] then
            seen[rid] = true
            list[#list + 1] = rid
        end
    end
    if #list == 0 then
        for _, rid in FALLBACK_RARITIES do list[#list + 1] = rid end
    end
    table.sort(list, function(x, y) return RankOf(x) < RankOf(y) end)
    Runtime.KnownRarities = {}
    for _, rid in list do Runtime.KnownRarities[rid] = true end
    return list
end

local function BuildBiomeOptions()
    local seen, list = {}, {}
    local areas = workspace:FindFirstChild("World")
    areas = areas and areas:FindFirstChild("Areas")
    areas = areas and areas:FindFirstChild("GuardAreas")
    if areas then
        for _, area in areas:GetChildren() do
            local areaName = area.Name
            if not area:GetAttribute("IntegrationStatus") and area:FindFirstChild("Nests") and not seen[areaName] then
                seen[areaName] = true
                list[#list + 1] = areaName
            end
        end
    end
    for _, rec in Runtime.Eggs do
        local aid = rec.AreaId
        if type(aid) == "string" and aid ~= "" and not seen[aid] then
            seen[aid] = true
            list[#list + 1] = aid
        end
    end
    if #list == 0 then
        for _, areaName in FALLBACK_BIOMES do list[#list + 1] = areaName end
    end
    return list
end

local function BuildPetRarityOptions()
    local seen, list = {}, {}
    if type(AssetsDir) == "table" then
        for _, asset in AssetsDir do
            if type(asset) == "table" and type(asset.Rarity) == "table" then
                local rid = asset.Rarity._id
                if type(rid) == "string" and (tonumber(asset.DropWeight) or 0) <= 0 and not seen[rid] then
                    seen[rid] = true
                    list[#list + 1] = rid
                end
            end
        end
    end
    if #list == 0 then
        for _, rid in FALLBACK_RARITIES do list[#list + 1] = rid end
    end
    table.sort(list, function(x, y) return RankOf(x) < RankOf(y) end)
    return list
end

--==============================================================
-- PROFILE MIRROR  (Money, EggInventory, Inventory, EquippedAssets)
--==============================================================

local function MergeInventoryDelta(current, delta)
    if type(delta) ~= "table" then return end
    local setPart = delta.Set
    local removePart = delta.Remove
    if type(setPart) == "table" then
        for uid, entry in setPart do
            current[tostring(uid)] = entry
        end
    end
    if type(removePart) == "table" then
        for k, v in removePart do
            if type(v) == "string" then
                current[v] = nil
            elseif type(k) == "string" then
                current[k] = nil
            end
        end
    end
    if setPart == nil and removePart == nil then
        for uid, entry in delta do
            current[tostring(uid)] = entry
        end
    end
end

local function OnProfileDelta(player, delta)
    if player ~= LocalPlayer or type(delta) ~= "table" then return end
    if type(delta.Money) == "number" then Runtime.Profile.Money = delta.Money end
    if delta.EggInventory ~= nil then
        MergeInventoryDelta(Runtime.Profile.EggInventory, delta.EggInventory)
    end
    if delta.Inventory ~= nil then
        MergeInventoryDelta(Runtime.Profile.Inventory, delta.Inventory)
    end
    if delta.EquippedAssets ~= nil then
        Runtime.Profile.EquippedAssets = delta.EquippedAssets
    end
end

--==============================================================
-- PLOTS + TREADMILL  (the sign text identifies YOUR plot; the
-- server itself relocates you onto your treadmill - we never fly)
--==============================================================

local function NormName(text)
    local trimmed = tostring(text or ""):gsub("@", "")
    trimmed = trimmed:gsub("^%s+", ""):gsub("%s+$", "")
    return trimmed:lower()
end

local function GetMyPlot()
    local plots = workspace:FindFirstChild("Plots")
    if not plots then return nil end
    local myDisplay = NormName(LocalPlayer.DisplayName)
    local myLogin = NormName(LocalPlayer.Name)
    for _, plot in plots:GetChildren() do
        local sign = plot:FindFirstChild("PlotSign")
        if sign then
            for _, node in sign:GetDescendants() do
                if node:IsA("TextLabel") then
                    local label = NormName(node.Text)
                    if label ~= "" and (label == myDisplay or label == myLogin) then
                        return plot
                    end
                end
            end
        end
    end
    if Runtime.MyPlotSlot then
        return plots:FindFirstChild(tostring(Runtime.MyPlotSlot))
    end
    return nil
end

-- free spot on the plot grid: >= 5 studs from every existing Placement
local function FindPlacementSpot()
    local taken = {}
    for _, entry in Runtime.Profile.EggInventory do
        if type(entry) == "table" and type(entry.Placement) == "table"
            and typeof(entry.Placement.LocalCFrame) == "CFrame" then
            local spotPos = entry.Placement.LocalCFrame.Position
            taken[#taken + 1] = { X = spotPos.X, Z = spotPos.Z }
        end
    end
    local xOffsets = { -8, -6, -4, -2, 0, 2, 4, 6, 8 }
    local zOffsets = { -4, -6, -8, -10, -12, -14, -16 }
    for _, zz in zOffsets do
        for _, xx in xOffsets do
            local free = true
            for _, point in taken do
                local dx, dz = point.X - xx, point.Z - zz
                if dx * dx + dz * dz < 25 then
                    free = false
                    break
                end
            end
            if free then return xx, zz end
        end
    end
    return nil
end

--==============================================================
-- WORLD POINTS  (SafeZone / Spawn / Forest middle)
--==============================================================

local function WeakKeyed()
    return setmetatable({}, { __mode = "k" })
end

Runtime.MotorBase = WeakKeyed()
Runtime.KnownPhysics = WeakKeyed()
Runtime.SavedCollide = WeakKeyed()

local function GetSafeZonePart()
    local world = workspace:FindFirstChild("World")
    local areas = world and world:FindFirstChild("Areas")
    local bounds = areas and areas:FindFirstChild("EggCarryBounds")
    local zone = bounds and bounds:FindFirstChild("SafeZone")
    if zone and zone:IsA("BasePart") then return zone end
    return nil
end

local function InSafeZone(pos)
    local zone = GetSafeZonePart()
    if zone then
        local rel = zone.CFrame:PointToObjectSpace(pos)
        return math.abs(rel.X) <= zone.Size.X / 2 and math.abs(rel.Z) <= zone.Size.Z / 2
    end
    return pos.X >= SAFEZONE_FALLBACK.X - SAFEZONE_FALLBACK.HX
       and pos.X <= SAFEZONE_FALLBACK.X + SAFEZONE_FALLBACK.HX
       and pos.Z >= SAFEZONE_FALLBACK.Z - SAFEZONE_FALLBACK.HZ
       and pos.Z <= SAFEZONE_FALLBACK.Z + SAFEZONE_FALLBACK.HZ
end

local function SpawnPoint()
    local spawnPart = workspace:FindFirstChild("SpawnLocation")
    if spawnPart and spawnPart:IsA("BasePart") then
        return spawnPart.Position + Vector3.new(0, STOP_ABOVE, 0)
    end
    local zone = GetSafeZonePart()
    if zone then
        return zone.Position + Vector3.new(0, STOP_ABOVE, 0)
    end
    return Vector3.new(512.7, 68.1 + STOP_ABOVE, -362.6)
end

local function ForestMiddle()
    local world = workspace:FindFirstChild("World")
    local areas = world and world:FindFirstChild("Areas")
    local guards = areas and areas:FindFirstChild("GuardAreas")
    local forest = guards and guards:FindFirstChild("Forest")
    local basePos = Vector3.new(602.1, 90.2, -372.0)
    if forest then
        local okPivot, pivot = pcall(function() return forest:GetPivot() end)
        if okPivot and typeof(pivot) == "CFrame" then basePos = pivot.Position end
    end
    local probe = RayDown(Vector3.new(basePos.X, basePos.Y + 60, basePos.Z), 300)
    local groundY = probe and probe.Position.Y or 67
    return Vector3.new(basePos.X, groundY, basePos.Z)
end

--==============================================================
-- STEAL CORE  (Direct Escape: no waiting at the nest - the escape
-- glide starts in the same breath as the confirmed carry)
--==============================================================

local function RequestCarry(rec)
    local node = Net("RF", "EggWorld/AskFieldEggCarry")
    local args = { Uid = rec.Uid }
    if type(rec.Uid) == "string" and rec.Uid:sub(1, 14) == "FirstAreaEgg_" then
        args.FirstAreaSlotKey = tostring(rec.AreaId) .. ":" .. tostring(rec.NestId or "")
    end
    local lastWhy = "denied"
    for _ = 1, CARRY_RETRIES do
        local ok, result = InvokeRemote(node, args)
        if ok and result == true then return true, nil end
        local text = ""
        if type(result) == "string" then
            text = result
        elseif not ok then
            text = tostring(result)
        end
        if text:lower():find("satchel", 1, true) then return false, "satchel" end
        if text ~= "" then lastWhy = text end
        task.wait(CARRY_RETRY_GAP)
    end
    return false, lastWhy
end

local function AwaitVerdict(uid, token, maxWait)
    local deadline = os.clock() + (maxWait or VERDICT_WAIT)
    while os.clock() < deadline do
        if not TokenAlive(token) then return "cancelled" end
        if Runtime.Carry.Redeemed or Runtime.LastVerdictUid == uid then return "redeemed" end
        if Runtime.Eggs[uid] == nil and not Runtime.Carry.IsCarrying then return "redeemed" end
        if Runtime.Carry.LostAt > 0 then return "lost" end
        task.wait(0.05)
    end
    if Runtime.Carry.IsCarrying then return "timeout" end
    return "redeemed"
end

local function WaitEggRecoverable(uid, token)
    local ragdollDeadline = os.clock() + RAGDOLL_WAIT_MAX
    while os.clock() < ragdollDeadline and IsRagdolled() do
        if not TokenAlive(token) then return nil end
        task.wait(0.1)
    end
    local deadline = os.clock() + EGG_RECOVER_WAIT
    while os.clock() < deadline do
        if not TokenAlive(token) then return nil end
        local rec = Runtime.Eggs[uid]
        if not rec then return nil end
        local state = rec.State
        if state == "Slot" or state == "Dropped" then return rec end
        if state == "Claimed" then return nil end
        if state == "Carried" then
            if rec.CarrierUserId == LocalPlayer.UserId then return rec end
            return nil -- another player took it
        end
        task.wait(0.2)
    end
    return nil
end

-- one full attempt. Outcomes: delivered | frienddropped | lost | gone |
-- satchel | cancelled | dead | carrying | carry | trick | drop | <glide reason>
local function AttemptSteal(rec, token, mode, useTrick, holdNestCam)
    local uid = rec.Uid
    local fresh = Runtime.Eggs[uid]
    if fresh then rec = fresh end
    local eggPos = RecordPos(rec)
    if not eggPos then return "gone" end
    if Runtime.Carry.IsCarrying then return "carrying" end

    -- leave the treadmill first (the server doffs and relocates by itself)
    if Runtime.Treadmill.Worn then
        FeatureInvoke("AutoTreadmill", Net("RF", "Treadmill/AskDoff"))
        Runtime.Treadmill.Worn = false
        Runtime.Treadmill.UnwornAt = os.clock()
    end

    local rarity = RarityOf(rec.AssetCategory) or Runtime.RarityByUid[uid]
    SetStatus(("Steal: %s egg - %s"):format(rarity or "?", tostring(rec.AreaId or "?")))

    FocusOn(eggPos)

    local _, _, root = Char()
    if not root then return "dead" end
    local distance = (eggPos - root.Position).Magnitude

    local approachCheck = function()
        if Runtime.Eggs[uid] == nil then return true, "gone" end
        if Runtime.Carry.IsCarrying then return true, "carrying" end
        return false
    end

    if distance > TWOLEG_DISTANCE then
        local flat = Vector3.new(eggPos.X - root.Position.X, 0, eggPos.Z - root.Position.Z)
        local staging = eggPos
        if flat.Magnitude > 1 then
            staging = eggPos - (flat / flat.Magnitude) * TWOLEG_BACKOFF
        end
        local okLeg, whyLeg = Glide(
            Vector3.new(staging.X, eggPos.Y + STOP_ABOVE, staging.Z),
            token, { Check = approachCheck })
        if not okLeg then
            ReleaseCamera()
            return whyLeg
        end
        PreStream(eggPos)
        local refetched = Runtime.Eggs[uid]
        if refetched then
            local refetchedPos = RecordPos(refetched)
            if refetchedPos then eggPos = refetchedPos end
        end
    else
        PreStream(eggPos)
    end

    local okApproach, whyApproach = Glide(eggPos + Vector3.new(0, STOP_ABOVE + 0.5, 0), token, { Check = approachCheck })
    if not okApproach then
        ReleaseCamera()
        return whyApproach
    end

    -- carry: accept true, retry 3x, never wait, never read the GUI
    local carried, carryWhy = RequestCarry(rec)
    if not carried then
        ReleaseCamera()
        if carryWhy == "satchel" then return "satchel" end
        return "carry"
    end
    Runtime.Carry = { IsCarrying = true, Uid = uid, Redeemed = false, LostAt = 0 }

    -- optional Nest Drop Trick: only on the retry of an egg we lost before
    if useTrick then
        task.wait(0.05)
        InvokeRemote(Net("RF", "EggWorld/AskFieldEggDrop"), { Reason = "PlayerRequest" })
        Runtime.Carry = { IsCarrying = false, Uid = uid, Redeemed = false, LostAt = 0 }
        task.wait(0.15)
        local recarried, recarryWhy = RequestCarry(rec)
        if not recarried then
            ReleaseCamera()
            if recarryWhy == "satchel" then return "satchel" end
            return "trick"
        end
        Runtime.Carry = { IsCarrying = true, Uid = uid, Redeemed = false, LostAt = 0 }
    end

    -- ESCAPE - destination chosen by mode, camera handled per mode
    local nestPos = eggPos
    if holdNestCam then
        FocusOn(nestPos)
    else
        ReleaseCamera()
    end
    local destination
    if mode == "friend" then
        destination = ForestMiddle()
        SetStatus("Escaping -> Forest (friend)")
    else
        destination = SpawnPoint()
        SetStatus("Escaping -> SafeZone")
    end

    local escapeCheck = function(pos)
        if Runtime.Carry.LostAt > 0 and not Runtime.Carry.Redeemed then
            return true, "lost"
        end
        if holdNestCam and Runtime.CamFocus then
            local flatFromNest = math.sqrt((pos.X - nestPos.X) ^ 2 + (pos.Z - nestPos.Z) ^ 2)
            if flatFromNest > 40 then ReleaseCamera() end
        end
        return false
    end

    local okEsc, whyEsc = Glide(destination, token, { Check = escapeCheck })
    if not okEsc then return whyEsc end

    if mode == "friend" then
        -- drop at the Forest middle, do NOT re-steal, glide 30 studs away
        InvokeRemote(Net("RF", "EggWorld/AskFieldEggDrop"), { Reason = "PlayerRequest" })
        Runtime.Carry = { IsCarrying = false, Uid = nil, Redeemed = false, LostAt = 0 }
        local awayFlat = Vector3.new(SpawnPoint().X - destination.X, 0, SpawnPoint().Z - destination.Z)
        if awayFlat.Magnitude > 1 then
            Glide(destination + (awayFlat / awayFlat.Magnitude) * 30, token, { Timeout = 15 })
        end
        return "frienddropped"
    end

    local verdict = AwaitVerdict(uid, token, VERDICT_WAIT)
    if verdict == "redeemed" then return "delivered" end
    if verdict == "lost" then return "lost" end
    if verdict == "cancelled" then return "cancelled" end
    return "noverdict"
end

--==============================================================
-- STEAL JOB  (up to MAX_RECOVERIES retries, then blacklist)
--==============================================================

local ManualEscapeJob -- forward: shared by Instant Steal + Help Friend

local function StealJob(rec, mode)
    local token = NewToken()
    Runtime.Busy = true
    Runtime.JobMode = mode
    local uid = rec.Uid
    local ok, err = pcall(function()
        local attempts = 0
        local lastOutcome = "unknown"
        local bail = false
        while attempts < 1 + MAX_RECOVERIES and not bail do
            attempts += 1
            local outcome = AttemptSteal(rec, token, mode, attempts > 1, false)
            lastOutcome = outcome
            if outcome == "delivered" then
                Runtime.JobFailures[uid] = nil
                Notify("Steal", "Egg delivered to the SafeZone.", "success", 4)
                SetStatus("Delivered")
                return
            elseif outcome == "frienddropped" then
                Runtime.JobFailures[uid] = nil
                Notify("Help Friend", "Egg dropped at the Forest middle for your friend.", "success", 4)
                SetStatus("Dropped for friend")
                return
            elseif outcome == "lost" and attempts <= MAX_RECOVERIES then
                SetStatus(("Recovering egg (%d/%d)"):format(attempts, MAX_RECOVERIES))
                local recovered = WaitEggRecoverable(uid, token)
                if not recovered then return end
                if Blacklisted(uid) then return end
                rec = recovered
            elseif outcome == "cancelled" or outcome == "dead" then
                return -- death / toggle off: no penalty
            elseif outcome == "satchel" then
                Runtime.PauseUntil = os.clock() + SATCHEL_PAUSE
                SetStatus("Satchel full - paused 15s")
                return
            elseif outcome == "gone" then
                return -- the egg no longer exists: no penalty, nothing to retry
            elseif outcome == "carrying" then
                -- something else put an egg in our hands mid-flight: hand it over
                local heldUid = Runtime.Carry.Uid
                if heldUid and (FlagOn("HelpFriend") or FlagOn("InstantSteal")) then
                    Runtime.Busy = false
                    task.spawn(ManualEscapeJob, heldUid)
                end
                return
            else
                bail = true -- plain failure: fall through to the failure handling
            end
        end
        if lastOutcome == "ground" then
            BlacklistUid(uid, BLACKLIST_GROUND)
        elseif lastOutcome == "region" then
            BlacklistUid(uid, 60)
        end
        Runtime.JobFailures[uid] = (Runtime.JobFailures[uid] or 0) + 1
        if Runtime.JobFailures[uid] >= 2 then
            BlacklistUid(uid, BLACKLIST_FAIL)
        end
        Notify("Steal", "Could not take that egg (" .. lastOutcome .. ").", "error", 4)
        SetStatus("Steal failed")
    end)
    if not ok then
        warn("[RageHub:StealJob] " .. tostring(err))
        SetStatus("Steal error (see console)")
    end
    ReleaseCamera()
    Runtime.Busy = false
    Runtime.JobMode = nil
    Runtime.CooldownUntil = math.max(Runtime.CooldownUntil, os.clock() + JOB_COOLDOWN)
end

--==============================================================
-- MANUAL ESCAPE  (Instant Steal + Help Friend share this: it
-- triggers on the server's own FieldEggCarry event for you)
--==============================================================

function ManualEscapeJob(uid)
    if Runtime.Busy or not Runtime.Alive then return end
    local mode = FlagOn("HelpFriend") and "friend" or "safezone"
    local token = NewToken()
    Runtime.Busy = true
    Runtime.JobMode = "manual"
    local ok, err = pcall(function()
        local rec = Runtime.Eggs[uid]
        local nestPos = rec and RecordPos(rec)
        local _, _, root = Char()
        if not root then return end
        if nestPos then FocusOn(nestPos) end
        SetStatus(mode == "friend" and "Manual steal -> Forest (friend)" or "Manual steal -> SafeZone")
        local destination = mode == "friend" and ForestMiddle() or SpawnPoint()
        local checkFn = function(pos)
            if Runtime.Carry.LostAt > 0 and not Runtime.Carry.Redeemed then
                return true, "lost"
            end
            if nestPos and Runtime.CamFocus then
                local flatFromNest = math.sqrt((pos.X - nestPos.X) ^ 2 + (pos.Z - nestPos.Z) ^ 2)
                if flatFromNest > 40 then ReleaseCamera() end
            end
            return false
        end
        local okEsc, whyEsc = Glide(destination, token, { Check = checkFn })
        if not okEsc then
            if whyEsc == "lost" then
                SetStatus("Recovering manual steal")
                local recovered = WaitEggRecoverable(uid, token)
                if recovered and (FlagOn("HelpFriend") or FlagOn("InstantSteal")) then
                    AttemptSteal(recovered, token, mode, true, false)
                end
            end
            return
        end
        if mode == "friend" then
            InvokeRemote(Net("RF", "EggWorld/AskFieldEggDrop"), { Reason = "PlayerRequest" })
            Runtime.Carry = { IsCarrying = false, Uid = nil, Redeemed = false, LostAt = 0 }
            local awayFlat = Vector3.new(SpawnPoint().X - destination.X, 0, SpawnPoint().Z - destination.Z)
            if awayFlat.Magnitude > 1 then
                Glide(destination + (awayFlat / awayFlat.Magnitude) * 30, token, { Timeout = 15 })
            end
            Notify("Help Friend", "Egg dropped at the Forest middle.", "success", 4)
            SetStatus("Dropped for friend")
        else
            local verdict = AwaitVerdict(uid, token, VERDICT_WAIT)
            if verdict == "redeemed" then
                Notify("Steal", "Egg delivered to the SafeZone.", "success", 4)
                SetStatus("Delivered")
            elseif verdict == "lost" then
                SetStatus("Egg lost")
            else
                SetStatus("Delivered (no verdict)")
            end
        end
    end)
    if not ok then warn("[RageHub:ManualEscape] " .. tostring(err)) end
    ReleaseCamera()
    Runtime.Busy = false
    Runtime.JobMode = nil
    Runtime.CooldownUntil = math.max(Runtime.CooldownUntil, os.clock() + JOB_COOLDOWN)
end

local function HandleCarryEvent(payload)
    if type(payload) ~= "table" then return end
    local uid = payload.Uid
    if payload.IsCarrying == true then
        Runtime.Carry = { IsCarrying = true, Uid = uid, Redeemed = false, LostAt = 0 }
        if not Runtime.Busy and Runtime.Alive and not Runtime.HopBusy then
            if FlagOn("HelpFriend") or FlagOn("InstantSteal") then
                task.spawn(ManualEscapeJob, uid)
            end
        end
    else
        if Runtime.Carry.Uid == nil or Runtime.Carry.Uid == uid then
            Runtime.Carry.IsCarrying = false
            -- a carry that ends while we are inside the SafeZone is a redeem,
            -- not a loss - only mark it lost outside the zone
            local _, _, rootNow = Char()
            local inZone = rootNow ~= nil and InSafeZone(rootNow.Position)
            if not Runtime.Carry.Redeemed and not inZone then
                Runtime.Carry.LostAt = os.clock()
            end
        end
    end
end

--==============================================================
-- EGG PICKER  (not set = random; set = nearest match; unknown
-- rarity only excluded when a rarity filter is on)
--==============================================================

local function PickEgg()
    local raritySel = FlagSet("Rarities")
    for rid in raritySel do
        if not Runtime.KnownRarities[rid] then raritySel[rid] = nil end
    end
    local biomeSel = FlagSet("Biomes")
    local anyRarity = next(raritySel) == nil
    local anyBiome = next(biomeSel) == nil
    local region = ArmedRegion()
    local candidates = {}
    for uid, rec in Runtime.Eggs do
        local state = rec.State
        if (state == "Slot" or state == "Dropped") and not Blacklisted(uid) then
            local rarity = RarityOf(rec.AssetCategory) or Runtime.RarityByUid[uid]
            local rarityOk = anyRarity or (rarity ~= nil and raritySel[rarity] == true)
            local biomeOk = anyBiome or (type(rec.AreaId) == "string" and biomeSel[rec.AreaId] == true)
            if rarityOk and biomeOk then
                local pos = RecordPos(rec)
                if pos and not (region and PosInBox(pos, region.Min, region.Max)) then
                    candidates[#candidates + 1] = { Rec = rec, Pos = pos }
                end
            end
        end
    end
    if #candidates == 0 then return nil end
    if anyRarity and anyBiome then
        return candidates[math.random(1, #candidates)].Rec
    end
    local _, _, root = Char()
    if not root then return candidates[1].Rec end
    local best, bestDist = nil, math.huge
    for _, cand in candidates do
        local d = (cand.Pos - root.Position).Magnitude
        if d < bestDist then
            bestDist = d
            best = cand.Rec
        end
    end
    return best
end

local function StealEngineTick()
    local mode = nil
    if FlagOn("AutoHelpFriend") then
        mode = "friend"
    elseif FlagOn("AutoSteal") then
        mode = "safezone"
    end
    if not mode then return end
    if Runtime.Busy or Runtime.HopBusy then return end
    if Runtime.Carry.IsCarrying then
        -- re-executed / left over while holding an egg: finish the delivery
        local _, _, root = Char()
        if root and not InSafeZone(root.Position) then
            task.spawn(ManualEscapeJob, Runtime.Carry.Uid)
        end
        return
    end
    if os.clock() < Runtime.CooldownUntil or os.clock() < Runtime.PauseUntil then return end
    if not Char() then return end
    if IsRagdolled() then return end
    local rec = PickEgg()
    if not rec then
        SetStatus(mode == "friend" and "Auto Help: waiting for a matching egg" or "Auto Steal: waiting for a matching egg")
        return
    end
    task.spawn(StealJob, rec, mode)
end

--==============================================================
-- ANTI RAGDOLL  (local hygiene only: the 2.5 s server ragdoll can
-- still happen - the real fix is not being hit. Never touches
-- RigSync or any remote.)
--==============================================================

local PHYSICS_CLASSES = {
    BodyVelocity = true, LinearVelocity = true, VectorForce = true,
    BodyAngularVelocity = true, BallSocketConstraint = true,
}

local function AntiRagdollBaseline(char)
    Runtime.MotorBase = WeakKeyed()
    Runtime.KnownPhysics = WeakKeyed()
    for _, node in char:GetDescendants() do
        if node:IsA("Motor6D") then
            Runtime.MotorBase[node] = node.Enabled
        elseif PHYSICS_CLASSES[node.ClassName] then
            Runtime.KnownPhysics[node] = true
        end
    end
end

local function SetAntiRagdoll(on)
    Runtime.AntiRagdollOn = on
    local char, hum = Char()
    if on then
        if char then AntiRagdollBaseline(char) end
        if hum then
            hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
            hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
        end
    else
        for part in Runtime.SavedCollide do
            pcall(function() part.CanCollide = true end)
        end
        Runtime.SavedCollide = WeakKeyed()
        if hum then
            hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, true)
            hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, true)
        end
    end
end

local function AntiRagdollTick()
    if not Runtime.AntiRagdollOn then return end
    local okAR, errAR = pcall(function()
        local char, hum, root = Char()
        if not char then return end
        for _, node in char:GetDescendants() do
            if node:IsA("Motor6D") then
                local wasEnabled = Runtime.MotorBase[node]
                if wasEnabled == nil then
                    Runtime.MotorBase[node] = node.Enabled
                elseif wasEnabled and not node.Enabled then
                    node.Enabled = true
                end
            elseif PHYSICS_CLASSES[node.ClassName] and not Runtime.KnownPhysics[node] then
                Runtime.KnownPhysics[node] = true
                node:Destroy()
            end
        end
        hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
        hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
        if hum.PlatformStand then hum.PlatformStand = false end
        local ragEnd = char:GetAttribute("RagdollEndTime") or LocalPlayer:GetAttribute("RagdollEndTime")
        if ragEnd and workspace:GetServerTimeNow() > ragEnd then
            local state = hum:GetState()
            if state == Enum.HumanoidStateType.Ragdoll or state == Enum.HumanoidStateType.FallingDown
                or state == Enum.HumanoidStateType.Physics then
                hum:ChangeState(Enum.HumanoidStateType.GettingUp)
            end
        end
        -- clamp absurd launch velocity when nothing of ours is flying
        if not Runtime.Gliding then
            local walk = math.max(hum.WalkSpeed or 16, 16)
            local vel = root.AssemblyLinearVelocity
            if vel.Magnitude > walk * 4 then
                root.AssemblyLinearVelocity = vel.Unit * walk * 2
            end
        end
        -- keep other players' parts from colliding with us (throttled)
        if os.clock() - Runtime.LastOthersApply > 3 then
            Runtime.LastOthersApply = os.clock()
            for _, plr in Players:GetPlayers() do
                if plr ~= LocalPlayer and plr.Character then
                    for _, part in plr.Character:GetDescendants() do
                        if part:IsA("BasePart") and part.CanCollide then
                            Runtime.SavedCollide[part] = true
                            part.CanCollide = false
                        end
                    end
                end
            end
        end
    end)
    if not okAR then warn("[RageHub:AntiRagdoll] " .. tostring(errAR)) end
end

--==============================================================
-- AUTOMATION · shared helpers
--==============================================================

local function IsEquipped(uid)
    local eq = Runtime.Profile.EquippedAssets
    if type(eq) ~= "table" then return false end
    if eq[uid] ~= nil then return true end
    for _, item in eq do
        if item == uid then return true end
        if type(item) == "table" and (item.Uid == uid or item._id == uid or item.Id == uid) then
            return true
        end
    end
    return false
end

local function IsFavourite(entry)
    if type(entry) ~= "table" then return false end
    return entry.Favorite == true or entry.Favourite == true
        or entry.IsFavorite == true or entry.IsFavourite == true
        or entry.Locked == true
end

local function EntryCategory(entry)
    if type(entry) ~= "table" then return nil end
    return entry.AssetCategory or entry.Category
end

local TreadmillList = nil
local function GetTreadmillConfigs()
    if TreadmillList then return TreadmillList end
    local okMod, module = pcall(function()
        local dataFolder = ReplicatedStorage:WaitForChild("Data", 5)
        local tm = dataFolder and dataFolder:WaitForChild("Treadmills", 5)
        return tm and require(tm)
    end)
    if okMod and type(module) == "table" then
        local raw = module.Configs or module
        local list = {}
        for key, cfg in raw do
            if type(cfg) == "table" then
                local id = cfg._id or cfg.Id or cfg.Name or (type(key) == "string" and key)
                if type(id) == "string" then
                    list[#list + 1] = { Id = id, Price = tonumber(cfg.Price) or math.huge }
                end
            end
        end
        table.sort(list, function(x, y) return x.Price < y.Price end)
        if #list > 0 then
            TreadmillList = list
            return list
        end
    end
    TreadmillList = { { Id = "Treadmill", Price = 0 }, { Id = "Sci-FiTreadmill", Price = 15000 } }
    return TreadmillList
end

local TrailList = nil
local function GetTrailConfigs()
    if TrailList then return TrailList end
    local okMod, module = pcall(function()
        local dataFolder = ReplicatedStorage:WaitForChild("Data", 5)
        local tr = dataFolder and dataFolder:WaitForChild("Trails", 5)
        return tr and require(tr)
    end)
    if okMod and type(module) == "table" then
        local raw = module.Configs or module
        local list = {}
        for key, cfg in raw do
            if type(cfg) == "table" then
                local id = cfg._id or cfg.Id or (type(key) == "string" and key)
                if type(id) == "string" and cfg.DisplayInShop and tonumber(cfg.Price) then
                    list[#list + 1] = { Id = id, Price = tonumber(cfg.Price) }
                end
            end
        end
        if #list > 0 then
            table.sort(list, function(x, y) return x.Price > y.Price end)
            TrailList = list
            return list
        end
    end
    TrailList = {}
    return TrailList
end

--==============================================================
-- AUTOMATION · Auto Sell  (RE/PetSatchel/SellSelection)
--==============================================================

local function AutoSellTick()
    if not (FlagOn("AutoSellEggs") or FlagOn("AutoSellPets")) then return end
    if Runtime.HopBusy then return end
    local eggFilter = FlagSet("SellEggRarity")
    local petFilter = FlagSet("SellPetRarity")
    local sellEggs, sellPets = {}, {}
    if FlagOn("AutoSellEggs") then
        for uid, entry in Runtime.Profile.EggInventory do
            if type(entry) == "table" and entry.Placement == nil and not entry.InFuse and not IsFavourite(entry) then
                local rid = RarityOf(EntryCategory(entry))
                if next(eggFilter) == nil or (rid and eggFilter[rid]) then
                    sellEggs[#sellEggs + 1] = uid
                end
            end
        end
    end
    if FlagOn("AutoSellPets") then
        for uid, entry in Runtime.Profile.Inventory do
            if type(entry) == "table" and not entry.InFuse and not IsFavourite(entry) and not IsEquipped(uid) then
                local rid = RarityOf(EntryCategory(entry))
                if next(petFilter) == nil or (rid and petFilter[rid]) then
                    sellPets[#sellPets + 1] = uid
                end
            end
        end
    end
    if #sellEggs == 0 and #sellPets == 0 then return end
    FireRemote(Net("RE", "PetSatchel/SellSelection"), { Eggs = sellEggs, Assets = sellPets })
end

--==============================================================
-- AUTOMATION · Auto Place Egg  (AskWearTool -> AskPlaceEgg)
--==============================================================

local function AutoPlaceTick()
    if not FlagOn("AutoPlaceEgg") then return end
    if Runtime.Busy or Runtime.Carry.IsCarrying or Runtime.HopBusy then return end
    if os.clock() < Runtime.PlacePauseUntil then return end
    if not GetMyPlot() then return end -- my plot not identifiable yet (sign not streamed)
    local uids = {}
    for uid, entry in Runtime.Profile.EggInventory do
        if type(entry) == "table" and entry.Placement == nil and not entry.InFuse then
            uids[#uids + 1] = uid
        end
    end
    if #uids == 0 then return end
    table.sort(uids)
    local uid = uids[1]
    local spotX, spotZ = FindPlacementSpot()
    if not spotX then return end -- plot grid full
    local wearOk, wearRes = FeatureInvoke("AutoPlaceEgg", Net("RF", "EggWorld/AskWearTool"), uid)
    if not (wearOk and wearRes == true) then return end
    task.wait(0.3)
    local placeOk, placeRes = FeatureInvoke("AutoPlaceEgg", Net("RF", "EggWorld/AskPlaceEgg"), {
        Uid = uid,
        LocalCFrame = CFrame.new(spotX, -0.5, spotZ),
    })
    if not (placeOk and placeRes == true) then
        pcall(function()
            InvokeRemote(Net("RF", "EggWorld/AskDoffTool"), uid)
        end)
        Runtime.PlaceFalseStreak = Runtime.PlaceFalseStreak + 1
        if Runtime.PlaceFalseStreak >= 3 then
            Runtime.PlacePauseUntil = os.clock() + 60
            Runtime.PlaceFalseStreak = 0
            SetStatus("Auto Place: server refused - paused 60s")
        end
    else
        Runtime.PlaceFalseStreak = 0
    end
end

--==============================================================
-- AUTOMATION · Auto Hatch Egg  (AskHatch -> 6.2s -> AskFinishHatch)
--==============================================================

local function AutoHatchTick()
    if not FlagOn("AutoHatch") then return end
    if Runtime.HopBusy then return end
    local now = os.clock()
    local due = {}
    for uid, finishAt in Runtime.HatchQueue do
        if now >= finishAt then due[#due + 1] = uid end
    end
    for _, uid in due do
        local finOk, finRes = FeatureInvoke("AutoHatch", Net("RF", "EggWorld/AskFinishHatch"), uid)
        if finOk and finRes == true then
            Runtime.HatchQueue[uid] = nil
            Runtime.HatchFinFails[uid] = nil
        else
            local fails = (Runtime.HatchFinFails[uid] or 0) + 1
            Runtime.HatchFinFails[uid] = fails
            if fails >= 3 then
                Runtime.HatchQueue[uid] = nil
                Runtime.HatchRetryAt[uid] = os.clock() + 120
            else
                Runtime.HatchQueue[uid] = os.clock() + 2
            end
        end
    end
    if Runtime.LastHatchStart + 1 > now then return end
    local starts = {}
    for uid, entry in Runtime.Profile.EggInventory do
        if type(entry) == "table" and entry.Placement ~= nil
            and Runtime.HatchQueue[uid] == nil and Runtime.HatchStarted[uid] == nil
            and now >= (Runtime.HatchRetryAt[uid] or 0) then
            starts[#starts + 1] = uid
        end
    end
    if #starts == 0 then return end
    table.sort(starts)
    local uid = starts[1]
    Runtime.LastHatchStart = now
    local hatchOk, hatchRes = FeatureInvoke("AutoHatch", Net("RF", "EggWorld/AskHatch"), uid)
    if hatchOk and hatchRes == true then
        Runtime.HatchStarted[uid] = true
        Runtime.HatchQueue[uid] = now + HATCH_TIME
    else
        Runtime.HatchRetryAt[uid] = now + 30
    end
end

--==============================================================
-- AUTOMATION · Auto Catch Butterfly  (event-only, unverified
-- payload: swings when in reach, chases only when idle)
--==============================================================

local function OnButterflyBloom(...)
    if not FlagOn("AutoButterfly") then return end
    local args = table.pack(...)
    local flightId, bloomPos = nil, nil
    for i = 1, args.n do
        local arg = args[i]
        if type(arg) == "string" or type(arg) == "number" then
            if flightId == nil then flightId = arg end
        elseif typeof(arg) == "Vector3" then
            if bloomPos == nil then bloomPos = arg end
        elseif type(arg) == "table" then
            if flightId == nil then
                flightId = arg.FlightId or arg.flightId or arg.Uid or arg.uid or arg.Id or arg._id
            end
            if bloomPos == nil then
                if typeof(arg.Position) == "Vector3" then
                    bloomPos = arg.Position
                elseif typeof(arg.Pos) == "Vector3" then
                    bloomPos = arg.Pos
                end
            end
        end
    end
    if flightId == nil then
        Runtime.Butterfly.Fails += 1
        if Runtime.Butterfly.Fails >= 5 and Window then
            local element = Window:GetElement("AutoButterfly")
            if element and element.Get and element:Get() == true then
                Notify("Auto Catch Butterfly", "Disabled: bloom carries no flight id. A RageDump during the event is needed.", "warning", 6)
                pcall(function() element:Set(false) end)
            end
        end
        return
    end
    Runtime.Butterfly.Fails = 0
    if os.clock() - Runtime.Butterfly.LastSwing < Runtime.Butterfly.Cooldown then return end
    local _, _, root = Char()
    if not root then return end
    if bloomPos and (bloomPos - root.Position).Magnitude > Runtime.Butterfly.NetReach then
        -- out of reach: chase only while the steal engine has nothing to do
        if (FlagOn("AutoSteal") or FlagOn("AutoHelpFriend")) or Runtime.Busy or Runtime.Carry.IsCarrying then
            return
        end
        local token = NewToken()
        Runtime.Busy = true
        Runtime.JobMode = "butterfly"
        task.spawn(function()
            pcall(function()
                Glide(bloomPos + Vector3.new(0, STOP_ABOVE, 0), token, { Timeout = 12 })
                local _, _, rootAfter = Char()
                if rootAfter and (bloomPos - rootAfter.Position).Magnitude <= Runtime.Butterfly.NetReach
                    and os.clock() - Runtime.Butterfly.LastSwing >= Runtime.Butterfly.Cooldown then
                    Runtime.Butterfly.LastSwing = os.clock()
                    FeatureInvoke("AutoButterfly", Net("RF", "Butterflies/AskSwing"), flightId)
                end
            end)
            Runtime.Busy = false
            Runtime.JobMode = nil
        end)
        return
    end
    Runtime.Butterfly.LastSwing = os.clock()
    FeatureInvoke("AutoButterfly", Net("RF", "Butterflies/AskSwing"), flightId)
end

local function TryConnectButterflies()
    if Runtime.Butterfly.Connected then return end
    local okCtl, controller = pcall(function()
        local controllers = ReplicatedStorage:WaitForChild("Controllers", 5)
        local gameCtl = controllers and controllers:WaitForChild("Game", 5)
        local module = gameCtl and gameCtl:FindFirstChild("AdminAbuseClientController")
        return module and require(module)
    end)
    if not okCtl or type(controller) ~= "table" then return end
    local events = controller.Events
    if type(events) ~= "table" then return end
    local bloom = events.ButterflyBloom
    if typeof(bloom) == "Instance" and bloom:IsA("BindableEvent") then
        Track(bloom.Event:Connect(OnButterflyBloom))
        Runtime.Butterfly.Connected = true
    elseif type(bloom) == "table" and type(bloom.Connect) == "function" then
        Track(bloom:Connect(OnButterflyBloom))
        Runtime.Butterfly.Connected = true
    end
    local okCfg, cfg = pcall(function()
        local dataFolder = ReplicatedStorage:WaitForChild("Data", 5)
        local bf = dataFolder and dataFolder:FindFirstChild("Butterflies")
        return bf and require(bf)
    end)
    if okCfg and type(cfg) == "table" then
        local realCfg = cfg.Configs or cfg.Config or cfg
        Runtime.Butterfly.NetReach = tonumber(realCfg.NetReach) or Runtime.Butterfly.NetReach
        Runtime.Butterfly.Cooldown = tonumber(realCfg.SwingCooldownSeconds) or Runtime.Butterfly.Cooldown
    end
end

--==============================================================
-- AUTOMATION · Best Pet / Claim / Upgrade / Buy Trail
--==============================================================

local function AutoBestPetTick()
    if not FlagOn("AutoBestPet") then return end
    if Runtime.HopBusy then return end
    local inv = Runtime.Profile.Inventory
    if type(inv) ~= "table" or next(inv) == nil then return end
    local sig = {}
    for uid in inv do sig[#sig + 1] = uid end
    table.sort(sig)
    local signature = table.concat(sig, ",")
    if signature == Runtime.LastPetSig then return end
    local okWear = FeatureInvoke("AutoBestPet", Net("RF", "Haul/WearBest"))
    if okWear then Runtime.LastPetSig = signature end
end

local function AutoClaimTick()
    if not FlagOn("AutoClaim") then return end
    if Runtime.HopBusy then return end
    FeatureInvoke("AutoClaim", Net("RF", "AwayEarnings/AskCollect"), { Kind = "Claim" })
    FeatureInvoke("AutoClaim", Net("RF", "Codex/AskRedeemAll"))
end

local function AutoUpgradeTreadmillTick()
    if not FlagOn("AutoUpgradeTreadmill") then return end
    if Runtime.HopBusy then return end
    local money = Runtime.Profile.Money
    if type(money) ~= "number" then return end -- unknown until the first ProfileDelta
    local configs = GetTreadmillConfigs()
    if #configs < 2 then return end
    local currentIndex = 1
    for i, cfg in configs do
        if cfg.Id == Runtime.Treadmill.TierId then
            currentIndex = i
            break
        end
    end
    local nextCfg = configs[currentIndex + 1]
    if not nextCfg then return end -- top tier owned
    if money < nextCfg.Price then return end
    local okRaise, resRaise = FeatureInvoke("AutoUpgradeTreadmill", Net("RF", "Treadmill/AskTierRaise"), nextCfg.Id)
    if okRaise and resRaise == true then
        Runtime.Treadmill.TierId = nextCfg.Id
        SetStatus(("Treadmill upgraded: %s"):format(nextCfg.Id))
    end
end

local function AutoBuyTrailTick()
    if not FlagOn("AutoBuyTrail") then return end
    if Runtime.HopBusy then return end
    local money = Runtime.Profile.Money
    if type(money) ~= "number" then return end
    local trails = GetTrailConfigs()
    for _, trail in trails do -- most expensive first
        if not Runtime.TrailAttempted[trail.Id] and money >= trail.Price then
            local okBuy, resBuy = FeatureInvoke("AutoBuyTrail", Net("RF", "Trailwear/AskPurchase"), trail.Id)
            if okBuy and resBuy == true then
                Runtime.TrailAttempted[trail.Id] = true
                pcall(function()
                    InvokeRemote(Net("RF", "Trailwear/AskChoose"), trail.Id) -- [UNVERIFIED shape]
                end)
                SetStatus(("Trail bought: %s"):format(trail.Id))
            else
                local falseCount = (Runtime.TrailFalseCount[trail.Id] or 0) + 1
                Runtime.TrailFalseCount[trail.Id] = falseCount
                if falseCount >= 3 then
                    Runtime.TrailAttempted[trail.Id] = true -- owned or unavailable: stop trying
                end
            end
            return -- one attempt per pass
        end
    end
end

--==============================================================
-- MISC · Anti AFK  (virtual input; never fires Telemetry/IdleRescue)
--==============================================================

local function SetupAntiAfk()
    Track(LocalPlayer.Idled:Connect(function()
        pcall(function()
            local virtualUser = game:GetService("VirtualUser")
            virtualUser:CaptureController()
            virtualUser:ClickButton1(Vector2.new())
        end)
    end))
end

local function AntiAfkTick()
    if not FlagOn("AntiAfk") then return end
    pcall(function()
        local uis = game:GetService("UserInputService")
        local virtualInput = game:GetService("VirtualInputManager")
        local loc = uis:GetMouseLocation()
        virtualInput:SendMouseMoveEvent(loc.X + math.random(-4, 4), loc.Y + math.random(-4, 4))
    end)
end

--==============================================================
-- MISC · Auto Execute / Reconnect
--==============================================================

local function QueueAutoExecute()
    if Runtime.AutoExecuteQueued then return end
    if not FlagOn("AutoExecute") then return end
    local src = ('loadstring(game:HttpGet("%s"))()'):format(AUTO_EXECUTE_URL)
    local okQueue = pcall(function() queue_on_teleport(src) end)
    Runtime.AutoExecuteQueued = true
    if not okQueue then
        warn("[RageHub] queue_on_teleport is not available on this executor")
    end
end

local function Rejoin()
    if Runtime.Rejoining or not Runtime.Alive then return end
    Runtime.Rejoining = true
    QueueAutoExecute()
    task.spawn(function()
        for attempt = 1, RECONNECT_MAX do
            if not Runtime.Alive then break end
            Runtime.LastTeleport = { PlaceId = game.PlaceId, JobId = nil }
            local okTp = pcall(function()
                TeleportService:Teleport(game.PlaceId, LocalPlayer)
            end)
            if okTp then break end
            task.wait(attempt * 2)
        end
        Runtime.Rejoining = false
    end)
end

local function SetupReconnect()
    Track(GuiService.ErrorMessageChanged:Connect(function()
        if not FlagOn("AutoReconnect") then return end
        if GuiService:GetErrorMessage() == "" then return end
        task.wait(1)
        Rejoin()
    end))
    local networkClient = game:GetService("NetworkClient")
    Track(networkClient.ChildRemoved:Connect(function()
        if not FlagOn("AutoReconnect") then return end
        task.wait(1)
        Rejoin()
    end))
    Track(TeleportService.TeleportInitFailed:Connect(function()
        if not FlagOn("AutoReconnect") then return end
        if Runtime.ReconnectRetries >= RECONNECT_MAX then return end
        Runtime.ReconnectRetries += 1
        task.wait(math.min(2 ^ Runtime.ReconnectRetries, 20))
        if not Runtime.Alive then return end
        local last = Runtime.LastTeleport
        pcall(function()
            if last and last.JobId then
                TeleportService:TeleportToPlaceInstance(last.PlaceId, last.JobId, LocalPlayer)
            else
                TeleportService:Teleport(game.PlaceId, LocalPlayer)
            end
        end)
    end))
end

--==============================================================
-- MISC · Hop to Lowest Server  (6 samples, keep servers present in
-- every sample, lowest player count, <= max-2 players)
--==============================================================

local function FetchServerPage()
    local url = ("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100"):format(game.PlaceId)
    local ok, body = pcall(function() return game:HttpGet(url) end)
    if not ok then return nil end
    local okDecode, data = pcall(function() return HttpService:JSONDecode(body) end)
    if not okDecode or type(data) ~= "table" or type(data.data) ~= "table" then return nil end
    return data.data
end

local function PickLowestServer()
    local common = nil
    local samples = 0
    local deadline = os.clock() + 20
    while samples < 6 and os.clock() < deadline do
        local page = FetchServerPage()
        if page then
            samples += 1
            local ids = {}
            for _, server in page do
                if type(server) == "table" and type(server.id) == "string" then
                    ids[server.id] = server
                end
            end
            if common == nil then
                common = ids
            else
                local kept = {}
                for id, server in common do
                    if ids[id] then kept[id] = server end
                end
                common = kept
            end
            if samples < 6 then task.wait(0.8) end
        else
            task.wait(1.2) -- HTTP 429 / failure: back off, don't count the sample
        end
    end
    if not common then return nil end
    local best = nil
    for id, server in common do
        local playing = tonumber(server.playing) or 0
        local maxP = tonumber(server.maxPlayers) or 0
        if id ~= game.JobId and maxP > 0 and playing < maxP - 1 then
            if not best or playing < (tonumber(best.playing) or 0) then
                best = server
            end
        end
    end
    return best
end

local function HopToLowest()
    if Runtime.HopBusy then return end
    Runtime.HopBusy = true
    task.spawn(function()
        local okHop, hopErr = pcall(function()
            local chosen = nil
            for round = 1, 2 do
                SetStatus(("Hop: sampling servers (%d/2)"):format(round))
                chosen = PickLowestServer()
                if chosen then break end
                if round == 1 then task.wait(1) end
            end
            if not chosen then
                Notify("Hop", "No lower server found - staying here.", "info", 4)
                SetStatus("Hop: no lower server")
                return
            end
            QueueAutoExecute()
            Runtime.LastTeleport = { PlaceId = game.PlaceId, JobId = chosen.id }
            local okTp = pcall(function()
                TeleportService:TeleportToPlaceInstance(game.PlaceId, chosen.id, LocalPlayer)
            end)
            if not okTp then
                Notify("Hop", "Teleport failed - staying here.", "error", 4)
                SetStatus("Hop: teleport failed")
            end
        end)
        if not okHop then
            warn("[RageHub:Hop] " .. tostring(hopErr))
            Notify("Hop", "Sampling failed - staying here.", "error", 4)
        end
        Runtime.HopBusy = false
    end)
end

--==============================================================
-- UNLOAD
--==============================================================

local function UnloadAll()
    if not Runtime.Alive then return end
    Runtime.Alive = false
    NewToken()
    Runtime.Busy = false
    Runtime.Gliding = false
    pcall(ReleaseCamera)
    pcall(function() LocalPlayer.ReplicationFocus = nil end)
    pcall(function() SetAntiRagdoll(false) end)
    for _, conn in Runtime.Conns do
        pcall(function() conn:Disconnect() end)
    end
    Runtime.Conns = {}
    if Window then
        pcall(function() Window:Destroy() end)
    end
end

--==============================================================
-- CHARACTER LIFECYCLE  (loops keep running; only state resets)
--==============================================================

local function OnCharacterAdded(char)
    task.spawn(function()
        local okChar, errChar = pcall(function()
            ResetRuntime()
            local deadline = os.clock() + 10
            while os.clock() < deadline do
                if char:FindFirstChild("HumanoidRootPart") and char:FindFirstChildOfClass("Humanoid") then break end
                task.wait(0.1)
            end
            local hum = char:FindFirstChildOfClass("Humanoid")
            if hum then
                Track(hum.Died:Connect(function()
                    ResetRuntime()
                    SetStatus("Died - recovering")
                end))
            end
            if Runtime.AntiRagdollOn then
                AntiRagdollBaseline(char)
            end
            RefreshSnapshot()
            SetStatus("Respawned - resuming")
        end)
        if not okChar then warn("[RageHub:Char] " .. tostring(errChar)) end
    end)
end

--==============================================================
-- AUTO TREADMILL  (remote-only: the server relocates you onto
-- YOUR treadmill; truth comes from RenderStateShifted)
--==============================================================

local function AutoTreadmillTick()
    if not FlagOn("AutoTreadmill") then return end
    if Runtime.Busy or Runtime.Carry.IsCarrying or Runtime.HopBusy then return end
    local tm = Runtime.Treadmill
    if tm.Worn then return end
    if os.clock() - (tm.UnwornAt or 0) < TREADMILL_UNWORN then return end
    if os.clock() - tm.LastWear < TREADMILL_GAP then return end
    if not Char() then return end
    tm.LastWear = os.clock()
    FeatureInvoke("AutoTreadmill", Net("RF", "Treadmill/AskWearStill"))
end

--==============================================================
-- EVENT WIRING
--==============================================================

local function ConnectRemote(kind, path, handler)
    local node = Net(kind, path)
    if not node then
        warn("[RageHub] remote missing: " .. kind .. "/" .. path)
        return
    end
    Track(node.Event:Connect(function(...)
        local okEv, errEv = pcall(handler, ...)
        if not okEv then warn("[RageHub:" .. path .. "] " .. tostring(errEv)) end
    end))
end

local function OnBatchShifted(batch)
    if type(batch) ~= "table" then return end
    if type(batch.Records) == "table" then
        ForEachRecord(batch.Records, ApplyRecord)
    else
        ForEachRecord(batch, ApplyRecord)
    end
end

local function OnEggGone(uid)
    if type(uid) == "string" then
        Runtime.Eggs[uid] = nil
    elseif type(uid) == "table" and type(uid.Uid) == "string" then
        Runtime.Eggs[uid.Uid] = nil
    end
end

local function OnRedeemVerdict(payload)
    if type(payload) ~= "table" then return end
    local uid = payload.Uid or payload.EggUid
    if type(uid) == "string" then
        Runtime.LastVerdictUid = uid
    end
    if Runtime.Carry.Uid == nil or Runtime.Carry.Uid == uid then
        Runtime.Carry.Redeemed = true
        Runtime.Carry.IsCarrying = false
    end
end

local function OnRaritiesShown(payload)
    if type(payload) ~= "table" or type(payload.RareSpawns) ~= "table" then return end
    for _, spawn in payload.RareSpawns do
        if type(spawn) == "table" and type(spawn.EggUid) == "string" then
            Runtime.RarityByUid[spawn.EggUid] = spawn.RarityId
        end
    end
end

local function OnOwnerShifted(payload)
    if type(payload) ~= "table" or type(payload.Records) ~= "table" then return end
    for key, value in payload.Records do
        if type(key) == "string" then
            Runtime.Eggs[key] = nil
        elseif type(value) == "table" and type(value.Uid) == "string" then
            Runtime.Eggs[value.Uid] = nil
        end
    end
end

local function OnHomesteadState(payload)
    if type(payload) ~= "table" then return end
    local function accept(entry)
        if type(entry) == "table" and entry.UserId == LocalPlayer.UserId and entry.Slot ~= nil then
            Runtime.MyPlotSlot = tonumber(entry.Slot) or entry.Slot
        end
    end
    accept(payload)
    for _, entry in payload do
        accept(entry)
    end
end

local function ConnectGameEvents()
    ConnectRemote("RE", "EggWorld/FieldEggShifted", ApplyRecord)
    ConnectRemote("RE", "EggWorld/FieldEggBatchShifted", OnBatchShifted)
    ConnectRemote("RE", "EggWorld/FieldEggGone", OnEggGone)
    ConnectRemote("RE", "EggWorld/FieldEggCarry", HandleCarryEvent)
    ConnectRemote("RE", "EggWorld/FieldEggRedeemVerdict", OnRedeemVerdict)
    ConnectRemote("RE", "EggWorld/FieldEggRaritiesShown", OnRaritiesShown)
    ConnectRemote("RE", "EggWorld/OwnerShifted", OnOwnerShifted)
    ConnectRemote("RE", "ProfileMirror/ProfileDelta", function(delta, _, player)
        local who = player
        if typeof(who) ~= "Instance" or not who:IsA("Player") then who = LocalPlayer end
        OnProfileDelta(who, delta)
    end)
    ConnectRemote("RE", "Treadmill/RenderStateShifted", function(player, worn)
        if typeof(player) == "Instance" and player:IsA("Player") and player == LocalPlayer then
            Runtime.Treadmill.Worn = worn == true
            if not worn then
                Runtime.Treadmill.UnwornAt = os.clock()
            end
        end
    end)
    ConnectRemote("RE", "Treadmill/AssignedBeltShifted", function(treadmillId)
        if type(treadmillId) == "string" then
            Runtime.Treadmill.TierId = treadmillId
        end
    end)
    ConnectRemote("RE", "Homestead/StateShifted", OnHomesteadState)
end

--==============================================================
-- WINDOW  (built last: every callback above is already in scope)
--==============================================================

Window = RageHub:CreateWindow({
    Name = "Rage Hub",
    Subtitle = "Steal An Egg - " .. VERSION,
    Theme = "Rage",
    Features = { Notifications = true },
    ConfigFolder = "RageHub/StealAnEgg",
    AutoSave = Prefs.AutoSave and "autosave" or nil,
    Splash = true,
    OnUnload = UnloadAll,
})

do
    local env = nil
    pcall(function() env = getgenv() end)
    if type(env) ~= "table" then pcall(function() env = shared end) end
    if type(env) == "table" then
        if env.__RageHubStealAnEgg and env.__RageHubStealAnEgg ~= Window then
            pcall(function() env.__RageHubStealAnEgg:Destroy() end)
        end
        env.__RageHubStealAnEgg = Window
    end
end

local function CancelMode(...)
    local modes = { ... }
    for _, wanted in modes do
        if Runtime.JobMode == wanted then
            CancelJobs()
            return
        end
    end
end

local function RefreshFilterDropdowns()
    if RarityDropdown then pcall(function() RarityDropdown:Refresh(BuildRarityOptions(), true) end) end
    if BiomeDropdown then pcall(function() BiomeDropdown:Refresh(BuildBiomeOptions(), true) end) end
end

local StealTab = Window:CreateTab("Steal", "🥚")
local PlayerTab = Window:CreateTab("Player", "🏃")
local MiscTab = Window:CreateTab("Misc", "🧰")

-- ---------- STEAL ----------

local StatusSection = StealTab:CreateSection("Status")
StatusLabel = StatusSection:CreateLabel("Ready - " .. VERSION)

local StealSection = StealTab:CreateSection("Stealing")

StealSection:CreateToggle({
    Name = "Instant Steal", Flag = "InstantSteal", Default = false,
    Description = "Tap the game's own Steal button; the script flies the egg straight to the SafeZone",
    Callback = function(on)
        if not on then CancelMode("manual") end
    end,
})

StealSection:CreateToggle({
    Name = "Auto Steal", Flag = "AutoSteal", Default = false,
    Description = "Steal a matching egg, escape straight to the SafeZone, repeat",
    Callback = function(on)
        if on then
            task.spawn(function()
                pcall(RefreshSnapshot)
                RefreshFilterDropdowns()
            end)
        else
            CancelMode("safezone")
        end
    end,
})

RarityDropdown = StealSection:CreateDropdown({
    Name = "Rarity", Flag = "Rarities", Multi = true, Search = true,
    Options = BuildRarityOptions(), Default = {},
    Description = "Not set = random. Built live from the game's own catalog (field-egg rarities only)",
})

BiomeDropdown = StealSection:CreateDropdown({
    Name = "Biome", Flag = "Biomes", Multi = true, Search = true,
    Options = BuildBiomeOptions(), Default = {},
    Description = "Not set = random. Real areas only (Enchanted Forest is WIP and hidden)",
})

StealSection:CreateToggle({
    Name = "Auto Treadmill", Flag = "AutoTreadmill", Default = false,
    Description = "Wears YOUR plot's treadmill (no flying - the server relocates you itself)",
})

StealSection:CreateToggle({
    Name = "Help Friend (Manual Steal)", Flag = "HelpFriend", Default = false,
    Description = "Your manual steals get dropped at the Forest middle for a friend instead of redeemed",
    Callback = function(on)
        if not on then CancelMode("manual") end
    end,
})

StealSection:CreateToggle({
    Name = "Auto Help Friend", Flag = "AutoHelpFriend", Default = false,
    Description = "AFK mode: auto-steal matching eggs and drop them at the Forest middle",
    Callback = function(on)
        if not on then CancelMode("friend") end
    end,
})

-- ---------- PLAYER ----------

local ProtectSection = PlayerTab:CreateSection("Protection")

ProtectSection:CreateToggle({
    Name = "Anti Ragdoll", Flag = "AntiRagdoll", Default = false,
    Description = "Local anti-fling hygiene: motors, physics junk, launch clamp, player collisions. The 2.5s server ragdoll can still happen",
    Callback = function(on)
        SetAntiRagdoll(on and true or false)
    end,
})

-- ---------- MISC (the former Automation tab lives here now) ----------

local SessionSection = MiscTab:CreateSection("Session")

SessionSection:CreateToggle({
    Name = "Anti AFK", Flag = "AntiAfk", Default = true,
    Description = "Virtual input every 45s so the game's own idle detector stays quiet",
})

SessionSection:CreateToggle({
    Name = "Auto Reconnect", Flag = "AutoReconnect", Default = false,
    Description = "Rejoins after a kick or disconnect (up to 8 tries)",
})

SessionSection:CreateToggle({
    Name = "Auto Execute", Flag = "AutoExecute", Default = false,
    Description = "Queue this script for the next server (survives hops and the game's own AFK hop)",
    Callback = function(on)
        if on then QueueAutoExecute() end
    end,
})

local SellSection = MiscTab:CreateSection("Auto Sell")

SellSection:CreateDropdown({
    Name = "Egg Rarity Filter", Flag = "SellEggRarity", Multi = true, Search = true,
    Options = BuildRarityOptions(), Default = {},
    Description = "Not set = sell all unprotected eggs (placed / favourite / fused eggs are never sold)",
})

SellSection:CreateDropdown({
    Name = "Pet Rarity Filter", Flag = "SellPetRarity", Multi = true, Search = true,
    Options = BuildPetRarityOptions(), Default = {},
    Description = "Not set = sell all unprotected pets (equipped / favourite / fused pets are never sold)",
})

SellSection:CreateToggle({
    Name = "Sell Eggs", Flag = "AutoSellEggs", Default = false,
    Description = "Every 5s via the satchel's own SellSelection remote",
})

SellSection:CreateToggle({
    Name = "Sell Pets", Flag = "AutoSellPets", Default = false,
    Description = "Every 5s via the satchel's own SellSelection remote",
})

local EggAutoSection = MiscTab:CreateSection("Eggs")

EggAutoSection:CreateToggle({
    Name = "Auto Place Egg", Flag = "AutoPlaceEgg", Default = false,
    Description = "Wear tool, then place on a free spot of your plot (5+ studs from other eggs)",
})

EggAutoSection:CreateToggle({
    Name = "Auto Hatch Egg", Flag = "AutoHatch", Default = false,
    Description = "Hatch placed eggs: AskHatch, 6.2s, AskFinishHatch (the game's own timing)",
})

local PetAutoSection = MiscTab:CreateSection("Pets & Events")

PetAutoSection:CreateToggle({
    Name = "Auto Catch Butterfly", Flag = "AutoButterfly", Default = false,
    Description = "Unverified remote shapes - swings the net when a butterfly blooms in reach; chases only while idle",
})

PetAutoSection:CreateToggle({
    Name = "Auto Place Best Pet", Flag = "AutoBestPet", Default = false,
    Description = "Wear best pets whenever new pets appear (every 30s)",
})

local EconomySection = MiscTab:CreateSection("Economy")

EconomySection:CreateToggle({
    Name = "Auto Claim Money", Flag = "AutoClaim", Default = false,
    Description = "Away earnings claim + codex redeem, every 2 minutes",
})

EconomySection:CreateToggle({
    Name = "Auto Upgrade Treadmill", Flag = "AutoUpgradeTreadmill", Default = false,
    Description = "Buys the next treadmill tier when you can afford it",
})

EconomySection:CreateToggle({
    Name = "Auto Buy Trail", Flag = "AutoBuyTrail", Default = false,
    Description = "Buys the most expensive affordable shop trail, then equips it",
})

local ConfigSection = MiscTab:CreateSection("Config")

ConfigSection:CreateToggle({
    Name = "Auto Save Config", Flag = "PrefAutoSave", Default = Prefs.AutoSave,
    Description = "Saves your toggles/filters 1.2s after any change (stored in its own _prefs file too)",
    Callback = function(on)
        Prefs.AutoSave = on and true or false
        SavePrefs()
        Window.AutoSaveName = on and "autosave" or nil
    end,
})

ConfigSection:CreateToggle({
    Name = "Auto Load Config", Flag = "PrefAutoLoad", Default = Prefs.AutoLoad,
    Description = "Restores the saved config on execute (this preference itself lives outside the config)",
    Callback = function(on)
        Prefs.AutoLoad = on and true or false
        SavePrefs()
        -- the ConfigLoading guard skips the echo fired while a config
        -- load applies this same toggle; only a real tap loads again
        if on and not ConfigLoading then
            task.spawn(function()
                if SafeLoadConfig() then
                    RefreshFilterDropdowns()
                    Notify("Config", "Saved config restored.", "success", 3)
                end
            end)
        end
    end,
})

local ServerSection = MiscTab:CreateSection("Server")

ServerSection:CreateButton({
    Name = "Hop to Lowest Server", ButtonText = "Hop", Cooldown = 10,
    Description = "6 samples, keeps servers seen in every sample, lowest player count",
    Callback = function()
        HopToLowest()
    end,
})

ServerSection:CreateButton({
    Name = "Unload", ButtonText = "Unload",
    Description = "Restores camera, replication focus and collisions, then closes the window",
    Callback = function()
        Window:Destroy()
    end,
})

local ProfileSection = MiscTab:CreateSection("Low Profile")
ProfileSection:CreateLabel("No hooks · nothing modified · load is read-only · regions avoided, never bypassed · glide ramps keep movement smooth")

--==============================================================
-- INIT
--==============================================================

ConnectGameEvents()
SetupAntiAfk()
SetupReconnect()

Track(LocalPlayer.CharacterAdded:Connect(OnCharacterAdded))
if LocalPlayer.Character then
    OnCharacterAdded(LocalPlayer.Character)
end

Supervisor("StealEngine", 1.0, StealEngineTick)
Supervisor("AutoTreadmill", 1.0, AutoTreadmillTick)
Supervisor("AntiRagdoll", 0.2, AntiRagdollTick)
Supervisor("AutoSell", SELL_INTERVAL, AutoSellTick)
Supervisor("AutoPlace", PLACE_INTERVAL, AutoPlaceTick)
Supervisor("AutoHatch", 1.0, AutoHatchTick)
Supervisor("AutoBestPet", BESTPET_INTERVAL, AutoBestPetTick)
Supervisor("AutoClaim", CLAIM_INTERVAL, AutoClaimTick)
Supervisor("AutoUpgradeTreadmill", UPGRADE_INTERVAL, AutoUpgradeTreadmillTick)
Supervisor("AutoBuyTrail", BUYTRAIL_INTERVAL, AutoBuyTrailTick)
Supervisor("AntiAfk", AFK_INTERVAL, AntiAfkTick)
Supervisor("ButterflyWatch", 30, TryConnectButterflies)
Supervisor("Watchdog", 2, function()
    for name, entry in Supervisors do
        if name ~= "Watchdog" and os.clock() - entry.HB > entry.Interval + 6 then
            entry.HB = os.clock()
            entry.Restart()
            warn("[RageHub] supervisor '" .. name .. "' stalled - restarted")
        end
    end
end)

task.spawn(function()
    pcall(RefreshSnapshot)
    RefreshFilterDropdowns()
end)

Notify("Rage Hub", "Steal An Egg " .. VERSION .. " loaded.", "success", 3)

task.delay(0.35, function()
    if not Runtime.Alive then return end
    if Prefs.AutoLoad and SafeLoadConfig() then
        RefreshFilterDropdowns()
        Notify("Config", "Saved config restored.", "success", 3)
    end
    QueueAutoExecute()
    SetStatus("Ready - " .. VERSION)
end)
