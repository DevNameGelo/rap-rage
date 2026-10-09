--// Rage Hub · Steal An Egg automation
--// Built for RageHub v1.0.0 UI API.
--// Research note: live community egg/biome catalogues change frequently; the scanner
--// prefers rarity/biome/egg metadata actually replicated in the current server.
--// If the game does not expose a label/attribute, the script cannot reliably infer it.

local RAGEHUB_URL = "https://raw.githubusercontent.com/devnamegelo/Rage-Hub/main/RageHub.lua"
local RageHub = loadstring(game:HttpGet(RAGEHUB_URL))()

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")
local VirtualUser = game:GetService("VirtualUser")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

--==============================================================
-- CONFIG / GAME REFERENCES
--==============================================================

local TREADMILL_TEST_SECONDS = 2
local TREADMILL_RETRY_DELAY = 0.3
local TREADMILL_RETURN_DISTANCE = 10
local TREADMILL_STAND_OFFSET = 3
local TRAVEL_SPEED = 500
local EGG_STAND_OFFSET = 3
local LAKE_STAND_OFFSET = 3
local LAKE_DROP_CONFIRM_TIMEOUT = 8
local WALK_TO_SPAWN_SPEED = 200
local TARGET_SCAN_INTERVAL = 1.1
local POST_STEAL_COOLDOWN = 2.5
local NextStealAllowedAt = 0
local LastTreadmillSearchAt = 0
local DROP_RETRY_COUNT = 5
local MAX_SERVER_PAGES = 3

local BIOMES = {
    "Forest", "Lake", "Desert", "Jungle", "Snow", "Volcano",
    "Abyss Ocean", "Prehistoric", "Cosmic", "Cherry Blossom",
    "Titan Temple", "Angels and Demons", "Enchanted Forest",
}

-- Higher numeric rank = higher priority. Exact rarity filtering uses exact labels.
local RARITY_RANK = {
    Unknown = 0, Common = 1, Uncommon = 2, Rare = 3, Epic = 4,
    Legendary = 5, Mythic = 6, Cosmic = 7, Secret = 8,
    Eternal = 9, Divine = 10, OG = 11,
}
local RARITIES = {"OG", "Divine", "Eternal", "Secret", "Cosmic", "Mythic", "Legendary", "Epic", "Rare", "Uncommon", "Common"}

-- Known named pulls documented in recent community guides. These are fallbacks only;
-- runtime rarity labels/attributes take priority over this table.
local KNOWN_RARITY_BY_NAME = {
    ["ice dragon"] = "Eternal", ["phoenix"] = "Eternal", ["lava dragon"] = "Eternal",
    ["el maja"] = "Eternal", ["mosasaurus"] = "Eternal", ["pegasus"] = "Eternal",
    ["eternal lunar dragon"] = "Eternal", ["oni tiger"] = "Eternal", ["gorilla king"] = "Eternal",
    ["skeleton horse"] = "Eternal", ["equinox"] = "Eternal", ["pink dragon experiment"] = "Eternal",
    ["archangel"] = "Divine", ["world burner"] = "Divine", ["aetheron"] = "Divine",
    ["unicorn"] = "Divine", ["kitsune"] = "Divine", ["nightflame"] = "Divine",
    ["mecha scrambler"] = "Divine", ["spirit world guardian"] = "Divine",
    ["cerberus"] = "Secret", ["king snake"] = "Secret", ["yeti"] = "Secret",
    ["tralaledon"] = "Secret", ["t-rex"] = "Secret", ["trex"] = "Secret",
    ["kraken"] = "Secret", ["cosmic dragon"] = "Secret", ["cosmic skeleton boss"] = "Secret",
    ["stag"] = "Secret", ["mutant shark"] = "Secret", ["pure jellyfish"] = "Secret",
    ["centaur"] = "Secret", ["gargoyle"] = "Secret", ["razorfang"] = "Secret",
    ["royal sphinx"] = "Cosmic", ["king mammoth"] = "Cosmic", ["holy peacock"] = "Cosmic",
    ["whale shark"] = "Cosmic", ["beluga whale"] = "Cosmic", ["mantaris"] = "Cosmic",
    ["rhinotaur"] = "Cosmic", ["sacred moth"] = "Cosmic", ["demon hound"] = "Cosmic",
}

local AUTO_TREADMILL = false
local AUTO_STEAL = false
local MANUAL_INSTANT_STEAL = false
local ANTI_AFK = false
local AUTO_RECONNECT = false
local AUTO_SMALLEST_SERVER = false
local AUTO_EXECUTE_AFTER_TELEPORT = false
local AUTO_SAVE_CONFIG = true

local SelectedRarities = {}
local SelectedBiomes = {}
local CurrentMode = "Idle"
local StealBusy = false
local StealJobToken = 0
local TweenToken = 0
local TreadmillToken = 0
local ActiveTween = nil
local OriginalWalkSpeed = nil
local OriginalAutoRotate = nil
local SavedTreadmill = nil
local SavedTreadmillPosition = nil
local TreadmillCandidates = {}
local TreadmillCandidateIndex = 0
local LastAttemptTime = setmetatable({}, {__mode = "k"})
local LastNotification = ""
local LastNotificationTime = 0
local AFKConnection = nil
local ReconnectAttempts = 0
local SCRIPT_RAW_URL = ""
local LastTargetDescription = "Waiting for a matching egg..."

local Env = _G
pcall(function() if type(getgenv) == "function" then Env = getgenv() end end)
if type(Env.__RageHubSavedTreadmill) == "table" then
    local saved = Env.__RageHubSavedTreadmill
    if type(saved.X) == "number" and type(saved.Y) == "number" and type(saved.Z) == "number" then
        SavedTreadmillPosition = Vector3.new(saved.X, saved.Y, saved.Z)
    end
end

--==============================================================
-- UI
--==============================================================

local Window = RageHub:CreateWindow({
    Name = "Rage Hub",
    Subtitle = "Steal An Egg · Auto Steal",
    Theme = "Rage",
    Features = { Notifications = true },
    ConfigFolder = "RageHub/StealAnEgg",
    AutoSave = "autosave",
    Splash = true,
    Watermark = true,
})

local MainTab = Window:CreateTab("Main", "⚡")
local StealTab = Window:CreateTab("Auto Steal", "🥚")
local FilterTab = Window:CreateTab("Filters", "🎯")
local SettingsTab = Window:CreateTab("Extra Settings", "⚙")

local TreadmillSection = MainTab:CreateSection("Auto Treadmill")
local StatusSection = MainTab:CreateSection("Live Status")
local AutoStealSection = StealTab:CreateSection("Automation")
local RarityFilterSection = FilterTab:CreateSection("Rarity Filter")
local BiomeFilterSection = FilterTab:CreateSection("Biome Filter")
local GeneralSettingsSection = SettingsTab:CreateSection("Session Settings")
local ServerSettingsSection = SettingsTab:CreateSection("Server Tools")
local ExecuteSettingsSection = SettingsTab:CreateSection("Auto Execute")

local function Notify(title, message, duration, kind)
    local now = os.clock()
    if LastNotification == tostring(message) and now - LastNotificationTime < 1 then return end
    LastNotification, LastNotificationTime = tostring(message), now
    pcall(function()
        Window:Notify({Title = title, Content = tostring(message), Duration = duration or 2.5, Type = kind or "info"})
    end)
end
local function EngineError(message)
    Notify("Engine Error", tostring(message), 4, "error")
end

local StatusLabel = StatusSection:CreateParagraph({
    Title = "Automation Status",
    Content = "Mode: Idle\nTarget: Waiting for a matching egg...\nTreadmill: Not tested",
})

local function SetStatus(extra)
    local saved = SavedTreadmillPosition and string.format("%.0f, %.0f, %.0f", SavedTreadmillPosition.X, SavedTreadmillPosition.Y, SavedTreadmillPosition.Z) or "Not saved"
    local text = "Mode: " .. tostring(CurrentMode) .. "\nTarget: " .. tostring(LastTargetDescription) .. "\nSaved treadmill: " .. saved
    if extra and extra ~= "" then text = text .. "\n" .. extra end
    pcall(function() StatusLabel:Set("Automation Status", text) end)
end

--==============================================================
-- CHARACTER / POSITION HELPERS
--==============================================================

local function Character() return LocalPlayer.Character end
local function Humanoid()
    local c = Character()
    return c and c:FindFirstChildOfClass("Humanoid")
end
local function Root()
    local c = Character()
    return c and c:FindFirstChild("HumanoidRootPart")
end
local function SafeGetPivot(model)
    local ok, cf = pcall(function() return model:GetPivot() end)
    return ok and cf or nil
end
local function PositionOf(obj)
    if not obj then return nil end
    if obj:IsA("BasePart") then return obj.Position end
    if obj:IsA("Attachment") then return obj.WorldPosition end
    if obj:IsA("Model") then
        local cf = SafeGetPivot(obj)
        return cf and cf.Position or nil
    end
    return nil
end
local function Distance(a, b)
    return a and b and (a - b).Magnitude or math.huge
end

local function RememberCharacterState()
    local h = Humanoid()
    if not h then return end
    if OriginalWalkSpeed == nil then OriginalWalkSpeed = h.WalkSpeed end
    if OriginalAutoRotate == nil then OriginalAutoRotate = h.AutoRotate end
end
local function RestoreCharacterState()
    local h = Humanoid()
    if h then
        if OriginalWalkSpeed ~= nil then pcall(function() h.WalkSpeed = OriginalWalkSpeed end) end
        if OriginalAutoRotate ~= nil then pcall(function() h.AutoRotate = OriginalAutoRotate end) end
    end
    OriginalWalkSpeed, OriginalAutoRotate = nil, nil
end

local function CancelTween()
    TweenToken += 1
    if ActiveTween then
        pcall(function() ActiveTween:Cancel() end)
        ActiveTween = nil
    end
end

local function TweenToPosition(targetPosition, offset, mode, callback, speed)
    local root, hum = Root(), Humanoid()
    if not root or not hum then EngineError("Character or HumanoidRootPart not ready."); return false end
    if typeof(targetPosition) ~= "Vector3" then EngineError("Target position was invalid."); return false end

    CancelTween()
    RememberCharacterState()
    hum.AutoRotate = false

    local destination = Vector3.new(targetPosition.X, targetPosition.Y + (offset or 0), targetPosition.Z)
    local goal = CFrame.new(destination) * root.CFrame.Rotation
    local distance = (root.Position - destination).Magnitude
    local duration = math.clamp(distance / math.max(1, speed or TRAVEL_SPEED), 0.18, 8)
    local myToken = TweenToken
    CurrentMode = mode or "TweenTravel"
    SetStatus()

    local tween = TweenService:Create(root, TweenInfo.new(duration, Enum.EasingStyle.Linear, Enum.EasingDirection.Out), {CFrame = goal})
    ActiveTween = tween
    tween.Completed:Connect(function(playbackState)
        if myToken ~= TweenToken then return end
        if ActiveTween == tween then ActiveTween = nil end
        if playbackState ~= Enum.PlaybackState.Completed then return end
        if callback then
            local ok, err = pcall(callback)
            if not ok then EngineError("Tween callback failed: " .. tostring(err)) end
        end
    end)
    tween:Play()
    return true
end

--==============================================================
-- RARITY / BIOME / VALUE IDENTIFICATION
--==============================================================

local function Normalize(s)
    s = string.lower(tostring(s or ""))
    s = s:gsub("[%p%c]", " "):gsub("%s+", " ")
    return s
end

local function GetKnownRarity(text)
    local n = Normalize(text)
    -- Check whole tier tokens in priority order; OG outranks Divine.
    for _, rarity in ipairs({"OG", "Divine", "Eternal", "Secret", "Cosmic", "Mythic", "Legendary", "Epic", "Rare", "Uncommon", "Common"}) do
        local token = string.lower(rarity)
        if n:match("%f[%a]" .. token .. "%f[%A]") then return rarity end
    end
    for knownName, rarity in pairs(KNOWN_RARITY_BY_NAME) do
        if n:find(knownName, 1, true) then return rarity end
    end
    return "Unknown"
end

local function GetBiomeFromText(text)
    local n = Normalize(text)
    local aliases = {
        {"Angels and Demons", {"angels and demons", "angels vs demons", "angel and demon", "angel biome", "demon biome", "darkness biome", "light biome"}},
        {"Abyss Ocean", {"abyss ocean", "abyss", "deep ocean"}},
        {"Cherry Blossom", {"cherry blossom", "sakura"}},
        {"Titan Temple", {"titan temple", "titan"}},
        {"Enchanted Forest", {"enchanted forest", "enchanted tree"}},
        {"Prehistoric", {"prehistoric", "dinosaur"}},
        {"Volcano", {"volcano", "volcanic"}},
        {"Desert", {"desert", "sand biome"}},
        {"Jungle", {"jungle"}}, {"Forest", {"forest"}}, {"Lake", {"lake"}},
        {"Snow", {"snow", "ice biome"}}, {"Cosmic", {"cosmic", "space biome"}},
    }
    for _, record in ipairs(aliases) do
        for _, alias in ipairs(record[2]) do
            if n:find(alias, 1, true) then return record[1] end
        end
    end
    return "Unknown"
end

local function IsStealPrompt(prompt)
    if not prompt or not prompt:IsA("ProximityPrompt") then return false end
    local n = Normalize(prompt.Name .. " " .. prompt.ActionText .. " " .. prompt.ObjectText)
    return n:find("steal", 1, true) ~= nil
end

local function GetPromptPosition(prompt)
    if not prompt then return nil end
    local p = prompt.Parent
    if p and p:IsA("Attachment") then return p.WorldPosition end
    if p and p:IsA("BasePart") then return p.Position end
    if p and p:IsA("Model") then return PositionOf(p) end
    local current = p
    for _ = 1, 5 do
        if not current then break end
        local pos = PositionOf(current)
        if pos then return pos end
        current = current.Parent
    end
    return nil
end

local function GetPromptContainer(prompt)
    local current = prompt and prompt.Parent
    local fallbackModel = nil
    for _ = 1, 5 do
        if not current or current == workspace then break end
        if current:IsA("Model") then
            if not fallbackModel then fallbackModel = current end
            local n = Normalize(current.Name)
            if n:find("egg", 1, true) or n:find("pet", 1, true) or n:find("nest", 1, true) then
                return current
            end
        end
        current = current.Parent
    end
    -- Prefer the prompt's own part/attachment for position and local labels; a shared Guard model
    -- may contain several eggs and must not be treated as one candidate.
    return (prompt and prompt.Parent) or fallbackModel
end

local function AppendAttributes(parts, obj)
    if not obj then return end
    local ok, attrs = pcall(function() return obj:GetAttributes() end)
    if ok and type(attrs) == "table" then
        for key, value in pairs(attrs) do
            local keyNorm = Normalize(key)
            if keyNorm:find("rarity", 1, true) or keyNorm:find("tier", 1, true) or keyNorm:find("biome", 1, true)
                or keyNorm:find("egg", 1, true) or keyNorm:find("pet", 1, true) or keyNorm:find("value", 1, true)
                or keyNorm:find("price", 1, true) or keyNorm:find("income", 1, true) or keyNorm:find("weight", 1, true)
                or keyNorm:find("worth", 1, true) then
                table.insert(parts, tostring(key) .. " " .. tostring(value))
            end
        end
    end
end

local function GetEggMetadata(prompt)
    local parts, containers = {}, {}
    local function add(v) if v ~= nil and tostring(v) ~= "" then table.insert(parts, tostring(v)) end end
    add(prompt.Name); add(prompt.ActionText); add(prompt.ObjectText)
    local current = prompt
    for _ = 1, 7 do
        if not current or current == workspace then break end
        containers[#containers + 1] = current
        add(current.Name)
        AppendAttributes(parts, current)
        if current:IsA("StringValue") or current:IsA("IntValue") or current:IsA("NumberValue") then add(current.Value) end
        current = current.Parent
    end

    local container = GetPromptContainer(prompt)
    if container then
        -- Inspect only a limited number of descendants to capture Billboard/Surface labels without scanning the whole map.
        local inspected = 0
        for _, desc in ipairs(container:GetDescendants()) do
            inspected += 1
            if inspected > 100 then break end
            if desc:IsA("TextLabel") or desc:IsA("TextButton") then
                if desc.Visible then add(desc.Text) end
            elseif desc:IsA("StringValue") or desc:IsA("IntValue") or desc:IsA("NumberValue") then
                local k = Normalize(desc.Name)
                if k:find("rarity", 1, true) or k:find("tier", 1, true) or k:find("egg", 1, true) or k:find("pet", 1, true)
                    or k:find("value", 1, true) or k:find("price", 1, true) or k:find("income", 1, true) or k:find("weight", 1, true) then
                    add(desc.Name); add(desc.Value)
                end
            end
            AppendAttributes(parts, desc)
        end
    end

    local combined = table.concat(parts, " | ")
    local rarity = GetKnownRarity(combined)
    local biome = GetBiomeFromText(combined)
    local label = prompt.ObjectText
    if label == nil or Normalize(label) == "" or Normalize(label) == "egg" or Normalize(label) == "steal" then
        label = (container and container.Name) or prompt.Parent.Name
    end
    local value, size = 0, 0
    for _, obj in ipairs(containers) do
        local ok, attrs = pcall(function() return obj:GetAttributes() end)
        if ok and type(attrs) == "table" then
            for key, raw in pairs(attrs) do
                if type(raw) == "number" then
                    local k = Normalize(key)
                    if k:find("value", 1, true) or k:find("price", 1, true) or k:find("income", 1, true)
                        or k:find("worth", 1, true) or k:find("cash", 1, true) or k:find("money", 1, true)
                        or k:find("weight", 1, true) then value = math.max(value, raw) end
                end
            end
        end
    end
    if container then
        pcall(function()
            if container:IsA("Model") then
                local _, boxSize = container:GetBoundingBox()
                size = boxSize.X * boxSize.Y * boxSize.Z
            elseif container:IsA("BasePart") then
                size = container.Size.X * container.Size.Y * container.Size.Z
            end
        end)
        pcall(function()
            local inspected = 0
            for _, desc in ipairs(container:GetDescendants()) do
                inspected += 1
                if inspected > 100 then break end
                if desc:IsA("NumberValue") or desc:IsA("IntValue") then
                    local k = Normalize(desc.Name)
                    if k:find("value", 1, true) or k:find("price", 1, true) or k:find("income", 1, true)
                        or k:find("worth", 1, true) or k:find("cash", 1, true) or k:find("money", 1, true) or k:find("weight", 1, true) then
                        value = math.max(value, desc.Value)
                    end
                end
            end
        end)
    end
    return {
        Prompt = prompt,
        Container = container,
        Position = GetPromptPosition(prompt),
        Label = tostring(label or "Unknown egg"),
        MetadataText = combined,
        Rarity = rarity,
        Biome = biome,
        Rank = RARITY_RANK[rarity] or 0,
        Value = value,
        Size = size,
    }
end

local function HasAny(set)
    return type(set) == "table" and next(set) ~= nil
end
local function MatchesFilters(candidate)
    if not candidate then return false end
    if HasAny(SelectedRarities) then
        if candidate.Rarity == "Unknown" or not SelectedRarities[candidate.Rarity] then return false end
    end
    if HasAny(SelectedBiomes) then
        if candidate.Biome == "Unknown" or not SelectedBiomes[candidate.Biome] then return false end
    end
    return true
end

local function CandidateCooldownActive(prompt)
    local last = LastAttemptTime[prompt]
    return last and (os.clock() - last) < 12
end

local function CandidateBetter(a, b, rootPosition)
    if not b then return true end
    if a.Rank ~= b.Rank then return a.Rank > b.Rank end
    if a.Value ~= b.Value then return a.Value > b.Value end
    if a.Size ~= b.Size then return a.Size > b.Size end
    local da = rootPosition and Distance(a.Position, rootPosition) or math.huge
    local db = rootPosition and Distance(b.Position, rootPosition) or math.huge
    return da < db
end

local function FindBestEggCandidate()
    local root = Root()
    local candidates = {}
    local seen = {}
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("ProximityPrompt") and obj.Enabled and IsStealPrompt(obj) then
            local candidate = GetEggMetadata(obj)
            if candidate.Position and not CandidateCooldownActive(obj) and MatchesFilters(candidate) then
                -- Keep each live prompt separate: several nests may share a Guard model.
                if not seen[obj] then
                    seen[obj] = true
                    table.insert(candidates, candidate)
                end
            end
        end
    end
    local best
    for _, candidate in ipairs(candidates) do
        if CandidateBetter(candidate, best, root and root.Position or nil) then best = candidate end
    end
    return best, #candidates
end

--==============================================================
-- TREADMILL DISCOVERY / SPEED PROOF
--==============================================================

local function IsTreadmill(obj)
    local n = Normalize(obj and obj.Name)
    return n:find("treadmill", 1, true) ~= nil or n:find("tread mill", 1, true) ~= nil
end
local function FindTreadmills()
    local found, seen = {}, {}
    for _, obj in ipairs(workspace:GetDescendants()) do
        if IsTreadmill(obj) and (obj:IsA("BasePart") or obj:IsA("Model")) then
            local rootObj = obj
            local parent = obj.Parent
            while parent and parent ~= workspace do
                if parent:IsA("Model") and IsTreadmill(parent) then rootObj = parent end
                parent = parent.Parent
            end
            if not seen[rootObj] and PositionOf(rootObj) then
                seen[rootObj] = true
                table.insert(found, rootObj)
            end
        end
    end
    local root = Root()
    if root then
        table.sort(found, function(a, b) return Distance(PositionOf(a), root.Position) < Distance(PositionOf(b), root.Position) end)
    end
    return found
end

local function GetTreadmillStandPosition(obj)
    if not obj then return nil end
    if obj:IsA("BasePart") then
        return obj.Position + Vector3.new(0, obj.Size.Y / 2 + TREADMILL_STAND_OFFSET, 0)
    elseif obj:IsA("Model") then
        local ok, cf, size = pcall(function() return obj:GetBoundingBox() end)
        if ok and cf and size then return cf.Position + Vector3.new(0, size.Y / 2 + TREADMILL_STAND_OFFSET, 0) end
    end
    local pos = PositionOf(obj)
    return pos and (pos + Vector3.new(0, TREADMILL_STAND_OFFSET, 0)) or nil
end

local function ReadSpeedCounters()
    local values = {}
    local function scan(container, prefix)
        if not container then return end
        local descendants = {}
        pcall(function() descendants = container:GetDescendants() end)
        for _, obj in ipairs(descendants) do
            local n = Normalize(obj.Name)
            if (n == "speed" or n == "walk speed" or n == "walkspeed" or n == "steps" or n == "power" or n == "total speed")
                and (obj:IsA("NumberValue") or obj:IsA("IntValue")) then
                values[prefix .. obj:GetFullName()] = obj.Value
            end
        end
    end
    scan(LocalPlayer:FindFirstChild("leaderstats"), "leader:")
    scan(LocalPlayer:FindFirstChild("Data"), "data:")
    scan(LocalPlayer:FindFirstChild("Stats"), "stats:")
    scan(LocalPlayer, "player:")
    for _, container in ipairs({LocalPlayer, Character(), Humanoid()}) do
        if container then
            local ok, attrs = pcall(function() return container:GetAttributes() end)
            if ok and type(attrs) == "table" then
                for key, val in pairs(attrs) do
                    local n = Normalize(key)
                    if type(val) == "number" and (n == "speed" or n == "steps" or n == "power" or n == "walkspeed" or n == "walk speed") then
                        values["attr:" .. container:GetFullName() .. ":" .. key] = val
                    end
                end
            end
        end
    end
    return values
end

local function CounterIncreased(before, after)
    for key, value in pairs(after) do
        if before[key] ~= nil and value > before[key] then return true, key end
    end
    return false
end

local function SaveTreadmill(obj)
    SavedTreadmill = obj
    SavedTreadmillPosition = GetTreadmillStandPosition(obj) or PositionOf(obj)
    if SavedTreadmillPosition then
        pcall(function()
            Env.__RageHubSavedTreadmill = {X = SavedTreadmillPosition.X, Y = SavedTreadmillPosition.Y, Z = SavedTreadmillPosition.Z}
        end)
        Notify("Auto Treadmill", "Speed gain detected. Working treadmill saved for respawns.", 3, "success")
        SetStatus("Treadmill accepted after speed test")
    end
end

local function StopTreadmillTask()
    TreadmillToken += 1
    if CurrentMode:find("Treadmill") then
        CancelTween()
        CurrentMode = "Idle"
    end
end

local function FindClosestTreadmillToSaved(candidates)
    if SavedTreadmill and SavedTreadmill.Parent then
        for _, obj in ipairs(candidates) do if obj == SavedTreadmill then return obj end end
    end
    if not SavedTreadmillPosition then return nil end
    local best, bestDistance
    for _, obj in ipairs(candidates) do
        local pos = GetTreadmillStandPosition(obj) or PositionOf(obj)
        local d = pos and Distance(pos, SavedTreadmillPosition) or math.huge
        if not best or d < bestDistance then best, bestDistance = obj, d end
    end
    return best
end

local StartTreadmillSearch
local function TestTreadmillCandidate(obj, generation)
    if not AUTO_TREADMILL or StealBusy or generation ~= TreadmillToken then return end
    local pos = GetTreadmillStandPosition(obj)
    if not pos then return end
    LastTargetDescription = "Testing treadmill: " .. obj:GetFullName()
    SetStatus()
    Notify("Auto Treadmill", "Testing treadmill for 2 seconds: " .. obj.Name, 2)
    local root = Root()
    if not root then EngineError("Character not ready for treadmill test."); return end

    local function beginTest()
        if not AUTO_TREADMILL or StealBusy or generation ~= TreadmillToken then return end
        local before = ReadSpeedCounters()
        local startWalkSpeed = (Humanoid() and Humanoid().WalkSpeed) or 16
        local hadCounter = next(before) ~= nil
        local start = os.clock()
        CurrentMode = "TreadmillTesting"
        SetStatus()
        task.spawn(function()
            while AUTO_TREADMILL and not StealBusy and generation == TreadmillToken and os.clock() - start < TREADMILL_TEST_SECONDS do
                task.wait(0.2)
                local r, h = Root(), Humanoid()
                if not r or not h then return end
                local after = ReadSpeedCounters()
                local gained = CounterIncreased(before, after)
                local walkSpeedGained = h.WalkSpeed > startWalkSpeed
                local horizontalSpeed = Vector3.new(r.AssemblyLinearVelocity.X, 0, r.AssemblyLinearVelocity.Z).Magnitude
                -- If the actual game speed counter is visible, require its gain or a real WalkSpeed increase.
                -- Only use movement as fallback when the game exposes no recognized speed stat.
                local fallbackMovement = (not hadCounter) and horizontalSpeed >= 8
                if gained or walkSpeedGained or fallbackMovement then
                    SaveTreadmill(obj)
                    CurrentMode = "Treadmill"
                    RestoreCharacterState()
                    SetStatus(hadCounter and "Speed counter changed" or "No readable counter; movement fallback accepted")
                    return
                end
            end
            if not AUTO_TREADMILL or StealBusy or generation ~= TreadmillToken then return end
            Notify("Auto Treadmill", "No speed gain in 2 seconds. Trying the next treadmill...", 2, "warning")
            task.wait(TREADMILL_RETRY_DELAY)
            if AUTO_TREADMILL and not StealBusy and generation == TreadmillToken then
                TreadmillCandidateIndex += 1
                if TreadmillCandidateIndex > #TreadmillCandidates then
                    TreadmillCandidates = FindTreadmills()
                    TreadmillCandidateIndex = 1
                end
                local nextObj = TreadmillCandidates[TreadmillCandidateIndex]
                if nextObj then TestTreadmillCandidate(nextObj, generation)
                else EngineError("No objects named Treadmill were found."); CurrentMode = "Idle" end
            end
        end)
    end

    local distance = Distance(root.Position, pos)
    if distance > 8 then
        TweenToPosition(pos, 0, "TreadmillTravel", function()
            if AUTO_TREADMILL and not StealBusy and generation == TreadmillToken then beginTest() end
        end, TRAVEL_SPEED)
    else
        beginTest()
    end
end

StartTreadmillSearch = function()
    if not AUTO_TREADMILL or StealBusy then return end
    TreadmillToken += 1
    local generation = TreadmillToken
    TreadmillCandidates = FindTreadmills()
    if #TreadmillCandidates == 0 then
        CurrentMode = "Idle"
        EngineError("No objects named Treadmill found. If the game uses a different object name, treadmill auto-detection needs that path.")
        return
    end
    local preferred = FindClosestTreadmillToSaved(TreadmillCandidates)
    if preferred then
        for i, obj in ipairs(TreadmillCandidates) do if obj == preferred then TreadmillCandidateIndex = i; break end end
    else
        TreadmillCandidateIndex = 1
    end
    TestTreadmillCandidate(TreadmillCandidates[TreadmillCandidateIndex], generation)
end

local function ReturnToTreadmill()
    if not AUTO_TREADMILL or StealBusy then return end
    TreadmillCandidates = FindTreadmills()
    if #TreadmillCandidates == 0 then
        StartTreadmillSearch()
        return
    end
    local saved = FindClosestTreadmillToSaved(TreadmillCandidates)
    if saved then
        local pos = GetTreadmillStandPosition(saved)
        if pos then
            TreadmillToken += 1
            local generation = TreadmillToken
            CurrentMode = "TreadmillReturn"
            Notify("Auto Treadmill", "Returning to saved working treadmill...", 2)
            TweenToPosition(pos, 0, "TreadmillReturn", function()
                if AUTO_TREADMILL and not StealBusy and generation == TreadmillToken then
                    for i, obj in ipairs(TreadmillCandidates) do if obj == saved then TreadmillCandidateIndex = i; break end end
                    TestTreadmillCandidate(saved, generation)
                end
            end, TRAVEL_SPEED)
            return
        end
    end
    StartTreadmillSearch()
end

--==============================================================
-- DROP GUI / CARRY INFO
--==============================================================

local function GuiVisible(gui)
    if not gui or not gui.Parent then return false end
    local current = gui
    while current and current ~= PlayerGui do
        if current:IsA("GuiObject") and not current.Visible then return false end
        if current:IsA("ScreenGui") and not current.Enabled then return false end
        current = current.Parent
    end
    return true
end

local function GuiButtonText(button)
    local pieces = {tostring(button.Name)}
    if button:IsA("TextButton") then table.insert(pieces, tostring(button.Text)) end
    for _, child in ipairs(button:GetDescendants()) do
        if child:IsA("TextLabel") or child:IsA("TextButton") then table.insert(pieces, tostring(child.Text)) end
    end
    return table.concat(pieces, " ")
end

local function FindDropButton()
    for _, obj in ipairs(PlayerGui:GetDescendants()) do
        if obj:IsA("GuiButton") and GuiVisible(obj) then
            local text = Normalize(GuiButtonText(obj))
            if text:match("%f[%a]drop%f[%A]") or text == "drop" then return obj end
        end
    end
    return nil
end

local function ReadPossibleCarriedEggInfo()
    local parts = {}
    local function add(s) if s ~= nil and tostring(s) ~= "" then table.insert(parts, tostring(s)) end end
    local containers = {LocalPlayer, Character()}
    for _, c in ipairs(containers) do
        if c then
            local ok, attrs = pcall(function() return c:GetAttributes() end)
            if ok and type(attrs) == "table" then
                for key, value in pairs(attrs) do
                    local k = Normalize(key)
                    if k:find("carry", 1, true) or k:find("holding", 1, true) or k:find("current egg", 1, true)
                        or k:find("egg name", 1, true) or k:find("held egg", 1, true) or k:find("rarity", 1, true) then
                        add(key); add(value)
                    end
                end
            end
            for _, desc in ipairs(c:GetDescendants()) do
                if desc:IsA("Tool") or desc:IsA("Model") then
                    local n = Normalize(desc.Name)
                    if n:find("egg", 1, true) or n:find("carry", 1, true) or n:find("hold", 1, true) then add(desc.Name); AppendAttributes(parts, desc) end
                end
            end
        end
    end
    -- Some versions expose held egg details in a Drop/Carry/Egg GUI. Avoid reading all unrelated Rage Hub labels.
    for _, gui in ipairs(PlayerGui:GetChildren()) do
        if gui:IsA("ScreenGui") and (Normalize(gui.Name):find("drop", 1, true) or Normalize(gui.Name):find("carry", 1, true) or Normalize(gui.Name):find("egg", 1, true)) then
            if gui.Enabled then
                for _, desc in ipairs(gui:GetDescendants()) do
                    if (desc:IsA("TextLabel") or desc:IsA("TextButton")) and GuiVisible(desc) then add(desc.Text) end
                end
            end
        end
    end
    local text = table.concat(parts, " | ")
    local rarity = GetKnownRarity(text)
    local biome = GetBiomeFromText(text)
    local normalized = Normalize(text)
    if normalized == "" or (not normalized:find("egg", 1, true) and rarity == "Unknown" and biome == "Unknown") then return nil end
    return {Text = text, Rarity = rarity, Biome = biome}
end

local function IsDetectedCarryWrong(held, target)
    if not held or not target then return false end
    -- Only declare a mismatch when the UI exposes a positive, specific clue.
    if HasAny(SelectedRarities) and held.Rarity ~= "Unknown" and not SelectedRarities[held.Rarity] then return true end
    if HasAny(SelectedBiomes) and held.Biome ~= "Unknown" and not SelectedBiomes[held.Biome] then return true end
    if target.Rarity ~= "Unknown" and held.Rarity ~= "Unknown" and target.Rarity ~= held.Rarity then return true end
    return false
end

local function ClickGuiButton(button)
    if not button or not button.Parent then return false end
    local sent = false
    if type(firesignal) == "function" then
        local ok = pcall(function() firesignal(button.Activated) end)
        sent = ok
        if not sent and button:IsA("TextButton") then
            ok = pcall(function() firesignal(button.MouseButton1Click) end)
            sent = ok
        end
    end
    if sent then return true end
    local ok = pcall(function()
        local vim = game:GetService("VirtualInputManager")
        local center = button.AbsolutePosition + button.AbsoluteSize / 2
        vim:SendMouseButtonEvent(center.X, center.Y, 0, true, game, 0)
        task.wait(0.05)
        vim:SendMouseButtonEvent(center.X, center.Y, 0, false, game, 0)
    end)
    return ok
end

local function ClickDropAndConfirm(jobToken)
    local deadline = os.clock() + LAKE_DROP_CONFIRM_TIMEOUT
    local button
    repeat
        if not StealBusy or jobToken ~= StealJobToken then return false end
        button = FindDropButton()
        if button then break end
        task.wait(0.1)
    until os.clock() >= deadline

    if not button then
        EngineError("Drop GUI did not appear at Lake. Workflow stopped; no spawn walk will happen.")
        return false
    end

    Notify("Auto Steal", "Drop GUI found. Clicking and verifying...", 2)
    for attempt = 1, DROP_RETRY_COUNT do
        if not StealBusy or jobToken ~= StealJobToken then return false end
        if not button or not button.Parent or not GuiVisible(button) then
            Notify("Auto Steal", "Drop confirmed: Drop GUI disappeared.", 2, "success")
            return true
        end
        ClickGuiButton(button)
        task.wait(0.35)
        local fresh = FindDropButton()
        if not fresh then
            Notify("Auto Steal", "Drop confirmed: Drop control is gone.", 2, "success")
            return true
        end
        button = fresh
    end
    EngineError("Could not confirm the Drop action. Staying at Lake; spawn walk cancelled.")
    return false
end

--==============================================================
-- SPAWN / SECOND STEAL PROMPT / WALK
--==============================================================

local function FindSpawn()
    local direct = workspace:FindFirstChild("SpawnLocation", true)
    if direct and direct:IsA("BasePart") then return direct end
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("SpawnLocation") then return obj end
    end
    return nil
end

local function FindLakeEggPoint()
    local world = workspace:FindFirstChild("World")
    local areas = world and world:FindFirstChild("Areas")
    local guards = areas and areas:FindFirstChild("GuardAreas")
    local lake = guards and guards:FindFirstChild("Lake")
    local guard = lake and lake:FindFirstChild("Guard")
    local point = guard and guard:FindFirstChild("EggPoint")
    if point then return point end
    for _, obj in ipairs(workspace:GetDescendants()) do if obj.Name == "EggPoint" then return obj end end
    return nil
end

local function FindNearbyStealPrompt(excludePrompt)
    local root = Root()
    if not root then return nil end
    local closest, best = nil, 18
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("ProximityPrompt") and obj ~= excludePrompt and obj.Enabled and IsStealPrompt(obj) then
            local pos = GetPromptPosition(obj)
            local d = pos and Distance(root.Position, pos) or math.huge
            if d < best then closest, best = obj, d end
        end
    end
    return closest
end

local function TriggerStealPrompt(prompt)
    if not prompt or not prompt.Parent then EngineError("Steal prompt disappeared."); return false end
    local ok = false
    if type(fireproximityprompt) == "function" then
        ok = pcall(function() fireproximityprompt(prompt, 0.1) end)
    end
    if not ok then
        ok = pcall(function()
            prompt:InputHoldBegin()
            task.wait(math.max(0.1, prompt.HoldDuration))
            prompt:InputHoldEnd()
        end)
    end
    if ok then return true end
    EngineError("Couldn't activate the Steal prompt.")
    return false
end

local function FinishJob(jobToken, message, restart)
    if jobToken ~= StealJobToken then return end
    NextStealAllowedAt = os.clock() + POST_STEAL_COOLDOWN
    CancelTween()
    RestoreCharacterState()
    StealBusy = false
    CurrentMode = "Idle"
    if message then Notify("Auto Steal", message, 2.5) end
    SetStatus()
    if restart then
        task.delay(POST_STEAL_COOLDOWN, function()
            if AUTO_STEAL and not StealBusy then
                local candidate = FindBestEggCandidate()
                if not candidate and AUTO_TREADMILL then ReturnToTreadmill() end
            elseif AUTO_TREADMILL and not StealBusy then
                ReturnToTreadmill()
            end
        end)
    end
end

local function WalkToSpawn(jobToken, lakeStealPrompt)
    local spawn, hum, root = FindSpawn(), Humanoid(), Root()
    if not spawn or not hum or not root then EngineError("SpawnLocation/Humanoid/Root not found."); FinishJob(jobToken, "Workflow stopped.", true); return end
    CancelTween()
    CurrentMode = "StealWalk"
    RememberCharacterState()
    hum.AutoRotate = true
    hum.WalkSpeed = WALK_TO_SPAWN_SPEED
    local destination = Vector3.new(spawn.Position.X, spawn.Position.Y + 2, spawn.Position.Z)
    hum:MoveTo(destination)
    Notify("Auto Steal", "Second Steal prompt activated. Walking to spawn at speed 200...", 2)
    SetStatus()
    task.spawn(function()
        local started = os.clock()
        while StealBusy and jobToken == StealJobToken and os.clock() - started < 25 do
            task.wait(0.15)
            root = Root()
            if not root or not root.Parent then break end
            if Distance(root.Position, destination) <= 6 then
                FinishJob(jobToken, "Reached spawn. Cycle complete.", true)
                return
            end
        end
        if StealBusy and jobToken == StealJobToken then
            EngineError("Walk to spawn was interrupted or timed out.")
            FinishJob(jobToken, "Spawn walk stopped.", true)
        end
    end)
end

local function RunStealWorkflow(initialPrompt, initialCandidate, isAutomated)
    if StealBusy then return false end
    if not initialPrompt or not initialPrompt.Parent or not initialPrompt.Enabled then
        EngineError("Target Steal prompt is no longer available.")
        return false
    end
    StealBusy = true
    StealJobToken += 1
    local jobToken = StealJobToken
    TreadmillToken += 1
    CancelTween()
    CurrentMode = "StealToEgg"

    local candidate = initialCandidate or GetEggMetadata(initialPrompt)
    LastTargetDescription = string.format("%s · %s · %s", tostring(candidate.Label), tostring(candidate.Rarity), tostring(candidate.Biome))
    SetStatus()
    Notify("Auto Steal", "Targeting " .. LastTargetDescription, 3, "info")

    local position = GetPromptPosition(initialPrompt)
    if not position then
        EngineError("Target egg position could not be read.")
        FinishJob(jobToken, "Target unavailable.", true)
        return false
    end

    local function AfterTargetArrival()
        if not StealBusy or jobToken ~= StealJobToken then return end
        if not initialPrompt.Parent or not initialPrompt.Enabled then
            LastAttemptTime[initialPrompt] = os.clock()
            FinishJob(jobToken, "Target disappeared before stealing; scanning again.", true)
            return
        end
        local fresh = GetEggMetadata(initialPrompt)
        if isAutomated and not MatchesFilters(fresh) then
            LastAttemptTime[initialPrompt] = os.clock()
            FinishJob(jobToken, "Target no longer matches filters; skipping it.", true)
            return
        end
        if not TriggerStealPrompt(initialPrompt) then
            LastAttemptTime[initialPrompt] = os.clock()
            FinishJob(jobToken, "Steal prompt failed; retry will scan another egg.", true)
            return
        end

        task.spawn(function()
            -- Give the game a moment to attach the Drop UI/carry state after the prompt.
            task.wait(0.3)
            if not StealBusy or jobToken ~= StealJobToken then return end
            local heldInfo = ReadPossibleCarriedEggInfo()
            local wrongEggDetected = heldInfo and IsDetectedCarryWrong(heldInfo, candidate) or false
            if wrongEggDetected then
                Notify("Auto Steal", "Detected a carried egg that doesn't match the filter. Going to Lake to drop it, then searching again.", 3, "warning")
            end

            local lakePoint = FindLakeEggPoint()
            if not lakePoint then
                EngineError("Lake EggPoint not found at World.Areas.GuardAreas.Lake.Guard.EggPoint.")
                LastAttemptTime[initialPrompt] = os.clock()
                FinishJob(jobToken, "Lake point missing; workflow stopped.", true)
                return
            end
            local lakePosition = PositionOf(lakePoint)
            if not lakePosition then
                EngineError("Lake EggPoint did not expose a position.")
                FinishJob(jobToken, "Lake point invalid.", true)
                return
            end
            CurrentMode = "StealToLake"
            Notify("Auto Steal", "Tweening to Lake Drop point...", 2)
            SetStatus()
            TweenToPosition(lakePosition, LAKE_STAND_OFFSET, "StealToLake", function()
                if not StealBusy or jobToken ~= StealJobToken then return end
                task.spawn(function()
                    local dropped = ClickDropAndConfirm(jobToken)
                    if not dropped then
                        LastAttemptTime[initialPrompt] = os.clock()
                        -- Hard requirement: never activate another prompt or walk to spawn without drop confirmation.
                        FinishJob(jobToken, "Drop could not be confirmed; stopped at Lake.", true)
                        return
                    end
                    task.wait(0.5)
                    if not StealBusy or jobToken ~= StealJobToken then return end

                    if wrongEggDetected then
                        LastAttemptTime[initialPrompt] = os.clock()
                        FinishJob(jobToken, "Wrong egg dropped. Rescanning for a filtered target.", true)
                        return
                    end

                    local nearbyPrompt = FindNearbyStealPrompt(initialPrompt)
                    if not nearbyPrompt then
                        EngineError("Drop confirmed, but no nearby Steal prompt was found. Staying at Lake.")
                        FinishJob(jobToken, "No nearby Steal prompt; spawn walk cancelled.", true)
                        return
                    end
                    if not TriggerStealPrompt(nearbyPrompt) then
                        FinishJob(jobToken, "Second Steal failed; spawn walk cancelled.", true)
                        return
                    end
                    task.wait(0.15)
                    if StealBusy and jobToken == StealJobToken then WalkToSpawn(jobToken, nearbyPrompt) end
                end)
            end, TRAVEL_SPEED)
        end)
    end

    local started = TweenToPosition(position, EGG_STAND_OFFSET, "StealToEgg", AfterTargetArrival, TRAVEL_SPEED)
    if not started then
        LastAttemptTime[initialPrompt] = os.clock()
        FinishJob(jobToken, "Could not start target tween.", true)
        return false
    end
    return true
end

--==============================================================
-- PROMPT HOLD DURATION / MANUAL FLOW
--==============================================================

local OriginalPromptDurations = setmetatable({}, {__mode = "k"})
local function SetPromptFast(prompt, enabled)
    if not IsStealPrompt(prompt) then return end
    if enabled then
        if OriginalPromptDurations[prompt] == nil then OriginalPromptDurations[prompt] = prompt.HoldDuration end
        pcall(function() prompt.HoldDuration = 0.1 end)
    else
        local old = OriginalPromptDurations[prompt]
        if old ~= nil and prompt.Parent then pcall(function() prompt.HoldDuration = old end) end
        OriginalPromptDurations[prompt] = nil
    end
end
local function SetupAllStealPrompts(enabled)
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("ProximityPrompt") then SetPromptFast(obj, enabled) end
    end
end
workspace.DescendantAdded:Connect(function(obj)
    if obj:IsA("ProximityPrompt") and (AUTO_STEAL or MANUAL_INSTANT_STEAL) then
        task.defer(function() if obj.Parent then SetPromptFast(obj, true) end end)
    end
end)

ProximityPromptService.PromptTriggered:Connect(function(prompt, triggeringPlayer)
    if triggeringPlayer ~= LocalPlayer or not IsStealPrompt(prompt) or StealBusy then return end
    if MANUAL_INSTANT_STEAL and not AUTO_STEAL then
        RunStealWorkflow(prompt, GetEggMetadata(prompt), false)
    end
end)

--==============================================================
-- AUTO STEAL SEARCH LOOP
--==============================================================

task.spawn(function()
    while task.wait(TARGET_SCAN_INTERVAL) do
        if AUTO_STEAL and not StealBusy and os.clock() >= NextStealAllowedAt then
            local candidate, count = FindBestEggCandidate()
            if candidate then
                LastTargetDescription = string.format("%s · %s · %s", candidate.Label, candidate.Rarity, candidate.Biome)
                SetStatus("Eligible prompts scanned: " .. tostring(count))
                RunStealWorkflow(candidate.Prompt, candidate, true)
            else
                local filtersActive = HasAny(SelectedRarities) or HasAny(SelectedBiomes)
                LastTargetDescription = filtersActive and "No matching filtered egg currently visible" or "No matching egg currently visible"
                SetStatus("Eligible prompts scanned: 0")
                if AUTO_TREADMILL and CurrentMode == "Idle" then ReturnToTreadmill() end
            end
        end
    end
end)

--==============================================================
-- AUTO TREADMILL RETURN MONITOR
--==============================================================

task.spawn(function()
    local lastAirStarted = nil
    while task.wait(0.25) do
        if not AUTO_TREADMILL or StealBusy then lastAirStarted = nil; continue end
        if CurrentMode == "TreadmillTravel" or CurrentMode == "TreadmillTesting" or CurrentMode == "TreadmillReturn" then continue end
        local root, hum = Root(), Humanoid()
        if not root or not hum then continue end
        local target = (SavedTreadmill and SavedTreadmill.Parent and GetTreadmillStandPosition(SavedTreadmill)) or SavedTreadmillPosition
        if target then
            local horizontal = Vector3.new(root.Position.X - target.X, 0, root.Position.Z - target.Z).Magnitude
            local airborne = hum.FloorMaterial == Enum.Material.Air
            if airborne then lastAirStarted = lastAirStarted or os.clock() else lastAirStarted = nil end
            local jumped = lastAirStarted and (os.clock() - lastAirStarted >= 0.15)
            if horizontal > TREADMILL_RETURN_DISTANCE or jumped then
                if CurrentMode ~= "TreadmillReturn" then
                    Notify("Auto Treadmill", "You walked/jumped away. Returning to the saved treadmill...", 2, "warning")
                    ReturnToTreadmill()
                end
            elseif CurrentMode == "Idle" then
                ReturnToTreadmill()
            end
        elseif CurrentMode == "Idle" then
            StartTreadmillSearch()
        end
    end
end)

--==============================================================
-- AFK / RECONNECT / SMALLEST SERVER / AUTO EXECUTE
--==============================================================

local function SetAntiAFK(enabled)
    ANTI_AFK = enabled
    if AFKConnection then AFKConnection:Disconnect(); AFKConnection = nil end
    if enabled then
        AFKConnection = LocalPlayer.Idled:Connect(function()
            pcall(function()
                VirtualUser:CaptureController()
                VirtualUser:ClickButton2(Vector2.new(0, 0))
            end)
            Notify("Anti-AFK", "Prevented an idle timeout.", 1.5)
        end)
        Notify("Anti-AFK", "Enabled.", 2, "success")
    else
        Notify("Anti-AFK", "Disabled.", 2)
    end
end

local function HttpGetJson(url)
    local body
    if type(request) == "function" then
        local ok, response = pcall(function() return request({Url = url, Method = "GET"}) end)
        if ok and response then body = response.Body end
    end
    if not body then
        local ok, result = pcall(function() return game:HttpGet(url) end)
        if ok then body = result end
    end
    if not body then return nil end
    local ok, decoded = pcall(function() return HttpService:JSONDecode(body) end)
    return ok and decoded or nil
end

local function FindSmallestPublicServer()
    local placeId = game.PlaceId
    local bestServer, bestPlayers = nil, math.huge
    local cursor = nil
    local currentCount = #Players:GetPlayers()
    for page = 1, MAX_SERVER_PAGES do
        local url = "https://games.roblox.com/v1/games/" .. tostring(placeId) .. "/servers/Public?sortOrder=Asc&limit=100&excludeFullGames=true"
        if cursor and cursor ~= "" then url = url .. "&cursor=" .. HttpService:UrlEncode(cursor) end
        local data = HttpGetJson(url)
        if not data or type(data.data) ~= "table" then break end
        for _, server in ipairs(data.data) do
            if server.id and server.id ~= game.JobId and type(server.playing) == "number" and server.playing < (server.maxPlayers or math.huge) then
                if not bestServer or server.playing < bestPlayers then bestServer, bestPlayers = server, server.playing end
            end
        end
        cursor = data.nextPageCursor
        if not cursor or cursor == "" then break end
    end
    if bestServer then
        Notify("Server Finder", "Smallest server found: " .. tostring(bestPlayers) .. " players. Teleporting...", 3, "success")
        local ok, err = pcall(function() TeleportService:TeleportToPlaceInstance(placeId, bestServer.id, LocalPlayer) end)
        if not ok then EngineError("Server teleport failed: " .. tostring(err)) end
        return true
    end
    EngineError("Couldn't read public server list. HTTP requests or the server API may be blocked.")
    return false
end

TeleportService.TeleportInitFailed:Connect(function(player, result, errorMessage)
    if player ~= LocalPlayer or not AUTO_RECONNECT then return end
    ReconnectAttempts += 1
    if ReconnectAttempts > 3 then
        EngineError("Auto reconnect stopped after 3 failed attempts: " .. tostring(errorMessage))
        return
    end
    Notify("Auto Reconnect", "Teleport failed; retrying in 2 seconds...", 3, "warning")
    task.delay(2, function()
        if AUTO_RECONNECT then pcall(function() TeleportService:Teleport(game.PlaceId, LocalPlayer) end) end
    end)
end)

local function GetQueueOnTeleport()
    if type(queue_on_teleport) == "function" then return queue_on_teleport end
    if type(queueonteleport) == "function" then return queueonteleport end
    if type(syn) == "table" and type(syn.queue_on_teleport) == "function" then return syn.queue_on_teleport end
    return nil
end

local function QueueAutoExecute()
    local url = tostring(SCRIPT_RAW_URL or ""):gsub("%s+", "")
    if url == "" or not url:match("^https?://") then
        Notify("Auto Execute", "Enter your hosted raw .lua script URL first. The executor cannot auto-execute an unhosted local download.", 5, "warning")
        return false
    end
    local queue = GetQueueOnTeleport()
    if not queue then
        Notify("Auto Execute", "This executor has no queue-on-teleport API. Use its Auto Execute folder for startup runs.", 5, "warning")
        return false
    end
    local source = "loadstring(game:HttpGet(" .. string.format("%q", url) .. "))()"
    local ok, err = pcall(function() queue(source) end)
    if ok then Notify("Auto Execute", "Queued the hosted script for the next teleport.", 3, "success")
    else EngineError("Queue failed: " .. tostring(err)) end
    return ok
end

--==============================================================
-- UI CALLBACKS / FILTERS
--==============================================================

TreadmillSection:CreateToggle({
    Name = "Auto Treadmill", Flag = "AutoTreadmill", Default = false,
    Description = "Tests candidates for speed gain every 2 seconds; saves and returns to a working treadmill.",
    Callback = function(on)
        AUTO_TREADMILL = on
        if on then
            Notify("Auto Treadmill", "Enabled. Testing treadmills for real speed gain...", 3)
            if not StealBusy then StartTreadmillSearch() end
        else
            TreadmillToken += 1
            if CurrentMode:find("Treadmill") then CancelTween(); CurrentMode = "Idle"; RestoreCharacterState() end
            Notify("Auto Treadmill", "Disabled; no automatic return will run.", 2)
        end
        SetStatus()
    end,
})

AutoStealSection:CreateToggle({
    Name = "Auto Steal", Flag = "AutoSteal", Default = false,
    Description = "Searches the server for the highest-priority matching egg and runs the Lake Drop workflow.",
    Callback = function(on)
        AUTO_STEAL = on
        if on then
            SetupAllStealPrompts(true)
            Notify("Auto Steal", "Enabled. Empty filters = highest rarity/value currently visible.", 3, "success")
        else
            if StealBusy then
                StealJobToken += 1
                StealBusy = false
                CancelTween()
                RestoreCharacterState()
                CurrentMode = "Idle"
            end
            if not MANUAL_INSTANT_STEAL then SetupAllStealPrompts(false) end
            Notify("Auto Steal", "Disabled.", 2)
        end
        SetStatus()
    end,
})

AutoStealSection:CreateToggle({
    Name = "Manual Instant Steal", Flag = "ManualInstantSteal", Default = false,
    Description = "When enabled, activating a Steal prompt manually runs the same Lake Drop workflow.",
    Callback = function(on)
        MANUAL_INSTANT_STEAL = on
        if on then SetupAllStealPrompts(true) elseif not AUTO_STEAL then SetupAllStealPrompts(false) end
        Notify("Manual Instant Steal", on and "Enabled." or "Disabled.", 2)
    end,
})

local function SetSelection(target, selected)
    table.clear(target)
    if type(selected) == "table" then
        for _, item in ipairs(selected) do target[tostring(item)] = true end
    end
    SetStatus("Filters updated")
    if HasAny(SelectedRarities) or HasAny(SelectedBiomes) then
        Notify("Filters", "Filters are active. Eggs without readable matching metadata will be skipped.", 2)
    else
        Notify("Filters", "No filters selected: Auto Steal will prioritize the most valuable detectable egg.", 2)
    end
end

RarityFilterSection:CreateDropdown({
    Name = "Allowed Rarities", Flag = "AllowedRarities", Multi = true, SelectAll = true,
    Options = RARITIES, Default = {}, Search = true,
    Description = "Leave empty to use all rarities and auto-pick the highest-value candidate.",
    Callback = function(selected) SetSelection(SelectedRarities, selected) end,
})

BiomeFilterSection:CreateDropdown({
    Name = "Allowed Biomes", Flag = "AllowedBiomes", Multi = true, SelectAll = true,
    Options = BIOMES, Default = {}, Search = true,
    Description = "Select one or more biomes. With Divine + Eternal and two biomes selected, only those matches qualify.",
    Callback = function(selected) SetSelection(SelectedBiomes, selected) end,
})

GeneralSettingsSection:CreateToggle({
    Name = "Auto Save Config", Flag = "AutoSaveConfig", Default = true,
    Description = "Uses Rage Hub's built-in autosave config for UI toggles and filters.",
    Callback = function(on)
        AUTO_SAVE_CONFIG = on
        Window.AutoSaveName = on and "autosave" or nil
        if on then pcall(function() Window:SaveConfig("autosave") end) end
        Notify("Settings", on and "Auto-save enabled." or "Auto-save disabled.", 2)
    end,
})

GeneralSettingsSection:CreateButton({
    Name = "Save Config Now", ButtonText = "Save",
    Callback = function()
        local ok, err = pcall(function() Window:SaveConfig("autosave") end)
        if ok then Notify("Settings", "Config saved.", 2, "success") else EngineError("Config save failed: " .. tostring(err)) end
    end,
})

GeneralSettingsSection:CreateToggle({
    Name = "Anti AFK", Flag = "AntiAFK", Default = false,
    Description = "Uses the executor-supported VirtualUser idle callback where available.",
    Callback = SetAntiAFK,
})

GeneralSettingsSection:CreateToggle({
    Name = "Auto Reconnect", Flag = "AutoReconnect", Default = false,
    Description = "Retries failed teleports. A client script cannot recover from every server disconnect by itself.",
    Callback = function(on)
        AUTO_RECONNECT = on
        ReconnectAttempts = 0
        Notify("Auto Reconnect", on and "Enabled for failed teleport attempts." or "Disabled.", 2)
    end,
})

ServerSettingsSection:CreateButton({
    Name = "Find Smallest Server", ButtonText = "Find",
    Callback = function() task.spawn(FindSmallestPublicServer) end,
})

ServerSettingsSection:CreateToggle({
    Name = "Auto Find Smallest Server", Flag = "AutoSmallestServer", Default = false,
    Description = "Checks every 3 minutes and tries a smaller public server when idle.",
    Callback = function(on)
        AUTO_SMALLEST_SERVER = on
        Notify("Server Finder", on and "Automatic small-server search enabled." or "Automatic server search disabled.", 2)
    end,
})

task.spawn(function()
    while task.wait(180) do
        if AUTO_SMALLEST_SERVER and not StealBusy then
            task.spawn(FindSmallestPublicServer)
        end
    end
end)

ExecuteSettingsSection:CreateInput({
    Name = "Hosted Raw Script URL", Flag = "HostedRawScriptURL", Default = "", Width = 300,
    Placeholder = "https://raw.githubusercontent.com/user/repo/main/script.lua", Clearable = true,
    Description = "Optional: host THIS script first, then paste its raw URL here.",
    Callback = function(value)
        SCRIPT_RAW_URL = tostring(value or "")
        if AUTO_EXECUTE_AFTER_TELEPORT and SCRIPT_RAW_URL ~= "" then
            task.defer(QueueAutoExecute)
        end
    end,
})

ExecuteSettingsSection:CreateToggle({
    Name = "Auto Execute After Teleport", Flag = "AutoExecuteAfterTeleport", Default = false,
    Description = "Queues the hosted raw script on teleport if the executor supports queue_on_teleport.",
    Callback = function(on)
        AUTO_EXECUTE_AFTER_TELEPORT = on
        if on then
            QueueAutoExecute()
        else
            Notify("Auto Execute", "Disabled.", 2)
        end
    end,
})

ExecuteSettingsSection:CreateButton({
    Name = "Queue Script For Next Teleport", ButtonText = "Queue",
    Callback = QueueAutoExecute,
})

ExecuteSettingsSection:CreateParagraph({
    Title = "Startup Auto-Execute",
    Content = "For automatic execution every time you join Roblox, use your executor's own Auto Execute/autoexec feature. This in-game script cannot enable that executor setting itself.",
})

-- Only the custom Settings tab above is used. Do not create the library's
-- built-in Settings tab, which can expose extra developer-module controls.
-- Load saved UI/filter options only; do not request module restoration.
pcall(function() Window:LoadConfig("autosave", { RestoreModules = false }) end)

--==============================================================
-- RESPAWN HANDLING
--==============================================================

LocalPlayer.CharacterAdded:Connect(function()
    CancelTween()
    OriginalWalkSpeed, OriginalAutoRotate = nil, nil
    if StealBusy then
        StealJobToken += 1
        StealBusy = false
    end
    CurrentMode = "Idle"
    task.wait(1.25)
    if AUTO_STEAL or MANUAL_INSTANT_STEAL then SetupAllStealPrompts(true) end
    if AUTO_STEAL then
        Notify("Auto Steal", "Respawn detected. Resuming egg search.", 2)
    elseif AUTO_TREADMILL then
        Notify("Auto Treadmill", "Respawn detected. Returning to saved treadmill.", 2)
        ReturnToTreadmill()
    end
    SetStatus()
end)

Notify("Rage Hub", "Auto Steal + filters loaded. Empty filters prioritize the highest detectable rarity/value.", 4, "success")
SetStatus()
