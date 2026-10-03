--//========================================================//
--//                 EGG AUTO RETURN                        //
--//                    RAYFIELD                            //
--//========================================================//

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ProximityPromptService = game:GetService("ProximityPromptService")

local LocalPlayer = Players.LocalPlayer

--==========================================================--
-- RAYFIELD
--==========================================================--

local Rayfield

local RayfieldSuccess, RayfieldResult = pcall(function()
    return loadstring(game:HttpGet(
        "https://sirius.menu/rayfield"
    ))()
end)

if not RayfieldSuccess then
    warn("[Egg Auto] Rayfield failed to load:", RayfieldResult)
    return
end

Rayfield = RayfieldResult

local Window = Rayfield:CreateWindow({
    Name = "Egg Auto Return",
    LoadingTitle = "Egg Auto Return",
    LoadingSubtitle = "Loading...",
    ConfigurationSaving = {
        Enabled = false
    },
    Discord = {
        Enabled = false
    },
    KeySystem = false
})

local MainTab = Window:CreateTab(
    "Egg",
    4483362458
)

--==========================================================--
-- REMOTES
--==========================================================--

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local GameRemotes = Remotes:WaitForChild("Game")

local RequestPlotEggs = GameRemotes:WaitForChild(
    "RequestPlotEggs"
)

local EggPickup = GameRemotes:WaitForChild(
    "EggPickup"
)

--==========================================================--
-- WORLD
--==========================================================--

local function GetFolder(Name)
    return workspace:FindFirstChild(Name)
end

--==========================================================--
-- VARIABLES
--==========================================================--

local AutoEgg = false
local Processing = false
local LastPrompt = nil
local LastEgg = nil

--==========================================================--
-- UUID
--==========================================================--

local function IsUUID(Value)

    if Value == nil then
        return false
    end

    local String = tostring(Value)

    return String:match(
        "^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$"
    ) ~= nil
end

--==========================================================--
-- SEARCH UUID
--==========================================================--

local function SearchUUID(Object)

    if not Object then
        return nil
    end

    -- Object name
    if IsUUID(Object.Name) then
        return Object.Name
    end

    -- Attributes
    for Name, Value in pairs(
        Object:GetAttributes()
    ) do

        if IsUUID(Value) then
            return tostring(Value)
        end

        if IsUUID(Name) then
            return tostring(Name)
        end
    end

    -- Children / descendants
    for _, Child in ipairs(
        Object:GetDescendants()
    ) do

        if IsUUID(Child.Name) then
            return Child.Name
        end

        if Child:IsA("StringValue")
            or Child:IsA("IntValue")
            or Child:IsA("NumberValue") then

            if IsUUID(Child.Value) then
                return tostring(Child.Value)
            end
        end

        for Name, Value in pairs(
            Child:GetAttributes()
        ) do

            if IsUUID(Value) then
                return tostring(Value)
            end

            if IsUUID(Name) then
                return tostring(Name)
            end
        end
    end

    return nil
end

--==========================================================--
-- POSITION
--==========================================================--

local function GetPosition(Object)

    if not Object then
        return nil
    end

    if Object:IsA("BasePart") then
        return Object.Position
    end

    if Object:IsA("Model") then
        return Object:GetPivot().Position
    end

    for _, Object2 in ipairs(
        Object:GetDescendants()
    ) do

        if Object2:IsA("BasePart") then
            return Object2.Position
        end
    end

    return nil
end

--==========================================================--
-- NEAREST EGG
--==========================================================--

local function FindNearestEgg(Prompt)

    local Character = LocalPlayer.Character

    if not Character then
        return nil
    end

    local Root = Character:FindFirstChild(
        "HumanoidRootPart"
    )

    if not Root then
        return nil
    end

    local PromptPosition = GetPosition(Prompt)

    local Closest = nil
    local ClosestDistance = math.huge

    local Containers = {
        GetFolder("RenderedEggs"),
        GetFolder("EggSpawns")
    }

    for _, Container in ipairs(Containers) do

        if Container then

            for _, Egg in ipairs(
                Container:GetChildren()
            ) do

                local Position = GetPosition(Egg)

                if Position then

                    local Distance

                    if PromptPosition then
                        Distance = (
                            Position - PromptPosition
                        ).Magnitude
                    else
                        Distance = (
                            Position - Root.Position
                        ).Magnitude
                    end

                    if Distance < ClosestDistance then

                        ClosestDistance = Distance
                        Closest = Egg

                    end
                end
            end
        end
    end

    return Closest
end

--==========================================================--
-- FIND EGG UUID
--==========================================================--

local function FindEggUUID(Prompt)

    -- Prompt itself
    local UUID = SearchUUID(Prompt)

    if UUID then
        return UUID
    end

    -- Nearby egg
    local Egg = FindNearestEgg(Prompt)

    if Egg then

        LastEgg = Egg

        UUID = SearchUUID(Egg)

        if UUID then
            return UUID
        end
    end

    -- RenderedEggs
    local Rendered = GetFolder(
        "RenderedEggs"
    )

    if Rendered then

        for _, Egg in ipairs(
            Rendered:GetChildren()
        ) do

            UUID = SearchUUID(Egg)

            if UUID then
                return UUID
            end
        end
    end

    -- EggSpawns
    local Spawns = GetFolder(
        "EggSpawns"
    )

    if Spawns then

        for _, Egg in ipairs(
            Spawns:GetChildren()
        ) do

            UUID = SearchUUID(Egg)

            if UUID then
                return UUID
            end
        end
    end

    return nil
end

--==========================================================--
-- FIND OWN PLOT
--==========================================================--

local function FindOwnPlot()

    local Plots = GetFolder("Plots")

    if not Plots then
        return nil
    end

    local PlayerName = LocalPlayer.Name
    local DisplayName = LocalPlayer.DisplayName
    local UserId = tostring(
        LocalPlayer.UserId
    )

    for _, Plot in ipairs(
        Plots:GetChildren()
    ) do

        -- Attributes
        for Name, Value in pairs(
            Plot:GetAttributes()
        ) do

            local String = tostring(Value)

            if String == PlayerName
                or String == DisplayName
                or String == UserId then

                return Plot
            end
        end

        -- Values
        for _, Object in ipairs(
            Plot:GetDescendants()
        ) do

            if Object:IsA("StringValue") then

                local Value = tostring(
                    Object.Value
                )

                if Value == PlayerName
                    or Value == DisplayName
                    or Value == UserId then

                    return Plot
                end
            end

            if Object:IsA("IntValue")
                or Object:IsA("NumberValue") then

                if tostring(Object.Value)
                    == UserId then

                    return Plot
                end
            end

            if Object:IsA("ObjectValue")
                and Object.Value == LocalPlayer then

                return Plot
            end
        end
    end

    return nil
end

--==========================================================--
-- GET PLOT CFRAME
--==========================================================--

local function GetPlotCFrame(Plot)

    if not Plot then
        return nil
    end

    if Plot:IsA("BasePart") then

        return Plot.CFrame
            + Vector3.new(0, 5, 0)
    end

    local Names = {
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

    for _, Name in ipairs(Names) do

        local Object = Plot:FindFirstChild(
            Name,
            true
        )

        if Object
            and Object:IsA("BasePart") then

            return Object.CFrame
                + Vector3.new(0, 5, 0)
        end
    end

    local Success, Pivot = pcall(function()
        return Plot:GetPivot()
    end)

    if Success and Pivot then

        return Pivot
            + Vector3.new(0, 5, 0)
    end

    for _, Object in ipairs(
        Plot:GetDescendants()
    ) do

        if Object:IsA("BasePart") then

            return Object.CFrame
                + Vector3.new(0, 5, 0)
        end
    end

    return nil
end

--==========================================================--
-- TELEPORT TO PLOT
--==========================================================--

local function ReturnToPlot()

    local Character = LocalPlayer.Character

    if not Character then
        return false
    end

    local Root = Character:FindFirstChild(
        "HumanoidRootPart"
    )

    if not Root then
        return false
    end

    local Plot = FindOwnPlot()

    if not Plot then

        warn(
            "[Egg Auto] Plot not found"
        )

        return false
    end

    local CFrame = GetPlotCFrame(Plot)

    if not CFrame then
        return false
    end

    Root.CFrame = CFrame

    return true
end

--==========================================================--
-- EGG CHECK
--==========================================================--

local function IsEggPrompt(Prompt)

    if not Prompt then
        return false
    end

    local Text = string.lower(
        tostring(Prompt.Name)
        .. " "
        .. tostring(Prompt.ActionText)
        .. " "
        .. tostring(Prompt.ObjectText)
    )

    if string.find(
        Text,
        "egg",
        1,
        true
    ) then

        return true
    end

    local Parent = Prompt.Parent

    for _ = 1, 6 do

        if not Parent then
            break
        end

        if string.find(
            string.lower(Parent.Name),
            "egg",
            1,
            true
        ) then

            return true
        end

        Parent = Parent.Parent
    end

    return false
end

--==========================================================--
-- PROCESS EGG
--==========================================================--

local function ProcessEgg(Prompt)

    if not AutoEgg then
        return
    end

    if Processing then
        return
    end

    if not IsEggPrompt(Prompt) then
        return
    end

    Processing = true
    LastPrompt = Prompt

    print(
        "[Egg Auto] Egg detected:",
        Prompt:GetFullName()
    )

    -- Refresh egg information
    pcall(function()
        RequestPlotEggs:FireServer(false)
    end)

    task.wait(0.1)

    local UUID = FindEggUUID(Prompt)

    if not UUID then

        warn(
            "[Egg Auto] UUID not found."
        )

        Rayfield:Notify({
            Title = "Egg Auto",
            Content = "Egg detected, but UUID was not found.",
            Duration = 3
        })

        Processing = false
        return
    end

    print(
        "[Egg Auto] UUID:",
        UUID
    )

    -- Pickup
    local Success, Error = pcall(function()

        EggPickup:FireServer(UUID)

    end)

    if not Success then

        warn(
            "[Egg Auto] Pickup error:",
            Error
        )

        Processing = false
        return
    end

    print(
        "[Egg Auto] EggPickup fired."
    )

    task.wait(0.05)

    -- Return
    if ReturnToPlot() then

        Rayfield:Notify({
            Title = "Egg Auto",
            Content = "Egg picked up and returned to your plot.",
            Duration = 2
        })

    else

        Rayfield:Notify({
            Title = "Egg Auto",
            Content = "Pickup sent, but plot teleport failed.",
            Duration = 3
        })
    end

    task.wait(0.15)

    Processing = false
end

--==========================================================--
-- PROXIMITY PROMPT
--==========================================================--

ProximityPromptService.PromptTriggered:Connect(
    function(Prompt, Player)

        if Player
            and Player ~= LocalPlayer then

            return
        end

        task.spawn(function()
            ProcessEgg(Prompt)
        end)
    end
)

--==========================================================--
-- UI
--==========================================================--

MainTab:CreateToggle({
    Name = "Auto Egg Return",
    CurrentValue = false,

    Callback = function(Value)

        AutoEgg = Value

        Rayfield:Notify({
            Title = "Egg Auto",
            Content = Value
                and "Enabled"
                or "Disabled",
            Duration = 2
        })
    end
})

MainTab:CreateButton({
    Name = "Teleport To My Plot",

    Callback = function()

        if ReturnToPlot() then

            Rayfield:Notify({
                Title = "Plot",
                Content = "Teleported to your plot.",
                Duration = 2
            })

        else

            Rayfield:Notify({
                Title = "Plot",
                Content = "Could not find your plot.",
                Duration = 3
            })
        end
    end
})

MainTab:CreateButton({
    Name = "Request Plot Eggs",

    Callback = function()

        local Success = pcall(function()
            RequestPlotEggs:FireServer(false)
        end)

        Rayfield:Notify({
            Title = "Eggs",
            Content = Success
                and "Egg request sent."
                or "Request failed.",
            Duration = 2
        })
    end
})

--==========================================================--
-- STATUS
--==========================================================--

MainTab:CreateParagraph({
    Title = "Status",
    Content =
        "Detects egg prompts → searches RenderedEggs/EggSpawns → sends EggPickup → returns to your plot."
})

--==========================================================--
-- START
--==========================================================--

Rayfield:Notify({
    Title = "Egg Auto Return",
    Content = "Loaded successfully.",
    Duration = 3
})

print("[Egg Auto] Loaded")
print("[Egg Auto] Player:", LocalPlayer.Name)
print("[Egg Auto] Plots:", GetFolder("Plots"))
print("[Egg Auto] EggSpawns:", GetFolder("EggSpawns"))
print("[Egg Auto] RenderedEggs:", GetFolder("RenderedEggs"))
