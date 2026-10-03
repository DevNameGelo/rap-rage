--[[
    RGC Egg Automation
    Auto Pick Up + Egg Filter + Radar + Plot Return
]]

--------------------------------------------------
-- SERVICES
--------------------------------------------------

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ProximityPromptService = game:GetService("ProximityPromptService")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")

local LocalPlayer = Players.LocalPlayer

--------------------------------------------------
-- RAYFIELD
--------------------------------------------------

local Rayfield

local ok, result = pcall(function()
    return loadstring(
        game:HttpGet("https://sirius.menu/rayfield")
    )()
end)

if not ok or not result then
    warn("[RGC] Rayfield failed:", result)
    return
end

Rayfield = result

--------------------------------------------------
-- REMOTES
--------------------------------------------------

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local GameRemotes = Remotes:WaitForChild("Game")

local EggPickup = GameRemotes:WaitForChild("EggPickup")
local RequestPlotEggs = GameRemotes:WaitForChild("RequestPlotEggs")
local ActivateRadar = GameRemotes:WaitForChild("ActivateRadar")

local PlotFolder = GameRemotes:FindFirstChild("Plot")
local PlotUpgrades = PlotFolder and PlotFolder:FindFirstChild("Upgrades")

local PlacePet = GameRemotes:FindFirstChild("PlacePet")
local EggPlaced = GameRemotes:FindFirstChild("EggPlaced")

--------------------------------------------------
-- WORLD
--------------------------------------------------

local RenderedEggs = workspace:FindFirstChild("RenderedEggs")
local EggSpawns = workspace:FindFirstChild("EggSpawns")
local Plots = workspace:FindFirstChild("Plots")

--------------------------------------------------
-- SETTINGS
--------------------------------------------------

local Settings = {
    AutoPickUp = false,
    AutoRadar = false,
    AutoPlaceBestPets = false,
    AutoFeedPets = false,
    AutoReconnect = false,

    SelectedEggs = {}
}

--------------------------------------------------
-- EGG LIST
--------------------------------------------------

local EggList = {
    "White Egg",
    "Easter Egg",
    "Stone Egg",
    "Leaf Egg",
    "Mushroom Egg",
    "Flower Egg",
    "Slime Egg",
    "Ice Egg",
    "Glass Egg",
    "Golden Egg",
    "Crystal Egg",
    "Magma Egg",
    "Cherub Egg",
    "Black Hole Egg",
    "Solaris Egg",
    "Volcanic Egg"
}

--------------------------------------------------
-- DEFAULT FILTER
--------------------------------------------------

for _, eggName in ipairs(EggList) do
    Settings.SelectedEggs[eggName] = false
end

--------------------------------------------------
-- STATE
--------------------------------------------------

local Processing = false
local CurrentEgg = nil
local LastProcessedKey = nil

--------------------------------------------------
-- UTILITIES
--------------------------------------------------

local function IsUUID(value)
    if typeof(value) ~= "string" then
        return false
    end

    return value:match(
        "^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$"
    ) ~= nil
end


local function GetPosition(object)
    if not object then
        return nil
    end

    if object:IsA("BasePart") then
        return object.Position
    end

    if object:IsA("Model") then
        local ok, pivot = pcall(function()
            return object:GetPivot()
        end)

        if ok and pivot then
            return pivot.Position
        end
    end

    for _, descendant in ipairs(object:GetDescendants()) do
        if descendant:IsA("BasePart") then
            return descendant.Position
        end
    end

    return nil
end


local function GetEggName(object)
    if not object then
        return nil
    end

    -- Object name
    for _, eggName in ipairs(EggList) do
        if string.find(
            string.lower(object.Name),
            string.lower(eggName),
            1,
            true
        ) then
            return eggName
        end
    end

    -- Attributes
    for _, eggName in ipairs(EggList) do
        local value = object:GetAttribute("EggName")

        if value == eggName then
            return eggName
        end
    end

    -- Descendants
    for _, descendant in ipairs(object:GetDescendants()) do
        for _, eggName in ipairs(EggList) do

            if string.find(
                string.lower(descendant.Name),
                string.lower(eggName),
                1,
                true
            ) then
                return eggName
            end

            if descendant:IsA("StringValue") then
                if descendant.Value == eggName then
                    return eggName
                end
            end
        end
    end

    return nil
end


local function FindUUID(object)
    if not object then
        return nil
    end

    -- Object attributes
    for _, attributeName in ipairs({
        "EggKey",
        "EggUUID",
        "UUID",
        "Id",
        "ID",
        "Key"
    }) do

        local value = object:GetAttribute(attributeName)

        if IsUUID(value) then
            return value
        end
    end

    -- Object name
    if IsUUID(object.Name) then
        return object.Name
    end

    -- Descendants
    for _, descendant in ipairs(object:GetDescendants()) do

        if IsUUID(descendant.Name) then
            return descendant.Name
        end

        if descendant:IsA("StringValue") then
            if IsUUID(descendant.Value) then
                return descendant.Value
            end
        end

        for _, attributeName in ipairs({
            "EggKey",
            "EggUUID",
            "UUID",
            "Id",
            "ID",
            "Key"
        }) do

            local value = descendant:GetAttribute(attributeName)

            if IsUUID(value) then
                return value
            end
        end
    end

    return nil
end

--------------------------------------------------
-- PLOT
--------------------------------------------------

local function FindOwnPlot()

    if not Plots then
        return nil
    end

    for _, plot in ipairs(Plots:GetChildren()) do

        -- Attributes
        for _, attributeName in ipairs({
            "Owner",
            "OwnerName",
            "Player",
            "PlayerName",
            "UserId",
            "OwnerUserId"
        }) do

            local value = plot:GetAttribute(attributeName)

            if value ~= nil then

                if value == LocalPlayer.Name
                    or value == LocalPlayer.DisplayName
                    or tostring(value) == tostring(LocalPlayer.UserId)
                then
                    return plot
                end
            end
        end

        -- Values
        for _, descendant in ipairs(plot:GetDescendants()) do

            if descendant:IsA("StringValue") then

                if descendant.Value == LocalPlayer.Name
                    or descendant.Value == LocalPlayer.DisplayName
                then
                    return plot
                end
            end

            if descendant:IsA("IntValue")
                or descendant:IsA("NumberValue")
            then

                if tostring(descendant.Value) ==
                    tostring(LocalPlayer.UserId)
                then
                    return plot
                end
            end

            if descendant:IsA("ObjectValue") then

                if descendant.Value == LocalPlayer then
                    return plot
                end
            end
        end
    end

    return nil
end


local function GetPlotCFrame(plot)

    if not plot then
        return nil
    end

    local names = {
        "Spawn",
        "SpawnLocation",
        "PlotSpawn",
        "PlayerSpawn",
        "Base",
        "Home",
        "Claim",
        "ClaimPoint",
        "OwnerSpawn"
    }

    for _, name in ipairs(names) do

        local object = plot:FindFirstChild(name, true)

        if object then

            if object:IsA("BasePart") then
                return object.CFrame
            end

            if object:IsA("Model") then
                local ok, cf = pcall(function()
                    return object:GetPivot()
                end)

                if ok then
                    return cf
                end
            end
        end
    end

    if plot:IsA("Model") then
        local ok, cf = pcall(function()
            return plot:GetPivot()
        end)

        if ok then
            return cf
        end
    end

    return nil
end


local function ReturnToPlot()

    local character = LocalPlayer.Character

    if not character then
        return false
    end

    local root = character:FindFirstChild("HumanoidRootPart")

    if not root then
        return false
    end

    local plot = FindOwnPlot()

    if not plot then
        warn("[RGC] Own plot not found")
        return false
    end

    local cf = GetPlotCFrame(plot)

    if not cf then
        warn("[RGC] Plot position not found")
        return false
    end

    root.CFrame = cf + Vector3.new(0, 3, 0)

    return true
end

--------------------------------------------------
-- EGG SEARCH
--------------------------------------------------

local function GetEggCandidates()

    local candidates = {}

    if RenderedEggs then

        for _, object in ipairs(RenderedEggs:GetChildren()) do
            table.insert(candidates, object)
        end
    end

    if EggSpawns then

        for _, object in ipairs(EggSpawns:GetChildren()) do
            table.insert(candidates, object)
        end
    end

    return candidates
end


local function FindEggFromPrompt(prompt)

    local promptPosition = GetPosition(prompt.Parent)

    if not promptPosition then
        return nil
    end

    local closest = nil
    local closestDistance = math.huge

    for _, object in ipairs(GetEggCandidates()) do

        local eggName = GetEggName(object)

        if eggName and Settings.SelectedEggs[eggName] then

            local position = GetPosition(object)

            if position then

                local distance =
                    (position - promptPosition).Magnitude

                if distance < closestDistance then

                    closestDistance = distance
                    closest = object
                end
            end
        end
    end

    return closest
end

--------------------------------------------------
-- TELEPORT TO EGG
--------------------------------------------------

local function TeleportToEgg(object)

    local character = LocalPlayer.Character

    if not character then
        return false
    end

    local root =
        character:FindFirstChild("HumanoidRootPart")

    if not root then
        return false
    end

    local position = GetPosition(object)

    if not position then
        return false
    end

    root.CFrame =
        CFrame.new(position + Vector3.new(0, 3, 0))

    return true
end

--------------------------------------------------
-- PROMPT CHECK
--------------------------------------------------

local function IsEggPrompt(prompt)

    if not prompt then
        return false
    end

    local text = string.lower(
        tostring(prompt.ActionText)
        .. " "
        .. tostring(prompt.ObjectText)
        .. " "
        .. tostring(prompt.Name)
    )

    if string.find(text, "egg", 1, true) then
        return true
    end

    local parent = prompt.Parent

    for _ = 1, 6 do

        if not parent then
            break
        end

        if string.find(
            string.lower(parent.Name),
            "egg",
            1,
            true
        ) then
            return true
        end

        parent = parent.Parent
    end

    return false
end

--------------------------------------------------
-- PROCESS EGG
--------------------------------------------------

local function ProcessEgg(prompt)

    -- IMPORTANT:
    -- This is the first check.
    -- If Auto Pick Up is OFF, NOTHING happens.
    if not Settings.AutoPickUp then
        return
    end

    if Processing then
        return
    end

    if not IsEggPrompt(prompt) then
        return
    end

    local egg = FindEggFromPrompt(prompt)

    if not egg then
        return
    end

    local eggName = GetEggName(egg)

    if not eggName then
        return
    end

    if not Settings.SelectedEggs[eggName] then
        return
    end

    local uuid = FindUUID(egg)

    if not uuid then

        -- Refresh the game's egg state.
        pcall(function()
            RequestPlotEggs:FireServer(false)
        end)

        task.wait(0.1)

        uuid = FindUUID(egg)
    end

    if not uuid then
        warn(
            "[RGC] Selected egg detected but UUID was not found:",
            eggName
        )
        return
    end

    Processing = true
    CurrentEgg = egg
    LastProcessedKey = uuid

    --------------------------------------------------
    -- DOUBLE CHECK AUTO TOGGLE
    --------------------------------------------------

    if not Settings.AutoPickUp then
        Processing = false
        CurrentEgg = nil
        return
    end

    --------------------------------------------------
    -- GO TO EGG
    --------------------------------------------------

    TeleportToEgg(egg)

    task.wait(0.15)

    --------------------------------------------------
    -- PICK UP
    --------------------------------------------------

    if Settings.AutoPickUp then

        pcall(function()
            EggPickup:FireServer(uuid)
        end)
    end

    task.wait(0.15)

    --------------------------------------------------
    -- RETURN TO PLOT
    --------------------------------------------------

    -- IMPORTANT:
    -- Check AGAIN before teleporting.
    -- Turning Auto Pick Up OFF during pickup
    -- now prevents the return teleport.
    if Settings.AutoPickUp then
        ReturnToPlot()
    end

    CurrentEgg = nil
    Processing = false
end

--------------------------------------------------
-- PROXIMITY PROMPT
--------------------------------------------------

ProximityPromptService.PromptTriggered:Connect(
    function(prompt, player)

        if player and player ~= LocalPlayer then
            return
        end

        -- Critical fix:
        -- OFF means no processing whatsoever.
        if not Settings.AutoPickUp then
            return
        end

        task.spawn(function()
            ProcessEgg(prompt)
        end)
    end
)

--------------------------------------------------
-- RADAR
--------------------------------------------------

local function EnableRadar()

    if not ActivateRadar then
        return
    end

    pcall(function()
        ActivateRadar:FireServer()
    end)
end

--------------------------------------------------
-- PLOT UPGRADES
--------------------------------------------------

local function UpgradePlot()

    if not PlotUpgrades then
        return
    end

    pcall(function()
        PlotUpgrades:FireServer()
    end)
end

--------------------------------------------------
-- VOLCANO DIP
--------------------------------------------------

local function VolcanoDip()

    local packages = ReplicatedStorage:FindFirstChild("packages")

    if not packages then
        return
    end

    local net = packages:FindFirstChild("Net")

    if not net then
        return
    end

    local remote = net:FindFirstChild("RE/VolcanoDip")

    if remote then

        pcall(function()
            remote:FireServer()
        end)
    end
end

--------------------------------------------------
-- UI
--------------------------------------------------

local Window = Rayfield:CreateWindow({
    Name = "RGC Egg Automation",
    LoadingTitle = "RGC Egg Automation",
    LoadingSubtitle = "Egg Collector",
    ConfigurationSaving = {
        Enabled = true,
        FolderName = "RGC_EggAutomation",
        FileName = "Config"
    }
})

--------------------------------------------------
-- MAIN TAB
--------------------------------------------------

local MainTab = Window:CreateTab(
    "Automation",
    4483362458
)

MainTab:CreateToggle({
    Name = "Auto Pick Up",
    CurrentValue = false,

    Callback = function(value)

        Settings.AutoPickUp = value

        if value then
            Rayfield:Notify({
                Title = "Auto Pick Up",
                Content = "Enabled",
                Duration = 2
            })
        else

            -- Immediately cancel processing state.
            Processing = false
            CurrentEgg = nil

            Rayfield:Notify({
                Title = "Auto Pick Up",
                Content = "Disabled",
                Duration = 2
            })
        end
    end
})

MainTab:CreateToggle({
    Name = "Auto Radar",
    CurrentValue = false,

    Callback = function(value)

        Settings.AutoRadar = value

        if value then
            EnableRadar()
        end
    end
})

MainTab:CreateToggle({
    Name = "Auto Plot Upgrade",
    CurrentValue = false,

    Callback = function(value)

        if value then
            UpgradePlot()
        end
    end
})

MainTab:CreateButton({
    Name = "Activate Radar",
    Callback = function()
        EnableRadar()
    end
})

--------------------------------------------------
-- EGG FILTER
--------------------------------------------------

local FilterTab = Window:CreateTab(
    "Egg Filter",
    4483362458
)

FilterTab:CreateLabel(
    "Select which eggs Auto Pick Up can collect."
)

for _, eggName in ipairs(EggList) do

    FilterTab:CreateToggle({
        Name = eggName,
        CurrentValue = false,

        Callback = function(value)
            Settings.SelectedEggs[eggName] = value
        end
    })
end

--------------------------------------------------
-- PET TAB
--------------------------------------------------

local PetTab = Window:CreateTab(
    "Pets",
    4483362458
)

PetTab:CreateToggle({
    Name = "Auto Place Best Pets",
    CurrentValue = false,

    Callback = function(value)

        Settings.AutoPlaceBestPets = value

        -- Actual placement logic intentionally isn't
        -- guessed because the supplied PlacePet remote
        -- doesn't reveal its required pet-selection data.
        if value then
            Rayfield:Notify({
                Title = "Auto Place Pets",
                Content = "Enabled — waiting for placement data",
                Duration = 3
            })
        end
    end
})

PetTab:CreateToggle({
    Name = "Auto Feed Pets",
    CurrentValue = false,

    Callback = function(value)

        Settings.AutoFeedPets = value

        if value then
            Rayfield:Notify({
                Title = "Auto Feed",
                Content = "Enabled — feed remote not yet identified",
                Duration = 3
            })
        end
    end
})

--------------------------------------------------
-- VOLCANO TAB
--------------------------------------------------

local VolcanoTab = Window:CreateTab(
    "Volcano",
    4483362458
)

VolcanoTab:CreateButton({
    Name = "Volcano Dip",
    Callback = function()
        VolcanoDip()
    end
})

--------------------------------------------------
-- SETTINGS
--------------------------------------------------

local SettingsTab = Window:CreateTab(
    "Settings",
    4483362458
)

SettingsTab:CreateToggle({
    Name = "Auto Reconnect",
    CurrentValue = false,

    Callback = function(value)
        Settings.AutoReconnect = value
    end
})

SettingsTab:CreateButton({
    Name = "Save Config",
    Callback = function()

        pcall(function()
            Rayfield:SaveConfiguration()
        end)

        Rayfield:Notify({
            Title = "Configuration",
            Content = "Configuration saved.",
            Duration = 2
        })
    end
})

--------------------------------------------------
-- AUTO RECONNECT
--------------------------------------------------

LocalPlayer.OnTeleport:Connect(function(
    teleportState
)

    if not Settings.AutoReconnect then
        return
    end

    if teleportState == Enum.TeleportState.Failed then

        task.wait(3)

        pcall(function()
            TeleportService:Teleport(
                game.PlaceId,
                LocalPlayer
            )
        end)
    end
end)

--------------------------------------------------
-- LOAD
--------------------------------------------------

Rayfield:Notify({
    Title = "RGC Egg Automation",
    Content = "Loaded successfully.",
    Duration = 3
})
