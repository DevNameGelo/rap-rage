--[[
    RAGE REJOIN HUB v2
    Auto Rejoin | Auto Execute | Anti AFK
]]

-- Single-instance guard: clean up any previous run
local env = (getgenv and getgenv()) or _G
if env.__RageRejoinHub and type(env.__RageRejoinHub.Destroy) == "function" then
    pcall(env.__RageRejoinHub.Destroy)
end

if not game:IsLoaded() then
    game.Loaded:Wait()
end

local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")
local VirtualUser = game:GetService("VirtualUser")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
while not player do
    Players:GetPropertyChangedSignal("LocalPlayer"):Wait()
    player = Players.LocalPlayer
end

local SETTINGS = {
    ScriptUrl = "https://raw.githubusercontent.com/DevNameGelo/rap-rage/refs/heads/main/script.lua",
    ConfigFile = "RageRejoinHub_Config.json",
    RetryDelay = 3,
    MaxAttempts = 5,
    AttemptWait = 12,
}

local defaults = {
    AutoRejoin = true,
    AutoExecute = false,
    AntiAFK = false,
}

local config = table.clone(defaults)

---------------------------------------------------------------------
-- Executor compatibility
---------------------------------------------------------------------
local queueTeleport = queue_on_teleport
    or queueonteleport
    or (syn and syn.queue_on_teleport)
    or (fluxus and fluxus.queue_on_teleport)

local connections = {}
local destroyed = false

local function track(connection)
    connections[#connections + 1] = connection
    return connection
end

---------------------------------------------------------------------
-- Config
---------------------------------------------------------------------
local function saveConfig()
    if type(writefile) ~= "function" then return end
    pcall(function()
        writefile(SETTINGS.ConfigFile, HttpService:JSONEncode(config))
    end)
end

local function loadConfig()
    if type(readfile) ~= "function" or type(isfile) ~= "function" then return end
    pcall(function()
        if isfile(SETTINGS.ConfigFile) then
            local data = HttpService:JSONDecode(readfile(SETTINGS.ConfigFile))
            if type(data) == "table" then
                for key in pairs(defaults) do
                    if type(data[key]) == "boolean" then
                        config[key] = data[key]
                    end
                end
            end
        end
    end)
end

loadConfig()

---------------------------------------------------------------------
-- GUI parent (safe fallback chain)
---------------------------------------------------------------------
local function getGuiParent()
    if type(gethui) == "function" then
        local ok, result = pcall(gethui)
        if ok and typeof(result) == "Instance" then
            return result
        end
    end

    local ok, coreGui = pcall(function()
        return game:GetService("CoreGui")
    end)
    if ok and coreGui then
        local test = Instance.new("Folder")
        local canParent = pcall(function() test.Parent = coreGui end)
        test:Destroy()
        if canParent then
            return coreGui
        end
    end

    return player:WaitForChild("PlayerGui")
end

---------------------------------------------------------------------
-- UI helpers
---------------------------------------------------------------------
local function make(class, props, parent)
    local object = Instance.new(class)
    for key, value in pairs(props) do
        object[key] = value
    end
    object.Parent = parent
    return object
end

local function round(object, radius)
    return make("UICorner", { CornerRadius = UDim.new(0, radius) }, object)
end

local function stroke(object, color, thickness)
    return make("UIStroke", {
        Color = color,
        Thickness = thickness or 1,
        Transparency = 0.15,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    }, object)
end

local GREEN = Color3.fromRGB(105, 235, 160)
local YELLOW = Color3.fromRGB(255, 205, 100)
local RED = Color3.fromRGB(255, 130, 130)
local GREY = Color3.fromRGB(190, 190, 205)

local gui = make("ScreenGui", {
    Name = HttpService:GenerateGUID(false),
    ResetOnSpawn = false,
    IgnoreGuiInset = true,
    DisplayOrder = 999,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, nil)
gui.Parent = getGuiParent()

local panel = make("Frame", {
    Name = "MainPanel",
    AnchorPoint = Vector2.new(0.5, 0.5),
    Size = UDim2.fromOffset(300, 340),
    Position = UDim2.fromScale(0.5, 0.5),
    BackgroundColor3 = Color3.fromRGB(17, 19, 27),
    BorderSizePixel = 0,
    Visible = false,
}, gui)
round(panel, 16)
stroke(panel, Color3.fromRGB(104, 70, 255), 1.5)

-- Scale panel to fit small phone screens
local panelScale = make("UIScale", {}, panel)
local function updateScale()
    local camera = workspace.CurrentCamera
    if not camera then return end
    local view = camera.ViewportSize
    panelScale.Scale = math.clamp(math.min(view.X / 330, view.Y / 370), 0.6, 1)
end
updateScale()
do
    local camera = workspace.CurrentCamera
    if camera then
        track(camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale))
    end
end

local header = make("Frame", {
    Size = UDim2.new(1, 0, 0, 64),
    BackgroundColor3 = Color3.fromRGB(27, 25, 43),
    BorderSizePixel = 0,
}, panel)
round(header, 16)

make("Frame", {
    Position = UDim2.new(0, 0, 1, -15),
    Size = UDim2.new(1, 0, 0, 15),
    BackgroundColor3 = header.BackgroundColor3,
    BorderSizePixel = 0,
}, header)

make("TextLabel", {
    Position = UDim2.fromOffset(16, 10),
    Size = UDim2.new(1, -60, 0, 25),
    BackgroundTransparency = 1,
    Text = "RAGE REJOIN",
    TextColor3 = Color3.fromRGB(190, 166, 255),
    Font = Enum.Font.GothamBold,
    TextSize = 17,
    TextXAlignment = Enum.TextXAlignment.Left,
}, header)

make("TextLabel", {
    Position = UDim2.fromOffset(17, 35),
    Size = UDim2.new(1, -60, 0, 18),
    BackgroundTransparency = 1,
    Text = "Reconnect • Persist • Resume",
    TextColor3 = Color3.fromRGB(165, 168, 185),
    Font = Enum.Font.Gotham,
    TextSize = 10,
    TextXAlignment = Enum.TextXAlignment.Left,
}, header)

local close = make("TextButton", {
    Position = UDim2.new(1, -38, 0, 13),
    Size = UDim2.fromOffset(26, 26),
    Text = "×",
    TextSize = 22,
    Font = Enum.Font.Gotham,
    TextColor3 = Color3.new(1, 1, 1),
    BackgroundColor3 = Color3.fromRGB(54, 48, 75),
    BorderSizePixel = 0,
}, header)
round(close, 8)

local status = make("TextLabel", {
    Position = UDim2.fromOffset(15, 72),
    Size = UDim2.new(1, -30, 0, 24),
    BackgroundColor3 = Color3.fromRGB(28, 31, 43),
    Text = "●  SYSTEM READY",
    TextColor3 = GREEN,
    Font = Enum.Font.GothamMedium,
    TextSize = 11,
    BorderSizePixel = 0,
}, panel)
round(status, 7)

local function setStatus(text, color)
    if destroyed then return end
    status.Text = "●  " .. string.upper(text)
    status.TextColor3 = color or GREEN
end

---------------------------------------------------------------------
-- Queue script on teleport
---------------------------------------------------------------------
local queued = false

local function queueScript()
    if queued or not config.AutoExecute or type(queueTeleport) ~= "function" then
        return
    end

    local source = string.format(
        'loadstring(game:HttpGet("%s"))()',
        SETTINGS.ScriptUrl
    )

    if pcall(queueTeleport, source) then
        queued = true
    end
end

---------------------------------------------------------------------
-- Rejoin logic
---------------------------------------------------------------------
local function requestTeleport()
    queueScript()

    local ok, err = pcall(function()
        if #Players:GetPlayers() <= 1 then
            -- Solo in server: a normal teleport gives a fresh server
            TeleportService:Teleport(game.PlaceId, player)
        else
            -- Others present: return to the same server if possible
            TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, player)
        end
    end)

    if not ok then
        queued = false
        warn("[Rage Rejoin] Teleport request failed:", err)
    end
    return ok
end

local handling = false

local function startRejoinLoop(reason)
    if handling or destroyed or not config.AutoRejoin then return end
    handling = true
    warn("[Rage Rejoin] Triggered:", reason or "unknown")

    task.spawn(function()
        for attempt = 1, SETTINGS.MaxAttempts do
            if destroyed or not config.AutoRejoin then break end

            setStatus(string.format("Rejoin %d/%d", attempt, SETTINGS.MaxAttempts), YELLOW)
            task.wait(SETTINGS.RetryDelay * attempt)

            if requestTeleport() then
                task.wait(SETTINGS.AttemptWait)
            end
        end

        if not destroyed then
            setStatus("Rejoin stopped", RED)
        end
        handling = false
    end)
end

---------------------------------------------------------------------
-- Toggles
---------------------------------------------------------------------
local function makeToggle(label, key, y)
    local row = make("Frame", {
        Position = UDim2.fromOffset(14, y),
        Size = UDim2.new(1, -28, 0, 43),
        BackgroundColor3 = Color3.fromRGB(27, 30, 42),
        BorderSizePixel = 0,
    }, panel)
    round(row, 9)

    make("TextLabel", {
        Position = UDim2.fromOffset(12, 0),
        Size = UDim2.new(1, -78, 1, 0),
        BackgroundTransparency = 1,
        Text = label,
        TextColor3 = Color3.fromRGB(237, 238, 245),
        Font = Enum.Font.GothamMedium,
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, row)

    local button = make("TextButton", {
        Position = UDim2.new(1, -60, 0.5, -12),
        Size = UDim2.fromOffset(48, 24),
        Text = "",
        AutoButtonColor = false,
        BackgroundColor3 = Color3.fromRGB(68, 70, 84),
        BorderSizePixel = 0,
    }, row)
    round(button, 12)

    local knob = make("Frame", {
        Position = UDim2.fromOffset(3, 3),
        Size = UDim2.fromOffset(18, 18),
        BackgroundColor3 = Color3.new(1, 1, 1),
        BorderSizePixel = 0,
    }, button)
    round(knob, 9)

    local info = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

    local function refresh()
        local enabled = config[key]
        TweenService:Create(button, info, {
            BackgroundColor3 = enabled
                and Color3.fromRGB(127, 87, 255)
                or Color3.fromRGB(68, 70, 84),
        }):Play()
        TweenService:Create(knob, info, {
            Position = enabled
                and UDim2.new(1, -21, 0, 3)
                or UDim2.fromOffset(3, 3),
        }):Play()
    end

    track(button.Activated:Connect(function()
        config[key] = not config[key]
        if key == "AutoExecute" and not config[key] then
            queued = false
        end
        refresh()
        saveConfig()
        setStatus(label .. (config[key] and " enabled" or " disabled"),
            config[key] and GREEN or GREY)
    end))

    -- Set initial state without animation
    local enabled = config[key]
    button.BackgroundColor3 = enabled
        and Color3.fromRGB(127, 87, 255)
        or Color3.fromRGB(68, 70, 84)
    knob.Position = enabled and UDim2.new(1, -21, 0, 3) or UDim2.fromOffset(3, 3)
end

makeToggle("Auto Rejoin", "AutoRejoin", 108)
makeToggle("Auto Execute", "AutoExecute", 158)
makeToggle("Anti AFK", "AntiAFK", 208)

---------------------------------------------------------------------
-- Action buttons
---------------------------------------------------------------------
local function makeAction(text, x, width, callback)
    local button = make("TextButton", {
        Position = UDim2.fromOffset(x, 267),
        Size = UDim2.fromOffset(width, 30),
        BackgroundColor3 = Color3.fromRGB(44, 39, 67),
        Text = text,
        TextColor3 = Color3.fromRGB(235, 230, 255),
        Font = Enum.Font.GothamMedium,
        TextSize = 11,
        BorderSizePixel = 0,
    }, panel)
    round(button, 8)
    track(button.Activated:Connect(callback))
end

makeAction("Test Rejoin", 14, 132, function()
    if handling then return end
    setStatus("Testing rejoin...", YELLOW)
    task.spawn(function()
        if not requestTeleport() then
            setStatus("Teleport failed", RED)
        end
    end)
end)

makeAction("Test Kick", 154, 132, function()
    setStatus("Testing kick...", RED)
    task.delay(0.3, function()
        -- With Auto Rejoin ON, the disconnect handler below takes over
        pcall(function()
            player:Kick("Rage Rejoin Hub test kick")
        end)
    end)
end)

make("TextLabel", {
    Position = UDim2.fromOffset(14, 306),
    Size = UDim2.new(1, -28, 0, 22),
    BackgroundTransparency = 1,
    Text = "Settings save automatically when supported",
    TextColor3 = Color3.fromRGB(142, 145, 163),
    Font = Enum.Font.Gotham,
    TextSize = 9,
}, panel)

---------------------------------------------------------------------
-- Floating draggable button
---------------------------------------------------------------------
local orb = make("TextButton", {
    Name = "FloatingButton",
    Position = UDim2.fromOffset(20, 200),
    Size = UDim2.fromOffset(54, 54),
    BackgroundColor3 = Color3.fromRGB(105, 65, 255),
    Text = "R",
    TextColor3 = Color3.new(1, 1, 1),
    TextSize = 24,
    Font = Enum.Font.GothamBlack,
    BorderSizePixel = 0,
    AutoButtonColor = true,
}, gui)
round(orb, 27)
stroke(orb, Color3.fromRGB(195, 174, 255), 2)

local dragInput, dragStart, startPos
local moved = false

local function clampOrb()
    local screen = gui.AbsoluteSize
    local size = orb.AbsoluteSize
    local pos = orb.AbsolutePosition
    orb.Position = UDim2.fromOffset(
        math.clamp(pos.X, 0, math.max(0, screen.X - size.X)),
        math.clamp(pos.Y, 0, math.max(0, screen.Y - size.Y))
    )
end

track(orb.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
        dragInput = input
        dragStart = input.Position
        startPos = orb.Position
        moved = false
    end
end))

track(UserInputService.InputChanged:Connect(function(input)
    if not dragInput then return end
    if input ~= dragInput
        and input.UserInputType ~= Enum.UserInputType.MouseMovement then
        return
    end

    local delta = input.Position - dragStart
    if math.abs(delta.X) > 6 or math.abs(delta.Y) > 6 then
        moved = true
    end
    if moved then
        orb.Position = UDim2.fromOffset(
            startPos.X.Offset + delta.X,
            startPos.Y.Offset + delta.Y
        )
    end
end))

track(UserInputService.InputEnded:Connect(function(input)
    if dragInput and (input == dragInput
        or input.UserInputType == Enum.UserInputType.MouseButton1) then
        dragInput = nil
        if moved then clampOrb() end
    end
end))

track(orb.Activated:Connect(function()
    if moved then return end
    panel.Visible = not panel.Visible
end))

track(close.Activated:Connect(function()
    panel.Visible = false
end))

---------------------------------------------------------------------
-- Anti-AFK
---------------------------------------------------------------------
track(player.Idled:Connect(function()
    if not config.AntiAFK then return end
    pcall(function()
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new(0, 0))
    end)
end))

---------------------------------------------------------------------
-- Disconnect / kick detection
---------------------------------------------------------------------
-- Method 1: GuiService error message (fires on kick/disconnect)
track(GuiService.ErrorMessageChanged:Connect(function(message)
    if type(message) == "string" and message ~= "" then
        startRejoinLoop("ErrorMessage: " .. message)
    end
end))

-- Method 2: Roblox error prompt overlay
task.spawn(function()
    local ok, overlay = pcall(function()
        local coreGui = game:GetService("CoreGui")
        return coreGui:WaitForChild("RobloxPromptGui", 15)
            :WaitForChild("promptOverlay", 15)
    end)

    if ok and overlay then
        track(overlay.ChildAdded:Connect(function(child)
            if child.Name == "ErrorPrompt" then
                startRejoinLoop("ErrorPrompt")
            end
        end))
    end
end)

-- Method 3: teleport failures
track(TeleportService.TeleportInitFailed:Connect(function(teleportPlayer, result, message)
    if teleportPlayer ~= player then return end
    queued = false
    warn("[Rage Rejoin] Teleport failed:", result, message)
    setStatus("Teleport failed", RED)
    startRejoinLoop("TeleportInitFailed")
end))

-- Re-queue if something else teleports us
track(player.OnTeleport:Connect(function(state)
    if state == Enum.TeleportState.Started then
        queueScript()
    end
end))

---------------------------------------------------------------------
-- Cleanup API
---------------------------------------------------------------------
local function destroy()
    destroyed = true
    for _, connection in ipairs(connections) do
        pcall(function() connection:Disconnect() end)
    end
    table.clear(connections)
    pcall(function() gui:Destroy() end)
    env.__RageRejoinHub = nil
end

env.__RageRejoinHub = { Destroy = destroy }

saveConfig()
setStatus("System ready", GREEN)
print("[Rage Rejoin Hub] Loaded successfully.")