
--[[
    RAGE REJOIN HUB
    Auto Rejoin: ON
    Auto Execute: OFF
    Anti AFK: OFF
]]

local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")
local VirtualUser = game:GetService("VirtualUser")

local player = Players.LocalPlayer
local CONFIG_URL =
    "https://raw.githubusercontent.com/DevNameGelo/rap-rage/refs/heads/main/script.lua"

local CONFIG_FILE = "RageRejoinHub_Config.json"

local defaults = {
    AutoRejoin = true,
    AutoExecute = false,
    AntiAFK = false
}

local config = table.clone(defaults)

-- Executor compatibility
local queueTeleport =
    queue_on_teleport
    or queueonteleport
    or (syn and syn.queue_on_teleport)

local function saveConfig()
    if type(writefile) ~= "function" then
        return
    end

    pcall(function()
        writefile(CONFIG_FILE, HttpService:JSONEncode(config))
    end)
end

local function loadConfig()
    if type(readfile) ~= "function"
        or type(isfile) ~= "function" then
        return
    end

    pcall(function()
        if isfile(CONFIG_FILE) then
            local data = HttpService:JSONDecode(readfile(CONFIG_FILE))

            for key in pairs(defaults) do
                if type(data[key]) == "boolean" then
                    config[key] = data[key]
                end
            end
        end
    end)
end

loadConfig()

-- Prevent multiple reconnect attempts from this instance
local rejoining = false

local function queueScript()
    if not config.AutoExecute or type(queueTeleport) ~= "function" then
        return
    end

    local source = string.format(
        'loadstring(game:HttpGet("%s"))()',
        CONFIG_URL
    )

    pcall(queueTeleport, source)
end

local function rejoin()
    if rejoining or not config.AutoRejoin then
        return
    end

    rejoining = true
    queueScript()

    local ok = pcall(function()
        TeleportService:Teleport(game.PlaceId, player)
    end)

    if not ok then
        rejoining = false
        warn("[Rage Rejoin] Teleport request failed.")
    end
end

-- GUI
local gui = Instance.new("ScreenGui")
gui.Name = "RageRejoinHub"
gui.ResetOnSpawn = false
gui.DisplayOrder = 999
gui.Parent = player:WaitForChild("PlayerGui")

local function round(object, radius)
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, radius)
    corner.Parent = object
end

local function stroke(object, color, thickness)
    local border = Instance.new("UIStroke")
    border.Color = color
    border.Thickness = thickness or 1
    border.Transparency = 0.15
    border.Parent = object
end

local function make(class, props, parent)
    local object = Instance.new(class)
    for key, value in pairs(props) do
        object[key] = value
    end
    object.Parent = parent
    return object
end

local panel = make("Frame", {
    Name = "MainPanel",
    Size = UDim2.fromOffset(300, 340),
    Position = UDim2.new(0.5, -150, 0.5, -170),
    BackgroundColor3 = Color3.fromRGB(17, 19, 27),
    Visible = false,
    BorderSizePixel = 0
}, gui)
round(panel, 16)
stroke(panel, Color3.fromRGB(104, 70, 255), 1.5)

local header = make("Frame", {
    Size = UDim2.new(1, 0, 0, 64),
    BackgroundColor3 = Color3.fromRGB(27, 25, 43),
    BorderSizePixel = 0
}, panel)
round(header, 16)

-- Cover the lower rounded part of the header for a clean edge
make("Frame", {
    Position = UDim2.new(0, 0, 1, -15),
    Size = UDim2.new(1, 0, 0, 15),
    BackgroundColor3 = header.BackgroundColor3,
    BorderSizePixel = 0
}, header)

make("TextLabel", {
    Position = UDim2.fromOffset(16, 10),
    Size = UDim2.new(1, -60, 0, 25),
    BackgroundTransparency = 1,
    Text = "RAGE REJOIN",
    TextColor3 = Color3.fromRGB(190, 166, 255),
    Font = Enum.Font.GothamBold,
    TextSize = 17,
    TextXAlignment = Enum.TextXAlignment.Left
}, header)

make("TextLabel", {
    Position = UDim2.fromOffset(17, 35),
    Size = UDim2.new(1, -60, 0, 18),
    BackgroundTransparency = 1,
    Text = "Reconnect • Persist • Resume",
    TextColor3 = Color3.fromRGB(165, 168, 185),
    Font = Enum.Font.Gotham,
    TextSize = 10,
    TextXAlignment = Enum.TextXAlignment.Left
}, header)

local close = make("TextButton", {
    Position = UDim2.new(1, -38, 0, 13),
    Size = UDim2.fromOffset(26, 26),
    Text = "×",
    TextSize = 22,
    Font = Enum.Font.Gotham,
    TextColor3 = Color3.new(1, 1, 1),
    BackgroundColor3 = Color3.fromRGB(54, 48, 75),
    BorderSizePixel = 0
}, header)
round(close, 8)

local status = make("TextLabel", {
    Position = UDim2.fromOffset(15, 72),
    Size = UDim2.new(1, -30, 0, 24),
    BackgroundColor3 = Color3.fromRGB(28, 31, 43),
    Text = "●  SYSTEM READY",
    TextColor3 = Color3.fromRGB(105, 235, 160),
    Font = Enum.Font.GothamMedium,
    TextSize = 11,
    BorderSizePixel = 0
}, panel)
round(status, 7)

local function setStatus(text, color)
    status.Text = "●  " .. text
    status.TextColor3 = color
end

local function makeToggle(label, key, y)
    local row = make("Frame", {
        Position = UDim2.fromOffset(14, y),
        Size = UDim2.new(1, -28, 0, 43),
        BackgroundColor3 = Color3.fromRGB(27, 30, 42),
        BorderSizePixel = 0
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
        TextXAlignment = Enum.TextXAlignment.Left
    }, row)

    local button = make("TextButton", {
        Position = UDim2.new(1, -60, 0.5, -12),
        Size = UDim2.fromOffset(48, 24),
        Text = "",
        BackgroundColor3 = Color3.fromRGB(68, 70, 84),
        BorderSizePixel = 0
    }, row)
    round(button, 12)

    local knob = make("Frame", {
        Position = UDim2.fromOffset(3, 3),
        Size = UDim2.fromOffset(18, 18),
        BackgroundColor3 = Color3.new(1, 1, 1),
        BorderSizePixel = 0
    }, button)
    round(knob, 10)

    local function refresh()
        local enabled = config[key]
        button.BackgroundColor3 = enabled
            and Color3.fromRGB(127, 87, 255)
            or Color3.fromRGB(68, 70, 84)
        knob.Position = enabled
            and UDim2.new(1, -21, 0, 3)
            or UDim2.fromOffset(3, 3)
    end

    button.Activated:Connect(function()
        config[key] = not config[key]
        refresh()
        saveConfig()
        setStatus(label .. (config[key] and " ENABLED" or " DISABLED"),
            config[key]
                and Color3.fromRGB(105, 235, 160)
                or Color3.fromRGB(190, 190, 205))
    end)

    refresh()
end

makeToggle("Auto Rejoin", "AutoRejoin", 108)
makeToggle("Auto Execute", "AutoExecute", 158)
makeToggle("Anti AFK", "AntiAFK", 208)

local function makeAction(text, x, width, callback)
    local button = make("TextButton", {
        Position = UDim2.fromOffset(x, 267),
        Size = UDim2.fromOffset(width, 30),
        BackgroundColor3 = Color3.fromRGB(44, 39, 67),
        Text = text,
        TextColor3 = Color3.fromRGB(235, 230, 255),
        Font = Enum.Font.GothamMedium,
        TextSize = 10,
        BorderSizePixel = 0
    }, panel)
    round(button, 8)
    button.Activated:Connect(callback)
end

makeAction("Fake Rejoin", 14, 132, function()
    setStatus("TESTING REJOIN...", Color3.fromRGB(255, 205, 100))
    rejoining = false
    rejoin()
end)

makeAction("Fake Kick", 154, 132, function()
    setStatus("TESTING KICK...", Color3.fromRGB(255, 130, 130))
    task.wait(0.3)
    player:Kick("Rage Rejoin Hub test kick")
    -- This script cannot run after the client has been kicked.
end)

make("TextLabel", {
    Position = UDim2.fromOffset(14, 306),
    Size = UDim2.new(1, -28, 0, 22),
    BackgroundTransparency = 1,
    Text = "Settings save automatically when supported",
    TextColor3 = Color3.fromRGB(142, 145, 163),
    Font = Enum.Font.Gotham,
    TextSize = 9
}, panel)

-- Floating draggable circle
local orb = make("TextButton", {
    Name = "FloatingButton",
    Position = UDim2.new(0, 20, 0.45, 0),
    Size = UDim2.fromOffset(54, 54),
    BackgroundColor3 = Color3.fromRGB(105, 65, 255),
    Text = "R",
    TextColor3 = Color3.new(1, 1, 1),
    TextSize = 24,
    Font = Enum.Font.GothamBlack,
    BorderSizePixel = 0,
    AutoButtonColor = true
}, gui)
round(orb, 30)
stroke(orb, Color3.fromRGB(195, 174, 255), 2)

local dragging = false
local dragStart
local startPosition
local moved = false

orb.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        moved = false
        dragStart = input.Position
        startPosition = orb.Position

        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then
                dragging = false
            end
        end)
    end
end)

game:GetService("UserInputService").InputChanged:Connect(function(input)
    if not dragging then return end
    if input.UserInputType ~= Enum.UserInputType.MouseMovement
        and input.UserInputType ~= Enum.UserInputType.Touch then
        return
    end

    local delta = input.Position - dragStart
    if math.abs(delta.X) > 5 or math.abs(delta.Y) > 5 then
        moved = true
    end

    orb.Position = UDim2.new(
        startPosition.X.Scale,
        startPosition.X.Offset + delta.X,
        startPosition.Y.Scale,
        startPosition.Y.Offset + delta.Y
    )
end)

orb.Activated:Connect(function()
    if moved then return end
    panel.Visible = not panel.Visible
end)

close.Activated:Connect(function()
    panel.Visible = false
end)

-- Anti-AFK: uses VirtualUser when supported by the environment.
player.Idled:Connect(function()
    if not config.AntiAFK then return end

    pcall(function()
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new(0, 0))
    end)
end)

-- Rejoin when the client reports a failed teleport.
TeleportService.TeleportInitFailed:Connect(function(
    teleportPlayer,
    result,
    errorMessage
)
    if teleportPlayer ~= player or not config.AutoRejoin then
        return
    end

    warn("[Rage Rejoin] Teleport failed:", result, errorMessage)
    rejoining = false

    task.delay(3, function()
        if config.AutoRejoin then
            rejoin()
        end
    end)
end)

saveConfig()
print("[Rage Rejoin Hub] Loaded successfully.")
