--[[
    RAGE REJOIN HUB v3 (Rayfield)
    Auto Rejoin | Auto Execute | Anti AFK
]]

local env = (getgenv and getgenv()) or _G
if env.__RageRejoinHub and type(env.__RageRejoinHub.Destroy) == "function" then
    pcall(env.__RageRejoinHub.Destroy)
end

if not game:IsLoaded() then
    game.Loaded:Wait()
end

local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local VirtualUser = game:GetService("VirtualUser")
local GuiService = game:GetService("GuiService")

local player = Players.LocalPlayer
while not player do
    Players:GetPropertyChangedSignal("LocalPlayer"):Wait()
    player = Players.LocalPlayer
end

local SETTINGS = {
    ScriptUrl = "https://raw.githubusercontent.com/DevNameGelo/rap-rage/refs/heads/main/script.lua",
    RetryDelay = 3,
    MaxAttempts = 5,
    AttemptWait = 12,
}

local config = {
    AutoRejoin = true,
    AutoExecute = false,
    AntiAFK = false,
}

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
-- Load Rayfield
---------------------------------------------------------------------
local okLib, Rayfield = pcall(function()
    return loadstring(game:HttpGet("https://sirius.menu/rayfield"))()
end)

if not okLib or not Rayfield then
    warn("[Rage Rejoin] Failed to load Rayfield:", Rayfield)
    return
end

local Window = Rayfield:CreateWindow({
    Name = "RAGE REJOIN",
    LoadingTitle = "Rage Rejoin Hub",
    LoadingSubtitle = "by DevNameGelo",
    DisableRayfieldPrompts = true,
    DisableBuildWarnings = true,
    ConfigurationSaving = {
        Enabled = true,
        FolderName = "RageRejoinHub",
        FileName = "Config",
    },
    KeySystem = false,
})

local Tab = Window:CreateTab("Main", 4483362458)
local StatusLabel = Tab:CreateLabel("● System ready")

local function setStatus(text)
    if destroyed then return end
    pcall(function()
        StatusLabel:Set("● " .. text)
    end)
end

local function notify(title, content)
    if destroyed then return end
    pcall(function()
        Rayfield:Notify({ Title = title, Content = content, Duration = 4 })
    end)
end

---------------------------------------------------------------------
-- Queue script on teleport
---------------------------------------------------------------------
local function queueScript()
    if queued or not config.AutoExecute or type(queueTeleport) ~= "function" then
        return
    end

    local source = string.format('loadstring(game:HttpGet("%s"))()', SETTINGS.ScriptUrl)
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

            setStatus(string.format("Rejoin %d/%d", attempt, SETTINGS.MaxAttempts))
            task.wait(SETTINGS.RetryDelay * attempt)

            if requestTeleport() then
                task.wait(SETTINGS.AttemptWait)
            end
        end

        if not destroyed then
            setStatus("Rejoin stopped")
        end
        handling = false
    end)
end

---------------------------------------------------------------------
-- UI controls
---------------------------------------------------------------------
Tab:CreateToggle({
    Name = "Auto Rejoin",
    CurrentValue = config.AutoRejoin,
    Flag = "AutoRejoin",
    Callback = function(value)
        config.AutoRejoin = value
        setStatus("Auto Rejoin " .. (value and "enabled" or "disabled"))
    end,
})

Tab:CreateToggle({
    Name = "Auto Execute",
    CurrentValue = config.AutoExecute,
    Flag = "AutoExecute",
    Callback = function(value)
        config.AutoExecute = value
        if not value then queued = false end
        setStatus("Auto Execute " .. (value and "enabled" or "disabled"))
    end,
})

Tab:CreateToggle({
    Name = "Anti AFK",
    CurrentValue = config.AntiAFK,
    Flag = "AntiAFK",
    Callback = function(value)
        config.AntiAFK = value
        setStatus("Anti AFK " .. (value and "enabled" or "disabled"))
    end,
})

Tab:CreateButton({
    Name = "Test Rejoin",
    Callback = function()
        if handling then return end
        setStatus("Testing rejoin...")
        task.spawn(function()
            if not requestTeleport() then
                setStatus("Teleport failed")
                notify("Rage Rejoin", "Teleport request failed.")
            end
        end)
    end,
})

Tab:CreateButton({
    Name = "Test Kick",
    Callback = function()
        setStatus("Testing kick...")
        task.delay(0.3, function()
            pcall(function()
                player:Kick("Rage Rejoin Hub test kick")
            end)
        end)
    end,
})

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
    setStatus("Teleport failed")
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
    pcall(function() Rayfield:Destroy() end)
    env.__RageRejoinHub = nil
end

env.__RageRejoinHub = { Destroy = destroy }

-- Apply saved toggle values (callbacks sync `config`)
pcall(function() Rayfield:LoadConfiguration() end)

setStatus("System ready")
print("[Rage Rejoin Hub] Loaded successfully.")