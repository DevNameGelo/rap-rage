--// Rage Dump · standalone Dex + Remote logger (one script, no libraries)
--//
--// Tap the circle -> Start. It records until YOU press DONE (5 minutes or 24 hours, your choice).
--//   Start : writes the Dex (whole explorer) + decompiled client scripts to files, and begins logging
--//           remotes. Identical sub-trees / identical scripts are written only once.
--//   DONE  : stops, saves everything, copies the report to the clipboard.
--//
--// The remote log keeps each UNIQUE argument shape once (count + 3 real examples + return values),
--// plus a compact timeline (first 100 and last 100 calls of every remote). It also records, once per
--// second, your position / speed / camera, and logs deaths, ragdoll states, walk speed changes,
--// MoveTo targets, camera changes, proximity prompts and the Drop button, so I can line everything up.
--// Use the MARK button right before you do something (steal, drop...) so I can find it in the log.
--// Autosaves every 30 seconds, so a crash or kick loses at most 30 seconds.
--//
--// Files go to the RageDump/ folder of your executor workspace.
--// Your name / user id and other players' names are replaced inside the files.
--//
--// Client->server logging uses a __namecall hook (like any remote spy). If the game ever kicks you while
--// it runs, turn "Log client->server" OFF before Start; server->client logging needs no hook.
--// Calls made by the game show as "C->S", calls from another script you run show as "C->S(exec)".

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local GuiService = game:GetService("GuiService")
local ProximityPromptService = game:GetService("ProximityPromptService")

local LocalPlayer = Players.LocalPlayer

--==============================================================
-- single instance
--==============================================================

local Env = (getgenv and getgenv()) or _G
if Env.__RageDump then pcall(function() Env.__RageDump.Destroy() end) end

--==============================================================
-- settings
--==============================================================

local FOLDER = "RageDump"
local CFG = {
    Decompile = true,
    HookC2S = true,
    AutosaveEvery = 30,
    ExamplesPerShape = 3,
    TimelineFirst = 100,     -- first N calls of every remote are kept
    TimelineLast = 100,      -- and the last N (ring buffer)
    ArgChars = 400,
    LeafCap = 20,            -- identical-name leaf siblings printed per parent
    MaxScriptChars = 200000,
    MaxShapes = 6000,
}

local HAS = {
    writefile = typeof(writefile) == "function",
    appendfile = typeof(appendfile) == "function",
    makefolder = typeof(makefolder) == "function",
    isfolder = typeof(isfolder) == "function",
    setclipboard = typeof(setclipboard) == "function",
    decompile = typeof(decompile) == "function",
    hook = typeof(hookmetamethod) == "function" and typeof(getnamecallmethod) == "function",
    setnamecall = typeof(setnamecallmethod) == "function",
    checkcaller = typeof(checkcaller) == "function",
}

--==============================================================
-- state
--==============================================================

local Connections = {}
local Alive = true
local Running = false            -- between Start and DONE
local Capturing = false          -- remote logging on
local DoneRequested = false
local StopRequested = false      -- force stop of the Dex / script dump
local DexState = "waiting"
local DexFinished = true
local T0 = os.clock()
local RunStart = os.clock()

local Stamp = os.date("%Y%m%d_%H%M%S")
local DexPath = FOLDER .. "/Dex_" .. Stamp .. ".txt"
local ScriptsPath = FOLDER .. "/Scripts_" .. Stamp .. ".txt"
local RemotesPath = FOLDER .. "/Remotes_" .. Stamp .. ".txt"

local Stats = { DexNodes = 0, DexBytes = 0, Scripts = 0, ScriptsSkipped = 0, Events = 0 }
local StatusText = "Idle. Tap Start."
local LastReport = ""
local LastSaveAt = 0

local function Track(conn)
    if conn then table.insert(Connections, conn) end
    return conn
end

--==============================================================
-- privacy: hide your name / id in the files
--==============================================================

local function EscapePattern(s) return (tostring(s):gsub("%p", "%%%0")) end
local NamePatterns = {}
for _, n in ipairs({ LocalPlayer.Name, LocalPlayer.DisplayName }) do
    if #n >= 3 then table.insert(NamePatterns, EscapePattern(n)) end
end
local UidPattern = EscapePattern(tostring(LocalPlayer.UserId))

local function Scrub(text)
    for _, pat in ipairs(NamePatterns) do text = text:gsub(pat, "PLAYER") end
    text = text:gsub(UidPattern, "USERID")
    local i = 0
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer then
            i += 1
            if #plr.Name >= 3 then text = text:gsub(EscapePattern(plr.Name), "OTHER" .. i) end
            if #plr.DisplayName >= 3 and plr.DisplayName ~= plr.Name then
                text = text:gsub(EscapePattern(plr.DisplayName), "OTHER" .. i)
            end
        end
    end
    return text
end

--==============================================================
-- serializer
--==============================================================

local function PathOf(inst)
    local ok, p = pcall(function() return inst:GetFullName() end)
    return ok and p or tostring(inst)
end

local function SortedKeys(t)
    local keys = {}
    for k in pairs(t) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    return keys
end

local function Ser(v, depth, seen)
    depth = depth or 0
    local t = typeof(v)
    if t == "string" then
        local s = v
        if #s > 160 then s = s:sub(1, 160) .. "...(" .. #v .. ")" end
        return string.format("%q", s)
    elseif t == "number" then
        if v ~= v then return "nan" end
        if v == math.floor(v) and math.abs(v) < 1e15 then return string.format("%d", v) end
        return string.format("%.5g", v)
    elseif t == "boolean" or t == "nil" then
        return tostring(v)
    elseif t == "Instance" then
        return "<" .. v.ClassName .. ":" .. PathOf(v) .. ">"
    elseif t == "Vector3" then
        return string.format("V3(%.1f,%.1f,%.1f)", v.X, v.Y, v.Z)
    elseif t == "Vector2" then
        return string.format("V2(%.1f,%.1f)", v.X, v.Y)
    elseif t == "CFrame" then
        local p = v.Position
        return string.format("CF(%.1f,%.1f,%.1f)", p.X, p.Y, p.Z)
    elseif t == "Color3" then
        return string.format("C3(%d,%d,%d)", v.R * 255, v.G * 255, v.B * 255)
    elseif t == "UDim2" then
        return string.format("UD2(%.2f,%d,%.2f,%d)", v.X.Scale, v.X.Offset, v.Y.Scale, v.Y.Offset)
    elseif t == "EnumItem" then
        return tostring(v)
    elseif t == "table" then
        seen = seen or {}
        if depth >= 4 or seen[v] then return "{...}" end
        seen[v] = true
        local parts, n = {}, 0
        for _, k in ipairs(SortedKeys(v)) do
            n += 1
            if n > 25 then parts[#parts + 1] = "..." break end
            local key
            if type(k) == "string" and k:match("^[%a_][%w_]*$") then key = k else key = "[" .. Ser(k, depth + 1, seen) .. "]" end
            parts[#parts + 1] = key .. "=" .. Ser(v[k], depth + 1, seen)
        end
        seen[v] = nil
        return "{" .. table.concat(parts, ", ") .. "}"
    end
    return "<" .. t .. ">"
end

-- shape: types + short enum-like strings, so repeated calls collapse into one entry
local function Shape(v, depth)
    depth = depth or 0
    local t = typeof(v)
    if t == "string" then
        if #v <= 24 then return '"' .. (v:gsub("%d", "#")) .. '"' end
        return "str"
    elseif t == "number" then
        return "num"
    elseif t == "Instance" then
        return "Inst:" .. v.ClassName
    elseif t == "table" then
        if depth >= 4 then return "{...}" end
        local seenPair, pairsList = {}, {}
        local count = 0
        for k, val in pairs(v) do
            count += 1
            if count > 60 then break end
            local ks
            if type(k) == "string" then
                ks = (#k <= 24) and (k:gsub("%d", "#")) or "<key>"
            elseif type(k) == "number" then
                ks = "#"
            else
                ks = "<key>"
            end
            local pair = ks .. "=" .. Shape(val, depth + 1)
            if not seenPair[pair] then
                seenPair[pair] = true
                pairsList[#pairsList + 1] = pair
            end
        end
        table.sort(pairsList)
        if #pairsList > 14 then
            local extra = #pairsList - 14
            for i = #pairsList, 15, -1 do pairsList[i] = nil end
            pairsList[#pairsList + 1] = "+" .. extra .. " more"
        end
        return "{" .. table.concat(pairsList, ", ") .. "}"
    end
    return t
end

local function Truncate(s, n)
    if #s > n then return s:sub(1, n) .. "...(" .. #s .. ")" end
    return s
end

--==============================================================
-- files
--==============================================================

local function EnsureFolder()
    if not HAS.makefolder then return end
    pcall(function()
        if not (HAS.isfolder and isfolder(FOLDER)) then makefolder(FOLDER) end
    end)
end

local function MakeWriter(path, header)
    local buf, pending = {}, {}
    local w = { Bytes = 0 }
    if HAS.writefile then pcall(writefile, path, Scrub(header) .. "\n") end
    pending[1] = Scrub(header) .. "\n"

    function w.Flush()
        if #buf == 0 then return end
        local text = Scrub(table.concat(buf, "\n") .. "\n")
        buf = {}
        w.Bytes += #text
        if HAS.appendfile then
            pcall(appendfile, path, text)
        else
            pending[#pending + 1] = text
        end
    end

    function w.Add(line)
        buf[#buf + 1] = line
        if #buf >= 400 then w.Flush() end
    end

    function w.Close()
        w.Flush()
        if not HAS.appendfile and HAS.writefile then
            pcall(writefile, path, table.concat(pending))
        end
    end

    return w
end

--==============================================================
-- UI (circle + panel)
--==============================================================

local function New(class, props, parent)
    local inst = Instance.new(class)
    for k, v in pairs(props or {}) do inst[k] = v end
    if parent then inst.Parent = parent end
    return inst
end

local function Round(inst, radius)
    New("UICorner", { CornerRadius = radius or UDim.new(0, 10) }, inst)
end

local Gui = New("ScreenGui", { Name = "RageDump", ResetOnSpawn = false, DisplayOrder = 9999, IgnoreGuiInset = true })
do
    local ok = pcall(function() Gui.Parent = (gethui and gethui()) or game:GetService("CoreGui") end)
    if not ok or not Gui.Parent then Gui.Parent = LocalPlayer:WaitForChild("PlayerGui") end
end

local BG, PANEL, ACCENT, TEXT, MUTED = Color3.fromRGB(18, 14, 30), Color3.fromRGB(30, 24, 52),
    Color3.fromRGB(139, 92, 246), Color3.fromRGB(235, 232, 250), Color3.fromRGB(150, 144, 180)
local GREEN, RED = Color3.fromRGB(46, 110, 80), Color3.fromRGB(160, 60, 70)

local Circle = New("TextButton", {
    Name = "Circle", Size = UDim2.fromOffset(56, 56), Position = UDim2.new(0, 16, 0.5, -28),
    BackgroundColor3 = PANEL, Text = "RD", TextColor3 = TEXT, Font = Enum.Font.GothamBold, TextSize = 18,
    AutoButtonColor = false, ZIndex = 10,
}, Gui)
Round(Circle, UDim.new(1, 0))
local CircleStroke = New("UIStroke", { Color = ACCENT, Thickness = 2 }, Circle)

local VP = (workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize) or Vector2.new(800, 420)
local PanelH = math.min(560, VP.Y - 30)
local Panel = New("ScrollingFrame", {
    Name = "Panel", Size = UDim2.fromOffset(310, PanelH), AnchorPoint = Vector2.new(0, 0),
    Position = UDim2.fromOffset(math.max(0, (VP.X - 310) / 2), 15), BackgroundColor3 = BG, Visible = false, ZIndex = 9,
    CanvasSize = UDim2.new(0, 0, 0, 0), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 4,
    BorderSizePixel = 0,
}, Gui)
Round(Panel, UDim.new(0, 14))
New("UIStroke", { Color = ACCENT, Thickness = 1.5, Transparency = 0.2 }, Panel)
New("UIPadding", { PaddingTop = UDim.new(0, 10), PaddingBottom = UDim.new(0, 10), PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }, Panel)
New("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, Panel)

local order = 0
local function NextOrder() order += 1 return order end

local function Label(text, size, color, height, bold)
    return New("TextLabel", {
        Size = UDim2.new(1, 0, 0, height or 18), BackgroundTransparency = 1, Text = text, TextColor3 = color or TEXT,
        Font = bold and Enum.Font.GothamBold or Enum.Font.Gotham, TextSize = size or 13, TextXAlignment = Enum.TextXAlignment.Left,
        TextWrapped = true, LayoutOrder = NextOrder(), ZIndex = 11,
    }, Panel)
end

local function Button(text, color, callback)
    local b = New("TextButton", {
        Size = UDim2.new(1, 0, 0, 36), BackgroundColor3 = color or ACCENT, Text = text, TextColor3 = Color3.new(1, 1, 1),
        Font = Enum.Font.GothamBold, TextSize = 14, AutoButtonColor = true, LayoutOrder = NextOrder(), ZIndex = 11,
    }, Panel)
    Round(b, UDim.new(0, 8))
    b.Activated:Connect(callback)
    return b
end

-- title (drag the title to move the panel)
local TitleRow = New("Frame", { Size = UDim2.new(1, 0, 0, 28), BackgroundTransparency = 1, LayoutOrder = NextOrder(), ZIndex = 11 }, Panel)
New("TextLabel", {
    Size = UDim2.new(1, -34, 1, 0), BackgroundTransparency = 1, Text = "Rage Dump  (drag me)", TextColor3 = TEXT,
    Font = Enum.Font.GothamBold, TextSize = 17, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 12,
}, TitleRow)
local CloseBtn = New("TextButton", {
    Size = UDim2.fromOffset(28, 28), Position = UDim2.new(1, -28, 0, 0), BackgroundColor3 = PANEL, Text = "X",
    TextColor3 = TEXT, Font = Enum.Font.GothamBold, TextSize = 14, ZIndex = 12,
}, TitleRow)
Round(CloseBtn, UDim.new(0, 6))

local StatusLabel = Label(StatusText, 13, TEXT, 60)
local TimerLabel = Label("00:00:00", 30, ACCENT, 38, true)
TimerLabel.TextXAlignment = Enum.TextXAlignment.Center
local StatsLabel = Label("", 12, MUTED, 62)

local StartBtn
local function SetStatus(text)
    StatusText = text
    StatusLabel.Text = text
end

local function RenderStartButton()
    if not Running then
        StartBtn.Text = "START"
        StartBtn.BackgroundColor3 = GREEN
        CircleStroke.Color = ACCENT
    elseif DoneRequested then
        StartBtn.Text = "Force stop (skip rest of the Dex)"
        StartBtn.BackgroundColor3 = Color3.fromRGB(120, 90, 40)
    else
        StartBtn.Text = "DONE - save everything"
        StartBtn.BackgroundColor3 = RED
        CircleStroke.Color = Color3.fromRGB(230, 70, 80)
    end
end

StartBtn = Button("START", GREEN, function() end)   -- callback is set below, after Run exists

local function Toggle(text, default, onChange)
    local state = default
    local b
    local function render()
        b.Text = text .. ": " .. (state and "ON" or "OFF")
        b.BackgroundColor3 = state and GREEN or PANEL
    end
    b = New("TextButton", {
        Size = UDim2.new(1, 0, 0, 30), Text = "", TextColor3 = TEXT, Font = Enum.Font.GothamMedium, TextSize = 13,
        LayoutOrder = NextOrder(), ZIndex = 11,
    }, Panel)
    Round(b, UDim.new(0, 8))
    render()
    b.Activated:Connect(function()
        if Running then return end      -- these apply at Start
        state = not state
        render()
        onChange(state)
    end)
end

Toggle("Decompile scripts", CFG.Decompile, function(v) CFG.Decompile = v end)
Toggle("Log client->server (hook)", CFG.HookC2S, function(v) CFG.HookC2S = v end)

-- MARK: type a note, press Mark right before you do something
local MarkRow = New("Frame", { Size = UDim2.new(1, 0, 0, 32), BackgroundTransparency = 1, LayoutOrder = NextOrder(), ZIndex = 11 }, Panel)
local MarkBox = New("TextBox", {
    Size = UDim2.new(0.62, -4, 1, 0), BackgroundColor3 = PANEL, Text = "", PlaceholderText = "note: stole egg...",
    PlaceholderColor3 = MUTED, TextColor3 = TEXT, Font = Enum.Font.Gotham, TextSize = 12, ClearTextOnFocus = false, ZIndex = 12,
}, MarkRow)
Round(MarkBox, UDim.new(0, 6))
local MarkBtn = New("TextButton", {
    Size = UDim2.new(0.38, 0, 1, 0), Position = UDim2.new(0.62, 0, 0, 0), BackgroundColor3 = ACCENT, Text = "MARK",
    TextColor3 = Color3.new(1, 1, 1), Font = Enum.Font.GothamBold, TextSize = 13, ZIndex = 12,
}, MarkRow)
Round(MarkBtn, UDim.new(0, 6))

local SaveBtn = Button("Save snapshot now", PANEL, function() end)
local CopyBtn = Button("Copy report to clipboard", PANEL, function() end)

local Hint = New("TextLabel", {
    Size = UDim2.new(1, 0, 0, 56), BackgroundTransparency = 1, TextColor3 = MUTED, Font = Enum.Font.Gotham, TextSize = 11,
    TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = NextOrder(), ZIndex = 11,
    Text = "START records until you press DONE (5 minutes or 24 hours). The toggles apply at Start. Tap the circle to hide/show it, drag it to move. Files: RageDump/ in your executor workspace.",
}, Panel)

-- circle: tap = open/close panel, drag = move
do
    local dragging, moved, startInput, startCircle
    Circle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging, moved = true, false
            startInput = input.Position
            startCircle = Circle.AbsolutePosition
        end
    end)
    Track(UserInputService.InputChanged:Connect(function(input)
        if not dragging then return end
        if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseMovement then
            local delta = input.Position - startInput
            if delta.Magnitude > 8 then moved = true end
            if moved then
                local vp = Gui.AbsoluteSize
                Circle.Position = UDim2.fromOffset(math.clamp(startCircle.X + delta.X, 0, vp.X - 56), math.clamp(startCircle.Y + delta.Y, 0, vp.Y - 56))
            end
        end
    end))
    Track(UserInputService.InputEnded:Connect(function(input)
        if not dragging then return end
        if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = false
            if not moved then Panel.Visible = not Panel.Visible end
        end
    end))
end

-- panel: drag by the title
do
    local dragging, startInput, startPanel
    TitleRow.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging, startInput, startPanel = true, input.Position, Panel.AbsolutePosition
        end
    end)
    Track(UserInputService.InputChanged:Connect(function(input)
        if not dragging then return end
        if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseMovement then
            local delta = input.Position - startInput
            local vp = Gui.AbsoluteSize
            Panel.Position = UDim2.fromOffset(math.clamp(startPanel.X + delta.X, 0, vp.X - 310), math.clamp(startPanel.Y + delta.Y, 0, vp.Y - 60))
        end
    end))
    Track(UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
    end))
end
CloseBtn.Activated:Connect(function() Panel.Visible = false end)

--==============================================================
-- Dex dump
--==============================================================

local SigMemo = {}
local SigCount = 0

local function Hash(str)
    local h = 5381
    for i = 1, #str do h = (h * 33 + str:byte(i)) % 4294967291 end
    return h
end

local function Sig(inst)
    local m = SigMemo[inst]
    if m then return m end
    SigCount += 1
    if SigCount % 2500 == 0 then task.wait() end
    local h = Hash(inst.ClassName)
    for _, c in ipairs(inst:GetChildren()) do
        h = (h * 1000003 + Hash(c.Name) + Sig(c) * 7) % 4294967291
    end
    SigMemo[inst] = h
    return h
end

local function PropsOf(inst)
    local p = {}
    local function add(k, v) p[#p + 1] = k .. "=" .. v end

    pcall(function()
        if inst:IsA("BasePart") then
            add("Pos", Ser(inst.Position))
            add("Size", Ser(inst.Size))
            if inst.Anchored then add("Anch", "1") end
            if not inst.CanCollide then add("NoCol", "1") end
            if inst.Transparency > 0 then add("Tr", string.format("%.2f", inst.Transparency)) end
            if inst:IsA("MeshPart") and inst.MeshId ~= "" then add("Mesh", inst.MeshId) end
        elseif inst:IsA("Model") then
            local ok, cf = pcall(function() return inst:GetPivot() end)
            if ok then add("Pivot", Ser(cf)) end
            if inst.PrimaryPart then add("Primary", inst.PrimaryPart.Name) end
        elseif inst:IsA("ProximityPrompt") then
            add("Action", Ser(inst.ActionText)); add("Object", Ser(inst.ObjectText))
            add("Hold", tostring(inst.HoldDuration)); add("Dist", tostring(inst.MaxActivationDistance))
            add("On", tostring(inst.Enabled))
        elseif inst:IsA("ClickDetector") then
            add("Dist", tostring(inst.MaxActivationDistance))
        elseif inst:IsA("ValueBase") then
            add("Value", Ser(inst.Value))
        elseif inst:IsA("TextLabel") or inst:IsA("TextButton") or inst:IsA("TextBox") then
            add("Text", Ser(inst.Text)); add("Vis", tostring(inst.Visible))
        elseif inst:IsA("GuiObject") then
            add("Vis", tostring(inst.Visible))
        elseif inst:IsA("ScreenGui") then
            add("On", tostring(inst.Enabled))
        elseif inst:IsA("Sound") then
            add("SoundId", inst.SoundId)
        elseif inst:IsA("Animation") then
            add("AnimationId", inst.AnimationId)
        elseif inst:IsA("Decal") or inst:IsA("Texture") then
            add("Texture", inst.Texture)
        elseif inst:IsA("BaseScript") then
            add("Disabled", tostring(inst.Disabled))
        elseif inst:IsA("Attachment") then
            add("World", Ser(inst.WorldPosition))
        elseif inst:IsA("Humanoid") then
            add("WalkSpeed", tostring(inst.WalkSpeed)); add("Health", tostring(inst.Health))
        end
    end)

    local ok, attrs = pcall(function() return inst:GetAttributes() end)
    if ok and type(attrs) == "table" then
        local n = 0
        for _, k in ipairs(SortedKeys(attrs)) do
            n += 1
            if n > 24 then add("@...", "more") break end
            add("@" .. k, Truncate(Ser(attrs[k]), 90))
        end
    end

    local okT, tags = pcall(function() return game:GetService("CollectionService"):GetTags(inst) end)
    if okT and type(tags) == "table" and #tags > 0 then add("tags", table.concat(tags, "|")) end

    return table.concat(p, ", ")
end

local function IsOurGui(inst)
    return inst == Gui or inst:IsDescendantOf(Gui)
end

local function DumpNode(inst, depth, w)
    if Stats.DexNodes % 1500 == 0 then task.wait() end
    if not Alive or StopRequested then return end
    Stats.DexNodes += 1

    local line = string.rep("  ", depth) .. "[" .. inst.ClassName .. "] " .. inst.Name
    local props = PropsOf(inst)
    if props ~= "" then line = line .. "  {" .. props .. "}" end

    local kids = inst:GetChildren()
    if #kids == 0 or depth > 70 then
        w.Add(line)
        return
    end
    w.Add(line)

    local seenSig, leafCount, leafOmitted = {}, {}, {}
    for _, child in ipairs(kids) do
        if not IsOurGui(child) then
            local childKids = child:GetChildren()
            if #childKids == 0 then
                -- leaf: print, but cap identical Class+Name leaves per parent
                local key = child.ClassName .. "|" .. child.Name
                leafCount[key] = (leafCount[key] or 0) + 1
                if leafCount[key] <= CFG.LeafCap then
                    DumpNode(child, depth + 1, w)
                else
                    leafOmitted[key] = (leafOmitted[key] or 0) + 1
                end
            else
                local sg = Sig(child)
                if seenSig[sg] then
                    -- same structure as an earlier sibling: one line, no repeated subtree
                    local cl = string.rep("  ", depth + 1) .. "[" .. child.ClassName .. "] " .. child.Name
                    local cp = PropsOf(child)
                    if cp ~= "" then cl = cl .. "  {" .. cp .. "}" end
                    w.Add(cl .. "  (same subtree as an earlier sibling, " .. #childKids .. " children)")
                    Stats.DexNodes += 1
                else
                    seenSig[sg] = true
                    DumpNode(child, depth + 1, w)
                end
            end
        end
    end
    for key, n in pairs(leafOmitted) do
        w.Add(string.rep("  ", depth + 1) .. "(+" .. n .. " more [" .. key:gsub("|", "] ") .. " omitted: identical name)")
    end
end

local function DumpDex()
    local info = {}
    local okInfo, product = pcall(function() return MarketplaceService:GetProductInfo(game.PlaceId) end)
    local gameName = okInfo and product and product.Name or "?"
    local exec = (identifyexecutor and select(1, identifyexecutor())) or "?"
    table.insert(info, "# Rage Dump - Dex")
    table.insert(info, "# Game: " .. tostring(gameName) .. "  PlaceId=" .. game.PlaceId .. "  GameId=" .. game.GameId)
    table.insert(info, "# Executor: " .. tostring(exec) .. "   Date: " .. os.date("%Y-%m-%d %H:%M:%S"))
    table.insert(info, "# Identical sub-trees are written once ('same subtree as an earlier sibling').")

    local w = MakeWriter(DexPath, table.concat(info, "\n"))

    -- remotes list first (small, very useful)
    w.Add("")
    w.Add("======== REMOTES (ReplicatedStorage) ========")
    local nRemotes = 0
    for _, d in ipairs(ReplicatedStorage:GetDescendants()) do
        local c = d.ClassName
        if c == "RemoteEvent" or c == "RemoteFunction" or c == "UnreliableRemoteEvent" or c == "BindableEvent" or c == "BindableFunction" then
            nRemotes += 1
            w.Add("[" .. c .. "] " .. PathOf(d))
        end
        if nRemotes % 400 == 0 then task.wait() end
    end

    local roots = {
        { "Workspace", workspace },
        { "ReplicatedStorage", ReplicatedStorage },
        { "ReplicatedFirst", game:GetService("ReplicatedFirst") },
        { "StarterGui", game:GetService("StarterGui") },
        { "StarterPack", game:GetService("StarterPack") },
        { "StarterPlayer", game:GetService("StarterPlayer") },
        { "Lighting", game:GetService("Lighting") },
        { "SoundService", game:GetService("SoundService") },
        { "Teams", game:GetService("Teams") },
        { "Players (you only)", LocalPlayer },
    }

    for _, pair in ipairs(roots) do
        if not Alive then break end
        w.Add("")
        w.Add("========================================================================")
        w.Add("== TREE: " .. pair[1])
        w.Add("========================================================================")
        DexState = "writing " .. pair[1] .. " (" .. Stats.DexNodes .. " nodes)"
        local ok, err = pcall(DumpNode, pair[2], 0, w)
        if not ok then w.Add("!! error while dumping " .. pair[1] .. ": " .. tostring(err)) end
    end

    w.Close()
    Stats.DexBytes = w.Bytes
end

--==============================================================
-- script sources (optional)
--==============================================================

local function SafeDecompile(scriptInst)
    local done, result = false, nil
    task.spawn(function()
        local ok, src = pcall(decompile, scriptInst)
        result = ok and src or nil
        done = true
    end)
    local t0 = os.clock()
    while not done and os.clock() - t0 < 10 do task.wait(0.05) end
    return result
end

local SKIP_ANCESTORS = { PlayerModule = true, RbxCharacterSounds = true, PlayerScriptsLoader = true, ChatScript = true, BubbleChat = true }

local function DumpScripts()
    if not CFG.Decompile then return end
    if not HAS.decompile then
        DexState = "scripts skipped (no decompile)"
        return
    end

    local header = "# Rage Dump - decompiled client scripts\n# Duplicates (same source) are skipped."
    local w = MakeWriter(ScriptsPath, header)
    local seen = {}
    local containers = { ReplicatedStorage, game:GetService("ReplicatedFirst"), game:GetService("StarterGui"),
        game:GetService("StarterPack"), game:GetService("StarterPlayer") }
    pcall(function() table.insert(containers, LocalPlayer:FindFirstChild("PlayerScripts")) end)
    pcall(function() table.insert(containers, LocalPlayer:FindFirstChild("PlayerGui")) end)
    table.insert(containers, workspace)

    local list = {}
    for _, root in ipairs(containers) do
        if root then
            for _, d in ipairs(root:GetDescendants()) do
                if (d.ClassName == "LocalScript" or d.ClassName == "ModuleScript") and not IsOurGui(d) then
                    local skip = false
                    local cur = d.Parent
                    while cur and cur ~= game do
                        if SKIP_ANCESTORS[cur.Name] then skip = true break end
                        cur = cur.Parent
                    end
                    if not skip then list[#list + 1] = d end
                end
            end
            task.wait()
        end
    end

    for i, s in ipairs(list) do
        if not Alive or StopRequested then break end
        DexState = string.format("decompiling scripts %d / %d", i, #list)
        local src = SafeDecompile(s)
        if src and #src > 0 then
            local h = Hash(src) .. ":" .. #src
            if seen[h] then
                Stats.ScriptsSkipped += 1
            elseif #src > CFG.MaxScriptChars then
                Stats.ScriptsSkipped += 1
                w.Add("\n--=== [" .. s.ClassName .. "] " .. PathOf(s) .. "  (skipped: " .. #src .. " chars)")
            else
                seen[h] = true
                Stats.Scripts += 1
                w.Add("\n--=== [" .. s.ClassName .. "] " .. PathOf(s) .. "  (" .. #src .. " chars)")
                w.Add(src)
            end
        else
            Stats.ScriptsSkipped += 1
        end
    end
    w.Close()
end

--==============================================================
-- remote capture
--==============================================================

local Shapes = {}              -- key -> entry
local ShapeCount = 0
local Totals = {}              -- "name|dir" -> count
local Tl = {}                  -- name -> { first = {}, ring = {}, i = 0, n = 0 }
local Samples = {}
local SampleEvery, SampleTick = 1, 0
local EventFirst, EventRing, EventRingI = {}, {}, 0
local Markers = {}
local RemoteInfo = {}          -- path -> class
local Connected = setmetatable({}, { __mode = "k" })
local StartState, EndState = {}, {}
local EVENT_FIRST, EVENT_RING = 1500, 2500

local function RingList(ring, idx, cap)
    local out = {}
    if #ring < cap then
        for i = 1, #ring do out[#out + 1] = ring[i] end
    else
        for i = idx + 1, cap do out[#out + 1] = ring[i] end
        for i = 1, idx do out[#out + 1] = ring[i] end
    end
    return out
end

local function RemoteName(remote)
    local p = PathOf(remote)
    return p:match("Networking%.(.+)$") or p:match("^ReplicatedStorage%.(.+)$") or p
end

local function IsRemoteClass(c)
    return c == "RemoteEvent" or c == "RemoteFunction" or c == "UnreliableRemoteEvent"
end

local function Now() return os.clock() - T0 end

local function AddEvent(text)
    local line = string.format("%10.2f %s", Now(), text)
    if #EventFirst < EVENT_FIRST then
        EventFirst[#EventFirst + 1] = line
    else
        EventRingI = EventRingI % EVENT_RING + 1
        EventRing[EventRingI] = line
    end
end

local function PackText(packed)
    local parts = {}
    for i = 1, packed.n do parts[i] = Ser(packed[i], 0) end
    return table.concat(parts, ", ")
end

local function Record(dir, remote, method, args, results)
    if not Capturing then return end
    local okClass, cls = pcall(function() return remote.ClassName end)
    if not okClass or not IsRemoteClass(cls) then return end

    Stats.Events += 1
    local name = RemoteName(remote)
    local totalKey = name .. "|" .. dir
    Totals[totalKey] = (Totals[totalKey] or 0) + 1

    local okShape, sig = pcall(function()
        local parts = {}
        for i = 1, args.n do parts[i] = Shape(args[i], 0) end
        return table.concat(parts, ", ")
    end)
    if not okShape then sig = "?" end
    if #sig > 700 then sig = sig:sub(1, 700) .. "..." end

    local key = totalKey .. "|" .. sig
    local entry = Shapes[key]
    if not entry then
        if ShapeCount >= CFG.MaxShapes then return end
        ShapeCount += 1
        entry = { Name = name, Dir = dir, Sig = sig, Count = 0, First = Now(), Last = Now(), Examples = {}, Results = {} }
        Shapes[key] = entry
    end
    entry.Count += 1
    entry.Last = Now()

    local okText, text = pcall(PackText, args)
    if not okText then text = "<unserializable>" end
    local resText
    if results then
        local okR, rt = pcall(PackText, results)
        resText = okR and rt or "?"
    end

    if #entry.Examples < CFG.ExamplesPerShape then
        entry.Examples[#entry.Examples + 1] = string.format("t=%.2f  (%s)", Now(), Truncate(text, CFG.ArgChars))
        if resText and #entry.Results < CFG.ExamplesPerShape then
            entry.Results[#entry.Results + 1] = Truncate(resText, 200)
        end
    end

    -- timeline: first N + last N calls of every remote (ring buffer)
    local slot = Tl[name]
    if not slot then
        slot = { first = {}, ring = {}, i = 0, n = 0 }
        Tl[name] = slot
    end
    slot.n += 1
    local line = string.format("%10.2f %s %s (%s)%s", Now(), dir, name, Truncate(text, 220),
        resText and ("  -> " .. Truncate(resText, 80)) or "")
    if #slot.first < CFG.TimelineFirst then
        slot.first[#slot.first + 1] = line
    else
        slot.i = slot.i % CFG.TimelineLast + 1
        slot.ring[slot.i] = line
    end
end

local function Listen(remote)
    if Connected[remote] then return end
    local c = remote.ClassName
    if not IsRemoteClass(c) then return end
    Connected[remote] = true
    RemoteInfo[PathOf(remote)] = c
    if c == "RemoteEvent" or c == "UnreliableRemoteEvent" then
        Track(remote.OnClientEvent:Connect(function(...)
            Record("S->C", remote, "OnClientEvent", table.pack(...), nil)
        end))
    end
end

local HookInstalled = false
local function InstallHook()
    if HookInstalled or not HAS.hook then return end
    HookInstalled = true
    local old
    old = hookmetamethod(game, "__namecall", function(self, ...)
        local method = getnamecallmethod()
        if Capturing and CFG.HookC2S and (method == "FireServer" or method == "InvokeServer") then
            -- calls made by the game are "C->S"; calls made by an executor script are "C->S(exec)"
            local dir = (HAS.checkcaller and checkcaller()) and "C->S(exec)" or "C->S"
            local args = table.pack(...)
            if method == "InvokeServer" then
                if HAS.setnamecall then setnamecallmethod(method) end
                local results = table.pack(old(self, ...))
                task.defer(Record, dir, self, method, args, results)
                return table.unpack(results, 1, results.n)
            end
            task.defer(Record, dir, self, method, args, nil)
            if HAS.setnamecall then setnamecallmethod(method) end
        end
        return old(self, ...)
    end)
end

local function PlayerState()
    local out = {}
    local ls = LocalPlayer:FindFirstChild("leaderstats")
    if ls then
        for _, v in ipairs(ls:GetChildren()) do
            if v:IsA("ValueBase") then out[#out + 1] = "leaderstats." .. v.Name .. " = " .. Ser(v.Value) end
        end
    end
    local okA, attrs = pcall(function() return LocalPlayer:GetAttributes() end)
    if okA and type(attrs) == "table" then
        for _, k in ipairs(SortedKeys(attrs)) do out[#out + 1] = "@" .. k .. " = " .. Truncate(Ser(attrs[k]), 80) end
    end
    local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
    if hum then
        out[#out + 1] = string.format("Humanoid WalkSpeed=%.1f JumpPower=%.1f Health=%.0f", hum.WalkSpeed, hum.JumpPower, hum.Health)
    end
    return out
end

local function WatchCharacter(char)
    local hum = char:WaitForChild("Humanoid", 10)
    local root = char:WaitForChild("HumanoidRootPart", 10)
    if not hum or not root then return end

    local function where()
        local p = root.Position
        return string.format("(%d,%d,%d)", p.X, p.Y, p.Z)
    end

    AddEvent("CHARACTER spawned " .. where() .. " WalkSpeed=" .. hum.WalkSpeed)
    Track(hum.Died:Connect(function() AddEvent("DIED at " .. where()) end))
    Track(hum.StateChanged:Connect(function(_, new)
        if new == Enum.HumanoidStateType.Ragdoll or new == Enum.HumanoidStateType.FallingDown
            or new == Enum.HumanoidStateType.Physics or new == Enum.HumanoidStateType.Dead
            or new == Enum.HumanoidStateType.PlatformStanding then
            AddEvent("STATE " .. tostring(new) .. " at " .. where())
        end
    end))
    Track(hum:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
        AddEvent("WalkSpeed -> " .. string.format("%.1f", hum.WalkSpeed))
    end))
    Track(hum:GetPropertyChangedSignal("PlatformStand"):Connect(function()
        AddEvent("PlatformStand -> " .. tostring(hum.PlatformStand))
    end))

    -- MoveTo targets (shows how a walking script moves you)
    local lastPoint, lastAt = nil, 0
    Track(hum:GetPropertyChangedSignal("WalkToPoint"):Connect(function()
        local p = hum.WalkToPoint
        if os.clock() - lastAt > 1 and (not lastPoint or (p - lastPoint).Magnitude > 5) then
            lastPoint, lastAt = p, os.clock()
            AddEvent(string.format("MoveTo -> (%d,%d,%d)", p.X, p.Y, p.Z))
        end
    end))
    Track(hum.MoveToFinished:Connect(function(reached)
        AddEvent("MoveToFinished reached=" .. tostring(reached) .. " at " .. where())
    end))
end

local function WatchDropGui()
    task.spawn(function()
        local pg = LocalPlayer:FindFirstChild("PlayerGui") or LocalPlayer:WaitForChild("PlayerGui", 10)
        local gui = pg and pg:WaitForChild("DropHeldEgg", 30)
        if not gui then return end
        local btn = gui:WaitForChild("Button", 10)
        Track(gui:GetPropertyChangedSignal("Enabled"):Connect(function()
            AddEvent("DropHeldEgg.Enabled -> " .. tostring(gui.Enabled))
        end))
        if btn then
            Track(btn:GetPropertyChangedSignal("Visible"):Connect(function()
                AddEvent("DropHeldEgg.Button.Visible -> " .. tostring(btn.Visible))
            end))
        end
    end)
end

local function WatchCamera()
    local cam = workspace.CurrentCamera
    if not cam then return end
    local function log()
        local subject = cam.CameraSubject
        AddEvent(string.format("CAMERA type=%s subject=%s", tostring(cam.CameraType), subject and PathOf(subject) or "nil"))
    end
    Track(cam:GetPropertyChangedSignal("CameraType"):Connect(log))
    Track(cam:GetPropertyChangedSignal("CameraSubject"):Connect(log))
end

local CaptureWired = false
local function StartCapture()
    Capturing = true
    if CaptureWired then return end
    CaptureWired = true

    for _, d in ipairs(ReplicatedStorage:GetDescendants()) do
        if IsRemoteClass(d.ClassName) then Listen(d) end
    end
    Track(ReplicatedStorage.DescendantAdded:Connect(function(d)
        if IsRemoteClass(d.ClassName) then Listen(d) end
    end))

    if CFG.HookC2S then
        if HAS.hook then InstallHook() else AddEvent("NOTE: executor has no hookmetamethod; client->server not logged") end
    end

    if LocalPlayer.Character then task.spawn(WatchCharacter, LocalPlayer.Character) end
    Track(LocalPlayer.CharacterAdded:Connect(function(c) task.spawn(WatchCharacter, c) end))
    WatchDropGui()
    WatchCamera()
    Track(workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(WatchCamera))

    Track(ProximityPromptService.PromptTriggered:Connect(function(prompt, plr)
        if Capturing and plr == LocalPlayer then
            AddEvent(string.format("PROMPT triggered %s action=%s", PathOf(prompt), tostring(prompt.ActionText)))
        end
    end))
    Track(ProximityPromptService.PromptButtonHoldBegan:Connect(function(prompt)
        if Capturing then AddEvent(string.format("PROMPT hold began %s", PathOf(prompt))) end
    end))
end

--==============================================================
-- report
--==============================================================

local function BuildReport(final)
    local out = {}
    local function add(s) out[#out + 1] = s end

    add("# Rage Dump - Remote report" .. (final and "" or " (snapshot)"))
    add(string.format("# Game PlaceId=%d  Date=%s  Recorded=%.0fs  Events=%d  UniqueShapes=%d",
        game.PlaceId, os.date("%Y-%m-%d %H:%M:%S"), Now(), Stats.Events, ShapeCount))
    add("# Client->server logging: " .. ((CFG.HookC2S and HAS.hook) and "ON (hook)" or "OFF"))
    add("# Dex file: " .. DexPath .. "   Scripts file: " .. ScriptsPath)
    add("")

    add("======== PLAYER STATE ========")
    add("-- at start:")
    for _, l in ipairs(StartState) do add("   " .. l) end
    add("-- now / at end:")
    for _, l in ipairs(final and EndState or PlayerState()) do add("   " .. l) end
    add("")

    add("======== MARKERS (your MARK presses) ========")
    for _, l in ipairs(Markers) do add(l) end
    add("")

    add("======== REMOTE LIST (from ReplicatedStorage) ========")
    local paths = {}
    for pth in pairs(RemoteInfo) do paths[#paths + 1] = pth end
    table.sort(paths)
    for _, pth in ipairs(paths) do add("[" .. RemoteInfo[pth] .. "] " .. pth) end
    add("")

    add("======== TOTALS (calls per remote and direction) ========")
    local tkeys = {}
    for k in pairs(Totals) do tkeys[#tkeys + 1] = k end
    table.sort(tkeys, function(a, b) return Totals[a] > Totals[b] end)
    for _, k in ipairs(tkeys) do add(string.format("%6d  %s", Totals[k], (k:gsub("|", "  ")))) end
    add("")

    add("======== UNIQUE SHAPES (duplicates collapsed; examples are real calls) ========")
    local entries = {}
    for _, e in pairs(Shapes) do entries[#entries + 1] = e end
    table.sort(entries, function(a, b)
        if a.Name ~= b.Name then return a.Name < b.Name end
        return a.Count > b.Count
    end)
    for _, e in ipairs(entries) do
        add(string.format("[%s] %s   x%d   first=%.1fs last=%.1fs", e.Dir, e.Name, e.Count, e.First, e.Last))
        add("   shape: " .. e.Sig)
        for i, ex in ipairs(e.Examples) do
            add("   ex" .. i .. ": " .. ex)
            if e.Results[i] then add("        -> " .. e.Results[i]) end
        end
    end
    add("")

    add("======== EVENTS (deaths, ragdoll/state, walk speed, MoveTo, camera, prompts, Drop button) ========")
    for _, line in ipairs(EventFirst) do add(line) end
    if #EventRing > 0 then
        add("   ... (older events in between were dropped to save memory) ...")
        for _, line in ipairs(RingList(EventRing, EventRingI, EVENT_RING)) do add(line) end
    end
    add("")

    add("======== TIMELINE (first " .. CFG.TimelineFirst .. " + last " .. CFG.TimelineLast .. " calls of each remote, time order) ========")
    local lines = {}
    for _, slot in pairs(Tl) do
        for _, l in ipairs(slot.first) do lines[#lines + 1] = l end
        for _, l in ipairs(RingList(slot.ring, slot.i, CFG.TimelineLast)) do lines[#lines + 1] = l end
    end
    table.sort(lines)
    for _, l in ipairs(lines) do add(l) end
    add("")

    add("======== POSITION (seconds,x,y,z,walkspeed,real speed,camX,camY,camZ; sampled every " .. SampleEvery .. "s) ========")
    for _, line in ipairs(Samples) do add(line) end

    return Scrub(table.concat(out, "\n") .. "\n")
end

local function SaveReport(final)
    local text = BuildReport(final)
    LastReport = text
    LastSaveAt = os.clock()
    if HAS.writefile then pcall(writefile, RemotesPath, text) end
    return text
end

local function CopyToClipboard(text)
    if not HAS.setclipboard then return false, "no setclipboard" end
    local ok = pcall(setclipboard, text)
    if ok then return true end
    -- too big for the clipboard: copy the compact part only
    local cut = text:find("======== TIMELINE", 1, true)
    local compact = cut and text:sub(1, cut - 1) or text:sub(1, 600000)
    ok = pcall(setclipboard, compact)
    return ok, "copied the compact part only (the full report is in the file)"
end

--==============================================================
-- run
--==============================================================

local function FmtHMS(sec)
    sec = math.max(0, math.floor(sec))
    return string.format("%02d:%02d:%02d", sec // 3600, (sec % 3600) // 60, sec % 60)
end

local function UpdateStats()
    local mb = collectgarbage("count") / 1024
    StatsLabel.Text = string.format(
        "Dex nodes: %d   Scripts: %d (+%d skipped)\nRemote events: %d   Unique shapes: %d\nMemory used: %.0f MB   Last autosave: %s",
        Stats.DexNodes, Stats.Scripts, Stats.ScriptsSkipped, Stats.Events, ShapeCount, mb,
        LastSaveAt > 0 and (FmtHMS(os.clock() - LastSaveAt) .. " ago") or "-")
end

local function ResetData()
    Stamp = os.date("%Y%m%d_%H%M%S")
    DexPath = FOLDER .. "/Dex_" .. Stamp .. ".txt"
    ScriptsPath = FOLDER .. "/Scripts_" .. Stamp .. ".txt"
    RemotesPath = FOLDER .. "/Remotes_" .. Stamp .. ".txt"
    table.clear(Shapes); table.clear(Totals); table.clear(Tl)
    table.clear(Samples); table.clear(EventFirst); table.clear(EventRing); table.clear(Markers)
    table.clear(SigMemo)
    EventRingI, ShapeCount, SigCount, LastReport, LastSaveAt = 0, 0, 0, "", 0
    SampleEvery, SampleTick = 1, 0
    Stats.DexNodes, Stats.DexBytes, Stats.Scripts, Stats.ScriptsSkipped, Stats.Events = 0, 0, 0, 0, 0
end

local function Sample()
    SampleTick += 1
    if SampleTick % SampleEvery ~= 0 then return end
    local char = LocalPlayer.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not root then return end
    local p = root.Position
    local cam = workspace.CurrentCamera
    local cp = cam and cam.CFrame.Position or Vector3.zero
    Samples[#Samples + 1] = string.format("%d,%d,%d,%d,%d,%d,%d,%d,%d", Now(), p.X, p.Y, p.Z,
        hum and hum.WalkSpeed or 0, root.AssemblyLinearVelocity.Magnitude, cp.X, cp.Y, cp.Z)
    if #Samples >= 3000 then            -- long runs: keep every other sample, sample half as often
        local kept = {}
        for i = 1, #Samples, 2 do kept[#kept + 1] = Samples[i] end
        Samples = kept
        SampleEvery *= 2
    end
end

local function Run()
    if Running then return end
    Running = true
    DoneRequested, StopRequested = false, false
    T0, RunStart = os.clock(), os.clock()
    ResetData()
    EnsureFolder()
    RenderStartButton()

    if not HAS.writefile then
        SetStatus("Your executor has no writefile: only the clipboard copy will work.")
    end

    StartState = PlayerState()
    StartCapture()          -- remote logging starts immediately

    -- the Dex + scripts are written in the background while the remotes keep recording
    DexFinished = false
    DexState = "starting"
    task.spawn(function()
        local ok, err = pcall(function()
            DumpDex()
            if not StopRequested then DumpScripts() end
        end)
        if not ok then
            DexState = "error: " .. tostring(err)
        elseif StopRequested then
            DexState = "stopped early"
        else
            DexState = "saved"
        end
        DexFinished = true
    end)

    local lastSave = os.clock()
    while Alive and not DoneRequested do
        task.wait(1)
        TimerLabel.Text = FmtHMS(os.clock() - RunStart)
        Sample()
        SetStatus("Recording remotes. Dex: " .. DexState .. ". Press DONE when you have enough.")
        UpdateStats()

        if os.clock() - lastSave >= CFG.AutosaveEvery then
            lastSave = os.clock()
            SaveReport(false)
        end
    end

    -- DONE pressed
    Capturing = false
    EndState = PlayerState()
    TimerLabel.Text = "SAVING"
    RenderStartButton()

    while Alive and not DexFinished and not StopRequested do
        SetStatus("Finishing the Dex files (" .. DexState .. "). Press Force stop to skip the rest.")
        UpdateStats()
        task.wait(0.5)
    end
    if not DexFinished then task.wait(1) end

    local text = SaveReport(true)
    local copied, note = CopyToClipboard(text)
    UpdateStats()
    TimerLabel.Text = "DONE " .. FmtHMS(os.clock() - RunStart)
    SetStatus(string.format("Saved.\n%s\n%s\n%s\nClipboard: %s", DexPath,
        (CFG.Decompile and HAS.decompile) and ScriptsPath or "(no scripts file)", RemotesPath,
        copied and (note or "report copied") or ("not copied (" .. tostring(note) .. ")")))

    Running = false
    RenderStartButton()
end

StartBtn.Activated:Connect(function()
    if not Running then
        task.spawn(function()
            local ok, err = pcall(Run)
            if not ok then
                Running, Capturing = false, false
                RenderStartButton()
                SetStatus("Error: " .. tostring(err))
            end
        end)
    elseif not DoneRequested then
        DoneRequested = true
        RenderStartButton()
        SetStatus("Stopping and saving...")
    else
        StopRequested = true
    end
end)

MarkBtn.Activated:Connect(function()
    if not Running then SetStatus("Press START first, then MARK.") return end
    local note = MarkBox.Text ~= "" and MarkBox.Text or "mark"
    local p = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    local pos = p and string.format(" at (%d,%d,%d)", p.Position.X, p.Position.Y, p.Position.Z) or ""
    local line = string.format("%10.2f MARK: %s%s", Now(), note, pos)
    if #Markers < 500 then Markers[#Markers + 1] = line end
    AddEvent("MARK: " .. note .. pos)
    MarkBtn.Text = "MARKED"
    task.delay(0.8, function() MarkBtn.Text = "MARK" end)
end)

SaveBtn.Activated:Connect(function()
    if not Running then SetStatus("Nothing to save yet. Press START first.") return end
    SaveReport(false)
    UpdateStats()
    SetStatus("Snapshot saved to " .. RemotesPath)
end)

CopyBtn.Activated:Connect(function()
    local text = LastReport ~= "" and LastReport or BuildReport(false)
    local ok, note = CopyToClipboard(text)
    SetStatus(ok and ("Copied. " .. (note or "")) or ("Could not copy: " .. tostring(note)))
end)

UpdateStats()
RenderStartButton()

--==============================================================
-- cleanup
--==============================================================

Env.__RageDump = {
    Destroy = function()
        Alive = false
        Capturing = false
        StopRequested = true
        for _, c in ipairs(Connections) do pcall(function() c:Disconnect() end) end
        table.clear(Connections)
        pcall(function() Gui:Destroy() end)
    end,
}