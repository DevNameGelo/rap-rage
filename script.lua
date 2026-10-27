-- RGC | Rage Gen Core | DevNameGelo
-- File path in repo: script.lua (root)
-- Features (always ON, no toggles): Auto Execute, Auto Rejoin, Anti-AFK
-- Manual buttons: Rejoin, Fake Kick (test)

if not game:IsLoaded() then game.Loaded:Wait() end

local genv = (getgenv and getgenv()) or _G
if genv.RGC_AUTO_LOADED then return end
genv.RGC_AUTO_LOADED = true

local SCRIPT_URL = "https://raw.githubusercontent.com/DevNameGelo/rap-rage/refs/heads/main/script.lua"

local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local GuiService = game:GetService("GuiService")
local CoreGui = game:GetService("CoreGui")
local VirtualUser = game:GetService("VirtualUser")
local UserInputService = game:GetService("UserInputService")

local LP = Players.LocalPlayer
while not LP do
	Players:GetPropertyChangedSignal("LocalPlayer"):Wait()
	LP = Players.LocalPlayer
end

----------------------------------------------------------------
-- GUI
----------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "RGC_AutoRejoin"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 999
pcall(function()
	if syn and syn.protect_gui then syn.protect_gui(gui) end
end)
local okParent = pcall(function()
	gui.Parent = (gethui and gethui()) or CoreGui
end)
if not okParent or not gui.Parent then
	gui.Parent = LP:WaitForChild("PlayerGui")
end

local main = Instance.new("Frame")
main.Size = UDim2.new(0, 230, 0, 214)
main.Position = UDim2.new(0, 12, 0.5, -107)
main.BackgroundColor3 = Color3.fromRGB(18, 18, 24)
main.BorderSizePixel = 0
main.Active = true
main.Parent = gui
Instance.new("UICorner", main).CornerRadius = UDim.new(0, 10)
local stroke = Instance.new("UIStroke", main)
stroke.Color = Color3.fromRGB(255, 60, 80)
stroke.Thickness = 1.5

local function label(text, y, size, color, font)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Position = UDim2.new(0, 12, 0, y)
	l.Size = UDim2.new(1, -24, 0, size)
	l.Text = text
	l.TextColor3 = color or Color3.fromRGB(235, 235, 240)
	l.Font = font or Enum.Font.GothamMedium
	l.TextSize = 13
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Parent = main
	return l
end

label("RGC | Rage Gen Core", 8, 20, Color3.fromRGB(255, 70, 90), Enum.Font.GothamBold)

local green = Color3.fromRGB(70, 230, 120)
local function featureRow(name, y)
	local l = label(name, y, 18)
	local s = Instance.new("TextLabel")
	s.BackgroundTransparency = 1
	s.Position = UDim2.new(1, -62, 0, y)
	s.Size = UDim2.new(0, 50, 0, 18)
	s.Text = "ON"
	s.TextColor3 = green
	s.Font = Enum.Font.GothamBold
	s.TextSize = 13
	s.TextXAlignment = Enum.TextXAlignment.Right
	s.Parent = main
end
featureRow("Auto Execute", 36)
featureRow("Auto Rejoin", 56)
featureRow("Anti-AFK", 76)

local statusLabel = label("Status: Active", 100, 32, Color3.fromRGB(170, 170, 185), Enum.Font.Gotham)
statusLabel.TextWrapped = true
statusLabel.TextYAlignment = Enum.TextYAlignment.Top
statusLabel.TextSize = 12

local function setStatus(text)
	statusLabel.Text = "Status: " .. tostring(text)
end

local function button(text, y, color)
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(1, -24, 0, 32)
	b.Position = UDim2.new(0, 12, 0, y)
	b.BackgroundColor3 = color
	b.Text = text
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Font = Enum.Font.GothamBold
	b.TextSize = 14
	b.AutoButtonColor = true
	b.Parent = main
	Instance.new("UICorner", b).CornerRadius = UDim.new(0, 8)
	return b
end

local rejoinBtn = button("Rejoin", 138, Color3.fromRGB(50, 110, 220))
local fakeKickBtn = button("Fake Kick (Test)", 174, Color3.fromRGB(210, 60, 70))

-- Drag (mouse + touch)
do
	local dragging, dragStart, startPos
	main.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			dragStart = input.Position
			startPos = main.Position
			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then dragging = false end
			end)
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch) then
			local d = input.Position - dragStart
			main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X,
				startPos.Y.Scale, startPos.Y.Offset + d.Y)
		end
	end)
end

----------------------------------------------------------------
-- 1) AUTO EXECUTE (re-runs this script after every teleport/rejoin)
----------------------------------------------------------------
local queueFn = queue_on_teleport
	or (syn and syn.queue_on_teleport)
	or (fluxus and fluxus.queue_on_teleport)
	or (http and http.queue_on_teleport)

local QUEUE_CODE = 'loadstring(game:HttpGet("' .. SCRIPT_URL .. '"))()'

local function queueScript()
	if queueFn then
		pcall(queueFn, QUEUE_CODE)
	end
end

queueScript()

local teleporting = false
LP.OnTeleport:Connect(function(state)
	if state == Enum.TeleportState.Started or state == Enum.TeleportState.InProgress then
		teleporting = true
		queueScript()
		task.delay(25, function() teleporting = false end)
	end
end)

----------------------------------------------------------------
-- 2) AUTO REJOIN (disconnect / kick / any error)
----------------------------------------------------------------
local rejoining = false

local function doRejoin(reason)
	if rejoining then return end
	rejoining = true
	setStatus("Rejoining (" .. tostring(reason) .. ")")
	queueScript()

	task.spawn(function()
		local attempt = 0
		while true do
			attempt += 1
			pcall(function()
				if #Players:GetPlayers() <= 1 then
					-- Alone in server: hop to a fresh one of the same place
					TeleportService:Teleport(game.PlaceId, LP)
				elseif attempt % 3 == 0 then
					-- Same-server join keeps failing (full/closed): fall back to any server
					TeleportService:Teleport(game.PlaceId, LP)
				else
					TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LP)
				end
			end)
			task.wait(8)
			setStatus("Retrying rejoin... (#" .. attempt .. ")")
		end
	end)
end

-- Automatic detection (ignored while a normal teleport is happening)
local function onDisconnect(reason)
	if teleporting then return end
	doRejoin(reason)
end

TeleportService.TeleportInitFailed:Connect(function()
	-- the retry loop above handles it
	if rejoining then setStatus("Teleport failed, retrying...") end
end)

GuiService.ErrorMessageChanged:Connect(function(msg)
	if msg and msg ~= "" then
		onDisconnect(msg)
	end
end)

task.spawn(function()
	local ok, overlay = pcall(function()
		return CoreGui:WaitForChild("RobloxPromptGui", 30):WaitForChild("promptOverlay", 30)
	end)
	if ok and overlay then
		overlay.ChildAdded:Connect(function(child)
			if child.Name == "ErrorPrompt" then
				task.wait(0.3)
				onDisconnect("Error prompt")
			end
		end)
		if overlay:FindFirstChild("ErrorPrompt") then
			onDisconnect("Error prompt")
		end
	end
end)

pcall(function()
	game:GetService("NetworkClient").ChildRemoved:Connect(function()
		onDisconnect("Connection lost")
	end)
end)

----------------------------------------------------------------
-- 3) ANTI-AFK
----------------------------------------------------------------
pcall(function()
	if getconnections then
		for _, c in ipairs(getconnections(LP.Idled)) do
			pcall(function() c:Disable() end)
		end
	end
end)

local function antiAfkPulse()
	pcall(function()
		VirtualUser:CaptureController()
		VirtualUser:ClickButton2(Vector2.new())
	end)
end

LP.Idled:Connect(antiAfkPulse)

task.spawn(function()
	while true do
		task.wait(55)
		antiAfkPulse()
	end
end)

----------------------------------------------------------------
-- MANUAL BUTTONS
----------------------------------------------------------------
rejoinBtn.MouseButton1Click:Connect(function()
	doRejoin("Manual")
end)

fakeKickBtn.MouseButton1Click:Connect(function()
	if rejoining then return end
	setStatus("Fake kick! Rejoining in 3s...")
	task.wait(3)
	-- Same path a real kick/disconnect takes
	onDisconnect("Fake kick test")
end)

setStatus("Active" .. (queueFn and "" or " (no queue_on_teleport support)"))
