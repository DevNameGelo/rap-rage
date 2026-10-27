-- RGC | Rage Gen Core | DevNameGelo
-- Always ON: Auto Execute, Auto Rejoin, Anti-AFK, Watchdog (no toggles)
-- UI: Rage Hub library | "x" = circle | "Hide All" = hide everything, /open to show

if not game:IsLoaded() then game.Loaded:Wait() end

local genv = (getgenv and getgenv()) or _G
if genv.RGC_AUTO_LOADED then return end
genv.RGC_AUTO_LOADED = true

local SCRIPT_URL = "https://raw.githubusercontent.com/DevNameGelo/rap-rage/refs/heads/main/script.lua"
local LIB_URL = "https://raw.githubusercontent.com/devnamegelo/Rage-Hub/main/RageHub.lua"
local SAVE_FILE = "RGC_AutoRejoin.json"

local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local GuiService = game:GetService("GuiService")
local CoreGui = game:GetService("CoreGui")
local VirtualUser = game:GetService("VirtualUser")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

local LP = Players.LocalPlayer
while not LP do
	Players:GetPropertyChangedSignal("LocalPlayer"):Wait()
	LP = Players.LocalPlayer
end

----------------------------------------------------------------
-- UI hooks (filled in after the library loads)
----------------------------------------------------------------
local win, statusLabel, statsLabel

local function setStatus(text)
	if statusLabel then
		pcall(function() statusLabel:Set("Status: " .. tostring(text)) end)
	end
end

local function notify(title, content, kind)
	if win then
		pcall(function()
			win:Notify({ Title = title, Content = content or "", Type = kind or "info", Duration = 4 })
		end)
	end
end

----------------------------------------------------------------
-- SAVE (rejoin counter survives rejoins)
----------------------------------------------------------------
local save = { count = 0, pending = false }

pcall(function()
	if isfile and readfile and isfile(SAVE_FILE) then
		local d = HttpService:JSONDecode(readfile(SAVE_FILE))
		if type(d) == "table" then save = d end
	end
end)

local function writeSave()
	pcall(function()
		if writefile then writefile(SAVE_FILE, HttpService:JSONEncode(save)) end
	end)
end

if save.pending then
	save.count = (save.count or 0) + 1
	save.pending = false
	writeSave()
end

----------------------------------------------------------------
-- 1) AUTO EXECUTE
----------------------------------------------------------------
local queueFn = queue_on_teleport
	or (syn and syn.queue_on_teleport)
	or (fluxus and fluxus.queue_on_teleport)
	or (http and http.queue_on_teleport)

local QUEUE_CODE = 'loadstring(game:HttpGet("' .. SCRIPT_URL .. '"))()'

local function queueScript()
	if queueFn then pcall(queueFn, QUEUE_CODE) end
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
-- 2) AUTO REJOIN
----------------------------------------------------------------
local rejoining = false

local function doRejoin(reason)
	if rejoining then return end
	rejoining = true
	setStatus("Rejoining (" .. tostring(reason) .. ")")
	notify("Rejoining", tostring(reason), "warning")
	queueScript()
	save.pending = true
	writeSave()

	task.spawn(function()
		local attempt = 0
		while true do
			attempt += 1
			pcall(function()
				if #Players:GetPlayers() <= 1 or attempt % 3 == 0 then
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

local function onDisconnect(reason)
	if teleporting then return end
	doRejoin(reason)
end

TeleportService.TeleportInitFailed:Connect(function()
	if rejoining then setStatus("Teleport failed, retrying...") end
end)

GuiService.ErrorMessageChanged:Connect(function(msg)
	if msg and msg ~= "" then onDisconnect(msg) end
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
-- 4) WATCHDOG (removed from game / stuck with no character)
----------------------------------------------------------------
LP.AncestryChanged:Connect(function(_, parent)
	if not parent then onDisconnect("Removed from game") end
end)

task.spawn(function()
	local noChar = 0
	while true do
		task.wait(5)
		if LP.Parent == nil then
			onDisconnect("Removed from game")
		end
		if LP.Character and LP.Character:FindFirstChild("HumanoidRootPart") then
			noChar = 0
		else
			noChar += 5
			if noChar >= 90 then
				noChar = 0
				onDisconnect("Stuck: no character")
			end
		end
	end
end)

----------------------------------------------------------------
-- LOW POWER
----------------------------------------------------------------
local function setLowPower(on)
	pcall(function() RunService:Set3dRenderingEnabled(not on) end)
	pcall(function() if setfpscap then setfpscap(on and 15 or 60) end end)
	pcall(function()
		settings().Rendering.QualityLevel = on and Enum.QualityLevel.Level01 or Enum.QualityLevel.Automatic
	end)
end

----------------------------------------------------------------
-- UI (Rage Hub)
----------------------------------------------------------------
local okLib, RageHub = pcall(function()
	return loadstring(game:HttpGet(LIB_URL))()
end)

if not okLib or type(RageHub) ~= "table" then
	warn("[RGC] Rage Hub failed to load, running without UI: " .. tostring(RageHub))
	return
end

win = RageHub:CreateWindow({
	Name = "RGC Auto Rejoin",
	Subtitle = "DevNameGelo | Rage Gen Core",
	Theme = "Crimson",
	Width = 460,
	Height = 340,
	Launcher = true,
	Search = false,
	Splash = { Title = "RGC Auto Rejoin", Subtitle = "Loading...", Duration = 0.8 },
})

local main = win:CreateTab("Main", "⚡")

local core = main:CreateSection("Always On")
local green = Color3.fromRGB(52, 211, 153)
core:CreateLabel("Auto Execute  |  ON"):Set("Auto Execute  |  ON" .. (queueFn and "" or " (no queue_on_teleport)"), green)
core:CreateLabel("Auto Rejoin  |  ON"):Set("Auto Rejoin  |  ON", green)
core:CreateLabel("Anti-AFK  |  ON"):Set("Anti-AFK  |  ON", green)
core:CreateLabel("Watchdog  |  ON"):Set("Watchdog  |  ON", green)

local info = main:CreateSection("Info")
statsLabel = info:CreateLabel("Uptime 00:00:00  |  Rejoins 0")
statusLabel = info:CreateLabel("Status: Active")

local ctl = main:CreateSection("Controls")

ctl:CreateButton({
	Name = "Rejoin",
	Description = "Rejoin the game now",
	ButtonText = "Rejoin",
	Callback = function()
		doRejoin("Manual")
	end,
})

ctl:CreateButton({
	Name = "Fake Kick (Test)",
	Description = "Simulates a kick to test auto rejoin",
	ButtonText = "Test",
	Callback = function()
		if rejoining then return end
		setStatus("Fake kick! Rejoining in 3s...")
		notify("Fake kick", "Rejoining in 3s...", "error")
		task.spawn(function()
			task.wait(3)
			onDisconnect("Fake kick test")
		end)
	end,
})

ctl:CreateToggle({
	Name = "Low Power Mode",
	Description = "3D off, low quality, 15 FPS (saves battery)",
	Default = false,
	Callback = function(on)
		setLowPower(on)
	end,
})

local function showPanel()
	if win._launcher then win._launcher.Visible = true end
	win:SetVisible(true)
end

ctl:CreateButton({
	Name = "Minimize to Circle",
	Description = "Tap the R circle to reopen (drag it anywhere)",
	ButtonText = "Hide",
	Callback = function()
		win:SetVisible(false)
	end,
})

ctl:CreateButton({
	Name = "Hide All",
	Description = "Hides window and circle. Type /open in chat to show",
	ButtonText = "Hide",
	Callback = function()
		win:SetVisible(false)
		if win._launcher then win._launcher.Visible = false end
		notify("Hidden", "Type /open in chat to show again.", "info")
	end,
})

win:CreateSettingsTab("Settings")

-- /open command (new TextChatService + legacy chat)
pcall(function()
	local TCS = game:GetService("TextChatService")
	local cmd = Instance.new("TextChatCommand")
	cmd.Name = "RGCOpenCommand"
	cmd.PrimaryAlias = "/open"
	cmd.SecondaryAlias = "/rgc"
	cmd.Parent = TCS
	cmd.Triggered:Connect(showPanel)
end)

LP.Chatted:Connect(function(msg)
	msg = string.lower((tostring(msg):gsub("^%s+", ""):gsub("%s+$", "")))
	if msg == "/open" or msg == "/rgc" then
		showPanel()
	end
end)

-- Uptime + rejoin counter
local startTime = os.time()
task.spawn(function()
	while true do
		local t = os.time() - startTime
		pcall(function()
			statsLabel:Set(string.format("Uptime %02d:%02d:%02d  |  Rejoins %d",
				math.floor(t / 3600), math.floor(t / 60) % 60, t % 60, save.count or 0))
		end)
		task.wait(1)
	end
end)

setStatus("Active")