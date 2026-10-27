--[[
    RAGE REJOIN HUB v4.0 (Standalone)
    Auto Rejoin | Auto Execute | Anti AFK
]]

local VERSION = "4.0"

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
    ConfigFile = "RageRejoinHub_v4.json",
    RetryDelay = 3,
    MaxAttempts = 5,
    AttemptWait = 12,
}

local defaults = { AutoRejoin = true, AutoExecute = false, AntiAFK = false }
local config = table.clone(defaults)

local queueTeleport = queue_on_teleport
    or queueonteleport
    or (syn and syn.queue_on_teleport)
    or (fluxus and fluxus.queue_on_teleport)

local connections = {}
local destroyed = false
local queued = false
local handling = false

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
-- Theme
---------------------------------------------------------------------
local C = {
    Bg = Color3.fromRGB(14, 15, 22),
    Surface = Color3.fromRGB(22, 24, 35),
    Row = Color3.fromRGB(28, 31, 45),
    Accent = Color3.fromRGB(124, 92, 255),
    AccentSoft = Color3.fromRGB(190, 170, 255),
    Off = Color3.fromRGB(62, 65, 82),
    Text = Color3.fromRGB(238, 239, 247),
    Sub = Color3.fromRGB(150, 154, 175),
    Green = Color3.fromRGB(96, 226, 156),
    Yellow = Color3.fromRGB(255, 206, 105),
    Red = Color3.fromRGB(255, 120, 120),
}

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

local function stroke(object, color, thickness, transparency)
    return make("UIStroke", {
        Color = color,
        Thickness = thickness or 1,
        Transparency = transparency or 0.4,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    }, object)
end

local function tween(object, props, time)
    local t = TweenService:Create(
        object,
        TweenInfo.new(time or 0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        props
    )
    t:Play()
    return t
end

---------------------------------------------------------------------
-- Root GUI
---------------------------------------------------------------------
local gui = make("ScreenGui", {
    Name = "RageRejoinHub",
    ResetOnSpawn = false,
    IgnoreGuiInset = true,
    DisplayOrder = 999,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, nil)
gui.Parent = player:WaitForChild("PlayerGui")

local panel = make("Frame", {
    Name = "MainPanel",
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.fromScale(0.5, 0.5),
    Size = UDim2.fromOffset(310, 360),
    BackgroundColor3 = C.Bg,
    BorderSizePixel = 0,
    Visible = false,
    ClipsDescendants = true,
}, gui)
round(panel, 18)
stroke(panel, C.Accent, 1.5, 0.25)

local panelScale = make("UIScale", {}, panel)
local function updateScale()
    local view = gui.AbsoluteSize
    if view.X <= 0 or view.Y <= 0 then return end
    panelScale.Scale = math.clamp(math.min(view.X / 340, view.Y / 390), 0.6, 1)
end
updateScale()
track(gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateScale))

-- Header
local header = make("Frame", {
    Name = "Header",
    Size = UDim2.new(1, 0, 0, 62),
    BackgroundColor3 = C.Surface,
    BorderSizePixel = 0,
}, panel)
make("UIGradient", {
    Color = ColorSequence.new(Color3.fromRGB(40, 32, 78), C.Surface),
    Rotation = 20,
}, header)

make("TextLabel", {
    Position = UDim2.fromOffset(16, 9),
    Size = UDim2.new(1, -90, 0, 24),
    BackgroundTransparency = 1,
    Text = "RAGE REJOIN",
    TextColor3 = C.AccentSoft,
    Font = Enum.Font.GothamBold,
    TextSize = 17,
    TextXAlignment = Enum.TextXAlignment.Left,
}, header)

make("TextLabel", {
    Position = UDim2.fromOffset(16, 34),
    Size = UDim2.new(1, -90, 0, 16),
    BackgroundTransparency = 1,
    Text = "Reconnect • Persist • Resume  |  v" .. VERSION,
    TextColor3 = C.Sub,
    Font = Enum.Font.Gotham,
    TextSize = 10,
    TextXAlignment = Enum.TextXAlignment.Left,
}, header)

local close = make("TextButton", {
    Position = UDim2.new(1, -40, 0, 16),
    Size = UDim2.fromOffset(28, 28),
    Text = "×",
    TextSize = 20,
    Font = Enum.Font.GothamMedium,
    TextColor3 = C.Text,
    BackgroundColor3 = Color3.fromRGB(52, 46, 82),
    AutoButtonColor = false,
    BorderSizePixel = 0,
}, header)
round(close, 9)

-- Status pill
local statusPill = make("Frame", {
    Position = UDim2.fromOffset(14, 74),
    Size = UDim2.new(1, -28, 0, 28),
    BackgroundColor3 = C.Surface,
    BorderSizePixel = 0,
}, panel)
round(statusPill, 8)

local statusDot = make("Frame", {
    Position = UDim2.fromOffset(11, 10),
    Size = UDim2.fromOffset(8, 8),
    BackgroundColor3 = C.Green,
    BorderSizePixel = 0,
}, statusPill)
round(statusDot, 4)

local statusText = make("TextLabel", {
    Position = UDim2.fromOffset(26, 0),
    Size = UDim2.new(1, -34, 1, 0),
    BackgroundTransparency = 1,
    Text = "SYSTEM READY",
    TextColor3 = C.Text,
    Font = Enum.Font.GothamMedium,
    TextSize = 11,
    TextXAlignment = Enum.TextXAlignment.Left,
}, statusPill)

local function setStatus(text, color)
    if destroyed then return end
    statusText.Text = string.upper(text)
    tween(statusDot, { BackgroundColor3 = color or C.Green }, 0.2)
end

---------------------------------------------------------------------
-- Toast
---------------------------------------------------------------------
local toast = make("TextLabel", {
    AnchorPoint = Vector2.new(0.5, 1),
    Position = UDim2.new(0.5, 0, 1, 40),
    Size = UDim2.fromOffset(240, 32),
    BackgroundColor3 = C.Surface,
    TextColor3 = C.Text,
    Font = Enum.Font.GothamMedium,
    TextSize = 12,
    Text = "",
    BorderSizePixel = 0,
    Visible = false,
}, gui)
round(toast, 10)
stroke(toast, C.Accent, 1, 0.4)

local toastToken = 0
local function notify(text)
    if destroyed then return end
    toastToken += 1
    local token = toastToken
    toast.Text = text
    toast.Visible = true
    toast.Position = UDim2.new(0.5, 0, 1, 40)
    tween(toast, { Position = UDim2.new(0.5, 0, 1, -24) }, 0.25)
    task.delay(2.5, function()
        if destroyed or token ~= toastToken then return end
        tween(toast, { Position = UDim2.new(0.5, 0, 1, 40) }, 0.25)
        task.wait(0.3)
        if token == toastToken then toast.Visible = false end
    end)
end

---------------------------------------------------------------------
-- Queue + rejoin logic
---------------------------------------------------------------------
local function queueScript()
    if queued or not config.AutoExecute or type(queueTeleport) ~= "function" then
        return
    end

    local source = string.format(
        'loadstring(game:HttpGet("%s?v=%d"))()',
        SETTINGS.ScriptUrl,
        os.time()
    )

    if pcall(queueTeleport, source) then
        queued = true
    end
end

local function requestTeleport()
    queueScript()

    local ok, err = pcall(function()
        if #Players:GetPlayers() <= 1 then
            TeleportService:Teleport(game.PlaceId, player)
        else
            TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, player)
        end
    end)

    if not ok then
        queued = false
        warn("[Rage Rejoin] Teleport request failed:", err)
    end
    return ok
end

local function startRejoinLoop(reason)
    if handling or destroyed or not config.AutoRejoin then return end
    handling = true
    warn("[Rage Rejoin] Triggered:", reason or "unknown")

    task.spawn(function()
        for attempt = 1, SETTINGS.MaxAttempts do
            if destroyed or not config.AutoRejoin then break end

            setStatus(string.format("Rejoin %d/%d", attempt, SETTINGS.MaxAttempts), C.Yellow)
            task.wait(SETTINGS.RetryDelay * attempt)

            if requestTeleport() then
                task.wait(SETTINGS.AttemptWait)
            end
        end

        if not destroyed then
            setStatus("Rejoin stopped", C.Red)
        end
        handling = false
    end)
end

---------------------------------------------------------------------
-- Toggles
---------------------------------------------------------------------
local function makeToggle(label, desc, key, y)
    local row = make("Frame", {
        Position = UDim2.fromOffset(14, y),
        Size = UDim2.new(1, -28, 0, 48),
        BackgroundColor3 = C.Row,
        BorderSizePixel = 0,
    }, panel)
    round(row, 10)

    make("TextLabel", {
        Position = UDim2.fromOffset(12, 7),
        Size = UDim2.new(1, -80, 0, 18),
        BackgroundTransparency = 1,
        Text = label,
        TextColor3 = C.Text,
        Font = Enum.Font.GothamMedium,
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, row)

    make("TextLabel", {
        Position = UDim2.fromOffset(12, 26),
        Size = UDim2.new(1, -80, 0, 14),
        BackgroundTransparency = 1,
        Text = desc,
        TextColor3 = C.Sub,
        Font = Enum.Font.Gotham,
        TextSize = 10,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, row)

    local track_ = make("TextButton", {
        Position = UDim2.new(1, -58, 0.5, -12),
        Size = UDim2.fromOffset(46, 24),
        Text = "",
        AutoButtonColor = false,
        BackgroundColor3 = C.Off,
        BorderSizePixel = 0,
    }, row)
    round(track_, 12)

    local knob = make("Frame", {
        Position = UDim2.fromOffset(3, 3),
        Size = UDim2.fromOffset(18, 18),
        BackgroundColor3 = Color3.new(1, 1, 1),
        BorderSizePixel = 0,
    }, track_)
    round(knob, 9)

    local function apply(animated)
        local on = config[key]
        local bg = on and C.Accent or C.Off
        local pos = on and UDim2.new(1, -21, 0, 3) or UDim2.fromOffset(3, 3)
        if animated then
            tween(track_, { BackgroundColor3 = bg })
            tween(knob, { Position = pos })
        else
            track_.BackgroundColor3 = bg
            knob.Position = pos
        end
    end

    apply(false)

    track(track_.Activated:Connect(function()
        config[key] = not config[key]
        if key == "AutoExecute" and not config[key] then
            queued = false
        end
        apply(true)
        saveConfig()
        setStatus(label .. (config[key] and " on" or " off"),
            config[key] and C.Green or C.Sub)
    end))
end

makeToggle("Auto Rejoin", "Reconnect after disconnect", "AutoRejoin", 114)
makeToggle("Auto Execute", "Re-run script after teleport", "AutoExecute", 170)
makeToggle("Anti AFK", "Prevent idle disconnect", "AntiAFK", 226)

---------------------------------------------------------------------
-- Action buttons
---------------------------------------------------------------------
local function makeAction(text, x, width, color, callback)
    local button = make("TextButton", {
        Position = UDim2.fromOffset(x, 290),
        Size = UDim2.fromOffset(width, 34),
        BackgroundColor3 = color,
        Text = text,
        TextColor3 = C.Text,
        Font = Enum.Font.GothamMedium,
        TextSize = 12,
        AutoButtonColor = false,
        BorderSizePixel = 0,
    }, panel)
    round(button, 10)

    track(button.MouseEnter:Connect(function()
        tween(button, { BackgroundTransparency = 0.15 }, 0.12)
    end))
    track(button.MouseLeave:Connect(function()
        tween(button, { BackgroundTransparency = 0 }, 0.12)
    end))
    track(button.Activated:Connect(callback))
end

makeAction("Test Rejoin", 14, 135, Color3.fromRGB(64, 52, 120), function()
    if handling then return end
    setStatus("Testing rejoin...", C.Yellow)
    task.spawn(function()
        if not requestTeleport() then
            setStatus("Teleport failed", C.Red)
            notify("Teleport request failed")
        end
    end)
end)

makeAction("Test Kick", 161, 135, Color3.fromRGB(110, 48, 62), function()
    setStatus("Testing kick...", C.Red)
    task.delay(0.3, function()
        pcall(function()
            player:Kick("Rage Rejoin Hub test kick")
        end)
    end)
end)

make("TextLabel", {
    Position = UDim2.fromOffset(14, 334),
    Size = UDim2.new(1, -28, 0, 18),
    BackgroundTransparency = 1,
    Text = "Settings save automatically when supported",
    TextColor3 = C.Sub,
    Font = Enum.Font.Gotham,
    TextSize = 9,
}, panel)

---------------------------------------------------------------------
-- Floating orb + dragging
---------------------------------------------------------------------
local orb = make("TextButton", {
    Name = "FloatingButton",
    Position = UDim2.fromOffset(20, 200),
    Size = UDim2.fromOffset(52, 52),
    BackgroundColor3 = C.Accent,
    Text = "R",
    TextColor3 = Color3.new(1, 1, 1),
    TextSize = 22,
    Font = Enum.Font.GothamBlack,
    AutoButtonColor = false,
    BorderSizePixel = 0,
}, gui)
round(orb, 26)
stroke(orb, C.AccentSoft, 2, 0.15)

local function clampToScreen(object)
    local screen = gui.AbsoluteSize
    local size = object.AbsoluteSize
    local pos = object.AbsolutePosition
    local anchor = object.AnchorPoint
    local x = math.clamp(pos.X + size.X * anchor.X, size.X * anchor.X, math.max(size.X * anchor.X, screen.X - size.X * (1 - anchor.X)))
    local y = math.clamp(pos.Y + size.Y * anchor.Y, size.Y * anchor.Y, math.max(size.Y * anchor.Y, screen.Y - size.Y * (1 - anchor.Y)))
    object.Position = UDim2.fromOffset(x, y)
end

-- Returns a function that reports whether the last gesture was a drag
local function makeDraggable(handle, target)
    local dragInput, dragStart, startPos
    local moved = false

    track(handle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragInput = input
            dragStart = input.Position
            local abs = target.AbsolutePosition
            local anchor = target.AnchorPoint
            local size = target.AbsoluteSize
            startPos = Vector2.new(abs.X + size.X * anchor.X, abs.Y + size.Y * anchor.Y)
            moved = false
        end
    end))

    track(UserInputService.InputChanged:Connect(function(input)
        if not dragInput then return end
        if input ~= dragInput and input.UserInputType ~= Enum.UserInputType.MouseMovement then
            return
        end
        local delta = input.Position - dragStart
        if math.abs(delta.X) > 6 or math.abs(delta.Y) > 6 then
            moved = true
        end
        if moved then
            target.Position = UDim2.fromOffset(startPos.X + delta.X, startPos.Y + delta.Y)
        end
    end))

    track(UserInputService.InputEnded:Connect(function(input)
        if dragInput and (input == dragInput
            or input.UserInputType == Enum.UserInputType.MouseButton1) then
            dragInput = nil
            if moved then clampToScreen(target) end
        end
    end))

    return function() return moved end
end

local orbMoved = makeDraggable(orb, orb)
makeDraggable(header, panel)

local function togglePanel()
    if panel.Visible then
        tween(panel, { BackgroundTransparency = 1 }, 0.12)
        task.delay(0.12, function()
            if not destroyed then
                panel.Visible = false
                panel.BackgroundTransparency = 0
            end
        end)
    else
        panel.BackgroundTransparency = 1
        panel.Visible = true
        tween(panel, { BackgroundTransparency = 0 }, 0.15)
    end
end

track(orb.Activated:Connect(function()
    if orbMoved() then return end
    togglePanel()
end))

track(close.Activated:Connect(function()
    if panel.Visible then togglePanel() end
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
-- Disconnect detection
---------------------------------------------------------------------
track(GuiService.ErrorMessageChanged:Connect(function(message)
    if type(message) == "string" and message ~= "" then
        startRejoinLoop("ErrorMessage: " .. message)
    end
end))

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

track(TeleportService.TeleportInitFailed:Connect(function(teleportPlayer, result, message)
    if teleportPlayer ~= player then return end
    queued = false
    warn("[Rage Rejoin] Teleport failed:", result, message)
    setStatus("Teleport failed", C.Red)
    startRejoinLoop("TeleportInitFailed")
end))

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

env.__RageRejoinHub = { Destroy = destroy, Version = VERSION }

saveConfig()
setStatus("System ready", C.Green)
notify("Rage Rejoin v" .. VERSION .. " loaded")
print("[Rage Rejoin Hub] v" .. VERSION .. " loaded.")