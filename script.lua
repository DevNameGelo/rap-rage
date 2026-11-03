print("[RGC Glass Creator Studio] v2.2 loaded - server insert + Bridge tab")
-- RGC Glass Creator Studio v2 | DevNameGelo · RGC
-- AI Agent with real tool calling (Gemini function calling), glass UI, Creator Store browser
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
local old = parentGui:FindFirstChild("RGC_CreatorStore")
if old then old:Destroy() end
local oldSnd = SoundService:FindFirstChild("RGC_CS_Sound")
if oldSnd then oldSnd:Destroy() end

-- ===== Config =====
local CATS = {
	{name = "Models",     id = 10,  icon = "📦"},
	{name = "Images",     id = 13,  icon = "🖼"},
	{name = "Sound FX",   id = 3,   icon = "🔊"},
	{name = "Music",      id = 300, icon = "🎵"},
	{name = "Plugins",    id = 38,  icon = "🔌"},
	{name = "Meshes",     id = 40,  icon = "🔷"},
	{name = "Animations", id = 24,  icon = "🏃"},
	{name = "Video",      id = 62,  icon = "🎬"},
	{name = "Fonts",      id = 73,  icon = "Aa"},
}
local TYPE_NAMES = {[1]="Image",[3]="Sound FX",[4]="Mesh",[10]="Model",[13]="Decal",[24]="Animation",[38]="Plugin",[40]="MeshPart",[62]="Video",[73]="Font",[300]="Music"}
local TYPE_ICONS = {[1]="🖼",[3]="🔊",[4]="🔷",[10]="📦",[13]="🖼",[24]="🏃",[38]="🔌",[40]="🔷",[62]="🎬",[73]="Aa",[300]="🎵"}
local PAGE_SIZE = 30
local DEFAULT_MODEL = "gemini-flash-latest"
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
		Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = TYPE_ICONS[typeId] or "📦",
		TextColor3 = C.sub, TextSize = 28, Font = Enum.Font.GothamBold,
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

-- ===== Root GUI =====
local gui = new("ScreenGui", {
	Name = "RGC_CreatorStore", ResetOnSpawn = false, IgnoreGuiInset = true,
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
	Size = UDim2.fromOffset(40, 24), Position = UDim2.fromOffset(8, 7), BackgroundColor3 = C.accent,
	Text = "RGC", TextColor3 = Color3.new(1, 1, 1), Font = Enum.Font.GothamBlack, TextSize = 12, BorderSizePixel = 0,
}, top), 12)
new("UIGradient", {Color = ColorSequence.new(C.accent, C.accent2), Rotation = 30}, logo)
new("TextLabel", {
	Size = UDim2.new(1, -250, 1, 0), Position = UDim2.fromOffset(56, 0), BackgroundTransparency = 1,
	Text = "Glass Creator Studio", TextColor3 = C.text, Font = Enum.Font.GothamBold,
	TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
}, top)
local function topBtn(txt, xOff, color)
	local b = btn(top, txt, UDim2.fromOffset(30, 26), UDim2.new(1, xOff, 0.5, -13), color, 12)
	b.ZIndex = 3
	return b
end
local btnClose = topBtn("X", -38, C.bad)
local btnExpand = topBtn("[]", -72)
local btnCollapse = topBtn("-", -106)
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
	BackgroundColor3 = C.accent, Text = "RGC", TextColor3 = Color3.new(1, 1, 1),
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
	btnCollapse.Text = "-"
	main.Position = UDim2.fromScale(0.5, 0.5)
	btnExpand.Text = expanded and "][" or "[]"
	apply()
end)
btnCollapse.MouseButton1Click:Connect(function()
	collapsed = not collapsed
	btnCollapse.Text = collapsed and "+" or "-"
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


-- ===== Server bridge (remotes) =====
-- An executor only runs on the client. Anything created here is invisible to the server.
-- To make REAL changes we call the game's own remotes (Studio Lite has them).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local function instPath(inst)
	if inst == game then return "game" end
	local parts, cur = {}, inst
	while cur and cur ~= game do
		table.insert(parts, 1, cur.Name)
		cur = cur.Parent
	end
	if cur ~= game then return "(detached)/" .. table.concat(parts, "/") end
	return table.concat(parts, "/")
end

-- Values <-> JSON-friendly tagged values ("v3:1,2,3", "inst:Workspace/Part", ...)
local function toTagged(v, depth)
	depth = depth or 0
	local t = typeof(v)
	if t == "string" or t == "number" or t == "boolean" then return v end
	if t == "nil" then return "nil:" end
	if t == "Vector3" then return ("v3:%g,%g,%g"):format(v.X, v.Y, v.Z) end
	if t == "Vector2" then return ("v2:%g,%g"):format(v.X, v.Y) end
	if t == "Color3" then return ("c3:%d,%d,%d"):format(math.round(v.R * 255), math.round(v.G * 255), math.round(v.B * 255)) end
	if t == "CFrame" then
		local c = {v:GetComponents()}
		for i, n in ipairs(c) do c[i] = ("%g"):format(n) end
		return "cf:" .. table.concat(c, ",")
	end
	if t == "Instance" then return "inst:" .. instPath(v) end
	if t == "EnumItem" then return "enum:" .. tostring(v) end
	if t == "table" then
		if depth >= 3 then return "<table too deep>" end
		local out, n, isArray = {}, 0, true
		for k in pairs(v) do
			n += 1
			if type(k) ~= "number" then isArray = false end
		end
		if n > 40 then return "<table with " .. n .. " entries>" end
		if isArray then
			for i = 1, #v do out[i] = toTagged(v[i], depth + 1) end
		else
			for k, x in pairs(v) do out[tostring(k)] = toTagged(x, depth + 1) end
		end
		return out
	end
	return "<" .. t .. ">"
end
local function numsIn(s)
	local t = {}
	for n in tostring(s):gmatch("[-+]?%d*%.?%d+") do table.insert(t, tonumber(n)) end
	return t
end
local resolveForTag -- set later (needs path resolver)
local function fromTagged(v)
	if type(v) == "string" then
		if v == "nil:" then return nil end
		local p = v:sub(1, 3)
		local rest = v:sub(4)
		if p == "v3:" then local n = numsIn(rest) return Vector3.new(n[1] or 0, n[2] or 0, n[3] or 0) end
		if p == "v2:" then local n = numsIn(rest) return Vector2.new(n[1] or 0, n[2] or 0) end
		if p == "c3:" then local n = numsIn(rest) return Color3.fromRGB(n[1] or 0, n[2] or 0, n[3] or 0) end
		if p == "cf:" then
			local n = numsIn(rest)
			if #n == 12 then return CFrame.new(unpack(n)) end
			return CFrame.new(n[1] or 0, n[2] or 0, n[3] or 0)
		end
		if v:sub(1, 5) == "inst:" then
			local inst = resolveForTag and resolveForTag(v:sub(6))
			return inst
		end
		return v
	elseif type(v) == "table" then
		local out = {}
		for k, x in pairs(v) do out[k] = fromTagged(x) end
		return out
	end
	return v
end
local function jsonOf(v)
	local ok, s = pcall(HttpService.JSONEncode, HttpService, v)
	return ok and s or tostring(v)
end
local function argsToJson(args, n)
	local list = {}
	for i = 1, n do list[i] = toTagged(args[i], 0) end
	return jsonOf(list)
end

local spy = {on = false, ignore = false, hooked = false, log = {}, onLog = nil}
function spy.install()
	if spy.hooked then return true end
	if not (hookmetamethod and getnamecallmethod) then
		return false, "Your executor has no hookmetamethod/getnamecallmethod, so it cannot record remote calls."
	end
	local okH, errH = pcall(function()
		local old
		local function hook(self, ...)
			local method = getnamecallmethod()
			if spy.on and not spy.ignore and (method == "FireServer" or method == "InvokeServer") then
				local okC, cn = pcall(function() return self.ClassName end)
				if okC and (cn == "RemoteEvent" or cn == "RemoteFunction" or cn == "UnreliableRemoteEvent") then
					local n = select("#", ...)
					local args = {...}
					task.defer(function()
						local okE, entry = pcall(function()
							return {remote = instPath(self), class = cn, method = method, args = argsToJson(args, n), t = os.clock()}
						end)
						if okE then
							local last = spy.log[#spy.log]
							if last and last.remote == entry.remote and last.args == entry.args and entry.t - last.t < 0.4 then
								last.count = (last.count or 1) + 1
								last.t = entry.t
							else
								entry.count = 1
								table.insert(spy.log, entry)
								if #spy.log > 300 then table.remove(spy.log, 1) end
							end
							if spy.onLog then pcall(spy.onLog) end
						end
					end)
				end
			end
			if setnamecallmethod then pcall(setnamecallmethod, method) end
			return old(self, ...)
		end
		old = hookmetamethod(game, "__namecall", newcclosure and newcclosure(hook) or hook)
	end)
	if not okH then return false, "Hook failed: " .. tostring(errH) end
	spy.hooked = true
	return true
end
function spy.fmt(e)
	local s = e.method .. "  " .. e.remote .. "  " .. e.args
	if (e.count or 1) > 1 then s = s .. "   x" .. e.count end
	return s
end
function spy.text(limit)
	local lines = {}
	local from = math.max(1, #spy.log - (limit or 60) + 1)
	for i = from, #spy.log do lines[#lines + 1] = spy.fmt(spy.log[i]) end
	return table.concat(lines, "\n")
end

local function callRemote(remote, method, args, n)
	spy.ignore = true
	local res = table.pack(pcall(function()
		if method == "invoke" then
			return remote:InvokeServer(table.unpack(args, 1, n))
		end
		remote:FireServer(table.unpack(args, 1, n))
		return nil
	end))
	spy.ignore = false
	return res
end

local function isRemote(o)
	return o:IsA("RemoteEvent") or o:IsA("RemoteFunction") or o:IsA("UnreliableRemoteEvent")
end
local function scanRemotes(root, limit)
	local out = {}
	root = root or ReplicatedStorage
	local okD, desc = pcall(root.GetDescendants, root)
	if not okD then return out end
	for _, d in ipairs(desc) do
		if isRemote(d) then
			table.insert(out, {path = instPath(d), class = d.ClassName})
			if #out >= (limit or 200) then break end
		end
	end
	table.sort(out, function(a, b) return a.path < b.path end)
	return out
end

-- Studio Lite's own model loader: Clear then Load (both RemoteFunctions). Inserts on the SERVER.
local function serverInsertAsset(id)
	local folder = ReplicatedStorage:FindFirstChild("StudioLiteFolder")
	local clear = folder and folder:FindFirstChild("ClearAssetModelToPlayerGuiServerFunction")
	local load = folder and folder:FindFirstChild("LoadAssetModelToPlayerGuiServerFunction")
	if not (clear and load) then return false, "Studio Lite remotes not found in ReplicatedStorage.StudioLiteFolder" end
	local lp = Players.LocalPlayer
	local function snapshot()
		local s = {}
		local function add(root, label_)
			if root then
				for _, c in ipairs(root:GetChildren()) do s[c] = label_ end
			end
		end
		add(Workspace, "Workspace")
		add(lp and lp:FindFirstChildOfClass("PlayerGui"), "PlayerGui")
		return s
	end
	local before = snapshot()
	local sid = tostring(id)
	spy.ignore = true
	local okC = pcall(function() return clear:InvokeServer(sid) end)
	local okL, resL = pcall(function() return load:InvokeServer(sid) end)
	spy.ignore = false
	if not okL then return false, tostring(resL) end
	task.wait(1.2)
	local found = {}
	local function scan(root, label_)
		if not root then return end
		for _, c in ipairs(root:GetChildren()) do
			if not before[c] and not c:IsDescendantOf(gui) then table.insert(found, {name = c.Name, where = label_}) end
		end
	end
	scan(Workspace, "Workspace")
	scan(lp and lp:FindFirstChildOfClass("PlayerGui"), "PlayerGui")
	return true, found, resL, okC
end

local aiPrefill, gotoTab
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
local projectRoot = Workspace:FindFirstChild("RGC_Project")
if not projectRoot then
	projectRoot = Instance.new("Folder")
	projectRoot.Name = "RGC_Project"
	projectRoot.Parent = Workspace
end
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
	TextSize = 40, Font = Enum.Font.GothamBold,
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
local bInsert = dBtn("Insert to Workspace", 9, C.good)
local bClose = btn(dCard, "X", UDim2.fromOffset(28, 26), UDim2.new(1, -34, 0, 4), C.accent, 13)

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
	dIcon.Text = TYPE_ICONS[m.typeId] or "📦"
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
bInsert.MouseButton1Click:Connect(function()
	if not curItem then return end
	local item = curItem
	local id, typeId = tonumber(item.id), tonumber(item.typeId)
	if not id then showToast("Invalid asset ID") return end
	-- Real SERVER-side insert through Studio Lite's own remotes (Clear, then Load)
	if typeId ~= 38 then
		showToast("Inserting on server...")
		local okS, found = serverInsertAsset(id)
		if okS then
			detail.Visible = false
			if #found > 0 then
				showToast("Inserted on server: " .. tostring(found[1].name):sub(1, 22) .. " (" .. found[1].where .. ")")
			else
				showToast("Server accepted the insert. Check Studio Lite's Dex / Workspace.")
			end
			return
		end
		showToast("Server insert failed (" .. tostring(found):sub(1, 50) .. "). Inserting locally only.")
		task.wait(1.8)
	end
	local lp = Players.LocalPlayer
	local hrp = lp and lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
	local target = hrp and (hrp.Position + hrp.CFrame.LookVector * 14) or Vector3.new(0, 10, 0)
	local groundY = hrp and (hrp.Position.Y - 3) or 0
	local function disableImportedScripts(root)
		local function off(o)
			if o:IsA("LuaSourceContainer") then
				pcall(function() o.Disabled = true end)
				pcall(function() o.Enabled = false end)
			end
		end
		off(root)
		for _, child in ipairs(root:GetDescendants()) do off(child) end
	end
	local function place(obj)
		obj.Parent = Workspace
		if obj.Parent ~= Workspace then error("Roblox refused to put it in Workspace") end
		if obj:IsA("Model") then
			pcall(function()
				obj:PivotTo(CFrame.new(target))
				local cf, size = obj:GetBoundingBox()
				obj:PivotTo(obj:GetPivot() + Vector3.new(0, groundY - (cf.Position.Y - size.Y / 2), 0))
			end)
		elseif obj:IsA("BasePart") then
			obj.Position = target
		end
		return obj
	end
	local function makePart()
		local p = Instance.new("Part")
		p.Name = item.name or "ImportedAsset"
		p.Anchored = true
		p.Size = Vector3.new(4, 1, 4)
		p.Position = target + Vector3.new(0, 2, 0)
		return p
	end
	local KNOWN = {[3] = true, [300] = true, [13] = true, [1] = true, [40] = true, [4] = true, [24] = true, [62] = true, [38] = true}
	local placed = nil
	local ok, msg = pcall(function()
		if typeId == 3 or typeId == 300 then
			local snd = Instance.new("Sound")
			snd.Name = item.name or "ImportedAudio"
			snd.SoundId = "rbxassetid://" .. id
			snd.Volume = 1
			placed = place(snd)
		elseif typeId == 13 or typeId == 1 then
			local part = makePart()
			local decal = Instance.new("Decal")
			decal.Name = "ImportedDecal"; decal.Texture = "rbxassetid://" .. id
			decal.Face = Enum.NormalId.Top; decal.Parent = part
			placed = place(part)
		elseif typeId == 40 or typeId == 4 then
			local part = makePart()
			local mesh = Instance.new("SpecialMesh")
			mesh.MeshType = Enum.MeshType.FileMesh; mesh.MeshId = "rbxassetid://" .. id; mesh.Parent = part
			placed = place(part)
		elseif typeId == 24 then
			local anim = Instance.new("Animation")
			anim.Name = item.name or "ImportedAnimation"; anim.AnimationId = "rbxassetid://" .. id
			placed = place(anim)
		elseif typeId == 62 then
			local part = makePart()
			local surface = Instance.new("SurfaceGui"); surface.Face = Enum.NormalId.Front; surface.Parent = part
			local video = Instance.new("VideoFrame"); video.Size = UDim2.fromScale(1, 1); video.Video = "rbxassetid://" .. id; video.Parent = surface
			placed = place(part)
		elseif typeId == 38 then
			error("Plugins cannot be installed from an in-game runtime. Copy the ID and install through Studio.")
		else
			-- models (and anything not recognised): load the real asset
			local objects
			local okGet, got = pcall(function() return game:GetObjects("rbxassetid://" .. id) end)
			if okGet and type(got) == "table" and #got > 0 then objects = got end
			if not objects then
				local okLoad, loaded = pcall(function() return game:GetService("InsertService"):LoadAsset(id) end)
				if okLoad and loaded then objects = loaded:GetChildren() end
			end
			if not objects or #objects == 0 then error("Roblox blocked loading this model in this game/runtime") end
			for _, obj in ipairs(objects) do
				disableImportedScripts(obj)
				placed = place(obj)
			end
		end
	end)
	if ok then
		detail.Visible = false
		showToast("Inserted LOCALLY (only you can see it)" .. (placed and (": " .. tostring(placed.Name):sub(1, 24)) or "") .. (hrp and " (in front of you)" or ""))
	else
		showToast("Insert failed: " .. tostring(msg):sub(1, 90))
	end
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
		Text = c.icon .. " " .. c.name, TextColor3 = C.text,
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

local function buildSnippetsPage()
-- ===== SNIPPETS PAGE =====
local pSnip = newPage("Snippets")
local SNIPPETS = {
	{"Touch door (open/close)", [==[-- Script inside the door Part (Anchored = true)
local door = script.Parent
local TweenService = game:GetService("TweenService")
local closedCF = door.CFrame
local openCF = closedCF * CFrame.new(0, door.Size.Y, 0)
local open = false

door.Touched:Connect(function(hit)
	if open or not hit.Parent:FindFirstChildOfClass("Humanoid") then return end
	open = true
	TweenService:Create(door, TweenInfo.new(0.5), {CFrame = openCF}):Play()
	task.wait(3)
	TweenService:Create(door, TweenInfo.new(0.5), {CFrame = closedCF}):Play()
	open = false
end)]==]},
	{"Kill brick", [==[-- Script inside a Part
script.Parent.Touched:Connect(function(hit)
	local hum = hit.Parent:FindFirstChildOfClass("Humanoid")
	if hum then hum.Health = 0 end
end)]==]},
	{"Leaderstats (Coins)", [==[-- Script in ServerScriptService
game.Players.PlayerAdded:Connect(function(player)
	local ls = Instance.new("Folder")
	ls.Name = "leaderstats"
	ls.Parent = player

	local coins = Instance.new("IntValue")
	coins.Name = "Coins"
	coins.Value = 0
	coins.Parent = ls
end)]==]},
	{"Coin pickup", [==[-- Script inside a Part (needs the Leaderstats script)
local part = script.Parent
local used = false

part.Touched:Connect(function(hit)
	if used then return end
	local player = game.Players:GetPlayerFromCharacter(hit.Parent)
	if not player then return end
	used = true
	player.leaderstats.Coins.Value += 1
	part:Destroy()
end)]==]},
	{"Teleporter pad", [==[-- Script inside the pad Part
local pad = script.Parent
local target = workspace:WaitForChild("TeleportTarget") -- Part to teleport to

pad.Touched:Connect(function(hit)
	local root = hit.Parent:FindFirstChild("HumanoidRootPart")
	if root then
		root.CFrame = target.CFrame + Vector3.new(0, 4, 0)
	end
end)]==]},
	{"Spinning part", [==[-- Script inside a Part
local part = script.Parent
game:GetService("RunService").Heartbeat:Connect(function(dt)
	part.CFrame *= CFrame.Angles(0, math.rad(90) * dt, 0)
end)]==]},
	{"Shop (ProximityPrompt)", [==[-- Script inside a Part that has a ProximityPrompt
local prompt = script.Parent:FindFirstChildOfClass("ProximityPrompt")
local PRICE = 50

prompt.Triggered:Connect(function(player)
	local coins = player.leaderstats.Coins
	if coins.Value >= PRICE then
		coins.Value -= PRICE
		-- give the item here
	end
end)]==]},
	{"Day / night cycle", [==[-- Script in ServerScriptService
local Lighting = game:GetService("Lighting")
while true do
	Lighting.ClockTime = (Lighting.ClockTime + 0.05) % 24
	task.wait(0.1)
end]==]},
	{"Checkpoint", [==[-- Script inside a SpawnLocation (set Neutral = false)
local spawn = script.Parent
spawn.Touched:Connect(function(hit)
	local player = game.Players:GetPlayerFromCharacter(hit.Parent)
	if player then player.RespawnLocation = spawn end
end)]==]},
	{"GUI button pop (LocalScript)", [==[-- LocalScript inside a TextButton
local button = script.Parent
local TweenService = game:GetService("TweenService")

button.MouseButton1Click:Connect(function()
	local info = TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, true)
	TweenService:Create(button, info, {Size = button.Size + UDim2.fromOffset(10, 10)}):Play()
end)]==]},
	{"Tool activated", [==[-- Script inside a Tool
local tool = script.Parent
tool.Activated:Connect(function()
	print(tool.Parent.Name .. " used " .. tool.Name)
end)]==]},
	{"Play sound on touch", [==[-- Script inside a Part that has a Sound child
local part = script.Parent
local sound = part:FindFirstChildOfClass("Sound")
local cooldown = false

part.Touched:Connect(function(hit)
	if cooldown or not hit.Parent:FindFirstChildOfClass("Humanoid") then return end
	cooldown = true
	sound:Play()
	task.wait(1)
	cooldown = false
end)]==]},
}
local snipScroll = vscroll(pSnip, UDim2.new(1, -16, 1, -4), UDim2.fromOffset(8, 0))
new("UIListLayout", {Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder}, snipScroll)
for i, s in ipairs(SNIPPETS) do
	local row = round(new("Frame", {
		Size = UDim2.new(1, -6, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = C.bar, LayoutOrder = i,
	}, snipScroll), 8)
	new("UIPadding", {PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 4), PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6)}, row)
	new("UIListLayout", {Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder}, row)
	local head = new("Frame", {Size = UDim2.new(1, 0, 0, 28), BackgroundTransparency = 1, LayoutOrder = 1}, row)
	local title = btn(head, s[1], UDim2.new(1, -70, 1, 0), nil, C.card, 12)
	title.TextXAlignment = Enum.TextXAlignment.Left
	local cp = btn(head, "Copy", UDim2.fromOffset(62, 28), UDim2.new(1, -62, 0, 0), C.accent, 12)
	local code = label(row, s[2], UDim2.new(1, 0, 0, 0), nil, C.sub, 11, Enum.Font.Code)
	code.AutomaticSize = Enum.AutomaticSize.Y
	code.TextYAlignment = Enum.TextYAlignment.Top
	code.Visible = false
	code.LayoutOrder = 2
	title.MouseButton1Click:Connect(function() code.Visible = not code.Visible end)
	cp.MouseButton1Click:Connect(function() copyOut(s[2], s[1]) end)
end

end -- buildSnippetsPage
buildSnippetsPage()

local function buildAIPage()
-- ===== AI AGENT (OpenRouter tool calling) =====
local pAI = newPage("AI")
local LogService = game:GetService("LogService")
local InsertService = game:GetService("InsertService")
local lp = Players.LocalPlayer

-- ---------- state ----------
local history = {}          -- OpenAI-style chat messages
local busy, stopFlag = false, false
local notes = ""
local undoGroups, currentGroup = {}, nil
local pendingUser = {}
local spawned = {}          -- threads started by run_script
local scriptOut = {}        -- output captured from run_script
local changeCount = 0

local function setting(name, default)
	local v = db.set[name]
	if v == nil then return default end
	return v
end
local function getKey()
	local k = db.set.orKey
	if type(k) ~= "string" then return "" end
	return (k:gsub("%s+", ""))
end

local logBuf = {}
pcall(function()
	LogService.MessageOut:Connect(function(msg, typ)
		local kind = "out"
		if typ == Enum.MessageType.MessageError then kind = "error" elseif typ == Enum.MessageType.MessageWarning then kind = "warn" end
		table.insert(logBuf, kind .. ": " .. tostring(msg))
		if #logBuf > 300 then table.remove(logBuf, 1) end
	end)
end)

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
local function logUndo(e)
	changeCount += 1
	if currentGroup then table.insert(currentGroup, e) end
end

-- ---------- paths ----------
local SERVICES = {}
for _, n in ipairs({"Workspace", "ReplicatedStorage", "ReplicatedFirst", "ServerScriptService", "ServerStorage", "StarterGui", "StarterPack", "StarterPlayer", "Lighting", "Players", "SoundService", "Teams", "TextChatService", "Chat", "MaterialService", "Debris", "RunService", "TweenService", "CollectionService", "UserInputService", "HttpService", "MarketplaceService", "InsertService", "PhysicsService", "ContextActionService"}) do
	SERVICES[n:lower()] = n
end

local function isHidden(inst)
	if inst == gui then return true end
	return inst:IsA("StringValue") and inst.Name:sub(1, 10) == "RGC_Source"
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
	if low == "project" or low == "rgc_project" then cur = projectRoot
	elseif low == "localplayer" then cur = lp
	elseif low == "playergui" then cur = lp and lp:FindFirstChildOfClass("PlayerGui")
	elseif low == "character" then cur = lp and lp.Character
	elseif low == "camera" or low == "currentcamera" then cur = Workspace.CurrentCamera
	elseif low == "terrain" then cur = Workspace.Terrain
	elseif SERVICES[low] then
		local s, svc = pcall(game.GetService, game, SERVICES[low])
		cur = s and svc or nil
	else
		cur = game:FindFirstChild(first) or projectRoot:FindFirstChild(first)
	end
	if not cur then
		if not slash then
			local deep = projectRoot:FindFirstChild(p, true)
			if deep then return deep end
		end
		return nil, "Not found: '" .. first .. "'. Top-level: " .. listNames(game, 40)
	end
	for i = 2, #segs do
		local nxt
		if segs[i] == "LocalPlayer" and cur == Players then nxt = lp else nxt = cur:FindFirstChild(segs[i]) end
		if not nxt then
			if not slash then
				local deep = projectRoot:FindFirstChild(p, true)
				if deep then return deep end
			end
			return nil, ("Not found: '%s' under %s. Children there: %s"):format(segs[i], pathOf(cur), listNames(cur, 25))
		end
		cur = nxt
	end
	return cur
end

local function destroyBlocked(inst)
	if inst == game or inst.Parent == game then return "Services cannot be deleted/moved" end
	if inst == gui or inst:IsDescendantOf(gui) then return "That is the RGC UI itself" end
	if inst == lp or inst == Workspace.CurrentCamera or inst == Workspace.Terrain or inst == projectRoot then return "Protected object" end
	return nil
end
local function canEdit(inst)
	if inst == gui or inst:IsDescendantOf(gui) then return false, "That is the RGC UI itself" end
	if setting("fullAccess", true) then return true end
	if inst == projectRoot or inst:IsDescendantOf(projectRoot) then return true end
	return false, "Outside RGC_Project. Turn on 'Allow all access' in AI settings to edit other places."
end

-- ---------- value helpers ----------
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
local function nums(s)
	local t = {}
	for n in tostring(s):gmatch("[-+]?%d*%.?%d+") do table.insert(t, tonumber(n)) end
	return t
end
local function parseValue(cur, text, name)
	local s = trim(text)
	local t = typeof(cur)
	if t == "boolean" then
		local l = s:lower()
		if l == "true" or l == "1" or l == "yes" or l == "on" then return true end
		if l == "false" or l == "0" or l == "no" or l == "off" then return false end
		error("expected true/false")
	elseif t == "number" then
		local n = tonumber(s)
		if not n then error("expected a number") end
		return n
	elseif t == "string" then
		return text
	elseif t == "Vector3" then
		local n = nums(s); if #n < 3 then error("expected 'x, y, z'") end
		return Vector3.new(n[1], n[2], n[3])
	elseif t == "Vector2" then
		local n = nums(s); if #n < 2 then error("expected 'x, y'") end
		return Vector2.new(n[1], n[2])
	elseif t == "Color3" then
		if s:sub(1, 1) == "#" then return Color3.fromHex(s) end
		local n = nums(s); if #n < 3 then error("expected 'r, g, b' or '#RRGGBB'") end
		if n[1] > 1 or n[2] > 1 or n[3] > 1 then return Color3.fromRGB(clamp(n[1], 0, 255), clamp(n[2], 0, 255), clamp(n[3], 0, 255)) end
		return Color3.new(n[1], n[2], n[3])
	elseif t == "UDim2" then
		local n = nums(s); if #n < 4 then error("expected 'xScale, xOffset, yScale, yOffset'") end
		return UDim2.new(n[1], n[2], n[3], n[4])
	elseif t == "UDim" then
		local n = nums(s); if #n < 2 then error("expected 'scale, offset'") end
		return UDim.new(n[1], n[2])
	elseif t == "CFrame" then
		local n = nums(s)
		if #n == 3 then return CFrame.new(n[1], n[2], n[3]) end
		if #n == 6 then return CFrame.new(n[1], n[2], n[3]) * CFrame.Angles(math.rad(n[4]), math.rad(n[5]), math.rad(n[6])) end
		if #n == 12 then return CFrame.new(unpack(n)) end
		error("expected 3 (position), 6 (position + rotation degrees) or 12 numbers")
	elseif t == "EnumItem" then
		local et = cur.EnumType
		local item = et[s] or (s:find("%.") and et[s:match("[^%.]+$")])
		if not item then
			local n = tonumber(s)
			if n then for _, it in ipairs(et:GetEnumItems()) do if it.Value == n then item = it end end end
		end
		if not item then error("unknown enum value '" .. s .. "'") end
		return item
	elseif t == "BrickColor" then
		return BrickColor.new(s)
	elseif t == "NumberRange" then
		local n = nums(s); if #n < 1 then error("expected 'min, max'") end
		return NumberRange.new(n[1], n[2] or n[1])
	elseif t == "ColorSequence" then
		local c = parseValue(Color3.new(), s)
		return ColorSequence.new(c)
	elseif t == "NumberSequence" then
		local n = nums(s); if #n < 1 then error("expected a number") end
		return NumberSequence.new(n[1])
	elseif t == "Instance" or t == "nil" then
		if s:lower() == "nil" or s == "" then return nil end
		local inst, err = resolve(s)
		if not inst then error(err) end
		return inst
	end
	error("unsupported property type " .. t)
end

-- ---------- script source (native or stored in StringValue chunks) ----------
local CHUNK = 50000
local nativeState = nil
local function nativeSourceWorks()
	if nativeState ~= nil then return nativeState end
	nativeState = false
	pcall(function()
		local t = Instance.new("ModuleScript")
		t.Source = "return 1"
		local back = t.Source
		t:Destroy()
		if back == "return 1" then nativeState = true end
	end)
	return nativeState
end
local function shadowChunks(inst)
	local list = {}
	for _, c in ipairs(inst:GetChildren()) do
		if c:IsA("StringValue") and c.Name:sub(1, 11) == "RGC_Source_" then table.insert(list, c) end
	end
	table.sort(list, function(a, b) return a.Name < b.Name end)
	return list
end
local function readSource(inst)
	if not inst:IsA("LuaSourceContainer") then return nil, "Not a script" end
	local chunks = shadowChunks(inst)
	if #chunks > 0 then
		local t = {}
		for _, c in ipairs(chunks) do t[#t + 1] = c.Value end
		return table.concat(t)
	end
	local okk, src = pcall(function() return inst.Source end)
	if okk and type(src) == "string" then return src end
	if decompile then
		local o2, d = pcall(decompile, inst)
		if o2 and type(d) == "string" then return d end
	end
	return nil, "Source of this script is protected in this runtime (only scripts created by the agent are readable)"
end
local function utf8Cut(s, stop)
	while stop < #s do
		local b = s:byte(stop + 1)
		if b and b >= 0x80 and b <= 0xBF then stop += 1 else break end
	end
	return stop
end
local function writeSource(inst, code)
	if #code > 0 and nativeSourceWorks() then
		local okk = pcall(function() inst.Source = code end)
		if okk then
			for _, c in ipairs(shadowChunks(inst)) do c:Destroy() end
			return "native"
		end
	end
	local chunks = shadowChunks(inst)
	local pos, i = 1, 0
	repeat
		i += 1
		local stop = utf8Cut(code, math.min(#code, pos + CHUNK - 1))
		local piece = code:sub(pos, stop)
		pos = stop + 1
		local c = chunks[i]
		if not c then
			c = Instance.new("StringValue")
			c.Name = ("RGC_Source_%03d"):format(i)
			c.Parent = inst
		end
		c.Value = piece
	until pos > #code
	for k = i + 1, #chunks do chunks[k]:Destroy() end
	return "shadow"
end
local function newScriptInstance(className)
	local obj = Instance.new(className)
	pcall(function() obj.Disabled = true end)
	return obj
end
local function lineCount(s)
	if s == "" then return 0 end
	local _, n = s:gsub("\n", "")
	return n + 1
end

-- ---------- tools ----------
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

local function setProp(inst, name, text)
	if name == "Source" then
		if not inst:IsA("LuaSourceContainer") then error("Source only exists on scripts") end
		local old = readSource(inst)
		writeSource(inst, text)
		logUndo({kind = "source", inst = inst, old = old})
		return
	end
	if name == "Parent" then
		local par, err = resolve(text)
		if not par then error(err) end
		local oldP = inst.Parent
		inst.Parent = par
		logUndo({kind = "moved", inst = inst, parent = oldP})
		return
	end
	if name:sub(1, 1) == "@" then
		local an = name:sub(2)
		local old = inst:GetAttribute(an)
		local v
		local l = trim(text):lower()
		if l == "true" then v = true elseif l == "false" then v = false elseif tonumber(text) then v = tonumber(text) else v = text end
		inst:SetAttribute(an, v)
		logUndo({kind = "attr", inst = inst, key = an, old = old})
		return
	end
	local okRead, cur = pcall(function() return inst[name] end)
	if not okRead then error("'" .. name .. "' is not a property of " .. inst.ClassName) end
	local v = parseValue(cur, text, name)
	inst[name] = v
	logUndo({kind = "props", inst = inst, key = name, old = cur})
end

def("list_children", "List the direct children of an instance (name [Class] (child count)). Use to explore Workspace, ReplicatedStorage, ServerScriptService, StarterGui etc. Path examples: 'Workspace', 'ServerScriptService', 'Workspace/RGC_Project', 'game'.", {
	path = P("STRING", "Instance path, e.g. 'Workspace/RGC_Project'. 'game' lists services."),
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

def("get_tree", "Print an indented tree of an instance and its descendants (names + classes, ValueBase values). Good for a quick overview of a service or model.", {
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

def("find_instances", "Search descendants of an instance by name substring and/or class (IsA). Returns paths.", {
	root = P("STRING", "Where to search (default Workspace)"),
	name_contains = P("STRING", "Case-insensitive name substring"),
	class_name = P("STRING", "Class or base class, e.g. 'BasePart', 'Script', 'RemoteEvent'"),
	limit = P("INTEGER", "Max results (default 80)"),
}, nil, function(a)
	local root, err = resolve(a.root or "Workspace")
	if not root then return fail(err) end
	local nm = a.name_contains and tostring(a.name_contains):lower() or nil
	local limit = clamp(tonumber(a.limit) or 80, 1, 300)
	local out, scanned = {}, 0
	local okk, desc = pcall(root.GetDescendants, root)
	if not okk then return fail("Cannot scan") end
	for _, d in ipairs(desc) do
		scanned += 1
		if not isHidden(d) and not d:IsDescendantOf(gui) then
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
	if inst:IsA("LuaSourceContainer") then
		local src = readSource(inst)
		if src then res.source_lines = lineCount(src); res.source_chars = #src end
	end
	return res
end)

def("set_property", "[CLIENT-ONLY: exists only on this device, the server/other players can't see it and it vanishes on rejoin] Set one property. Value is always a string: numbers '5', booleans 'true', Vector3 '1, 2, 3', Color3 '255, 0, 0' or '#FF0000', UDim2 'xScale, xOffset, yScale, yOffset', CFrame '3 or 6 or 12 numbers', enums by name ('Neon'), instances by path. Use property 'Parent' (value = new parent path) to move, '@AttrName' for attributes, 'Source' for script code (prefer create_script/edit_script).", {
	path = P("STRING", "Instance path"),
	property = P("STRING", "Property name"),
	value = P("STRING", "New value as string"),
}, {"path", "property", "value"}, function(a)
	local inst, err = resolve(a.path)
	if not inst then return fail(err) end
	local allowed, why = canEdit(inst)
	if not allowed then return fail(why) end
	if a.property == "Parent" then
		local blocked = destroyBlocked(inst)
		if blocked then return fail(blocked) end
	end
	local okk, e = pcall(setProp, inst, tostring(a.property), tostring(a.value))
	if not okk then return fail(tostring(e)) end
	local nowv = "?"
	pcall(function() nowv = ser(inst[a.property]) end)
	return okr({path = pathOf(inst), property = a.property, now = nowv})
end)

def("create_instance", "[CLIENT-ONLY: exists only on this device, the server/other players can't see it and it vanishes on rejoin] Create ANY instance (Part, Model, Folder, Sound, PointLight, ScreenGui, TextLabel, RemoteEvent, Humanoid, ...). For scripts prefer create_script. BaseParts default to Anchored and are placed in front of the player unless Position is given.", {
	class_name = P("STRING", "ClassName, e.g. 'Part'"),
	parent = P("STRING", "Parent path (default 'project' = Workspace/RGC_Project)"),
	name = P("STRING", "Instance name"),
	properties = P("ARRAY", "Properties to set", {items = {type = "OBJECT", properties = {name = P("STRING", "Property"), value = P("STRING", "Value as string")}, required = {"name", "value"}}}),
}, {"class_name"}, function(a)
	local parent, err = resolve(a.parent or "project")
	if not parent then return fail(err) end
	if parent == gui or parent:IsDescendantOf(gui) then return fail("Cannot create inside the RGC UI") end
	if not setting("fullAccess", true) and not (parent == projectRoot or parent:IsDescendantOf(projectRoot)) then
		return fail("Outside RGC_Project. Turn on 'Allow all access' in AI settings.")
	end
	local className = tostring(a.class_name)
	local okNew, obj = pcall(Instance.new, className)
	if not okNew or not obj then return fail("Cannot create class '" .. className .. "'") end
	obj.Name = (a.name and tostring(a.name) ~= "") and tostring(a.name) or className
	local givenPos, errs = false, {}
	if obj:IsA("LuaSourceContainer") then pcall(function() obj.Disabled = true end) end
	if obj:IsA("BasePart") then obj.Anchored = true end
	if type(a.properties) == "table" then
		for _, p in ipairs(a.properties) do
			if type(p) == "table" and p.name then
				if p.name == "Position" or p.name == "CFrame" then givenPos = true end
				local saved = currentGroup
				currentGroup = nil
				local okP, e = pcall(setProp, obj, tostring(p.name), tostring(p.value))
				currentGroup = saved
				if not okP then table.insert(errs, tostring(p.name) .. ": " .. tostring(e)) end
			end
		end
	end
	if obj:IsA("BasePart") and not givenPos then
		local hrp = lp and lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
		obj.Position = hrp and (hrp.Position + hrp.CFrame.LookVector * 10 + Vector3.new(0, 2, 0)) or Vector3.new(0, 5, 0)
	end
	obj.Parent = parent
	logUndo({kind = "created", inst = obj})
	local res = okr({path = pathOf(obj), class = obj.ClassName, scope = "CLIENT-ONLY (server and other players cannot see it)"})
	if #errs > 0 then res.property_errors = errs end
	return res
end)

def("create_script", "[CLIENT-ONLY: exists only on this device, the server/other players can't see it and it vanishes on rejoin] Create (or overwrite/append to) a Script, LocalScript or ModuleScript with source code. Keep each call under ~200 lines: for bigger scripts call once with mode='replace' and then again with mode='append' for each next part. Always verify with read_script for big scripts.", {
	parent = P("STRING", "Parent path, e.g. 'ServerScriptService', 'StarterGui', 'StarterPlayer/StarterPlayerScripts', 'Workspace/RGC_Project'"),
	name = P("STRING", "Script name"),
	script_type = P("STRING", "Script, LocalScript or ModuleScript", {enum = {"Script", "LocalScript", "ModuleScript"}}),
	source = P("STRING", "Luau source (this chunk)"),
	mode = P("STRING", "replace (default) or append", {enum = {"replace", "append"}}),
}, {"parent", "name", "source"}, function(a)
	local parent, err = resolve(a.parent or "project")
	if not parent then return fail(err) end
	if parent == gui or parent:IsDescendantOf(gui) then return fail("Cannot create inside the RGC UI") end
	if not setting("fullAccess", true) and not (parent == projectRoot or parent:IsDescendantOf(projectRoot)) then
		return fail("Outside RGC_Project. Turn on 'Allow all access' in AI settings.")
	end
	local name = tostring(a.name)
	local code = tostring(a.source or "")
	local inst = parent:FindFirstChild(name)
	local created = false
	if inst and not inst:IsA("LuaSourceContainer") then return fail("'" .. name .. "' already exists and is not a script (" .. inst.ClassName .. ")") end
	if not inst then
		local stype = tostring(a.script_type or "Script")
		if stype ~= "Script" and stype ~= "LocalScript" and stype ~= "ModuleScript" then return fail("script_type must be Script, LocalScript or ModuleScript") end
		inst = newScriptInstance(stype)
		inst.Name = name
		inst.Parent = parent
		created = true
		logUndo({kind = "created", inst = inst})
	end
	local old = readSource(inst)
	local final = code
	if a.mode == "append" and old and old ~= "" then
		final = old .. (old:sub(-1) == "\n" and "" or "\n") .. code
	end
	if not created then logUndo({kind = "source", inst = inst, old = old}) end
	local okW, how = pcall(writeSource, inst, final)
	if not okW then return fail("Write failed: " .. tostring(how)) end
	local back = readSource(inst)
	return okr({path = pathOf(inst), class = inst.ClassName, scope = "CLIENT-ONLY (not a real server script)", created = created, storage = how, lines = lineCount(final), chars = #final, verified = (back == final)})
end)

def("read_script", "Read a script's source with line numbers. Returns up to ~12000 chars per call; use start_line/end_line to page (next_start_line is given when truncated). Only scripts created by the agent (or readable in this runtime) can be read.", {
	path = P("STRING", "Script path"),
	start_line = P("INTEGER", "First line (default 1)"),
	end_line = P("INTEGER", "Last line (default end)"),
}, {"path"}, function(a)
	local inst, err = resolve(a.path)
	if not inst then return fail(err) end
	local src, why = readSource(inst)
	if not src then return fail(why) end
	local lines = {}
	for l in (src .. "\n"):gmatch("(.-)\n") do lines[#lines + 1] = l end
	if src:sub(-1) == "\n" then lines[#lines] = nil end
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
	local res = okr({path = pathOf(inst), class = inst.ClassName, total_lines = total, total_chars = #src, from = s, to = last, code = table.concat(out, "\n")})
	if last < e then res.next_start_line = last + 1 end
	return res
end)

def("edit_script", "[CLIENT-ONLY: exists only on this device, the server/other players can't see it and it vanishes on rejoin] Replace an exact piece of text inside a script (find must match exactly, including whitespace). Fails if 'find' is missing or not unique unless replace_all=true. Preferred way to modify existing code.", {
	path = P("STRING", "Script path"),
	find = P("STRING", "Exact text to find"),
	replace = P("STRING", "Replacement text"),
	replace_all = P("BOOLEAN", "Replace every occurrence"),
}, {"path", "find", "replace"}, function(a)
	local inst, err = resolve(a.path)
	if not inst then return fail(err) end
	local src, why = readSource(inst)
	if not src then return fail(why) end
	local find, rep = tostring(a.find), tostring(a.replace)
	if find == "" then return fail("'find' is empty") end
	local count, pos = 0, 1
	while true do
		local s, e = src:find(find, pos, true)
		if not s then break end
		count += 1
		pos = e + 1
	end
	if count == 0 then return fail("Text to find was not found. Use read_script to copy the exact text.") end
	if count > 1 and not a.replace_all then return fail(count .. " matches; make 'find' longer/unique or set replace_all=true") end
	local out, p2 = {}, 1
	while true do
		local s, e = src:find(find, p2, true)
		if not s then break end
		out[#out + 1] = src:sub(p2, s - 1)
		out[#out + 1] = rep
		p2 = e + 1
		if not a.replace_all then break end
	end
	out[#out + 1] = src:sub(p2)
	local final = table.concat(out)
	logUndo({kind = "source", inst = inst, old = src})
	local how = writeSource(inst, final)
	return okr({path = pathOf(inst), replaced = a.replace_all and count or 1, lines = lineCount(final), storage = how})
end)

def("edit_script_lines", "[CLIENT-ONLY: exists only on this device, the server/other players can't see it and it vanishes on rejoin] Replace lines start_line..end_line (inclusive, 1-based) of a script with new_text. Use new_text='' to delete lines. To insert before line N use start_line=N, end_line=N-1.", {
	path = P("STRING", "Script path"),
	start_line = P("INTEGER", "First line to replace"),
	end_line = P("INTEGER", "Last line to replace"),
	new_text = P("STRING", "New text (may be multiple lines)"),
}, {"path", "start_line", "end_line", "new_text"}, function(a)
	local inst, err = resolve(a.path)
	if not inst then return fail(err) end
	local src, why = readSource(inst)
	if not src then return fail(why) end
	local lines = {}
	for l in (src .. "\n"):gmatch("(.-)\n") do lines[#lines + 1] = l end
	if src:sub(-1) == "\n" then lines[#lines] = nil end
	local s, e = tonumber(a.start_line), tonumber(a.end_line)
	if not s or not e or s < 1 or s > #lines + 1 or e < s - 1 or e > #lines then return fail("Invalid line range (script has " .. #lines .. " lines)") end
	local out = {}
	for i = 1, s - 1 do out[#out + 1] = lines[i] end
	local nt = tostring(a.new_text or "")
	if nt ~= "" then out[#out + 1] = nt end
	for i = e + 1, #lines do out[#out + 1] = lines[i] end
	local final = table.concat(out, "\n")
	logUndo({kind = "source", inst = inst, old = src})
	local how = writeSource(inst, final)
	return okr({path = pathOf(inst), lines = lineCount(final), storage = how})
end)

def("delete_instance", "[CLIENT-ONLY: exists only on this device, the server/other players can't see it and it vanishes on rejoin] Destroy an instance (and its descendants). Services and the RGC UI are protected.", {
	path = P("STRING", "Instance path"),
}, {"path"}, function(a)
	local inst, err = resolve(a.path)
	if not inst then return fail(err) end
	local blocked = destroyBlocked(inst)
	if blocked then return fail(blocked) end
	local allowed, why = canEdit(inst)
	if not allowed then return fail(why) end
	local parent, p = inst.Parent, pathOf(inst)
	local n = 1
	pcall(function() n += #inst:GetDescendants() end)
	local okC, clone = pcall(function() return inst:Clone() end)
	inst:Destroy()
	logUndo({kind = "deleted", clone = okC and clone or nil, parent = parent})
	return okr({deleted = p, instances_removed = n, undo_available = okC and clone ~= nil})
end)

def("move_instance", "[CLIENT-ONLY: exists only on this device, the server/other players can't see it and it vanishes on rejoin] Move an instance to a new parent (and optionally rename it).", {
	path = P("STRING", "Instance path"),
	new_parent = P("STRING", "New parent path"),
	new_name = P("STRING", "Optional new name"),
}, {"path", "new_parent"}, function(a)
	local inst, err = resolve(a.path)
	if not inst then return fail(err) end
	local blocked = destroyBlocked(inst)
	if blocked then return fail(blocked) end
	local allowed, why = canEdit(inst)
	if not allowed then return fail(why) end
	local np, e2 = resolve(a.new_parent)
	if not np then return fail(e2) end
	if np == inst or np:IsDescendantOf(inst) then return fail("Cannot move an instance into itself") end
	local oldP, oldN = inst.Parent, inst.Name
	inst.Parent = np
	logUndo({kind = "moved", inst = inst, parent = oldP})
	if a.new_name and tostring(a.new_name) ~= "" then
		inst.Name = tostring(a.new_name)
		logUndo({kind = "props", inst = inst, key = "Name", old = oldN})
	end
	return okr({path = pathOf(inst)})
end)

def("clone_instance", "[CLIENT-ONLY: exists only on this device, the server/other players can't see it and it vanishes on rejoin] Clone an instance (scripts keep their stored code).", {
	path = P("STRING", "Instance path"),
	new_parent = P("STRING", "Parent for the clone (default: same parent)"),
	new_name = P("STRING", "Name for the clone"),
}, {"path"}, function(a)
	local inst, err = resolve(a.path)
	if not inst then return fail(err) end
	local par = inst.Parent
	if a.new_parent then
		local np, e2 = resolve(a.new_parent)
		if not np then return fail(e2) end
		par = np
	end
	local okC, c = pcall(function() return inst:Clone() end)
	if not okC or not c then return fail("This instance cannot be cloned") end
	if a.new_name and tostring(a.new_name) ~= "" then c.Name = tostring(a.new_name) end
	c.Parent = par
	logUndo({kind = "created", inst = c})
	return okr({path = pathOf(c)})
end)

local function captureEnv(scriptInst, out)
	local function cap(prefix, ...)
		local parts = {}
		for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
		local line = prefix .. table.concat(parts, "\t")
		table.insert(out, line)
		table.insert(scriptOut, line)
		if #scriptOut > 200 then table.remove(scriptOut, 1) end
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
		script = scriptInst,
		print = function(...) cap("", ...) end,
		warn = function(...) cap("[warn] ", ...) end,
	}, {__index = base})
end

def("run_script", "Execute Luau locally in this game session and capture print/warn output and errors. Give either 'path' of a script you created, or inline 'source' for a quick test/one-off action (e.g. quickly spawn things, query game state). Scripts that loop forever keep running; use stop_scripts to cancel.", {
	path = P("STRING", "Path of a script to run"),
	source = P("STRING", "Inline Luau to run"),
	wait_seconds = P("NUMBER", "How long to wait for it to finish (default 3, max 20)"),
}, nil, function(a)
	if not setting("fullAccess", true) then return fail("Running code needs 'Allow all access' to be ON in AI settings") end
	local src, inst, label_ = nil, nil, "inline"
	if a.path and a.path ~= "" then
		local i2, err = resolve(a.path)
		if not i2 then return fail(err) end
		local s, why = readSource(i2)
		if not s then return fail(why) end
		src, inst, label_ = s, i2, i2.Name
	else
		src = tostring(a.source or "")
	end
	if src == "" then return fail("Nothing to run (give 'path' or 'source')") end
	if not loadstring then return fail("loadstring is not available in this executor") end
	local fn, cerr = loadstring(src, "=" .. label_)
	if not fn then return fail("Compile error: " .. tostring(cerr)) end
	local out = {}
	local env = captureEnv(inst, out)
	pcall(setfenv, fn, env)
	local done, result, errMsg = false, nil, nil
	local th = task.spawn(function()
		local okR, res = pcall(fn)
		done = true
		if okR then result = res else errMsg = tostring(res) end
	end)
	table.insert(spawned, th)
	local t0, waitFor = os.clock(), clamp(tonumber(a.wait_seconds) or 3, 0, 20)
	while not done and os.clock() - t0 < waitFor do task.wait(0.1) end
	local text = table.concat(out, "\n")
	if #text > 4000 then text = text:sub(1, 4000) .. "\n...(output cut)" end
	local res = {ok = errMsg == nil, finished = done, output = text}
	if errMsg then res.error = errMsg end
	if done and result ~= nil then res.returned = tostring(result):sub(1, 300) end
	if not done then res.note = "Still running in the background (use stop_scripts to cancel)" end
	return res
end)

def("stop_scripts", "Cancel all scripts started with run_script that are still running.", nil, nil, function()
	local n = 0
	for _, th in ipairs(spawned) do
		if pcall(task.cancel, th) then n += 1 end
	end
	spawned = {}
	return okr({cancelled = n})
end)

def("get_output", "Read recent game console output (prints, warnings, errors) to debug. Includes output from run_script.", {
	limit = P("INTEGER", "Number of recent lines (default 40, max 120)"),
	only_errors = P("BOOLEAN", "Only warnings and errors"),
}, nil, function(a)
	local limit = clamp(tonumber(a.limit) or 40, 1, 120)
	local lines = {}
	for _, l in ipairs(logBuf) do
		if not a.only_errors or l:sub(1, 5) == "error" or l:sub(1, 4) == "warn" then table.insert(lines, l) end
	end
	local out = {}
	for i = math.max(1, #lines - limit + 1), #lines do out[#out + 1] = lines[i]:sub(1, 300) end
	return okr({count = #out, lines = out})
end)

def("get_player", "Get the local player's position, facing direction and camera position (useful for placing things).", nil, nil, function()
	local res = okr({})
	local hrp = lp and lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
	if hrp then
		res.position = ser(hrp.Position)
		res.look_direction = ser(hrp.CFrame.LookVector)
	else
		res.note = "No character yet"
	end
	local cam = Workspace.CurrentCamera
	if cam then res.camera_position = ser(cam.CFrame.Position) end
	res.player = lp and lp.Name or "?"
	return res
end)

local CAT = {Model = {10, "Model"}, Audio = {3, "Audio"}, Music = {300, "Audio"}, Image = {13, "Decal"}, Decal = {13, "Decal"}, Mesh = {40, "MeshPart"}, Animation = {24, nil}, Video = {62, "Video"}}
def("search_assets", "Search the Roblox Creator Store for models, audio, images, meshes, animations. Returns asset ids you can pass to insert_asset (models) or use in properties (e.g. SoundId 'rbxassetid://ID').", {
	query = P("STRING", "Search keywords"),
	category = P("STRING", "Model (default), Audio, Image, Mesh, Animation, Video"),
	limit = P("INTEGER", "Max results (default 10, max 30)"),
}, {"query"}, function(a)
	local cat = CAT[tostring(a.category or "Model")] or CAT.Model
	local limit = clamp(tonumber(a.limit) or 10, 1, 30)
	local kw = tostring(a.query)
	local ids, info = {}, {}
	if db.set.storeKey and db.set.storeKey ~= "" and cat[2] then
		local res = postJSONWithHeaders("https://apis.roblox.com/toolbox-service/v2/assets:search", {["x-api-key"] = db.set.storeKey}, {searchCategoryType = cat[2], query = kw, maxPageSize = limit, searchView = "Full", sortCategory = "Relevance", pageNumber = 0})
		local entries = res and (res.creatorStoreAssets or res.data or res.assets or res.items or res.results)
		if type(entries) == "table" then
			for _, entry in ipairs(entries) do
				local x = type(entry) == "table" and (entry.asset or entry) or nil
				local id = x and (x.id or x.assetId)
				if id then
					table.insert(ids, id)
					info[id] = {name = x.name or x.title, creator = type(entry.creator) == "table" and entry.creator.name or nil}
				end
			end
		end
	end
	if #ids == 0 then
		local res = getJSON(("%s%d?limit=%d&pageNumber=0&keyword=%s"):format(MARKET, cat[1], limit, HttpService:UrlEncode(kw)))
		if not res or type(res.data) ~= "table" then return fail("Search failed (HTTP blocked or the Creator Store API key lacks access)") end
		for _, v in ipairs(res.data) do table.insert(ids, v.id) end
		if #ids > 0 then
			local det = getJSON(DETAILS .. table.concat(ids, ","))
			if det and type(det.data) == "table" then
				for _, d in ipairs(det.data) do
					local x = d.asset or d
					if x and x.id then info[x.id] = {name = x.name, creator = d.creator and d.creator.name} end
				end
			end
		end
	end
	local out = {}
	for i, id in ipairs(ids) do
		if i > limit then break end
		local it = info[id] or {}
		out[#out + 1] = ("%s | %s%s"):format(tostring(id), tostring(it.name or "?"), it.creator and (" | by " .. it.creator) or "")
	end
	return okr({count = #out, results = out})
end)

def("insert_asset", "Insert a Creator Store asset by id on the SERVER using Studio Lite's own loader remotes (real, visible to everyone). Falls back to a client-only insert if the remotes fail. Use search_assets first to find ids.", {
	asset_id = P("INTEGER", "Asset id"),
}, {"asset_id"}, function(a)
	local id = tonumber(a.asset_id)
	if not id then return fail("asset_id must be a number") end
	if not setting("fullAccess", true) then return fail("Needs 'Allow all access' ON") end
	local okS, found, ret = serverInsertAsset(id)
	if okS then
		changeCount += 1
		local items = {}
		for _, f in ipairs(found) do items[#items + 1] = f.where .. "/" .. f.name end
		return okr({server_side = true, inserted = items, note = #items == 0 and "Remote accepted the request but no new object was detected yet; check get_tree on Workspace in a moment." or "Inserted through Studio Lite's server remotes.", returned = ret ~= nil and tostring(ret):sub(1, 100) or nil})
	end
	return fail("Server insert failed: " .. tostring(found))
end)

def("list_remotes", "List RemoteEvents/RemoteFunctions under an instance (default ReplicatedStorage). Studio Lite's own remotes are under ReplicatedStorage/StudioLiteFolder.", {
	root = P("STRING", "Where to look (default ReplicatedStorage)"),
	limit = P("INTEGER", "Max results (default 120)"),
}, nil, function(a)
	local root, err = resolve(a.root or "ReplicatedStorage")
	if not root then return fail(err) end
	local list = scanRemotes(root, clamp(tonumber(a.limit) or 120, 1, 300))
	local out = {}
	for _, r in ipairs(list) do out[#out + 1] = r.path .. " [" .. r.class .. "]" end
	return okr({count = #out, remotes = out})
end)

def("get_spy_log", "Read the remote calls the USER recorded with the Bridge tab 'Spy' while using Studio Lite's own buttons (create part, new script, set property...). This shows the exact remote names and argument formats, so you can replay/adapt them with call_remote. If empty, ask the user to turn Spy ON in the Bridge tab, do the action in Studio Lite, then tell you.", {
	limit = P("INTEGER", "Number of recent calls (default 30)"),
}, nil, function(a)
	local n = clamp(tonumber(a.limit) or 30, 1, 100)
	return okr({spy_installed = spy.hooked, spy_on = spy.on, total = #spy.log, calls = spy.text(n)})
end)

def("call_remote", "Call a RemoteEvent (fire) or RemoteFunction (invoke): the way to make REAL server-side changes. args_json is a JSON array of arguments. Special strings: 'inst:Workspace/Part' (instance), 'v3:1,2,3', 'v2:1,2', 'c3:255,0,0' (Color3), 'cf:x,y,z' or 12 numbers (CFrame), 'nil:' (nil). Learn the exact format from get_spy_log before guessing; never guess destructive calls.", {
	path = P("STRING", "Remote path, e.g. ReplicatedStorage/StudioLiteFolder/SomeRemote"),
	method = P("STRING", "fire or invoke (default: by remote class)", {enum = {"fire", "invoke"}}),
	args_json = P("STRING", "JSON array of arguments, e.g. [\"abc\", 5, \"v3:0,5,0\"]"),
}, {"path"}, function(a)
	if not setting("fullAccess", true) then return fail("Needs 'Allow all access' ON") end
	local r, err = resolve(a.path)
	if not r then return fail(err) end
	if not (r:IsA("RemoteEvent") or r:IsA("RemoteFunction") or r:IsA("UnreliableRemoteEvent")) then return fail(pathOf(r) .. " is not a remote (" .. r.ClassName .. ")") end
	local args, n = {}, 0
	if a.args_json and trim(a.args_json) ~= "" then
		local okJ, decoded = pcall(HttpService.JSONDecode, HttpService, a.args_json)
		if not okJ or type(decoded) ~= "table" or (decoded[1] == nil and next(decoded) ~= nil) then return fail("args_json must be a JSON array like [\"a\", 1]") end
		n = #decoded
		for i = 1, n do args[i] = fromTagged(decoded[i]) end
	end
	local method = a.method or (r:IsA("RemoteFunction") and "invoke" or "fire")
	if method == "invoke" and not r:IsA("RemoteFunction") then return fail("This is a RemoteEvent: use method 'fire'") end
	if method == "fire" and r:IsA("RemoteFunction") then return fail("This is a RemoteFunction: use method 'invoke'") end
	local res = callRemote(r, method, args, n)
	if not res[1] then return fail("Remote error: " .. tostring(res[2])) end
	local out = {}
	for i = 2, res.n do out[#out + 1] = toTagged(res[i], 0) end
	changeCount += 1
	return okr({called = pathOf(r), method = method, returned = out, note = "Server calls cannot be undone from the Undo button."})
end)

def("describe_map", "Summarize the map in Workspace (or a sub-tree): part counts, size/bounds, biggest models, lighting, spawns, sounds, lights, scripts, how dense it is. Use it before giving advice about what to add or improve.", {
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
		if not isHidden(d) and not d:IsDescendantOf(gui) then
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

def("save_notes", "Save a short plan / progress note (max ~3000 chars). It is shown to you at the start of every step, so use it to keep track of long multi-step tasks. Replaces the previous note.", {
	text = P("STRING", "Plan / progress"),
}, {"text"}, function(a)
	notes = tostring(a.text or ""):sub(1, 3000)
	return okr({saved = #notes})
end)

resolveForTag = resolve

local function toolDecls()
	local d = {}
	for _, n in ipairs(ORDER) do table.insert(d, TOOLS[n].decl) end
	return d
end

-- ---------- undo ----------
local function undoLast()
	if busy then showToast("Stop the agent first") return end
	local g
	while #undoGroups > 0 do
		g = table.remove(undoGroups)
		if #g > 0 then break end
		g = nil
	end
	if not g then showToast("Nothing to undo") return end
	local n = 0
	for i = #g, 1, -1 do
		local e = g[i]
		local okk = pcall(function()
			if e.kind == "created" then
				if e.inst then e.inst:Destroy() end
			elseif e.kind == "deleted" then
				if e.clone and e.parent then e.clone.Parent = e.parent end
			elseif e.kind == "props" then
				e.inst[e.key] = e.old
			elseif e.kind == "attr" then
				e.inst:SetAttribute(e.key, e.old)
			elseif e.kind == "moved" then
				e.inst.Parent = e.parent
			elseif e.kind == "source" then
				writeSource(e.inst, e.old or "")
			end
		end)
		if okk then n += 1 end
	end
	showToast("Undid " .. n .. " change(s)")
end

-- ---------- system prompt ----------
local SYSTEM_PROMPT = [==[You are RGC Agent, an autonomous Roblox building, scripting and map-design assistant inside the Studio Lite game (RGC Glass Creator Studio). You act through TOOLS and you never just describe what you would do.

THE MOST IMPORTANT FACT: CLIENT vs SERVER
- You run on the player's device (client, via an executor). Anything created by create_instance, create_script, set_property, clone/move/delete is CLIENT-ONLY: the server and other players cannot see it, server scripts cannot find it, and it disappears when the player rejoins. It is only good for a quick local preview or for testing.
- Real, working changes must reach the SERVER. There are three ways, in this order of preference:
  1. A server bridge: insert_asset already inserts models on the server through Studio Lite's own remotes. For other actions use call_remote, but ONLY with a format you have seen: read get_spy_log (the user records Studio Lite's own remote calls in the Bridge tab) or list_remotes. Never guess unknown remote arguments and never call remotes you do not understand.
  2. Write the complete script in your reply, in a ```lua code block (one block per script). Say exactly where it goes (for example: Script in ServerScriptService, LocalScript in StarterPlayerScripts, ModuleScript in ReplicatedStorage). The user copies it with the Copy button and pastes it into Studio Lite's script editor, where it runs on the server for real. Prefer self-contained BUILDER scripts that create the parts, UI, lighting, sounds and logic by code, so one paste builds everything.
  3. If the user only wants a quick look, you may make a client-only preview, and you must say it is local only.
- NEVER say that something exists for the server, or that a script is installed, unless a tool result confirmed server_side=true or a successful call_remote. Be honest about what is client-only.
- Reading works: you can inspect Workspace, ReplicatedStorage, StarterGui, Lighting and everything the client can replicate. ServerScriptService and ServerStorage contents are not visible to the client.

HOW YOU WORK
- Explore first (describe_map, get_tree, list_children, find_instances, read_script), then act, then verify. If a tool returns an error, read it and fix the cause. Never invent paths.
- You may chain as many tool calls as you need. Every tool call needs VALID JSON arguments. Keep going until the task is done, then give a short summary: what you did, what is local vs real, and what the user must paste or do.
- Paths look like Workspace/Folder/Part or ReplicatedStorage/Remotes. The first segment is a service. 'game' lists all services.
- You can find Creator Store assets with search_assets and put them in the map with insert_asset (server side).

MAP ADVISOR
- When the user asks what to add or improve, or asks if their map looks good: call describe_map (and get_tree on interesting parts), look at size, density, lighting, sky/atmosphere, sounds, spawns, then give concrete, specific recommendations grouped as: Look and feel (lighting, atmosphere, colors, props, decals), Gameplay (objectives, checkpoints, hazards, collectibles, NPCs, shops), Sound (ambience, music, effects), Performance. Be honest if it looks empty or messy. Offer to build the best ideas: with search_assets plus insert_asset for ready-made models, or with a builder script they can paste.

WRITING LARGE CODE
- Write complete, working, modern Luau (task.wait, no wait()). No placeholders like "-- rest of code". For very big systems split into several scripts/modules, each in its own code block.
- If you use create_script for a local preview, keep each call under ~200 lines and use mode=append for the next parts.

STYLE
- Be concise. Reply in the language the user writes (they may use Tagalog or Taglish).
- If a request is ambiguous, decide sensibly and proceed; ask only when truly blocked.
- For long tasks keep a short plan with save_notes (shown to you at the start of every step).]==]

local function systemText()
	local s = SYSTEM_PROMPT .. "\n\nPROJECT FOLDER: " .. pathOf(projectRoot)
	if notes ~= "" then s ..= "\n\nYOUR SAVED NOTES / PLAN:\n" .. notes end
	if not setting("fullAccess", true) then s ..= "\n\nNOTE: 'Allow all access' is OFF: you may only modify things inside " .. pathOf(projectRoot) .. " and run_script is disabled." end
	return s
end

-- ---------- context size control ----------
local CTX_LIMIT = 260000
local MAX_STEPS = 200
local OR_URL = "https://openrouter.ai/api/v1/chat/completions"
local OR_DEFAULT_MODEL = "nvidia/nemotron-3.5-super-vl:free"
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

-- ---------- OpenRouter request ----------
local function modelName()
	local m = db.set.orModel
	return (type(m) == "string" and m ~= "") and m or OR_DEFAULT_MODEL
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
	if key == "" then return nil, "No OpenRouter API key. Open Settings (gear) and paste one." end
	local msgs = {{role = "system", content = systemText()}}
	for _, m in ipairs(history) do table.insert(msgs, m) end
	local payload = {model = modelName(), messages = msgs, tools = toolList(), tool_choice = "auto", max_tokens = maxTokens, temperature = 0.4}
	local okE, body = pcall(HttpService.JSONEncode, HttpService, payload)
	if not okE then return nil, "Could not encode request: " .. tostring(body) end
	local lastErr = "Request failed"
	for attempt = 1, 6 do
		if stopFlag then return nil, "Stopped" end
		local res = doRequest({
			Url = OR_URL, Method = "POST",
			Headers = {["Content-Type"] = "application/json", ["Authorization"] = "Bearer " .. key, ["HTTP-Referer"] = "https://github.com/devnamegelo", ["X-Title"] = "RGC Glass Creator Studio"},
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
				task.wait(2)
			elseif data.error or status >= 400 then
				local e = data.error
				local msg = type(e) == "table" and tostring(e.message or e.code or "API error") or tostring(e or ("HTTP " .. status))
				local code = (type(e) == "table" and tonumber(e.code)) or status
				if type(e) == "table" and type(e.metadata) == "table" and e.metadata.raw then
					msg = msg .. " (" .. tostring(e.metadata.raw):sub(1, 160) .. ")"
				end
				lastErr = msg
				local low = msg:lower()
				if code == 429 then
					if low:find("per%-day") or low:find("per day") or low:find("daily") then
						return nil, "OpenRouter free daily limit reached (" .. msg .. "). Free models allow about 50 requests per day (1000 after buying $10 credits). Try again later."
					end
					local w = math.min(6 * attempt, 40)
					setStatus("Rate limited, waiting " .. w .. "s", C.warn)
					task.wait(w)
				elseif code >= 500 or code == 408 then
					setStatus("Provider busy, retrying (" .. attempt .. ")", C.warn)
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

-- ---------- chat UI ----------
local header = new("Frame", {Size = UDim2.new(1, -16, 0, 30), Position = UDim2.fromOffset(8, 0), BackgroundTransparency = 1}, pAI)
local btnRow = new("Frame", {Size = UDim2.new(0, 238, 1, 0), Position = UDim2.new(1, -238, 0, 0), BackgroundTransparency = 1}, header)
new("UIListLayout", {FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Right, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder}, btnRow)
local stopBtn = btn(btnRow, "■ Stop", UDim2.fromOffset(58, 28), nil, C.bad, 11)
stopBtn.LayoutOrder = 1
stopBtn.Visible = false
local undoBtn = btn(btnRow, "↶ Undo", UDim2.fromOffset(60, 28), nil, C.card, 11)
undoBtn.LayoutOrder = 2
local clearBtn = btn(btnRow, "Clear", UDim2.fromOffset(52, 28), nil, C.card, 11)
clearBtn.LayoutOrder = 3
local setBtn = btn(btnRow, "⚙", UDim2.fromOffset(34, 28), nil, C.card, 14)
setBtn.LayoutOrder = 4
local statusLbl = label(header, "● Ready", UDim2.new(1, -246, 1, 0), nil, C.good, 11, Enum.Font.GothamMedium)
statusLbl.TextWrapped = false
statusLbl.TextTruncate = Enum.TextTruncate.AtEnd
setStatus = function(text, color)
	statusLbl.Text = "● " .. text
	statusLbl.TextColor3 = color or C.good
end

local chatScroll = vscroll(pAI, UDim2.new(1, -16, 1, -112), UDim2.fromOffset(8, 34))
new("UIListLayout", {Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder}, chatScroll)
local chips = hscroll(pAI, UDim2.new(1, -16, 0, 26), UDim2.new(0, 8, 1, -74))
local inputBox = box(pAI, "Tell the agent what to build or fix...", UDim2.new(1, -84, 0, 38), UDim2.new(0, 8, 1, -42), true)
local sendBtn = btn(pAI, "Send ➤", UDim2.fromOffset(68, 38), UDim2.new(1, -76, 1, -42), C.accent, 13)

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
	label(head, "lua · " .. nLines .. " lines", UDim2.new(1, -140, 1, 0), nil, C.sub, 10, Enum.Font.Code)
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

local function addMessage(role, text)
	msgOrder += 1
	local isUser = role == "user"
	local f = round(new("Frame", {
		Size = UDim2.new(1, -6, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BorderSizePixel = 0,
		BackgroundColor3 = isUser and Color3.fromRGB(50, 80, 140) or C.bar, LayoutOrder = msgOrder,
	}, chatScroll), 12)
	f.BackgroundTransparency = isUser and 0.2 or 0.35
	pad(f, 7)
	listLayout(f, 4)
	if isUser then
		f.Size = UDim2.new(0.86, 0, 0, 0)
		f.Position = UDim2.new(0.14, -6, 0, 0)
	end
	if role == "sys" then
		f.BackgroundColor3 = Color3.fromRGB(90, 40, 50)
	end
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
local ICON = {list_children = "📂", get_tree = "🌳", find_instances = "🔎", get_properties = "📋", set_property = "✏️", create_instance = "🧱", create_script = "📜", read_script = "📖", edit_script = "🛠", edit_script_lines = "🛠", delete_instance = "🗑", move_instance = "↦", clone_instance = "⧉", run_script = "▶", stop_scripts = "■", get_output = "🖥", get_player = "🧍", search_assets = "🛍", insert_asset = "📥", save_notes = "📝"}
local function argSummary(args)
	for _, k in ipairs({"path", "parent", "root", "query", "asset_id", "class_name"}) do
		if args[k] ~= nil then
			local s = tostring(args[k])
			if k == "parent" and args.name then s = s .. "/" .. tostring(args.name) end
			if k == "class_name" and args.name then s = s .. " '" .. tostring(args.name) .. "'" end
			return s
		end
	end
	return ""
end
local function addToolCard(name, args)
	msgOrder += 1
	local card = round(new("Frame", {Size = UDim2.new(1, -6, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = C.card, BorderSizePixel = 0, LayoutOrder = msgOrder}, chatScroll), 9)
	card.BackgroundTransparency = 0.45
	listLayout(card, 0)
	local row = new("TextButton", {
		Size = UDim2.new(1, 0, 0, 26), BackgroundTransparency = 1, Text = "⏳ " .. (ICON[name] or "⚙") .. " " .. name .. "  " .. argSummary(args),
		TextColor3 = C.sub, Font = Enum.Font.GothamMedium, TextSize = 11, TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd, AutoButtonColor = false, LayoutOrder = 1,
	}, card)
	new("UIPadding", {PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8)}, row)
	local detail = label(card, "", UDim2.new(1, 0, 0, 0), nil, C.sub, 10, Enum.Font.Code)
	detail.AutomaticSize = Enum.AutomaticSize.Y
	detail.TextYAlignment = Enum.TextYAlignment.Top
	detail.Visible = false
	detail.LayoutOrder = 2
	new("UIPadding", {PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8), PaddingBottom = UDim.new(0, 6)}, detail)
	local argText = toJson(args)
	detail.Text = "args: " .. argText
	row.MouseButton1Click:Connect(function() detail.Visible = not detail.Visible end)
	trimChat()
	scrollBottom()
	return function(res)
		local good = res and res.ok ~= false
		row.Text = (good and "✓ " or "✗ ") .. (ICON[name] or "⚙") .. " " .. name .. "  " .. argSummary(args)
		row.TextColor3 = good and C.good or C.bad
		local shown = toJson(res)
		if #shown > 1200 then shown = shown:sub(1, 1200) .. "..." end
		detail.Text = "args: " .. argText .. "\nresult: " .. shown
		if not good and res and res.error then
			detail.Visible = true
		end
	end
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
		return {ok = true, truncated = true, partial = js:sub(1, 20000), note = "Result too large. Narrow your request (smaller depth/limit/line range)."}
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
	sendBtn.Text = v and "Send ↪" or "Send ➤"
	if not v then setStatus("Ready", C.good) end
end

local function agentLoop()
	local step, bad = 0, 0
	local maxTokens = 20000
	while not stopFlag do
		step += 1
		if step > MAX_STEPS then
			addMessage("sys", "Reached the step limit (" .. MAX_STEPS .. "). Send \"continue\" to keep going.")
			return
		end
		compact()
		setStatus("Thinking... (step " .. step .. ")", C.accent)
		local data, err = llmRequest(maxTokens)
		if not data then
			if stopFlag then return end
			local low = tostring(err):lower()
			if maxTokens > 6000 and (low:find("max_tokens") or low:find("max tokens") or low:find("completion tokens")) then
				maxTokens = 6000
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
			return
		end
		local choice = data.choices and data.choices[1]
		local msg = choice and choice.message
		if type(msg) ~= "table" then
			bad += 1
			if bad > 2 then addMessage("sys", "The model returned nothing. Try again or rephrase.") return end
			task.wait(2)
			continue
		end
		local finish = choice.finish_reason
		local text = type(msg.content) == "string" and trim(msg.content) or ""
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
		if text ~= "" then addMessage("model", text) end
		local stored = {role = "assistant"}
		if text ~= "" then stored.content = text end
		if #calls > 0 then
			stored.tool_calls = {}
			for _, c in ipairs(calls) do
				table.insert(stored.tool_calls, {id = c.id, type = "function", ["function"] = {name = c.name, arguments = c.argStr}})
			end
			if msg.reasoning_details then stored.reasoning_details = msg.reasoning_details end
		end
		if #calls == 0 then
			if text == "" then
				bad += 1
				if bad > 2 then addMessage("sys", "The model returned an empty reply" .. (finish and (" (" .. tostring(finish) .. ")") or "") .. ". Try again.") return end
				pushUserText("Your last reply was empty. Continue the task: call a tool, or give the final answer.")
			else
				bad = 0
				table.insert(history, stored)
				if finish == "length" then
					pushUserText("Continue exactly where you stopped.")
				elseif #pendingUser > 0 then
					pushUserText(table.remove(pendingUser, 1))
				else
					return
				end
			end
		else
			bad = 0
			table.insert(history, stored)
			for _, c in ipairs(calls) do
				local okA, args = pcall(HttpService.JSONDecode, HttpService, c.argStr)
				local result
				local done = addToolCard(c.name, okA and type(args) == "table" and args or {})
				if stopFlag then
					result = fail("Stopped by the user")
				elseif not okA or type(args) ~= "table" then
					result = fail("Invalid JSON in tool arguments (the output was probably cut off). Retry with a smaller piece: max ~150 lines per create_script call, then mode=append.")
				else
					setStatus("Step " .. step .. " · " .. tostring(c.name), C.accent)
					result = execTool(c.name, args)
				end
				done(result)
				local okJ, js = pcall(HttpService.JSONEncode, HttpService, result)
				table.insert(history, {role = "tool", tool_call_id = c.id, content = okJ and js or '{"ok":false,"error":"result not encodable"}'})
			end
			while #pendingUser > 0 do
				pushUserText("USER (sent while you were working): " .. table.remove(pendingUser, 1))
			end
			task.wait(0.15)
		end
	end
end

local function runAgent()
	setBusy(true)
	stopFlag = false
	local okk, e = pcall(agentLoop)
	if not okk then addMessage("sys", "Agent crashed: " .. tostring(e)) end
	setBusy(false)
	if stopFlag then
		addMessage("sys", "Stopped.")
		stopFlag = false
	end
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
sLabel("OpenRouter API key (saved only on this device)")
local keyBox = box(setScroll, getKey() ~= "" and "Saved - type to replace" or "sk-or-v1-...", UDim2.new(1, -6, 0, 34))
keyBox.LayoutOrder = sNext()
keyBox.ZIndex = 10
sLabel("Model")
local modelBox = box(setScroll, OR_DEFAULT_MODEL, UDim2.new(1, -6, 0, 34))
modelBox.LayoutOrder = sNext()
modelBox.ZIndex = 10
modelBox.Text = (type(db.set.orModel) == "string" and db.set.orModel ~= "") and db.set.orModel or OR_DEFAULT_MODEL
do
	local b = btn(setScroll, "", UDim2.new(1, -6, 0, 36), nil, C.card, 12)
	b.LayoutOrder = sNext()
	b.ZIndex = 10
	local function paint()
		local on = setting("fullAccess", true)
		b.Text = "Allow all access (read & write):  " .. (on and "ON" or "OFF")
		b.BackgroundColor3 = on and C.accent or C.card
	end
	b.MouseButton1Click:Connect(function()
		db.set.fullAccess = not setting("fullAccess", true)
		saveDB()
		paint()
	end)
	paint()
end
local saveKeyBtn = btn(setScroll, "Save", UDim2.new(1, -6, 0, 38), nil, C.good, 14)
saveKeyBtn.LayoutOrder = sNext()
saveKeyBtn.ZIndex = 10
saveKeyBtn.MouseButton1Click:Connect(function()
	local k = trim(keyBox.Text)
	if k ~= "" then
		db.set.orKey = k
		keyBox.Text = ""
		keyBox.PlaceholderText = "Saved - type to replace"
	end
	local m = trim(modelBox.Text)
	db.set.orModel = (m ~= "") and m or OR_DEFAULT_MODEL
	modelBox.Text = db.set.orModel
	saveDB()
	settingsPanel.Visible = false
	showToast("AI settings saved")
end)
setBtn.MouseButton1Click:Connect(function() settingsPanel.Visible = not settingsPanel.Visible end)

-- ---------- input wiring ----------
local function submit()
	local txt = trim(inputBox.Text)
	if txt == "" then return end
	if getKey() == "" then
		settingsPanel.Visible = true
		showToast("Add your OpenRouter API key first")
		return
	end
	inputBox.Text = ""
	addMessage("user", txt)
	if busy then
		table.insert(pendingUser, txt)
		showToast("Sent to the agent")
		return
	end
	pushUserText(txt)
	currentGroup = {}
	table.insert(undoGroups, currentGroup)
	while #undoGroups > 30 do table.remove(undoGroups, 1) end
	task.spawn(runAgent)
end
sendBtn.MouseButton1Click:Connect(submit)
stopBtn.MouseButton1Click:Connect(function()
	stopFlag = true
	setStatus("Stopping...", C.warn)
end)
undoBtn.MouseButton1Click:Connect(undoLast)
clearBtn.MouseButton1Click:Connect(function()
	if busy then showToast("Stop the agent first") return end
	history = {}
	pendingUser = {}
	undoGroups, currentGroup = {}, nil
	clearGui(chatScroll)
	showToast("Chat cleared")
end)

for i, c in ipairs({
	{"🗺 Review my map", "Look at my current map (describe_map and get_tree), tell me honestly how it looks, and recommend what to add or improve."},
	{"🧱 Builder script", "Write me a builder script that creates a small obby with 10 platforms, a checkpoint and a kill brick. I'll paste it into Studio Lite."},
	{"📜 Write a script", "Write a Script and a ModuleScript that give players a Coins leaderstat and a coin pickup system."},
	{"🛍 Add models", "Search the Creator Store for a medieval house and insert the best match on the server."},
	{"🔗 Learn the game", "List the remotes in ReplicatedStorage/StudioLiteFolder and tell me what each one probably does."},
}) do
	local chip = btn(chips, c[1], UDim2.fromOffset(#c[1] * 6 + 28, 24), nil, C.card, 11)
	chip.LayoutOrder = i
	chip.MouseButton1Click:Connect(function() inputBox.Text = c[2] inputBox:CaptureFocus() end)
end

aiPrefill = function(text)
	inputBox.Text = text
end
addMessage("model", "Hi! I'm the RGC Agent. I can explore your map, review it and recommend what to add, search and insert Creator Store models on the server, and write complete scripts for you to paste into Studio Lite (real server scripts). Things I create directly are client-only previews, and I'll always tell you which is which. Add your OpenRouter key in ⚙ Settings to start.")

end -- buildAIPage
buildAIPage()

-- ===== BRIDGE PAGE (remote scanner + spy) =====
local function buildBridgePage()
	local pB = newPage("Bridge")
	local info = label(pB, "Make REAL (server) changes: turn Spy ON, then use Studio Lite's own buttons (insert part, new script, set property...). The calls it sends are recorded here. Send them to the AI so it can repeat them.", UDim2.new(1, -16, 0, 44), UDim2.fromOffset(8, 0), C.sub, 11)
	local row = new("Frame", {Size = UDim2.new(1, -16, 0, 30), Position = UDim2.fromOffset(8, 48), BackgroundTransparency = 1}, pB)
	local function rb(i, text, color)
		return btn(row, text, UDim2.new(0.2, -4, 1, 0), UDim2.new((i - 1) * 0.2, 0, 0, 0), color or C.card, 11)
	end
	local spyBtn = rb(1, "Spy: OFF")
	local scanBtn = rb(2, "Scan remotes")
	local copyBtn = rb(3, "Copy")
	local sendBtn2 = rb(4, "Send to AI", C.accent)
	local clearBtn2 = rb(5, "Clear")
	local list = vscroll(pB, UDim2.new(1, -16, 1, -86), UDim2.fromOffset(8, 82))
	new("UIListLayout", {Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder}, list)
	local mode, order = "log", 0
	local scanLines = {}

	local function addRow(text, color, copyText)
		order += 1
		local r = round(new("TextButton", {
			Size = UDim2.new(1, -6, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = C.bar, BackgroundTransparency = 0.4,
			Text = #text > 700 and (text:sub(1, 700) .. "...") or text, TextColor3 = color or C.text, Font = Enum.Font.Code, TextSize = 10,
			TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, TextWrapped = true,
			AutoButtonColor = false, LayoutOrder = order, BorderSizePixel = 0,
		}, list), 8)
		new("UIPadding", {PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 4), PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6)}, r)
		r.MouseButton1Click:Connect(function() copyOut(copyText or text, "line") end)
	end
	local function render()
		clearGui(list)
		order = 0
		if mode == "scan" then
			if #scanLines == 0 then addRow("No remotes found.", C.sub) end
			for _, l in ipairs(scanLines) do addRow(l, l:find("StudioLiteFolder") and C.good or C.text) end
			return
		end
		if #spy.log == 0 then
			addRow(spy.on and "Spy is ON. Now do something in Studio Lite (insert a part, create a script...). Calls will appear here." or "Nothing recorded yet. Turn Spy ON first.", C.sub)
			return
		end
		local from = math.max(1, #spy.log - 80 + 1)
		for i = from, #spy.log do addRow(spy.fmt(spy.log[i]), C.text) end
		task.defer(function() list.CanvasPosition = Vector2.new(0, 1e7) end)
	end
	spy.onLog = function() if mode == "log" then render() end end

	spyBtn.MouseButton1Click:Connect(function()
		if not spy.on then
			local ok, err = spy.install()
			if not ok then showToast(tostring(err):sub(1, 80)) return end
			spy.on = true
			mode = "log"
		else
			spy.on = false
		end
		spyBtn.Text = spy.on and "Spy: ON" or "Spy: OFF"
		spyBtn.BackgroundColor3 = spy.on and C.good or C.card
		render()
	end)
	scanBtn.MouseButton1Click:Connect(function()
		mode = "scan"
		scanLines = {}
		local found = scanRemotes(ReplicatedStorage, 250)
		for _, r in ipairs(found) do scanLines[#scanLines + 1] = r.path .. "  [" .. r.class .. "]" end
		render()
		showToast(#found .. " remote(s) found")
	end)
	copyBtn.MouseButton1Click:Connect(function()
		if mode == "scan" then
			copyOut(table.concat(scanLines, "\n"), "remote list")
		else
			copyOut(spy.text(100), "recorded calls")
		end
	end)
	sendBtn2.MouseButton1Click:Connect(function()
		local text
		if mode == "scan" then
			text = "These are the remotes in this game. Tell me what each probably does and which ones can create parts/scripts/instances on the server:\n" .. table.concat(scanLines, "\n")
		else
			if #spy.log == 0 then showToast("Nothing recorded yet") return end
			text = "I recorded these remote calls while using Studio Lite's own buttons (I did: <describe what you did>). Learn the format, then repeat/adapt it with call_remote, or tell me what you need:\n" .. spy.text(25)
		end
		if #text > 7000 then text = text:sub(1, 7000) .. "\n...(cut)" end
		if aiPrefill then aiPrefill(text) end
		if gotoTab then gotoTab("AI") end
		showToast("Added to the AI input. Edit it and press Send")
	end)
	clearBtn2.MouseButton1Click:Connect(function()
		spy.log = {}
		scanLines = {}
		render()
	end)
	render()
end
buildBridgePage()

-- ===== Tabs =====
local TABS = {
	{"Store", "🛍 Store"},
	{"Saved", "★ Saved"},
	{"AI", "✦ AI Agent"},
	{"Bridge", "🔗 Bridge"},
	{"Snippets", "{ } Snippets"},
}
local tabBtns = {}
local function showTab(name)
	for n, p in pairs(pages) do p.Visible = (n == name) end
	for n, b in pairs(tabBtns) do
		local on = (n == name)
		b.BackgroundColor3 = on and C.accent or C.card
		b.TextColor3 = on and Color3.new(1, 1, 1) or C.sub
	end
	if name == "Saved" then refreshSaved() end
end
gotoTab = showTab
for i, t in ipairs(TABS) do
	local b = btn(tabBar, t[2], UDim2.fromOffset(#t[2] * 7 + 34, 28), nil, C.card, 12)
	b.LayoutOrder = i
	b.TextColor3 = C.sub
	tabBtns[t[1]] = b
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
