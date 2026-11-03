print("[Rage Hub Dev] Beta loaded")
-- Rage Hub Dev | Beta | DevNameGelo
-- Creator Store browser + saved collections + AI assistant (chat, coding, script fixing)
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local UIS = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local SoundService = game:GetService("SoundService")

-- ===== Parent / cleanup =====
local parentGui
if gethui then
	parentGui = gethui()
elseif pcall(function() return game:GetService("CoreGui").Name end) then
	parentGui = game:GetService("CoreGui")
else
	parentGui = Players.LocalPlayer:WaitForChild("PlayerGui")
end
for _, nm in ipairs({"RageHubDev", "RGC_CreatorStore"}) do
	local old = parentGui:FindFirstChild(nm)
	if old then old:Destroy() end
end
local oldSnd = SoundService:FindFirstChild("RGC_CS_Sound")
if oldSnd then oldSnd:Destroy() end

-- ===== Config =====
local CATS = {
	{name = "Models",     id = 10},
	{name = "Images",     id = 13},
	{name = "Sound FX",   id = 3},
	{name = "Music",      id = 300},
	{name = "Plugins",    id = 38},
	{name = "Meshes",     id = 40},
	{name = "Animations", id = 24},
	{name = "Video",      id = 62},
	{name = "Fonts",      id = 73},
}
local TYPE_NAMES = {[1]="Image",[3]="Sound FX",[4]="Mesh",[10]="Model",[13]="Decal",[24]="Animation",[38]="Plugin",[40]="MeshPart",[62]="Video",[73]="Font",[300]="Music"}
local TYPE_ICONS = {[1]="IMAGE",[3]="SFX",[4]="MESH",[10]="MODEL",[13]="DECAL",[24]="ANIM",[38]="PLUGIN",[40]="MESH",[62]="VIDEO",[73]="FONT",[300]="MUSIC"}
local PAGE_SIZE = 30
local FILE = "RGC_CreatorStore.json"
-- Legacy compatibility fallback only; Roblox now recommends the v2 POST search below.
local MARKET = "https://apis.roblox.com/toolbox-service/v1/marketplace/"
local DETAILS = "https://apis.roblox.com/toolbox-service/v1/items/details?assetIds="

local C = {
	-- Deep navy + electric cyan/violet glass palette
	bg = Color3.fromRGB(11, 16, 30),
	bar = Color3.fromRGB(22, 33, 58),
	card = Color3.fromRGB(34, 50, 82),
	accent = Color3.fromRGB(70, 170, 255),
	accent2 = Color3.fromRGB(150, 110, 255),
	text = Color3.fromRGB(240, 247, 255),
	sub = Color3.fromRGB(160, 182, 210),
	good = Color3.fromRGB(70, 210, 160),
	bad = Color3.fromRGB(240, 90, 110),
	warn = Color3.fromRGB(255, 190, 90),
}

local function isAudio(t) return t == 3 or t == 300 end

-- ===== Saved data (favorites, collections, recent, settings) =====
local db = {favs = {}, cols = {"Default"}, recent = {}, set = {}}

local function loadDB()
	if not (isfile and readfile) then return end
	local ok, txt = pcall(function()
		if isfile(FILE) then return readfile(FILE) end
	end)
	if not (ok and txt) then return end
	local ok2, d = pcall(HttpService.JSONDecode, HttpService, txt)
	if ok2 and type(d) == "table" then
		db.favs = d.favs or {}
		db.cols = (d.cols and #d.cols > 0) and d.cols or {"Default"}
		db.recent = d.recent or {}
		db.set = d.set or {}
	end
end

local saveQueued = false
local function saveDB()
	if not writefile or saveQueued then return end
	saveQueued = true
	task.delay(0.5, function()
		saveQueued = false
		pcall(writefile, FILE, HttpService:JSONEncode(db))
	end)
end
loadDB()

-- ===== HTTP / clipboard / utils =====
local function doRequest(opts)
	local req = (syn and syn.request) or http_request or request or (fluxus and fluxus.request)
	if not req then return nil end
	local ok, res = pcall(req, opts)
	if ok and type(res) == "table" then return res end
	return nil
end

local function httpGet(url)
	local res = doRequest({Url = url, Method = "GET"})
	if res and res.Body and (res.Success or res.StatusCode == 200) then return res.Body end
	local ok, body = pcall(function() return game:HttpGet(url) end)
	if ok then return body end
	return nil
end

local function getJSON(url)
	local body = httpGet(url)
	if not body then return nil end
	local ok, data = pcall(HttpService.JSONDecode, HttpService, body)
	if ok then return data end
	return nil
end

local function getJSONWithHeaders(url, headers)
	local res = doRequest({Url = url, Method = "GET", Headers = headers or {}})
	if not res or not res.Body or not (res.Success or res.StatusCode == 200) then
		return nil, res
	end
	local ok, data = pcall(HttpService.JSONDecode, HttpService, res.Body)
	if ok then return data, res end
	return nil, res
end

local function postJSONWithHeaders(url, headers, payload)
	local requestHeaders = {}
	for k, v in pairs(headers or {}) do requestHeaders[k] = v end
	requestHeaders["Content-Type"] = "application/json"
	local okEncode, body = pcall(HttpService.JSONEncode, HttpService, payload or {})
	if not okEncode then return nil, nil end
	local res = doRequest({Url = url, Method = "POST", Headers = requestHeaders, Body = body})
	if not res or not res.Body or not (res.Success or res.StatusCode == 200) then
		return nil, res
	end
	local ok, data = pcall(HttpService.JSONDecode, HttpService, res.Body)
	if ok then return data, res end
	return nil, res
end

local function copy(text)
	local f = setclipboard or toclipboard or set_clipboard or (Clipboard and Clipboard.set)
	if f then return (pcall(f, tostring(text))) end
	return false
end

local function trim(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end

-- ===== UI helpers (glass style) =====
local function new(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props) do o[k] = v end
	if parent then o.Parent = parent end
	return o
end
local function round(o, r)
	new("UICorner", {CornerRadius = UDim.new(0, r or 10)}, o)
	if o:IsA("GuiObject") and o.BackgroundTransparency < 0.15 then
		o.BackgroundTransparency = 0.2
	end
	if not o:FindFirstChildOfClass("UIStroke") then
		new("UIStroke", {Color = Color3.fromRGB(190, 220, 255), Thickness = 1, Transparency = 0.84, ApplyStrokeMode = Enum.ApplyStrokeMode.Border}, o)
	end
	return o
end
local function sheen(o, rot)
	new("UIGradient", {
		Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(205, 215, 235)),
		Rotation = rot or 90,
	}, o)
end
local function btn(parent, text, size, pos, color, ts)
	local b = round(new("TextButton", {
		Size = size, Position = pos or UDim2.new(), BackgroundColor3 = color or C.card, Text = text,
		TextColor3 = C.text, Font = Enum.Font.GothamBold, TextSize = ts or 12, AutoButtonColor = true,
		TextTruncate = Enum.TextTruncate.AtEnd, BorderSizePixel = 0,
	}, parent), 9)
	sheen(b)
	return b
end
local function box(parent, placeholder, size, pos, multiline)
	local b = round(new("TextBox", {
		Size = size, Position = pos or UDim2.new(), BackgroundColor3 = Color3.fromRGB(8, 12, 24), BackgroundTransparency = 0.3,
		Text = "", PlaceholderText = placeholder, PlaceholderColor3 = C.sub, TextColor3 = C.text,
		Font = Enum.Font.Gotham, TextSize = 13, ClearTextOnFocus = false, BorderSizePixel = 0,
		TextXAlignment = Enum.TextXAlignment.Left, MultiLine = multiline or false,
		TextWrapped = multiline or false, TextYAlignment = multiline and Enum.TextYAlignment.Top or Enum.TextYAlignment.Center,
	}, parent), 9)
	b.BackgroundTransparency = 0.3
	new("UIPadding", {PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), PaddingTop = UDim.new(0, multiline and 6 or 0)}, b)
	local st = b:FindFirstChildOfClass("UIStroke")
	if st then
		b.Focused:Connect(function()
			st.Color = C.accent
			TweenService:Create(st, TweenInfo.new(0.15), {Transparency = 0.1}):Play()
		end)
		b.FocusLost:Connect(function()
			st.Color = Color3.fromRGB(190, 220, 255)
			TweenService:Create(st, TweenInfo.new(0.15), {Transparency = 0.84}):Play()
		end)
	end
	return b
end
local function label(parent, text, size, pos, color, ts, font)
	return new("TextLabel", {
		Size = size, Position = pos or UDim2.new(), BackgroundTransparency = 1, Text = text,
		TextColor3 = color or C.text, Font = font or Enum.Font.Gotham, TextSize = ts or 12,
		TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true, BorderSizePixel = 0,
	}, parent)
end
local function clearGui(container)
	for _, c in ipairs(container:GetChildren()) do
		if c:IsA("GuiObject") then c:Destroy() end
	end
end
local function hscroll(parent, size, pos)
	local s = new("ScrollingFrame", {
		Size = size, Position = pos, BackgroundTransparency = 1, ScrollBarThickness = 0,
		BorderSizePixel = 0, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.X,
		ScrollingDirection = Enum.ScrollingDirection.X,
	}, parent)
	new("UIListLayout", {FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, VerticalAlignment = Enum.VerticalAlignment.Center}, s)
	return s
end
local function vscroll(parent, size, pos)
	return new("ScrollingFrame", {
		Size = size, Position = pos, BackgroundTransparency = 1, ScrollBarThickness = 3,
		ScrollBarImageColor3 = C.accent, ScrollBarImageTransparency = 0.3, BorderSizePixel = 0, CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
	}, parent)
end

local grids = {}
local function makeGrid(parent, pos, size)
	local sc = vscroll(parent, size, pos)
	local g = new("UIGridLayout", {
		CellPadding = UDim2.fromOffset(8, 8), CellSize = UDim2.fromOffset(100, 140),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, sc)
	table.insert(grids, g)
	return sc, g
end

local function makeCell(parent, id, name, typeId, order)
	local cell = round(new("TextButton", {
		BackgroundColor3 = C.card, Text = "", AutoButtonColor = false, LayoutOrder = order, BorderSizePixel = 0,
	}, parent), 12)
	new("UIStroke", {Name = "Sel", Color = C.accent, Thickness = 2, Enabled = false, ApplyStrokeMode = Enum.ApplyStrokeMode.Border}, cell)
	local holder = round(new("Frame", {
		Size = UDim2.new(1, -8, 1, -48), Position = UDim2.fromOffset(4, 4),
		BackgroundColor3 = C.bar, ClipsDescendants = true, BorderSizePixel = 0,
	}, cell), 9)
	new("TextLabel", {
		Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = TYPE_ICONS[typeId] or "ASSET",
		TextColor3 = C.sub, TextSize = 11, Font = Enum.Font.GothamBold,
	}, holder)
	new("ImageLabel", {
		Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ScaleType = Enum.ScaleType.Fit,
		Image = "rbxthumb://type=Asset&id=" .. tostring(id) .. "&w=150&h=150",
	}, holder)
	new("TextLabel", {
		Size = UDim2.new(1, -8, 0, 26), Position = UDim2.new(0, 4, 1, -42),
		BackgroundTransparency = 1, Text = name or ("Asset " .. tostring(id)),
		TextColor3 = C.text, Font = Enum.Font.GothamMedium, TextSize = 11,
		TextWrapped = true, TextTruncate = Enum.TextTruncate.AtEnd,
		TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
	}, cell)
	new("TextLabel", {
		Size = UDim2.new(1, -8, 0, 14), Position = UDim2.new(0, 4, 1, -16),
		BackgroundTransparency = 1, Text = "ID " .. tostring(id), TextColor3 = C.accent,
		Font = Enum.Font.Code, TextSize = 10, TextXAlignment = Enum.TextXAlignment.Left,
	}, cell)
	return cell
end

-- ===== Vector icons (drawn with frames, no emoji) =====
local function makeIcon(name, parent, px, color)
	color = color or C.text
	local root = new("Frame", {Name = "Icon_" .. name, BackgroundTransparency = 1, Size = UDim2.fromOffset(px, px), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5)}, parent)
	local th = math.max(1.5, px / 11)
	local lineTh = th * 24 / px
	local L = {}
	function L.line(x1, y1, x2, y2)
		local dx, dy = x2 - x1, y2 - y1
		local f = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale((x1 + x2) / 48, (y1 + y2) / 48),
			Size = UDim2.fromScale((math.sqrt(dx * dx + dy * dy) + lineTh * 0.6) / 24, lineTh / 24),
			Rotation = math.deg(math.atan2(dy, dx)), BackgroundColor3 = color, BorderSizePixel = 0,
		}, root)
		new("UICorner", {CornerRadius = UDim.new(1, 0)}, f)
	end
	function L.ring(cx, cy, r)
		local f = new("Frame", {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(cx / 24, cy / 24), Size = UDim2.fromScale(2 * r / 24, 2 * r / 24), BackgroundTransparency = 1, BorderSizePixel = 0}, root)
		new("UICorner", {CornerRadius = UDim.new(1, 0)}, f)
		new("UIStroke", {Color = color, Thickness = th, ApplyStrokeMode = Enum.ApplyStrokeMode.Border}, f)
	end
	function L.dot(cx, cy, r)
		local f = new("Frame", {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(cx / 24, cy / 24), Size = UDim2.fromScale(2 * r / 24, 2 * r / 24), BackgroundColor3 = color, BorderSizePixel = 0}, root)
		new("UICorner", {CornerRadius = UDim.new(1, 0)}, f)
	end
	function L.rrect(x, y, w, h, rad, filled)
		local f = new("Frame", {Position = UDim2.fromScale(x / 24, y / 24), Size = UDim2.fromScale(w / 24, h / 24), BackgroundColor3 = color, BackgroundTransparency = filled and 0 or 1, BorderSizePixel = 0}, root)
		new("UICorner", {CornerRadius = UDim.new(0, math.max(1, px * rad / 24))}, f)
		if not filled then new("UIStroke", {Color = color, Thickness = th, ApplyStrokeMode = Enum.ApplyStrokeMode.Border}, f) end
	end
	local D = {
		x = function() L.line(6, 6, 18, 18) L.line(18, 6, 6, 18) end,
		minus = function() L.line(6, 12, 18, 12) end,
		plus = function() L.line(6, 12, 18, 12) L.line(12, 6, 12, 18) end,
		expand = function() L.rrect(5, 5, 14, 14, 3) end,
		search = function() L.ring(10.5, 10.5, 5.5) L.line(14.5, 14.5, 19, 19) end,
		gear = function()
			L.ring(12, 12, 3) L.ring(12, 12, 6.5)
			for i = 0, 7 do
				local a = math.rad(i * 45)
				L.line(12 + math.cos(a) * 7.6, 12 + math.sin(a) * 7.6, 12 + math.cos(a) * 10, 12 + math.sin(a) * 10)
			end
		end,
		send = function() L.line(4, 12, 19, 12) L.line(13, 6, 19, 12) L.line(13, 18, 19, 12) end,
		stop = function() L.rrect(6, 6, 12, 12, 2.5, true) end,
		trash = function()
			L.line(5, 7, 19, 7) L.line(9.5, 4.5, 14.5, 4.5)
			L.rrect(7, 9, 10, 11, 2)
			L.line(10.5, 12, 10.5, 17) L.line(13.5, 12, 13.5, 17)
		end,
		copy = function() L.rrect(9, 9, 10, 10, 2) L.rrect(5, 5, 10, 10, 2) end,
		bag = function()
			L.rrect(5, 9, 14, 11, 3)
			L.line(9, 9, 9, 7) L.line(15, 9, 15, 7) L.line(9, 7, 15, 7)
		end,
		bookmark = function()
			L.line(7, 4, 7, 20) L.line(17, 4, 17, 20) L.line(7, 4, 17, 4)
			L.line(7, 20, 12, 15) L.line(17, 20, 12, 15)
		end,
		chat = function()
			L.rrect(4, 5, 16, 11, 3)
			L.line(9, 17, 9, 20.5) L.line(9, 20.5, 13, 16.5)
		end,
		chevron = function() L.line(9, 5, 16, 12) L.line(16, 12, 9, 19) end,
		check = function() L.line(5, 12, 10, 17) L.line(10, 17, 19, 7) end,
		dot = function() L.dot(12, 12, 5) end,
	}
	if D[name] then D[name]() end
	return root
end
local function setIconColor(root, color)
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("UIStroke") then d.Color = color
		elseif d:IsA("Frame") and d.BackgroundTransparency < 1 then d.BackgroundColor3 = color end
	end
end
local function iconBtn(parent, iconName, text, size, pos, color, ts, px)
	local b = btn(parent, text, size, pos, color, ts)
	px = px or 14
	local holder
	if text ~= "" then
		new("UIPadding", {PaddingLeft = UDim.new(0, px + 10)}, b)
		holder = new("Frame", {BackgroundTransparency = 1, Size = UDim2.fromOffset(px, px), Position = UDim2.new(0, 10, 0.5, -px / 2)}, b)
	else
		holder = new("Frame", {BackgroundTransparency = 1, Size = UDim2.fromOffset(px, px), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5)}, b)
	end
	local ic = makeIcon(iconName, holder, px, b.TextColor3)
	return b, ic
end

-- ===== Root GUI =====
local gui = new("ScreenGui", {
	Name = "RageHubDev", ResetOnSpawn = false, IgnoreGuiInset = true,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 999,
}, parentGui)

local function getViewportSize()
	-- UserInputService has no GetViewportSize() method. Read the active camera.
	local camera = workspace.CurrentCamera
	if camera then
		return camera.ViewportSize
	end
	return Vector2.new(800, 600)
end

local expanded, collapsed = false, false
local function calcSize()
	local vp = getViewportSize()
	if expanded then
		return math.floor(vp.X * 0.98), math.floor(vp.Y * 0.96)
	end
	return math.floor(math.clamp(vp.X * 0.96, 280, 780)), math.floor(math.clamp(vp.Y * 0.92, 250, 620))
end

local startW, startH = calcSize()
local main = round(new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(startW, startH), BackgroundColor3 = C.bg, ClipsDescendants = true, BorderSizePixel = 0,
}, gui), 16)
main.BackgroundTransparency = 0.12
do
	local st = main:FindFirstChildOfClass("UIStroke")
	st.Color = Color3.fromRGB(255, 255, 255)
	st.Thickness = 1.5
	st.Transparency = 0.35
	new("UIGradient", {Color = ColorSequence.new(C.accent, C.accent2), Rotation = 35}, st)
end
new("UIGradient", {
	Color = ColorSequence.new({ColorSequenceKeypoint.new(0, Color3.fromRGB(24, 36, 64)), ColorSequenceKeypoint.new(1, Color3.fromRGB(10, 14, 28))}),
	Rotation = 28,
}, main)

local top = new("Frame", {Size = UDim2.new(1, 0, 0, 38), BackgroundColor3 = C.bar, BackgroundTransparency = 0.35, Active = true, BorderSizePixel = 0}, main)
new("UIGradient", {Color = ColorSequence.new(Color3.fromRGB(70, 120, 190), Color3.fromRGB(40, 30, 90)), Rotation = 0, Transparency = NumberSequence.new(0.45, 0.7)}, top)
local logo = round(new("TextLabel", {
	Size = UDim2.fromOffset(34, 24), Position = UDim2.fromOffset(8, 7), BackgroundColor3 = C.accent,
	Text = "RH", TextColor3 = Color3.new(1, 1, 1), Font = Enum.Font.GothamBlack, TextSize = 12, BorderSizePixel = 0,
}, top), 12)
new("UIGradient", {Color = ColorSequence.new(C.accent, C.accent2), Rotation = 30}, logo)
local titleRow = new("Frame", {Size = UDim2.new(1, -250, 1, 0), Position = UDim2.fromOffset(50, 0), BackgroundTransparency = 1}, top)
new("UIListLayout", {FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder}, titleRow)
local titleLbl = new("TextLabel", {
	Size = UDim2.fromOffset(0, 20), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1,
	Text = "Rage Hub Dev", TextColor3 = C.text, Font = Enum.Font.GothamBold, TextSize = 14, LayoutOrder = 1,
}, titleRow)
local betaBadge = round(new("TextLabel", {
	Size = UDim2.fromOffset(38, 16), BackgroundColor3 = C.accent2, Text = "BETA", TextColor3 = Color3.new(1, 1, 1),
	Font = Enum.Font.GothamBold, TextSize = 9, BorderSizePixel = 0, LayoutOrder = 2,
}, titleRow), 8)
local function topBtn(txt, xOff, color, iconName)
	local b = btn(top, iconName and "" or txt, UDim2.fromOffset(30, 26), UDim2.new(1, xOff, 0.5, -13), color, 12)
	b.ZIndex = 3
	if iconName then
		local holder = new("Frame", {BackgroundTransparency = 1, Size = UDim2.fromOffset(14, 14), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5)}, b)
		makeIcon(iconName, holder, 14, C.text)
	end
	return b
end
local btnClose = topBtn("X", -38, C.bad, "x")
local btnExpand = topBtn("[]", -72, nil, "expand")
local btnCollapse = topBtn("-", -106, nil, "minus")
local btnLandscape = topBtn("LS", -140, C.accent)
local btnReverse = topBtn("RV", -174)

local body = new("Frame", {Size = UDim2.new(1, 0, 1, -38), Position = UDim2.fromOffset(0, 38), BackgroundTransparency = 1}, main)
local tabBar = hscroll(body, UDim2.new(1, -16, 0, 30), UDim2.fromOffset(8, 4))

local pages = {}
local function newPage(name)
	local f = new("Frame", {
		Name = name, Size = UDim2.new(1, 0, 1, -40), Position = UDim2.fromOffset(0, 40),
		BackgroundTransparency = 1, Visible = false,
	}, body)
	pages[name] = f
	return f
end

local toast = round(new("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -14),
	Size = UDim2.fromOffset(280, 30), BackgroundColor3 = C.accent, TextColor3 = Color3.new(1, 1, 1),
	Font = Enum.Font.GothamBold, TextSize = 12, Visible = false, ZIndex = 30, TextTruncate = Enum.TextTruncate.AtEnd, BorderSizePixel = 0,
}, main), 15)
local toastId = 0
local function showToast(msg)
	toastId += 1
	local my = toastId
	toast.Text = msg
	toast.BackgroundTransparency = 1
	toast.TextTransparency = 1
	toast.Visible = true
	TweenService:Create(toast, TweenInfo.new(0.15), {BackgroundTransparency = 0.12, TextTransparency = 0}):Play()
	task.delay(2, function()
		if my == toastId then
			TweenService:Create(toast, TweenInfo.new(0.25), {BackgroundTransparency = 1, TextTransparency = 1}):Play()
			task.delay(0.26, function() if my == toastId then toast.Visible = false end end)
		end
	end)
end
local function copyOut(text, what)
	local ok = copy(text)
	showToast(ok and ("Copied " .. what) or "Clipboard not supported")
	return ok
end

local bubble = round(new("TextButton", {
	Size = UDim2.fromOffset(50, 50), Position = UDim2.new(0, 12, 0.5, -25),
	BackgroundColor3 = C.accent, Text = "RH", TextColor3 = Color3.new(1, 1, 1),
	Font = Enum.Font.GothamBlack, TextSize = 13, Visible = false, AutoButtonColor = false, BorderSizePixel = 0,
}, gui), 25)
new("UIGradient", {Color = ColorSequence.new(C.accent, C.accent2), Rotation = 30}, bubble)
new("UIStroke", {Color = Color3.new(1, 1, 1), Thickness = 1.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border}, bubble)

-- ===== Dragging =====
local function drag(handle, target, onTap)
	local dragging, moved, startPos, startMouse = false, false, nil, nil
	handle.InputBegan:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
			dragging, moved = true, false
			startMouse, startPos = i.Position, target.Position
			i.Changed:Connect(function()
				if i.UserInputState == Enum.UserInputState.End then
					dragging = false
					if not moved and onTap then onTap() end
				end
			end)
		end
	end)
	UIS.InputChanged:Connect(function(i)
		if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
			local d = i.Position - startMouse
			if d.Magnitude > 6 then moved = true end
			if moved then
				target.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
			end
		end
	end)
end

-- ===== Sizing =====
local function relayout(w)
	local avail = w - 16 - 8
	local cols = math.max(2, math.floor(avail / 112))
	local cell = math.floor((avail - (cols - 1) * 8) / cols)
	for _, g in ipairs(grids) do
		g.CellSize = UDim2.fromOffset(cell, cell + 40)
	end
end
local function apply()
	local w, h = calcSize()
	body.Visible = not collapsed
	TweenService:Create(main, TweenInfo.new(0.18, Enum.EasingStyle.Quad), {Size = UDim2.fromOffset(w, collapsed and 38 or h)}):Play()
	relayout(w)
end
btnExpand.MouseButton1Click:Connect(function()
	expanded = not expanded
	collapsed = false
	main.Position = UDim2.fromScale(0.5, 0.5)
	apply()
end)
btnCollapse.MouseButton1Click:Connect(function()
	collapsed = not collapsed
	apply()
end)
btnClose.MouseButton1Click:Connect(function()
	main.Visible = false
	bubble.Visible = true
end)
drag(top, main)
drag(bubble, bubble, function()
	bubble.Visible = false
	main.Visible = true
end)
local camConn
local function hookCamera()
	local cam = Workspace.CurrentCamera
	if camConn then camConn:Disconnect() camConn = nil end
	if cam then camConn = cam:GetPropertyChangedSignal("ViewportSize"):Connect(apply) end
end
hookCamera()
Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function() hookCamera() apply() end)

-- ===== Favorites / collections =====
local activeCol = "Default"
local function isFav(id, col)
	local f = db.favs[tostring(id)]
	return (f and f.cols and f.cols[col]) and true or false
end
local function addFav(m, col)
	local k = tostring(m.id)
	local f = db.favs[k]
	if not f then
		f = {id = m.id, name = m.name, typeId = m.typeId, creator = m.creator, t = os.time(), cols = {}}
		db.favs[k] = f
	end
	f.cols[col] = true
	saveDB()
end
local function removeFav(id, col)
	local k = tostring(id)
	local f = db.favs[k]
	if f then
		f.cols[col] = nil
		if next(f.cols) == nil then db.favs[k] = nil end
		saveDB()
	end
end

-- ===== Lua snippet per asset type =====
local function luaLine(id, t)
	local sid = tostring(id)
	local rid = "rbxassetid://" .. sid
	if isAudio(t) then
		return ('local s = Instance.new("Sound")\ns.SoundId = "%s"\ns.Parent = workspace\ns:Play()'):format(rid)
	elseif t == 13 or t == 1 then
		return ('local d = Instance.new("Decal")\nd.Texture = "%s"\nd.Parent = workspace.Part -- change target'):format(rid)
	elseif t == 10 then
		return ('local m = game:GetService("InsertService"):LoadAsset(%s):GetChildren()[1]\nm.Parent = workspace'):format(sid)
	elseif t == 24 then
		return ('local a = Instance.new("Animation")\na.AnimationId = "%s"'):format(rid)
	elseif t == 40 or t == 4 then
		return ('local m = Instance.new("SpecialMesh")\nm.MeshId = "%s"\nm.Parent = workspace.Part -- change target'):format(rid)
	elseif t == 62 then
		return ('local v = Instance.new("VideoFrame")\nv.Video = "%s"'):format(rid)
	elseif t == 38 then
		return ('-- Plugin ID: %s (plugins install in Roblox Studio, not in-game)'):format(sid)
	end
	return ('"%s"'):format(rid)
end

-- ===== Audio preview =====
local sound = new("Sound", {Name = "RGC_CS_Sound", Volume = 1}, SoundService)
local bPlay
local playToken = 0
local function hookSound()
	sound.Ended:Connect(function() if bPlay then bPlay.Text = "Play audio" end end)
end
hookSound()
local function stopSound()
	playToken += 1
	pcall(function() sound:Stop() end)
	if bPlay then bPlay.Text = "Play audio" end
end

-- ===== Detail popup =====
local refreshSaved
local curItem = nil

local detail = new("Frame", {
	Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.4,
	Visible = false, ZIndex = 20, Active = true,
}, main)
local dCard = round(new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.new(1, -20, 1, -20), BackgroundColor3 = C.bg,
}, detail), 10)
new("UIStroke", {Color = C.accent, Thickness = 1}, dCard)

local dHolder = round(new("Frame", {
	Position = UDim2.fromOffset(8, 8), Size = UDim2.new(0.4, 0, 1, -16),
	BackgroundColor3 = C.bar, ClipsDescendants = true,
}, dCard), 8)
new("UIAspectRatioConstraint", {AspectRatio = 1, AspectType = Enum.AspectType.FitWithinMaxSize}, dHolder)
local dIcon = new("TextLabel", {
	Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", TextColor3 = C.sub,
	TextSize = 14, Font = Enum.Font.GothamBold,
}, dHolder)
local dImg = new("ImageLabel", {
	Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ScaleType = Enum.ScaleType.Fit, Image = "",
}, dHolder)

local dScroll = vscroll(dCard, UDim2.new(0.6, -28, 1, -42), UDim2.new(0.4, 16, 0, 34))
dScroll.ScrollBarThickness = 3
new("UIListLayout", {Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder}, dScroll)
local dTitle = label(dScroll, "", UDim2.new(1, -6, 0, 0), nil, C.text, 14, Enum.Font.GothamBold)
dTitle.AutomaticSize = Enum.AutomaticSize.Y
dTitle.LayoutOrder = 1
local dMeta = label(dScroll, "", UDim2.new(1, -6, 0, 0), nil, C.sub, 11)
dMeta.AutomaticSize = Enum.AutomaticSize.Y
dMeta.LayoutOrder = 2
local function dBtn(text, order, color)
	local b = btn(dScroll, text, UDim2.new(1, -6, 0, 30), nil, color, 12)
	b.LayoutOrder = order
	return b
end
local bCopyId = dBtn("Copy ID", 3, C.accent)
local bCopyRid = dBtn("Copy rbxassetid://", 4)
local bCopyLua = dBtn("Copy Lua snippet", 5)
local bCol = dBtn("Collection: Default", 6)
local bSave = dBtn("Save", 7)
bPlay = dBtn("Play audio", 8)
local bClose = iconBtn(dCard, "x", "", UDim2.fromOffset(28, 26), UDim2.new(1, -34, 0, 4), C.accent, 13, 12)

local function refreshSaveBtn()
	if not curItem then return end
	local on = isFav(curItem.id, activeCol)
	bCol.Text = "Collection: " .. activeCol
	bSave.Text = (on and "Saved - tap to remove" or "Save to " .. activeCol)
	bSave.BackgroundColor3 = on and C.accent or C.card
end

local function openDetail(m)
	curItem = m
	dTitle.Text = m.name or ("Asset " .. tostring(m.id))
	dMeta.Text = ("ID %s | %s%s"):format(tostring(m.id), TYPE_NAMES[m.typeId] or "Asset", m.creator and (" | by " .. m.creator) or "")
	dIcon.Text = TYPE_ICONS[m.typeId] or "ASSET"
	dImg.Image = ("rbxthumb://type=Asset&id=%s&w=420&h=420"):format(tostring(m.id))
	bPlay.Visible = isAudio(m.typeId)
	bPlay.Text = "Play audio"
	refreshSaveBtn()
	detail.Visible = true
end

bCopyId.MouseButton1Click:Connect(function() if curItem then copyOut(tostring(curItem.id), "ID " .. tostring(curItem.id)) end end)
bCopyRid.MouseButton1Click:Connect(function() if curItem then copyOut("rbxassetid://" .. tostring(curItem.id), "rbxassetid://") end end)
bCopyLua.MouseButton1Click:Connect(function() if curItem then copyOut(luaLine(curItem.id, curItem.typeId), "Lua snippet") end end)
bCol.MouseButton1Click:Connect(function()
	local idx = table.find(db.cols, activeCol) or 0
	activeCol = db.cols[(idx % #db.cols) + 1]
	refreshSaveBtn()
end)
bSave.MouseButton1Click:Connect(function()
	if not curItem then return end
	if isFav(curItem.id, activeCol) then
		removeFav(curItem.id, activeCol)
		showToast("Removed from " .. activeCol)
	else
		addFav(curItem, activeCol)
		showToast("Saved to " .. activeCol)
	end
	refreshSaveBtn()
	if refreshSaved then refreshSaved() end
end)
bPlay.MouseButton1Click:Connect(function()
	if not curItem then return end
	if bPlay.Text ~= "Play audio" then
		stopSound()
		return
	end
	local rid = "rbxassetid://" .. tostring(curItem.id)
	playToken += 1
	local my = playToken
	pcall(function() sound:Stop() sound:Destroy() end)
	sound = new("Sound", {Name = "RGC_CS_Sound", Volume = 1, Looped = false, SoundId = rid}, SoundService)
	hookSound()
	bPlay.Text = "Loading..."
	task.spawn(function()
		local function attempt(parent)
			sound.Parent = parent
			pcall(function() game:GetService("ContentProvider"):PreloadAsync({sound}) end)
			local t0 = os.clock()
			while my == playToken and not sound.IsLoaded and sound.TimeLength <= 0 and os.clock() - t0 < 6 do task.wait(0.2) end
			return sound.IsLoaded or sound.TimeLength > 0
		end
		local loaded = attempt(SoundService)
		if my ~= playToken then return end
		if not loaded then loaded = attempt(Workspace) end
		if my ~= playToken then return end
		sound:Play()
		if not loaded then
			task.wait(2.5)
			if my ~= playToken then return end
			loaded = sound.IsPlaying or sound.IsLoaded or sound.TimeLength > 0
		end
		if loaded then
			bPlay.Text = "Stop audio"
			local len = sound.TimeLength
			if len and len > 0 then showToast(("Playing - %d:%02d"):format(math.floor(len / 60), math.floor(len % 60))) end
		else
			bPlay.Text = "Play audio"
			showToast("This game didn't load that audio (restricted or removed). Try another.")
		end
	end)
end)
bClose.MouseButton1Click:Connect(function()
	stopSound()
	detail.Visible = false
end)

-- ===== STORE PAGE =====
local pStore = newPage("Store")
local searchBox = box(pStore, "Search or paste asset ID...", UDim2.new(1, -86, 0, 32), UDim2.fromOffset(8, 0))
local goBtn = btn(pStore, "Search", UDim2.fromOffset(62, 32), UDim2.new(1, -70, 0, 0), C.accent, 13)
local catBar = hscroll(pStore, UDim2.new(1, -16, 0, 28), UDim2.fromOffset(8, 36))
local toolRow = new("Frame", {Size = UDim2.new(1, -16, 0, 24), Position = UDim2.fromOffset(8, 68), BackgroundTransparency = 1}, pStore)
local scroll = makeGrid(pStore, UDim2.fromOffset(8, 96), UDim2.new(1, -16, 1, -100))
local status = new("TextLabel", {
	Size = UDim2.new(1, -16, 0, 40), Position = UDim2.new(0, 8, 0.5, -20),
	BackgroundTransparency = 1, Text = "", TextColor3 = C.sub, Font = Enum.Font.Gotham,
	TextSize = 14, TextWrapped = true, ZIndex = 5,
}, pStore)

local function toolBtn(i, text)
	return btn(toolRow, text, UDim2.new(0.25, -4, 1, 0), UDim2.new((i - 1) * 0.25, 0, 0, 0), C.card, 11)
end
local multiBtn = toolBtn(1, "Select: OFF")
local copySelBtn = toolBtn(2, "Copy IDs (0)")
local saveSelBtn = toolBtn(3, "Save (0)")
local recentBtn = toolBtn(4, "Recent")

local multi = false
local sel, selCount = {}, 0
local cellRefs, meta = {}, {}
local catIdx, page, reqId, order = 1, 0, 0, 0
local v2PageToken = nil
local v2Type = {[1] = "Model", [2] = "Decal", [3] = "Audio", [4] = "Audio", [5] = "Plugin", [6] = "MeshPart", [8] = "Video", [9] = "FontFamily"}
local loadBtn
local search
local function audioKind(ad)
	if type(ad) ~= "table" then return nil end
	local t = ad.audioType
	if type(t) == "table" then
		for _, x in ipairs(t) do
			local s = tostring(x):lower()
			if s == "0" or s == "music" then return "music" end
			if s == "1" or s == "soundeffect" or s == "sound effect" then return "sfx" end
		end
	end
	local d = tonumber(ad.duration or ad.durationSeconds)
	if d then return d >= 45 and "music" or "sfx" end
	return nil
end

local function updateToolUI()
	multiBtn.Text = multi and "Select: ON" or "Select: OFF"
	multiBtn.BackgroundColor3 = multi and C.accent or C.card
	copySelBtn.Text = "Copy IDs (" .. selCount .. ")"
	saveSelBtn.Text = "Save (" .. selCount .. ")"
end
local function clearSelection()
	for id in pairs(sel) do
		local c = cellRefs[id]
		if c and c.Parent then c.Sel.Enabled = false end
	end
	sel, selCount = {}, 0
	updateToolUI()
end
local function clearResults()
	clearGui(scroll)
	cellRefs, loadBtn, order = {}, nil, 0
end

multiBtn.MouseButton1Click:Connect(function()
	multi = not multi
	if not multi then clearSelection() end
	updateToolUI()
end)
copySelBtn.MouseButton1Click:Connect(function()
	if selCount == 0 then showToast("Select items first (turn Select ON)") return end
	local ids = {}
	for id in pairs(sel) do table.insert(ids, tostring(id)) end
	copyOut(table.concat(ids, ", "), selCount .. " IDs")
end)
saveSelBtn.MouseButton1Click:Connect(function()
	if selCount == 0 then showToast("Select items first (turn Select ON)") return end
	for _, m in pairs(sel) do addFav(m, activeCol) end
	showToast("Saved " .. selCount .. " to " .. activeCol)
	clearSelection()
	if refreshSaved then refreshSaved() end
end)

-- recent searches popup
local recentFrame = round(new("Frame", {
	Size = UDim2.new(1, -16, 0, 150), Position = UDim2.fromOffset(8, 96),
	BackgroundColor3 = C.bar, Visible = false, ZIndex = 8,
}, pStore), 8)
local recentList = vscroll(recentFrame, UDim2.new(1, -8, 1, -8), UDim2.fromOffset(4, 4))
new("UIListLayout", {Padding = UDim.new(0, 3)}, recentList)
local function pushRecent(kw)
	for i = #db.recent, 1, -1 do
		if db.recent[i] == kw then table.remove(db.recent, i) end
	end
	table.insert(db.recent, 1, kw)
	while #db.recent > 12 do table.remove(db.recent) end
	saveDB()
end
recentBtn.MouseButton1Click:Connect(function()
	if recentFrame.Visible then recentFrame.Visible = false return end
	clearGui(recentList)
	if #db.recent == 0 then
		label(recentList, "No recent searches yet.", UDim2.new(1, 0, 0, 24), nil, C.sub, 12)
	end
	for _, kw in ipairs(db.recent) do
		local b = btn(recentList, kw, UDim2.new(1, -4, 0, 26), nil, C.card, 12)
		b.TextXAlignment = Enum.TextXAlignment.Left
		b.MouseButton1Click:Connect(function()
			recentFrame.Visible = false
			searchBox.Text = kw
			search(false)
		end)
	end
	recentFrame.Visible = true
end)

local function addStoreCell(m)
	order += 1
	local cell = makeCell(scroll, m.id, m.name, m.typeId, order)
	cellRefs[m.id] = cell
	meta[m.id] = m
	cell.MouseButton1Click:Connect(function()
		if multi then
			if sel[m.id] then
				sel[m.id] = nil
				selCount -= 1
				cell.Sel.Enabled = false
			else
				sel[m.id] = m
				selCount += 1
				cell.Sel.Enabled = true
			end
			updateToolUI()
		else
			openDetail(m)
		end
	end)
end

local function addLoadMore()
	order += 1
	loadBtn = round(new("TextButton", {
		BackgroundColor3 = C.bar, Text = "Load more", TextColor3 = C.text,
		Font = Enum.Font.GothamBold, TextSize = 12, LayoutOrder = order,
	}, scroll), 8)
	loadBtn.MouseButton1Click:Connect(function()
		loadBtn.Text = "Loading..."
		if not (db.set.storeKey and db.set.storeKey ~= "" and v2Type[catIdx] and v2PageToken) then page += 1 end
		search(true)
	end)
end

search = function(append)
	local kw = trim(searchBox.Text)
	recentFrame.Visible = false
	if not append then
		page = 0
		v2PageToken = nil
		clearResults()
		clearSelection()
		scroll.CanvasPosition = Vector2.zero
		status.Text = "Loading..."
		if kw ~= "" and not kw:match("^%d+$") then pushRecent(kw) end
	end
	reqId += 1
	local my = reqId
	task.spawn(function()
		-- direct asset ID lookup
		if kw:match("^%d%d%d%d%d%d+$") and not append then
			local det
			if db.set.storeKey and db.set.storeKey ~= "" then
				det = getJSONWithHeaders("https://apis.roblox.com/toolbox-service/v2/assets/" .. kw, { ["x-api-key"] = db.set.storeKey })
			end
			if not det then det = getJSON(DETAILS .. kw) end
			if my ~= reqId then return end
			local d = det and (det.data and det.data[1] or det)
			if d then
				local a = d.asset or d
				status.Text = ""
				addStoreCell({id = tonumber(kw), name = a.name, typeId = a.assetTypeId or a.typeId or 10, creator = d.creator and d.creator.name, desc = a.description})
			else
				status.Text = "Asset ID not found (or API key lacks Creator Store read access)"
			end
			return
		end

		local cat = CATS[catIdx]
		local info, ids, hasNext = {}, {}, false
		local categoryV2 = (cat.id ~= 3 and cat.id ~= 300) and v2Type[catIdx] or nil
		local usedV2 = false
		local res
		if db.set.storeKey and db.set.storeKey ~= "" and categoryV2 then
			-- Current recommended Creator Store search operation: POST JSON body.
			local body = {
				searchCategoryType = categoryV2,
				maxPageSize = PAGE_SIZE,
				searchView = "Full",
				sortCategory = "Relevance",
			}
			if kw ~= "" then body.query = kw end
			if append and v2PageToken then
				body.pageToken = v2PageToken
			else
				body.pageNumber = 0
			end
			res = postJSONWithHeaders("https://apis.roblox.com/toolbox-service/v2/assets:search", { ["x-api-key"] = db.set.storeKey }, body)
			-- Roblox responses may wrap the asset records under different collection keys.
			local entries = res and (res.creatorStoreAssets or res.data or res.assets or res.items or res.results)
			if type(entries) == "table" then
				usedV2 = true
				v2PageToken = res.nextPageToken or res.nextPageCursor
				for _, entry in ipairs(entries) do
					local a = (type(entry) == "table" and (entry.asset or entry)) or nil
					local creator = type(entry) == "table" and entry.creator or nil
					local assetId = a and (a.id or a.assetId)
					if assetId then
						table.insert(ids, assetId)
						info[assetId] = {name = a.name or a.title, creator = type(creator) == "table" and creator.name or nil, desc = a.description, typeId = a.assetTypeId or a.typeId or cat.id}
					end
				end
				hasNext = type(v2PageToken) == "string" and v2PageToken ~= ""
			end
		end
		if not usedV2 then
			local url = ("%s%d?limit=%d&pageNumber=%d&keyword=%s"):format(MARKET, cat.id, PAGE_SIZE, page, HttpService:UrlEncode(kw))
			local extra = ""
			if cat.id == 3 then extra = "&audioTypes=1&maxDuration=45"
			elseif cat.id == 300 then extra = "&audioTypes=0&minDuration=45" end
			res = getJSON(url .. extra)
			if (not res or type(res.data) ~= "table") and extra ~= "" then res = getJSON(url) end
			if not res or type(res.data) ~= "table" then
				if append then
					page = math.max(0, page - 1)
					if loadBtn then loadBtn.Text = "Retry" end
				else
					status.Text = "Search failed. Check the Creator Store API key scope creator-store-product:read, HTTP access, or try the legacy fallback."
				end
				return
			end
			for _, v in ipairs(res.data) do table.insert(ids, v.id) end
			if #ids > 0 then
				local det = getJSON(DETAILS .. table.concat(ids, ","))
				if det and type(det.data) == "table" then
					for _, d in ipairs(det.data) do
						local a = d.asset or d
						if a and a.id then info[a.id] = {name = a.name, creator = d.creator and d.creator.name, desc = a.description, typeId = a.typeId, kind = audioKind(a.audioDetails or d.audioDetails)} end
					end
				end
			end
			hasNext = #ids >= PAGE_SIZE
		end
		if my ~= reqId then return end
		if #ids == 0 and not append then status.Text = "No results"; return end
		status.Text = ""
		if loadBtn then loadBtn:Destroy() loadBtn = nil end
		local shown = 0
		for _, id in ipairs(ids) do
			local item = info[id] or {}
			local skip = (cat.id == 3 and item.kind == "music") or (cat.id == 300 and item.kind == "sfx")
			if not skip then
				shown += 1
				addStoreCell({id = id, name = item.name, typeId = item.typeId or cat.id, creator = item.creator, desc = item.desc})
			end
		end
		if shown == 0 and not append and not hasNext then status.Text = "No results" end
		if hasNext then addLoadMore() end
	end)
end

local catButtons = {}
local function setCat(i)
	catIdx = i
	for idx, b in ipairs(catButtons) do
		b.BackgroundColor3 = (idx == i) and C.accent or C.card
	end
	search(false)
end
for i, c in ipairs(CATS) do
	local b = round(new("TextButton", {
		Size = UDim2.fromOffset(98, 28), BackgroundColor3 = C.card,
		Text = c.name, TextColor3 = C.text,
		Font = Enum.Font.GothamBold, TextSize = 12, LayoutOrder = i,
	}, catBar), 14)
	catButtons[i] = b
	b.MouseButton1Click:Connect(function() setCat(i) end)
end
goBtn.MouseButton1Click:Connect(function() search(false) end)
setCat(1) -- load models right away (no need to tap a category first)
searchBox.FocusLost:Connect(function(enter) if enter then search(false) end end)

-- ===== SAVED PAGE =====
local pSaved = newPage("Saved")
local viewCol = "All"
local colBar = hscroll(pSaved, UDim2.new(1, -16, 0, 28), UDim2.fromOffset(8, 0))
local row2 = new("Frame", {Size = UDim2.new(1, -16, 0, 28), Position = UDim2.fromOffset(8, 32), BackgroundTransparency = 1}, pSaved)
local newColBox = box(row2, "New collection", UDim2.new(0.28, -3, 1, 0), UDim2.new(0, 0, 0, 0))
newColBox.TextSize = 12
local addColBtn = btn(row2, "+ Add", UDim2.new(0.14, -3, 1, 0), UDim2.new(0.28, 0, 0, 0), C.accent, 11)
local copyTblBtn = btn(row2, "Copy table", UDim2.new(0.22, -3, 1, 0), UDim2.new(0.42, 0, 0, 0), C.card, 11)
local copyIdsBtn = btn(row2, "Copy IDs", UDim2.new(0.18, -3, 1, 0), UDim2.new(0.64, 0, 0, 0), C.card, 11)
local delColBtn = btn(row2, "Del col", UDim2.new(0.18, -3, 1, 0), UDim2.new(0.82, 0, 0, 0), C.card, 11)
local sScroll = makeGrid(pSaved, UDim2.fromOffset(8, 64), UDim2.new(1, -16, 1, -68))
local sStatus = new("TextLabel", {
	Size = UDim2.new(1, -16, 0, 40), Position = UDim2.new(0, 8, 0.5, -20),
	BackgroundTransparency = 1, Text = "", TextColor3 = C.sub, Font = Enum.Font.Gotham,
	TextSize = 13, TextWrapped = true, ZIndex = 5,
}, pSaved)

local visibleFavs = {}

refreshSaved = function()
	-- chips
	for _, c in ipairs(colBar:GetChildren()) do
		if c:IsA("GuiObject") then c:Destroy() end
	end
	local names = {"All"}
	for _, n in ipairs(db.cols) do table.insert(names, n) end
	for i, n in ipairs(names) do
		local b = round(new("TextButton", {
			Size = UDim2.fromOffset(math.max(60, #n * 8 + 24), 28),
			BackgroundColor3 = (n == viewCol) and C.accent or C.card,
			Text = n, TextColor3 = C.text, Font = Enum.Font.GothamBold, TextSize = 12, LayoutOrder = i,
		}, colBar), 14)
		b.MouseButton1Click:Connect(function()
			viewCol = n
			if n ~= "All" then activeCol = n end
			refreshSaved()
		end)
	end
	-- items
	clearGui(sScroll)
	visibleFavs = {}
	for _, f in pairs(db.favs) do
		if viewCol == "All" or (f.cols and f.cols[viewCol]) then
			table.insert(visibleFavs, f)
		end
	end
	table.sort(visibleFavs, function(a, b) return (a.t or 0) > (b.t or 0) end)
	sStatus.Text = (#visibleFavs == 0) and "Nothing saved here yet.\nTap an item in Store, then Save." or ""
	for i, f in ipairs(visibleFavs) do
		local cell = makeCell(sScroll, f.id, f.name, f.typeId, i)
		cell.MouseButton1Click:Connect(function()
			openDetail({id = f.id, name = f.name, typeId = f.typeId, creator = f.creator})
		end)
	end
end

addColBtn.MouseButton1Click:Connect(function()
	local n = trim(newColBox.Text)
	if n == "" then showToast("Type a collection name") return end
	if table.find(db.cols, n) then showToast("Already exists") return end
	table.insert(db.cols, n)
	activeCol, viewCol = n, n
	newColBox.Text = ""
	saveDB()
	refreshSaved()
end)
delColBtn.MouseButton1Click:Connect(function()
	if viewCol == "All" or viewCol == "Default" then showToast("Pick a custom collection to delete") return end
	local i = table.find(db.cols, viewCol)
	if i then table.remove(db.cols, i) end
	for k, f in pairs(db.favs) do
		f.cols[viewCol] = nil
		if next(f.cols) == nil then db.favs[k] = nil end
	end
	if activeCol == viewCol then activeCol = "Default" end
	viewCol = "All"
	saveDB()
	refreshSaved()
end)
copyIdsBtn.MouseButton1Click:Connect(function()
	if #visibleFavs == 0 then showToast("Nothing to copy") return end
	local ids = {}
	for _, f in ipairs(visibleFavs) do table.insert(ids, tostring(f.id)) end
	copyOut(table.concat(ids, ", "), #ids .. " IDs")
end)
copyTblBtn.MouseButton1Click:Connect(function()
	if #visibleFavs == 0 then showToast("Nothing to copy") return end
	local lines = {"local Assets = {"}
	for _, f in ipairs(visibleFavs) do
		table.insert(lines, ("\t{id = %s, name = %q},"):format(tostring(f.id), tostring(f.name or "")))
	end
	table.insert(lines, "}")
	copyOut(table.concat(lines, "\n"), "Lua table")
end)

local function buildAIPage()
-- ===== AI ASSISTANT (chat + coding, read-only tools, NVIDIA API) =====
local pAI = newPage("AI")
local LogService = game:GetService("LogService")
local lp = Players.LocalPlayer

-- ---------- state ----------
local history = {}          -- OpenAI-style chat messages
local busy, stopFlag = false, false
local pendingUser = {}
local spawned = {}          -- threads started by run_script
local codeStore, codeCount = {}, {user = 0, ai = 0}
local logSeq, logBuf = 0, {}

pcall(function()
	LogService.MessageOut:Connect(function(msg, typ)
		logSeq += 1
		local kind = "out"
		if typ == Enum.MessageType.MessageError then kind = "error" elseif typ == Enum.MessageType.MessageWarning then kind = "warn" end
		table.insert(logBuf, {seq = logSeq, kind = kind, text = tostring(msg)})
		if #logBuf > 400 then table.remove(logBuf, 1) end
	end)
end)

local function setting(name, default)
	local v = db.set[name]
	if v == nil then return default end
	return v
end
local function getKey()
	local k = db.set.nvKey
	if type(k) ~= "string" then return "" end
	k = k:gsub("^%s*[Bb]earer%s+", ""):gsub("[%s\"']", "")
	return k
end
local function clamp(n, a, b) return math.max(a, math.min(b, n)) end
local function fail(msg, extra)
	local t = extra or {}
	t.ok = false
	t.error = msg
	return t
end
local function okr(t)
	t = t or {}
	t.ok = true
	return t
end

-- ---------- paths ----------
local SERVICES = {}
for _, n in ipairs({"Workspace", "ReplicatedStorage", "ReplicatedFirst", "ServerScriptService", "ServerStorage", "StarterGui", "StarterPack", "StarterPlayer", "Lighting", "Players", "SoundService", "Teams", "TextChatService", "Chat", "MaterialService", "Debris", "RunService", "TweenService", "CollectionService", "UserInputService", "HttpService", "MarketplaceService", "InsertService", "PhysicsService", "ContextActionService", "CoreGui"}) do
	SERVICES[n:lower()] = n
end
local function isHidden(inst)
	return inst == gui or inst:IsDescendantOf(gui)
end
local function pathOf(inst)
	if inst == game then return "game" end
	local parts, cur = {}, inst
	while cur and cur ~= game do
		table.insert(parts, 1, cur.Name)
		cur = cur.Parent
	end
	if cur ~= game then return "(detached)/" .. table.concat(parts, "/") end
	return table.concat(parts, "/")
end
local function listNames(inst, n)
	local names = {}
	local okk, kids = pcall(inst.GetChildren, inst)
	if okk then
		for i, k in ipairs(kids) do
			if i > n then table.insert(names, "...") break end
			if not isHidden(k) then table.insert(names, k.Name) end
		end
	end
	return table.concat(names, ", ")
end
local function resolve(path)
	if type(path) ~= "string" then return nil, "path must be a string" end
	local p = trim(path)
	p = p:gsub("^game:GetService%([\"'](%w+)[\"']%)", "%1")
	p = p:gsub("^game[/%.]", "")
	p = p:gsub("^/+", "")
	p = p:gsub("/+$", "")
	if p == "" or p == "game" then return game end
	local slash = p:find("/", 1, true) ~= nil
	local segs = {}
	for s in p:gmatch(slash and "[^/]+" or "[^%.]+") do segs[#segs + 1] = s end
	local first = segs[1]
	local low = first:lower()
	local cur
	if low == "localplayer" then cur = lp
	elseif low == "playergui" then cur = lp and lp:FindFirstChildOfClass("PlayerGui")
	elseif low == "character" then cur = lp and lp.Character
	elseif low == "camera" or low == "currentcamera" then cur = Workspace.CurrentCamera
	elseif low == "terrain" then cur = Workspace.Terrain
	elseif SERVICES[low] then
		local s, svc = pcall(game.GetService, game, SERVICES[low])
		cur = s and svc or nil
	else
		cur = game:FindFirstChild(first)
	end
	if not cur then
		if not slash then
			local deep = Workspace:FindFirstChild(p, true)
			if deep then return deep end
		end
		return nil, "Not found: '" .. first .. "'. Top-level: " .. listNames(game, 40)
	end
	for i = 2, #segs do
		local nxt
		if segs[i] == "LocalPlayer" and cur == Players then nxt = lp else nxt = cur:FindFirstChild(segs[i]) end
		if not nxt then
			return nil, ("Not found: '%s' under %s. Children there: %s"):format(segs[i], pathOf(cur), listNames(cur, 25))
		end
		cur = nxt
	end
	return cur
end

-- ---------- value / source helpers ----------
local function ser(v)
	local t = typeof(v)
	if t == "Vector3" then return ("%g, %g, %g"):format(v.X, v.Y, v.Z)
	elseif t == "Vector2" then return ("%g, %g"):format(v.X, v.Y)
	elseif t == "Color3" then return ("%d, %d, %d"):format(math.round(v.R * 255), math.round(v.G * 255), math.round(v.B * 255))
	elseif t == "UDim2" then return ("%g, %g, %g, %g"):format(v.X.Scale, v.X.Offset, v.Y.Scale, v.Y.Offset)
	elseif t == "UDim" then return ("%g, %g"):format(v.Scale, v.Offset)
	elseif t == "CFrame" then
		local c = {v:GetComponents()}
		for i, n in ipairs(c) do c[i] = ("%g"):format(n) end
		return table.concat(c, ", ")
	elseif t == "EnumItem" then return v.Name
	elseif t == "Instance" then return pathOf(v)
	elseif t == "BrickColor" then return v.Name
	elseif t == "nil" then return "nil"
	end
	return tostring(v)
end
local function readSource(inst)
	if not inst:IsA("LuaSourceContainer") then return nil, "Not a script" end
	local okk, src = pcall(function() return inst.Source end)
	if okk and type(src) == "string" and src ~= "" then return src end
	if decompile then
		local o2, d = pcall(decompile, inst)
		if o2 and type(d) == "string" and d ~= "" then return d end
		if not o2 then return nil, "decompile failed: " .. tostring(d) end
	end
	return nil, "Cannot read this script's source (no decompile in this executor, or it is a server-only script)"
end
local function lineCount(s)
	if s == "" then return 0 end
	local _, n = s:gsub("\n", "")
	return n + 1
end
local function utf8Cut(s, stop)
	while stop < #s do
		local b = s:byte(stop + 1)
		if b and b >= 0x80 and b <= 0xBF then stop += 1 else break end
	end
	return stop
end
local function splitLines(src)
	local lines = {}
	for l in (src .. "\n"):gmatch("(.-)\n") do lines[#lines + 1] = l end
	if src:sub(-1) == "\n" then lines[#lines] = nil end
	return lines
end

-- ---------- tool registry ----------
local TOOLS, ORDER = {}, {}
local function P(t, d, extra)
	local p = {type = t, description = d}
	if extra then for k, v in pairs(extra) do p[k] = v end end
	return p
end
local function def(name, desc, props, required, fn)
	local d = {name = name, description = desc}
	if props then d.parameters = {type = "OBJECT", properties = props, required = required} end
	TOOLS[name] = {decl = d, run = fn}
	table.insert(ORDER, name)
end

def("list_children", "List the direct children of an instance (like the Dex/Explorer): name [Class] (child count). Paths: 'Workspace', 'ServerScriptService', 'ReplicatedStorage/StudioLiteFolder', 'StarterGui', 'game' (all services).", {
	path = P("STRING", "Instance path"),
	limit = P("INTEGER", "Max items (default 150)"),
}, {"path"}, function(a)
	local inst, err = resolve(a.path)
	if not inst then return fail(err) end
	local okk, kids = pcall(inst.GetChildren, inst)
	if not okk then return fail("Cannot read children") end
	table.sort(kids, function(x, y) return x.Name:lower() < y.Name:lower() end)
	local limit = clamp(tonumber(a.limit) or 150, 1, 400)
	local out, total = {}, 0
	for _, k in ipairs(kids) do
		if not isHidden(k) then
			total += 1
			if total <= limit then
				local n = 0
				pcall(function() n = #k:GetChildren() end)
				table.insert(out, k.Name .. " [" .. k.ClassName .. "]" .. (n > 0 and (" (" .. n .. ")") or ""))
			end
		end
	end
	return okr({path = pathOf(inst), class = inst.ClassName, total = total, items = out, truncated = total > limit})
end)

def("get_tree", "Indented tree of an instance and its descendants (names + classes, ValueBase values). Good overview of a service, model or GUI.", {
	path = P("STRING", "Root of the tree"),
	depth = P("INTEGER", "Max depth (default 3, max 8)"),
	max_nodes = P("INTEGER", "Max nodes (default 300, max 800)"),
}, {"path"}, function(a)
	local root, err = resolve(a.path)
	if not root then return fail(err) end
	local maxDepth, maxNodes = clamp(tonumber(a.depth) or 3, 0, 8), clamp(tonumber(a.max_nodes) or 300, 1, 800)
	local lines, count = {}, 0
	local function walk(inst, depth)
		if count >= maxNodes or isHidden(inst) then return end
		count += 1
		local line = string.rep("  ", depth) .. inst.Name .. " [" .. inst.ClassName .. "]"
		local okv, v = pcall(function() if inst:IsA("ValueBase") then return tostring(inst.Value) end end)
		if okv and v then line ..= " = " .. v:sub(1, 80):gsub("\n", " ") end
		table.insert(lines, line)
		if depth >= maxDepth then
			local n = 0
			pcall(function() n = #inst:GetChildren() end)
			if n > 0 then lines[#lines] = lines[#lines] .. " (+" .. n .. " children)" end
			return
		end
		local okk, kids = pcall(inst.GetChildren, inst)
		if okk then for _, k in ipairs(kids) do walk(k, depth + 1) end end
	end
	walk(root, 0)
	return okr({root = pathOf(root), nodes = count, truncated = count >= maxNodes, tree = table.concat(lines, "\n")})
end)

def("find_instances", "Search descendants by name substring and/or class (IsA). Returns paths.", {
	root = P("STRING", "Where to search (default Workspace)"),
	name_contains = P("STRING", "Case-insensitive name substring"),
	class_name = P("STRING", "Class or base class, e.g. 'BasePart', 'Script', 'RemoteEvent', 'ScreenGui'"),
	limit = P("INTEGER", "Max results (default 80)"),
}, nil, function(a)
	local root, err = resolve(a.root or "Workspace")
	if not root then return fail(err) end
	local nm = a.name_contains and tostring(a.name_contains):lower() or nil
	local limit = clamp(tonumber(a.limit) or 80, 1, 300)
	local out = {}
	local okk, desc = pcall(root.GetDescendants, root)
	if not okk then return fail("Cannot scan") end
	for _, d in ipairs(desc) do
		if not isHidden(d) then
			local match = true
			if nm and not d.Name:lower():find(nm, 1, true) then match = false end
			if match and a.class_name and a.class_name ~= "" then
				local okI, isA = pcall(d.IsA, d, a.class_name)
				if not (okI and isA) then match = false end
			end
			if match then
				table.insert(out, pathOf(d) .. " [" .. d.ClassName .. "]")
				if #out >= limit then break end
			end
		end
	end
	return okr({count = #out, truncated = #out >= limit, results = out})
end)

local PROP_SETS = {
	{"BasePart", {"Position", "Size", "Orientation", "Color", "Material", "Transparency", "Anchored", "CanCollide", "CanTouch"}},
	{"Model", {"PrimaryPart"}},
	{"GuiObject", {"Position", "Size", "AnchorPoint", "BackgroundColor3", "BackgroundTransparency", "Visible", "ZIndex"}},
	{"TextLabel", {"Text", "TextColor3", "TextSize"}},
	{"TextButton", {"Text", "TextColor3", "TextSize"}},
	{"TextBox", {"Text", "PlaceholderText"}},
	{"ImageLabel", {"Image"}},
	{"Light", {"Brightness", "Range", "Color", "Enabled"}},
	{"Sound", {"SoundId", "Volume", "Looped", "Playing"}},
	{"ValueBase", {"Value"}},
	{"Humanoid", {"Health", "MaxHealth", "WalkSpeed", "JumpPower"}},
	{"Decal", {"Texture", "Face"}},
	{"Lighting", {"ClockTime", "Brightness", "Ambient", "OutdoorAmbient", "FogEnd"}},
	{"Workspace", {"Gravity"}},
	{"LuaSourceContainer", {"Disabled"}},
}
def("get_properties", "Read properties of an instance. Without 'names' returns the common ones for its class plus attributes. Vectors print as 'x, y, z', colors as 'r, g, b' (0-255).", {
	path = P("STRING", "Instance path"),
	names = P("ARRAY", "Specific property names to read", {items = {type = "STRING"}}),
}, {"path"}, function(a)
	local inst, err = resolve(a.path)
	if not inst then return fail(err) end
	local names = {"Name", "ClassName", "Parent"}
	if type(a.names) == "table" and #a.names > 0 then
		names = a.names
	else
		for _, set in ipairs(PROP_SETS) do
			local okI, isA = pcall(inst.IsA, inst, set[1])
			if okI and isA then for _, n in ipairs(set[2]) do table.insert(names, n) end end
		end
	end
	local props = {}
	for _, n in ipairs(names) do
		local okk, v = pcall(function() return inst[n] end)
		props[tostring(n)] = okk and ser(v) or "<not readable>"
	end
	local res = okr({path = pathOf(inst), properties = props})
	local attrs = {}
	pcall(function() for k, v in pairs(inst:GetAttributes()) do attrs[k] = ser(v) end end)
	if next(attrs) then res.attributes = attrs end
	return res
end)

def("read_script", "Read the source of a script in the game with line numbers (needs decompile support; server-only scripts cannot be read). Returns up to ~12000 chars per call; page with start_line/end_line (next_start_line is returned when truncated).", {
	path = P("STRING", "Script path"),
	start_line = P("INTEGER", "First line (default 1)"),
	end_line = P("INTEGER", "Last line (default end)"),
}, {"path"}, function(a)
	local inst, err = resolve(a.path)
	if not inst then return fail(err) end
	local src, why = readSource(inst)
	if not src then return fail(why) end
	local lines = splitLines(src)
	local total = #lines
	local s = clamp(tonumber(a.start_line) or 1, 1, math.max(1, total))
	local e = clamp(tonumber(a.end_line) or total, s, math.max(s, total))
	local out, size, last = {}, 0, s - 1
	for i = s, e do
		local row = i .. "| " .. lines[i]
		if size + #row > 12000 and #out > 0 then break end
		size += #row + 1
		out[#out + 1] = row
		last = i
	end
	local res = okr({path = pathOf(inst), class = inst.ClassName, total_lines = total, from = s, to = last, code = table.concat(out, "\n")})
	if last < e then res.next_start_line = last + 1 end
	return res
end)

def("search_scripts", "Search the text of every readable script in the game (LocalScripts, ModuleScripts, loaded modules) for a word, e.g. a remote's name, a function or a GUI name. Use it to learn how the game's systems and remotes are used.", {
	query = P("STRING", "Text to find (case-insensitive)"),
	limit = P("INTEGER", "Max matching lines (default 25)"),
}, {"query"}, function(a)
	if not decompile then return fail("This executor has no decompile, so scripts cannot be searched.") end
	local q = tostring(a.query or ""):lower()
	if q == "" then return fail("query is empty") end
	local limit = clamp(tonumber(a.limit) or 25, 1, 80)
	local seen, list = {}, {}
	local function add(s)
		if typeof(s) == "Instance" and not seen[s] and s:IsA("LuaSourceContainer") and not isHidden(s) then
			seen[s] = true
			list[#list + 1] = s
		end
	end
	for _, d in ipairs(game:GetDescendants()) do add(d) end
	if getscripts then pcall(function() for _, s in ipairs(getscripts()) do add(s) end end) end
	if getloadedmodules then pcall(function() for _, s in ipairs(getloadedmodules()) do add(s) end end) end
	local out, scanned = {}, 0
	for i, s in ipairs(list) do
		if i > 600 or #out >= limit then break end
		if i % 6 == 0 then task.wait() end
		local src = readSource(s)
		if src then
			scanned += 1
			if src:lower():find(q, 1, true) then
				local hits = 0
				for n, l in ipairs(splitLines(src)) do
					if l:lower():find(q, 1, true) then
						out[#out + 1] = pathOf(s) .. ":" .. n .. ": " .. trim(l):sub(1, 160)
						hits += 1
						if hits >= 4 or #out >= limit then break end
					end
				end
			end
		end
	end
	return okr({scripts_scanned = scanned, scripts_total = #list, matches = out})
end)

def("list_remotes", "List RemoteEvents/RemoteFunctions (default: everywhere). The game's own remotes are already loaded when this runs, for example under ReplicatedStorage/StudioLiteFolder. Use search_scripts with a remote's name to see how it is called.", {
	root = P("STRING", "Where to look (default game)"),
	limit = P("INTEGER", "Max results (default 150)"),
}, nil, function(a)
	local root, err = resolve(a.root or "game")
	if not root then return fail(err) end
	local limit = clamp(tonumber(a.limit) or 150, 1, 400)
	local out = {}
	local okD, desc = pcall(root.GetDescendants, root)
	if not okD then return fail("Cannot scan") end
	for _, d in ipairs(desc) do
		if d:IsA("RemoteEvent") or d:IsA("RemoteFunction") or d:IsA("UnreliableRemoteEvent") then
			out[#out + 1] = pathOf(d) .. " [" .. d.ClassName .. "]"
			if #out >= limit then break end
		end
	end
	table.sort(out)
	return okr({count = #out, truncated = #out >= limit, remotes = out})
end)

local function historyLines()
	local lines = {}
	local okH, hist = pcall(function() return LogService:GetLogHistory() end)
	if okH and type(hist) == "table" then
		for _, e in ipairs(hist) do
			local kind = "out"
			if e.messageType == Enum.MessageType.MessageError then kind = "error" elseif e.messageType == Enum.MessageType.MessageWarning then kind = "warn" end
			lines[#lines + 1] = {kind = kind, text = tostring(e.message)}
		end
	end
	if #lines == 0 then
		for _, e in ipairs(logBuf) do lines[#lines + 1] = {kind = e.kind, text = e.text} end
	end
	return lines
end
def("get_output", "Read the latest game console output (prints, warnings, errors with script name and line number). Use this first when the user reports an error.", {
	limit = P("INTEGER", "Number of recent lines (default 40, max 150)"),
	only_errors = P("BOOLEAN", "Only warnings and errors"),
	contains = P("STRING", "Only lines containing this text"),
}, nil, function(a)
	local limit = clamp(tonumber(a.limit) or 40, 1, 150)
	local all = historyLines()
	local lines = {}
	local f = a.contains and tostring(a.contains):lower() or nil
	for _, l in ipairs(all) do
		if (not a.only_errors or l.kind ~= "out") and (not f or l.text:lower():find(f, 1, true)) then
			lines[#lines + 1] = l.kind .. ": " .. l.text:sub(1, 400)
		end
	end
	local out = {}
	for i = math.max(1, #lines - limit + 1), #lines do out[#out + 1] = lines[i] end
	return okr({count = #out, total_in_log = #all, lines = out})
end)

local function captureEnv(out)
	local function cap(prefix, ...)
		local parts = {}
		for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
		table.insert(out, prefix .. table.concat(parts, "\t"))
	end
	local base
	if getgenv then
		local o, g = pcall(getgenv)
		if o then base = g end
	end
	if not base then
		local o, g = pcall(getfenv, 0)
		base = o and g or _G
	end
	return setmetatable({
		print = function(...) cap("", ...) end,
		warn = function(...) cap("[warn] ", ...) end,
	}, {__index = base})
end

def("run_script", "Run Luau locally to reproduce an error or test a fix; captures print/warn output, the error message and any new console errors. Give 'script_id' (a script the user pasted in chat, e.g. user_script_1, or one you wrote earlier, e.g. ai_script_1), or 'path' of a readable script, or short inline 'source'. Only use when the user asks to debug/test.", {
	script_id = P("STRING", "Id of a script from the chat, e.g. user_script_1"),
	path = P("STRING", "Path of a readable script in the game"),
	source = P("STRING", "Short inline Luau"),
	wait_seconds = P("NUMBER", "How long to wait for it to finish (default 4, max 20)"),
}, nil, function(a)
	if not setting("allowRun", true) then return fail("Running scripts is turned off in the AI settings") end
	local src, label_ = nil, "inline"
	if a.script_id and a.script_id ~= "" then
		local e = codeStore[tostring(a.script_id)]
		if not e then
			local ids = {}
			for k in pairs(codeStore) do ids[#ids + 1] = k end
			table.sort(ids)
			return fail("Unknown script_id. Available: " .. (#ids > 0 and table.concat(ids, ", ") or "none"))
		end
		src, label_ = e.source, tostring(a.script_id)
	elseif a.path and a.path ~= "" then
		local inst, err = resolve(a.path)
		if not inst then return fail(err) end
		local s, why = readSource(inst)
		if not s then return fail(why) end
		src, label_ = s, inst.Name
	else
		src = tostring(a.source or "")
	end
	if src == "" then return fail("Nothing to run (give script_id, path or source)") end
	if not loadstring then return fail("loadstring is not available in this executor") end
	local fn, cerr = loadstring(src, "=" .. label_)
	if not fn then return fail("Compile error: " .. tostring(cerr)) end
	local out = {}
	pcall(setfenv, fn, captureEnv(out))
	local seq0 = logSeq
	local done, result, errMsg = false, nil, nil
	local th = task.spawn(function()
		local okR, res = pcall(fn)
		done = true
		if okR then result = res else errMsg = tostring(res) end
	end)
	table.insert(spawned, th)
	local t0, waitFor = os.clock(), clamp(tonumber(a.wait_seconds) or 4, 0, 20)
	while not done and os.clock() - t0 < waitFor do task.wait(0.1) end
	task.wait(0.3)
	local text = table.concat(out, "\n")
	if #text > 4000 then text = text:sub(1, 4000) .. "\n...(output cut)" end
	local newLogs = {}
	for _, e in ipairs(logBuf) do
		if e.seq > seq0 and e.kind ~= "out" then newLogs[#newLogs + 1] = e.kind .. ": " .. e.text:sub(1, 300) end
		if #newLogs >= 25 then break end
	end
	local res = {ok = errMsg == nil and #newLogs == 0, finished = done, output = text}
	if errMsg then res.error = errMsg end
	if #newLogs > 0 then res.console_errors = newLogs end
	if done and result ~= nil then res.returned = tostring(result):sub(1, 300) end
	if not done then res.note = "Still running in the background (stop_scripts cancels it)" end
	return res
end)

def("stop_scripts", "Cancel scripts started with run_script that are still running.", nil, nil, function()
	local n = 0
	for _, th in ipairs(spawned) do
		if pcall(task.cancel, th) then n += 1 end
	end
	spawned = {}
	return okr({cancelled = n})
end)

def("get_player", "Local player's position, facing direction, camera position and humanoid stats.", nil, nil, function()
	local res = okr({})
	local char = lp and lp.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if hrp then
		res.position = ser(hrp.Position)
		res.look_direction = ser(hrp.CFrame.LookVector)
	else
		res.note = "No character yet"
	end
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum then res.humanoid = ("WalkSpeed %g, JumpPower %g, Health %g"):format(hum.WalkSpeed, hum.JumpPower, hum.Health) end
	local cam = Workspace.CurrentCamera
	if cam then res.camera_position = ser(cam.CFrame.Position) end
	res.player = lp and lp.Name or "?"
	return res
end)

def("describe_map", "Summarize the map in Workspace (or a sub-tree): part counts, size/bounds, biggest models, lighting, spawns, sounds, lights, scripts, density. Use before giving advice about what to add or improve.", {
	root = P("STRING", "Where (default Workspace)"),
}, nil, function(a)
	local root, err = resolve(a.root or "Workspace")
	if not root then return fail(err) end
	local counts, parts, scanned = {}, 0, 0
	local minV, maxV
	local okD, desc = pcall(root.GetDescendants, root)
	if not okD then return fail("Cannot scan") end
	local spawns, lights, sounds, scriptsN, trunc = 0, 0, 0, 0, false
	for _, d in ipairs(desc) do
		scanned += 1
		if scanned > 60000 then trunc = true break end
		if scanned % 4000 == 0 then task.wait() end
		if not isHidden(d) then
			counts[d.ClassName] = (counts[d.ClassName] or 0) + 1
			if d:IsA("BasePart") then
				parts += 1
				local p, s = d.Position, d.Size
				local lo, hi = p - s / 2, p + s / 2
				minV = minV and Vector3.new(math.min(minV.X, lo.X), math.min(minV.Y, lo.Y), math.min(minV.Z, lo.Z)) or lo
				maxV = maxV and Vector3.new(math.max(maxV.X, hi.X), math.max(maxV.Y, hi.Y), math.max(maxV.Z, hi.Z)) or hi
			end
			if d:IsA("SpawnLocation") then spawns += 1 end
			if d:IsA("Light") then lights += 1 end
			if d:IsA("Sound") then sounds += 1 end
			if d:IsA("LuaSourceContainer") then scriptsN += 1 end
		end
	end
	local top = {}
	for k, v in pairs(counts) do top[#top + 1] = {k, v} end
	table.sort(top, function(x, y) return x[2] > y[2] end)
	local classes = {}
	for i = 1, math.min(14, #top) do classes[#classes + 1] = top[i][1] .. " x" .. top[i][2] end
	local res = okr({root = pathOf(root), parts = parts, classes = classes, spawns = spawns, lights = lights, sounds = sounds, scripts_visible = scriptsN, truncated = trunc})
	if minV and maxV then
		local size = maxV - minV
		res.bounds_min = ser(minV)
		res.bounds_max = ser(maxV)
		res.size = ser(size)
		local area = math.max(1, size.X * size.Z)
		res.parts_per_1000_sq_studs = math.floor(parts / area * 1000 * 100) / 100
	end
	local models = {}
	local okK, kids = pcall(root.GetChildren, root)
	if okK then
		for _, k in ipairs(kids) do
			if not isHidden(k) and (k:IsA("Model") or k:IsA("Folder")) then
				local n, sz = 0, ""
				pcall(function() n = #k:GetDescendants() end)
				if k:IsA("Model") then pcall(function() sz = " size " .. ser(k:GetExtentsSize()) end) end
				models[#models + 1] = {k.Name .. " [" .. k.ClassName .. "] " .. n .. " items" .. sz, n}
			end
		end
	end
	table.sort(models, function(x, y) return x[2] > y[2] end)
	local ml = {}
	for i = 1, math.min(25, #models) do ml[#ml + 1] = models[i][1] end
	res.top_level = ml
	local L = game:GetService("Lighting")
	local lt = {}
	for _, n in ipairs({"ClockTime", "Brightness", "Ambient", "OutdoorAmbient", "FogEnd", "FogColor", "GlobalShadows"}) do
		local okL, v = pcall(function() return L[n] end)
		if okL then lt[n] = ser(v) end
	end
	res.lighting = lt
	res.has_sky = L:FindFirstChildOfClass("Sky") ~= nil
	res.has_atmosphere = L:FindFirstChildOfClass("Atmosphere") ~= nil
	local hrp = lp and lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
	if hrp then res.player_position = ser(hrp.Position) end
	return res
end)

local function toolDecls()
	local d = {}
	for _, n in ipairs(ORDER) do table.insert(d, TOOLS[n].decl) end
	return d
end

-- ---------- system prompt ----------
local SYSTEM_PROMPT = [==[You are the AI assistant of "Rage Hub Dev (Beta)", a script hub for Roblox. You chat with the user and you write Luau code. You work inside the Studio Lite game, running on the player's device through an executor.

WHAT YOU CAN DO
- You have READ-ONLY tools: you can look at the game like the Dex/Explorer (list_children, get_tree, find_instances, get_properties), read scripts (read_script, search_scripts), see the game's remotes (list_remotes), read the console output (get_output), inspect the map and player (describe_map, get_player), and run a script locally to reproduce an error (run_script).
- You can NOT add, change or delete anything in the game. You have no tool for creating scripts, parts, GUIs or remotes. The user copies and pastes your code themselves.
- The game's remotes (for example in ReplicatedStorage/StudioLiteFolder) are already loaded when you run. When the user wants something that works with the game's systems, first LOOK: list_remotes, then search_scripts with a remote's name or a feature word, then read_script, so you understand how it is called before you write code that uses it. Never guess remote arguments you have not seen.

WHEN THE USER ASKS YOU TO CREATE SOMETHING (a UI, a script, a system, a tool...)
- Start with ONE short line saying you can't add scripts or objects to the game yourself, then write the complete script. Example in Taglish: "Wala akong tool para mag-add ng script sa game, pero heto ang script na pwede mong i-copy at i-paste." Use the user's language.
- Then give the full working code in a single ```lua block (split into several blocks only if it is really huge, say "Part 1/2"). Say where it goes or how to run it (for example: run it in your executor, or LocalScript in StarterPlayerScripts).
- Write complete, modern, working Luau: no placeholders, no "-- rest of code". Use clean, good-looking UI when asked for UI (rounded corners, dark theme, smooth tweens) and make it draggable and responsive when it makes sense.

WHEN THE USER REPORTS AN ERROR IN A SCRIPT ("my admin panel has an error, fix it")
1. Call get_output (only_errors=true) to see the latest errors and their line numbers.
2. If the user pasted the script it has an id such as user_script_1: call run_script with that script_id to reproduce the problem and read the real error. If the script is in the game, use read_script or search_scripts to read it.
3. Find the real cause. Check the line numbers against the script.
4. Reply with the COMPLETE updated script in one ```lua block (or numbered parts if it is very long). Change ONLY what is needed for the fix. Keep every UI element, feature, name, color, layout and behavior exactly as it was: do not redesign, rename, remove or "improve" anything else.
5. After the code, list briefly what you changed (line or function, and why). Do not add anything else.
- If the output shows no error and the script runs fine, say so and ask what is wrong.

STYLE
- Be concise and direct. Reply in the language the user writes (they often write Tagalog or Taglish).
- If a request is ambiguous, decide sensibly and proceed; ask only when truly blocked.
- Every tool call needs VALID JSON arguments. Keep tool use focused: only look at what you need.
- When asked about the map (what to add, does it look good), use describe_map and get_tree, then give concrete recommendations (look and feel, gameplay, sound, performance) and offer to write a script for the best ideas.]==]

local function systemText()
	local s = SYSTEM_PROMPT
	if not setting("allowRun", true) then s ..= "\n\nNOTE: the user turned OFF running scripts, so run_script is unavailable." end
	return s
end

-- ---------- context size control ----------
local CTX_LIMIT = 260000
local MAX_STEPS = 120
local NV_URL = "https://integrate.api.nvidia.com/v1/chat/completions"
local NV_DEFAULT_MODEL = "z-ai/glm-5.3-flash"
local function strSize(v)
	local t = type(v)
	if t == "string" then return #v end
	if t == "table" then
		local n = 0
		for _, x in pairs(v) do n += strSize(x) end
		return n
	end
	return 8
end
local function compact()
	local total = strSize(history)
	if total <= CTX_LIMIT then return end
	for i = 1, #history - 8 do
		local m = history[i]
		local before = strSize(m)
		if m.role == "tool" and type(m.content) == "string" and #m.content > 300 then
			m.content = m.content:sub(1, 300) .. "...[trimmed]"
		elseif m.role == "assistant" and type(m.tool_calls) == "table" then
			for _, tc in ipairs(m.tool_calls) do
				local f = tc["function"]
				if f and type(f.arguments) == "string" and #f.arguments > 1500 then
					f.arguments = '{"trimmed":"omitted to save context"}'
				end
			end
		end
		total -= (before - strSize(m))
		if total <= CTX_LIMIT * 0.6 then break end
	end
end
local function dropOldest()
	local cut = math.max(1, math.floor(#history * 0.4))
	for i = cut, #history do
		local m = history[i]
		if m and m.role == "user" then
			for _ = 1, i - 1 do table.remove(history, 1) end
			return true
		end
	end
	return false
end

-- ---------- NVIDIA API request (OpenAI-compatible) ----------
local function modelName()
	local m = db.set.nvModel
	return (type(m) == "string" and m ~= "") and m or NV_DEFAULT_MODEL
end
local function lowerTypes(v)
	if type(v) ~= "table" then return v end
	local t = {}
	for k, x in pairs(v) do
		if k == "type" and type(x) == "string" then t[k] = x:lower() else t[k] = lowerTypes(x) end
	end
	return t
end
local cachedTools
local function toolList()
	if not cachedTools then
		cachedTools = {}
		for _, d in ipairs(toolDecls()) do
			local params = d.parameters and lowerTypes(d.parameters) or {type = "object", properties = {note = {type = "string", description = "unused"}}}
			table.insert(cachedTools, {type = "function", ["function"] = {name = d.name, description = d.description, parameters = params}})
		end
	end
	return cachedTools
end
local setStatus
local function llmRequest(maxTokens)
	local key = getKey()
	if key == "" then return nil, "No NVIDIA API key. Open Settings (gear) and paste your key (starts with nvapi-)." end
	local msgs = {{role = "system", content = systemText()}}
	for _, m in ipairs(history) do table.insert(msgs, m) end
	local payload = {model = modelName(), messages = msgs, tools = toolList(), tool_choice = "auto", max_tokens = maxTokens, temperature = 0.4}
	local okE, body = pcall(HttpService.JSONEncode, HttpService, payload)
	if not okE then return nil, "Could not encode request: " .. tostring(body) end
	local lastErr = "Request failed"
	for attempt = 1, 6 do
		if stopFlag then return nil, "Stopped" end
		local res = doRequest({
			Url = NV_URL, Method = "POST",
			Headers = {["Content-Type"] = "application/json", ["Accept"] = "application/json", ["Authorization"] = "Bearer " .. key},
			Body = body,
		})
		if not res then
			lastErr = "No response. Your executor may block HTTP requests."
			setStatus("Network problem, retrying (" .. attempt .. ")", C.warn)
			task.wait(math.min(2 * attempt, 10))
		else
			local status = tonumber(res.StatusCode) or 0
			local okD, data = pcall(HttpService.JSONDecode, HttpService, res.Body)
			if not okD or type(data) ~= "table" then
				lastErr = "Bad response (HTTP " .. status .. ")"
				if status == 401 or status == 403 then return nil, "NVIDIA rejected the API key (HTTP " .. status .. "). Check that you pasted the full nvapi- key." end
				task.wait(2)
			elseif data.error or (status >= 400 and not data.choices) then
				local e = data.error
				local msg
				if type(e) == "table" then msg = tostring(e.message or e.code or "API error")
				elseif e ~= nil then msg = tostring(e)
				else msg = tostring(data.detail or data.message or data.title or ("HTTP " .. status)) end
				if type(data.detail) == "table" then
					local okJ, js = pcall(HttpService.JSONEncode, HttpService, data.detail)
					if okJ then msg = msg .. " " .. js:sub(1, 160) end
				end
				local code = (type(e) == "table" and tonumber(e.code)) or status
				lastErr = msg
				if code == 401 or code == 403 then
					return nil, "NVIDIA rejected the API key (HTTP " .. code .. "). Check that you pasted the full nvapi- key."
				elseif code == 429 then
					local w = math.min(6 * attempt, 40)
					setStatus("Rate limited, waiting " .. w .. "s", C.warn)
					task.wait(w)
				elseif code >= 500 or code == 408 then
					setStatus("Server busy, retrying (" .. attempt .. ")", C.warn)
					task.wait(math.min(3 * attempt, 15))
				else
					return nil, msg, code
				end
			else
				return data
			end
		end
	end
	return nil, lastErr
end

local currentCard = nil
setStatus = function(text, color)
	if currentCard then currentCard.setAction(text) end
end



-- ---------- chat UI ----------
local header = new("Frame", {Size = UDim2.new(1, -16, 0, 30), Position = UDim2.fromOffset(8, 0), BackgroundTransparency = 1}, pAI)
local btnRow = new("Frame", {Size = UDim2.new(0, 190, 1, 0), Position = UDim2.new(1, -190, 0, 0), BackgroundTransparency = 1}, header)
new("UIListLayout", {FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Right, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder}, btnRow)
local stopBtn = iconBtn(btnRow, "stop", "Stop", UDim2.fromOffset(66, 28), nil, C.bad, 11, 11)
stopBtn.LayoutOrder = 1
stopBtn.Visible = false
local clearBtn = iconBtn(btnRow, "trash", "Clear", UDim2.fromOffset(66, 28), nil, C.card, 11, 12)
clearBtn.LayoutOrder = 2
local setBtn = iconBtn(btnRow, "gear", "", UDim2.fromOffset(34, 28), nil, C.card, 11, 15)
setBtn.LayoutOrder = 3
local modelLbl = label(header, "", UDim2.new(1, -198, 1, 0), nil, C.sub, 11, Enum.Font.GothamMedium)
modelLbl.TextWrapped = false
modelLbl.TextTruncate = Enum.TextTruncate.AtEnd

local chatScroll = vscroll(pAI, UDim2.new(1, -16, 1, -112), UDim2.fromOffset(8, 34))
new("UIListLayout", {Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder}, chatScroll)
local chips = hscroll(pAI, UDim2.new(1, -16, 0, 26), UDim2.new(0, 8, 1, -74))
local inputBox = box(pAI, "Ask anything, or paste a script to fix...", UDim2.new(1, -92, 0, 38), UDim2.new(0, 8, 1, -42), true)
local sendBtn = iconBtn(pAI, "send", "Send", UDim2.fromOffset(76, 38), UDim2.new(1, -84, 1, -42), C.accent, 13, 14)

local msgOrder = 0
local TXT_CHUNK = 2400
local function scrollBottom()
	task.defer(function() chatScroll.CanvasPosition = Vector2.new(0, 1e7) end)
end
local function trimChat()
	local frames = {}
	for _, c in ipairs(chatScroll:GetChildren()) do
		if c:IsA("GuiObject") then table.insert(frames, c) end
	end
	table.sort(frames, function(x, y) return x.LayoutOrder < y.LayoutOrder end)
	for i = 1, #frames - 90 do frames[i]:Destroy() end
end
local function pad(f, v)
	new("UIPadding", {PaddingTop = UDim.new(0, v), PaddingBottom = UDim.new(0, v), PaddingLeft = UDim.new(0, v + 2), PaddingRight = UDim.new(0, v + 2)}, f)
end
local function listLayout(f, p)
	new("UIListLayout", {Padding = UDim.new(0, p or 4), SortOrder = Enum.SortOrder.LayoutOrder}, f)
end
local function addTextChunks(parent, text, color, ts, font, order)
	local pos = 1
	while pos <= #text do
		local stop = math.min(#text, pos + TXT_CHUNK - 1)
		if stop < #text then
			local nl = text:sub(pos, stop):match(".*()\n")
			if nl and nl > 200 then stop = pos + nl - 1 else stop = utf8Cut(text, stop) end
		end
		local seg = text:sub(pos, stop)
		pos = stop + 1
		local l = label(parent, seg, UDim2.new(1, 0, 0, 0), nil, color, ts, font)
		l.AutomaticSize = Enum.AutomaticSize.Y
		l.TextYAlignment = Enum.TextYAlignment.Top
		l.LayoutOrder = order
		order += 1
	end
	return order
end

local function addCodeBlock(parent, code, order)
	local cf = round(new("Frame", {Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = Color3.fromRGB(6, 9, 18), BorderSizePixel = 0, LayoutOrder = order}, parent), 8)
	cf.BackgroundTransparency = 0.15
	pad(cf, 5)
	listLayout(cf, 4)
	local nLines = 1
	for _ in code:gmatch("\n") do nLines += 1 end
	local head = new("Frame", {Size = UDim2.new(1, 0, 0, 24), BackgroundTransparency = 1, LayoutOrder = 1}, cf)
	label(head, "lua - " .. nLines .. " lines", UDim2.new(1, -140, 1, 0), nil, C.sub, 10, Enum.Font.Code)
	local cp = btn(head, "Copy", UDim2.fromOffset(56, 22), UDim2.new(1, -56, 0, 1), C.accent, 11)
	local ex = btn(head, "Expand", UDim2.fromOffset(62, 22), UDim2.new(1, -122, 0, 1), C.card, 11)
	local bodyF = new("Frame", {Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = 2}, cf)
	listLayout(bodyF, 0)
	local open = false
	local function render()
		clearGui(bodyF)
		local shown = code
		if not open and nLines > 12 then
			local cut, cnt = 0, 0
			for i = 1, #code do
				if code:byte(i) == 10 then
					cnt += 1
					if cnt >= 12 then cut = i break end
				end
			end
			if cut > 0 then shown = code:sub(1, cut) .. "... (" .. (nLines - 12) .. " more lines)" end
		end
		addTextChunks(bodyF, shown, C.text, 11, Enum.Font.Code, 1)
		ex.Text = open and "Collapse" or "Expand"
		ex.Visible = nLines > 12
	end
	ex.MouseButton1Click:Connect(function() open = not open render() end)
	cp.MouseButton1Click:Connect(function() copyOut(code, "code") end)
	render()
end

local function parseBlocks(text)
	local out, pos = {}, 1
	while pos <= #text do
		local s, e = text:find("```", pos, true)
		if not s then table.insert(out, {t = "text", v = text:sub(pos)}) break end
		table.insert(out, {t = "text", v = text:sub(pos, s - 1)})
		local s2, e2 = text:find("```", e + 1, true)
		local code
		if s2 then code = text:sub(e + 1, s2 - 1) pos = e2 + 1 else code = text:sub(e + 1) pos = #text + 1 end
		code = code:gsub("^[ \t]*%a*[ \t]*\r?\n", "", 1)
		table.insert(out, {t = "code", v = code})
	end
	return out
end



-- code registry: pasted / written scripts get ids so run_script can use them
local function looksLikeCode(text)
	if lineCount(text) < 6 then return false end
	return text:find("local%s+[%w_]+%s*=") ~= nil or text:find("function%s*[%w_%.:]*%(") ~= nil or text:find("game:GetService") ~= nil
end
local function registerCode(text, origin)
	local ids = {}
	local found = false
	for _, b in ipairs(parseBlocks(text)) do
		if b.t == "code" and #trim(b.v) > 60 then
			found = true
			codeCount[origin] += 1
			local id = origin .. "_script_" .. codeCount[origin]
			codeStore[id] = {source = trim(b.v), lines = lineCount(trim(b.v))}
			ids[#ids + 1] = id .. " (" .. codeStore[id].lines .. " lines)"
		end
	end
	if not found and origin == "user" and looksLikeCode(text) then
		codeCount[origin] += 1
		local id = origin .. "_script_" .. codeCount[origin]
		codeStore[id] = {source = trim(text), lines = lineCount(trim(text))}
		ids[#ids + 1] = id .. " (" .. codeStore[id].lines .. " lines)"
	end
	return table.concat(ids, ", ")
end

local function addMessage(role, text)
	msgOrder += 1
	local isUser = role == "user"
	local f = round(new("Frame", {
		Size = UDim2.new(isUser and 0.88 or 1, -6, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BorderSizePixel = 0,
		BackgroundColor3 = isUser and Color3.fromRGB(50, 80, 140) or C.bar, LayoutOrder = msgOrder,
	}, chatScroll), 12)
	f.BackgroundTransparency = isUser and 0.2 or 0.35
	pad(f, 7)
	listLayout(f, 4)
	if role == "sys" then f.BackgroundColor3 = Color3.fromRGB(90, 40, 50) end
	local n = 0
	for _, b in ipairs(parseBlocks(text)) do
		local v = trim(b.v)
		if v ~= "" then
			n += 1
			if b.t == "text" then
				n = addTextChunks(f, v, C.text, 13, Enum.Font.Gotham, n)
			else
				addCodeBlock(f, v, n)
			end
		end
	end
	trimChat()
	scrollBottom()
	return f
end

local function clip(v, n)
	if type(v) == "string" then return #v > n and (v:sub(1, n) .. "...(" .. #v .. " chars)") or v end
	if type(v) == "table" then
		local t = {}
		for k, x in pairs(v) do t[k] = clip(x, n) end
		return t
	end
	return v
end
local function toJson(v)
	local okk, s = pcall(HttpService.JSONEncode, HttpService, clip(v, 300))
	return okk and s or tostring(v)
end


-- ---------- run card: Thinking -> Summary with live timer ----------
local function fmtDur(s)
	if s < 10 then return ("%.1fs"):format(s) end
	if s < 60 then return ("%ds"):format(math.floor(s)) end
	return ("%dm %02ds"):format(math.floor(s / 60), math.floor(s % 60))
end
local VERB = {
	list_children = "Listing", get_tree = "Scanning", find_instances = "Searching", get_properties = "Inspecting",
	read_script = "Reading script", search_scripts = "Searching scripts", list_remotes = "Checking remotes",
	get_output = "Reading output", run_script = "Running script", stop_scripts = "Stopping scripts",
	get_player = "Checking player", describe_map = "Analyzing map",
}
local function argSummary(args)
	for _, k in ipairs({"path", "root", "script_id", "query", "contains"}) do
		if args[k] ~= nil then return tostring(args[k]) end
	end
	return ""
end
local function newRunCard()
	msgOrder += 1
	local card = round(new("Frame", {Size = UDim2.new(1, -6, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = C.bar, BorderSizePixel = 0, LayoutOrder = msgOrder}, chatScroll), 12)
	card.BackgroundTransparency = 0.3
	listLayout(card, 0)
	local head = new("TextButton", {Size = UDim2.new(1, 0, 0, 32), BackgroundTransparency = 1, Text = "", AutoButtonColor = false, LayoutOrder = 1}, card)
	local dots = {}
	for i = 1, 3 do
		local d = new("Frame", {Size = UDim2.fromOffset(6, 6), Position = UDim2.new(0, 12 + (i - 1) * 10, 0.5, -3), BackgroundColor3 = C.accent, BorderSizePixel = 0}, head)
		new("UICorner", {CornerRadius = UDim.new(1, 0)}, d)
		dots[i] = d
	end
	local title = label(head, "Thinking", UDim2.new(1, -150, 1, 0), UDim2.fromOffset(46, 0), C.text, 13, Enum.Font.GothamBold)
	title.TextWrapped = false
	local timer = label(head, "0.0s", UDim2.fromOffset(70, 32), UDim2.new(1, -96, 0, 0), C.sub, 12, Enum.Font.Code)
	timer.TextXAlignment = Enum.TextXAlignment.Right
	local chevHolder = new("Frame", {BackgroundTransparency = 1, Size = UDim2.fromOffset(12, 12), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -14, 0.5, 0)}, head)
	local chev = makeIcon("chevron", chevHolder, 12, C.sub)
	local action = label(card, "Starting...", UDim2.new(1, 0, 0, 0), nil, C.sub, 11)
	action.AutomaticSize = Enum.AutomaticSize.Y
	action.TextWrapped = false
	action.TextTruncate = Enum.TextTruncate.AtEnd
	action.LayoutOrder = 2
	new("UIPadding", {PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12), PaddingBottom = UDim.new(0, 8)}, action)
	local bodyF = new("Frame", {Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Visible = false, LayoutOrder = 3}, card)
	listLayout(bodyF, 3)
	new("UIPadding", {PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8)}, bodyF)
	head.MouseButton1Click:Connect(function()
		bodyF.Visible = not bodyF.Visible
		chev.Rotation = bodyF.Visible and 90 or 0
	end)

	local rc = {t0 = os.clock(), steps = 0, reads = 0, runs = 0, finished = false}
	local bodyOrder = 0
	task.spawn(function()
		while not rc.finished and card.Parent do
			local e = os.clock() - rc.t0
			timer.Text = fmtDur(e)
			for i, d in ipairs(dots) do
				d.BackgroundTransparency = 0.1 + 0.75 * (0.5 + 0.5 * math.sin(e * 5 - i * 0.9))
			end
			task.wait(0.2)
		end
	end)
	function rc.setAction(text)
		if not rc.finished then action.Text = text end
	end
	function rc.addNote(text)
		if not text or trim(text) == "" then return end
		bodyOrder += 1
		local l = label(bodyF, "Thinking notes: " .. trim(text):sub(1, 1200), UDim2.new(1, 0, 0, 0), nil, C.sub, 10, Enum.Font.Gotham)
		l.AutomaticSize = Enum.AutomaticSize.Y
		l.TextYAlignment = Enum.TextYAlignment.Top
		l.LayoutOrder = bodyOrder
	end
	function rc.addStep(name, args)
		rc.steps += 1
		if name == "run_script" then rc.runs += 1 else rc.reads += 1 end
		bodyOrder += 1
		local row = new("TextButton", {
			Size = UDim2.new(1, 0, 0, 22), BackgroundTransparency = 1, Text = (VERB[name] or name) .. "  " .. argSummary(args),
			TextColor3 = C.text, Font = Enum.Font.GothamMedium, TextSize = 11, TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd, AutoButtonColor = false, LayoutOrder = bodyOrder,
		}, bodyF)
		new("UIPadding", {PaddingLeft = UDim.new(0, 16)}, row)
		local ind = new("Frame", {Size = UDim2.fromOffset(7, 7), Position = UDim2.new(0, 2, 0.5, -3), BackgroundColor3 = C.warn, BorderSizePixel = 0}, row)
		new("UICorner", {CornerRadius = UDim.new(1, 0)}, ind)
		bodyOrder += 1
		local detailL = label(bodyF, "", UDim2.new(1, 0, 0, 0), nil, C.sub, 10, Enum.Font.Code)
		detailL.AutomaticSize = Enum.AutomaticSize.Y
		detailL.TextYAlignment = Enum.TextYAlignment.Top
		detailL.Visible = false
		detailL.LayoutOrder = bodyOrder
		local argText = toJson(args)
		detailL.Text = "args: " .. argText
		row.MouseButton1Click:Connect(function() detailL.Visible = not detailL.Visible end)
		rc.setAction((VERB[name] or name) .. "  " .. argSummary(args))
		return function(res)
			local good = res and res.ok ~= false
			ind.BackgroundColor3 = good and C.good or C.bad
			local shown = toJson(res)
			if #shown > 1200 then shown = shown:sub(1, 1200) .. "..." end
			detailL.Text = "args: " .. argText .. "\nresult: " .. shown
		end
	end
	function rc.finish(kind)
		if rc.finished then return end
		rc.finished = true
		local e = os.clock() - rc.t0
		timer.Text = fmtDur(e)
		local good = kind == "done"
		title.Text = good and "Summary" or (kind == "stopped" and "Stopped" or "Stopped by error")
		title.TextColor3 = good and C.good or (kind == "stopped" and C.warn or C.bad)
		for _, d in ipairs(dots) do
			d.BackgroundTransparency = 0
			d.BackgroundColor3 = good and C.good or (kind == "stopped" and C.warn or C.bad)
		end
		local parts = {}
		if rc.reads > 0 then table.insert(parts, rc.reads .. (rc.reads == 1 and " check" or " checks")) end
		if rc.runs > 0 then table.insert(parts, rc.runs .. (rc.runs == 1 and " test run" or " test runs")) end
		if #parts == 0 then
			action.Text = "Replied in " .. fmtDur(e)
		else
			action.Text = "Worked for " .. fmtDur(e) .. " - " .. table.concat(parts, ", ")
		end
		action.TextColor3 = C.sub
	end
	trimChat()
	scrollBottom()
	return rc
end

-- ---------- tool execution ----------
local function execTool(name, args)
	local t = TOOLS[name]
	if not t then return fail("Unknown tool '" .. tostring(name) .. "'. Available: " .. table.concat(ORDER, ", ")) end
	if type(args) ~= "table" then args = {} end
	local okk, res = pcall(t.run, args)
	if not okk then return fail("Tool crashed: " .. tostring(res)) end
	if type(res) ~= "table" then res = okr({result = tostring(res)}) end
	local okJ, js = pcall(HttpService.JSONEncode, HttpService, res)
	if okJ and #js > 24000 then
		return {ok = true, truncated = true, partial = js:sub(1, 20000), note = "Result too large. Narrow the request (smaller depth/limit/line range)."}
	end
	return res
end

local function pushUserText(text)
	local last = history[#history]
	if last and last.role == "user" and type(last.content) == "string" then
		last.content = last.content .. "\n\n" .. text
	else
		table.insert(history, {role = "user", content = text})
	end
end

-- ---------- agent loop ----------
local function setBusy(v)
	busy = v
	stopBtn.Visible = v
end

local function agentLoop(rc)
	local step, bad = 0, 0
	local maxTokens = 16384
	while not stopFlag do
		step += 1
		if step > MAX_STEPS then
			addMessage("sys", "Reached the step limit (" .. MAX_STEPS .. "). Send \"continue\" to keep going.")
			return "done"
		end
		compact()
		rc.setAction("Thinking (step " .. step .. ")")
		local data, err = llmRequest(maxTokens)
		if not data then
			if stopFlag then return "stopped" end
			local low = tostring(err):lower()
			if maxTokens > 4096 and (low:find("max_tokens") or low:find("max tokens") or low:find("completion tokens") or low:find("max_completion")) then
				maxTokens = 4096
				step -= 1
				continue
			end
			if low:find("context") and (low:find("length") or low:find("exceed") or low:find("maximum")) then
				if dropOldest() then
					addMessage("sys", "Context was too long: dropped the oldest part of the conversation and retrying.")
					step -= 1
					continue
				end
			end
			addMessage("sys", "Error: " .. tostring(err))
			return "error"
		end
		local choice = data.choices and data.choices[1]
		local msg = choice and choice.message
		if type(msg) ~= "table" then
			bad += 1
			if bad > 2 then addMessage("sys", "The model returned nothing. Try again or rephrase.") return "error" end
			task.wait(2)
			continue
		end
		local finish = choice.finish_reason
		local text = type(msg.content) == "string" and trim((msg.content:gsub("<think>.-</think>", ""))) or ""
		local thought = msg.reasoning_content or msg.reasoning
		if type(thought) == "string" then rc.addNote(thought) end
		local calls = {}
		if type(msg.tool_calls) == "table" then
			for i, tc in ipairs(msg.tool_calls) do
				local f = type(tc) == "table" and tc["function"] or nil
				if f and f.name then
					local argStr = f.arguments
					if type(argStr) == "table" then
						local okA, enc = pcall(HttpService.JSONEncode, HttpService, argStr)
						argStr = okA and enc or "{}"
					end
					if type(argStr) ~= "string" or argStr == "" then argStr = "{}" end
					table.insert(calls, {id = tc.id or ("call_" .. step .. "_" .. i), name = f.name, argStr = argStr})
				end
			end
		end
		if text ~= "" then
			addMessage("model", text)
			registerCode(text, "ai")
		end
		local stored = {role = "assistant"}
		if text ~= "" then stored.content = text end
		if #calls > 0 then
			stored.tool_calls = {}
			for _, c in ipairs(calls) do
				table.insert(stored.tool_calls, {id = c.id, type = "function", ["function"] = {name = c.name, arguments = c.argStr}})
			end
		end
		if #calls == 0 then
			if text == "" then
				bad += 1
				if bad > 2 then addMessage("sys", "The model returned an empty reply" .. (finish and (" (" .. tostring(finish) .. ")") or "") .. ". Try again.") return "error" end
				pushUserText("Your last reply was empty. Continue the task: call a tool, or give the final answer.")
			else
				bad = 0
				table.insert(history, stored)
				if finish == "length" then
					pushUserText("Continue exactly where you stopped.")
				elseif #pendingUser > 0 then
					pushUserText(table.remove(pendingUser, 1))
				else
					return "done"
				end
			end
		else
			bad = 0
			table.insert(history, stored)
			for _, c in ipairs(calls) do
				local okA, args = pcall(HttpService.JSONDecode, HttpService, c.argStr)
				local result
				local done = rc.addStep(c.name, okA and type(args) == "table" and args or {})
				if stopFlag then
					result = fail("Stopped by the user")
				elseif not okA or type(args) ~= "table" then
					result = fail("Invalid JSON in tool arguments (the output was probably cut off). Retry with simpler arguments.")
				else
					result = execTool(c.name, args)
				end
				done(result)
				local okJ, js = pcall(HttpService.JSONEncode, HttpService, result)
				table.insert(history, {role = "tool", tool_call_id = c.id, content = okJ and js or '{"ok":false,"error":"result not encodable"}'})
			end
			while #pendingUser > 0 do
				pushUserText("USER (sent while you were working): " .. table.remove(pendingUser, 1))
			end
			task.wait(0.1)
		end
	end
	return "stopped"
end

local function runAgent()
	setBusy(true)
	stopFlag = false
	local rc = newRunCard()
	currentCard = rc
	local okk, result = pcall(agentLoop, rc)
	if not okk then
		addMessage("sys", "Assistant crashed: " .. tostring(result))
		result = "error"
	end
	rc.finish(result)
	currentCard = nil
	setBusy(false)
	stopFlag = false
end

-- ---------- settings panel ----------
local settingsPanel = round(new("Frame", {Size = UDim2.new(1, -16, 1, -40), Position = UDim2.fromOffset(8, 34), BackgroundColor3 = C.bg, Visible = false, ZIndex = 10, BorderSizePixel = 0}, pAI), 12)
settingsPanel.BackgroundTransparency = 0.04
local setScroll = vscroll(settingsPanel, UDim2.new(1, -12, 1, -12), UDim2.fromOffset(6, 6))
setScroll.ZIndex = 10
new("UIListLayout", {Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder}, setScroll)
local sOrder = 0
local function sNext() sOrder += 1 return sOrder end
local function sLabel(t)
	local l = label(setScroll, t, UDim2.new(1, -6, 0, 0), nil, C.sub, 11)
	l.AutomaticSize = Enum.AutomaticSize.Y
	l.LayoutOrder = sNext()
	l.ZIndex = 10
	return l
end
sLabel("NVIDIA API key (starts with nvapi-). Get a free one at build.nvidia.com. Saved only on this device. Long-press the box to paste.")
local keyBox = box(setScroll, "nvapi-...", UDim2.new(1, -6, 0, 38))
keyBox.LayoutOrder = sNext()
keyBox.ZIndex = 10
keyBox.TextSize = 12
keyBox.Font = Enum.Font.Code
keyBox.Text = getKey()
sLabel("Model")
local modelBox = box(setScroll, NV_DEFAULT_MODEL, UDim2.new(1, -6, 0, 34))
modelBox.LayoutOrder = sNext()
modelBox.ZIndex = 10
modelBox.Text = (type(db.set.nvModel) == "string" and db.set.nvModel ~= "") and db.set.nvModel or NV_DEFAULT_MODEL
local function refreshModelLabel()
	modelLbl.Text = modelName()
end
do
	local b = btn(setScroll, "", UDim2.new(1, -6, 0, 36), nil, C.card, 12)
	b.LayoutOrder = sNext()
	b.ZIndex = 10
	local function paint()
		local on = setting("allowRun", true)
		b.Text = "Allow AI to run scripts for testing:  " .. (on and "ON" or "OFF")
		b.BackgroundColor3 = on and C.accent or C.card
	end
	b.MouseButton1Click:Connect(function()
		db.set.allowRun = not setting("allowRun", true)
		saveDB()
		paint()
	end)
	paint()
end
local saveKeyBtn = btn(setScroll, "Save", UDim2.new(1, -6, 0, 38), nil, C.good, 14)
saveKeyBtn.LayoutOrder = sNext()
saveKeyBtn.ZIndex = 10
saveKeyBtn.MouseButton1Click:Connect(function()
	local k = trim(keyBox.Text):gsub("^[Bb]earer%s+", ""):gsub("[%s\"']", "")
	db.set.nvKey = k
	keyBox.Text = k
	local m = trim(modelBox.Text)
	db.set.nvModel = (m ~= "") and m or NV_DEFAULT_MODEL
	modelBox.Text = db.set.nvModel
	saveDB()
	refreshModelLabel()
	settingsPanel.Visible = false
	showToast(k ~= "" and "AI settings saved" or "API key removed")
end)
setBtn.MouseButton1Click:Connect(function() settingsPanel.Visible = not settingsPanel.Visible end)
refreshModelLabel()

-- ---------- input wiring ----------
local function submit()
	local txt = trim(inputBox.Text)
	if txt == "" then return end
	if getKey() == "" then
		settingsPanel.Visible = true
		showToast("Add your NVIDIA API key first")
		return
	end
	inputBox.Text = ""
	addMessage("user", txt)
	local note = registerCode(txt, "user")
	local sendText = txt
	if note ~= "" then
		sendText = txt .. "\n\n[Detected pasted script saved as: " .. note .. ". Use run_script with script_id to test it.]"
	end
	if busy then
		table.insert(pendingUser, sendText)
		showToast("Sent to the assistant")
		return
	end
	pushUserText(sendText)
	task.spawn(runAgent)
end
sendBtn.MouseButton1Click:Connect(submit)
stopBtn.MouseButton1Click:Connect(function()
	stopFlag = true
	if currentCard then currentCard.setAction("Stopping...") end
end)
clearBtn.MouseButton1Click:Connect(function()
	if busy then showToast("Stop the assistant first") return end
	history = {}
	pendingUser = {}
	codeStore, codeCount = {}, {user = 0, ai = 0}
	clearGui(chatScroll)
	showToast("Chat cleared")
end)

for i, c in ipairs({
	{"Fix my script", "My script has an error. Check the output, find the cause and send me the complete fixed script. Keep every feature and the whole UI the same, only change the fix."},
	{"Explore the game", "Look at Workspace, ReplicatedStorage, ServerScriptService, StarterGui and the remotes, then explain how this game is set up."},
	{"Write a script", "Write a speed adjustment UI script (draggable, with a slider for WalkSpeed)."},
	{"Map ideas", "Check my current map and recommend what I can add to make it better."},
}) do
	local chip = btn(chips, c[1], UDim2.fromOffset(#c[1] * 7 + 26, 24), nil, C.card, 11)
	chip.LayoutOrder = i
	chip.MouseButton1Click:Connect(function() inputBox.Text = c[2] inputBox:CaptureFocus() end)
end

addMessage("model", "Hi! I can chat, write scripts and fix errors. I can look at your game (Workspace, scripts, remotes, output) but I can't add anything to it myself: you copy my scripts and paste them. Add your NVIDIA API key in Settings to start.")

end -- buildAIPage
buildAIPage()

-- ===== Tabs =====
local TABS = {
	{"Store", "bag", "Store"},
	{"Saved", "bookmark", "Saved"},
	{"AI", "chat", "AI Assistant"},
}
local tabBtns, tabIcons = {}, {}
local function showTab(name)
	for n, p in pairs(pages) do p.Visible = (n == name) end
	for n, b in pairs(tabBtns) do
		local on = (n == name)
		b.BackgroundColor3 = on and C.accent or C.card
		b.TextColor3 = on and Color3.new(1, 1, 1) or C.sub
		setIconColor(tabIcons[n], b.TextColor3)
	end
	if name == "Saved" and refreshSaved then refreshSaved() end
end
for i, t in ipairs(TABS) do
	local b, ic = iconBtn(tabBar, t[2], t[3], UDim2.fromOffset(#t[3] * 8 + 46, 28), nil, C.card, 12, 14)
	b.LayoutOrder = i
	tabBtns[t[1]] = b
	tabIcons[t[1]] = ic
	b.MouseButton1Click:Connect(function() showTab(t[1]) end)
end

-- ===== Force landscape =====
local landscapeLock = true
local orient = Enum.ScreenOrientation.LandscapeSensor
local function getPG()
	local lp = Players.LocalPlayer
	return lp and lp:FindFirstChildOfClass("PlayerGui")
end
local function enforceOrientation()
	local pg = getPG()
	if not pg then return end
	local want = landscapeLock and orient or Enum.ScreenOrientation.Sensor
	if pg.ScreenOrientation ~= want then
		pcall(function() pg.ScreenOrientation = want end)
	end
end
btnLandscape.MouseButton1Click:Connect(function()
	landscapeLock = not landscapeLock
	if landscapeLock then orient = Enum.ScreenOrientation.LandscapeSensor end
	btnLandscape.BackgroundColor3 = landscapeLock and C.accent or C.card
	enforceOrientation()
	showToast(landscapeLock and "Landscape locked (auto)" or "Auto-rotate on")
end)
btnReverse.MouseButton1Click:Connect(function()
	landscapeLock = true
	if orient == Enum.ScreenOrientation.LandscapeLeft then
		orient = Enum.ScreenOrientation.LandscapeRight
	else
		orient = Enum.ScreenOrientation.LandscapeLeft
	end
	btnLandscape.BackgroundColor3 = C.accent
	enforceOrientation()
	showToast(orient == Enum.ScreenOrientation.LandscapeLeft and "Landscape Left" or "Landscape Right")
end)
task.spawn(function()
	local pg = getPG() or (Players.LocalPlayer and Players.LocalPlayer:WaitForChild("PlayerGui", 10))
	if pg then
		pg:GetPropertyChangedSignal("ScreenOrientation"):Connect(enforceOrientation)
	end
	while gui.Parent do
		enforceOrientation()
		task.wait(0.5)
	end
end)

-- ===== Start =====
apply()
showTab("Store")
