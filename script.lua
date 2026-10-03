--//========================================================//
--//                 EGG AUTO RETURN                        //
--//                 Rayfield Edition                       //
--//========================================================//

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ProximityPromptService = game:GetService("ProximityPromptService")

local LocalPlayer = Players.LocalPlayer

--//========================================================//
--// REMOTES
--//========================================================//

local GameRemotes = ReplicatedStorage
    :WaitForChild("Remotes")
    :WaitForChild("Game")

local RequestPlotEggs = GameRemotes:WaitForChild("RequestPlotEggs")
local EggPickup = GameRemotes:WaitForChild("EggPickup")
local EggArrivalClaim = GameRemotes:WaitForChild("EggArrivalClaim")

--//========================================================//
--// WORLD FOLDERS
--//========================================================//

local EggSpawns = workspace:FindFirstChild("EggSpawns")
local RenderedEggs = workspace:FindFirstChild("RenderedEggs")
local Plots = workspace:FindFirstChild("Plots")

--//========================================================//
--// RAYFIELD
--//========================================================//

local Rayfield = loadstring(
    game:HttpGet("https://sirius.menu/rayfield")
)()

local Window = Rayfield:CreateWindow({
    Name = "Egg Auto Return",
    LoadingTitle = "Egg Auto Return",
    LoadingSubtitle = "RGC",
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

--//========================================================//
--// STATE
--//========================================================//

local AutoEgg = false
local Processing = false
local LastPrompt = nil
local LastEgg = nil

--//========================================================//
--// UUID CHECK
--//========================================================//

local function IsUUID(Value)

    if Value == nil then
        return false
    end

    Value = tostring(Value)

    return Value:match(
        "^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$"
    ) ~= nil
end

--//========================================================//
--// SEARCH ONE OBJECT FOR UUID
--//========================================================//

local function SearchForUUID(Object)

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

    -- Value objects
    for _, Child in ipairs(
        Object:GetDescendants()
    ) do

        if Child:IsA("StringValue")
            or Child:IsA("IntValue")
            or Child:IsA("NumberValue") then

            if IsUUID(Child.Value) then
                return tostring(Child.Value)
            end
        end

        if IsUUID(Child.Name) then
            return Child.Name
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

--//========================================================//
--// GET EGG POSITION
--//========================================================//

local function GetObjectPosition(Object)

    if not Object then
        return nil
    end

    if Object:IsA("BasePart") then
        return Object.Position
    end

    if Object:IsA("Model") then
        return Object:GetPivot().Position
    end

    for _, Child in ipairs(
        Object:GetDescendants()
    ) do

        if Child:IsA("BasePart") then
            return Child.Position
        end
    end

    return nil
end

--//========================================================//
--// FIND NEAREST RENDERED EGG
--//========================================================//

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

    local PromptPosition = GetObjectPosition(
        Prompt
    )

    local BestEgg = nil
    local BestDistance = math.huge

    --------------------------------------------------------
    -- RenderedEggs
    --------------------------------------------------------

    if RenderedEggs then

        for _, Egg in ipairs(
            RenderedEggs:GetChildren()
        ) do

            local Position = GetObjectPosition(Egg)

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

                if Distance < BestDistance then

                    BestDistance = Distance
                    BestEgg = Egg

                end
            end
        end
    end

    --------------------------------------------------------
    -- EggSpawns fallback
    --------------------------------------------------------

    if not BestEgg and EggSpawns then

        for _, Egg in ipairs(
            EggSpawns:GetChildren()
        ) do

            local Position = GetObjectPosition(Egg)

            if Position then

                local Distance = (
                    Position - Root.Position
                ).Magnitude

                if Distance < BestDistance then

                    BestDistance = Distance
                    BestEgg = Egg

                end
            end
        end
    end

    return BestEgg
end

--//========================================================//
--// FIND EGG UUID
--//========================================================//

local function FindEggUUID(Prompt)

    --------------------------------------------------------
    -- First: exact prompt
    --------------------------------------------------------

    local UUID = SearchForUUID(Prompt)

    if UUID then
        return UUID
    end

    --------------------------------------------------------
    -- Second: nearest rendered egg
    --------------------------------------------------------

    local Egg = FindNearestEgg(Prompt)

    if Egg then

        LastEgg = Egg

        UUID = SearchForUUID(Egg)

        if UUID then
            return UUID
        end
    end

    --------------------------------------------------------
    -- Third: search all RenderedEggs
    --------------------------------------------------------

    if RenderedEggs then

        for _, Egg in ipairs(
            RenderedEggs:GetChildren()
        ) do

            UUID = SearchForUUID(Egg)

            if UUID then
                return UUID
            end
        end
    end

    --------------------------------------------------------
    -- Fourth: search EggSpawns
    --------------------------------------------------------

    if EggSpawns then

        for _, Egg in ipairs(
            EggSpawns:GetChildren()
        ) do

            UUID = SearchForUUID(Egg)

            if UUID then
                return UUID
            end
        end
    end

    return nil
end

--//========================================================//
--// FIND PLAYER PLOT
--//========================================================//

local function FindOwnPlot()

    if not Plots then
        return nil
    end

    local Name = LocalPlayer.Name
    local DisplayName = LocalPlayer.DisplayName
    local UserId = tostring(LocalPlayer.UserId)

    for _, Plot in ipairs(
        Plots:GetChildren()
    ) do

        ----------------------------------------------------
        -- Attributes
        ----------------------------------------------------

        for AttributeName, Value in pairs(
            Plot:GetAttributes()
        ) do

            local StringValue = tostring(Value)

            if StringValue == Name
                or StringValue == DisplayName
                or StringValue == UserId then

                return Plot
            end
        end

        ----------------------------------------------------
        -- Descendants
        ----------------------------------------------------

        for _, Object in ipairs(
            Plot:GetDescendants()
        ) do

            if Object:IsA("StringValue") then

                local Value = tostring(
                    Object.Value
                )

                if Value == Name
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

            if Object:IsA("ObjectValue") then

                if Object.Value == LocalPlayer then
                    return Plot
                end
            end
        end
    end

    return nil
end

--//========================================================//
--// GET PLOT POSITION
--//========================================================//

local function GetPlotCFrame(Plot)

    if not Plot then
        return nil
    end

    if Plot:IsA("BasePart") then

        return Plot.CFrame
            + Vector3.new(0, 5, 0)
    end

    --------------------------------------------------------
    -- Common spawn names
    --------------------------------------------------------

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

    --------------------------------------------------------
    -- Plot pivot
    --------------------------------------------------------

    local Success, Pivot = pcall(function()
        return Plot:GetPivot()
    end)

    if Success and Pivot then

        return Pivot
            + Vector3.new(0, 5, 0)
    end

    --------------------------------------------------------
    -- First BasePart
    --------------------------------------------------------

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

--//========================================================//
--// TELEPORT TO OWN PLOT
--//========================================================//

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
            "[Egg Auto] Own plot not found."
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

--//========================================================//
--// IS EGG PROMPT
--//========================================================//

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

--//========================================================//
--// PROCESS EGG
--//========================================================//

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
        "[Egg Auto] Egg prompt detected:",
        Prompt:GetFullName()
    )

    --------------------------------------------------------
    -- Refresh plot eggs
    --------------------------------------------------------

    pcall(function()
        RequestPlotEggs:FireServer(false)
    end)

    task.wait(0.1)

    --------------------------------------------------------
    -- Find UUID
    --------------------------------------------------------

    local UUID = FindEggUUID(Prompt)

    if not UUID then

        warn(
            "[Egg Auto] UUID not found."
        )

        Rayfield:Notify({
            Title = "Egg Auto",
            Content = "Egg detected, but its UUID isn't exposed in the egg objects.",
            Duration = 3
        })

        Processing = false
        return
    end

    print(
        "[Egg Auto] UUID:",
        UUID
    )

    --------------------------------------------------------
    -- Pickup
    --------------------------------------------------------

    local Success, Error = pcall(function()

        EggPickup:FireServer(UUID)

    end)

    if not Success then

        warn(
            "[Egg Auto] EggPickup error:",
            Error
        )

        Processing = false
        return
    end

    print(
        "[Egg Auto] EggPickup sent."
    )

    --------------------------------------------------------
    -- Return immediately
    --------------------------------------------------------

    task.wait(0.05)

    local Returned = ReturnToPlot()

    if Returned then

        Rayfield:Notify({
            Title = "Egg Auto",
            Content = "Egg picked up → returned to your plot.",
            Duration = 2
        })

    else

        Rayfield:Notify({
            Title = "Egg Auto",
            Content = "Pickup succeeded, but plot teleport failed.",
            Duration = 3
        })
    end

    task.wait(0.15)

    Processing = false
end

--//========================================================//
--// PROMPT LISTENER
--//========================================================//

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

--//========================================================//
--// UI
--//========================================================//

MainTab:CreateToggle({
    Name = "Auto Egg Return",
    CurrentValue = false,
    Flag = "AutoEggReturn",

    Callback = function(Value)

        AutoEgg = Value

        if Value then

            Rayfield:Notify({
                Title = "Egg Auto",
                Content = "Enabled.",
                Duration = 2
            })

        else

            Rayfield:Notify({
                Title = "Egg Auto",
                Content = "Disabled.",
                Duration = 2
            })
        end
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
    Name = "Refresh Plot Eggs",

    Callback = function()

        local Success = pcall(function()
            RequestPlotEggs:FireServer(false)
        end)

        if Success then

            Rayfield:Notify({
                Title = "Eggs",
                Content = "Plot eggs requested.",
                Duration = 2
            })

        else

            Rayfield:Notify({
                Title = "Eggs",
                Content = "Request failed.",
                Duration = 2
            })
        end
    end
})

--//========================================================//
--// DEBUG EGG STRUCTURE
--//========================================================//

MainTab:CreateButton({
    Name = "Debug Egg",

    Callback = function()

        local Egg = LastEgg

        if not Egg then
            Egg = FindNearestEgg(LastPrompt)
        end

        if not Egg then

            Rayfield:Notify({
                Title = "Debug",
                Content = "No rendered egg found.",
                Duration = 3
            })

            return
        end

        print("================================")
        print("           EGG DEBUG")
        print("================================")

        print(
            "Egg:",
            Egg:GetFullName()
        )

        print(
            "Class:",
            Egg.ClassName
        )

        print("--- ATTRIBUTES ---")

        for Name, Value in pairs(
            Egg:GetAttributes()
        ) do

            print(
                Name,
                "=",
                Value
            )
        end

        print("--- DESCENDANTS ---")

        for _, Object in ipairs(
            Egg:GetDescendants()
        ) do

            print(
                Object:GetFullName(),
                "|",
                Object.ClassName
            )

            for Name, Value in pairs(
                Object:GetAttributes()
            ) do

                print(
                    "   ATTRIBUTE:",
                    Name,
                    "=",
                    Value
                )
            end

            if Object:IsA("StringValue")
                or Object:IsA("IntValue")
                or Object:IsA("NumberValue") then

                print(
                    "   VALUE:",
                    Object.Value
                )
            end
        end

        print("================================")
    end
})

--//========================================================//
--// STATUS
//========================================================//

MainTab:CreateParagraph({
    Title = "Egg Auto",
    Content =
        "Watches egg ProximityPrompts, searches RenderedEggs/EggSpawns for the egg UUID, fires EggPickup, then returns to your own plot."
})

--//========================================================//
--// LOADED
//========================================================//

Rayfield:Notify({
    Title = "Egg Auto Return",
    Content = "Loaded successfully.",
    Duration = 3
})

print(
    "[Egg Auto] Loaded | Player:",
    LocalPlayer.Name
)

print(
    "[Egg Auto] EggSpawns:",
    EggSpawns
)

print(
    "[Egg Auto] RenderedEggs:",
    RenderedEggs
)

print(
    "[Egg Auto] Plots:",
    Plots
)
