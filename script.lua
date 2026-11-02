
--[[
    OpenRouter Agent  |  glass chat UI + tool calling + remote spy + stoppable scripts
    Run it, tap the key button, paste your OpenRouter key, save.
]]

local Config = {
    ApiKey = "", -- set from the UI (key button)
    Model = "nvidia/nemotron-3.5-lightning:free", -- change in the UI if the ID differs
    Fallback = "nvidia/nemotron-3-nano-30b-a3b:free", -- used once if the main model returns 403/404
    Endpoint = "https://openrouter.ai/api/v1/chat/completions",
    Temperature = 0.4,
    MaxTokens = 2048,
    MaxToolSteps = 16,
    MaxToolOutput = 12000,
    MaxHistory = 40,
    Typewriter = true,
}

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local CoreGui = game:GetService("CoreGui")
local CollectionService = game:GetService("CollectionService")

local LocalPlayer = Players.LocalPlayer
local httpRequest = (syn and syn.request) or (http and http.request) or http_request or request
local isMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
local genv = (getgenv and getgenv()) or _G

-- saved settings (key + model)
local SAVE = "OpenRouterAgent_settings.json"
pcall(function()
    if isfile and readfile and isfile(SAVE) then
        local d = HttpService:JSONDecode(readfile(SAVE))
        if type(d.key) == "string" then Config.ApiKey = d.key end
        if type(d.model) == "string" and d.model ~= "" then Config.Model = d.model end
    end
end)
local function saveSettings()
    pcall(function()
        if writefile then writefile(SAVE, HttpService:JSONEncode({ key = Config.ApiKey, model = Config.Model })) end
    end)
end

------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------
local function fullName(inst)
    local ok, n = pcall(inst.GetFullName, inst)
    return ok and n or inst.Name
end
local function path(inst) return "game." .. fullName(inst) end

local function clip(s)
    s = tostring(s)
    if #s > Config.MaxToolOutput then
        return s:sub(1, Config.MaxToolOutput) .. "\n...[truncated " .. (#s - Config.MaxToolOutput) .. " chars]"
    end
    return s
end

local function ser(v, d)
    d = d or 0
    local t = typeof(v)
    if t == "string" then
        local s = v:sub(1, 200):gsub("[\r\n]", " ")
        return '"' .. s .. '"' .. (#v > 200 and "…" or "")
    elseif t == "Instance" then
        return path(v)
    elseif t == "table" then
        if d >= 3 then return "{...}" end
        local parts, n = {}, 0
        for k, val in pairs(v) do
            n += 1
            if n > 12 then parts[#parts + 1] = "..." break end
            local key = type(k) == "number" and "" or (tostring(k) .. "=")
            parts[#parts + 1] = key .. ser(val, d + 1)
        end
        return "{" .. table.concat(parts, ", ") .. "}"
    elseif t == "Vector3" then
        return string.format("Vector3.new(%g, %g, %g)", v.X, v.Y, v.Z)
    elseif t == "Vector2" then
        return string.format("Vector2.new(%g, %g)", v.X, v.Y)
    elseif t == "CFrame" then
        local p = v.Position
        return string.format("CFrame.new(%g, %g, %g)", p.X, p.Y, p.Z)
    elseif t == "Color3" then
        return string.format("Color3.fromRGB(%d, %d, %d)", v.R * 255, v.G * 255, v.B * 255)
    end
    return tostring(v)
end

local function child(cur, seg)
    local c = cur:FindFirstChild(seg)
    if c then return c end
    if cur == game then
        local ok, svc = pcall(game.GetService, game, seg)
        if ok and svc then return svc end
    end
    local l = seg:lower()
    if cur == Players and l == "localplayer" then return LocalPlayer end
    if cur == LocalPlayer and l == "character" then return LocalPlayer.Character end
    for _, x in ipairs(cur:GetChildren()) do
        if x.Name:lower() == l then return x end
    end
end

local function resolve(p)
    if type(p) ~= "string" or p == "" then return game end
    local cur = game
    local first = true
    for seg in p:gmatch("[^%.]+") do
        if not (first and seg == "game") then
            local nxt = child(cur, seg)
            if not nxt then return nil, "not found: '" .. seg .. "' under " .. path(cur) end
            cur = nxt
        end
        first = false
    end
    return cur
end

------------------------------------------------------------------
-- Remote spy (outgoing FireServer/InvokeServer + incoming OnClientEvent)
------------------------------------------------------------------
local onSpyChange = function() end

local Spy = genv.__GA_Spy
if not Spy then
    Spy = { on = false, log = {}, hooked = false, conns = {}, max = 400, t0 = os.clock(), watched = setmetatable({}, { __mode = "k" }) }
    genv.__GA_Spy = Spy
end

local function spyLog(dir, remote, method, args)
    local parts = {}
    for i = 1, args.n do parts[i] = ser(args[i]) end
    local rest
    if dir == "out" then
        rest = "→ server  " .. path(remote) .. ":" .. method .. "(" .. table.concat(parts, ", ") .. ")"
    else
        rest = "← client  " .. path(remote) .. ".OnClientEvent(" .. table.concat(parts, ", ") .. ")"
    end
    local last = Spy.log[#Spy.log]
    if last and last.key == rest then
        last.n += 1
        return
    end
    Spy.log[#Spy.log + 1] = { t = os.clock() - Spy.t0, key = rest, n = 1 }
    if #Spy.log > Spy.max then table.remove(Spy.log, 1) end
end
Spy.record = spyLog

local function installHook()
    if Spy.hooked then return true end
    if not (hookmetamethod and getnamecallmethod) then return false end
    local old
    local wrap = newcclosure or function(f) return f end
    local ok = pcall(function()
        old = hookmetamethod(game, "__namecall", wrap(function(self, ...)
            local method = getnamecallmethod()
            if Spy.on and (method == "FireServer" or method == "InvokeServer") and typeof(self) == "Instance" and not (checkcaller and checkcaller()) then
                local args = table.pack(...)
                local target = self
                task.defer(function() pcall(Spy.record, "out", target, method, args) end)
            end
            return old(self, ...)
        end))
    end)
    if ok then Spy.hooked = true end
    return ok
end

local function watch(r)
    if Spy.watched[r] then return end
    if r:IsA("RemoteEvent") or r:IsA("UnreliableRemoteEvent") then
        Spy.watched[r] = true
        Spy.conns[#Spy.conns + 1] = r.OnClientEvent:Connect(function(...)
            if Spy.on then Spy.record("in", r, "OnClientEvent", table.pack(...)) end
        end)
    end
end

local function startSpy()
    local hooked = installHook()
    Spy.on = true
    Spy.t0 = os.clock()
    Spy.record = spyLog
    for _, d in ipairs(game:GetDescendants()) do pcall(watch, d) end
    if not Spy.added then
        Spy.added = game.DescendantAdded:Connect(function(d) if Spy.on then pcall(watch, d) end end)
    end
    onSpyChange()
    return "remote spy ON. Outgoing FireServer/InvokeServer: " .. (hooked and "captured" or "NOT available (executor has no hookmetamethod)") .. ". Incoming OnClientEvent: captured. Ask the user to do the action in-game, then call get_remote_log."
end

local function stopSpy()
    Spy.on = false
    onSpyChange()
    return "remote spy OFF (" .. #Spy.log .. " events kept)"
end

------------------------------------------------------------------
-- Script runner (run + stop/undo)
------------------------------------------------------------------
local onScriptEvent = function() end
local Running, nextId = {}, 0

local function stopScript(id)
    local rec = Running[id]
    if not rec then return false, "no script with id " .. tostring(id) end
    if rec.stopped then return false, "script #" .. id .. " already stopped" end
    rec.stopped = true
    for _, c in ipairs(rec.conns) do pcall(function() c:Disconnect() end) end
    for _, th in ipairs(rec.threads) do pcall(task.cancel, th) end
    for i = #rec.cleanups, 1, -1 do pcall(rec.cleanups[i]) end
    for i = #rec.instances, 1, -1 do pcall(function() rec.instances[i]:Destroy() end) end
    rec.state = "stopped"
    onScriptEvent("stop", rec)
    return true
end

local function runCode(code, label)
    local fn, cerr = loadstring(code)
    if not fn then return nil, "compile error: " .. tostring(cerr) end
    nextId += 1
    local rec = { id = nextId, name = label or ("script " .. nextId), conns = {}, threads = {}, cleanups = {}, instances = {}, logs = {}, state = "running" }
    Running[rec.id] = rec

    local function log(...)
        local t = table.pack(...)
        for i = 1, t.n do t[i] = tostring(t[i]) end
        rec.logs[#rec.logs + 1] = table.concat(t, " ")
        if #rec.logs > 80 then table.remove(rec.logs, 1) end
    end
    local function trackThread(th) rec.threads[#rec.threads + 1] = th return th end
    local env = {
        print = log,
        warn = function(...) log("[warn]", ...) end,
        cleanup = function(f) if type(f) == "function" then rec.cleanups[#rec.cleanups + 1] = f end end,
        track = function(x)
            local t = typeof(x)
            if t == "RBXScriptConnection" then rec.conns[#rec.conns + 1] = x
            elseif t == "Instance" then rec.instances[#rec.instances + 1] = x
            elseif t == "function" then rec.cleanups[#rec.cleanups + 1] = x
            elseif t == "thread" then rec.threads[#rec.threads + 1] = x end
            return x
        end,
        task = setmetatable({
            spawn = function(f, ...) return trackThread(task.spawn(f, ...)) end,
            delay = function(t, f, ...) return trackThread(task.delay(t, f, ...)) end,
            defer = function(f, ...) return trackThread(task.defer(f, ...)) end,
        }, { __index = task }),
        Instance = setmetatable({
            new = function(...)
                local o = Instance.new(...)
                rec.instances[#rec.instances + 1] = o
                return o
            end,
        }, { __index = Instance }),
    }
    local okEnv = pcall(function()
        setfenv(fn, setmetatable(env, { __index = getfenv(fn) }))
    end)

    onScriptEvent("start", rec)
    local done, ok, res = false, false, nil
    trackThread(task.spawn(function()
        ok, res = pcall(fn)
        done = true
        if not ok then
            rec.state = "error"
            log("[error]", tostring(res))
            onScriptEvent("error", rec, tostring(res))
        end
    end))
    if not done then task.wait(0.35) end

    local out
    if done and ok then
        out = "script #" .. rec.id .. " ran OK and finished its main chunk. Anything it created stays active until stop_script(" .. rec.id .. ")."
        if res ~= nil then out ..= "\nreturned: " .. tostring(res) end
    elseif done then
        out = "script #" .. rec.id .. " ERROR: " .. tostring(res)
    else
        out = "script #" .. rec.id .. " is running in the background (loop or waiting). Use stop_script(" .. rec.id .. ") to stop and undo it."
    end
    if not okEnv then out ..= "\n(note: executor has no setfenv, cleanup()/track() helpers were unavailable)" end
    if #rec.logs > 0 then out ..= "\noutput:\n" .. table.concat(rec.logs, "\n") end
    return rec, out
end

------------------------------------------------------------------
-- Tools
------------------------------------------------------------------
local Tools = {}

local function defaultProps(inst)
    local p = { "Name", "ClassName", "Parent" }
    local function add(...) for _, n in ipairs({ ... }) do p[#p + 1] = n end end
    if inst:IsA("BasePart") then add("Position", "Size", "Anchored", "CanCollide", "Transparency", "Color", "Material") end
    if inst:IsA("Humanoid") then add("WalkSpeed", "JumpPower", "JumpHeight", "UseJumpPower", "Health", "MaxHealth", "HipHeight") end
    if inst:IsA("GuiObject") then add("Position", "Size", "Visible", "BackgroundTransparency", "ZIndex") end
    if inst:IsA("TextLabel") or inst:IsA("TextButton") or inst:IsA("TextBox") then add("Text") end
    if inst:IsA("ValueBase") then add("Value") end
    if inst:IsA("Model") then add("PrimaryPart") end
    if inst:IsA("ProximityPrompt") then add("ActionText", "HoldDuration", "MaxActivationDistance", "Enabled") end
    if inst:IsA("ClickDetector") then add("MaxActivationDistance") end
    if inst:IsA("LocalScript") or inst:IsA("Script") then add("Disabled") end
    return p
end

local function readProps(inst, names)
    local out = {}
    for _, n in ipairs(names) do
        local ok, v = pcall(function() return inst[n] end)
        if not ok and gethiddenproperty then
            local ok2, v2 = pcall(gethiddenproperty, inst, n)
            if ok2 then ok, v = true, v2 end
        end
        if ok then out[#out + 1] = n .. " = " .. ser(v) end
    end
    return out
end

Tools.overview = function()
    local out = { "PlaceId " .. game.PlaceId .. " | JobId " .. tostring(game.JobId):sub(1, 8) }
    for _, name in ipairs({ "Workspace", "ReplicatedStorage", "ReplicatedFirst", "StarterGui", "StarterPack", "StarterPlayer", "Lighting", "SoundService", "Players" }) do
        local ok, svc = pcall(game.GetService, game, name)
        if ok and svc then
            out[#out + 1] = name .. ": " .. #svc:GetChildren() .. " children, " .. #svc:GetDescendants() .. " descendants"
        end
    end
    local remotes, scripts = 0, 0
    for _, d in ipairs(game:GetDescendants()) do
        if d:IsA("RemoteEvent") or d:IsA("RemoteFunction") or d:IsA("UnreliableRemoteEvent") then remotes += 1
        elseif d:IsA("LocalScript") or d:IsA("ModuleScript") then scripts += 1 end
    end
    out[#out + 1] = "remotes visible: " .. remotes .. " | local/module scripts visible: " .. scripts
    out[#out + 1] = "executor: decompile=" .. tostring(decompile ~= nil) .. " hookmetamethod=" .. tostring(hookmetamethod ~= nil) .. " setclipboard=" .. tostring(setclipboard ~= nil)
    return table.concat(out, "\n")
end

Tools.explore = function(a)
    local root, err = resolve(a.path)
    if not root then return err end
    local maxDepth = math.clamp(tonumber(a.depth) or 1, 1, 6)
    local lines, count, capped = {}, 0, false
    local function walk(inst, d)
        for _, c in ipairs(inst:GetChildren()) do
            if count >= 300 then capped = true return end
            count += 1
            local n = #c:GetChildren()
            lines[#lines + 1] = string.rep("  ", d - 1) .. c.Name .. " [" .. c.ClassName .. "]" .. (n > 0 and (" (" .. n .. ")") or "")
            if d < maxDepth then walk(c, d + 1) end
        end
    end
    walk(root, 1)
    return path(root) .. " [" .. root.ClassName .. "]\n" .. (#lines > 0 and table.concat(lines, "\n") or "(no children)") .. (capped and "\n...(capped at 300, narrow the path)" or "")
end

Tools.find = function(a)
    local root = resolve(a.root) or game
    local q = tostring(a.query or ""):lower()
    local cls = a.className
    local out = {}
    for _, d in ipairs(root:GetDescendants()) do
        if (q == "" or d.Name:lower():find(q, 1, true)) and (not cls or d:IsA(cls)) then
            out[#out + 1] = path(d) .. " [" .. d.ClassName .. "]"
            if #out >= 80 then break end
        end
    end
    return #out > 0 and table.concat(out, "\n") or "no matches"
end

Tools.inspect = function(a)
    local inst, err = resolve(a.path)
    if not inst then return err end
    local out = { path(inst) .. " [" .. inst.ClassName .. "]", "children: " .. #inst:GetChildren() .. ", descendants: " .. #inst:GetDescendants() }
    local attrs = {}
    for k, v in pairs(inst:GetAttributes()) do attrs[#attrs + 1] = k .. "=" .. ser(v) end
    if #attrs > 0 then out[#out + 1] = "attributes: " .. table.concat(attrs, ", ") end
    local tags = CollectionService:GetTags(inst)
    if #tags > 0 then out[#out + 1] = "tags: " .. table.concat(tags, ", ") end
    for _, l in ipairs(readProps(inst, defaultProps(inst))) do out[#out + 1] = l end
    return table.concat(out, "\n")
end

Tools.get_properties = function(a)
    local inst, err = resolve(a.path)
    if not inst then return err end
    local names = a.names
    if type(names) ~= "table" or #names == 0 then names = defaultProps(inst) end
    return table.concat(readProps(inst, names), "\n")
end

Tools.list_remotes = function(a)
    local root = resolve(a.root) or game
    local out = {}
    for _, d in ipairs(root:GetDescendants()) do
        if d:IsA("RemoteEvent") or d:IsA("RemoteFunction") or d:IsA("UnreliableRemoteEvent") or d:IsA("BindableEvent") or d:IsA("BindableFunction") then
            out[#out + 1] = path(d) .. " [" .. d.ClassName .. "]"
            if #out >= 250 then break end
        end
    end
    return #out > 0 and table.concat(out, "\n") or "no remotes visible"
end

Tools.list_scripts = function(a)
    local root = resolve(a.root) or game
    local out = {}
    for _, d in ipairs(root:GetDescendants()) do
        if d:IsA("LocalScript") or d:IsA("ModuleScript") then
            out[#out + 1] = path(d) .. " [" .. d.ClassName .. "]"
            if #out >= 250 then break end
        end
    end
    return #out > 0 and table.concat(out, "\n") or "no scripts visible"
end

Tools.read_script = function(a)
    local s, err = resolve(a.path)
    if not s then return err end
    if decompile then
        local ok, src = pcall(decompile, s)
        if ok and src and src ~= "" then return clip(src) end
    end
    local ok, src = pcall(function() return s.Source end)
    if ok and src and src ~= "" then return clip(src) end
    return "could not read source (no decompiler or protected)"
end

Tools.player_info = function()
    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    local tools = {}
    for _, t in ipairs(LocalPlayer.Backpack:GetChildren()) do tools[#tools + 1] = t.Name end
    return table.concat({
        "Player: " .. LocalPlayer.Name .. " (UserId " .. LocalPlayer.UserId .. ")",
        "PlaceId: " .. game.PlaceId,
        "Character: " .. (char and char.Name or "none"),
        hum and ("WalkSpeed " .. hum.WalkSpeed .. " | JumpPower " .. hum.JumpPower .. " | JumpHeight " .. hum.JumpHeight .. " | Health " .. hum.Health .. "/" .. hum.MaxHealth) or "No humanoid",
        hrp and ("Position: " .. ser(hrp.Position)) or "",
        "Backpack: " .. (#tools > 0 and table.concat(tools, ", ") or "empty"),
    }, "\n")
end

Tools.spy_start = function() return startSpy() end
Tools.spy_stop = function() return stopSpy() end
Tools.clear_remote_log = function() Spy.log = {} return "remote log cleared" end

Tools.get_remote_log = function(a)
    local f = tostring(a.filter or ""):lower()
    local limit = math.clamp(tonumber(a.limit) or 40, 1, 150)
    local out = {}
    for i = #Spy.log, 1, -1 do
        local e = Spy.log[i]
        if f == "" or e.key:lower():find(f, 1, true) then
            table.insert(out, 1, string.format("[%.1fs] %s%s", e.t, e.key, e.n > 1 and (" (x" .. e.n .. ")") or ""))
            if #out >= limit then break end
        end
    end
    local head = "spy " .. (Spy.on and "ON" or "OFF") .. ", " .. #Spy.log .. " events stored"
    if #out == 0 then
        return head .. "\nno matching events" .. (Spy.on and "" or " (call spy_start first, then have the user trigger the action)")
    end
    return head .. "\n" .. table.concat(out, "\n")
end

Tools.run_lua = function(a)
    local rec, out = runCode(tostring(a.code or ""), a.name)
    return out
end

Tools.list_running = function()
    local out = {}
    for id = 1, nextId do
        local r = Running[id]
        if r then
            local tail = {}
            for i = math.max(1, #r.logs - 4), #r.logs do tail[#tail + 1] = r.logs[i] end
            out[#out + 1] = "#" .. id .. " " .. r.name .. " [" .. r.state .. "]" .. (#tail > 0 and ("\n  " .. table.concat(tail, "\n  ")) or "")
        end
    end
    return #out > 0 and table.concat(out, "\n") or "no scripts have been run"
end

Tools.stop_script = function(a)
    local id = tonumber(a.id)
    if not id then return "id required" end
    local ok, msg = stopScript(id)
    return ok and ("script #" .. id .. " stopped and cleaned up") or msg
end

local S = "string"
local function fn(name, desc, props, required)
    return {
        type = "function",
        ["function"] = {
            name = name,
            description = desc,
            parameters = {
                type = "object",
                properties = props or { reason = { type = S, description = "optional, can be left out" } },
                required = required,
            },
        },
    }
end

local ToolSpecs = {
    fn("overview", "Quick summary of the game: services, counts, remotes, scripts, executor features."),
    fn("explore", "Dex-style tree of an instance's children. Paths: Workspace, ReplicatedStorage.Remotes, Players.LocalPlayer.PlayerGui, Players.LocalPlayer.Character. Empty path = game.", { path = { type = S }, depth = { type = "integer", description = "1-6, default 1" } }),
    fn("find", "Search descendants by partial name; className may be a base class like BasePart or GuiButton.", { query = { type = S }, className = { type = S }, root = { type = S } }, { "query" }),
    fn("inspect", "Full details of one instance: class, counts, attributes, tags and key properties.", { path = { type = S } }, { "path" }),
    fn("get_properties", "Read specific properties of an instance (omit names for sensible defaults).", { path = { type = S }, names = { type = "array", items = { type = S } } }, { "path" }),
    fn("list_remotes", "List all RemoteEvent/RemoteFunction/Bindable instances visible to the client.", { root = { type = S } }),
    fn("list_scripts", "List LocalScripts and ModuleScripts under a root.", { root = { type = S } }),
    fn("read_script", "Decompile/read a script's source.", { path = { type = S } }, { "path" }),
    fn("player_info", "Local player, character, humanoid stats, backpack."),
    fn("spy_start", "Start capturing remote traffic: outgoing FireServer/InvokeServer and incoming OnClientEvent."),
    fn("spy_stop", "Stop capturing remote traffic."),
    fn("get_remote_log", "Read captured remote events as ready-to-use Lua calls. Repeated identical calls are collapsed (xN).", { filter = { type = S, description = "substring of remote path/args" }, limit = { type = "integer" } }),
    fn("clear_remote_log", "Clear the captured remote log."),
    fn("run_lua", "Execute Lua on the client. The script can use print(), cleanup(function() ... end) to register undo code, and track(connection_or_instance). Instances it creates and task.spawn threads are tracked automatically. Returns a script id.", { code = { type = S }, name = { type = S, description = "short label" } }, { "code" }),
    fn("list_running", "List scripts started with run_lua and their recent output."),
    fn("stop_script", "Stop a running script and undo it (runs cleanup functions, disconnects, destroys what it created).", { id = { type = "integer" } }, { "id" }),
}

local SYSTEM = [[You are OpenRouter Agent, an assistant running inside a Roblox client as a Lua script. You chat with the user and you create Lua (Luau) scripts for Roblox. Within that scope you do whatever the user asks.

SCOPE
- You only do two things: chat, and create Lua/Luau scripts (UIs, tools, helpers, game modifications written in Lua).
- If the user asks you to create anything that is not a Lua script (Python, JavaScript, C#, websites, images, essays, documents, anything unrelated), deny it. Say briefly that you are only for Lua scripting and chatting, and offer a Lua alternative if one exists.
- Normal conversation is always fine.

HOW TO WORK
- Inspect before building. Use overview, explore, find, inspect, list_remotes, list_scripts and read_script to learn the real names and structure. Never invent paths or remote names, check them first.
- To learn what a remote sends: call spy_start, ask the user to perform the action in game, then call get_remote_log (use filter to narrow). The log shows calls as ready-to-use Lua.
- Build with run_lua. Read the result, fix errors and retry. If a script keeps running, it has an id; use list_running to check it and stop_script to stop and undo it.
- Inside run_lua code you have print(), cleanup(fn) and track(x). Always register cleanup(function() ... end) that restores anything you changed (for example the original WalkSpeed) and disconnects connections, so stopping the script fully undoes it. Instances you create are destroyed automatically on stop.
- For UIs: modern glass look (UICorner, UIStroke, semi-transparent dark background, gradients), draggable, works on mobile and PC, parented to gethui() or CoreGui.
- After a script works, include the final script in your reply inside a ```lua block so the user can copy it.
- Keep chat replies short. Do not paste huge tool outputs back. Be honest about errors and limits (for example when the executor lacks a function).
- Reply in the same language the user writes in.]]

------------------------------------------------------------------
-- OpenRouter API
------------------------------------------------------------------
local history = {}
local setTitle -- defined in the UI section below

local function trimHistory()
    while #history > Config.MaxHistory do
        local nextUser
        for i = 2, #history do
            if history[i].role == "user" then nextUser = i break end
        end
        if not nextUser then break end
        for _ = 1, nextUser - 1 do table.remove(history, 1) end
    end
end

local function buildBody(model)
    local msgs = { { role = "system", content = SYSTEM } }
    for _, m in ipairs(history) do msgs[#msgs + 1] = m end
    return HttpService:JSONEncode({
        model = model,
        messages = msgs,
        tools = ToolSpecs,
        tool_choice = "auto",
        temperature = Config.Temperature,
        max_tokens = Config.MaxTokens,
    })
end

local function callAI()
    if not httpRequest then return nil, "No HTTP request function in this executor." end
    local model = Config.Model
    local fellBack = false
    local lastErr = "request failed"

    for attempt = 1, 6 do
        local ok, res = pcall(httpRequest, {
            Url = Config.Endpoint,
            Method = "POST",
            Headers = {
                ["Content-Type"] = "application/json",
                ["Accept"] = "application/json",
                ["HTTP-Referer"] = "https://roblox.com",
                ["X-Title"] = "OpenRouter Agent",
                Authorization = "Bearer " .. Config.ApiKey,
            },
            Body = buildBody(model),
        })
        if not ok then return nil, "request error: " .. tostring(res) end

        local status = res.StatusCode
        local raw = tostring(res.Body or "")
        local dok, data = pcall(HttpService.JSONDecode, HttpService, raw)

        if dok and type(data) == "table" and data.choices and data.choices[1] and data.choices[1].message then
            if fellBack then
                Config.Model = model -- keep using the model that works
                task.defer(setTitle)
            end
            return data.choices[1].message
        end

        -- OpenRouter can return errors inside a 200 response, so prefer error.code
        local errObj = dok and type(data) == "table" and type(data.error) == "table" and data.error or nil
        local code = (errObj and tonumber(errObj.code)) or status
        local apiMsg = (errObj and errObj.message) or raw:sub(1, 160)
        if apiMsg == "" then apiMsg = tostring(res.StatusMessage or "no response body") end
        lastErr = "HTTP " .. tostring(code) .. " (" .. model .. "): " .. tostring(apiMsg)

        -- 403 / 404 on the main model: try the fallback model once
        if (code == 403 or code == 404) and not fellBack and model ~= Config.Fallback then
            fellBack = true
            model = Config.Fallback
            continue
        end

        -- 429 (free model rate limit), 5xx, or an empty 200 from a free provider: retry with backoff
        local retry = code == 429 or code == 200 or (code and code >= 500)
        if retry and attempt < 6 then
            task.wait(3 * attempt)
        else
            if code == 401 then
                lastErr ..= "\nInvalid API key. Re-paste it with the key button (it should start with sk-or-)."
            elseif code == 402 then
                lastErr ..= "\nNot enough OpenRouter credits for this model. Use a model ending in :free or add credits."
            elseif code == 404 then
                lastErr ..= "\nModel not found or has no endpoint that supports tool calling. Check the exact model ID on openrouter.ai."
            elseif code == 429 then
                lastErr ..= "\nFree models are rate limited. Wait a bit and try again."
            end
            return nil, lastErr
        end
    end
    return nil, lastErr
end

local function clean(text)
    if type(text) ~= "string" then return "" end
    text = text:gsub("<think>.-</think>", ""):gsub("^%s+", ""):gsub("%s+$", "")
    return text
end

------------------------------------------------------------------
-- UI
------------------------------------------------------------------
local parent = (gethui and gethui()) or CoreGui
local old = parent:FindFirstChild("OpenRouterAgentUI")
if old then old:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "OpenRouterAgentUI"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.IgnoreGuiInset = true
if syn and syn.protect_gui then pcall(syn.protect_gui, gui) end
gui.Parent = parent

local C = {
    bg = Color3.fromRGB(16, 18, 30),
    accent = Color3.fromRGB(124, 108, 255),
    accent2 = Color3.fromRGB(56, 189, 248),
    text = Color3.fromRGB(235, 238, 250),
    sub = Color3.fromRGB(150, 158, 185),
    red = Color3.fromRGB(248, 113, 113),
    green = Color3.fromRGB(74, 222, 128),
}

local function corner(o, r) local c = Instance.new("UICorner") c.CornerRadius = UDim.new(0, r) c.Parent = o return c end
local function stroke(o, t, col) local s = Instance.new("UIStroke") s.Color = col or Color3.new(1, 1, 1) s.Transparency = t or 0.85 s.Thickness = 1 s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border s.Parent = o return s end
local function pad(o, p) local u = Instance.new("UIPadding") u.PaddingTop = UDim.new(0, p) u.PaddingBottom = UDim.new(0, p) u.PaddingLeft = UDim.new(0, p) u.PaddingRight = UDim.new(0, p) u.Parent = o return u end
local function grad(o, c1, c2, rot) local g = Instance.new("UIGradient") g.Color = ColorSequence.new(c1, c2) g.Rotation = rot or 45 g.Parent = o return g end

local main = Instance.new("Frame")
main.Name = "Main"
main.AnchorPoint = Vector2.new(0.5, 0.5)
main.Position = UDim2.fromScale(0.5, 0.5)
main.Size = isMobile and UDim2.new(0.94, 0, 0.88, 0) or UDim2.fromOffset(480, 580)
main.BackgroundColor3 = C.bg
main.BackgroundTransparency = 0.06
main.BorderSizePixel = 0
main.ClipsDescendants = true
main.Parent = gui
corner(main, 20)
stroke(main, 0.8)
local mainGrad = grad(main, Color3.fromRGB(40, 36, 80), Color3.fromRGB(14, 20, 34), 60)
mainGrad.Transparency = NumberSequence.new(0, 0.12)
local cons = Instance.new("UISizeConstraint")
cons.MaxSize = Vector2.new(560, 700)
cons.MinSize = Vector2.new(280, 320)
cons.Parent = main

-- header
local header = Instance.new("Frame")
header.Size = UDim2.new(1, 0, 0, 52)
header.BackgroundTransparency = 1
header.Parent = main

local dot = Instance.new("Frame")
dot.Size = UDim2.fromOffset(10, 10)
dot.Position = UDim2.new(0, 18, 0.5, -5)
dot.BackgroundColor3 = C.accent2
dot.BorderSizePixel = 0
dot.Parent = header
corner(dot, 5)
grad(dot, C.accent, C.accent2, 45)

local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1
title.Position = UDim2.fromOffset(36, 0)
title.Size = UDim2.new(1, -226, 1, 0)
title.Font = Enum.Font.GothamBold
title.TextSize = 15
title.TextColor3 = C.text
title.TextXAlignment = Enum.TextXAlignment.Left
title.RichText = true
title.TextTruncate = Enum.TextTruncate.AtEnd
title.Parent = header
function setTitle()
    title.Text = "OpenRouter Agent" .. (isMobile and "" or ("  <font size='11' color='#9ea6c0'>" .. Config.Model .. "</font>"))
end
setTitle()

local function hbtn(txt, x)
    local b = Instance.new("TextButton")
    b.Size = UDim2.fromOffset(30, 30)
    b.AnchorPoint = Vector2.new(1, 0.5)
    b.Position = UDim2.new(1, x, 0.5, 0)
    b.BackgroundColor3 = Color3.new(1, 1, 1)
    b.BackgroundTransparency = 0.9
    b:SetAttribute("rest", 0.9)
    b.Text = txt
    b.Font = Enum.Font.GothamBold
    b.TextSize = 14
    b.TextColor3 = C.text
    b.AutoButtonColor = false
    b.Parent = header
    corner(b, 10)
    b.MouseEnter:Connect(function() TweenService:Create(b, TweenInfo.new(0.15), { BackgroundTransparency = 0.75 }):Play() end)
    b.MouseLeave:Connect(function() TweenService:Create(b, TweenInfo.new(0.15), { BackgroundTransparency = b:GetAttribute("rest") }):Play() end)
    return b
end
local closeBtn = hbtn("✕", -10)
local minBtn = hbtn("–", -44)
local copyBtn = hbtn("⧉", -78)
local clearBtn = hbtn("⟲", -112)
local keyBtn = hbtn("🔑", -146)
local spyBtn = hbtn("📡", -180)

local divider = Instance.new("Frame")
divider.Position = UDim2.fromOffset(0, 52)
divider.Size = UDim2.new(1, 0, 0, 1)
divider.BackgroundColor3 = Color3.new(1, 1, 1)
divider.BackgroundTransparency = 0.9
divider.BorderSizePixel = 0
divider.Parent = main

-- chat area
local scroll = Instance.new("ScrollingFrame")
scroll.Position = UDim2.fromOffset(0, 53)
scroll.Size = UDim2.new(1, 0, 1, -127)
scroll.BackgroundTransparency = 1
scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = 3
scroll.ScrollBarImageColor3 = C.accent
scroll.ScrollingDirection = Enum.ScrollingDirection.Y
scroll.ElasticBehavior = Enum.ElasticBehavior.Never
scroll.CanvasSize = UDim2.new()
scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
scroll.Parent = main
pad(scroll, 12)
local list = Instance.new("UIListLayout")
list.Padding = UDim.new(0, 10)
list.SortOrder = Enum.SortOrder.LayoutOrder
list.Parent = scroll

local order = 0
local lastCode = ""

local function toBottom()
    task.defer(function()
        scroll.CanvasPosition = Vector2.new(0, math.max(0, scroll.AbsoluteCanvasSize.Y - scroll.AbsoluteSize.Y))
    end)
end

local function esc(s)
    return (s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

local function inline(raw)
    local s = esc(raw)
    s = s:gsub("`([^`\n]+)`", "<font face='Code' color='#a5f3fc'>%1</font>")
    s = s:gsub("%*%*(.-)%*%*", "<b>%1</b>")
    s = s:gsub("\n#+ ([^\n]+)", "\n<b>%1</b>")
    s = s:gsub("^#+ ([^\n]+)", "<b>%1</b>")
    return s
end

local function row(role)
    order += 1
    local r = Instance.new("Frame")
    r.LayoutOrder = order
    r.BackgroundTransparency = 1
    r.AutomaticSize = Enum.AutomaticSize.Y
    r.Size = UDim2.new(1, 0, 0, 0)
    r.Parent = scroll
    local l = Instance.new("UIListLayout")
    l.HorizontalAlignment = role == "user" and Enum.HorizontalAlignment.Right or Enum.HorizontalAlignment.Left
    l.Parent = r
    return r
end

local function bubble(role)
    local isUser = role == "user"
    local f = Instance.new("Frame")
    f.AutomaticSize = Enum.AutomaticSize.Y
    f.Size = UDim2.new(isUser and 0.85 or 1, 0, 0, 0)
    f.BackgroundColor3 = isUser and C.accent or Color3.new(1, 1, 1)
    f.BackgroundTransparency = isUser and 0.2 or 0.93
    f.BorderSizePixel = 0
    f.Parent = row(role)
    corner(f, 14)
    stroke(f, isUser and 0.7 or 0.88)
    pad(f, 10)
    local l = Instance.new("UIListLayout")
    l.Padding = UDim.new(0, 8)
    l.SortOrder = Enum.SortOrder.LayoutOrder
    l.Parent = f
    return f
end

local function label(parentFrame, text, color, size)
    local t = Instance.new("TextLabel")
    t.BackgroundTransparency = 1
    t.AutomaticSize = Enum.AutomaticSize.Y
    t.Size = UDim2.new(1, 0, 0, 0)
    t.Font = Enum.Font.Gotham
    t.TextSize = size or 14
    t.TextColor3 = color or C.text
    t.TextXAlignment = Enum.TextXAlignment.Left
    t.TextYAlignment = Enum.TextYAlignment.Top
    t.TextWrapped = true
    t.RichText = true
    t.Text = text
    t.Parent = parentFrame
    return t
end

local function typeOut(lbl)
    local total = utf8.len(lbl.ContentText) or #lbl.ContentText
    if not Config.Typewriter or total > 3000 then return end
    lbl.MaxVisibleGraphemes = 0
    local step = math.max(3, math.ceil(total / 70))
    local i, n = 0, 0
    while i < total and lbl.Parent do
        i += step
        n += 1
        lbl.MaxVisibleGraphemes = i
        if n % 5 == 0 then toBottom() end
        task.wait(0.025)
    end
    lbl.MaxVisibleGraphemes = -1
    toBottom()
end

local addChip -- forward declaration

local function codeBlock(parentFrame, code, layoutOrder)
    code = code:gsub("^\n+", ""):gsub("\n+$", "")
    lastCode = code
    local box = Instance.new("Frame")
    box.LayoutOrder = layoutOrder
    box.AutomaticSize = Enum.AutomaticSize.Y
    box.Size = UDim2.new(1, 0, 0, 0)
    box.BackgroundColor3 = Color3.fromRGB(6, 8, 16)
    box.BackgroundTransparency = 0.12
    box.BorderSizePixel = 0
    box.Parent = parentFrame
    corner(box, 10)
    stroke(box, 0.85)
    local bl = Instance.new("UIListLayout")
    bl.SortOrder = Enum.SortOrder.LayoutOrder
    bl.Parent = box

    local top = Instance.new("Frame")
    top.LayoutOrder = 1
    top.Size = UDim2.new(1, 0, 0, 32)
    top.BackgroundTransparency = 1
    top.Parent = box
    local tl = Instance.new("TextLabel")
    tl.BackgroundTransparency = 1
    tl.Position = UDim2.fromOffset(12, 0)
    tl.Size = UDim2.new(0.3, 0, 1, 0)
    tl.Font = Enum.Font.GothamMedium
    tl.TextSize = 11
    tl.TextColor3 = C.sub
    tl.TextXAlignment = Enum.TextXAlignment.Left
    tl.Text = "lua"
    tl.Parent = top

    local function cbtn(txt, x)
        local b = Instance.new("TextButton")
        b.AnchorPoint = Vector2.new(1, 0.5)
        b.Position = UDim2.new(1, x, 0.5, 0)
        b.Size = UDim2.fromOffset(60, 24)
        b.BackgroundColor3 = Color3.new(1, 1, 1)
        b.BackgroundTransparency = 0.88
        b.Text = txt
        b.Font = Enum.Font.GothamBold
        b.TextSize = 12
        b.TextColor3 = C.text
        b.AutoButtonColor = false
        b.Parent = top
        corner(b, 8)
        return b
    end
    local copy = cbtn("Copy", -8)
    local run = cbtn("Run", -74)

    local tb = Instance.new("TextBox")
    tb.LayoutOrder = 2
    tb.AutomaticSize = Enum.AutomaticSize.Y
    tb.Size = UDim2.new(1, 0, 0, 0)
    tb.BackgroundTransparency = 1
    tb.TextEditable = false
    tb.ClearTextOnFocus = false
    tb.MultiLine = true
    tb.Font = Enum.Font.Code
    tb.TextSize = 13
    tb.TextColor3 = Color3.fromRGB(165, 243, 252)
    tb.TextXAlignment = Enum.TextXAlignment.Left
    tb.TextYAlignment = Enum.TextYAlignment.Top
    tb.TextWrapped = true
    tb.RichText = false
    tb.Text = #code > 15000 and (code:sub(1, 15000) .. "\n...[display truncated, Copy has everything]") or code
    tb.Parent = box
    local tp = Instance.new("UIPadding")
    tp.PaddingLeft = UDim.new(0, 12)
    tp.PaddingRight = UDim.new(0, 12)
    tp.PaddingBottom = UDim.new(0, 10)
    tp.Parent = tb

    copy.MouseButton1Click:Connect(function()
        if setclipboard then
            setclipboard(code)
            copy.Text = "Copied ✓"
        else
            copy.Text = "Hold code"
        end
        task.delay(1.2, function() if copy.Parent then copy.Text = "Copy" end end)
    end)
    run.MouseButton1Click:Connect(function()
        task.spawn(function()
            local rec, report = runCode(code, "your script")
            if not rec then addChip(report, C.red) end
        end)
    end)
end

local function addUser(text)
    local b = bubble("user")
    label(b, esc(text))
    toBottom()
end

local function addAI(text)
    local b = bubble("ai")
    local n = 0
    local function textSeg(seg)
        seg = seg:gsub("^\n+", ""):gsub("\n+$", "")
        if seg == "" then return end
        local i = 1
        while i <= #seg do
            local j = math.min(i + 11000, #seg)
            if j < #seg then
                local nl = seg:sub(i, j):match(".*()\n")
                if nl and nl > 2000 then j = i + nl - 1 end
            end
            n += 1
            local l = label(b, inline(seg:sub(i, j)))
            l.LayoutOrder = n
            typeOut(l)
            i = j + 1
        end
    end
    local pos = 1
    while true do
        local s, e = text:find("```", pos, true)
        if not s then textSeg(text:sub(pos)) break end
        textSeg(text:sub(pos, s - 1))
        local ce = text:find("```", e + 1, true)
        local body = text:sub(e + 1, ce and (ce - 1) or #text)
        body = (body:gsub("^[%w_]*\n", ""))
        n += 1
        codeBlock(b, body, n)
        toBottom()
        if not ce then break end
        pos = ce + 3
    end
    if n == 0 then
        n += 1
        label(b, "(empty)").LayoutOrder = n
    end
    toBottom()
end

function addChip(text, color)
    order += 1
    local c = Instance.new("TextLabel")
    c.LayoutOrder = order
    c.AutomaticSize = Enum.AutomaticSize.XY
    c.BackgroundColor3 = color or C.accent2
    c.BackgroundTransparency = 0.88
    c.Font = Enum.Font.Code
    c.TextSize = 12
    c.TextColor3 = color or C.accent2
    c.Text = text
    c.TextWrapped = true
    c.TextXAlignment = Enum.TextXAlignment.Left
    c.Size = UDim2.new(0, 0, 0, 0)
    c.Parent = scroll
    corner(c, 8)
    pad(c, 6)
    local sz = Instance.new("UISizeConstraint")
    sz.MaxSize = Vector2.new(420, 1e4)
    sz.Parent = c
    toBottom()
    return c
end

-- input bar
local bar = Instance.new("Frame")
bar.AnchorPoint = Vector2.new(0, 1)
bar.Position = UDim2.new(0, 12, 1, -12)
bar.Size = UDim2.new(1, -24, 0, 46)
bar.BackgroundColor3 = Color3.new(1, 1, 1)
bar.BackgroundTransparency = 0.9
bar.BorderSizePixel = 0
bar.Parent = main
corner(bar, 16)
local barStroke = stroke(bar, 0.85)

local input = Instance.new("TextBox")
input.BackgroundTransparency = 1
input.Position = UDim2.fromOffset(14, 0)
input.Size = UDim2.new(1, -66, 1, 0)
input.Font = Enum.Font.Gotham
input.TextSize = 14
input.TextColor3 = C.text
input.PlaceholderText = "Ask me to build a Lua script..."
input.PlaceholderColor3 = C.sub
input.TextXAlignment = Enum.TextXAlignment.Left
input.ClearTextOnFocus = false
input.Text = ""
input.Parent = bar

local send = Instance.new("TextButton")
send.AnchorPoint = Vector2.new(1, 0.5)
send.Position = UDim2.new(1, -7, 0.5, 0)
send.Size = UDim2.fromOffset(36, 32)
send.BackgroundColor3 = C.accent
send.Text = "➤"
send.TextColor3 = Color3.new(1, 1, 1)
send.TextSize = 15
send.Font = Enum.Font.GothamBold
send.AutoButtonColor = false
send.Parent = bar
corner(send, 11)
grad(send, C.accent, C.accent2, 30)

input.Focused:Connect(function() TweenService:Create(barStroke, TweenInfo.new(0.2), { Transparency = 0.3, Color = C.accent }):Play() end)
input.FocusLost:Connect(function() TweenService:Create(barStroke, TweenInfo.new(0.2), { Transparency = 0.85, Color = Color3.new(1, 1, 1) }):Play() end)

-- key / settings panel
local keyPanel = Instance.new("Frame")
keyPanel.Visible = false
keyPanel.ZIndex = 5
keyPanel.Position = UDim2.fromOffset(12, 62)
keyPanel.Size = UDim2.new(1, -24, 0, 186)
keyPanel.BackgroundColor3 = Color3.fromRGB(10, 12, 22)
keyPanel.BackgroundTransparency = 0.03
keyPanel.BorderSizePixel = 0
keyPanel.Parent = main
corner(keyPanel, 14)
stroke(keyPanel, 0.75)
pad(keyPanel, 10)
local kl = Instance.new("UIListLayout")
kl.Padding = UDim.new(0, 6)
kl.SortOrder = Enum.SortOrder.LayoutOrder
kl.Parent = keyPanel

local function kLabel(t, o)
    local l = label(keyPanel, t, C.sub, 12)
    l.AutomaticSize = Enum.AutomaticSize.None
    l.Size = UDim2.new(1, 0, 0, 16)
    l.LayoutOrder = o
    return l
end
local function kBox(ph, o)
    local t = Instance.new("TextBox")
    t.LayoutOrder = o
    t.Size = UDim2.new(1, 0, 0, 34)
    t.BackgroundColor3 = Color3.new(1, 1, 1)
    t.BackgroundTransparency = 0.9
    t.Font = Enum.Font.Code
    t.TextSize = 13
    t.TextColor3 = C.text
    t.PlaceholderText = ph
    t.PlaceholderColor3 = C.sub
    t.ClearTextOnFocus = false
    t.TextXAlignment = Enum.TextXAlignment.Left
    t.ClipsDescendants = true
    t.Text = ""
    t.Parent = keyPanel
    corner(t, 10)
    local p = Instance.new("UIPadding")
    p.PaddingLeft = UDim.new(0, 10)
    p.PaddingRight = UDim.new(0, 10)
    p.Parent = t
    return t
end
kLabel("OpenRouter API key", 1)
local keyBox = kBox(Config.ApiKey ~= "" and "Key saved. Paste a new one to replace" or "Paste your key (sk-or-v1-...)", 2)
kLabel("Model ID (copy from openrouter.ai)", 3)
local modelBox = kBox("nvidia/nemotron-3.5-lightning:free", 4)
modelBox.Text = Config.Model
local saveBtn = Instance.new("TextButton")
saveBtn.LayoutOrder = 5
saveBtn.Size = UDim2.new(1, 0, 0, 34)
saveBtn.BackgroundColor3 = C.accent
saveBtn.Text = "Save"
saveBtn.Font = Enum.Font.GothamBold
saveBtn.TextSize = 14
saveBtn.TextColor3 = Color3.new(1, 1, 1)
saveBtn.AutoButtonColor = false
saveBtn.Parent = keyPanel
corner(saveBtn, 10)
grad(saveBtn, C.accent, C.accent2, 30)
saveBtn.MouseButton1Click:Connect(function()
    local k = keyBox.Text:gsub("[%s\"']", "")
    if k ~= "" then Config.ApiKey = k end
    local m = modelBox.Text:gsub("[%s\"']", "")
    if m ~= "" then Config.Model = m end
    saveSettings()
    setTitle()
    keyBox.Text = ""
    keyBox.PlaceholderText = "Key saved. Paste a new one to replace"
    keyPanel.Visible = false
    addChip(Config.ApiKey ~= "" and ("✓ saved · " .. Config.Model) or "No key set yet", C.accent2)
end)
keyBtn.MouseButton1Click:Connect(function() keyPanel.Visible = not keyPanel.Visible end)

-- floating orb (minimized)
local orb = Instance.new("TextButton")
orb.Size = UDim2.fromOffset(52, 52)
orb.Position = UDim2.new(0, 20, 0.5, -26)
orb.BackgroundColor3 = C.accent
orb.BackgroundTransparency = 0.15
orb.Text = "✦"
orb.TextSize = 22
orb.TextColor3 = Color3.new(1, 1, 1)
orb.Font = Enum.Font.GothamBold
orb.AutoButtonColor = false
orb.Visible = false
orb.Parent = gui
corner(orb, 26)
stroke(orb, 0.6)
grad(orb, C.accent, C.accent2, 45)

-- dragging
local function makeDraggable(handle, target, onTap)
    local dragging, start, startPos, moved
    handle.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dragging, moved = true, false
            start, startPos = i.Position, target.Position
            i.Changed:Connect(function()
                if i.UserInputState == Enum.UserInputState.End then
                    dragging = false
                    if onTap and not moved then onTap() end
                end
            end)
        end
    end)
    UserInputService.InputChanged:Connect(function(i)
        if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
            local d = i.Position - start
            if d.Magnitude > 4 then moved = true end
            target.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end)
end
makeDraggable(header, main)
makeDraggable(orb, orb, function() orb.Visible = false main.Visible = true end)

minBtn.MouseButton1Click:Connect(function() main.Visible = false orb.Visible = true end)
closeBtn.MouseButton1Click:Connect(function() gui:Destroy() end)
copyBtn.MouseButton1Click:Connect(function()
    if setclipboard and lastCode ~= "" then
        setclipboard(lastCode)
        copyBtn.Text = "✓"
        task.delay(1, function() copyBtn.Text = "⧉" end)
    end
end)
clearBtn.MouseButton1Click:Connect(function()
    history = {}
    for _, c in ipairs(scroll:GetChildren()) do
        if not c:IsA("UIListLayout") and not c:IsA("UIPadding") then c:Destroy() end
    end
    addChip("conversation cleared", C.sub)
end)

-- spy button
onSpyChange = function()
    spyBtn:SetAttribute("rest", Spy.on and 0.45 or 0.9)
    spyBtn.BackgroundColor3 = Spy.on and C.green or Color3.new(1, 1, 1)
    spyBtn.BackgroundTransparency = Spy.on and 0.45 or 0.9
end
spyBtn.MouseButton1Click:Connect(function()
    if Spy.on then
        addChip("📡 " .. stopSpy(), C.sub)
    else
        addChip("📡 " .. startSpy(), C.green)
    end
end)
onSpyChange()

-- running script rows with Stop button
onScriptEvent = function(kind, rec, info)
    if kind == "start" then
        order += 1
        local f = Instance.new("Frame")
        f.LayoutOrder = order
        f.Size = UDim2.new(1, 0, 0, 36)
        f.BackgroundColor3 = C.accent2
        f.BackgroundTransparency = 0.88
        f.BorderSizePixel = 0
        f.Parent = scroll
        corner(f, 10)
        local l = Instance.new("TextLabel")
        l.BackgroundTransparency = 1
        l.Position = UDim2.fromOffset(12, 0)
        l.Size = UDim2.new(1, -84, 1, 0)
        l.Font = Enum.Font.Code
        l.TextSize = 12
        l.TextColor3 = C.accent2
        l.TextXAlignment = Enum.TextXAlignment.Left
        l.TextTruncate = Enum.TextTruncate.AtEnd
        l.Text = "▶ #" .. rec.id .. " " .. rec.name
        l.Parent = f
        local b = Instance.new("TextButton")
        b.AnchorPoint = Vector2.new(1, 0.5)
        b.Position = UDim2.new(1, -6, 0.5, 0)
        b.Size = UDim2.fromOffset(62, 26)
        b.BackgroundColor3 = C.red
        b.BackgroundTransparency = 0.7
        b.Text = "Stop"
        b.Font = Enum.Font.GothamBold
        b.TextSize = 12
        b.TextColor3 = C.text
        b.AutoButtonColor = false
        b.Parent = f
        corner(b, 8)
        b.MouseButton1Click:Connect(function() stopScript(rec.id) end)
        rec.ui = { label = l, btn = b }
        toBottom()
    elseif rec.ui then
        if kind == "error" then
            rec.ui.label.Text = "✖ #" .. rec.id .. " " .. tostring(info):sub(1, 80)
            rec.ui.label.TextColor3 = C.red
        elseif kind == "stop" then
            rec.ui.label.Text = "■ #" .. rec.id .. " stopped & undone"
            rec.ui.label.TextColor3 = C.sub
            if rec.ui.btn then rec.ui.btn:Destroy() rec.ui.btn = nil end
        end
    end
end

------------------------------------------------------------------
-- Agent loop
------------------------------------------------------------------
local busy = false

local function thinking()
    local chip = addChip("thinking", C.sub)
    local alive = true
    task.spawn(function()
        local n = 0
        while alive and chip.Parent do
            n = n % 3 + 1
            chip.Text = "thinking" .. string.rep(".", n)
            task.wait(0.4)
        end
    end)
    return function()
        alive = false
        if chip.Parent then chip:Destroy() end
    end
end

local function handle(userText)
    history[#history + 1] = { role = "user", content = userText }
    trimHistory()
    local seen = {}

    for _ = 1, Config.MaxToolSteps do
        local stop = thinking()
        local ok, msg, err = pcall(callAI)
        stop()
        if not ok then addChip("error: " .. tostring(msg), C.red) return end
        if not msg then addChip("error: " .. tostring(err), C.red) return end

        local text = clean(msg.content)
        local calls = msg.tool_calls
        local hasCalls = type(calls) == "table" and #calls > 0
        history[#history + 1] = {
            role = "assistant",
            content = (text == "" and hasCalls) and nil or text,
            tool_calls = hasCalls and calls or nil,
        }

        if text ~= "" then addAI(text) end
        if not hasCalls then return end

        for _, call in ipairs(calls) do
            local f = call["function"] or {}
            local name = f.name or "?"
            local aok, args = pcall(HttpService.JSONDecode, HttpService, (f.arguments and f.arguments ~= "") and f.arguments or "{}")
            if not aok or type(args) ~= "table" then args = {} end

            local argStr = (f.arguments or ""):gsub("%s+", " ")
            if #argStr > 90 then argStr = argStr:sub(1, 90) .. "…" end
            addChip("⚙ " .. name .. " " .. argStr)

            local sig = name .. "|" .. (f.arguments or "")
            seen[sig] = (seen[sig] or 0) + 1
            local res
            if seen[sig] > 2 and name ~= "run_lua" then
                res = "this exact call was already made twice with the same result; try a different approach or answer the user"
            else
                local tool = Tools[name]
                local rok, r = pcall(function()
                    if not tool then return "unknown tool: " .. name end
                    return tool(args)
                end)
                res = clip(rok and r or ("tool error: " .. tostring(r)))
            end
            history[#history + 1] = { role = "tool", tool_call_id = call.id, content = res }
        end
    end
    addChip("stopped: tool step limit reached", Color3.fromRGB(251, 191, 36))
end

local function submit()
    if busy then return end
    local text = input.Text
    if text:gsub("%s", "") == "" then return end
    if Config.ApiKey == "" then
        keyPanel.Visible = true
        addChip("Add your OpenRouter API key first.", C.red)
        return
    end
    input.Text = ""
    busy = true
    send.Text = "…"
    addUser(text)
    task.spawn(function()
        local ok, e = pcall(handle, text)
        if not ok then addChip("error: " .. tostring(e), C.red) end
        busy = false
        send.Text = "➤"
    end)
end

send.MouseButton1Click:Connect(submit)
input.FocusLost:Connect(function(enter) if enter then submit() end end)

-- intro
if Config.ApiKey == "" then keyPanel.Visible = true end
main.BackgroundTransparency = 1
TweenService:Create(main, TweenInfo.new(0.35, Enum.EasingStyle.Quad), { BackgroundTransparency = 0.06 }):Play()
addAI("Hey! I chat and write Lua scripts. I can explore the game, catch remote events (📡), and run or undo scripts.\n\nTry: `make a speed adjustment UI`")
```

Setup:
1. Get a key at openrouter.ai/keys. It starts with `sk-or-v1-`.
2. Run the script, tap 🔑, paste the key, check the model ID, and press Save.

Two things to expect:
- Free models are often rate limited and can be slow. The script retries with backoff, but you may still see a 429.
- Not every free model handles tool calling well. If Nemotron ignores the tools or errors with "no endpoints support tools", switch to another `:free` model that lists tool support on its OpenRouter page.
````
````
can you change the ai model into
Nemotron 3.5 Lightning (free)
and openrouther api
--[[
    Groq Agent  |  glass chat UI + tool calling + remote spy + stoppable scripts
    Run it, tap the key button, paste your Groq key, save.
]]

local Config = {
    ApiKey = "", -- set from the UI (key button)
    Model = "qwen/qwen3.8-27b",
    Fallback = "qwen/qwen3-32b", -- used once if the main model returns 403/404
    Endpoint = "https://api.groq.com/openai/v1/chat/completions",
    Temperature = 0.4,
    MaxTokens = 900, -- keep under your tier's output-tokens-per-minute limit (auto-lowers on 429)
    MaxToolSteps = 16,
    MaxToolOutput = 12000,
    MaxHistory = 40,
    Typewriter = true,
}

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local CoreGui = game:GetService("CoreGui")
local CollectionService = game:GetService("CollectionService")

local LocalPlayer = Players.LocalPlayer
local httpRequest = (syn and syn.request) or (http and http.request) or http_request or request
local isMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
local genv = (getgenv and getgenv()) or _G

-- saved settings (key + model)
local SAVE = "GroqAgent_settings.json"
pcall(function()
    if isfile and readfile and isfile(SAVE) then
        local d = HttpService:JSONDecode(readfile(SAVE))
        if type(d.key) == "string" then Config.ApiKey = d.key end
        if type(d.model) == "string" and d.model ~= "" then Config.Model = d.model end
    end
end)
local function saveSettings()
    pcall(function()
        if writefile then writefile(SAVE, HttpService:JSONEncode({ key = Config.ApiKey, model = Config.Model })) end
    end)
end

------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------
local function fullName(inst)
    local ok, n = pcall(inst.GetFullName, inst)
    return ok and n or inst.Name
end
local function path(inst) return "game." .. fullName(inst) end

local function clip(s)
    s = tostring(s)
    if #s > Config.MaxToolOutput then
        return s:sub(1, Config.MaxToolOutput) .. "\n...[truncated " .. (#s - Config.MaxToolOutput) .. " chars]"
    end
    return s
end

local function ser(v, d)
    d = d or 0
    local t = typeof(v)
    if t == "string" then
        local s = v:sub(1, 200):gsub("[\r\n]", " ")
        return '"' .. s .. '"' .. (#v > 200 and "…" or "")
    elseif t == "Instance" then
        return path(v)
    elseif t == "table" then
        if d >= 3 then return "{...}" end
        local parts, n = {}, 0
        for k, val in pairs(v) do
            n += 1
            if n > 12 then parts[#parts + 1] = "..." break end
            local key = type(k) == "number" and "" or (tostring(k) .. "=")
            parts[#parts + 1] = key .. ser(val, d + 1)
        end
        return "{" .. table.concat(parts, ", ") .. "}"
    elseif t == "Vector3" then
        return string.format("Vector3.new(%g, %g, %g)", v.X, v.Y, v.Z)
    elseif t == "Vector2" then
        return string.format("Vector2.new(%g, %g)", v.X, v.Y)
    elseif t == "CFrame" then
        local p = v.Position
        return string.format("CFrame.new(%g, %g, %g)", p.X, p.Y, p.Z)
    elseif t == "Color3" then
        return string.format("Color3.fromRGB(%d, %d, %d)", v.R * 255, v.G * 255, v.B * 255)
    end
    return tostring(v)
end

local function child(cur, seg)
    local c = cur:FindFirstChild(seg)
    if c then return c end
    if cur == game then
        local ok, svc = pcall(game.GetService, game, seg)
        if ok and svc then return svc end
    end
    local l = seg:lower()
    if cur == Players and l == "localplayer" then return LocalPlayer end
    if cur == LocalPlayer and l == "character" then return LocalPlayer.Character end
    for _, x in ipairs(cur:GetChildren()) do
        if x.Name:lower() == l then return x end
    end
end

local function resolve(p)
    if type(p) ~= "string" or p == "" then return game end
    local cur = game
    local first = true
    for seg in p:gmatch("[^%.]+") do
        if not (first and seg == "game") then
            local nxt = child(cur, seg)
            if not nxt then return nil, "not found: '" .. seg .. "' under " .. path(cur) end
            cur = nxt
        end
        first = false
    end
    return cur
end

------------------------------------------------------------------
-- Remote spy (outgoing FireServer/InvokeServer + incoming OnClientEvent)
------------------------------------------------------------------
local onSpyChange = function() end

local Spy = genv.__GA_Spy
if not Spy then
    Spy = { on = false, log = {}, hooked = false, conns = {}, max = 400, t0 = os.clock(), watched = setmetatable({}, { __mode = "k" }) }
    genv.__GA_Spy = Spy
end

local function spyLog(dir, remote, method, args)
    local parts = {}
    for i = 1, args.n do parts[i] = ser(args[i]) end
    local rest
    if dir == "out" then
        rest = "→ server  " .. path(remote) .. ":" .. method .. "(" .. table.concat(parts, ", ") .. ")"
    else
        rest = "← client  " .. path(remote) .. ".OnClientEvent(" .. table.concat(parts, ", ") .. ")"
    end
    local last = Spy.log[#Spy.log]
    if last and last.key == rest then
        last.n += 1
        return
    end
    Spy.log[#Spy.log + 1] = { t = os.clock() - Spy.t0, key = rest, n = 1 }
    if #Spy.log > Spy.max then table.remove(Spy.log, 1) end
end
Spy.record = spyLog

local function installHook()
    if Spy.hooked then return true end
    if not (hookmetamethod and getnamecallmethod) then return false end
    local old
    local wrap = newcclosure or function(f) return f end
    local ok = pcall(function()
        old = hookmetamethod(game, "__namecall", wrap(function(self, ...)
            local method = getnamecallmethod()
            if Spy.on and (method == "FireServer" or method == "InvokeServer") and typeof(self) == "Instance" and not (checkcaller and checkcaller()) then
                local args = table.pack(...)
                local target = self
                task.defer(function() pcall(Spy.record, "out", target, method, args) end)
            end
            return old(self, ...)
        end))
    end)
    if ok then Spy.hooked = true end
    return ok
end

local function watch(r)
    if Spy.watched[r] then return end
    if r:IsA("RemoteEvent") or r:IsA("UnreliableRemoteEvent") then
        Spy.watched[r] = true
        Spy.conns[#Spy.conns + 1] = r.OnClientEvent:Connect(function(...)
            if Spy.on then Spy.record("in", r, "OnClientEvent", table.pack(...)) end
        end)
    end
end

local function startSpy()
    local hooked = installHook()
    Spy.on = true
    Spy.t0 = os.clock()
    Spy.record = spyLog
    for _, d in ipairs(game:GetDescendants()) do pcall(watch, d) end
    if not Spy.added then
        Spy.added = game.DescendantAdded:Connect(function(d) if Spy.on then pcall(watch, d) end end)
    end
    onSpyChange()
    return "remote spy ON. Outgoing FireServer/InvokeServer: " .. (hooked and "captured" or "NOT available (executor has no hookmetamethod)") .. ". Incoming OnClientEvent: captured. Ask the user to do the action in-game, then call get_remote_log."
end

local function stopSpy()
    Spy.on = false
    onSpyChange()
    return "remote spy OFF (" .. #Spy.log .. " events kept)"
end

------------------------------------------------------------------
-- Script runner (run + stop/undo)
------------------------------------------------------------------
local onScriptEvent = function() end
local Running, nextId = {}, 0

local function stopScript(id)
    local rec = Running[id]
    if not rec then return false, "no script with id " .. tostring(id) end
    if rec.stopped then return false, "script #" .. id .. " already stopped" end
    rec.stopped = true
    for _, c in ipairs(rec.conns) do pcall(function() c:Disconnect() end) end
    for _, th in ipairs(rec.threads) do pcall(task.cancel, th) end
    for i = #rec.cleanups, 1, -1 do pcall(rec.cleanups[i]) end
    for i = #rec.instances, 1, -1 do pcall(function() rec.instances[i]:Destroy() end) end
    rec.state = "stopped"
    onScriptEvent("stop", rec)
    return true
end

local function runCode(code, label)
    local fn, cerr = loadstring(code)
    if not fn then return nil, "compile error: " .. tostring(cerr) end
    nextId += 1
    local rec = { id = nextId, name = label or ("script " .. nextId), conns = {}, threads = {}, cleanups = {}, instances = {}, logs = {}, state = "running" }
    Running[rec.id] = rec

    local function log(...)
        local t = table.pack(...)
        for i = 1, t.n do t[i] = tostring(t[i]) end
        rec.logs[#rec.logs + 1] = table.concat(t, " ")
        if #rec.logs > 80 then table.remove(rec.logs, 1) end
    end
    local function trackThread(th) rec.threads[#rec.threads + 1] = th return th end
    local env = {
        print = log,
        warn = function(...) log("[warn]", ...) end,
        cleanup = function(f) if type(f) == "function" then rec.cleanups[#rec.cleanups + 1] = f end end,
        track = function(x)
            local t = typeof(x)
            if t == "RBXScriptConnection" then rec.conns[#rec.conns + 1] = x
            elseif t == "Instance" then rec.instances[#rec.instances + 1] = x
            elseif t == "function" then rec.cleanups[#rec.cleanups + 1] = x
            elseif t == "thread" then rec.threads[#rec.threads + 1] = x end
            return x
        end,
        task = setmetatable({
            spawn = function(f, ...) return trackThread(task.spawn(f, ...)) end,
            delay = function(t, f, ...) return trackThread(task.delay(t, f, ...)) end,
            defer = function(f, ...) return trackThread(task.defer(f, ...)) end,
        }, { __index = task }),
        Instance = setmetatable({
            new = function(...)
                local o = Instance.new(...)
                rec.instances[#rec.instances + 1] = o
                return o
            end,
        }, { __index = Instance }),
    }
    local okEnv = pcall(function()
        setfenv(fn, setmetatable(env, { __index = getfenv(fn) }))
    end)

    onScriptEvent("start", rec)
    local done, ok, res = false, false, nil
    trackThread(task.spawn(function()
        ok, res = pcall(fn)
        done = true
        if not ok then
            rec.state = "error"
            log("[error]", tostring(res))
            onScriptEvent("error", rec, tostring(res))
        end
    end))
    if not done then task.wait(0.35) end

    local out
    if done and ok then
        out = "script #" .. rec.id .. " ran OK and finished its main chunk. Anything it created stays active until stop_script(" .. rec.id .. ")."
        if res ~= nil then out ..= "\nreturned: " .. tostring(res) end
    elseif done then
        out = "script #" .. rec.id .. " ERROR: " .. tostring(res)
    else
        out = "script #" .. rec.id .. " is running in the background (loop or waiting). Use stop_script(" .. rec.id .. ") to stop and undo it."
    end
    if not okEnv then out ..= "\n(note: executor has no setfenv, cleanup()/track() helpers were unavailable)" end
    if #rec.logs > 0 then out ..= "\noutput:\n" .. table.concat(rec.logs, "\n") end
    return rec, out
end

------------------------------------------------------------------
-- Tools
------------------------------------------------------------------
local Tools = {}

local function defaultProps(inst)
    local p = { "Name", "ClassName", "Parent" }
    local function add(...) for _, n in ipairs({ ... }) do p[#p + 1] = n end end
    if inst:IsA("BasePart") then add("Position", "Size", "Anchored", "CanCollide", "Transparency", "Color", "Material") end
    if inst:IsA("Humanoid") then add("WalkSpeed", "JumpPower", "JumpHeight", "UseJumpPower", "Health", "MaxHealth", "HipHeight") end
    if inst:IsA("GuiObject") then add("Position", "Size", "Visible", "BackgroundTransparency", "ZIndex") end
    if inst:IsA("TextLabel") or inst:IsA("TextButton") or inst:IsA("TextBox") then add("Text") end
    if inst:IsA("ValueBase") then add("Value") end
    if inst:IsA("Model") then add("PrimaryPart") end
    if inst:IsA("ProximityPrompt") then add("ActionText", "HoldDuration", "MaxActivationDistance", "Enabled") end
    if inst:IsA("ClickDetector") then add("MaxActivationDistance") end
    if inst:IsA("LocalScript") or inst:IsA("Script") then add("Disabled") end
    return p
end

local function readProps(inst, names)
    local out = {}
    for _, n in ipairs(names) do
        local ok, v = pcall(function() return inst[n] end)
        if not ok and gethiddenproperty then
            local ok2, v2 = pcall(gethiddenproperty, inst, n)
            if ok2 then ok, v = true, v2 end
        end
        if ok then out[#out + 1] = n .. " = " .. ser(v) end
    end
    return out
end

Tools.overview = function()
    local out = { "PlaceId " .. game.PlaceId .. " | JobId " .. tostring(game.JobId):sub(1, 8) }
    for _, name in ipairs({ "Workspace", "ReplicatedStorage", "ReplicatedFirst", "StarterGui", "StarterPack", "StarterPlayer", "Lighting", "SoundService", "Players" }) do
        local ok, svc = pcall(game.GetService, game, name)
        if ok and svc then
            out[#out + 1] = name .. ": " .. #svc:GetChildren() .. " children, " .. #svc:GetDescendants() .. " descendants"
        end
    end
    local remotes, scripts = 0, 0
    for _, d in ipairs(game:GetDescendants()) do
        if d:IsA("RemoteEvent") or d:IsA("RemoteFunction") or d:IsA("UnreliableRemoteEvent") then remotes += 1
        elseif d:IsA("LocalScript") or d:IsA("ModuleScript") then scripts += 1 end
    end
    out[#out + 1] = "remotes visible: " .. remotes .. " | local/module scripts visible: " .. scripts
    out[#out + 1] = "executor: decompile=" .. tostring(decompile ~= nil) .. " hookmetamethod=" .. tostring(hookmetamethod ~= nil) .. " setclipboard=" .. tostring(setclipboard ~= nil)
    return table.concat(out, "\n")
end

Tools.explore = function(a)
    local root, err = resolve(a.path)
    if not root then return err end
    local maxDepth = math.clamp(tonumber(a.depth) or 1, 1, 6)
    local lines, count, capped = {}, 0, false
    local function walk(inst, d)
        for _, c in ipairs(inst:GetChildren()) do
            if count >= 300 then capped = true return end
            count += 1
            local n = #c:GetChildren()
            lines[#lines + 1] = string.rep("  ", d - 1) .. c.Name .. " [" .. c.ClassName .. "]" .. (n > 0 and (" (" .. n .. ")") or "")
            if d < maxDepth then walk(c, d + 1) end
        end
    end
    walk(root, 1)
    return path(root) .. " [" .. root.ClassName .. "]\n" .. (#lines > 0 and table.concat(lines, "\n") or "(no children)") .. (capped and "\n...(capped at 300, narrow the path)" or "")
end

Tools.find = function(a)
    local root = resolve(a.root) or game
    local q = tostring(a.query or ""):lower()
    local cls = a.className
    local out = {}
    for _, d in ipairs(root:GetDescendants()) do
        if (q == "" or d.Name:lower():find(q, 1, true)) and (not cls or d:IsA(cls)) then
            out[#out + 1] = path(d) .. " [" .. d.ClassName .. "]"
            if #out >= 80 then break end
        end
    end
    return #out > 0 and table.concat(out, "\n") or "no matches"
end

Tools.inspect = function(a)
    local inst, err = resolve(a.path)
    if not inst then return err end
    local out = { path(inst) .. " [" .. inst.ClassName .. "]", "children: " .. #inst:GetChildren() .. ", descendants: " .. #inst:GetDescendants() }
    local attrs = {}
    for k, v in pairs(inst:GetAttributes()) do attrs[#attrs + 1] = k .. "=" .. ser(v) end
    if #attrs > 0 then out[#out + 1] = "attributes: " .. table.concat(attrs, ", ") end
    local tags = CollectionService:GetTags(inst)
    if #tags > 0 then out[#out + 1] = "tags: " .. table.concat(tags, ", ") end
    for _, l in ipairs(readProps(inst, defaultProps(inst))) do out[#out + 1] = l end
    return table.concat(out, "\n")
end

Tools.get_properties = function(a)
    local inst, err = resolve(a.path)
    if not inst then return err end
    local names = a.names
    if type(names) ~= "table" or #names == 0 then names = defaultProps(inst) end
    return table.concat(readProps(inst, names), "\n")
end

Tools.list_remotes = function(a)
    local root = resolve(a.root) or game
    local out = {}
    for _, d in ipairs(root:GetDescendants()) do
        if d:IsA("RemoteEvent") or d:IsA("RemoteFunction") or d:IsA("UnreliableRemoteEvent") or d:IsA("BindableEvent") or d:IsA("BindableFunction") then
            out[#out + 1] = path(d) .. " [" .. d.ClassName .. "]"
            if #out >= 250 then break end
        end
    end
    return #out > 0 and table.concat(out, "\n") or "no remotes visible"
end

Tools.list_scripts = function(a)
    local root = resolve(a.root) or game
    local out = {}
    for _, d in ipairs(root:GetDescendants()) do
        if d:IsA("LocalScript") or d:IsA("ModuleScript") then
            out[#out + 1] = path(d) .. " [" .. d.ClassName .. "]"
            if #out >= 250 then break end
        end
    end
    return #out > 0 and table.concat(out, "\n") or "no scripts visible"
end

Tools.read_script = function(a)
    local s, err = resolve(a.path)
    if not s then return err end
    if decompile then
        local ok, src = pcall(decompile, s)
        if ok and src and src ~= "" then return clip(src) end
    end
    local ok, src = pcall(function() return s.Source end)
    if ok and src and src ~= "" then return clip(src) end
    return "could not read source (no decompiler or protected)"
end

Tools.player_info = function()
    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    local tools = {}
    for _, t in ipairs(LocalPlayer.Backpack:GetChildren()) do tools[#tools + 1] = t.Name end
    return table.concat({
        "Player: " .. LocalPlayer.Name .. " (UserId " .. LocalPlayer.UserId .. ")",
        "PlaceId: " .. game.PlaceId,
        "Character: " .. (char and char.Name or "none"),
        hum and ("WalkSpeed " .. hum.WalkSpeed .. " | JumpPower " .. hum.JumpPower .. " | JumpHeight " .. hum.JumpHeight .. " | Health " .. hum.Health .. "/" .. hum.MaxHealth) or "No humanoid",
        hrp and ("Position: " .. ser(hrp.Position)) or "",
        "Backpack: " .. (#tools > 0 and table.concat(tools, ", ") or "empty"),
    }, "\n")
end

Tools.spy_start = function() return startSpy() end
Tools.spy_stop = function() return stopSpy() end
Tools.clear_remote_log = function() Spy.log = {} return "remote log cleared" end

Tools.get_remote_log = function(a)
    local f = tostring(a.filter or ""):lower()
    local limit = math.clamp(tonumber(a.limit) or 40, 1, 150)
    local out = {}
    for i = #Spy.log, 1, -1 do
        local e = Spy.log[i]
        if f == "" or e.key:lower():find(f, 1, true) then
            table.insert(out, 1, string.format("[%.1fs] %s%s", e.t, e.key, e.n > 1 and (" (x" .. e.n .. ")") or ""))
            if #out >= limit then break end
        end
    end
    local head = "spy " .. (Spy.on and "ON" or "OFF") .. ", " .. #Spy.log .. " events stored"
    if #out == 0 then
        return head .. "\nno matching events" .. (Spy.on and "" or " (call spy_start first, then have the user trigger the action)")
    end
    return head .. "\n" .. table.concat(out, "\n")
end

Tools.run_lua = function(a)
    local rec, out = runCode(tostring(a.code or ""), a.name)
    return out
end

Tools.list_running = function()
    local out = {}
    for id = 1, nextId do
        local r = Running[id]
        if r then
            local tail = {}
            for i = math.max(1, #r.logs - 4), #r.logs do tail[#tail + 1] = r.logs[i] end
            out[#out + 1] = "#" .. id .. " " .. r.name .. " [" .. r.state .. "]" .. (#tail > 0 and ("\n  " .. table.concat(tail, "\n  ")) or "")
        end
    end
    return #out > 0 and table.concat(out, "\n") or "no scripts have been run"
end

Tools.stop_script = function(a)
    local id = tonumber(a.id)
    if not id then return "id required" end
    local ok, msg = stopScript(id)
    return ok and ("script #" .. id .. " stopped and cleaned up") or msg
end

local S = "string"
local function fn(name, desc, props, required)
    return {
        type = "function",
        ["function"] = {
            name = name,
            description = desc,
            parameters = {
                type = "object",
                properties = props or { reason = { type = S, description = "optional, can be left out" } },
                required = required,
            },
        },
    }
end

local ToolSpecs = {
    fn("overview", "Quick summary of the game: services, counts, remotes, scripts, executor features."),
    fn("explore", "Dex-style tree of an instance's children. Paths: Workspace, ReplicatedStorage.Remotes, Players.LocalPlayer.PlayerGui, Players.LocalPlayer.Character. Empty path = game.", { path = { type = S }, depth = { type = "integer", description = "1-6, default 1" } }),
    fn("find", "Search descendants by partial name; className may be a base class like BasePart or GuiButton.", { query = { type = S }, className = { type = S }, root = { type = S } }, { "query" }),
    fn("inspect", "Full details of one instance: class, counts, attributes, tags and key properties.", { path = { type = S } }, { "path" }),
    fn("get_properties", "Read specific properties of an instance (omit names for sensible defaults).", { path = { type = S }, names = { type = "array", items = { type = S } } }, { "path" }),
    fn("list_remotes", "List all RemoteEvent/RemoteFunction/Bindable instances visible to the client.", { root = { type = S } }),
    fn("list_scripts", "List LocalScripts and ModuleScripts under a root.", { root = { type = S } }),
    fn("read_script", "Decompile/read a script's source.", { path = { type = S } }, { "path" }),
    fn("player_info", "Local player, character, humanoid stats, backpack."),
    fn("spy_start", "Start capturing remote traffic: outgoing FireServer/InvokeServer and incoming OnClientEvent."),
    fn("spy_stop", "Stop capturing remote traffic."),
    fn("get_remote_log", "Read captured remote events as ready-to-use Lua calls. Repeated identical calls are collapsed (xN).", { filter = { type = S, description = "substring of remote path/args" }, limit = { type = "integer" } }),
    fn("clear_remote_log", "Clear the captured remote log."),
    fn("run_lua", "Execute Lua on the client. The script can use print(), cleanup(function() ... end) to register undo code, and track(connection_or_instance). Instances it creates and task.spawn threads are tracked automatically. Returns a script id.", { code = { type = S }, name = { type = S, description = "short label" } }, { "code" }),
    fn("list_running", "List scripts started with run_lua and their recent output."),
    fn("stop_script", "Stop a running script and undo it (runs cleanup functions, disconnects, destroys what it created).", { id = { type = "integer" } }, { "id" }),
}

local SYSTEM = [[You are Groq Agent, an assistant running inside a Roblox client as a Lua script. You chat with the user and you create Lua (Luau) scripts for Roblox. Within that scope you do whatever the user asks.

SCOPE
- You only do two things: chat, and create Lua/Luau scripts (UIs, tools, helpers, game modifications written in Lua).
- If the user asks you to create anything that is not a Lua script (Python, JavaScript, C#, websites, images, essays, documents, anything unrelated), deny it. Say briefly that you are only for Lua scripting and chatting, and offer a Lua alternative if one exists.
- Normal conversation is always fine.

HOW TO WORK
- Inspect before building. Use overview, explore, find, inspect, list_remotes, list_scripts and read_script to learn the real names and structure. Never invent paths or remote names, check them first.
- To learn what a remote sends: call spy_start, ask the user to perform the action in game, then call get_remote_log (use filter to narrow). The log shows calls as ready-to-use Lua.
- Build with run_lua. Read the result, fix errors and retry. If a script keeps running, it has an id; use list_running to check it and stop_script to stop and undo it.
- Inside run_lua code you have print(), cleanup(fn) and track(x). Always register cleanup(function() ... end) that restores anything you changed (for example the original WalkSpeed) and disconnects connections, so stopping the script fully undoes it. Instances you create are destroyed automatically on stop.
- For UIs: modern glass look (UICorner, UIStroke, semi-transparent dark background, gradients), draggable, works on mobile and PC, parented to gethui() or CoreGui.
- After a script works, include the final script in your reply inside a ```lua block so the user can copy it.
- Keep chat replies short. Do not paste huge tool outputs back. Be honest about errors and limits (for example when the executor lacks a function).
- Reply in the same language the user writes in.]]

------------------------------------------------------------------
-- Groq API
------------------------------------------------------------------
local history = {}
local setTitle -- defined in the UI section below

local function trimHistory()
    while #history > Config.MaxHistory do
        local nextUser
        for i = 2, #history do
            if history[i].role == "user" then nextUser = i break end
        end
        if not nextUser then break end
        for _ = 1, nextUser - 1 do table.remove(history, 1) end
    end
end

local function buildBody(model)
    local msgs = { { role = "system", content = SYSTEM } }
    for _, m in ipairs(history) do msgs[#msgs + 1] = m end
    return HttpService:JSONEncode({
        model = model,
        messages = msgs,
        tools = ToolSpecs,
        tool_choice = "auto",
        temperature = Config.Temperature,
        max_completion_tokens = Config.MaxTokens,
    })
end

local function groq()
    if not httpRequest then return nil, "No HTTP request function in this executor." end
    local model = Config.Model
    local fellBack = false
    local lastErr = "request failed"

    for attempt = 1, 6 do
        local ok, res = pcall(httpRequest, {
            Url = Config.Endpoint,
            Method = "POST",
            Headers = {
                ["Content-Type"] = "application/json",
                ["Accept"] = "application/json",
                ["User-Agent"] = "Mozilla/5.0 (Linux; Android 13) GroqAgent/1.1",
                Authorization = "Bearer " .. Config.ApiKey,
            },
            Body = buildBody(model), -- uses the current Config.MaxTokens
        })
        if not ok then return nil, "request error: " .. tostring(res) end

        local status = res.StatusCode
        local raw = tostring(res.Body or "")
        local dok, data = pcall(HttpService.JSONDecode, HttpService, raw)

        if dok and type(data) == "table" and data.choices and data.choices[1] and data.choices[1].message then
            if fellBack then
                Config.Model = model -- keep using the model that works
                task.defer(setTitle)
            end
            return data.choices[1].message
        end

        local apiMsg = (dok and type(data) == "table" and type(data.error) == "table" and data.error.message) or raw:sub(1, 160)
        if apiMsg == "" then apiMsg = tostring(res.StatusMessage or "no response body") end
        lastErr = "HTTP " .. tostring(status) .. " (" .. model .. "): " .. tostring(apiMsg)

        -- 403 / 404 on the main model: try the fallback model once
        if (status == 403 or status == 404) and not fellBack and model ~= Config.Fallback then
            fellBack = true
            model = Config.Fallback
            continue
        end

        -- 429 "Request too large": output-token limit of your Groq tier is too small
        if status == 429 and tostring(apiMsg):lower():find("too large", 1, true) then
            local lim = tonumber(tostring(apiMsg):match("Limit (%d+)"))
            if Config.MaxTokens > 300 then
                local target = lim and math.floor(lim * 0.5) or 4096
                Config.MaxTokens = math.max(256, math.min(math.floor(Config.MaxTokens / 2), target))
                continue
            elseif not fellBack and model ~= Config.Fallback then
                fellBack = true
                model = Config.Fallback
                continue
            end
        end

        local retry = status == 429 or (status and status >= 500) or tostring(apiMsg):find("Failed to call a function", 1, true)
        if retry and attempt < 6 then
            task.wait(2 * attempt)
        else
            if status == 403 then
                lastErr ..= "\nGroq is blocking this request. Usually your network/IP/region: turn off VPN, switch between data and WiFi, or check the key at console.groq.com."
            elseif status == 401 then
                lastErr ..= "\nInvalid API key. Re-paste it with the key button."
            end
            return nil, lastErr
        end
    end
    return nil, lastErr
end

local function clean(text)
    if type(text) ~= "string" then return "" end
    text = text:gsub("<think>.-</think>", ""):gsub("^%s+", ""):gsub("%s+$", "")
    return text
end

------------------------------------------------------------------
-- UI
------------------------------------------------------------------
local parent = (gethui and gethui()) or CoreGui
local old = parent:FindFirstChild("GroqAgentUI")
if old then old:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "GroqAgentUI"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.IgnoreGuiInset = true
if syn and syn.protect_gui then pcall(syn.protect_gui, gui) end
gui.Parent = parent

local C = {
    bg = Color3.fromRGB(16, 18, 30),
    accent = Color3.fromRGB(124, 108, 255),
    accent2 = Color3.fromRGB(56, 189, 248),
    text = Color3.fromRGB(235, 238, 250),
    sub = Color3.fromRGB(150, 158, 185),
    red = Color3.fromRGB(248, 113, 113),
    green = Color3.fromRGB(74, 222, 128),
}

local function corner(o, r) local c = Instance.new("UICorner") c.CornerRadius = UDim.new(0, r) c.Parent = o return c end
local function stroke(o, t, col) local s = Instance.new("UIStroke") s.Color = col or Color3.new(1, 1, 1) s.Transparency = t or 0.85 s.Thickness = 1 s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border s.Parent = o return s end
local function pad(o, p) local u = Instance.new("UIPadding") u.PaddingTop = UDim.new(0, p) u.PaddingBottom = UDim.new(0, p) u.PaddingLeft = UDim.new(0, p) u.PaddingRight = UDim.new(0, p) u.Parent = o return u end
local function grad(o, c1, c2, rot) local g = Instance.new("UIGradient") g.Color = ColorSequence.new(c1, c2) g.Rotation = rot or 45 g.Parent = o return g end

local main = Instance.new("Frame")
main.Name = "Main"
main.AnchorPoint = Vector2.new(0.5, 0.5)
main.Position = UDim2.fromScale(0.5, 0.5)
main.Size = isMobile and UDim2.new(0.94, 0, 0.88, 0) or UDim2.fromOffset(480, 580)
main.BackgroundColor3 = C.bg
main.BackgroundTransparency = 0.06
main.BorderSizePixel = 0
main.ClipsDescendants = true
main.Parent = gui
corner(main, 20)
stroke(main, 0.8)
local mainGrad = grad(main, Color3.fromRGB(40, 36, 80), Color3.fromRGB(14, 20, 34), 60)
mainGrad.Transparency = NumberSequence.new(0, 0.12)
local cons = Instance.new("UISizeConstraint")
cons.MaxSize = Vector2.new(560, 700)
cons.MinSize = Vector2.new(280, 320)
cons.Parent = main

-- header
local header = Instance.new("Frame")
header.Size = UDim2.new(1, 0, 0, 52)
header.BackgroundTransparency = 1
header.Parent = main

local dot = Instance.new("Frame")
dot.Size = UDim2.fromOffset(10, 10)
dot.Position = UDim2.new(0, 18, 0.5, -5)
dot.BackgroundColor3 = C.accent2
dot.BorderSizePixel = 0
dot.Parent = header
corner(dot, 5)
grad(dot, C.accent, C.accent2, 45)

local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1
title.Position = UDim2.fromOffset(36, 0)
title.Size = UDim2.new(1, -226, 1, 0)
title.Font = Enum.Font.GothamBold
title.TextSize = 15
title.TextColor3 = C.text
title.TextXAlignment = Enum.TextXAlignment.Left
title.RichText = true
title.TextTruncate = Enum.TextTruncate.AtEnd
title.Parent = header
function setTitle()
    title.Text = "Groq Agent" .. (isMobile and "" or ("  <font size='11' color='#9ea6c0'>" .. Config.Model .. "</font>"))
end
setTitle()

local function hbtn(txt, x)
    local b = Instance.new("TextButton")
    b.Size = UDim2.fromOffset(30, 30)
    b.AnchorPoint = Vector2.new(1, 0.5)
    b.Position = UDim2.new(1, x, 0.5, 0)
    b.BackgroundColor3 = Color3.new(1, 1, 1)
    b.BackgroundTransparency = 0.9
    b:SetAttribute("rest", 0.9)
    b.Text = txt
    b.Font = Enum.Font.GothamBold
    b.TextSize = 14
    b.TextColor3 = C.text
    b.AutoButtonColor = false
    b.Parent = header
    corner(b, 10)
    b.MouseEnter:Connect(function() TweenService:Create(b, TweenInfo.new(0.15), { BackgroundTransparency = 0.75 }):Play() end)
    b.MouseLeave:Connect(function() TweenService:Create(b, TweenInfo.new(0.15), { BackgroundTransparency = b:GetAttribute("rest") }):Play() end)
    return b
end
local closeBtn = hbtn("✕", -10)
local minBtn = hbtn("–", -44)
local copyBtn = hbtn("⧉", -78)
local clearBtn = hbtn("⟲", -112)
local keyBtn = hbtn("🔑", -146)
local spyBtn = hbtn("📡", -180)

local divider = Instance.new("Frame")
divider.Position = UDim2.fromOffset(0, 52)
divider.Size = UDim2.new(1, 0, 0, 1)
divider.BackgroundColor3 = Color3.new(1, 1, 1)
divider.BackgroundTransparency = 0.9
divider.BorderSizePixel = 0
divider.Parent = main

-- chat area
local scroll = Instance.new("ScrollingFrame")
scroll.Position = UDim2.fromOffset(0, 53)
scroll.Size = UDim2.new(1, 0, 1, -127)
scroll.BackgroundTransparency = 1
scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = 3
scroll.ScrollBarImageColor3 = C.accent
scroll.ScrollingDirection = Enum.ScrollingDirection.Y
scroll.ElasticBehavior = Enum.ElasticBehavior.Never
scroll.CanvasSize = UDim2.new()
scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
scroll.Parent = main
pad(scroll, 12)
local list = Instance.new("UIListLayout")
list.Padding = UDim.new(0, 10)
list.SortOrder = Enum.SortOrder.LayoutOrder
list.Parent = scroll

local order = 0
local lastCode = ""

local function toBottom()
    task.defer(function()
        scroll.CanvasPosition = Vector2.new(0, math.max(0, scroll.AbsoluteCanvasSize.Y - scroll.AbsoluteSize.Y))
    end)
end

local function esc(s)
    return (s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

local function inline(raw)
    local s = esc(raw)
    s = s:gsub("`([^`\n]+)`", "<font face='Code' color='#a5f3fc'>%1</font>")
    s = s:gsub("%*%*(.-)%*%*", "<b>%1</b>")
    s = s:gsub("\n#+ ([^\n]+)", "\n<b>%1</b>")
    s = s:gsub("^#+ ([^\n]+)", "<b>%1</b>")
    return s
end

local function row(role)
    order += 1
    local r = Instance.new("Frame")
    r.LayoutOrder = order
    r.BackgroundTransparency = 1
    r.AutomaticSize = Enum.AutomaticSize.Y
    r.Size = UDim2.new(1, 0, 0, 0)
    r.Parent = scroll
    local l = Instance.new("UIListLayout")
    l.HorizontalAlignment = role == "user" and Enum.HorizontalAlignment.Right or Enum.HorizontalAlignment.Left
    l.Parent = r
    return r
end

local function bubble(role)
    local isUser = role == "user"
    local f = Instance.new("Frame")
    f.AutomaticSize = Enum.AutomaticSize.Y
    f.Size = UDim2.new(isUser and 0.85 or 1, 0, 0, 0)
    f.BackgroundColor3 = isUser and C.accent or Color3.new(1, 1, 1)
    f.BackgroundTransparency = isUser and 0.2 or 0.93
    f.BorderSizePixel = 0
    f.Parent = row(role)
    corner(f, 14)
    stroke(f, isUser and 0.7 or 0.88)
    pad(f, 10)
    local l = Instance.new("UIListLayout")
    l.Padding = UDim.new(0, 8)
    l.SortOrder = Enum.SortOrder.LayoutOrder
    l.Parent = f
    return f
end

local function label(parentFrame, text, color, size)
    local t = Instance.new("TextLabel")
    t.BackgroundTransparency = 1
    t.AutomaticSize = Enum.AutomaticSize.Y
    t.Size = UDim2.new(1, 0, 0, 0)
    t.Font = Enum.Font.Gotham
    t.TextSize = size or 14
    t.TextColor3 = color or C.text
    t.TextXAlignment = Enum.TextXAlignment.Left
    t.TextYAlignment = Enum.TextYAlignment.Top
    t.TextWrapped = true
    t.RichText = true
    t.Text = text
    t.Parent = parentFrame
    return t
end

local function typeOut(lbl)
    local total = utf8.len(lbl.ContentText) or #lbl.ContentText
    if not Config.Typewriter or total > 3000 then return end
    lbl.MaxVisibleGraphemes = 0
    local step = math.max(3, math.ceil(total / 70))
    local i, n = 0, 0
    while i < total and lbl.Parent do
        i += step
        n += 1
        lbl.MaxVisibleGraphemes = i
        if n % 5 == 0 then toBottom() end
        task.wait(0.025)
    end
    lbl.MaxVisibleGraphemes = -1
    toBottom()
end

local addChip -- forward declaration

local function codeBlock(parentFrame, code, layoutOrder)
    code = code:gsub("^\n+", ""):gsub("\n+$", "")
    lastCode = code
    local box = Instance.new("Frame")
    box.LayoutOrder = layoutOrder
    box.AutomaticSize = Enum.AutomaticSize.Y
    box.Size = UDim2.new(1, 0, 0, 0)
    box.BackgroundColor3 = Color3.fromRGB(6, 8, 16)
    box.BackgroundTransparency = 0.12
    box.BorderSizePixel = 0
    box.Parent = parentFrame
    corner(box, 10)
    stroke(box, 0.85)
    local bl = Instance.new("UIListLayout")
    bl.SortOrder = Enum.SortOrder.LayoutOrder
    bl.Parent = box

    local top = Instance.new("Frame")
    top.LayoutOrder = 1
    top.Size = UDim2.new(1, 0, 0, 32)
    top.BackgroundTransparency = 1
    top.Parent = box
    local tl = Instance.new("TextLabel")
    tl.BackgroundTransparency = 1
    tl.Position = UDim2.fromOffset(12, 0)
    tl.Size = UDim2.new(0.3, 0, 1, 0)
    tl.Font = Enum.Font.GothamMedium
    tl.TextSize = 11
    tl.TextColor3 = C.sub
    tl.TextXAlignment = Enum.TextXAlignment.Left
    tl.Text = "lua"
    tl.Parent = top

    local function cbtn(txt, x)
        local b = Instance.new("TextButton")
        b.AnchorPoint = Vector2.new(1, 0.5)
        b.Position = UDim2.new(1, x, 0.5, 0)
        b.Size = UDim2.fromOffset(60, 24)
        b.BackgroundColor3 = Color3.new(1, 1, 1)
        b.BackgroundTransparency = 0.88
        b.Text = txt
        b.Font = Enum.Font.GothamBold
        b.TextSize = 12
        b.TextColor3 = C.text
        b.AutoButtonColor = false
        b.Parent = top
        corner(b, 8)
        return b
    end
    local copy = cbtn("Copy", -8)
    local run = cbtn("Run", -74)

    local tb = Instance.new("TextBox")
    tb.LayoutOrder = 2
    tb.AutomaticSize = Enum.AutomaticSize.Y
    tb.Size = UDim2.new(1, 0, 0, 0)
    tb.BackgroundTransparency = 1
    tb.TextEditable = false
    tb.ClearTextOnFocus = false
    tb.MultiLine = true
    tb.Font = Enum.Font.Code
    tb.TextSize = 13
    tb.TextColor3 = Color3.fromRGB(165, 243, 252)
    tb.TextXAlignment = Enum.TextXAlignment.Left
    tb.TextYAlignment = Enum.TextYAlignment.Top
    tb.TextWrapped = true
    tb.RichText = false
    tb.Text = #code > 15000 and (code:sub(1, 15000) .. "\n...[display truncated, Copy has everything]") or code
    tb.Parent = box
    local tp = Instance.new("UIPadding")
    tp.PaddingLeft = UDim.new(0, 12)
    tp.PaddingRight = UDim.new(0, 12)
    tp.PaddingBottom = UDim.new(0, 10)
    tp.Parent = tb

    copy.MouseButton1Click:Connect(function()
        if setclipboard then
            setclipboard(code)
            copy.Text = "Copied ✓"
        else
            copy.Text = "Hold code"
        end
        task.delay(1.2, function() if copy.Parent then copy.Text = "Copy" end end)
    end)
    run.MouseButton1Click:Connect(function()
        task.spawn(function()
            local rec, report = runCode(code, "your script")
            if not rec then addChip(report, C.red) end
        end)
    end)
end

local function addUser(text)
    local b = bubble("user")
    label(b, esc(text))
    toBottom()
end

local function addAI(text)
    local b = bubble("ai")
    local n = 0
    local function textSeg(seg)
        seg = seg:gsub("^\n+", ""):gsub("\n+$", "")
        if seg == "" then return end
        local i = 1
        while i <= #seg do
            local j = math.min(i + 11000, #seg)
            if j < #seg then
                local nl = seg:sub(i, j):match(".*()\n")
                if nl and nl > 2000 then j = i + nl - 1 end
            end
            n += 1
            local l = label(b, inline(seg:sub(i, j)))
            l.LayoutOrder = n
            typeOut(l)
            i = j + 1
        end
    end
    local pos = 1
    while true do
        local s, e = text:find("```", pos, true)
        if not s then textSeg(text:sub(pos)) break end
        textSeg(text:sub(pos, s - 1))
        local ce = text:find("```", e + 1, true)
        local body = text:sub(e + 1, ce and (ce - 1) or #text)
        body = (body:gsub("^[%w_]*\n", ""))
        n += 1
        codeBlock(b, body, n)
        toBottom()
        if not ce then break end
        pos = ce + 3
    end
    if n == 0 then
        n += 1
        label(b, "(empty)").LayoutOrder = n
    end
    toBottom()
end

function addChip(text, color)
    order += 1
    local c = Instance.new("TextLabel")
    c.LayoutOrder = order
    c.AutomaticSize = Enum.AutomaticSize.XY
    c.BackgroundColor3 = color or C.accent2
    c.BackgroundTransparency = 0.88
    c.Font = Enum.Font.Code
    c.TextSize = 12
    c.TextColor3 = color or C.accent2
    c.Text = text
    c.TextWrapped = true
    c.TextXAlignment = Enum.TextXAlignment.Left
    c.Size = UDim2.new(0, 0, 0, 0)
    c.Parent = scroll
    corner(c, 8)
    pad(c, 6)
    local sz = Instance.new("UISizeConstraint")
    sz.MaxSize = Vector2.new(420, 1e4)
    sz.Parent = c
    toBottom()
    return c
end

-- input bar
local bar = Instance.new("Frame")
bar.AnchorPoint = Vector2.new(0, 1)
bar.Position = UDim2.new(0, 12, 1, -12)
bar.Size = UDim2.new(1, -24, 0, 46)
bar.BackgroundColor3 = Color3.new(1, 1, 1)
bar.BackgroundTransparency = 0.9
bar.BorderSizePixel = 0
bar.Parent = main
corner(bar, 16)
local barStroke = stroke(bar, 0.85)

local input = Instance.new("TextBox")
input.BackgroundTransparency = 1
input.Position = UDim2.fromOffset(14, 0)
input.Size = UDim2.new(1, -66, 1, 0)
input.Font = Enum.Font.Gotham
input.TextSize = 14
input.TextColor3 = C.text
input.PlaceholderText = "Ask me to build a Lua script..."
input.PlaceholderColor3 = C.sub
input.TextXAlignment = Enum.TextXAlignment.Left
input.ClearTextOnFocus = false
input.Text = ""
input.Parent = bar

local send = Instance.new("TextButton")
send.AnchorPoint = Vector2.new(1, 0.5)
send.Position = UDim2.new(1, -7, 0.5, 0)
send.Size = UDim2.fromOffset(36, 32)
send.BackgroundColor3 = C.accent
send.Text = "➤"
send.TextColor3 = Color3.new(1, 1, 1)
send.TextSize = 15
send.Font = Enum.Font.GothamBold
send.AutoButtonColor = false
send.Parent = bar
corner(send, 11)
grad(send, C.accent, C.accent2, 30)

input.Focused:Connect(function() TweenService:Create(barStroke, TweenInfo.new(0.2), { Transparency = 0.3, Color = C.accent }):Play() end)
input.FocusLost:Connect(function() TweenService:Create(barStroke, TweenInfo.new(0.2), { Transparency = 0.85, Color = Color3.new(1, 1, 1) }):Play() end)

-- key / settings panel
local keyPanel = Instance.new("Frame")
keyPanel.Visible = false
keyPanel.ZIndex = 5
keyPanel.Position = UDim2.fromOffset(12, 62)
keyPanel.Size = UDim2.new(1, -24, 0, 186)
keyPanel.BackgroundColor3 = Color3.fromRGB(10, 12, 22)
keyPanel.BackgroundTransparency = 0.03
keyPanel.BorderSizePixel = 0
keyPanel.Parent = main
corner(keyPanel, 14)
stroke(keyPanel, 0.75)
pad(keyPanel, 10)
local kl = Instance.new("UIListLayout")
kl.Padding = UDim.new(0, 6)
kl.SortOrder = Enum.SortOrder.LayoutOrder
kl.Parent = keyPanel

local function kLabel(t, o)
    local l = label(keyPanel, t, C.sub, 12)
    l.AutomaticSize = Enum.AutomaticSize.None
    l.Size = UDim2.new(1, 0, 0, 16)
    l.LayoutOrder = o
    return l
end
local function kBox(ph, o)
    local t = Instance.new("TextBox")
    t.LayoutOrder = o
    t.Size = UDim2.new(1, 0, 0, 34)
    t.BackgroundColor3 = Color3.new(1, 1, 1)
    t.BackgroundTransparency = 0.9
    t.Font = Enum.Font.Code
    t.TextSize = 13
    t.TextColor3 = C.text
    t.PlaceholderText = ph
    t.PlaceholderColor3 = C.sub
    t.ClearTextOnFocus = false
    t.TextXAlignment = Enum.TextXAlignment.Left
    t.ClipsDescendants = true
    t.Text = ""
    t.Parent = keyPanel
    corner(t, 10)
    local p = Instance.new("UIPadding")
    p.PaddingLeft = UDim.new(0, 10)
    p.PaddingRight = UDim.new(0, 10)
    p.Parent = t
    return t
end
kLabel("Groq API key", 1)
local keyBox = kBox(Config.ApiKey ~= "" and "Key saved. Paste a new one to replace" or "Paste your key (gsk_...)", 2)
kLabel("Model", 3)
local modelBox = kBox("qwen/qwen3.8-27b", 4)
modelBox.Text = Config.Model
local saveBtn = Instance.new("TextButton")
saveBtn.LayoutOrder = 5
saveBtn.Size = UDim2.new(1, 0, 0, 34)
saveBtn.BackgroundColor3 = C.accent
saveBtn.Text = "Save"
saveBtn.Font = Enum.Font.GothamBold
saveBtn.TextSize = 14
saveBtn.TextColor3 = Color3.new(1, 1, 1)
saveBtn.AutoButtonColor = false
saveBtn.Parent = keyPanel
corner(saveBtn, 10)
grad(saveBtn, C.accent, C.accent2, 30)
saveBtn.MouseButton1Click:Connect(function()
    local k = keyBox.Text:gsub("[%s\"']", "")
    if k ~= "" then Config.ApiKey = k end
    local m = modelBox.Text:gsub("[%s\"']", "")
    if m ~= "" then Config.Model = m end
    saveSettings()
    setTitle()
    keyBox.Text = ""
    keyBox.PlaceholderText = "Key saved. Paste a new one to replace"
    keyPanel.Visible = false
    addChip(Config.ApiKey ~= "" and ("✓ saved · " .. Config.Model) or "No key set yet", C.accent2)
end)
keyBtn.MouseButton1Click:Connect(function() keyPanel.Visible = not keyPanel.Visible end)

-- floating orb (minimized)
local orb = Instance.new("TextButton")
orb.Size = UDim2.fromOffset(52, 52)
orb.Position = UDim2.new(0, 20, 0.5, -26)
orb.BackgroundColor3 = C.accent
orb.BackgroundTransparency = 0.15
orb.Text = "✦"
orb.TextSize = 22
orb.TextColor3 = Color3.new(1, 1, 1)
orb.Font = Enum.Font.GothamBold
orb.AutoButtonColor = false
orb.Visible = false
orb.Parent = gui
corner(orb, 26)
stroke(orb, 0.6)
grad(orb, C.accent, C.accent2, 45)

-- dragging
local function makeDraggable(handle, target, onTap)
    local dragging, start, startPos, moved
    handle.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dragging, moved = true, false
            start, startPos = i.Position, target.Position
            i.Changed:Connect(function()
                if i.UserInputState == Enum.UserInputState.End then
                    dragging = false
                    if onTap and not moved then onTap() end
                end
            end)
        end
    end)
    UserInputService.InputChanged:Connect(function(i)
        if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
            local d = i.Position - start
            if d.Magnitude > 4 then moved = true end
            target.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end)
end
makeDraggable(header, main)
makeDraggable(orb, orb, function() orb.Visible = false main.Visible = true end)

minBtn.MouseButton1Click:Connect(function() main.Visible = false orb.Visible = true end)
closeBtn.MouseButton1Click:Connect(function() gui:Destroy() end)
copyBtn.MouseButton1Click:Connect(function()
    if setclipboard and lastCode ~= "" then
        setclipboard(lastCode)
        copyBtn.Text = "✓"
        task.delay(1, function() copyBtn.Text = "⧉" end)
    end
end)
clearBtn.MouseButton1Click:Connect(function()
    history = {}
    for _, c in ipairs(scroll:GetChildren()) do
        if not c:IsA("UIListLayout") and not c:IsA("UIPadding") then c:Destroy() end
    end
    addChip("conversation cleared", C.sub)
end)

-- spy button
onSpyChange = function()
    spyBtn:SetAttribute("rest", Spy.on and 0.45 or 0.9)
    spyBtn.BackgroundColor3 = Spy.on and C.green or Color3.new(1, 1, 1)
    spyBtn.BackgroundTransparency = Spy.on and 0.45 or 0.9
end
spyBtn.MouseButton1Click:Connect(function()
    if Spy.on then
        addChip("📡 " .. stopSpy(), C.sub)
    else
        addChip("📡 " .. startSpy(), C.green)
    end
end)
onSpyChange()

-- running script rows with Stop button
onScriptEvent = function(kind, rec, info)
    if kind == "start" then
        order += 1
        local f = Instance.new("Frame")
        f.LayoutOrder = order
        f.Size = UDim2.new(1, 0, 0, 36)
        f.BackgroundColor3 = C.accent2
        f.BackgroundTransparency = 0.88
        f.BorderSizePixel = 0
        f.Parent = scroll
        corner(f, 10)
        local l = Instance.new("TextLabel")
        l.BackgroundTransparency = 1
        l.Position = UDim2.fromOffset(12, 0)
        l.Size = UDim2.new(1, -84, 1, 0)
        l.Font = Enum.Font.Code
        l.TextSize = 12
        l.TextColor3 = C.accent2
        l.TextXAlignment = Enum.TextXAlignment.Left
        l.TextTruncate = Enum.TextTruncate.AtEnd
        l.Text = "▶ #" .. rec.id .. " " .. rec.name
        l.Parent = f
        local b = Instance.new("TextButton")
        b.AnchorPoint = Vector2.new(1, 0.5)
        b.Position = UDim2.new(1, -6, 0.5, 0)
        b.Size = UDim2.fromOffset(62, 26)
        b.BackgroundColor3 = C.red
        b.BackgroundTransparency = 0.7
        b.Text = "Stop"
        b.Font = Enum.Font.GothamBold
        b.TextSize = 12
        b.TextColor3 = C.text
        b.AutoButtonColor = false
        b.Parent = f
        corner(b, 8)
        b.MouseButton1Click:Connect(function() stopScript(rec.id) end)
        rec.ui = { label = l, btn = b }
        toBottom()
    elseif rec.ui then
        if kind == "error" then
            rec.ui.label.Text = "✖ #" .. rec.id .. " " .. tostring(info):sub(1, 80)
            rec.ui.label.TextColor3 = C.red
        elseif kind == "stop" then
            rec.ui.label.Text = "■ #" .. rec.id .. " stopped & undone"
            rec.ui.label.TextColor3 = C.sub
            if rec.ui.btn then rec.ui.btn:Destroy() rec.ui.btn = nil end
        end
    end
end

------------------------------------------------------------------
-- Agent loop
------------------------------------------------------------------
local busy = false

local function thinking()
    local chip = addChip("thinking", C.sub)
    local alive = true
    task.spawn(function()
        local n = 0
        while alive and chip.Parent do
            n = n % 3 + 1
            chip.Text = "thinking" .. string.rep(".", n)
            task.wait(0.4)
        end
    end)
    return function()
        alive = false
        if chip.Parent then chip:Destroy() end
    end
end

local function handle(userText)
    history[#history + 1] = { role = "user", content = userText }
    trimHistory()
    local seen = {}

    for _ = 1, Config.MaxToolSteps do
        local stop = thinking()
        local ok, msg, err = pcall(groq)
        stop()
        if not ok then addChip("error: " .. tostring(msg), C.red) return end
        if not msg then addChip("error: " .. tostring(err), C.red) return end

        local text = clean(msg.content)
        local calls = msg.tool_calls
        history[#history + 1] = { role = "assistant", content = text, tool_calls = calls }

        if text ~= "" then addAI(text) end
        if type(calls) ~= "table" or #calls == 0 then return end

        for _, call in ipairs(calls) do
            local f = call["function"] or {}
            local name = f.name or "?"
            local aok, args = pcall(HttpService.JSONDecode, HttpService, (f.arguments and f.arguments ~= "") and f.arguments or "{}")
            if not aok or type(args) ~= "table" then args = {} end

            local argStr = (f.arguments or ""):gsub("%s+", " ")
            if #argStr > 90 then argStr = argStr:sub(1, 90) .. "…" end
            addChip("⚙ " .. name .. " " .. argStr)

            local sig = name .. "|" .. (f.arguments or "")
            seen[sig] = (seen[sig] or 0) + 1
            local res
            if seen[sig] > 2 and name ~= "run_lua" then
                res = "this exact call was already made twice with the same result; try a different approach or answer the user"
            else
                local tool = Tools[name]
                local rok, r = pcall(function()
                    if not tool then return "unknown tool: " .. name end
                    return tool(args)
                end)
                res = clip(rok and r or ("tool error: " .. tostring(r)))
            end
            history[#history + 1] = { role = "tool", tool_call_id = call.id, content = res }
        end
    end
    addChip("stopped: tool step limit reached", Color3.fromRGB(251, 191, 36))
end

local function submit()
    if busy then return end
    local text = input.Text
    if text:gsub("%s", "") == "" then return end
    if Config.ApiKey == "" then
        keyPanel.Visible = true
        addChip("Add your Groq API key first.", C.red)
        return
    end
    input.Text = ""
    busy = true
    send.Text = "…"
    addUser(text)
    task.spawn(function()
        local ok, e = pcall(handle, text)
        if not ok then addChip("error: " .. tostring(e), C.red) end
        busy = false
        send.Text = "➤"
    end)
end

send.MouseButton1Click:Connect(submit)
input.FocusLost:Connect(function(enter) if enter then submit() end end)

-- intro
if Config.ApiKey == "" then keyPanel.Visible = true end
main.BackgroundTransparency = 1
TweenService:Create(main, TweenInfo.new(0.35, Enum.EasingStyle.Quad), { BackgroundTransparency = 0.06 }):Play()
addAI("Hey! I chat and write Lua scripts. I can explore the game, catch remote events (📡), and run or undo scripts.\n\nTry: `make a speed adjustment UI`")