-- RGC Creator Store Browser v2 | DevNameGelo
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
	{name = "Audio",      id = 3,   icon = "♪"},
	{name = "Music",      id = 300, icon = "♪"},
	{name = "Plugins",    id = 38,  icon = "🔌"},
	{name = "Meshes",     id = 40,  icon = "🔷"},
	{name = "Animations", id = 24,  icon = "🏃"},
	{name = "Video",      id = 62,  icon = "🎬"},
	{name = "Fonts",      id = 73,  icon = "Aa"},
}
local TYPE_NAMES = {[1]="Image",[3]="Audio",[4]="Mesh",[10]="Model",[13]="Decal",[24]="Animation",[38]="Plugin",[40]="MeshPart",[62]="Video",[73]="Font",[300]="Music"}
local TYPE_ICONS = {[1]="🖼",[3]="♪",[4]="🔷",[10]="📦",[13]="🖼",[24]="🏃",[38]="🔌",[40]="🔷",[62]="🎬",[73]="Aa",[300]="♪"}
local PAGE_SIZE = 30
local DEFAULT_MODEL = "gemini-flash-latest"
local FILE = "RGC_CreatorStore.json"
-- Legacy compatibility fallback only; Roblox now recommends the v2 POST search below.
local MARKET = "https://apis.roblox.com/toolbox-service/v1/marketplace/"
local DETAILS = "https://apis.roblox.com/toolbox-service/v1/items/details?assetIds="

local C = {
	-- Deep navy + electric cyan glass palette
	bg = Color3.fromRGB(12, 18, 30),
	bar = Color3.fromRGB(22, 34, 52),
	card = Color3.fromRGB(28, 44, 66),
	accent = Color3.fromRGB(76, 190, 255),
	text = Color3.fromRGB(240, 247, 255),
	sub = Color3.fromRGB(157, 180, 205),
	good = Color3.fromRGB(82, 220, 170),
	bad = Color3.fromRGB(255, 105, 125),
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

-- ===== UI helpers =====
local function new(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props) do o[k] = v end
	if parent then o.Parent = parent end
	return o
end
local function round(o, r)
	new("UICorner", {CornerRadius = UDim.new(0, r or 8)}, o)
	if o:IsA("GuiObject") and o.BackgroundTransparency < 0.95 then
		o.BackgroundTransparency = math.max(o.BackgroundTransparency, 0.07)
	end
	if not o:FindFirstChildOfClass("UIStroke") then
		new("UIStroke", {Color = Color3.fromRGB(135, 190, 230), Thickness = 1, Transparency = 0.82}, o)
	end
	return o
end
local function btn(parent, text, size, pos, color, ts)
	return round(new("TextButton", {
		Size = size, Position = pos or UDim2.new(), BackgroundColor3 = color or C.card, Text = text,
		TextColor3 = C.text, Font = Enum.Font.GothamBold, TextSize = ts or 12, AutoButtonColor = true,
	}, parent), 6)
end
local function box(parent, placeholder, size, pos, multiline)
	local b = round(new("TextBox", {
		Size = size, Position = pos or UDim2.new(), BackgroundColor3 = C.card, Text = "",
		PlaceholderText = placeholder, PlaceholderColor3 = C.sub, TextColor3 = C.text,
		Font = Enum.Font.Gotham, TextSize = 13, ClearTextOnFocus = false,
		TextXAlignment = Enum.TextXAlignment.Left, MultiLine = multiline or false,
		TextWrapped = multiline or false, TextYAlignment = multiline and Enum.TextYAlignment.Top or Enum.TextYAlignment.Center,
	}, parent), 8)
	new("UIPadding", {PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8)}, b)
	return b
end
local function label(parent, text, size, pos, color, ts, font)
	return new("TextLabel", {
		Size = size, Position = pos or UDim2.new(), BackgroundTransparency = 1, Text = text,
		TextColor3 = color or C.text, Font = font or Enum.Font.Gotham, TextSize = ts or 12,
		TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true,
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
	new("UIListLayout", {FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder}, s)
	return s
end
local function vscroll(parent, size, pos)
	return new("ScrollingFrame", {
		Size = size, Position = pos, BackgroundTransparency = 1, ScrollBarThickness = 4,
		ScrollBarImageColor3 = C.accent, BorderSizePixel = 0, CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
	}, parent)
end

local grids = {}
local function makeGrid(parent, pos, size)
	local sc = vscroll(parent, size, pos)
	local g = new("UIGridLayout", {
		CellPadding = UDim2.fromOffset(6, 6), CellSize = UDim2.fromOffset(100, 140),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, sc)
	table.insert(grids, g)
	return sc, g
end

local function makeCell(parent, id, name, typeId, order)
	local cell = round(new("TextButton", {
		BackgroundColor3 = C.card, Text = "", AutoButtonColor = false, LayoutOrder = order,
	}, parent), 8)
	new("UIStroke", {Name = "Sel", Color = C.accent, Thickness = 2, Enabled = false, ApplyStrokeMode = Enum.ApplyStrokeMode.Border}, cell)
	local holder = round(new("Frame", {
		Size = UDim2.new(1, -8, 1, -48), Position = UDim2.fromOffset(4, 4),
		BackgroundColor3 = C.bar, ClipsDescendants = true,
	}, cell), 6)
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

local function responsiveWindowSize()
	local viewport = UIS:GetViewportSize()
	local width = math.clamp(viewport.X - 20, 300, 720)
	local height = math.clamp(viewport.Y - 44, 260, 680)
	return UDim2.fromOffset(width, height)
end

local main = round(new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
	Size = responsiveWindowSize(), BackgroundColor3 = C.bg, BackgroundTransparency = 0.08, ClipsDescendants = true,
}, gui), 12)
new("UIStroke", {Color = C.accent, Thickness = 1.35, Transparency = 0.25}, main)
new("UIGradient", {Color = ColorSequence.new({ColorSequenceKeypoint.new(0, Color3.fromRGB(18, 32, 53)), ColorSequenceKeypoint.new(1, Color3.fromRGB(10, 17, 29))}), Rotation = 28}, main)
UIS:GetPropertyChangedSignal("ViewportSize"):Connect(function()
	if main and main.Parent then
		main.Size = responsiveWindowSize()
		main.Position = UDim2.fromScale(0.5, 0.5)
	end
end)

local top = new("Frame", {Size = UDim2.new(1, 0, 0, 36), BackgroundColor3 = C.bar, BackgroundTransparency = 0.06, Active = true}, main)
new("UIGradient", {Color = ColorSequence.new({ColorSequenceKeypoint.new(0, Color3.fromRGB(40, 86, 124)), ColorSequenceKeypoint.new(1, Color3.fromRGB(20, 36, 57))}), Rotation = 0}, top)
new("TextLabel", {
	Size = UDim2.new(1, -190, 1, 0), Position = UDim2.fromOffset(12, 0), BackgroundTransparency = 1,
	Text = "RGC • Glass Creator Studio", TextColor3 = C.text, Font = Enum.Font.GothamBold,
	TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left,
}, top)
local function topBtn(txt, xOff, color)
	local b = btn(top, txt, UDim2.fromOffset(30, 26), UDim2.new(1, xOff, 0.5, -13), color, 13)
	b.ZIndex = 3
	return b
end
local btnClose = topBtn("X", -36, C.accent)
local btnExpand = topBtn("[]", -70)
local btnCollapse = topBtn("-", -104)
local btnLandscape = topBtn("LS", -138, C.accent)
local btnReverse = topBtn("RV", -172)

local body = new("Frame", {Size = UDim2.new(1, 0, 1, -36), Position = UDim2.fromOffset(0, 36), BackgroundTransparency = 1}, main)
local tabBar = hscroll(body, UDim2.new(1, -16, 0, 28), UDim2.fromOffset(8, 4))

local pages = {}
local function newPage(name)
	local f = new("Frame", {
		Name = name, Size = UDim2.new(1, 0, 1, -36), Position = UDim2.fromOffset(0, 36),
		BackgroundTransparency = 1, Visible = false,
	}, body)
	pages[name] = f
	return f
end

local toast = round(new("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -12),
	Size = UDim2.fromOffset(260, 30), BackgroundColor3 = C.accent, TextColor3 = C.text,
	Font = Enum.Font.GothamBold, TextSize = 12, Visible = false, ZIndex = 30, TextTruncate = Enum.TextTruncate.AtEnd,
}, main), 15)
local toastId = 0
local function showToast(msg)
	toastId += 1
	local my = toastId
	toast.Text = msg
	toast.Visible = true
	task.delay(1.8, function()
		if my == toastId then toast.Visible = false end
	end)
end
local function copyOut(text, what)
	local ok = copy(text)
	showToast(ok and ("Copied " .. what) or "Clipboard not supported")
	return ok
end

local bubble = round(new("TextButton", {
	Size = UDim2.fromOffset(48, 48), Position = UDim2.new(0, 12, 0.5, -24),
	BackgroundColor3 = C.accent, Text = "RGC", TextColor3 = C.text,
	Font = Enum.Font.GothamBlack, TextSize = 13, Visible = false, AutoButtonColor = false,
}, gui), 24)
new("UIStroke", {Color = C.text, Thickness = 1.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border}, bubble)

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
local expanded, collapsed = false, false
local function relayout(w)
	local avail = w - 16 - 8
	local cols = math.max(2, math.floor(avail / 112))
	local cell = math.floor((avail - (cols - 1) * 6) / cols)
	for _, g in ipairs(grids) do
		g.CellSize = UDim2.fromOffset(cell, cell + 40)
	end
end
local function calcSize()
	local cam = Workspace.CurrentCamera
	local vp = cam and cam.ViewportSize or Vector2.new(800, 600)
	if expanded then
		return math.floor(vp.X * 0.98), math.floor(vp.Y * 0.96)
	end
	return math.floor(math.min(680, vp.X * 0.96)), math.floor(math.min(560, vp.Y * 0.92))
end
local function apply()
	local w, h = calcSize()
	body.Visible = not collapsed
	TweenService:Create(main, TweenInfo.new(0.15), {Size = UDim2.fromOffset(w, collapsed and 36 or h)}):Play()
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
local function hookCamera()
	local cam = Workspace.CurrentCamera
	if cam then cam:GetPropertyChangedSignal("ViewportSize"):Connect(apply) end
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
local function stopSound()
	pcall(function() sound:Stop() end)
	if bPlay then bPlay.Text = "Play audio" end
end
sound.Ended:Connect(function() if bPlay then bPlay.Text = "Play audio" end end)

-- ===== Detail popup =====
local refreshSaved, refreshExplorer
local projectRoot
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
local bInsert = dBtn("Insert to project", 9, C.good)
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
	if not projectRoot then showToast("Project root not ready") return end
	local item = curItem
	local id, typeId = tonumber(item.id), tonumber(item.typeId)
	if not id then showToast("Invalid asset ID") return end
	local function disableImportedScripts(root)
		if root:IsA("LuaSourceContainer") then pcall(function() root.Enabled = false end) end
		for _, child in ipairs(root:GetDescendants()) do
			if child:IsA("LuaSourceContainer") then pcall(function() child.Enabled = false end) end
		end
	end
	local function makePart()
		local p = Instance.new("Part")
		p.Name = item.name or "ImportedAsset"
		p.Anchored = true
		p.Size = Vector3.new(4, 1, 4)
		local lp = Players.LocalPlayer
		local hrp = lp and lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
		if hrp then p.CFrame = hrp.CFrame * CFrame.new(0, 3, -8) else p.Position = Vector3.new(0, 5, 0) end
		return p
	end
	local ok, msg = pcall(function()
		if typeId == 10 then
			local objects
			local okGet, got = pcall(function() return game:GetObjects("rbxassetid://" .. id) end)
			if okGet and type(got) == "table" and #got > 0 then objects = got end
			if not objects then
				local InsertService = game:GetService("InsertService")
				local okLoad, loaded = pcall(function() return InsertService:LoadAsset(id) end)
				if okLoad and loaded then objects = {loaded} end
			end
			if not objects then error("Model import is blocked by this runtime") end
			for _, obj in ipairs(objects) do
				disableImportedScripts(obj)
				obj.Parent = projectRoot
			end
		elseif typeId == 3 or typeId == 300 then
			local snd = Instance.new("Sound")
			snd.Name = item.name or "ImportedAudio"
			snd.SoundId = "rbxassetid://" .. id
			snd.Parent = projectRoot
		elseif typeId == 13 or typeId == 1 then
			local part = makePart(); part.Parent = projectRoot
			local decal = Instance.new("Decal")
			decal.Name = "ImportedDecal"; decal.Texture = "rbxassetid://" .. id
			decal.Face = Enum.NormalId.Top; decal.Parent = part
		elseif typeId == 40 or typeId == 4 then
			local part = makePart(); part.Parent = projectRoot
			local mesh = Instance.new("SpecialMesh")
			mesh.MeshType = Enum.MeshType.FileMesh; mesh.MeshId = "rbxassetid://" .. id; mesh.Parent = part
		elseif typeId == 24 then
			local anim = Instance.new("Animation")
			anim.Name = item.name or "ImportedAnimation"; anim.AnimationId = "rbxassetid://" .. id; anim.Parent = projectRoot
		elseif typeId == 62 then
			local part = makePart(); part.Parent = projectRoot
			local surface = Instance.new("SurfaceGui"); surface.Face = Enum.NormalId.Front; surface.Parent = part
			local video = Instance.new("VideoFrame"); video.Size = UDim2.fromScale(1, 1); video.Video = "rbxassetid://" .. id; video.Parent = surface
		elseif typeId == 38 then
			error("Plugins cannot be installed from an in-game runtime. Copy the ID and install through Studio.")
		else
			error("This asset type cannot be inserted by this runtime")
		end
	end)
	if ok then detail.Visible = false; showToast("Asset added to RGC_Project (runtime-local)") else showToast("Insert failed: " .. tostring(msg):sub(1, 100)) end
end)

bPlay.MouseButton1Click:Connect(function()
	if not curItem then return end
	local rid = "rbxassetid://" .. tostring(curItem.id)
	if sound.IsPlaying and sound.SoundId == rid then
		stopSound()
		return
	end
	sound.SoundId = rid
	sound:Play()
	bPlay.Text = "Stop audio"
	local my = curItem
	task.delay(5, function()
		if curItem == my and not sound.IsLoaded then showToast("Audio can't load (private?)") end
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
		local categoryV2 = v2Type[catIdx]
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
			res = getJSON(url)
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
						if a and a.id then info[a.id] = {name = a.name, creator = d.creator and d.creator.name, desc = a.description, typeId = a.typeId} end
					end
				end
			end
			hasNext = #ids >= PAGE_SIZE
		end
		if my ~= reqId then return end
		if #ids == 0 and not append then status.Text = "No results"; return end
		status.Text = ""
		if loadBtn then loadBtn:Destroy() loadBtn = nil end
		for _, id in ipairs(ids) do
			local item = info[id] or {}
			addStoreCell({id = id, name = item.name, typeId = item.typeId or cat.id, creator = item.creator, desc = item.desc})
		end
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

-- ===== EXPLORER PAGE =====
local pExp = newPage("Explorer")
-- A dedicated project folder keeps the project Explorer separate from game-wide Dex.
-- This folder is created on the client in executor environments; it is not a saved Studio project.
projectRoot = Workspace:FindFirstChild("RGC_Project")
if not projectRoot then
	projectRoot = Instance.new("Folder")
	projectRoot.Name = "RGC_Project"
	projectRoot.Parent = Workspace
end
local expCur = projectRoot
local okCore, CoreGui = pcall(game.GetService, game, "CoreGui")

local function isIdent(s) return s:match("^[%a_][%w_]*$") ~= nil end
local function getPath(inst)
	if inst == game then return "game" end
	local parts, cur = {}, inst
	while cur and cur ~= game do
		table.insert(parts, 1, cur)
		cur = cur.Parent
	end
	local out = "game"
	for i, p in ipairs(parts) do
		if i == 1 and p.Parent == game then
			local okS = pcall(game.GetService, game, p.ClassName)
			out = okS and ('game:GetService("%s")'):format(p.ClassName) or ("game[%q]"):format(p.Name)
		else
			out = out .. (isIdent(p.Name) and ("." .. p.Name) or ("[%q]"):format(p.Name))
		end
	end
	return out
end

local function dumpTree(root, maxDepth, maxNodes)
	local lines, count = {}, 0
	local function walk(inst, depth)
		if count >= maxNodes then return end
		count += 1
		local line = string.rep("  ", depth) .. inst.Name .. " [" .. inst.ClassName .. "]"
		local okv, v = pcall(function()
			if inst:IsA("ValueBase") then return tostring(inst.Value) end
		end)
		if okv and v then line = line .. " = " .. v:sub(1, 120):gsub("\n", " ") end
		table.insert(lines, line)
		if depth >= maxDepth then return end
		local ok, kids = pcall(inst.GetChildren, inst)
		if ok then
			for _, k in ipairs(kids) do
				if k ~= gui then walk(k, depth + 1) end
			end
		end
	end
	walk(root, 0)
	if count >= maxNodes then table.insert(lines, "... (truncated)") end
	return table.concat(lines, "\n")
end

local expPath = label(pExp, "game", UDim2.new(1, -16, 0, 18), UDim2.fromOffset(8, 0), C.sub, 11, Enum.Font.Code)
expPath.TextWrapped = false
expPath.TextTruncate = Enum.TextTruncate.AtEnd
local expBar = hscroll(pExp, UDim2.new(1, -16, 0, 28), UDim2.fromOffset(8, 20))
local expRoot = label(pExp, "Project root: " .. getPath(projectRoot), UDim2.new(1, -16, 0, 16), UDim2.fromOffset(8, 50), C.accent, 11)
expRoot.TextWrapped = false
expRoot.TextTruncate = Enum.TextTruncate.AtEnd
local expScroll = vscroll(pExp, UDim2.new(1, -16, 1, -72), UDim2.fromOffset(8, 68))
new("UIListLayout", {Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder}, expScroll)

local function rowText(inst)
	local kids = 0
	pcall(function() kids = #inst:GetChildren() end)
	local s = inst.Name .. "  [" .. inst.ClassName .. "]"
	if kids > 0 then s = s .. "  (" .. kids .. ")" end
	local ok, v = pcall(function()
		if inst:IsA("ValueBase") then return tostring(inst.Value) end
	end)
	if ok and v then s = s .. "  = " .. v:sub(1, 40):gsub("\n", " ") end
	return s
end

refreshExplorer = function()
	clearGui(expScroll)
	expPath.Text = getPath(expCur)
	local ok, kids = pcall(expCur.GetChildren, expCur)
	if not ok then kids = {} end
	table.sort(kids, function(a, b) return a.Name:lower() < b.Name:lower() end)
	local n = 0
	for _, k in ipairs(kids) do
		if k ~= gui then
			n += 1
			if n > 300 then break end
			local b = round(new("TextButton", {
				Size = UDim2.new(1, -6, 0, 28), BackgroundColor3 = C.card, Text = rowText(k),
				TextColor3 = C.text, Font = Enum.Font.Gotham, TextSize = 12,
				TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, LayoutOrder = n,
			}, expScroll), 6)
			new("UIPadding", {PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8)}, b)
			b.MouseButton1Click:Connect(function()
				local has = false
				pcall(function() has = #k:GetChildren() > 0 end)
				if has then
					expCur = k
					refreshExplorer()
				else
					showToast(k.ClassName .. ": " .. k.Name)
				end
			end)
		end
	end
	if n == 0 then
		label(expScroll, "Empty", UDim2.new(1, -6, 0, 24), nil, C.sub, 12)
	end
end

local function expBtn(text, w, color)
	return btn(expBar, text, UDim2.fromOffset(w, 28), nil, color or C.card, 11)
end
local eUp = expBtn("Up", 50)
local eGame = expBtn("Project", 62)
local eRoot = expBtn("Set root", 74, C.accent)
local ePath = expBtn("Copy path", 80)
local eTree = expBtn("Copy tree", 78)
local eRem = expBtn("Project remotes", 104)

eUp.MouseButton1Click:Connect(function()
	if expCur == projectRoot then return end
	local parent = expCur.Parent
	if parent and (parent == projectRoot or parent:IsDescendantOf(projectRoot)) then expCur = parent end
	refreshExplorer()
end)
eGame.MouseButton1Click:Connect(function()
	expCur = projectRoot
	refreshExplorer()
end)
eRoot.MouseButton1Click:Connect(function()
	if expCur == game or expCur == Workspace or not expCur:IsDescendantOf(Workspace) then showToast("Choose a folder inside Workspace") return end
	projectRoot = expCur
	expCur = projectRoot
	expRoot.Text = "Project root: " .. getPath(projectRoot)
	showToast("Project scope changed")
end)
ePath.MouseButton1Click:Connect(function() copyOut(getPath(expCur), "path") end)
eTree.MouseButton1Click:Connect(function() copyOut(dumpTree(expCur, 6, 500), "tree") end)
eRem.MouseButton1Click:Connect(function()
	local out, n = {}, 0
	local scope = projectRoot
	local okD, desc = pcall(scope.GetDescendants, scope)
	if not okD then showToast("Project scan failed") return end
	for _, d in ipairs(desc) do
		if d:IsA("RemoteEvent") or d:IsA("RemoteFunction") or d:IsA("BindableEvent") or d:IsA("BindableFunction") then
			n += 1
			if n <= 200 then table.insert(out, d.ClassName .. "  " .. getPath(d)) end
		end
	end
	copyOut(table.concat(out, "\n"), n .. " project remotes")
end)

-- Build bounded context for AI. Script.Source is protected in normal clients,
-- so unavailable source is reported rather than fabricated.
local function readLocalScriptSource(inst)
	if not inst or not (inst:IsA("Script") or inst:IsA("LocalScript") or inst:IsA("ModuleScript")) then return nil, "Not a script" end
	local ok, src = pcall(function() return inst.Source end)
	if ok and type(src) == "string" then return src, nil end
	return nil, "Roblox protected script source in this environment"
end

local function dumpProjectContext(root)
	root = root or projectRoot
	local out = {"PROJECT ROOT: " .. getPath(root), "INSTANCE TREE:", dumpTree(root, 7, 500), "", "SCRIPT SOURCES (only where runtime permissions allow):"}
	local used, count = 0, 0
	local ok, descendants = pcall(root.GetDescendants, root)
	if ok then
		for _, inst in ipairs(descendants) do
			if inst:IsA("Script") or inst:IsA("LocalScript") or inst:IsA("ModuleScript") then
				count += 1
				if count > 18 or used > 26000 then
					table.insert(out, "[More scripts omitted to keep AI context bounded]")
					break
				end
				local src, err = readLocalScriptSource(inst)
				if src then
					local part = "\n--- " .. getPath(inst) .. " ---\n" .. src:sub(1, 6500)
					table.insert(out, part)
					used += #part
				else
					table.insert(out, "\n--- " .. getPath(inst) .. " ---\n[SOURCE UNAVAILABLE: " .. tostring(err) .. "]")
				end
			end
		end
	end
	return table.concat(out, "\n")
end

-- ===== AI PAGE (Gemini) =====
local pAI = newPage("AI")
local chat = {}
local ctxOn = false
local busy = false
local msgOrder = 0

local SYSTEM_PROMPT = "You are an expert Roblox Luau scripting assistant for the mobile game-building app Studio Lite. "
	.. "Be concise. Give complete, ready-to-paste scripts inside ```lua code blocks. "
	.. "Say which script type to use (Script, LocalScript, ModuleScript) and where to put it. "
	.. "Use modern Luau (task.wait, no wait()). If a PROJECT TREE is provided, use its exact names and paths. "
	.. "If something can't be done in Studio Lite or needs Roblox Studio, say so briefly."

local aiBar = new("Frame", {Size = UDim2.new(1, -16, 0, 28), Position = UDim2.fromOffset(8, 0), BackgroundTransparency = 1}, pAI)
local ctxBtn = btn(aiBar, "Context: OFF", UDim2.new(0.4, -3, 1, 0), UDim2.new(0, 0, 0, 0), C.card, 11)
local clearBtn = btn(aiBar, "Clear chat", UDim2.new(0.28, -3, 1, 0), UDim2.new(0.4, 0, 0, 0), C.card, 11)
local setBtn = btn(aiBar, "Settings", UDim2.new(0.32, 0, 1, 0), UDim2.new(0.68, 0, 0, 0), C.card, 11)

local chatScroll = vscroll(pAI, UDim2.new(1, -16, 1, -76), UDim2.fromOffset(8, 32))
new("UIListLayout", {Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder}, chatScroll)
local inputBox = box(pAI, "Ask for a script...", UDim2.new(1, -86, 0, 36), UDim2.new(0, 8, 1, -40), true)
local sendBtn = btn(pAI, "Send", UDim2.fromOffset(62, 36), UDim2.new(1, -70, 1, -40), C.accent, 13)

local settingsPanel = round(new("Frame", {
	Size = UDim2.new(1, -16, 0, 208), Position = UDim2.fromOffset(8, 32),
	BackgroundColor3 = C.bar, Visible = false, ZIndex = 6,
}, pAI), 8)
new("UIPadding", {PaddingTop = UDim.new(0, 6), PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8)}, settingsPanel)
new("UIListLayout", {Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder}, settingsPanel)
local l1 = label(settingsPanel, "Gemini API key (saved locally; never sent to Roblox)", UDim2.new(1, 0, 0, 14), nil, C.sub, 11)
l1.LayoutOrder = 1
local keyBox = box(settingsPanel, (db.set.gemKey and db.set.gemKey ~= "") and "Key saved - type to replace" or "Paste API key", UDim2.new(1, 0, 0, 30))
keyBox.LayoutOrder = 2
local l2 = label(settingsPanel, "Model", UDim2.new(1, 0, 0, 14), nil, C.sub, 11)
l2.LayoutOrder = 3
local modelBox = box(settingsPanel, DEFAULT_MODEL, UDim2.new(1, 0, 0, 30))
modelBox.LayoutOrder = 4
modelBox.Text = db.set.gemModel or ""
local l3 = label(settingsPanel, "Creator Store API key (creator-store-product:read) • saved locally as plain text; separate from Publish key", UDim2.new(1, 0, 0, 14), nil, C.sub, 10)
l3.LayoutOrder = 5
local storeKeyBox = box(settingsPanel, (db.set.storeKey and db.set.storeKey ~= "") and "Creator Store key saved - type to replace" or "Paste read-only Creator Store API key", UDim2.new(1, 0, 0, 30))
storeKeyBox.LayoutOrder = 6
local saveKeyBtn = btn(settingsPanel, "Save keys", UDim2.new(1, 0, 0, 28), nil, C.accent, 12)
saveKeyBtn.LayoutOrder = 7
saveKeyBtn.MouseButton1Click:Connect(function()
	local k = trim(keyBox.Text)
	if k ~= "" then
		db.set.gemKey = k
		keyBox.Text = ""
		keyBox.PlaceholderText = "Gemini key saved - type to replace"
	end
	local sk = trim(storeKeyBox.Text)
	if sk ~= "" then
		db.set.storeKey = sk
		storeKeyBox.Text = ""
		storeKeyBox.PlaceholderText = "Creator Store key saved - type to replace"
	end
	db.set.gemModel = trim(modelBox.Text)
	saveDB()
	settingsPanel.Visible = false
	showToast("AI settings saved")
end)
setBtn.MouseButton1Click:Connect(function() settingsPanel.Visible = not settingsPanel.Visible end)

local function parseBlocks(text)
	local out, pos = {}, 1
	while pos <= #text do
		local s, e = text:find("```", pos, true)
		if not s then
			table.insert(out, {t = "text", v = text:sub(pos)})
			break
		end
		table.insert(out, {t = "text", v = text:sub(pos, s - 1)})
		local s2, e2 = text:find("```", e + 1, true)
		local code
		if s2 then
			code = text:sub(e + 1, s2 - 1)
			pos = e2 + 1
		else
			code = text:sub(e + 1)
			pos = #text + 1
		end
		code = code:gsub("^[ \t]*%a*[ \t]*\r?\n", "", 1)
		table.insert(out, {t = "code", v = code})
	end
	return out
end

local function scrollBottom()
	task.defer(function() chatScroll.CanvasPosition = Vector2.new(0, 1e6) end)
end

local function addMessage(role, text)
	msgOrder += 1
	local f = round(new("Frame", {
		Size = UDim2.new(1, -6, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = (role == "user") and Color3.fromRGB(60, 32, 40) or C.bar, LayoutOrder = msgOrder,
	}, chatScroll), 8)
	new("UIPadding", {PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6), PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8)}, f)
	new("UIListLayout", {Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder}, f)
	local blocks = (role == "model") and parseBlocks(text) or {{t = "text", v = text}}
	local n = 0
	for _, b in ipairs(blocks) do
		local v = trim(b.v)
		if #v > 15000 then v = v:sub(1, 15000) .. "\n...(cut)" end
		if v ~= "" then
			n += 1
			if b.t == "text" then
				local tl = label(f, v, UDim2.new(1, 0, 0, 0), nil, C.text, 13)
				tl.AutomaticSize = Enum.AutomaticSize.Y
				tl.TextYAlignment = Enum.TextYAlignment.Top
				tl.LayoutOrder = n
			else
				local cf = round(new("Frame", {
					Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
					BackgroundColor3 = Color3.fromRGB(10, 10, 14), LayoutOrder = n,
				}, f), 6)
				new("UIPadding", {PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 4), PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6)}, cf)
				new("UIListLayout", {Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder}, cf)
				local cb = btn(cf, "Copy code", UDim2.new(1, 0, 0, 24), nil, C.accent, 12)
				cb.LayoutOrder = 1
				local cl = label(cf, v, UDim2.new(1, 0, 0, 0), nil, C.text, 11, Enum.Font.Code)
				cl.AutomaticSize = Enum.AutomaticSize.Y
				cl.TextYAlignment = Enum.TextYAlignment.Top
				cl.LayoutOrder = 2
				local code = v
				cb.MouseButton1Click:Connect(function() copyOut(code, "code") end)
			end
		end
	end
	if role == "model" and #text > 0 then
		local whole = text
		local cb = btn(f, "Copy full reply", UDim2.new(1, 0, 0, 22), nil, C.card, 11)
		cb.LayoutOrder = n + 1
		cb.MouseButton1Click:Connect(function() copyOut(whole, "reply") end)
	end
	scrollBottom()
	return f
end

local function geminiChat()
	local key = db.set.gemKey
	local model = (db.set.gemModel and db.set.gemModel ~= "") and db.set.gemModel or DEFAULT_MODEL
	local contents = {}
	local from = math.max(1, #chat - 15)
	for i = from, #chat do
		local m = chat[i]
		table.insert(contents, {role = m.role, parts = {{text = (i == #chat) and m.send or m.text}}})
	end
	if contents[1] and contents[1].role ~= "user" then table.remove(contents, 1) end
	local body = HttpService:JSONEncode({
		system_instruction = {parts = {{text = SYSTEM_PROMPT}}},
		contents = contents,
	})
	local url = "https://generativelanguage.googleapis.com/v1beta/models/" .. model .. ":generateContent"
	local res = doRequest({
		Url = url, Method = "POST",
		Headers = {["Content-Type"] = "application/json", ["x-goog-api-key"] = key},
		Body = body,
	})
	local raw
	if res then
		raw = res.Body
	else
		local ok, r = pcall(function() return game:HttpPostAsync(url .. "?key=" .. key, body, "application/json") end)
		if ok then raw = r end
	end
	if not raw then return nil, "No response. Your executor may block HTTP requests." end
	local ok, data = pcall(HttpService.JSONDecode, HttpService, raw)
	if not ok or type(data) ~= "table" then
		return nil, "Bad response" .. (res and (" (HTTP " .. tostring(res.StatusCode) .. ")") or "")
	end
	if data.error then return nil, tostring(data.error.message or "API error") end
	local cand = data.candidates and data.candidates[1]
	local parts = cand and cand.content and cand.content.parts
	if not parts then
		return nil, (cand and cand.finishReason) and ("Blocked: " .. tostring(cand.finishReason)) or "Empty reply"
	end
	local out = {}
	for _, p in ipairs(parts) do
		if p.text and not p.thought then table.insert(out, p.text) end
	end
	return table.concat(out)
end

local function sendMessage()
	if busy then return end
	local txt = trim(inputBox.Text)
	if txt == "" then return end
	if not db.set.gemKey or db.set.gemKey == "" then
		settingsPanel.Visible = true
		showToast("Add your Gemini API key first")
		return
	end
	inputBox.Text = ""
	addMessage("user", txt)
	local payload = txt
	if ctxOn then
		if projectRoot then
			payload = dumpProjectContext(projectRoot) .. "\n\nUSER REQUEST:\n" .. txt
		else
			showToast("No project root set - sending without context")
		end
	end
	table.insert(chat, {role = "user", text = txt, send = payload})
	busy = true
	local thinking = addMessage("model", "Thinking...")
	task.spawn(function()
		local reply, err = geminiChat()
		thinking:Destroy()
		busy = false
		if reply and reply ~= "" then
			table.insert(chat, {role = "model", text = reply, send = reply})
			addMessage("model", reply)
		else
			table.remove(chat)
			addMessage("model", "Error: " .. tostring(err))
		end
	end)
end
sendBtn.MouseButton1Click:Connect(sendMessage)
ctxBtn.MouseButton1Click:Connect(function()
	ctxOn = not ctxOn
	ctxBtn.Text = ctxOn and "Context: ON" or "Context: OFF"
	ctxBtn.BackgroundColor3 = ctxOn and C.accent or C.card
	if ctxOn and not projectRoot then showToast("Set a project root in Explorer first") end
end)
clearBtn.MouseButton1Click:Connect(function()
	chat = {}
	clearGui(chatScroll)
	showToast("Chat cleared")
end)
addMessage("model", "Hi! Ask me for Roblox scripts and I'll give you code with Copy buttons. Add your Gemini key in Settings. Turn Context ON to share your project tree and readable scripts from your selected project.")

local function buildStudioBuilderPage()
-- ===== STUDIO BUILDER / PROJECT DEX =====
-- Live runtime editor scoped strictly to projectRoot. Changes are local to this running client.
local pBuilder = newPage("Builder")
local buildScroll = vscroll(pBuilder, UDim2.new(1, -12, 1, -4), UDim2.fromOffset(6, 2))
new("UIListLayout", {Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder}, buildScroll)
local buildOrder = 0
local function bo() buildOrder += 1 return buildOrder end
local function bLabel(text, h, color, size)
	local l = label(buildScroll, text, UDim2.new(1, -8, 0, h), nil, color or C.sub, size or 11)
	l.LayoutOrder = bo()
	return l
end
local function bRow(height)
	local r = new("Frame", {Size = UDim2.new(1, -8, 0, height), BackgroundTransparency = 1, LayoutOrder = bo()}, buildScroll)
	return r
end
local function bBtn(parent, text, width, x, callback, color)
	local b = btn(parent, text, UDim2.new(width, -4, 1, 0), UDim2.new(x, 0, 0, 0), color or C.card, 11)
	b.MouseButton1Click:Connect(callback)
	return b
end
local function bInput(parent, placeholder, width, x, multiline)
	return box(parent, placeholder, UDim2.new(width, -4, 1, 0), UDim2.new(x, 0, 0, 0), multiline)
end

local scopeLabel = bLabel("PROJECT SCOPE • Workspace/RGC_Project • runtime-local changes", 20, C.accent, 11)
local createRow1 = bRow(28)
local createRow2 = bRow(28)
local createRow3 = bRow(28)
local builderSelected = nil
local builderSource = nil
local builderTree
local selectedLabel = bLabel("Selected: none", 18, C.text, 12)
local propertyNameBox, positionBox, sizeBox, transparencyBox, rotationBox, movePathBox
local scriptEditor
local stagedActions = nil
local undoStack = {}
local deletePending = nil

local function inProject(inst)
	return inst == projectRoot or (inst and inst:IsDescendantOf(projectRoot))
end
local function safePathFind(path)
	if path == nil or path == "" or path == "root" or path == "." then return projectRoot end
	local cur = projectRoot
	for segment in tostring(path):gmatch("[^/]+") do
		local nextInst = cur:FindFirstChild(segment)
		if not nextInst then return nil end
		cur = nextInst
	end
	return cur
end
local function vectorText(v)
	return string.format("%.2f, %.2f, %.2f", v.X, v.Y, v.Z)
end
local function parseVector(txt)
	local nums = {}
	for token in tostring(txt or ""):gmatch("[-+]?[%d]*%.?[%d]+") do table.insert(nums, tonumber(token)) end
	if #nums < 3 then return nil end
	for i = 1, 3 do if nums[i] ~= nums[i] or math.abs(nums[i]) > 100000 then return nil end end
	return Vector3.new(nums[1], nums[2], nums[3])
end
local function refreshBuilder()
	if not builderTree then return end
	clearGui(builderTree)
	if not inProject(builderSelected) then builderSelected = nil end
	local count = 0
	local function addChildren(parent, depth)
		if count >= 160 then return end
		local kids = parent:GetChildren()
		table.sort(kids, function(a, b) return a.Name:lower() < b.Name:lower() end)
		for _, inst in ipairs(kids) do
			if count >= 160 then return end
			count += 1
			local icon = inst:IsA("BasePart") and "◆" or (inst:IsA("LuaSourceContainer") and "▣" or (inst:IsA("Folder") and "▸" or "◇"))
			local row = round(new("TextButton", {Size = UDim2.new(1, -6, 0, 24), BackgroundColor3 = (inst == builderSelected) and Color3.fromRGB(36, 91, 126) or C.card, Text = string.rep("  ", math.min(depth, 5)) .. icon .. "  " .. inst.Name .. "  ·  " .. inst.ClassName, TextColor3 = C.text, Font = Enum.Font.Gotham, TextSize = 11, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, LayoutOrder = count}, builderTree), 6)
			new("UIPadding", {PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 4)}, row)
			row.MouseButton1Click:Connect(function()
				builderSelected = inst
				refreshBuilder()
			end)
			if depth < 4 and #inst:GetChildren() > 0 then addChildren(inst, depth + 1) end
		end
	end
	addChildren(projectRoot, 0)
	if count == 0 then
		local empty = label(builderTree, "Your project is empty. Create a Part, Model, Folder or Script above.", UDim2.new(1, -6, 0, 30), nil, C.sub, 11)
		empty.LayoutOrder = 1
	end
	if builderSelected then
		selectedLabel.Text = "Selected: " .. getPath(builderSelected) .. "  [" .. builderSelected.ClassName .. "]"
		propertyNameBox.Text = builderSelected.Name
		if builderSelected:IsA("BasePart") then
			positionBox.Text = vectorText(builderSelected.Position)
			sizeBox.Text = vectorText(builderSelected.Size)
			transparencyBox.Text = tostring(builderSelected.Transparency)
			rotationBox.Text = vectorText(builderSelected.Orientation)
		else
			positionBox.Text = ""
			sizeBox.Text = ""
			transparencyBox.Text = ""
			rotationBox.Text = ""
		end
		local src = readLocalScriptSource(builderSelected)
		if src then scriptEditor.Text = src else scriptEditor.Text = "-- Select a Script / LocalScript / ModuleScript.\n-- Source may be protected in this runtime." end
	else
		selectedLabel.Text = "Selected: none"
		propertyNameBox.Text = ""
		positionBox.Text = ""
		sizeBox.Text = ""
		transparencyBox.Text = ""
		rotationBox.Text = ""
		scriptEditor.Text = "-- Script editor: select a script from the project tree."
	end
end

builderTree = vscroll(buildScroll, UDim2.new(1, -8, 0, 92), nil)
builderTree.LayoutOrder = bo()
new("UIListLayout", {Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder}, builderTree)

local function disableScriptsDeep(root)
	if root:IsA("LuaSourceContainer") then pcall(function() root.Enabled = false end) end
	for _, child in ipairs(root:GetDescendants()) do
		if child:IsA("LuaSourceContainer") then pcall(function() child.Enabled = false end) end
	end
end

local function newObject(className)
	local classMap = {Part = "Part", Folder = "Folder", Model = "Model", Script = "Script", LocalScript = "LocalScript", ModuleScript = "ModuleScript", Wedge = "WedgePart", Spawn = "SpawnLocation", Light = "PointLight", Sound = "Sound", Attachment = "Attachment", Decal = "Decal"}
	local actual = classMap[className]
	if not actual then showToast("Unsupported object type") return end
	local obj
	local ok, err = pcall(function() obj = Instance.new(actual) end)
	if not ok or not obj then showToast("Create failed: " .. tostring(err)) return end
	obj.Name = "New" .. className
	if obj:IsA("BasePart") then
		obj.Anchored = true
		obj.Size = Vector3.new(4, 1, 4)
		local cf = CFrame.new(0, 5, 0)
		local lp = Players.LocalPlayer
		local char = lp and lp.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if hrp then cf = hrp.CFrame * CFrame.new(0, 3, -8) end
		obj.CFrame = cf
	elseif obj:IsA("LuaSourceContainer") then
		pcall(function() obj.Source = "-- Created with RGC Builder\n" end)
		pcall(function() obj.Enabled = false end)
	elseif obj:IsA("PointLight") then
		obj.Brightness = 1; obj.Range = 16
	elseif obj:IsA("Sound") then
		obj.Volume = 0.5
	end
	local selectedCanContain = builderSelected and (builderSelected:IsA("Folder") or builderSelected:IsA("Model"))
	local attachToPart = builderSelected and builderSelected:IsA("BasePart") and (actual == "PointLight" or actual == "Attachment" or actual == "Decal")
	local dest = selectedCanContain and builderSelected or (attachToPart and builderSelected or projectRoot)
	obj.Parent = dest
	builderSelected = obj
	table.insert(undoStack, {kind = "created", inst = obj})
	refreshBuilder()
	showToast(className .. " created in project")
end

bBtn(createRow1, "+ Part", 0.25, 0, function() newObject("Part") end, C.accent)
bBtn(createRow1, "+ Model", 0.25, 0.25, function() newObject("Model") end)
bBtn(createRow1, "+ Folder", 0.25, 0.50, function() newObject("Folder") end)
bBtn(createRow1, "+ Wedge", 0.25, 0.75, function() newObject("Wedge") end)
bBtn(createRow2, "+ Script", 1/3, 0, function() newObject("Script") end)
bBtn(createRow2, "+ LocalScript", 1/3, 1/3, function() newObject("LocalScript") end)
bBtn(createRow2, "+ Module", 1/3, 2/3, function() newObject("ModuleScript") end)
bBtn(createRow3, "+ Light", 0.25, 0, function() newObject("Light") end)
bBtn(createRow3, "+ Sound", 0.25, 0.25, function() newObject("Sound") end)
bBtn(createRow3, "+ Attachment", 0.25, 0.50, function() newObject("Attachment") end)
bBtn(createRow3, "+ Decal", 0.25, 0.75, function() newObject("Decal") end)

local treeTools = bRow(26)
bBtn(treeTools, "Refresh", 0.25, 0, function() refreshBuilder() end)
bBtn(treeTools, "Duplicate", 0.25, 0.25, function()
	if not builderSelected or not inProject(builderSelected) then showToast("Select an object") return end
	local ok, clone = pcall(function() return builderSelected:Clone() end)
	if not ok or not clone then showToast("Clone failed") return end
	disableScriptsDeep(clone)
	clone.Name = builderSelected.Name .. " Copy"
	clone.Parent = builderSelected.Parent
	builderSelected = clone
	table.insert(undoStack, {kind = "created", inst = clone})
	refreshBuilder()
end)
local delBtn
delBtn = bBtn(treeTools, "Delete", 0.25, 0.50, function()
	if not builderSelected or not inProject(builderSelected) then showToast("Select an object") return end
	if deletePending ~= builderSelected then
		deletePending = builderSelected
		delBtn.Text = "Confirm?"
		showToast("Tap Delete again to confirm")
		return
	end
	local inst = builderSelected
	local parent = inst.Parent
	local cloneOk, backup = pcall(function() return inst:Clone() end)
	if cloneOk and backup then disableScriptsDeep(backup); table.insert(undoStack, {kind = "deleted", inst = backup, parent = parent}) end
	inst:Destroy()
	builderSelected, deletePending = nil, nil
	delBtn.Text = "Delete"
	refreshBuilder()
	showToast("Object deleted")
end, C.bad)
local undoBtn = bBtn(treeTools, "Undo", 0.25, 0.75, function()
	local last = table.remove(undoStack)
	if not last then showToast("Nothing to undo") return end
	if last.kind == "batch" then
		for i = #last.entries, 1, -1 do
			local entry = last.entries[i]
			if entry.kind == "created" and entry.inst and entry.inst.Parent then entry.inst:Destroy()
			elseif entry.kind == "deleted" and entry.inst and entry.parent then entry.inst.Parent = entry.parent
			elseif entry.kind == "props" and entry.inst and entry.inst.Parent then for key, value in pairs(entry.values) do pcall(function() entry.inst[key] = value end) end
			elseif entry.kind == "custom" and entry.undo then pcall(entry.undo)
			end
		end
	elseif last.kind == "source" and last.inst then pcall(function() last.inst.Source = last.source end)
	elseif last.kind == "created" and last.inst and last.inst.Parent then
		last.inst:Destroy()
	elseif last.kind == "deleted" and last.inst and last.parent then
		last.inst.Parent = last.parent
	elseif last.kind == "custom" and last.undo then pcall(last.undo)
	elseif last.kind == "props" and last.inst and last.inst.Parent then
		for key, value in pairs(last.values) do pcall(function() last.inst[key] = value end) end
	end
	builderSelected = nil
	refreshBuilder()
	showToast("Last builder action undone")
end)

local moveRow = bRow(28)
movePathBox = bInput(moveRow, "Move to path: Folder/Subfolder (root = project root)", 0.72, 0)
bBtn(moveRow, "Move", 0.28, 0.72, function()
	if not builderSelected or builderSelected == projectRoot or not inProject(builderSelected) then showToast("Select a project object") return end
	local dest = safePathFind(trim(movePathBox.Text))
	if not dest or not inProject(dest) or not (dest == projectRoot or dest:IsA("Folder") or dest:IsA("Model")) then showToast("Destination must be a project Folder or Model") return end
	if dest == builderSelected or dest:IsDescendantOf(builderSelected) then showToast("Cannot move an object into itself or its child") return end
	local inst, oldParent = builderSelected, builderSelected.Parent
	table.insert(undoStack, {kind = "props", inst = inst, values = {Parent = oldParent}})
	inst.Parent = dest
	movePathBox.Text = ""
	refreshBuilder()
	showToast("Moved inside project")
end, C.accent)

selectedLabel.LayoutOrder = bo()
local nameRow = bRow(28)
propertyNameBox = bInput(nameRow, "Object name", 0.72, 0)
bBtn(nameRow, "Rename", 0.28, 0.72, function()
	if not builderSelected or not inProject(builderSelected) then showToast("Select an object") return end
	local name = trim(propertyNameBox.Text)
	if name == "" then showToast("Name cannot be empty") return end
	table.insert(undoStack, {kind = "props", inst = builderSelected, values = {Name = builderSelected.Name}})
	builderSelected.Name = name
	refreshBuilder()
end, C.accent)
local posRow = bRow(28)
positionBox = bInput(posRow, "Position: X, Y, Z", 0.5, 0)
sizeBox = bInput(posRow, "Size: X, Y, Z", 0.5, 0.5)
local rotationRow = bRow(28)
rotationBox = bInput(rotationRow, "Rotation in degrees: X, Y, Z", 0.68, 0)
bBtn(rotationRow, "Zero rotation", 0.32, 0.68, function() rotationBox.Text = "0, 0, 0" end)
local partRow = bRow(28)
transparencyBox = bInput(partRow, "Transparency 0-1", 0.35, 0)
local anchoredBtn
anchoredBtn = bBtn(partRow, "Anchored: —", 0.30, 0.35, function()
	if not (builderSelected and builderSelected:IsA("BasePart")) then showToast("Select a Part") return end
	table.insert(undoStack, {kind = "props", inst = builderSelected, values = {Anchored = builderSelected.Anchored}})
	builderSelected.Anchored = not builderSelected.Anchored
	anchoredBtn.Text = "Anchored: " .. (builderSelected.Anchored and "ON" or "OFF")
end)
local collideBtn
collideBtn = bBtn(partRow, "Collide: —", 0.35, 0.65, function()
	if not (builderSelected and builderSelected:IsA("BasePart")) then showToast("Select a Part") return end
	table.insert(undoStack, {kind = "props", inst = builderSelected, values = {CanCollide = builderSelected.CanCollide}})
	builderSelected.CanCollide = not builderSelected.CanCollide
	collideBtn.Text = "Collide: " .. (builderSelected.CanCollide and "ON" or "OFF")
end)
local applyRow = bRow(28)
bBtn(applyRow, "Apply properties", 0.65, 0, function()
	if not builderSelected or not inProject(builderSelected) then showToast("Select an object") return end
	local inst = builderSelected
	local oldProps = {Name = inst.Name}
	if inst:IsA("BasePart") then
		oldProps.CFrame, oldProps.Size, oldProps.Transparency = inst.CFrame, inst.Size, inst.Transparency
		oldProps.Anchored, oldProps.CanCollide = inst.Anchored, inst.CanCollide
	end
	table.insert(undoStack, {kind = "props", inst = inst, values = oldProps})
	local newName = trim(propertyNameBox.Text)
	if newName ~= "" then pcall(function() inst.Name = newName end) end
	if inst:IsA("BasePart") then
		local pos = parseVector(positionBox.Text)
		local size = parseVector(sizeBox.Text)
		local tr = tonumber(transparencyBox.Text)
		local rot = parseVector(rotationBox.Text)
		if pos then inst.Position = pos end
		if rot then inst.CFrame = CFrame.new(inst.Position) * CFrame.Angles(math.rad(rot.X), math.rad(rot.Y), math.rad(rot.Z)) end
		if size and size.X > 0 and size.Y > 0 and size.Z > 0 then inst.Size = size end
		if tr then inst.Transparency = math.clamp(tr, 0, 1) end
	end
	refreshBuilder()
	showToast("Properties applied")
end, C.accent)
local resetProps = bBtn(applyRow, "Reset fields", 0.35, 0.65, function() refreshBuilder() end)

local scaleRow = bRow(28)
local scaleBox = bInput(scaleRow, "Model scale multiplier (e.g. 1.2)", 0.65, 0)
bBtn(scaleRow, "Scale model", 0.35, 0.65, function()
	if not builderSelected or not builderSelected:IsA("Model") or not inProject(builderSelected) then showToast("Select a Model") return end
	local factor = tonumber(scaleBox.Text)
	if not factor or factor < 0.05 or factor > 20 then showToast("Scale must be between 0.05 and 20") return end
	local ok, oldScale = pcall(function() return builderSelected:GetScale() end)
	if not ok then showToast("Model scaling unavailable") return end
	local inst = builderSelected
	pcall(function() table.insert(undoStack, {kind = "custom", undo = function() inst:ScaleTo(oldScale) end}) end)
	local scaled, err = pcall(function() inst:ScaleTo(oldScale * factor) end)
	if not scaled then showToast("Scale failed: " .. tostring(err)) else showToast("Model scaled") end
end, C.accent)

bLabel("SCRIPT SOURCE EDITOR • source access depends on the runtime", 18, C.accent, 11)
scriptEditor = box(buildScroll, "Select a Script to read or edit its source...", UDim2.new(1, -8, 0, 100), nil, true)
scriptEditor.LayoutOrder = bo()
scriptEditor.Font = Enum.Font.Code
scriptEditor.TextSize = 11
local sourceRow = bRow(28)
bBtn(sourceRow, "Read source", 0.5, 0, function()
	if not builderSelected then showToast("Select a script") return end
	local src, err = readLocalScriptSource(builderSelected)
	if not src then showToast(err) return end
	scriptEditor.Text = src
	showToast("Script source loaded")
end)
bBtn(sourceRow, "Save source", 0.5, 0.5, function()
	if not builderSelected or not (builderSelected:IsA("Script") or builderSelected:IsA("LocalScript") or builderSelected:IsA("ModuleScript")) then showToast("Select a script") return end
	local oldSource, readErr = readLocalScriptSource(builderSelected)
	local ok, err = pcall(function() builderSelected.Source = scriptEditor.Text end)
	if not ok then showToast("Source write blocked: " .. tostring(err):sub(1, 90)) return end
	if oldSource then table.insert(undoStack, {kind = "source", inst = builderSelected, source = oldSource}) end
	showToast("Source saved in this runtime")
end, C.accent)

bLabel("AI PROJECT BUILDER • describes changes as a reviewed action plan", 18, C.accent, 11)
local aiBuildInput = box(buildScroll, "Describe what to build or change in this project...", UDim2.new(1, -8, 0, 54), nil, true)
aiBuildInput.LayoutOrder = bo()
local planRow = bRow(30)
local planBtn = bBtn(planRow, "Generate AI plan", 0.55, 0, function() end, C.accent)
local applyPlanBtn = bBtn(planRow, "Apply plan (0)", 0.45, 0.55, function() end, C.good)
applyPlanBtn.Active = false
local planPreview = box(buildScroll, "AI plan preview will appear here. Review before applying.", UDim2.new(1, -8, 0, 90), nil, true)
planPreview.LayoutOrder = bo()
planPreview.TextEditable = false
local discardRow = bRow(26)
local discardPlanBtn = bBtn(discardRow, "Discard plan", 1, 0, function()
	stagedActions = nil
	planPreview.Text = "Plan discarded."
	applyPlanBtn.Text = "Apply plan (0)"
	applyPlanBtn.Active = false
	applyPlanBtn.AutoButtonColor = false
end)

local allowedClasses = {Part = true, WedgePart = true, SpawnLocation = true, Model = true, Folder = true, Script = true, LocalScript = true, ModuleScript = true, PointLight = true, Sound = true, Attachment = true, Decal = true, Texture = true, SpotLight = true, SurfaceLight = true, ParticleEmitter = true, Highlight = true}
local function applySafeProperties(inst, props, undoValues)
	if type(props) ~= "table" then return end
	local function remember(key)
		if undoValues[key] == nil then
			local ok, val = pcall(function() return inst[key] end)
			if ok then undoValues[key] = val end
		end
	end
	for key, value in pairs(props) do
		if key == "name" or key == "Name" then
			remember("Name"); if type(value) == "string" and #value > 0 and #value < 80 then inst.Name = value end
		elseif key == "position" or key == "Position" then
			if inst:IsA("BasePart") then local v = type(value) == "table" and Vector3.new(tonumber(value[1]) or 0, tonumber(value[2]) or 0, tonumber(value[3]) or 0) or parseVector(value); if v then remember("CFrame"); inst.Position = v end end
		elseif key == "rotation" or key == "Rotation" then
			if inst:IsA("BasePart") then local v = type(value) == "table" and Vector3.new(tonumber(value[1]) or 0, tonumber(value[2]) or 0, tonumber(value[3]) or 0) or parseVector(value); if v then remember("CFrame"); inst.CFrame = CFrame.new(inst.Position) * CFrame.Angles(math.rad(v.X), math.rad(v.Y), math.rad(v.Z)) end end
		elseif key == "size" or key == "Size" then
			if inst:IsA("BasePart") then local v = type(value) == "table" and Vector3.new(tonumber(value[1]) or 1, tonumber(value[2]) or 1, tonumber(value[3]) or 1) or parseVector(value); if v and v.X > 0 and v.Y > 0 and v.Z > 0 then remember("Size"); inst.Size = v end end
		elseif key == "anchored" or key == "Anchored" then
			if inst:IsA("BasePart") and type(value) == "boolean" then remember("Anchored"); inst.Anchored = value end
		elseif key == "canCollide" or key == "CanCollide" then
			if inst:IsA("BasePart") and type(value) == "boolean" then remember("CanCollide"); inst.CanCollide = value end
		elseif key == "transparency" or key == "Transparency" then
			if inst:IsA("BasePart") and tonumber(value) then remember("Transparency"); inst.Transparency = math.clamp(tonumber(value), 0, 1) end
		elseif key == "material" or key == "Material" then
			if inst:IsA("BasePart") and type(value) == "string" and Enum.Material[value] then remember("Material"); inst.Material = Enum.Material[value] end
		elseif key == "color" or key == "Color" then
			if type(value) == "table" then
				local color = Color3.fromRGB(math.clamp(tonumber(value[1]) or 255, 0, 255), math.clamp(tonumber(value[2]) or 255, 0, 255), math.clamp(tonumber(value[3]) or 255, 0, 255))
				if inst:IsA("BasePart") or inst:IsA("Light") or inst:IsA("Highlight") then remember("Color"); inst.Color = color
				elseif inst:IsA("ParticleEmitter") then remember("Color"); inst.Color = ColorSequence.new(color) end
			end
		elseif key == "brightness" or key == "Brightness" then
			if inst:IsA("Light") and tonumber(value) then remember("Brightness"); inst.Brightness = math.clamp(tonumber(value), 0, 100) end
		elseif key == "range" or key == "Range" then
			if inst:IsA("PointLight") or inst:IsA("SpotLight") or inst:IsA("SurfaceLight") then if tonumber(value) then remember("Range"); inst.Range = math.clamp(tonumber(value), 0, 60) end end
		elseif key == "enabled" or key == "Enabled" then
			if inst:IsA("Light") or inst:IsA("ParticleEmitter") or inst:IsA("Beam") or inst:IsA("Trail") or inst:IsA("Highlight") or inst:IsA("Script") or inst:IsA("LocalScript") then if type(value) == "boolean" then remember("Enabled"); inst.Enabled = value end end
		elseif key == "volume" or key == "Volume" then
			if inst:IsA("Sound") and tonumber(value) then remember("Volume"); inst.Volume = math.clamp(tonumber(value), 0, 10) end
		elseif key == "soundId" or key == "SoundId" then
			if inst:IsA("Sound") and type(value) == "string" then remember("SoundId"); inst.SoundId = value:sub(1, 200) end
		elseif key == "texture" or key == "Texture" then
			if inst:IsA("Decal") or inst:IsA("Texture") or inst:IsA("ParticleEmitter") then if type(value) == "string" then remember("Texture"); inst.Texture = value:sub(1, 200) end end
		elseif key == "source" or key == "Source" then
			if inst:IsA("LuaSourceContainer") and type(value) == "string" and #value <= 20000 then
				local old = readLocalScriptSource(inst)
				if old then undoValues.Source = old end
				local wrote, writeErr = pcall(function() inst.Source = value end)
				if not wrote then undoValues.__sourceError = tostring(writeErr) end
			end
		end
	end
end

local function runActionPlan(actions)
	if type(actions) ~= "table" or #actions == 0 or #actions > 20 then return false, "Plan must contain 1-20 actions" end
	local batchLog, done, failed = {}, 0, {}
	for i, a in ipairs(actions) do
		if type(a) ~= "table" then table.insert(failed, "Action " .. i .. ": invalid"); continue end
		local op = tostring(a.op or "")
		local target = safePathFind(a.target or "root")
		if op == "create" then
			local className = tostring(a.class or "")
			if not allowedClasses[className] then table.insert(failed, "Action " .. i .. ": class not allowed") continue end
			local obj
			local ok, err = pcall(function() obj = Instance.new(className) end)
			if not ok or not obj then table.insert(failed, "Action " .. i .. ": " .. tostring(err)); continue end
			obj.Name = (type(a.name) == "string" and a.name:sub(1, 80) ~= "") and a.name:sub(1, 80) or ("New" .. className)
			if obj:IsA("BasePart") then obj.Anchored = true end
			if obj:IsA("LuaSourceContainer") then pcall(function() obj.Enabled = false end) end
			local parent = safePathFind(a.parent or "root") or projectRoot
			if not inProject(parent) then parent = projectRoot end
			obj.Parent = parent
			local old = {}
			applySafeProperties(obj, a.properties, old)
			if old.__sourceError then table.insert(failed, "Action " .. i .. ": object created, but script source write was blocked") end
			table.insert(batchLog, {kind = "created", inst = obj})
			done += 1
		elseif op == "set" or op == "rename" then
			if not target or not inProject(target) then table.insert(failed, "Action " .. i .. ": target not found") continue end
			local props = a.properties or {}
			if op == "rename" then props = {Name = a.name} end
			local old = {}
			applySafeProperties(target, props, old)
			if old.__sourceError then table.insert(failed, "Action " .. i .. ": instance changed, but script source write was blocked") old.__sourceError = nil end
			if next(old) then table.insert(batchLog, {kind = "props", inst = target, values = old}) end
			done += 1
		elseif op == "scale" then
			local factor = tonumber(a.factor)
			if not target or not target:IsA("Model") or not inProject(target) or not factor or factor < 0.05 or factor > 20 then
				table.insert(failed, "Action " .. i .. ": invalid model scale target/factor")
			else
				local inst = target
				local okScale, oldScale = pcall(function() return inst:GetScale() end)
				if not okScale then table.insert(failed, "Action " .. i .. ": model scale unavailable")
				else
					local scaled, scaleErr = pcall(function() inst:ScaleTo(oldScale * factor) end)
					if scaled then table.insert(batchLog, {kind = "custom", undo = function() inst:ScaleTo(oldScale) end}); done += 1
					else table.insert(failed, "Action " .. i .. ": " .. tostring(scaleErr)) end
				end
			end
		elseif op == "move" then
			local dest = safePathFind(a.parent or "root")
			if not target or target == projectRoot or not inProject(target) or not dest or not inProject(dest) or not (dest == projectRoot or dest:IsA("Folder") or dest:IsA("Model")) or dest == target or dest:IsDescendantOf(target) then
				table.insert(failed, "Action " .. i .. ": invalid move path")
			else
				table.insert(batchLog, {kind = "props", inst = target, values = {Parent = target.Parent}})
				target.Parent = dest
				done += 1
			end
		elseif op == "duplicate" then
			if not target or not inProject(target) then table.insert(failed, "Action " .. i .. ": target not found") continue end
			local ok, clone = pcall(function() return target:Clone() end)
			if ok and clone then
				disableScriptsDeep(clone)
				clone.Name = (type(a.name) == "string" and a.name or target.Name .. " Copy"):sub(1, 80)
				clone.Parent = target.Parent
				table.insert(batchLog, {kind = "created", inst = clone}); done += 1
			else table.insert(failed, "Action " .. i .. ": duplicate failed") end
		elseif op == "delete" then
			if not target or target == projectRoot or not inProject(target) then table.insert(failed, "Action " .. i .. ": target missing or protected") continue end
			local parent = target.Parent
			local ok, clone = pcall(function() return target:Clone() end)
			if ok and clone then disableScriptsDeep(clone); table.insert(batchLog, {kind = "deleted", inst = clone, parent = parent}); target:Destroy(); done += 1 else table.insert(failed, "Action " .. i .. ": delete backup failed") end
		else
			table.insert(failed, "Action " .. i .. ": unsupported operation")
		end
	end
	if #batchLog > 0 then table.insert(undoStack, {kind = "batch", entries = batchLog}) end
	refreshBuilder()
	return true, tostring(done) .. " applied" .. (#failed > 0 and ("; " .. #failed .. " skipped: " .. table.concat(failed, " | ")) or "")
end

local function generateBuilderPlan()
	if busy then showToast("AI is busy") return end
	local promptText = trim(aiBuildInput.Text)
	if promptText == "" then showToast("Describe what you want built") return end
	if not db.set.gemKey or db.set.gemKey == "" then settingsPanel.Visible = true; showToast("Add your Gemini key in AI Settings"); return end
	planBtn.Text = "Planning..."
	planBtn.Active = false
	busy = true
	task.spawn(function()
		local sys = "You are a Roblox project builder planner. Return ONLY valid JSON with shape {\"summary\":string,\"actions\":[...]}. Never return Lua or arbitrary code. Allowed action schemas: {\"op\":\"create\",\"class\":\"Part|WedgePart|SpawnLocation|Model|Folder|Script|LocalScript|ModuleScript|PointLight|Sound|Attachment|Decal|Texture|SpotLight|SurfaceLight|ParticleEmitter|Highlight\",\"name\":string,\"parent\":relative/path,\"properties\":{\"position\":[x,y,z],\"size\":[x,y,z],\"anchored\":boolean,\"canCollide\":boolean,\"transparency\":number,\"material\":string,\"color\":[r,g,b],\"brightness\":number,\"range\":number,\"enabled\":boolean,\"volume\":number,\"soundId\":string,\"texture\":string,\"source\":string}}; {\"op\":\"set\",\"target\":relative/path,\"properties\":same safe property map}; {\"op\":\"rename\",\"target\":relative/path,\"name\":string}; {\"op\":\"scale\",\"target\":relative/path,\"factor\":number}; {\"op\":\"move\",\"target\":relative/path,\"parent\":relative/path}; {\"op\":\"duplicate\",\"target\":relative/path,\"name\":string}; {\"op\":\"delete\",\"target\":relative/path}. Paths start at project root; use root for the root. Maximum 20 actions. Keep scripts disabled and only create script source when specifically requested. Do not change or delete objects unless user explicitly requests it."
		local userPrompt = "PROJECT CONTEXT:\n" .. dumpProjectContext(projectRoot) .. "\n\nUSER REQUEST:\n" .. promptText .. "\n\nReturn JSON only."
		local model = (db.set.gemModel and db.set.gemModel ~= "") and db.set.gemModel or DEFAULT_MODEL
		local url = "https://generativelanguage.googleapis.com/v1beta/models/" .. model .. ":generateContent"
		local payload = HttpService:JSONEncode({system_instruction = {parts = {{text = sys}}}, contents = {{role = "user", parts = {{text = userPrompt}}}}, generationConfig = {responseMimeType = "application/json", temperature = 0.2}})
		local res = doRequest({Url = url, Method = "POST", Headers = { ["Content-Type"] = "application/json", ["x-goog-api-key"] = db.set.gemKey }, Body = payload})
		local raw = res and res.Body
		if not raw then busy = false; planBtn.Text = "Generate AI plan"; planBtn.Active = true; planPreview.Text = "AI request failed. Check executor HTTP access and your API key."; return end
		local okJ, data = pcall(HttpService.JSONDecode, HttpService, raw)
		local cand = okJ and data.candidates and data.candidates[1]
		local parts = cand and cand.content and cand.content.parts
		local response = ""
		if parts then for _, part in ipairs(parts) do if part.text then response = response .. part.text end end end
		if response == "" then
			busy = false
			planBtn.Text = "Generate AI plan"; planBtn.Active = true
			planPreview.Text = "AI returned no plan: " .. tostring(okJ and data.error and data.error.message or "empty response")
			return
		end
		response = response:gsub("^%s*```json", ""):gsub("^%s*```", ""):gsub("```%s*$", "")
		local okPlan, plan = pcall(HttpService.JSONDecode, HttpService, response)
		if not okPlan or type(plan) ~= "table" or type(plan.actions) ~= "table" or #plan.actions == 0 or #plan.actions > 20 then
			stagedActions = nil
			planPreview.Text = "Could not parse a valid action plan. AI response:\n" .. response:sub(1, 5000)
			applyPlanBtn.Text = "Apply plan (0)"; applyPlanBtn.Active = false
		else
			stagedActions = plan.actions
			planPreview.Text = tostring(plan.summary or "Review these proposed project changes") .. "\n\n" .. HttpService:JSONEncode(plan.actions)
			applyPlanBtn.Text = "Apply plan (" .. #stagedActions .. ")"
			applyPlanBtn.Active = true
			applyPlanBtn.AutoButtonColor = true
		end
		busy = false
		planBtn.Text = "Generate AI plan"
		planBtn.Active = true
	end)
end
planBtn.MouseButton1Click:Connect(generateBuilderPlan)
applyPlanBtn.MouseButton1Click:Connect(function()
	if not stagedActions then showToast("No reviewed plan") return end
	local ok, result = runActionPlan(stagedActions)
	if ok then
		planPreview.Text = "RESULT: " .. result .. "\n\nChanges are runtime-local. Use Undo to revert the last batch."
		stagedActions = nil
		applyPlanBtn.Text = "Apply plan (0)"
		applyPlanBtn.Active = false
		applyPlanBtn.AutoButtonColor = false
	else
		showToast(result)
	end
end)

-- Extend Undo for source edits and AI batches.
-- A separate source/AI undo control keeps the plan-discard control unobstructed.
local undoRow = bRow(26)
local undoAdvanced = bBtn(undoRow, "Undo source / AI batch", 1, 0, function()
	local last = table.remove(undoStack)
	if not last then showToast("Nothing to undo") return end
	if last.kind == "batch" then
		for i = #last.entries, 1, -1 do
			local entry = last.entries[i]
			if entry.kind == "created" and entry.inst and entry.inst.Parent then entry.inst:Destroy()
			elseif entry.kind == "deleted" and entry.inst and entry.parent then entry.inst.Parent = entry.parent
			elseif entry.kind == "props" and entry.inst and entry.inst.Parent then for key, value in pairs(entry.values) do pcall(function() entry.inst[key] = value end) end
			elseif entry.kind == "custom" and entry.undo then pcall(entry.undo)
			end
		end
	elseif last.kind == "source" and last.inst then
		local ok = pcall(function() last.inst.Source = last.source end)
		if not ok then showToast("Source restore blocked") end
	elseif last.kind == "created" and last.inst and last.inst.Parent then last.inst:Destroy()
	elseif last.kind == "deleted" and last.inst and last.parent then last.inst.Parent = last.parent
	elseif last.kind == "custom" and last.undo then pcall(last.undo)
	elseif last.kind == "props" and last.inst and last.inst.Parent then for key, value in pairs(last.values) do pcall(function() last.inst[key] = value end) end end
	refreshBuilder()
	showToast("Undo completed where permissions allowed")
end)

refreshBuilder()

end -- buildStudioBuilderPage
buildStudioBuilderPage()

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

local function buildPublishPage()
-- ===== PUBLISH PAGE (Open Cloud) =====
local pPub = newPage("Publish")
local pubScroll = vscroll(pPub, UDim2.new(1, -16, 1, -4), UDim2.fromOffset(8, 0))
new("UIListLayout", {Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder}, pubScroll)
local plo = 0
local function nxt() plo += 1 return plo end

local warn = label(pubScroll, "Experimental. Uploads an exported .rbxl/.rbxlx from your executor workspace folder to your place using an Open Cloud API key (Universe Places write permission). Studio Lite's own Publish page is the safest option. Never share this script after saving your key.", UDim2.new(1, -6, 0, 0), nil, C.sub, 11)
warn.AutomaticSize = Enum.AutomaticSize.Y
warn.LayoutOrder = nxt()

local function field(title, key, secret)
	local l = label(pubScroll, title, UDim2.new(1, -6, 0, 14), nil, C.sub, 11)
	l.LayoutOrder = nxt()
	local has = db.set[key] and db.set[key] ~= ""
	local b = box(pubScroll, (secret and has) and "Saved - type to replace" or title, UDim2.new(1, -6, 0, 30))
	b.LayoutOrder = nxt()
	if not secret then b.Text = db.set[key] or "" end
	b.FocusLost:Connect(function()
		local v = trim(b.Text)
		if secret then
			if v ~= "" then
				db.set[key] = v
				b.Text = ""
				b.PlaceholderText = "Saved - type to replace"
			end
		else
			db.set[key] = v
		end
		saveDB()
	end)
	return b
end
field("Open Cloud API key", "pubKey", true)
field("Universe ID", "uni", false)
field("Place ID", "place", false)
field("File name in executor workspace (e.g. game.rbxl)", "file", false)

local versionType = "Published"
local verBtn = btn(pubScroll, "Version type: Published", UDim2.new(1, -6, 0, 30), nil, C.card, 12)
verBtn.LayoutOrder = nxt()
verBtn.MouseButton1Click:Connect(function()
	versionType = (versionType == "Published") and "Saved" or "Published"
	verBtn.Text = "Version type: " .. versionType
end)
local pubBtn = btn(pubScroll, "Upload / Publish", UDim2.new(1, -6, 0, 34), nil, C.accent, 13)
pubBtn.LayoutOrder = nxt()
local pubResult = label(pubScroll, "", UDim2.new(1, -6, 0, 0), nil, C.text, 12)
pubResult.AutomaticSize = Enum.AutomaticSize.Y
pubResult.LayoutOrder = nxt()

pubBtn.MouseButton1Click:Connect(function()
	local s = db.set
	if not (s.pubKey and s.pubKey ~= "" and s.uni and s.uni ~= "" and s.place and s.place ~= "" and s.file and s.file ~= "") then
		pubResult.Text = "Fill in all four fields first."
		return
	end
	if not (readfile and isfile) then
		pubResult.Text = "Your executor doesn't support readfile."
		return
	end
	if not isfile(s.file) then
		pubResult.Text = "File not found in executor workspace: " .. s.file
		return
	end
	pubResult.Text = "Uploading..."
	task.spawn(function()
		local okR, data = pcall(readfile, s.file)
		if not okR or not data then
			pubResult.Text = "Couldn't read the file."
			return
		end
		local ctype = s.file:lower():match("%.rbxlx$") and "application/xml" or "application/octet-stream"
		local url = ("https://apis.roblox.com/universes/v1/%s/places/%s/versions?versionType=%s"):format(s.uni, s.place, versionType)
		local res = doRequest({
			Url = url, Method = "POST",
			Headers = {["x-api-key"] = s.pubKey, ["Content-Type"] = ctype},
			Body = data,
		})
		if not res then
			pubResult.Text = "Request failed (executor has no HTTP request function)."
			return
		end
		if res.StatusCode == 200 then
			local okJ, j = pcall(HttpService.JSONDecode, HttpService, res.Body or "{}")
			pubResult.Text = "Done! Version " .. tostring(okJ and j.versionNumber or "?") .. " (" .. versionType .. ")"
		else
			pubResult.Text = "Failed (HTTP " .. tostring(res.StatusCode) .. "): " .. tostring(res.Body or ""):sub(1, 200)
		end
	end)
end)

-- ===== Tabs =====
local TABS = {"Store", "Saved", "Explorer", "Builder", "AI", "Snippets", "Publish"}
local tabBtns = {}
local function showTab(name)
	for n, p in pairs(pages) do p.Visible = (n == name) end
	for n, b in pairs(tabBtns) do b.BackgroundColor3 = (n == name) and C.accent or C.card end
	if name == "Saved" then refreshSaved() end
	if name == "Explorer" then refreshExplorer() end
end
for i, n in ipairs(TABS) do
	local b = round(new("TextButton", {
		Size = UDim2.fromOffset(86, 28), BackgroundColor3 = C.card, Text = n, TextColor3 = C.text,
		Font = Enum.Font.GothamBold, TextSize = 12, LayoutOrder = i,
	}, tabBar), 14)
	tabBtns[n] = b
	b.MouseButton1Click:Connect(function() showTab(n) end)
end

end -- buildPublishPage
buildPublishPage()

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
refreshExplorer()
showTab("Store")
setCat(1)