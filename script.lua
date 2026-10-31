--[[
STEAL AN EGG - STANDALONE RECONSTRUCTION (single server script)
Source: uploaded Roblox workspace snapshot dated 2026-10-31.
Install: create ONE Script under ServerScriptService, paste this entire file, then Play.

RECONSTRUCTION FIDELITY:
* 7,434 visible source parts are rebuilt from recorded names, sizes and world positions.
* Seven original plot coordinate layouts, 13 guard-area bounds and 64 egg spawn locations
  are embedded from the uploaded snapshot.
* The dump did NOT include original MeshPart asset IDs, part rotations, full materials/colors,
  UI source, or server module source. Meshes are represented by primitives; rotations and
  some visual properties are approximated. This is a playable standalone game, not a byte-
  exact copy of the original place.

SYSTEMS:
* field egg pickup -> carry -> base incubator -> hatch -> pet display
* server-validated egg/pet stealing, base shields, sell stand, pet inventory and mounting
* 13 biome progression, treadmill speed upgrades, rebirths, daily reward and luck boost
* DataStore persistence + capped offline earnings (enable Studio API access to test saves)

For best performance, enable Workspace.StreamingEnabled in Studio Properties before publishing.
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local DataStoreService = game:GetService("DataStoreService")
local Lighting = game:GetService("Lighting")
local HttpService = game:GetService("HttpService")

local CONFIG = {
    DataStoreName = "StealEggRebuild_Production_v1",
    StartingCash = 500,
    StartingWalkSpeed = 16,
    FieldEggRespawnSeconds = 35,
    HatchSecondsBase = 24,
    IncomeTickSeconds = 5,
    AutosaveSeconds = 120,
    MaxOfflineHours = 4,
    OfflineIncomeRate = 0.20,
    MaxPetInventory = 60,
    MaxDisplayedSlots = 6,
    StealCooldown = 8,
    ShieldToggleCooldown = 5,
    RebirthCash = 500000,
    RebirthSpeed = 40,
    MapBuildYieldEvery = 120,
}

local RANDOM = Random.new()
local DATASTORE = DataStoreService:GetDataStore(CONFIG.DataStoreName)
local WORLD_NAME = "StealAnEgg_Rebuilt"
local previous = Workspace:FindFirstChild(WORLD_NAME)
if previous then previous:Destroy() end

local world = Instance.new("Folder")
world.Name = WORLD_NAME
world.Parent = Workspace
local geometryFolder = Instance.new("Folder")
geometryFolder.Name = "ReconstructedMapGeometry"
geometryFolder.Parent = world
local biomeFolder = Instance.new("Folder")
biomeFolder.Name = "Biomes"
biomeFolder.Parent = world
local eggFolder = Instance.new("Folder")
eggFolder.Name = "FieldEggs"
eggFolder.Parent = world
local baseFolder = Instance.new("Folder")
baseFolder.Name = "PlayerPlots"
baseFolder.Parent = world
local systemFolder = Instance.new("Folder")
systemFolder.Name = "GameSystems"
systemFolder.Parent = world

Lighting.ClockTime = 14
Lighting.Brightness = 2
Lighting.EnvironmentDiffuseScale = 0.35
Lighting.EnvironmentSpecularScale = 0.35

local function v3(textValue)
    local n = string.split(textValue, ",")
    return Vector3.new(tonumber(n[1]) or 0, tonumber(n[2]) or 0, tonumber(n[3]) or 0)
end

local function makePart(parent, name, size, cf, color, material, anchored, collide)
    local part = Instance.new("Part")
    part.Name = name
    part.Size = size
    part.CFrame = cf
    part.Color = color or Color3.fromRGB(120, 120, 120)
    part.Material = material or Enum.Material.SmoothPlastic
    part.Anchored = anchored ~= false
    part.CanCollide = collide == true
    part.CanTouch = false
    part.CanQuery = true
    part.TopSurface = Enum.SurfaceType.Smooth
    part.BottomSurface = Enum.SurfaceType.Smooth
    part.Parent = parent
    return part
end

local function prompt(parent, actionText, objectText, hold, distance)
    local p = Instance.new("ProximityPrompt")
    p.ActionText = actionText
    p.ObjectText = objectText
    p.HoldDuration = hold or 0.3
    p.MaxActivationDistance = distance or 10
    p.RequiresLineOfSight = false
    p.Parent = parent
    return p
end

local function billboard(adornee, text, color, size)
    local gui = Instance.new("BillboardGui")
    gui.Name = "WorldLabel"
    gui.Adornee = adornee
    gui.Size = size or UDim2.fromOffset(210, 48)
    gui.StudsOffset = Vector3.new(0, 3.2, 0)
    gui.AlwaysOnTop = true
    gui.MaxDistance = 180
    gui.Parent = adornee
    local label = Instance.new("TextLabel")
    label.BackgroundTransparency = 1
    label.Size = UDim2.fromScale(1, 1)
    label.Font = Enum.Font.GothamBold
    label.TextScaled = true
    label.TextWrapped = true
    label.TextColor3 = color or Color3.new(1, 1, 1)
    label.TextStrokeColor3 = Color3.new(0, 0, 0)
    label.TextStrokeTransparency = 0.25
    label.Text = text
    label.Parent = gui
    return label
end

local function makeAnchor(parent, name, position)
    local a = makePart(parent, name, Vector3.new(1, 1, 1), CFrame.new(position),
        Color3.new(1, 1, 1), Enum.Material.SmoothPlastic, true, false)
    a.Transparency = 1
    a.CanQuery = false
    return a
end

local function safeNumber(value, fallback, minValue, maxValue)
    local n = tonumber(value)
    if not n or n ~= n then return fallback end
    return math.clamp(n, minValue, maxValue)
end

local function deepCopy(t)
    if type(t) ~= "table" then return t end
    local out = {}
    for k, v in pairs(t) do out[k] = type(v) == "table" and deepCopy(v) or v end
    return out
end

-- Source map geometry table: name | class | nocollide | size xyz | position xyz | source group.
local MAP_DATA = [==[
Sign|Part|1|1,2.83,4.97|466.84,70.38,-353.95|Plots/1
Support|Part|1|1,1.57,1|466.84,68.4,-353.88|Plots/1
Support|Part|1|1,1.57,1|476.52,68.4,-366.07|Plots/1
Sign|Part|1|1,2.83,5.23|476.5,70.38,-366.01|Plots/1
Part|Part|1|10.3,0.6,0.36|376.15,70.37,-390.63|Plots/1
Part|Part|1|10.3,0.6,0.28|376.15,70.37,-390.63|Plots/1
Part|Part|1|10.3,0.6,0.28|386.65,70.37,-390.63|Plots/1
Part|Part|1|10.3,0.6,0.36|386.65,70.37,-390.63|Plots/1
Part|Part|1|10.3,0.6,0.36|397.15,70.37,-390.63|Plots/1
Part|Part|1|10.3,0.6,0.28|397.15,70.37,-390.63|Plots/1
Part|Part|1|10.3,0.6,0.36|407.65,70.37,-390.63|Plots/1
Part|Part|1|10.3,0.6,0.28|407.65,70.37,-390.63|Plots/1
Part|Part|1|10.3,0.6,0.36|418.15,70.37,-390.63|Plots/1
Part|Part|1|10.3,0.6,0.28|418.15,70.37,-390.63|Plots/1
Part|Part|1|10.3,0.6,0.36|428.65,70.37,-390.63|Plots/1
Part|Part|1|10.3,0.6,0.28|428.65,70.37,-390.63|Plots/1
Part|Part|1|10.3,0.6,0.36|439.15,70.37,-390.63|Plots/1
Part|Part|1|10.3,0.6,0.28|439.15,70.37,-390.63|Plots/1
Part|Part|1|10.3,0.6,0.36|449.65,70.37,-390.63|Plots/1
Part|Part|1|10.3,0.6,0.28|449.65,70.37,-390.63|Plots/1
Part|Part|1|10.3,0.6,0.36|460.15,70.37,-390.63|Plots/1
Part|Part|1|10.3,0.6,0.28|460.15,70.37,-390.63|Plots/1
Part|Part|1|10.3,0.6,0.28|465.4,70.37,-385.38|Plots/1
Part|Part|1|10.3,0.6,0.36|465.4,70.37,-385.38|Plots/1
Part|Part|1|10.3,0.6,0.28|465.4,70.37,-374.88|Plots/1
Part|Part|1|10.3,0.6,0.36|465.4,70.37,-374.88|Plots/1
Part|Part|1|10.3,0.6,0.28|465.4,70.37,-353.88|Plots/1
Part|Part|1|10.3,0.6,0.36|465.4,70.37,-353.88|Plots/1
Part|Part|1|10.3,0.6,0.28|465.4,70.37,-343.38|Plots/1
Part|Part|1|10.3,0.6,0.36|465.4,70.37,-343.38|Plots/1
Part|Part|1|10.3,0.6,0.28|460.15,70.37,-338.13|Plots/1
Part|Part|1|10.3,0.6,0.36|460.15,70.37,-338.13|Plots/1
Part|Part|1|10.3,0.6,0.28|449.65,70.37,-338.13|Plots/1
Part|Part|1|10.3,0.6,0.36|449.65,70.37,-338.13|Plots/1
Part|Part|1|10.3,0.6,0.28|439.15,70.37,-338.13|Plots/1
Part|Part|1|10.3,0.6,0.36|439.15,70.37,-338.13|Plots/1
Part|Part|1|10.3,0.6,0.28|428.65,70.37,-338.13|Plots/1
Part|Part|1|10.3,0.6,0.36|428.65,70.37,-338.13|Plots/1
Part|Part|1|10.3,0.6,0.28|418.15,70.37,-338.13|Plots/1
Part|Part|1|10.3,0.6,0.36|418.15,70.37,-338.13|Plots/1
Part|Part|1|10.3,0.6,0.28|407.65,70.37,-338.13|Plots/1
Part|Part|1|10.3,0.6,0.36|407.65,70.37,-338.13|Plots/1
Part|Part|1|10.3,0.6,0.28|397.15,70.37,-338.13|Plots/1
Part|Part|1|10.3,0.6,0.36|397.15,70.37,-338.13|Plots/1
Part|Part|1|10.3,0.6,0.28|386.65,70.37,-338.13|Plots/1
Part|Part|1|10.3,0.6,0.36|386.65,70.37,-338.13|Plots/1
Part|Part|1|10.3,0.6,0.28|376.15,70.37,-338.13|Plots/1
Part|Part|1|10.3,0.6,0.36|376.15,70.37,-338.13|Plots/1
Part|Part|1|10.3,0.6,0.36|350.02,70.37,-343.38|Plots/1
Part|Part|1|10.3,0.6,0.28|350.02,70.37,-343.38|Plots/1
Part|Part|1|10.3,0.6,0.36|350.02,70.37,-353.88|Plots/1
Part|Part|1|10.3,0.6,0.28|350.02,70.37,-353.88|Plots/1
Part|Part|1|10.3,0.6,0.36|350.02,70.37,-364.38|Plots/1
Part|Part|1|10.3,0.6,0.28|350.02,70.37,-364.38|Plots/1
Part|Part|1|10.3,0.6,0.36|350.02,70.37,-374.88|Plots/1
Part|Part|1|10.3,0.6,0.36|350.02,70.37,-385.38|Plots/1
Part|Part|1|10.3,0.6,0.28|350.02,70.37,-385.38|Plots/1
Part|Part|1|10.3,0.6,0.28|350.02,70.37,-374.88|Plots/1
Part|Part|1|10.3,0.6,0.36|365.65,70.37,-390.63|Plots/1
Part|Part|1|10.3,0.6,0.28|365.65,70.37,-390.63|Plots/1
Part|Part|1|10.3,0.6,0.28|365.65,70.37,-338.13|Plots/1
Part|Part|1|10.3,0.6,0.36|365.65,70.37,-338.13|Plots/1
Part|Part|1|10.3,0.6,0.36|355.15,70.37,-390.63|Plots/1
Part|Part|1|10.3,0.6,0.28|355.15,70.37,-390.63|Plots/1
Part|Part|1|10.3,0.6,0.28|355.15,70.37,-338.13|Plots/1
Part|Part|1|10.3,0.6,0.36|355.15,70.37,-338.13|Plots/1
Part|Part|1|1,6.9,1|412.9,70.98,-390.63|Plots/1
Part|Part|1|1,6.9,1|454.9,70.98,-390.63|Plots/1
Part|Part|1|1,6.9,1|465.4,70.98,-369.63|Plots/1
Part|Part|1|9.5,0.6,0.5|350.03,68.38,-374.88|Plots/1
Part|Part|1|1,6.9,1|465.4,70.98,-380.13|Plots/1
Part|Part|1|9.5,0.6,0.5|439.15,68.38,-338.13|Plots/1
Part|Part|1|9.5,0.6,0.5|460.15,68.38,-338.13|Plots/1
Part|Part|1|9.5,0.6,0.5|465.4,72.53,-353.88|Plots/1
Part|Part|1|1,6.9,1|454.9,70.98,-338.13|Plots/1
Part|Part|1|9.5,0.6,0.5|428.65,72.53,-338.13|Plots/1
Part|Part|1|9.5,0.6,0.5|428.65,72.53,-390.63|Plots/1
Part|Part|1|1,6.9,1|444.4,70.98,-390.63|Plots/1
Part|Part|1|9.5,0.6,0.5|449.65,72.53,-390.63|Plots/1
Part|Part|1|1,6.9,1|360.55,70.98,-338.13|Plots/1
Part|Part|1|9.5,0.6,0.5|350.03,72.53,-364.38|Plots/1
Part|Part|1|1,6.9,1|465.4,70.98,-338.13|Plots/1
Part|Part|1|9.5,0.6,0.5|350.03,68.38,-353.88|Plots/1
Part|Part|1|9.5,0.6,0.5|355.36,72.53,-338.13|Plots/1
Part|Part|1|9.5,0.6,0.5|418.15,72.53,-390.63|Plots/1
Part|Part|1|9.5,0.6,0.5|350.03,72.53,-385.38|Plots/1
Part|Part|1|9.5,0.6,0.5|350.03,68.38,-385.38|Plots/1
Part|Part|1|1,6.9,1|465.4,70.98,-390.63|Plots/1
Part|Part|1|9.5,0.6,0.5|460.15,72.53,-390.63|Plots/1
Part|Part|1|9.5,0.6,0.5|460.15,68.38,-390.63|Plots/1
Part|Part|1|9.5,0.6,0.5|465.4,72.53,-374.88|Plots/1
Part|Part|1|9.5,0.6,0.5|465.4,68.38,-374.88|Plots/1
Part|Part|1|9.5,0.6,0.5|350.03,72.53,-374.88|Plots/1
Part|Part|1|1,6.9,1|350.03,70.98,-380.13|Plots/1
Part|Part|1|9.5,0.6,0.5|465.4,72.53,-385.38|Plots/1
Part|Part|1|9.5,0.6,0.5|465.4,68.38,-385.38|Plots/1
Part|Part|1|9.5,0.6,0.5|439.15,72.53,-338.13|Plots/1
Part|Part|1|1,6.9,1|444.4,70.98,-338.13|Plots/1
Part|Part|1|9.5,0.6,0.5|460.15,72.53,-338.13|Plots/1
Part|Part|1|9.5,0.6,0.5|465.4,68.38,-353.88|Plots/1
Part|Part|1|1,6.9,1|465.4,70.98,-359.13|Plots/1
Part|Part|1|9.5,0.6,0.5|449.65,68.38,-338.13|Plots/1
Part|Part|1|9.5,0.6,0.5|449.65,72.53,-338.13|Plots/1
Part|Part|1|9.5,0.6,0.5|428.65,68.38,-338.13|Plots/1
Part|Part|1|1,6.9,1|433.9,70.98,-338.13|Plots/1
Part|Part|1|9.5,0.6,0.5|428.65,68.38,-390.63|Plots/1
Part|Part|1|1,6.9,1|433.9,70.98,-390.63|Plots/1
Part|Part|1|9.5,0.6,0.5|439.15,72.53,-390.63|Plots/1
Part|Part|1|9.5,0.6,0.5|439.15,68.38,-390.63|Plots/1
Part|Part|1|9.5,0.6,0.5|449.65,68.38,-390.63|Plots/1
Part|Part|1|1,6.9,1|350.11,70.98,-338.13|Plots/1
Part|Part|1|1,6.9,1|381.46,70.98,-338.13|Plots/1
Part|Part|1|1,6.9,1|370.95,70.98,-338.13|Plots/1
Part|Part|1|1,6.9,1|402.42,70.98,-338.13|Plots/1
Part|Part|1|1,6.9,1|391.94,70.98,-338.13|Plots/1
Part|Part|1|9.5,0.6,0.5|350.03,72.53,-343.38|Plots/1
Part|Part|1|1,6.9,1|412.9,70.98,-338.13|Plots/1
Part|Part|1|1,6.9,1|350.03,70.98,-348.63|Plots/1
Part|Part|1|9.5,0.6,0.5|350.03,68.38,-343.38|Plots/1
Part|Part|1|9.5,0.6,0.5|350.03,68.38,-364.38|Plots/1
Part|Part|1|1,6.9,1|350.03,70.98,-369.63|Plots/1
Part|Part|1|9.5,0.6,0.5|465.4,72.53,-343.38|Plots/1
Part|Part|1|1,6.9,1|465.4,70.98,-348.63|Plots/1
Part|Part|1|9.5,0.6,0.5|465.4,68.38,-343.38|Plots/1
Part|Part|1|1,6.9,1|350.03,70.98,-359.13|Plots/1
Part|Part|1|9.5,0.6,0.5|350.03,72.53,-353.88|Plots/1
Part|Part|1|9.5,0.6,0.5|397.19,68.38,-338.13|Plots/1
Part|Part|1|9.5,0.6,0.5|397.19,72.53,-338.13|Plots/1
Part|Part|1|9.5,0.6,0.5|418.15,68.38,-338.13|Plots/1
Part|Part|1|9.5,0.6,0.5|386.71,68.38,-338.13|Plots/1
Part|Part|1|1,6.9,1|423.4,70.98,-338.13|Plots/1
Part|Part|1|9.5,0.6,0.5|365.8,72.53,-338.13|Plots/1
Part|Part|1|9.5,0.6,0.5|355.36,68.38,-338.13|Plots/1
Part|Part|1|9.5,0.6,0.5|376.2,68.38,-338.13|Plots/1
Part|Part|1|9.5,0.6,0.5|365.8,68.38,-338.13|Plots/1
Part|Part|1|9.5,0.6,0.5|407.67,68.38,-338.13|Plots/1
Part|Part|1|9.5,0.6,0.5|418.15,72.53,-338.13|Plots/1
Part|Part|1|9.5,0.6,0.5|376.2,72.53,-338.13|Plots/1
Part|Part|1|9.5,0.6,0.5|386.71,72.53,-338.13|Plots/1
Part|Part|1|9.5,0.6,0.5|407.67,72.53,-338.13|Plots/1
Part|Part|1|1,6.9,1|391.93,70.98,-390.63|Plots/1
Part|Part|1|9.5,0.6,0.5|376.19,68.38,-390.63|Plots/1
Part|Part|1|9.5,0.6,0.5|397.18,72.53,-390.63|Plots/1
Part|Part|1|9.5,0.6,0.5|407.66,68.38,-390.63|Plots/1
Part|Part|1|1,6.9,1|350.1,70.98,-390.63|Plots/1
Part|Part|1|9.5,0.6,0.5|386.7,72.53,-390.63|Plots/1
Part|Part|1|1,6.9,1|402.41,70.98,-390.63|Plots/1
Part|Part|1|9.5,0.6,0.5|397.18,68.38,-390.63|Plots/1
Part|Part|1|1,6.9,1|360.54,70.98,-390.63|Plots/1
Part|Part|1|9.5,0.6,0.5|418.15,68.38,-390.63|Plots/1
Part|Part|1|9.5,0.6,0.5|355.35,72.53,-390.63|Plots/1
Part|Part|1|9.5,0.6,0.5|365.79,72.53,-390.63|Plots/1
Part|Part|1|1,6.9,1|381.45,70.98,-390.63|Plots/1
Part|Part|1|9.5,0.6,0.5|365.79,68.38,-390.63|Plots/1
Part|Part|1|1,6.9,1|423.4,70.98,-390.63|Plots/1
Part|Part|1|9.5,0.6,0.5|355.35,68.38,-390.63|Plots/1
Part|Part|1|1,6.9,1|370.94,70.98,-390.63|Plots/1
Part|Part|1|9.5,0.6,0.5|376.19,72.53,-390.63|Plots/1
Part|Part|1|9.5,0.6,0.5|407.66,72.53,-390.63|Plots/1
Part|Part|1|9.5,0.6,0.5|386.7,68.38,-390.63|Plots/1
Part|Part|1|0.31,0.15,0.37|513.51,67.65,-225.32|Plots/6
Part|Part|1|0.19,0.42,0.28|513.51,67.92,-225.32|Plots/6
Part|Part|1|0.19,0.42,0.28|510.06,67.92,-225.32|Plots/6
Part|Part|1|0.31,0.15,0.37|510.06,67.65,-225.32|Plots/6
Part|Part|1|0.42,0.24,5.62|511.7,68.47,-225.48|Plots/6
Part|Part|1|0.36,0.24,5.38|511.82,71.65,-225.51|Plots/6
Part|Part|1|0.44,3.17,0.24|509,70.18,-225.47|Plots/6
Part|Part|1|0.42,3.42,0.24|514.63,70.06,-225.48|Plots/6
Part|Part|1|0.24,3.9,5.87|511.81,70.07,-225.32|Plots/6
Part|Part|1|0.24,0.24,3.9|514.87,70.07,-225.32|Plots/6
Part|Part|1|0.24,0.24,3.9|508.76,70.07,-225.32|Plots/6
Display|Part|1|5.4,2.93,0.28|511.8,70.06,-225.39|Plots/6
Support|Part|1|1,1.57,1|532.82,68.4,-225.52|Plots/6
Sign|Part|1|1,2.83,4.97|532.75,70.38,-225.52|Plots/6
Sign|Part|1|1,2.83,5.23|539.33,70.38,-233.72|Plots/6
Support|Part|1|1,1.57,1|539.27,68.4,-233.74|Plots/6
Part|Part|1|10.3,0.6,0.36|496.1,70.37,-208.33|Plots/6
Part|Part|1|10.3,0.6,0.28|496.1,70.37,-197.83|Plots/6
Part|Part|1|10.3,0.6,0.36|496.1,70.37,-197.83|Plots/6
Part|Part|1|10.3,0.6,0.28|496.1,70.37,-187.33|Plots/6
Part|Part|1|10.3,0.6,0.36|496.1,70.37,-187.33|Plots/6
Part|Part|1|10.3,0.6,0.28|496.1,70.37,-176.83|Plots/6
Part|Part|1|10.3,0.6,0.36|496.1,70.37,-176.83|Plots/6
Part|Part|1|10.3,0.6,0.28|496.1,70.37,-166.33|Plots/6
Part|Part|1|10.3,0.6,0.36|496.1,70.37,-166.33|Plots/6
Part|Part|1|10.3,0.6,0.28|496.1,70.37,-155.83|Plots/6
Part|Part|1|10.3,0.6,0.36|496.1,70.37,-155.83|Plots/6
Part|Part|1|10.3,0.6,0.36|496.1,70.37,-145.33|Plots/6
Part|Part|1|10.3,0.6,0.28|496.1,70.37,-145.33|Plots/6
Part|Part|1|10.3,0.6,0.28|496.1,70.37,-134.83|Plots/6
Part|Part|1|10.3,0.6,0.36|496.1,70.37,-134.83|Plots/6
Part|Part|1|1,5.4,1|496.07,70.23,-203.08|Plots/6
Part|Part|1|1,4,1|496.07,69.53,-192.58|Plots/6
Part|Part|1|9.5,0.6,0.5|496.07,68.38,-197.83|Plots/6
Part|Part|1|9.5,0.6,0.5|532.82,68.38,-108.71|Plots/6
Part|Part|1|1,5.4,1|527.57,70.23,-108.71|Plots/6
Part|Part|1|1,5.4,1|548.57,70.23,-224.08|Plots/6
Part|Part|1|9.5,0.6,0.5|543.32,68.38,-224.08|Plots/6
Part|Part|1|1,5.4,1|538.07,70.23,-224.08|Plots/6
Part|Part|1|1,5.4,1|548.57,70.23,-192.58|Plots/6
Part|Part|1|9.5,0.6,0.5|548.57,72.53,-187.33|Plots/6
Part|Part|1|9.5,0.6,0.5|522.32,72.53,-108.71|Plots/6
Part|Part|1|1,5.4,1|517.07,70.23,-108.71|Plots/6
Part|Part|1|9.5,0.6,0.5|501.32,72.53,-224.08|Plots/6
Part|Part|1|1,5.4,1|506.57,70.23,-224.08|Plots/6
Part|Part|1|9.5,0.6,0.5|548.57,68.38,-218.83|Plots/6
Part|Part|1|9.5,0.6,0.5|548.57,72.53,-218.83|Plots/6
Part|Part|1|9.5,0.6,0.5|532.82,68.38,-224.08|Plots/6
Part|Part|1|9.5,0.6,0.5|532.82,72.53,-224.08|Plots/6
Part|Part|1|9.5,0.6,0.5|543.32,68.38,-108.71|Plots/6
Part|Part|1|9.5,0.6,0.5|543.32,72.53,-108.71|Plots/6
Part|Part|1|1,5.4,1|548.57,70.23,-108.79|Plots/6
Part|Part|1|1,5.4,1|548.57,70.23,-150.62|Plots/6
Part|Part|1|1,5.4,1|538.07,70.23,-108.71|Plots/6
Part|Part|1|1,5.4,1|548.57,70.23,-171.58|Plots/6
Part|Part|1|1,5.4,1|548.57,70.23,-119.23|Plots/6
Part|Part|1|1,5.4,1|548.57,70.23,-140.14|Plots/6
Part|Part|1|1,5.4,1|548.57,70.23,-161.1|Plots/6
Part|Part|1|9.5,0.6,0.5|496.07,68.38,-208.33|Plots/6
Part|Part|1|1,5.4,1|496.07,70.23,-224.08|Plots/6
Part|Part|1|1,5.4,1|496.07,70.23,-213.58|Plots/6
Part|Part|1|9.5,0.6,0.5|496.07,72.53,-218.83|Plots/6
Part|Part|1|9.5,0.6,0.5|501.32,68.38,-108.71|Plots/6
Part|Part|1|1,5.4,1|496.07,70.23,-171.58|Plots/6
Part|Part|1|1,5.4,1|548.57,70.23,-182.08|Plots/6
Part|Part|1|9.5,0.6,0.5|548.57,68.38,-176.83|Plots/6
Part|Part|1|9.5,0.6,0.5|548.57,72.53,-134.88|Plots/6
Part|Part|1|9.5,0.6,0.5|548.57,68.38,-134.88|Plots/6
Part|Part|1|9.5,0.6,0.5|548.57,68.38,-166.35|Plots/6
Part|Part|1|9.5,0.6,0.5|548.57,68.38,-155.87|Plots/6
Part|Part|1|9.5,0.6,0.5|548.57,72.53,-145.39|Plots/6
Part|Part|1|9.5,0.6,0.5|548.57,72.53,-114.04|Plots/6
Part|Part|1|9.5,0.6,0.5|548.57,72.53,-124.48|Plots/6
Part|Part|1|9.5,0.6,0.5|548.57,72.53,-155.87|Plots/6
Part|Part|1|9.5,0.6,0.5|548.57,72.53,-166.35|Plots/6
Part|Part|1|9.5,0.6,0.5|548.57,68.38,-114.04|Plots/6
Part|Part|1|9.5,0.6,0.5|548.57,68.38,-124.48|Plots/6
Part|Part|1|9.5,0.6,0.5|548.57,68.38,-145.39|Plots/6
Part|Part|1|1,5.4,1|496.07,70.23,-182.08|Plots/6
Part|Part|1|9.5,0.6,0.5|496.07,68.38,-166.33|Plots/6
Part|Part|1|9.5,0.6,0.5|496.07,68.38,-176.83|Plots/6
Part|Part|1|1,5.4,1|496.07,70.23,-129.62|Plots/6
Part|Part|1|9.5,0.6,0.5|496.07,72.53,-166.33|Plots/6
Part|Part|1|9.5,0.6,0.5|496.07,68.38,-124.47|Plots/6
Part|Part|1|9.5,0.6,0.5|496.07,72.53,-114.03|Plots/6
Part|Part|1|1,5.4,1|496.07,70.23,-140.13|Plots/6
Part|Part|1|9.5,0.6,0.5|548.57,72.53,-197.83|Plots/6
Part|Part|1|9.5,0.6,0.5|511.82,72.53,-108.71|Plots/6
Part|Part|1|10.3,0.6,0.36|548.6,70.37,-113.83|Plots/6
Part|Part|1|10.3,0.6,0.28|548.6,70.37,-113.83|Plots/6
Part|Part|1|10.3,0.6,0.28|496.1,70.37,-113.83|Plots/6
Part|Part|1|10.3,0.6,0.36|496.1,70.37,-113.83|Plots/6
Part|Part|1|10.3,0.6,0.36|548.6,70.37,-124.33|Plots/6
Part|Part|1|10.3,0.6,0.28|548.6,70.37,-124.33|Plots/6
Part|Part|1|10.3,0.6,0.28|496.1,70.37,-124.33|Plots/6
Part|Part|1|10.3,0.6,0.36|496.1,70.37,-124.33|Plots/6
Part|Part|1|10.3,0.6,0.28|511.85,70.37,-108.7|Plots/6
Part|Part|1|10.3,0.6,0.28|501.35,70.37,-108.7|Plots/6
Part|Part|1|10.3,0.6,0.36|501.35,70.37,-108.7|Plots/6
Part|Part|1|10.3,0.6,0.36|511.85,70.37,-108.7|Plots/6
Part|Part|1|10.3,0.6,0.28|522.35,70.37,-108.7|Plots/6
Part|Part|1|10.3,0.6,0.36|522.35,70.37,-108.7|Plots/6
Part|Part|1|10.3,0.6,0.28|532.85,70.37,-108.7|Plots/6
Part|Part|1|10.3,0.6,0.36|532.85,70.37,-108.7|Plots/6
Part|Part|1|10.3,0.6,0.28|543.35,70.37,-108.7|Plots/6
Part|Part|1|10.3,0.6,0.36|543.35,70.37,-108.7|Plots/6
Part|Part|1|10.3,0.6,0.36|548.6,70.37,-134.83|Plots/6
Part|Part|1|10.3,0.6,0.28|548.6,70.37,-134.83|Plots/6
Part|Part|1|10.3,0.6,0.36|548.6,70.37,-145.33|Plots/6
Part|Part|1|10.3,0.6,0.28|548.6,70.37,-145.33|Plots/6
Part|Part|1|10.3,0.6,0.36|548.6,70.37,-155.83|Plots/6
Part|Part|1|10.3,0.6,0.28|548.6,70.37,-155.83|Plots/6
Part|Part|1|10.3,0.6,0.36|548.6,70.37,-166.33|Plots/6
Part|Part|1|10.3,0.6,0.28|548.6,70.37,-166.33|Plots/6
Part|Part|1|10.3,0.6,0.36|548.6,70.37,-176.83|Plots/6
Part|Part|1|10.3,0.6,0.28|548.6,70.37,-176.83|Plots/6
Part|Part|1|10.3,0.6,0.36|548.6,70.37,-187.33|Plots/6
Part|Part|1|10.3,0.6,0.28|548.6,70.37,-187.33|Plots/6
Part|Part|1|10.3,0.6,0.36|548.6,70.37,-197.83|Plots/6
Part|Part|1|10.3,0.6,0.28|548.6,70.37,-197.83|Plots/6
Part|Part|1|10.3,0.6,0.36|548.6,70.37,-208.33|Plots/6
Part|Part|1|10.3,0.6,0.28|548.6,70.37,-208.33|Plots/6
Part|Part|1|10.3,0.6,0.36|548.6,70.37,-218.83|Plots/6
Part|Part|1|10.3,0.6,0.28|548.6,70.37,-218.83|Plots/6
Part|Part|1|10.3,0.6,0.36|543.35,70.37,-224.08|Plots/6
Part|Part|1|10.3,0.6,0.28|543.35,70.37,-224.08|Plots/6
Part|Part|1|10.3,0.6,0.36|532.85,70.37,-224.08|Plots/6
Part|Part|1|10.3,0.6,0.28|532.85,70.37,-224.08|Plots/6
Part|Part|1|10.3,0.6,0.36|511.85,70.37,-224.08|Plots/6
Part|Part|1|10.3,0.6,0.28|511.85,70.37,-224.08|Plots/6
Part|Part|1|10.3,0.6,0.36|501.35,70.37,-224.08|Plots/6
Part|Part|1|10.3,0.6,0.28|501.35,70.37,-224.08|Plots/6
Part|Part|1|10.3,0.6,0.28|496.1,70.37,-218.83|Plots/6
Part|Part|1|10.3,0.6,0.36|496.1,70.37,-218.83|Plots/6
Part|Part|1|10.3,0.6,0.28|496.1,70.37,-208.33|Plots/6
Part|Part|1|9.5,0.6,0.5|496.07,72.53,-187.33|Plots/6
Part|Part|1|9.5,0.6,0.5|496.07,68.38,-187.33|Plots/6
Part|Part|1|1,5.4,1|496.07,70.23,-192.58|Plots/6
Part|Part|1|1,5.4,1|517.07,70.23,-224.08|Plots/6
Part|Part|1|9.5,0.6,0.5|511.82,72.53,-224.08|Plots/6
Part|Part|1|1,5.4,1|527.57,70.23,-224.08|Plots/6
Part|Part|1|1,5.4,1|548.57,70.23,-129.63|Plots/6
Part|Part|1|9.5,0.6,0.5|496.07,72.53,-208.33|Plots/6
Part|Part|1|9.5,0.6,0.5|496.07,68.38,-218.83|Plots/6
Part|Part|1|9.5,0.6,0.5|501.32,72.53,-108.71|Plots/6
Part|Part|1|9.5,0.6,0.5|548.57,72.53,-176.83|Plots/6
Part|Part|1|9.5,0.6,0.5|496.07,72.53,-176.83|Plots/6
Part|Part|1|9.5,0.6,0.5|548.57,72.53,-208.33|Plots/6
Part|Part|1|9.5,0.6,0.5|496.07,72.53,-145.38|Plots/6
Part|Part|1|1,5.4,1|496.07,70.23,-161.08|Plots/6
Part|Part|1|9.5,0.6,0.5|496.07,72.53,-124.47|Plots/6
Part|Part|1|1,5.4,1|496.07,70.23,-150.61|Plots/6
Part|Part|1|9.5,0.6,0.5|496.07,68.38,-134.87|Plots/6
Part|Part|1|9.5,0.6,0.5|496.07,68.38,-114.03|Plots/6
Part|Part|1|1,5.4,1|496.07,70.23,-119.22|Plots/6
Part|Part|1|1,4,1|496.07,69.53,-171.58|Plots/6
Part|Part|1|9.5,0.6,0.5|496.07,68.38,-155.86|Plots/6
Part|Part|1|1,5.4,1|496.07,70.23,-108.78|Plots/6
Part|Part|1|9.5,0.6,0.5|496.07,68.38,-145.38|Plots/6
Part|Part|1|9.5,0.6,0.5|496.07,72.53,-155.86|Plots/6
Part|Part|1|9.5,0.6,0.5|496.07,72.53,-134.87|Plots/6
Part|Part|1|1,5.4,1|548.57,70.23,-213.58|Plots/6
Part|Part|1|9.5,0.6,0.5|548.57,68.38,-208.33|Plots/6
Part|Part|1|1,4,1|548.57,69.53,-203.08|Plots/6
Part|Part|1|9.5,0.6,0.5|548.57,68.38,-197.83|Plots/6
Part|Part|1|1,5.4,1|548.57,70.23,-203.08|Plots/6
Part|Part|1|9.5,0.6,0.5|511.82,68.38,-108.71|Plots/6
Part|Part|1|1,5.4,1|506.57,70.23,-108.71|Plots/6
Part|Part|1|9.5,0.6,0.5|511.82,68.38,-224.08|Plots/6
Part|Part|1|1,4,1|496.07,69.53,-182.08|Plots/6
Part|Part|1|9.5,0.6,0.5|496.07,72.53,-197.83|Plots/6
Part|Part|1|9.5,0.6,0.5|532.82,72.53,-108.71|Plots/6
Part|Part|1|9.5,0.6,0.5|543.32,72.53,-224.08|Plots/6
Part|Part|1|9.5,0.6,0.5|548.57,68.38,-187.33|Plots/6
Part|Part|1|9.5,0.6,0.5|522.32,68.38,-108.71|Plots/6
Part|Part|1|9.5,0.6,0.5|501.32,68.38,-224.08|Plots/6
Part|Part|1|1,4,1|548.57,69.53,-213.58|Plots/6
Mesh|MeshPart|1|46.65,34.96,43.6|522.49,84.94,-166.3|Plots/6
Main|MeshPart|1|47.39,36.18,48.32|522.34,85.83,-166.32|Plots/6
Sign|Part|1|1,2.83,5.23|475.24,70.38,-421.35|Plots/4
Support|Part|1|1,1.57,1|475.27,68.4,-421.41|Plots/4
Support|Part|1|1,1.57,1|466.84,68.4,-433.53|Plots/4
Sign|Part|1|1,2.83,4.97|466.84,70.38,-433.6|Plots/4
Part|Part|1|10.3,0.6,0.36|439.15,70.37,-470.28|Plots/4
Part|Part|1|10.3,0.6,0.28|439.15,70.37,-470.28|Plots/4
Part|Part|1|10.3,0.6,0.36|449.65,70.37,-470.28|Plots/4
Part|Part|1|10.3,0.6,0.28|449.65,70.37,-470.28|Plots/4
Part|Part|1|10.3,0.6,0.36|460.15,70.37,-470.28|Plots/4
Part|Part|1|10.3,0.6,0.28|460.15,70.37,-470.28|Plots/4
Part|Part|1|10.3,0.6,0.28|465.4,70.37,-465.03|Plots/4
Part|Part|1|10.3,0.6,0.36|465.4,70.37,-465.03|Plots/4
Part|Part|1|10.3,0.6,0.28|465.4,70.37,-454.53|Plots/4
Part|Part|1|10.3,0.6,0.36|465.4,70.37,-454.53|Plots/4
Part|Part|1|10.3,0.6,0.28|465.4,70.37,-433.53|Plots/4
Part|Part|1|10.3,0.6,0.36|465.4,70.37,-433.53|Plots/4
Part|Part|1|10.3,0.6,0.28|465.4,70.37,-423.03|Plots/4
Part|Part|1|10.3,0.6,0.36|465.4,70.37,-423.03|Plots/4
Part|Part|1|10.3,0.6,0.28|460.15,70.37,-417.78|Plots/4
Part|Part|1|10.3,0.6,0.36|460.15,70.37,-417.78|Plots/4
Part|Part|1|10.3,0.6,0.28|449.65,70.37,-417.78|Plots/4
Part|Part|1|10.3,0.6,0.36|449.65,70.37,-417.78|Plots/4
Part|Part|1|10.3,0.6,0.28|439.15,70.37,-417.78|Plots/4
Part|Part|1|10.3,0.6,0.36|439.15,70.37,-417.78|Plots/4
Part|Part|1|10.3,0.6,0.28|428.65,70.37,-417.78|Plots/4
Part|Part|1|10.3,0.6,0.36|428.65,70.37,-417.78|Plots/4
Part|Part|1|10.3,0.6,0.28|418.15,70.37,-417.78|Plots/4
Part|Part|1|10.3,0.6,0.36|418.15,70.37,-417.78|Plots/4
Part|Part|1|10.3,0.6,0.28|407.65,70.37,-417.78|Plots/4
Part|Part|1|10.3,0.6,0.36|407.65,70.37,-417.78|Plots/4
Part|Part|1|10.3,0.6,0.28|397.15,70.37,-417.78|Plots/4
Part|Part|1|10.3,0.6,0.36|397.15,70.37,-417.78|Plots/4
Part|Part|1|10.3,0.6,0.28|386.65,70.37,-417.78|Plots/4
Part|Part|1|10.3,0.6,0.36|386.65,70.37,-417.78|Plots/4
Part|Part|1|10.3,0.6,0.28|376.15,70.37,-417.78|Plots/4
Part|Part|1|10.3,0.6,0.36|376.15,70.37,-417.78|Plots/4
Part|Part|1|10.3,0.6,0.36|350.02,70.37,-423.03|Plots/4
Part|Part|1|10.3,0.6,0.28|350.02,70.37,-423.03|Plots/4
Part|Part|1|10.3,0.6,0.36|350.02,70.37,-433.53|Plots/4
Part|Part|1|10.3,0.6,0.28|350.02,70.37,-433.53|Plots/4
Part|Part|1|10.3,0.6,0.36|350.02,70.37,-444.03|Plots/4
Part|Part|1|10.3,0.6,0.28|350.02,70.37,-444.03|Plots/4
Part|Part|1|10.3,0.6,0.36|350.02,70.37,-454.53|Plots/4
Part|Part|1|10.3,0.6,0.36|350.02,70.37,-465.03|Plots/4
Part|Part|1|10.3,0.6,0.28|350.02,70.37,-465.03|Plots/4
Part|Part|1|10.3,0.6,0.28|350.02,70.37,-454.53|Plots/4
Part|Part|1|10.3,0.6,0.36|365.65,70.37,-470.28|Plots/4
Part|Part|1|10.3,0.6,0.28|365.65,70.37,-470.28|Plots/4
Part|Part|1|10.3,0.6,0.28|365.65,70.37,-417.78|Plots/4
Part|Part|1|10.3,0.6,0.36|365.65,70.37,-417.78|Plots/4
Part|Part|1|10.3,0.6,0.36|355.15,70.37,-470.28|Plots/4
Part|Part|1|10.3,0.6,0.28|355.15,70.37,-470.28|Plots/4
Part|Part|1|10.3,0.6,0.28|355.15,70.37,-417.78|Plots/4
Part|Part|1|10.3,0.6,0.36|355.15,70.37,-417.78|Plots/4
Part|Part|1|1,6.9,1|412.9,70.98,-470.28|Plots/4
Part|Part|1|1,6.9,1|454.9,70.98,-470.28|Plots/4
Part|Part|1|1,6.9,1|465.4,70.98,-449.28|Plots/4
Part|Part|1|9.5,0.6,0.5|350.03,68.38,-454.53|Plots/4
Part|Part|1|1,6.9,1|465.4,70.98,-459.78|Plots/4
Part|Part|1|9.5,0.6,0.5|439.15,68.38,-417.78|Plots/4
Part|Part|1|9.5,0.6,0.5|460.15,68.38,-417.78|Plots/4
Part|Part|1|9.5,0.6,0.5|465.4,72.53,-433.53|Plots/4
Part|Part|1|1,6.9,1|454.9,70.98,-417.78|Plots/4
Part|Part|1|9.5,0.6,0.5|428.65,72.53,-417.78|Plots/4
Part|Part|1|9.5,0.6,0.5|428.65,72.53,-470.28|Plots/4
Part|Part|1|1,6.9,1|444.4,70.98,-470.28|Plots/4
Part|Part|1|9.5,0.6,0.5|449.65,72.53,-470.28|Plots/4
Part|Part|1|1,6.9,1|360.55,70.98,-417.78|Plots/4
Part|Part|1|9.5,0.6,0.5|350.03,72.53,-444.03|Plots/4
Part|Part|1|1,6.9,1|465.4,70.98,-417.78|Plots/4
Part|Part|1|9.5,0.6,0.5|350.03,68.38,-433.53|Plots/4
Part|Part|1|9.5,0.6,0.5|355.36,72.53,-417.78|Plots/4
Part|Part|1|9.5,0.6,0.5|418.15,72.53,-470.28|Plots/4
Part|Part|1|9.5,0.6,0.5|350.03,72.53,-465.03|Plots/4
Part|Part|1|9.5,0.6,0.5|350.03,68.38,-465.03|Plots/4
Part|Part|1|1,6.9,1|465.4,70.98,-470.28|Plots/4
Part|Part|1|9.5,0.6,0.5|460.15,72.53,-470.28|Plots/4
Part|Part|1|9.5,0.6,0.5|460.15,68.38,-470.28|Plots/4
Part|Part|1|9.5,0.6,0.5|465.4,72.53,-454.53|Plots/4
Part|Part|1|9.5,0.6,0.5|465.4,68.38,-454.53|Plots/4
Part|Part|1|9.5,0.6,0.5|350.03,72.53,-454.53|Plots/4
Part|Part|1|1,6.9,1|350.03,70.98,-459.78|Plots/4
Part|Part|1|9.5,0.6,0.5|465.4,72.53,-465.03|Plots/4
Part|Part|1|9.5,0.6,0.5|465.4,68.38,-465.03|Plots/4
Part|Part|1|9.5,0.6,0.5|439.15,72.53,-417.78|Plots/4
Part|Part|1|1,6.9,1|444.4,70.98,-417.78|Plots/4
Part|Part|1|9.5,0.6,0.5|460.15,72.53,-417.78|Plots/4
Part|Part|1|9.5,0.6,0.5|465.4,68.38,-433.53|Plots/4
Part|Part|1|1,6.9,1|465.4,70.98,-438.78|Plots/4
Part|Part|1|9.5,0.6,0.5|449.65,68.38,-417.78|Plots/4
Part|Part|1|9.5,0.6,0.5|449.65,72.53,-417.78|Plots/4
Part|Part|1|9.5,0.6,0.5|428.65,68.38,-417.78|Plots/4
Part|Part|1|1,6.9,1|433.9,70.98,-417.78|Plots/4
Part|Part|1|9.5,0.6,0.5|428.65,68.38,-470.28|Plots/4
Part|Part|1|1,6.9,1|433.9,70.98,-470.28|Plots/4
Part|Part|1|9.5,0.6,0.5|439.15,72.53,-470.28|Plots/4
Part|Part|1|9.5,0.6,0.5|439.15,68.38,-470.28|Plots/4
Part|Part|1|9.5,0.6,0.5|449.65,68.38,-470.28|Plots/4
Part|Part|1|1,6.9,1|350.11,70.98,-417.78|Plots/4
Part|Part|1|1,6.9,1|381.46,70.98,-417.78|Plots/4
Part|Part|1|1,6.9,1|370.95,70.98,-417.78|Plots/4
Part|Part|1|1,6.9,1|402.42,70.98,-417.78|Plots/4
Part|Part|1|1,6.9,1|391.94,70.98,-417.78|Plots/4
Part|Part|1|9.5,0.6,0.5|350.03,72.53,-423.03|Plots/4
Part|Part|1|1,6.9,1|412.9,70.98,-417.78|Plots/4
Part|Part|1|1,6.9,1|350.03,70.98,-428.28|Plots/4
Part|Part|1|9.5,0.6,0.5|350.03,68.38,-423.03|Plots/4
Part|Part|1|9.5,0.6,0.5|350.03,68.38,-444.03|Plots/4
Part|Part|1|1,6.9,1|350.03,70.98,-449.28|Plots/4
Part|Part|1|9.5,0.6,0.5|465.4,72.53,-423.03|Plots/4
Part|Part|1|1,6.9,1|465.4,70.98,-428.28|Plots/4
Part|Part|1|9.5,0.6,0.5|465.4,68.38,-423.03|Plots/4
Part|Part|1|1,6.9,1|350.03,70.98,-438.78|Plots/4
Part|Part|1|9.5,0.6,0.5|350.03,72.53,-433.53|Plots/4
Part|Part|1|9.5,0.6,0.5|397.19,68.38,-417.78|Plots/4
Part|Part|1|9.5,0.6,0.5|397.19,72.53,-417.78|Plots/4
Part|Part|1|9.5,0.6,0.5|418.15,68.38,-417.78|Plots/4
Part|Part|1|9.5,0.6,0.5|386.71,68.38,-417.78|Plots/4
Part|Part|1|1,6.9,1|423.4,70.98,-417.78|Plots/4
Part|Part|1|9.5,0.6,0.5|365.8,72.53,-417.78|Plots/4
Part|Part|1|9.5,0.6,0.5|355.36,68.38,-417.78|Plots/4
Part|Part|1|9.5,0.6,0.5|376.2,68.38,-417.78|Plots/4
Part|Part|1|9.5,0.6,0.5|365.8,68.38,-417.78|Plots/4
Part|Part|1|9.5,0.6,0.5|407.67,68.38,-417.78|Plots/4
Part|Part|1|9.5,0.6,0.5|418.15,72.53,-417.78|Plots/4
Part|Part|1|9.5,0.6,0.5|376.2,72.53,-417.78|Plots/4
Part|Part|1|9.5,0.6,0.5|386.71,72.53,-417.78|Plots/4
Part|Part|1|9.5,0.6,0.5|407.67,72.53,-417.78|Plots/4
Part|Part|1|1,6.9,1|391.93,70.98,-470.28|Plots/4
Part|Part|1|9.5,0.6,0.5|376.19,68.38,-470.28|Plots/4
Part|Part|1|9.5,0.6,0.5|397.18,72.53,-470.28|Plots/4
Part|Part|1|9.5,0.6,0.5|407.66,68.38,-470.28|Plots/4
Part|Part|1|1,6.9,1|350.1,70.98,-470.28|Plots/4
Part|Part|1|9.5,0.6,0.5|386.7,72.53,-470.28|Plots/4
Part|Part|1|1,6.9,1|402.41,70.98,-470.28|Plots/4
Part|Part|1|9.5,0.6,0.5|397.18,68.38,-470.28|Plots/4
Part|Part|1|1,6.9,1|360.54,70.98,-470.28|Plots/4
Part|Part|1|9.5,0.6,0.5|418.15,68.38,-470.28|Plots/4
Part|Part|1|9.5,0.6,0.5|355.35,72.53,-470.28|Plots/4
Part|Part|1|9.5,0.6,0.5|365.79,72.53,-470.28|Plots/4
Part|Part|1|1,6.9,1|381.45,70.98,-470.28|Plots/4
Part|Part|1|9.5,0.6,0.5|365.79,68.38,-470.28|Plots/4
Part|Part|1|1,6.9,1|423.4,70.98,-470.28|Plots/4
Part|Part|1|9.5,0.6,0.5|355.35,68.38,-470.28|Plots/4
Part|Part|1|1,6.9,1|370.94,70.98,-470.28|Plots/4
Part|Part|1|9.5,0.6,0.5|376.19,72.53,-470.28|Plots/4
Part|Part|1|9.5,0.6,0.5|407.66,72.53,-470.28|Plots/4
Part|Part|1|9.5,0.6,0.5|386.7,68.38,-470.28|Plots/4
Part|Part|1|10.3,0.6,0.36|376.15,70.37,-470.28|Plots/4
Part|Part|1|10.3,0.6,0.28|376.15,70.37,-470.28|Plots/4
Part|Part|1|10.3,0.6,0.28|386.65,70.37,-470.28|Plots/4
Part|Part|1|10.3,0.6,0.36|386.65,70.37,-470.28|Plots/4
Part|Part|1|10.3,0.6,0.36|397.15,70.37,-470.28|Plots/4
Part|Part|1|10.3,0.6,0.28|397.15,70.37,-470.28|Plots/4
Part|Part|1|10.3,0.6,0.36|407.65,70.37,-470.28|Plots/4
Part|Part|1|10.3,0.6,0.28|407.65,70.37,-470.28|Plots/4
Part|Part|1|10.3,0.6,0.36|418.15,70.37,-470.28|Plots/4
Part|Part|1|10.3,0.6,0.28|418.15,70.37,-470.28|Plots/4
Part|Part|1|10.3,0.6,0.36|428.65,70.37,-470.28|Plots/4
Part|Part|1|10.3,0.6,0.28|428.65,70.37,-470.28|Plots/4
Sign|Part|1|1,2.83,4.97|467.76,70.38,-513.05|Plots/5
Support|Part|1|1,1.57,1|467.76,68.4,-512.99|Plots/5
Sign|Part|1|1,2.83,5.23|478.09,70.38,-497.77|Plots/5
Support|Part|1|1,1.57,1|478.12,68.4,-497.83|Plots/5
Part|Part|1|10.3,0.6,0.36|398.07,70.37,-497.23|Plots/5
Part|Part|1|10.3,0.6,0.28|387.57,70.37,-497.23|Plots/5
Part|Part|1|10.3,0.6,0.36|387.57,70.37,-497.23|Plots/5
Part|Part|1|10.3,0.6,0.28|377.07,70.37,-497.23|Plots/5
Part|Part|1|10.3,0.6,0.36|377.07,70.37,-497.23|Plots/5
Part|Part|1|10.3,0.6,0.36|350.95,70.37,-502.48|Plots/5
Part|Part|1|10.3,0.6,0.28|350.95,70.37,-502.48|Plots/5
Part|Part|1|10.3,0.6,0.36|350.95,70.37,-512.98|Plots/5
Part|Part|1|10.3,0.6,0.28|350.95,70.37,-512.98|Plots/5
Part|Part|1|10.3,0.6,0.36|350.95,70.37,-523.48|Plots/5
Part|Part|1|10.3,0.6,0.28|350.95,70.37,-523.48|Plots/5
Part|Part|1|10.3,0.6,0.36|350.95,70.37,-533.98|Plots/5
Part|Part|1|10.3,0.6,0.36|350.95,70.37,-544.48|Plots/5
Part|Part|1|10.3,0.6,0.28|350.95,70.37,-544.48|Plots/5
Part|Part|1|10.3,0.6,0.28|350.95,70.37,-533.98|Plots/5
Part|Part|1|10.3,0.6,0.36|366.57,70.37,-549.73|Plots/5
Part|Part|1|10.3,0.6,0.28|366.57,70.37,-549.73|Plots/5
Part|Part|1|10.3,0.6,0.28|366.57,70.37,-497.23|Plots/5
Part|Part|1|10.3,0.6,0.36|366.57,70.37,-497.23|Plots/5
Part|Part|1|10.3,0.6,0.36|356.07,70.37,-549.73|Plots/5
Part|Part|1|10.3,0.6,0.28|356.07,70.37,-549.73|Plots/5
Part|Part|1|10.3,0.6,0.28|356.07,70.37,-497.23|Plots/5
Part|Part|1|10.3,0.6,0.36|356.07,70.37,-497.23|Plots/5
Part|Part|1|1,6.9,1|413.82,70.98,-549.73|Plots/5
Part|Part|1|1,6.9,1|455.82,70.98,-549.73|Plots/5
Part|Part|1|1,6.9,1|466.32,70.98,-528.73|Plots/5
Part|Part|1|9.5,0.6,0.5|350.95,68.38,-533.98|Plots/5
Part|Part|1|1,6.9,1|466.32,70.98,-539.23|Plots/5
Part|Part|1|9.5,0.6,0.5|440.07,68.38,-497.23|Plots/5
Part|Part|1|9.5,0.6,0.5|461.07,68.38,-497.23|Plots/5
Part|Part|1|9.5,0.6,0.5|466.32,72.53,-512.98|Plots/5
Part|Part|1|1,6.9,1|455.82,70.98,-497.23|Plots/5
Part|Part|1|9.5,0.6,0.5|429.57,72.53,-497.23|Plots/5
Part|Part|1|9.5,0.6,0.5|429.57,72.53,-549.73|Plots/5
Part|Part|1|1,6.9,1|445.32,70.98,-549.73|Plots/5
Part|Part|1|9.5,0.6,0.5|450.57,72.53,-549.73|Plots/5
Part|Part|1|1,6.9,1|361.47,70.98,-497.23|Plots/5
Part|Part|1|9.5,0.6,0.5|350.95,72.53,-523.48|Plots/5
Part|Part|1|1,6.9,1|466.32,70.98,-497.23|Plots/5
Part|Part|1|9.5,0.6,0.5|350.95,68.38,-512.98|Plots/5
Part|Part|1|9.5,0.6,0.5|356.28,72.53,-497.23|Plots/5
Part|Part|1|9.5,0.6,0.5|419.07,72.53,-549.73|Plots/5
Part|Part|1|9.5,0.6,0.5|350.95,72.53,-544.48|Plots/5
Part|Part|1|9.5,0.6,0.5|350.95,68.38,-544.48|Plots/5
Part|Part|1|1,6.9,1|466.32,70.98,-549.73|Plots/5
Part|Part|1|9.5,0.6,0.5|461.07,72.53,-549.73|Plots/5
Part|Part|1|9.5,0.6,0.5|461.07,68.38,-549.73|Plots/5
Part|Part|1|9.5,0.6,0.5|466.32,72.53,-533.98|Plots/5
Part|Part|1|9.5,0.6,0.5|466.32,68.38,-533.98|Plots/5
Part|Part|1|9.5,0.6,0.5|350.95,72.53,-533.98|Plots/5
Part|Part|1|1,6.9,1|350.95,70.98,-539.23|Plots/5
Part|Part|1|9.5,0.6,0.5|466.32,72.53,-544.48|Plots/5
Part|Part|1|9.5,0.6,0.5|466.32,68.38,-544.48|Plots/5
Part|Part|1|9.5,0.6,0.5|440.07,72.53,-497.23|Plots/5
Part|Part|1|1,6.9,1|445.32,70.98,-497.23|Plots/5
Part|Part|1|9.5,0.6,0.5|461.07,72.53,-497.23|Plots/5
Part|Part|1|9.5,0.6,0.5|466.32,68.38,-512.98|Plots/5
Part|Part|1|1,6.9,1|466.32,70.98,-518.23|Plots/5
Part|Part|1|9.5,0.6,0.5|450.57,68.38,-497.23|Plots/5
Part|Part|1|9.5,0.6,0.5|450.57,72.53,-497.23|Plots/5
Part|Part|1|9.5,0.6,0.5|429.57,68.38,-497.23|Plots/5
Part|Part|1|1,6.9,1|434.82,70.98,-497.23|Plots/5
Part|Part|1|9.5,0.6,0.5|429.57,68.38,-549.73|Plots/5
Part|Part|1|1,6.9,1|434.82,70.98,-549.73|Plots/5
Part|Part|1|9.5,0.6,0.5|440.07,72.53,-549.73|Plots/5
Part|Part|1|9.5,0.6,0.5|440.07,68.38,-549.73|Plots/5
Part|Part|1|9.5,0.6,0.5|450.57,68.38,-549.73|Plots/5
Part|Part|1|1,6.9,1|351.03,70.98,-497.23|Plots/5
Part|Part|1|1,6.9,1|382.38,70.98,-497.23|Plots/5
Part|Part|1|1,6.9,1|371.87,70.98,-497.23|Plots/5
Part|Part|1|1,6.9,1|403.34,70.98,-497.23|Plots/5
Part|Part|1|1,6.9,1|392.87,70.98,-497.23|Plots/5
Part|Part|1|10.3,0.6,0.36|377.07,70.37,-549.73|Plots/5
Part|Part|1|10.3,0.6,0.28|377.07,70.37,-549.73|Plots/5
Part|Part|1|10.3,0.6,0.28|387.57,70.37,-549.73|Plots/5
Part|Part|1|10.3,0.6,0.36|387.57,70.37,-549.73|Plots/5
Part|Part|1|10.3,0.6,0.36|398.07,70.37,-549.73|Plots/5
Part|Part|1|10.3,0.6,0.28|398.07,70.37,-549.73|Plots/5
Part|Part|1|10.3,0.6,0.36|408.57,70.37,-549.73|Plots/5
Part|Part|1|10.3,0.6,0.28|408.57,70.37,-549.73|Plots/5
Part|Part|1|10.3,0.6,0.36|419.07,70.37,-549.73|Plots/5
Part|Part|1|10.3,0.6,0.28|419.07,70.37,-549.73|Plots/5
Part|Part|1|10.3,0.6,0.36|429.57,70.37,-549.73|Plots/5
Part|Part|1|10.3,0.6,0.28|429.57,70.37,-549.73|Plots/5
Part|Part|1|10.3,0.6,0.36|440.07,70.37,-549.73|Plots/5
Part|Part|1|10.3,0.6,0.28|440.07,70.37,-549.73|Plots/5
Part|Part|1|10.3,0.6,0.36|450.57,70.37,-549.73|Plots/5
Part|Part|1|10.3,0.6,0.28|450.57,70.37,-549.73|Plots/5
Part|Part|1|10.3,0.6,0.36|461.07,70.37,-549.73|Plots/5
Part|Part|1|10.3,0.6,0.28|461.07,70.37,-549.73|Plots/5
Part|Part|1|10.3,0.6,0.28|466.32,70.37,-544.48|Plots/5
Part|Part|1|10.3,0.6,0.36|466.32,70.37,-544.48|Plots/5
Part|Part|1|10.3,0.6,0.28|466.32,70.37,-533.98|Plots/5
Part|Part|1|10.3,0.6,0.36|466.32,70.37,-533.98|Plots/5
Part|Part|1|10.3,0.6,0.28|466.32,70.37,-512.98|Plots/5
Part|Part|1|10.3,0.6,0.36|466.32,70.37,-512.98|Plots/5
Part|Part|1|10.3,0.6,0.28|466.32,70.37,-502.48|Plots/5
Part|Part|1|10.3,0.6,0.36|466.32,70.37,-502.48|Plots/5
Part|Part|1|10.3,0.6,0.28|461.07,70.37,-497.23|Plots/5
Part|Part|1|10.3,0.6,0.36|461.07,70.37,-497.23|Plots/5
Part|Part|1|10.3,0.6,0.28|450.57,70.37,-497.23|Plots/5
Part|Part|1|10.3,0.6,0.36|450.57,70.37,-497.23|Plots/5
Part|Part|1|10.3,0.6,0.28|440.07,70.37,-497.23|Plots/5
Part|Part|1|10.3,0.6,0.36|440.07,70.37,-497.23|Plots/5
Part|Part|1|10.3,0.6,0.28|429.57,70.37,-497.23|Plots/5
Part|Part|1|10.3,0.6,0.36|429.57,70.37,-497.23|Plots/5
Part|Part|1|10.3,0.6,0.28|419.07,70.37,-497.23|Plots/5
Part|Part|1|10.3,0.6,0.36|419.07,70.37,-497.23|Plots/5
Part|Part|1|10.3,0.6,0.28|408.57,70.37,-497.23|Plots/5
Part|Part|1|10.3,0.6,0.36|408.57,70.37,-497.23|Plots/5
Part|Part|1|10.3,0.6,0.28|398.07,70.37,-497.23|Plots/5
Part|Part|1|9.5,0.6,0.5|350.95,72.53,-502.48|Plots/5
Part|Part|1|1,6.9,1|413.82,70.98,-497.23|Plots/5
Part|Part|1|1,6.9,1|350.95,70.98,-507.73|Plots/5
Part|Part|1|9.5,0.6,0.5|350.95,68.38,-502.48|Plots/5
Part|Part|1|9.5,0.6,0.5|350.95,68.38,-523.48|Plots/5
Part|Part|1|1,6.9,1|350.95,70.98,-528.73|Plots/5
Part|Part|1|9.5,0.6,0.5|466.32,72.53,-502.48|Plots/5
Part|Part|1|1,6.9,1|466.32,70.98,-507.73|Plots/5
Part|Part|1|9.5,0.6,0.5|466.32,68.38,-502.48|Plots/5
Part|Part|1|1,6.9,1|350.95,70.98,-518.23|Plots/5
Part|Part|1|9.5,0.6,0.5|350.95,72.53,-512.98|Plots/5
Part|Part|1|9.5,0.6,0.5|398.11,68.38,-497.23|Plots/5
Part|Part|1|9.5,0.6,0.5|398.11,72.53,-497.23|Plots/5
Part|Part|1|9.5,0.6,0.5|419.07,68.38,-497.23|Plots/5
Part|Part|1|9.5,0.6,0.5|387.63,68.38,-497.23|Plots/5
Part|Part|1|1,6.9,1|424.32,70.98,-497.23|Plots/5
Part|Part|1|9.5,0.6,0.5|366.72,72.53,-497.23|Plots/5
Part|Part|1|9.5,0.6,0.5|356.28,68.38,-497.23|Plots/5
Part|Part|1|9.5,0.6,0.5|377.12,68.38,-497.23|Plots/5
Part|Part|1|9.5,0.6,0.5|366.72,68.38,-497.23|Plots/5
Part|Part|1|9.5,0.6,0.5|408.59,68.38,-497.23|Plots/5
Part|Part|1|9.5,0.6,0.5|419.07,72.53,-497.23|Plots/5
Part|Part|1|9.5,0.6,0.5|377.12,72.53,-497.23|Plots/5
Part|Part|1|9.5,0.6,0.5|387.63,72.53,-497.23|Plots/5
Part|Part|1|9.5,0.6,0.5|408.59,72.53,-497.23|Plots/5
Part|Part|1|1,6.9,1|392.86,70.98,-549.73|Plots/5
Part|Part|1|9.5,0.6,0.5|377.11,68.38,-549.73|Plots/5
Part|Part|1|9.5,0.6,0.5|398.11,72.53,-549.73|Plots/5
Part|Part|1|9.5,0.6,0.5|408.58,68.38,-549.73|Plots/5
Part|Part|1|1,6.9,1|351.02,70.98,-549.73|Plots/5
Part|Part|1|9.5,0.6,0.5|387.62,72.53,-549.73|Plots/5
Part|Part|1|1,6.9,1|403.33,70.98,-549.73|Plots/5
Part|Part|1|9.5,0.6,0.5|398.11,68.38,-549.73|Plots/5
Part|Part|1|1,6.9,1|361.46,70.98,-549.73|Plots/5
Part|Part|1|9.5,0.6,0.5|419.07,68.38,-549.73|Plots/5
Part|Part|1|9.5,0.6,0.5|356.27,72.53,-549.73|Plots/5
Part|Part|1|9.5,0.6,0.5|366.71,72.53,-549.73|Plots/5
Part|Part|1|1,6.9,1|382.37,70.98,-549.73|Plots/5
Part|Part|1|9.5,0.6,0.5|366.71,68.38,-549.73|Plots/5
Part|Part|1|1,6.9,1|424.32,70.98,-549.73|Plots/5
Part|Part|1|9.5,0.6,0.5|356.27,68.38,-549.73|Plots/5
Part|Part|1|1,6.9,1|371.86,70.98,-549.73|Plots/5
Part|Part|1|9.5,0.6,0.5|377.11,72.53,-549.73|Plots/5
Part|Part|1|9.5,0.6,0.5|408.58,72.53,-549.73|Plots/5
Part|Part|1|9.5,0.6,0.5|387.62,68.38,-549.73|Plots/5
Support|Part|1|1,1.57,1|466.84,68.4,-191.88|Plots/3
Sign|Part|1|1,2.83,4.97|466.84,70.38,-191.95|Plots/3
Support|Part|1|1,1.57,1|480.01,68.4,-230.5|Plots/3
Sign|Part|1|1,2.83,5.23|480.04,70.38,-230.44|Plots/3
Part|Part|1|9.5,0.6,0.5|418.15,68.38,-228.63|Plots/3
Part|Part|1|9.5,0.6,0.5|355.35,72.53,-228.63|Plots/3
Part|Part|1|9.5,0.6,0.5|365.79,72.53,-228.63|Plots/3
Part|Part|1|1,6.9,1|381.45,70.98,-228.63|Plots/3
Part|Part|1|9.5,0.6,0.5|365.79,68.38,-228.63|Plots/3
Part|Part|1|1,6.9,1|423.4,70.98,-228.63|Plots/3
Part|Part|1|9.5,0.6,0.5|355.35,68.38,-228.63|Plots/3
Part|Part|1|1,6.9,1|370.94,70.98,-228.63|Plots/3
Part|Part|1|9.5,0.6,0.5|376.19,72.53,-228.63|Plots/3
Part|Part|1|9.5,0.6,0.5|407.66,72.53,-228.63|Plots/3
Part|Part|1|9.5,0.6,0.5|386.7,68.38,-228.63|Plots/3
Part|Part|1|1,6.9,1|360.54,70.98,-228.63|Plots/3
Part|Part|1|10.3,0.6,0.36|376.15,70.37,-228.63|Plots/3
Part|Part|1|10.3,0.6,0.28|376.15,70.37,-228.63|Plots/3
Part|Part|1|10.3,0.6,0.28|386.65,70.37,-228.63|Plots/3
Part|Part|1|10.3,0.6,0.36|386.65,70.37,-228.63|Plots/3
Part|Part|1|10.3,0.6,0.36|397.15,70.37,-228.63|Plots/3
Part|Part|1|10.3,0.6,0.28|397.15,70.37,-228.63|Plots/3
Part|Part|1|10.3,0.6,0.36|407.65,70.37,-228.63|Plots/3
Part|Part|1|10.3,0.6,0.28|407.65,70.37,-228.63|Plots/3
Part|Part|1|10.3,0.6,0.36|418.15,70.37,-228.63|Plots/3
Part|Part|1|10.3,0.6,0.28|418.15,70.37,-228.63|Plots/3
Part|Part|1|10.3,0.6,0.36|428.65,70.37,-228.63|Plots/3
Part|Part|1|10.3,0.6,0.28|428.65,70.37,-228.63|Plots/3
Part|Part|1|10.3,0.6,0.36|439.15,70.37,-228.63|Plots/3
Part|Part|1|10.3,0.6,0.28|439.15,70.37,-228.63|Plots/3
Part|Part|1|10.3,0.6,0.36|449.65,70.37,-228.63|Plots/3
Part|Part|1|10.3,0.6,0.28|449.65,70.37,-228.63|Plots/3
Part|Part|1|10.3,0.6,0.36|460.15,70.37,-228.63|Plots/3
Part|Part|1|10.3,0.6,0.28|460.15,70.37,-228.63|Plots/3
Part|Part|1|10.3,0.6,0.28|465.4,70.37,-223.38|Plots/3
Part|Part|1|10.3,0.6,0.36|465.4,70.37,-223.38|Plots/3
Part|Part|1|10.3,0.6,0.28|465.4,70.37,-212.88|Plots/3
Part|Part|1|10.3,0.6,0.36|465.4,70.37,-212.88|Plots/3
Part|Part|1|10.3,0.6,0.28|465.4,70.37,-191.88|Plots/3
Part|Part|1|10.3,0.6,0.36|465.4,70.37,-191.88|Plots/3
Part|Part|1|10.3,0.6,0.28|465.4,70.37,-181.38|Plots/3
Part|Part|1|10.3,0.6,0.36|465.4,70.37,-181.38|Plots/3
Part|Part|1|10.3,0.6,0.28|460.15,70.37,-176.13|Plots/3
Part|Part|1|10.3,0.6,0.36|460.15,70.37,-176.13|Plots/3
Part|Part|1|10.3,0.6,0.28|449.65,70.37,-176.13|Plots/3
Part|Part|1|10.3,0.6,0.36|449.65,70.37,-176.13|Plots/3
Part|Part|1|10.3,0.6,0.28|439.15,70.37,-176.13|Plots/3
Part|Part|1|10.3,0.6,0.36|439.15,70.37,-176.13|Plots/3
Part|Part|1|10.3,0.6,0.28|428.65,70.37,-176.13|Plots/3
Part|Part|1|10.3,0.6,0.36|428.65,70.37,-176.13|Plots/3
Part|Part|1|10.3,0.6,0.28|418.15,70.37,-176.13|Plots/3
Part|Part|1|10.3,0.6,0.36|418.15,70.37,-176.13|Plots/3
Part|Part|1|10.3,0.6,0.28|407.65,70.37,-176.13|Plots/3
Part|Part|1|10.3,0.6,0.36|407.65,70.37,-176.13|Plots/3
Part|Part|1|10.3,0.6,0.28|397.15,70.37,-176.13|Plots/3
Part|Part|1|10.3,0.6,0.36|397.15,70.37,-176.13|Plots/3
Part|Part|1|10.3,0.6,0.28|386.65,70.37,-176.13|Plots/3
Part|Part|1|10.3,0.6,0.36|386.65,70.37,-176.13|Plots/3
Part|Part|1|10.3,0.6,0.28|376.15,70.37,-176.13|Plots/3
Part|Part|1|10.3,0.6,0.36|376.15,70.37,-176.13|Plots/3
Part|Part|1|10.3,0.6,0.36|350.02,70.37,-181.38|Plots/3
Part|Part|1|10.3,0.6,0.28|350.02,70.37,-181.38|Plots/3
Part|Part|1|10.3,0.6,0.36|350.02,70.37,-191.88|Plots/3
Part|Part|1|10.3,0.6,0.28|350.02,70.37,-191.88|Plots/3
Part|Part|1|10.3,0.6,0.36|350.02,70.37,-202.38|Plots/3
Part|Part|1|10.3,0.6,0.28|350.02,70.37,-202.38|Plots/3
Part|Part|1|10.3,0.6,0.36|350.02,70.37,-212.88|Plots/3
Part|Part|1|10.3,0.6,0.36|350.02,70.37,-223.38|Plots/3
Part|Part|1|10.3,0.6,0.28|350.02,70.37,-223.38|Plots/3
Part|Part|1|10.3,0.6,0.28|350.02,70.37,-212.88|Plots/3
Part|Part|1|10.3,0.6,0.36|365.65,70.37,-228.63|Plots/3
Part|Part|1|10.3,0.6,0.28|365.65,70.37,-228.63|Plots/3
Part|Part|1|10.3,0.6,0.28|365.65,70.37,-176.13|Plots/3
Part|Part|1|10.3,0.6,0.36|365.65,70.37,-176.13|Plots/3
Part|Part|1|10.3,0.6,0.36|355.15,70.37,-228.63|Plots/3
Part|Part|1|10.3,0.6,0.28|355.15,70.37,-228.63|Plots/3
Part|Part|1|10.3,0.6,0.28|355.15,70.37,-176.13|Plots/3
Part|Part|1|10.3,0.6,0.36|355.15,70.37,-176.13|Plots/3
Part|Part|1|1,6.9,1|412.9,70.98,-228.63|Plots/3
Part|Part|1|1,6.9,1|454.9,70.98,-228.63|Plots/3
Part|Part|1|1,6.9,1|465.4,70.98,-207.63|Plots/3
Part|Part|1|9.5,0.6,0.5|350.03,68.38,-212.88|Plots/3
Part|Part|1|1,6.9,1|465.4,70.98,-218.13|Plots/3
Part|Part|1|9.5,0.6,0.5|439.15,68.38,-176.13|Plots/3
Part|Part|1|9.5,0.6,0.5|460.15,68.38,-176.13|Plots/3
Part|Part|1|9.5,0.6,0.5|465.4,72.53,-191.88|Plots/3
Part|Part|1|1,6.9,1|454.9,70.98,-176.13|Plots/3
Part|Part|1|9.5,0.6,0.5|428.65,72.53,-176.13|Plots/3
Part|Part|1|9.5,0.6,0.5|428.65,72.53,-228.63|Plots/3
Part|Part|1|1,6.9,1|444.4,70.98,-228.63|Plots/3
Part|Part|1|9.5,0.6,0.5|449.65,72.53,-228.63|Plots/3
Part|Part|1|1,6.9,1|360.55,70.98,-176.13|Plots/3
Part|Part|1|9.5,0.6,0.5|350.03,72.53,-202.38|Plots/3
Part|Part|1|1,6.9,1|465.4,70.98,-176.13|Plots/3
Part|Part|1|9.5,0.6,0.5|350.03,68.38,-191.88|Plots/3
Part|Part|1|9.5,0.6,0.5|355.36,72.53,-176.13|Plots/3
Part|Part|1|9.5,0.6,0.5|418.15,72.53,-228.63|Plots/3
Part|Part|1|9.5,0.6,0.5|350.03,72.53,-223.38|Plots/3
Part|Part|1|9.5,0.6,0.5|350.03,68.38,-223.38|Plots/3
Part|Part|1|1,6.9,1|465.4,70.98,-228.63|Plots/3
Part|Part|1|9.5,0.6,0.5|460.15,72.53,-228.63|Plots/3
Part|Part|1|9.5,0.6,0.5|460.15,68.38,-228.63|Plots/3
Part|Part|1|9.5,0.6,0.5|465.4,72.53,-212.88|Plots/3
Part|Part|1|9.5,0.6,0.5|465.4,68.38,-212.88|Plots/3
Part|Part|1|9.5,0.6,0.5|350.03,72.53,-212.88|Plots/3
Part|Part|1|1,6.9,1|350.03,70.98,-218.13|Plots/3
Part|Part|1|9.5,0.6,0.5|465.4,72.53,-223.38|Plots/3
Part|Part|1|9.5,0.6,0.5|465.4,68.38,-223.38|Plots/3
Part|Part|1|9.5,0.6,0.5|439.15,72.53,-176.13|Plots/3
Part|Part|1|1,6.9,1|444.4,70.98,-176.13|Plots/3
Part|Part|1|9.5,0.6,0.5|460.15,72.53,-176.13|Plots/3
Part|Part|1|9.5,0.6,0.5|465.4,68.38,-191.88|Plots/3
Part|Part|1|1,6.9,1|465.4,70.98,-197.13|Plots/3
Part|Part|1|9.5,0.6,0.5|449.65,68.38,-176.13|Plots/3
Part|Part|1|9.5,0.6,0.5|449.65,72.53,-176.13|Plots/3
Part|Part|1|9.5,0.6,0.5|428.65,68.38,-176.13|Plots/3
Part|Part|1|1,6.9,1|433.9,70.98,-176.13|Plots/3
Part|Part|1|9.5,0.6,0.5|428.65,68.38,-228.63|Plots/3
Part|Part|1|1,6.9,1|433.9,70.98,-228.63|Plots/3
Part|Part|1|9.5,0.6,0.5|439.15,72.53,-228.63|Plots/3
Part|Part|1|9.5,0.6,0.5|439.15,68.38,-228.63|Plots/3
Part|Part|1|9.5,0.6,0.5|449.65,68.38,-228.63|Plots/3
Part|Part|1|1,6.9,1|350.11,70.98,-176.13|Plots/3
Part|Part|1|1,6.9,1|381.46,70.98,-176.13|Plots/3
Part|Part|1|1,6.9,1|370.95,70.98,-176.13|Plots/3
Part|Part|1|1,6.9,1|402.42,70.98,-176.13|Plots/3
Part|Part|1|1,6.9,1|391.94,70.98,-176.13|Plots/3
Part|Part|1|9.5,0.6,0.5|350.03,72.53,-181.38|Plots/3
Part|Part|1|1,6.9,1|412.9,70.98,-176.13|Plots/3
Part|Part|1|1,6.9,1|350.03,70.98,-186.63|Plots/3
Part|Part|1|9.5,0.6,0.5|350.03,68.38,-181.38|Plots/3
Part|Part|1|9.5,0.6,0.5|350.03,68.38,-202.38|Plots/3
Part|Part|1|1,6.9,1|350.03,70.98,-207.63|Plots/3
Part|Part|1|9.5,0.6,0.5|465.4,72.53,-181.38|Plots/3
Part|Part|1|1,6.9,1|465.4,70.98,-186.63|Plots/3
Part|Part|1|9.5,0.6,0.5|465.4,68.38,-181.38|Plots/3
Part|Part|1|1,6.9,1|350.03,70.98,-197.13|Plots/3
Part|Part|1|9.5,0.6,0.5|350.03,72.53,-191.88|Plots/3
Part|Part|1|9.5,0.6,0.5|397.19,68.38,-176.13|Plots/3
Part|Part|1|9.5,0.6,0.5|397.19,72.53,-176.13|Plots/3
Part|Part|1|9.5,0.6,0.5|418.15,68.38,-176.13|Plots/3
Part|Part|1|9.5,0.6,0.5|386.71,68.38,-176.13|Plots/3
Part|Part|1|1,6.9,1|423.4,70.98,-176.13|Plots/3
Part|Part|1|9.5,0.6,0.5|365.8,72.53,-176.13|Plots/3
Part|Part|1|9.5,0.6,0.5|355.36,68.38,-176.13|Plots/3
Part|Part|1|9.5,0.6,0.5|376.2,68.38,-176.13|Plots/3
Part|Part|1|9.5,0.6,0.5|365.8,68.38,-176.13|Plots/3
Part|Part|1|9.5,0.6,0.5|407.67,68.38,-176.13|Plots/3
Part|Part|1|9.5,0.6,0.5|418.15,72.53,-176.13|Plots/3
Part|Part|1|9.5,0.6,0.5|376.2,72.53,-176.13|Plots/3
Part|Part|1|9.5,0.6,0.5|386.71,72.53,-176.13|Plots/3
Part|Part|1|9.5,0.6,0.5|407.67,72.53,-176.13|Plots/3
Part|Part|1|1,6.9,1|391.93,70.98,-228.63|Plots/3
Part|Part|1|9.5,0.6,0.5|376.19,68.38,-228.63|Plots/3
Part|Part|1|9.5,0.6,0.5|397.18,72.53,-228.63|Plots/3
Part|Part|1|9.5,0.6,0.5|407.66,68.38,-228.63|Plots/3
Part|Part|1|1,6.9,1|350.1,70.98,-228.63|Plots/3
Part|Part|1|9.5,0.6,0.5|386.7,72.53,-228.63|Plots/3
Part|Part|1|1,6.9,1|402.41,70.98,-228.63|Plots/3
Part|Part|1|9.5,0.6,0.5|397.18,68.38,-228.63|Plots/3
Support|Part|1|1,1.57,1|532.93,68.4,-497.41|Plots/7
Sign|Part|1|1,2.83,5.23|532.87,70.38,-497.37|Plots/7
Sign|Part|1|1,2.83,4.97|511.9,70.38,-502.51|Plots/7
Support|Part|1|1,1.57,1|511.84,68.4,-502.51|Plots/7
GatePart|Part|1|0.5,2.75,0.6|522.74,70.05,-503.96|Plots/7
Hinge|Part|1|0.5,2.75,0.6|526.99,70.05,-503.96|Plots/7
GatePart|Part|1|0.5,3.65,0.6|524.86,71.13,-503.96|Plots/7
GatePart|Part|1|0.5,4.85,0.6|524.86,68.38,-503.96|Plots/7
GatePart|Part|1|0.5,4.85,0.6|519.76,68.38,-503.96|Plots/7
GatePart|Part|1|0.5,3.65,0.6|519.76,71.13,-503.96|Plots/7
Hinge|Part|1|0.5,2.75,0.6|517.64,70.05,-503.96|Plots/7
GatePart|Part|1|0.2,4.42,0.6|519.76,69.75,-503.96|Plots/7
GatePart|Part|1|0.5,2.75,0.6|521.89,70.05,-503.96|Plots/7
GatePart|Part|1|0.25,4.4,0.6|519.76,69.75,-503.96|Plots/7
GatePart|Part|1|0.2,4.39,0.6|524.86,69.75,-503.96|Plots/7
GatePart|Part|1|0.25,4.45,0.6|524.86,69.75,-503.96|Plots/7
Part|Part|1|1,4,1|527.59,69.53,-503.96|Plots/7
Part|Part|1|1,4,1|517.09,69.53,-503.96|Plots/7
Part|Part|1|10.3,0.6,0.36|496.09,69.75,-551.21|Plots/7
Part|Part|1|10.3,0.6,0.28|496.09,69.75,-551.21|Plots/7
Part|Part|1|10.3,0.6,0.36|496.09,69.75,-530.21|Plots/7
Part|Part|1|10.3,0.6,0.28|496.09,69.75,-530.21|Plots/7
Part|Part|1|10.3,0.6,0.28|496.09,69.75,-540.71|Plots/7
Part|Part|1|10.3,0.6,0.36|496.09,69.75,-540.71|Plots/7
Part|Part|1|10.3,0.6,0.28|496.09,69.75,-519.71|Plots/7
Part|Part|1|10.3,0.6,0.36|496.09,69.75,-519.71|Plots/7
Part|Part|1|10.3,0.6,0.28|496.09,69.75,-509.21|Plots/7
Part|Part|1|10.3,0.6,0.36|496.09,69.75,-509.21|Plots/7
Part|Part|1|10.3,0.6,0.28|543.34,69.75,-556.46|Plots/7
Part|Part|1|10.3,0.6,0.36|543.34,69.75,-556.46|Plots/7
Part|Part|1|10.3,0.6,0.28|532.84,69.75,-556.46|Plots/7
Part|Part|1|10.3,0.6,0.36|532.84,69.75,-556.46|Plots/7
Part|Part|1|10.3,0.6,0.28|522.34,69.75,-556.46|Plots/7
Part|Part|1|10.3,0.6,0.36|522.34,69.75,-556.46|Plots/7
Part|Part|1|10.3,0.6,0.28|511.84,69.75,-556.46|Plots/7
Part|Part|1|10.3,0.6,0.36|511.84,69.75,-556.46|Plots/7
Part|Part|1|10.3,0.6,0.28|501.34,69.75,-556.46|Plots/7
Part|Part|1|10.3,0.6,0.36|501.34,69.75,-556.46|Plots/7
Part|Part|1|10.3,0.6,0.36|548.59,69.75,-551.21|Plots/7
Part|Part|1|10.3,0.6,0.28|548.59,69.75,-551.21|Plots/7
Part|Part|1|10.3,0.6,0.36|548.59,69.75,-530.21|Plots/7
Part|Part|1|10.3,0.6,0.28|548.59,69.75,-530.21|Plots/7
Part|Part|1|10.3,0.6,0.28|548.59,69.75,-540.71|Plots/7
Part|Part|1|10.3,0.6,0.36|548.59,69.75,-540.71|Plots/7
Part|Part|1|10.3,0.6,0.28|548.59,69.75,-519.71|Plots/7
Part|Part|1|10.3,0.6,0.36|548.59,69.75,-519.71|Plots/7
Part|Part|1|10.3,0.6,0.28|548.59,69.75,-509.21|Plots/7
Part|Part|1|10.3,0.6,0.36|548.59,69.75,-509.21|Plots/7
Part|Part|1|10.3,0.6,0.28|543.34,69.75,-503.96|Plots/7
Part|Part|1|10.3,0.6,0.36|543.34,69.75,-503.96|Plots/7
Part|Part|1|10.3,0.6,0.28|532.84,69.75,-503.96|Plots/7
Part|Part|1|10.3,0.6,0.36|532.84,69.75,-503.96|Plots/7
Part|Part|1|10.3,0.6,0.28|511.84,69.75,-503.96|Plots/7
Part|Part|1|10.3,0.6,0.36|511.84,69.75,-503.96|Plots/7
Part|Part|1|10.3,0.6,0.28|501.34,69.75,-503.96|Plots/7
Part|Part|1|10.3,0.6,0.36|501.34,69.75,-503.96|Plots/7
Part|Part|1|9.5,0.6,0.5|501.34,71.13,-503.96|Plots/7
Part|Part|1|1,4,1|506.59,69.53,-503.96|Plots/7
Part|Part|1|9.5,0.6,0.5|501.34,68.38,-503.96|Plots/7
Part|Part|1|1,4,1|496.09,69.53,-503.96|Plots/7
Part|Part|1|1,4,1|506.59,69.53,-556.46|Plots/7
Part|Part|1|9.5,0.6,0.5|501.34,68.38,-556.46|Plots/7
Part|Part|1|1,4,1|496.09,69.53,-556.46|Plots/7
Part|Part|1|9.5,0.6,0.5|501.34,71.13,-556.46|Plots/7
Part|Part|1|1,4,1|548.59,69.53,-535.46|Plots/7
Part|Part|1|1,4,1|548.59,69.53,-524.96|Plots/7
Part|Part|1|9.5,0.6,0.5|548.59,68.38,-530.21|Plots/7
Part|Part|1|9.5,0.6,0.5|548.59,71.13,-530.21|Plots/7
Part|Part|1|1,4,1|496.09,69.53,-556.46|Plots/7
Part|Part|1|9.5,0.6,0.5|496.09,68.38,-551.21|Plots/7
Part|Part|1|9.5,0.6,0.5|496.09,71.13,-551.21|Plots/7
Part|Part|1|1,4,1|496.09,69.53,-545.96|Plots/7
Part|Part|1|9.5,0.6,0.5|522.34,71.13,-556.46|Plots/7
Part|Part|1|9.5,0.6,0.5|522.34,68.38,-556.46|Plots/7
Part|Part|1|1,4,1|517.09,69.53,-556.46|Plots/7
Part|Part|1|1,4,1|527.59,69.53,-556.46|Plots/7
Part|Part|1|9.5,0.6,0.5|532.84,71.13,-556.46|Plots/7
Part|Part|1|1,4,1|527.59,69.53,-556.46|Plots/7
Part|Part|1|9.5,0.6,0.5|532.84,68.38,-556.46|Plots/7
Part|Part|1|1,4,1|538.09,69.53,-556.46|Plots/7
Part|Part|1|9.5,0.6,0.5|496.09,68.38,-540.71|Plots/7
Part|Part|1|1,4,1|496.09,69.53,-535.46|Plots/7
Part|Part|1|9.5,0.6,0.5|496.09,71.13,-540.71|Plots/7
Part|Part|1|1,4,1|496.09,69.53,-545.96|Plots/7
Part|Part|1|1,4,1|496.09,69.53,-535.46|Plots/7
Part|Part|1|9.5,0.6,0.5|496.09,68.38,-530.21|Plots/7
Part|Part|1|9.5,0.6,0.5|496.09,71.13,-530.21|Plots/7
Part|Part|1|1,4,1|496.09,69.53,-524.96|Plots/7
Part|Part|1|9.5,0.6,0.5|548.59,68.38,-509.21|Plots/7
Part|Part|1|9.5,0.6,0.5|548.59,71.13,-509.21|Plots/7
Part|Part|1|1,4,1|548.59,69.53,-514.46|Plots/7
Part|Part|1|1,4,1|548.59,69.53,-503.96|Plots/7
Part|Part|1|1,4,1|548.59,69.53,-503.96|Plots/7
Part|Part|1|9.5,0.6,0.5|543.34,68.38,-503.96|Plots/7
Part|Part|1|1,4,1|538.09,69.53,-503.96|Plots/7
Part|Part|1|9.5,0.6,0.5|543.34,71.13,-503.96|Plots/7
Part|Part|1|9.5,0.6,0.5|548.59,68.38,-551.21|Plots/7
Part|Part|1|1,4,1|548.59,69.53,-556.46|Plots/7
Part|Part|1|9.5,0.6,0.5|548.59,71.13,-551.21|Plots/7
Part|Part|1|1,4,1|548.59,69.53,-545.96|Plots/7
Part|Part|1|9.5,0.6,0.5|532.84,71.13,-503.96|Plots/7
Part|Part|1|9.5,0.6,0.5|532.84,68.38,-503.96|Plots/7
Part|Part|1|1,4,1|527.59,69.53,-503.96|Plots/7
Part|Part|1|1,4,1|538.09,69.53,-503.96|Plots/7
Part|Part|1|1,4,1|496.09,69.53,-524.96|Plots/7
Part|Part|1|9.5,0.6,0.5|496.09,68.38,-519.71|Plots/7
Part|Part|1|1,4,1|496.09,69.53,-514.46|Plots/7
Part|Part|1|9.5,0.6,0.5|496.09,71.13,-519.71|Plots/7
Part|Part|1|1,4,1|548.59,69.53,-535.46|Plots/7
Part|Part|1|9.5,0.6,0.5|548.59,71.13,-540.71|Plots/7
Part|Part|1|9.5,0.6,0.5|548.59,68.38,-540.71|Plots/7
Part|Part|1|1,4,1|548.59,69.53,-545.96|Plots/7
Part|Part|1|9.5,0.6,0.5|511.84,68.38,-503.96|Plots/7
Part|Part|1|1,4,1|517.09,69.53,-503.96|Plots/7
Part|Part|1|9.5,0.6,0.5|511.84,71.13,-503.96|Plots/7
Part|Part|1|1,4,1|506.59,69.53,-503.96|Plots/7
Part|Part|1|1,4,1|517.09,69.53,-556.46|Plots/7
Part|Part|1|9.5,0.6,0.5|511.84,71.13,-556.46|Plots/7
Part|Part|1|1,4,1|506.59,69.53,-556.46|Plots/7
Part|Part|1|9.5,0.6,0.5|511.84,68.38,-556.46|Plots/7
Part|Part|1|9.5,0.6,0.5|496.09,71.13,-509.21|Plots/7
Part|Part|1|1,4,1|496.09,69.53,-514.46|Plots/7
Part|Part|1|9.5,0.6,0.5|496.09,68.38,-509.21|Plots/7
Part|Part|1|1,4,1|496.09,69.53,-503.96|Plots/7
Part|Part|1|9.5,0.6,0.5|543.34,68.38,-556.46|Plots/7
Part|Part|1|1,4,1|538.09,69.53,-556.46|Plots/7
Part|Part|1|1,4,1|548.59,69.53,-556.46|Plots/7
Part|Part|1|9.5,0.6,0.5|543.34,71.13,-556.46|Plots/7
Part|Part|1|9.5,0.6,0.5|548.59,68.38,-519.71|Plots/7
Part|Part|1|9.5,0.6,0.5|548.59,71.13,-519.71|Plots/7
Part|Part|1|1,4,1|548.59,69.53,-514.46|Plots/7
Part|Part|1|1,4,1|548.59,69.53,-524.96|Plots/7
Support|Part|1|1,1.57,1|466.84,68.4,-272.88|Plots/2
Sign|Part|1|1,2.83,4.97|466.84,70.38,-272.95|Plots/2
Support|Part|1|1,1.57,1|474.16,68.4,-296.69|Plots/2
Sign|Part|1|1,2.83,5.23|474.15,70.38,-296.63|Plots/2
GatePart|Part|1|0.5,2.75,0.6|465.4,70.05,-283.78|Plots/2
Hinge|Part|1|0.5,2.75,0.6|465.4,70.05,-288.03|Plots/2
GatePart|Part|1|0.5,3.65,0.6|465.4,71.13,-285.9|Plots/2
GatePart|Part|1|0.5,4.85,0.6|465.4,68.38,-285.9|Plots/2
GatePart|Part|1|0.5,4.85,0.6|465.4,68.38,-280.8|Plots/2
GatePart|Part|1|0.5,3.65,0.6|465.4,71.13,-280.8|Plots/2
Hinge|Part|1|0.5,2.75,0.6|465.4,70.05,-278.68|Plots/2
GatePart|Part|1|0.2,4.42,0.6|465.4,69.75,-280.8|Plots/2
GatePart|Part|1|0.5,2.75,0.6|465.4,70.05,-282.93|Plots/2
GatePart|Part|1|0.25,4.4,0.6|465.4,69.75,-280.8|Plots/2
GatePart|Part|1|0.2,4.39,0.6|465.4,69.75,-285.9|Plots/2
GatePart|Part|1|0.25,4.45,0.6|465.4,69.75,-285.9|Plots/2
Part|Part|1|1,4,1|465.4,69.53,-288.63|Plots/2
Part|Part|1|1,4,1|465.4,69.53,-278.13|Plots/2
Part|Part|1|10.3,0.6,0.36|418.15,69.75,-257.13|Plots/2
Part|Part|1|10.3,0.6,0.28|418.15,69.75,-257.13|Plots/2
Part|Part|1|10.3,0.6,0.36|439.15,69.75,-257.13|Plots/2
Part|Part|1|10.3,0.6,0.28|439.15,69.75,-257.13|Plots/2
Part|Part|1|10.3,0.6,0.28|428.65,69.75,-257.13|Plots/2
Part|Part|1|10.3,0.6,0.36|428.65,69.75,-257.13|Plots/2
Part|Part|1|10.3,0.6,0.28|449.65,69.75,-257.13|Plots/2
Part|Part|1|10.3,0.6,0.36|449.65,69.75,-257.13|Plots/2
Part|Part|1|10.3,0.6,0.28|460.15,69.75,-257.13|Plots/2
Part|Part|1|10.3,0.6,0.36|460.15,69.75,-257.13|Plots/2
Part|Part|1|10.3,0.6,0.28|412.9,69.75,-304.38|Plots/2
Part|Part|1|10.3,0.6,0.36|412.9,69.75,-304.38|Plots/2
Part|Part|1|10.3,0.6,0.28|412.9,69.75,-293.88|Plots/2
Part|Part|1|10.3,0.6,0.36|412.9,69.75,-293.88|Plots/2
Part|Part|1|10.3,0.6,0.28|412.9,69.75,-283.38|Plots/2
Part|Part|1|10.3,0.6,0.36|412.9,69.75,-283.38|Plots/2
Part|Part|1|10.3,0.6,0.28|412.9,69.75,-272.88|Plots/2
Part|Part|1|10.3,0.6,0.36|412.9,69.75,-272.88|Plots/2
Part|Part|1|10.3,0.6,0.28|412.9,69.75,-262.38|Plots/2
Part|Part|1|10.3,0.6,0.36|412.9,69.75,-262.38|Plots/2
Part|Part|1|10.3,0.6,0.36|418.15,69.75,-309.63|Plots/2
Part|Part|1|10.3,0.6,0.28|418.15,69.75,-309.63|Plots/2
Part|Part|1|10.3,0.6,0.36|439.15,69.75,-309.63|Plots/2
Part|Part|1|10.3,0.6,0.28|439.15,69.75,-309.63|Plots/2
Part|Part|1|10.3,0.6,0.28|428.65,69.75,-309.63|Plots/2
Part|Part|1|10.3,0.6,0.36|428.65,69.75,-309.63|Plots/2
Part|Part|1|10.3,0.6,0.28|449.65,69.75,-309.63|Plots/2
Part|Part|1|10.3,0.6,0.36|449.65,69.75,-309.63|Plots/2
Part|Part|1|10.3,0.6,0.28|460.15,69.75,-309.63|Plots/2
Part|Part|1|10.3,0.6,0.36|460.15,69.75,-309.63|Plots/2
Part|Part|1|10.3,0.6,0.28|465.4,69.75,-304.38|Plots/2
Part|Part|1|10.3,0.6,0.36|465.4,69.75,-304.38|Plots/2
Part|Part|1|10.3,0.6,0.28|465.4,69.75,-293.88|Plots/2
Part|Part|1|10.3,0.6,0.36|465.4,69.75,-293.88|Plots/2
Part|Part|1|10.3,0.6,0.28|465.4,69.75,-272.88|Plots/2
Part|Part|1|10.3,0.6,0.36|465.4,69.75,-272.88|Plots/2
Part|Part|1|10.3,0.6,0.28|465.4,69.75,-262.38|Plots/2
Part|Part|1|10.3,0.6,0.36|465.4,69.75,-262.38|Plots/2
Part|Part|1|9.5,0.6,0.5|465.4,71.13,-262.38|Plots/2
Part|Part|1|1,4,1|465.4,69.53,-267.63|Plots/2
Part|Part|1|9.5,0.6,0.5|465.4,68.38,-262.38|Plots/2
Part|Part|1|1,4,1|465.4,69.53,-257.13|Plots/2
Part|Part|1|1,4,1|412.9,69.53,-267.63|Plots/2
Part|Part|1|9.5,0.6,0.5|412.9,68.38,-262.38|Plots/2
Part|Part|1|1,4,1|412.9,69.53,-257.13|Plots/2
Part|Part|1|9.5,0.6,0.5|412.9,71.13,-262.38|Plots/2
Part|Part|1|1,4,1|433.9,69.53,-309.63|Plots/2
Part|Part|1|1,4,1|444.4,69.53,-309.63|Plots/2
Part|Part|1|9.5,0.6,0.5|439.15,68.38,-309.63|Plots/2
Part|Part|1|9.5,0.6,0.5|439.15,71.13,-309.63|Plots/2
Part|Part|1|1,4,1|412.9,69.53,-257.13|Plots/2
Part|Part|1|9.5,0.6,0.5|418.15,68.38,-257.13|Plots/2
Part|Part|1|9.5,0.6,0.5|418.15,71.13,-257.13|Plots/2
Part|Part|1|1,4,1|423.4,69.53,-257.13|Plots/2
Part|Part|1|9.5,0.6,0.5|412.9,71.13,-283.38|Plots/2
Part|Part|1|9.5,0.6,0.5|412.9,68.38,-283.38|Plots/2
Part|Part|1|1,4,1|412.9,69.53,-278.13|Plots/2
Part|Part|1|1,4,1|412.9,69.53,-288.63|Plots/2
Part|Part|1|9.5,0.6,0.5|412.9,71.13,-293.88|Plots/2
Part|Part|1|1,4,1|412.9,69.53,-288.63|Plots/2
Part|Part|1|9.5,0.6,0.5|412.9,68.38,-293.88|Plots/2
Part|Part|1|1,4,1|412.9,69.53,-299.13|Plots/2
Part|Part|1|9.5,0.6,0.5|428.65,68.38,-257.13|Plots/2
Part|Part|1|1,4,1|433.9,69.53,-257.13|Plots/2
Part|Part|1|9.5,0.6,0.5|428.65,71.13,-257.13|Plots/2
Part|Part|1|1,4,1|423.4,69.53,-257.13|Plots/2
Part|Part|1|1,4,1|433.9,69.53,-257.13|Plots/2
Part|Part|1|9.5,0.6,0.5|439.15,68.38,-257.13|Plots/2
Part|Part|1|9.5,0.6,0.5|439.15,71.13,-257.13|Plots/2
Part|Part|1|1,4,1|444.4,69.53,-257.13|Plots/2
Part|Part|1|9.5,0.6,0.5|460.15,68.38,-309.63|Plots/2
Part|Part|1|9.5,0.6,0.5|460.15,71.13,-309.63|Plots/2
Part|Part|1|1,4,1|454.9,69.53,-309.63|Plots/2
Part|Part|1|1,4,1|465.4,69.53,-309.63|Plots/2
Part|Part|1|1,4,1|465.4,69.53,-309.63|Plots/2
Part|Part|1|9.5,0.6,0.5|465.4,68.38,-304.38|Plots/2
Part|Part|1|1,4,1|465.4,69.53,-299.13|Plots/2
Part|Part|1|9.5,0.6,0.5|465.4,71.13,-304.38|Plots/2
Part|Part|1|9.5,0.6,0.5|418.15,68.38,-309.63|Plots/2
Part|Part|1|1,4,1|412.9,69.53,-309.63|Plots/2
Part|Part|1|9.5,0.6,0.5|418.15,71.13,-309.63|Plots/2
Part|Part|1|1,4,1|423.4,69.53,-309.63|Plots/2
Part|Part|1|9.5,0.6,0.5|465.4,71.13,-293.88|Plots/2
Part|Part|1|9.5,0.6,0.5|465.4,68.38,-293.88|Plots/2
Part|Part|1|1,4,1|465.4,69.53,-288.63|Plots/2
Part|Part|1|1,4,1|465.4,69.53,-299.13|Plots/2
Part|Part|1|1,4,1|444.4,69.53,-257.13|Plots/2
Part|Part|1|9.5,0.6,0.5|449.65,68.38,-257.13|Plots/2
Part|Part|1|1,4,1|454.9,69.53,-257.13|Plots/2
Part|Part|1|9.5,0.6,0.5|449.65,71.13,-257.13|Plots/2
Part|Part|1|1,4,1|433.9,69.53,-309.63|Plots/2
Part|Part|1|9.5,0.6,0.5|428.65,71.13,-309.63|Plots/2
Part|Part|1|9.5,0.6,0.5|428.65,68.38,-309.63|Plots/2
Part|Part|1|1,4,1|423.4,69.53,-309.63|Plots/2
Part|Part|1|9.5,0.6,0.5|465.4,68.38,-272.88|Plots/2
Part|Part|1|1,4,1|465.4,69.53,-278.13|Plots/2
Part|Part|1|9.5,0.6,0.5|465.4,71.13,-272.88|Plots/2
Part|Part|1|1,4,1|465.4,69.53,-267.63|Plots/2
Part|Part|1|1,4,1|412.9,69.53,-278.13|Plots/2
Part|Part|1|9.5,0.6,0.5|412.9,71.13,-272.88|Plots/2
Part|Part|1|1,4,1|412.9,69.53,-267.63|Plots/2
Part|Part|1|9.5,0.6,0.5|412.9,68.38,-272.88|Plots/2
Part|Part|1|9.5,0.6,0.5|460.15,71.13,-257.13|Plots/2
Part|Part|1|1,4,1|454.9,69.53,-257.13|Plots/2
Part|Part|1|9.5,0.6,0.5|460.15,68.38,-257.13|Plots/2
Part|Part|1|1,4,1|465.4,69.53,-257.13|Plots/2
Part|Part|1|9.5,0.6,0.5|412.9,68.38,-304.38|Plots/2
Part|Part|1|1,4,1|412.9,69.53,-299.13|Plots/2
Part|Part|1|1,4,1|412.9,69.53,-309.63|Plots/2
Part|Part|1|9.5,0.6,0.5|412.9,71.13,-304.38|Plots/2
Part|Part|1|9.5,0.6,0.5|449.65,68.38,-309.63|Plots/2
Part|Part|1|9.5,0.6,0.5|449.65,71.13,-309.63|Plots/2
Part|Part|1|1,4,1|454.9,69.53,-309.63|Plots/2
Part|Part|1|1,4,1|444.4,69.53,-309.63|Plots/2
Part|Part|1|0.48,9.13,0.57|541.14,72.4,-423.46|Stands
Part|Part|1|5.33,0.81,0.18|532.67,68.77,-427.75|Stands
Part|Part|1|0.13,1.28,0.57|531.36,75.57,-430.2|Stands
Part|Part|1|0.48,9.13,0.57|536.82,72.4,-432.71|Stands
Part|Part|1|0.48,6.28,0.57|534.53,76.4,-431.63|Stands
Crooked Plank|Part|1|5.82,0.81,0.18|532.77,69.73,-427.53|Stands
Part|Part|1|4.44,0.81,0.18|534.92,69.64,-422.94|Stands
Part|Part|1|0.48,11.28,0.57|533.99,75.48,-425.75|Stands
Shop Stand|Part|1|11.07,0.24,1.51|533.96,70.51,-425.71|Stands
Part|Part|1|1.29,6.84,0.12|536.5,76.69,-426.91|Stands
Part|Part|1|0.13,1.27,0.57|534.08,75.57,-424.37|Stands
Part|Part|1|0.13,1.28,0.57|535.71,75.57,-420.86|Stands
Part|Part|1|1.29,6.84,0.12|537.04,76.69,-425.75|Stands
Part|Part|1|0.13,1.28,0.57|533.54,75.57,-425.54|Stands
Part|Part|1|0.48,7.84,0.57|531.85,71.75,-430.39|Stands
Part|Part|1|1.29,6.84,0.12|534.87,76.69,-430.42|Stands
Part|Part|1|0.48,7.84,0.57|536.17,71.75,-421.12|Stands
Part|Part|1|0.13,1.27,0.57|535.17,75.57,-422.02|Stands
Crooked Plank2|Part|1|5.03,0.81,0.18|534.79,68.73,-423.21|Stands
Part|Part|1|0.13,1.28,0.57|534.63,75.57,-423.19|Stands
Part|Part|1|1.29,6.84,0.12|537.59,76.69,-424.58|Stands
Part|Part|1|1.29,6.84,0.12|538.68,76.69,-422.25|Stands
Part|Part|1|0.13,1.27,0.57|532.99,75.57,-426.7|Stands
Part|Part|1|0.13,1.27,0.57|531.91,75.57,-429.03|Stands
Part|Part|1|1.29,6.84,0.12|538.14,76.69,-423.4|Stands
Part|Part|1|1.29,6.84,0.12|535.96,76.69,-428.08|Stands
Part|Part|1|1.29,6.84,0.12|534.32,76.69,-431.6|Stands
Part|Part|1|0.48,6.24,0.57|538.87,76.41,-422.38|Stands
Part|Part|1|0.13,1.29,0.57|532.45,75.57,-427.87|Stands
Part|Part|1|0.48,11.28,0.57|538.94,77.11,-428.06|Stands
Part|Part|1|1.29,6.84,0.12|535.42,76.69,-429.24|Stands
Wedge|WedgePart|1|0.25,0.38,0.38|531.29,74.67,-306.81|Stands
Part|Part|1|0.38,0.5,1|537.17,76.57,-298.8|Stands
Wedge|WedgePart|1|0.25,0.38,0.38|530.8,74.67,-306.43|Stands
Wedge|WedgePart|1|0.25,0.38,0.38|531.59,74.67,-307.04|Stands
Part|Part|1|0.38,0.25,0.25|531.04,74.67,-306.62|Stands
Wedge|WedgePart|1|0.25,0.38,0.38|537.65,75.94,-298.7|Stands
Part|Part|1|0.63,0.25,1|531.79,75.16,-307.29|Stands
Part|Part|1|0.63,0.25,1|537.4,76.44,-298.51|Stands
Part|Part|1|0.38,0.25,0.25|538.19,75.94,-299.12|Stands
Wedge|WedgePart|1|0.25,0.38,0.38|532.08,74.67,-307.43|Stands
Part|Part|1|0.38,0.25,0.25|537.4,75.94,-298.51|Stands
Part|Part|1|0.38,9.88,1|534.01,75.93,-302.83|Stands
Wedge|WedgePart|1|0.25,0.38,0.38|537.15,75.94,-298.31|Stands
Wedge|WedgePart|1|0.25,0.38,0.38|538.43,75.94,-299.32|Stands
Part|Part|1|0.63,0.25,1|538.19,76.44,-299.12|Stands
Wedge|WedgePart|1|0.25,0.38,0.38|537.94,75.94,-298.93|Stands
Part|Part|1|0.63,0.25,1|531,75.16,-306.67|Stands
Part|Part|1|0.38,9.88,1|534.8,75.93,-303.45|Stands
Part|Part|1|0.38,0.5,1|537.96,76.57,-299.42|Stands
Part|Part|1|0.38,0.25,0.25|531.83,74.67,-307.24|Stands
Part|Part|1|0.38,0.25,0.25|529.47,74.67,-305.39|Stands
Part|Part|1|0.63,0.25,1|530.22,75.16,-306.06|Stands
Part|Part|1|0.63,0.25,1|535.83,76.44,-297.27|Stands
Part|Part|1|0.38,0.5,1|535.6,76.57,-297.57|Stands
Wedge|WedgePart|1|0.25,0.38,0.38|536.86,75.94,-298.08|Stands
Part|Part|1|0.38,0.5,1|536.38,76.57,-298.18|Stands
Part|Part|1|0.38,0.25,0.25|530.26,74.67,-306|Stands
Wedge|WedgePart|1|0.25,0.38,0.38|529.22,74.67,-305.19|Stands
Part|Part|1|0.63,0.25,1|529.43,75.16,-305.44|Stands
Part|Part|1|0.63,0.25,1|536.61,76.44,-297.89|Stands
Wedge|WedgePart|1|0.25,0.38,0.38|529.72,74.67,-305.58|Stands
Wedge|WedgePart|1|0.25,0.38,0.38|530.01,74.67,-305.81|Stands
Part|Part|1|0.38,9.88,1|533.23,75.93,-302.21|Stands
Wedge|WedgePart|1|0.25,0.38,0.38|536.37,75.94,-297.7|Stands
Wedge|WedgePart|1|0.25,0.38,0.38|536.07,75.94,-297.47|Stands
Wedge|WedgePart|1|0.25,0.38,0.38|535.58,75.94,-297.08|Stands
Part|Part|1|0.38,0.25,0.25|536.61,75.94,-297.89|Stands
Wedge|WedgePart|1|0.25,0.38,0.38|530.5,74.67,-306.2|Stands
Part|Part|1|0.38,9.88,1|532.44,75.93,-301.6|Stands
Part|Part|1|0.38,0.25,0.25|535.83,75.94,-297.27|Stands
Part|Part|1|0.63,0.25,1|541.34,76.44,-301.59|Stands
Wedge|WedgePart|1|0.25,0.38,0.38|534.44,74.67,-309.28|Stands
Wedge|WedgePart|1|0.25,0.38,0.38|541.09,75.94,-301.4|Stands
Wedge|WedgePart|1|0.25,0.38,0.38|540.3,75.94,-300.78|Stands
Part|Part|1|0.38,0.5,1|541.11,76.57,-301.88|Stands
Wedge|WedgePart|1|0.25,0.38,0.38|540.8,75.94,-301.17|Stands
Part|Part|1|0.63,0.25,1|534.15,75.16,-309.14|Stands
Part|Part|1|0.38,9.88,1|537.95,75.93,-305.91|Stands
Wedge|WedgePart|1|0.25,0.38,0.38|541.58,75.94,-301.78|Stands
Wedge|WedgePart|1|0.25,0.38,0.38|533.95,74.67,-308.89|Stands
Part|Part|1|0.63,0.25,1|540.55,76.44,-300.97|Stands
Part|Part|1|0.38,0.5,1|540.32,76.57,-301.27|Stands
Part|Part|1|0.63,0.25,1|534.94,75.16,-309.76|Stands
Part|Part|1|0.38,0.25,0.25|541.34,75.94,-301.59|Stands
Part|Part|1|0.38,0.25,0.25|540.55,75.94,-300.97|Stands
Part|Part|1|0.38,0.25,0.25|534.19,74.67,-309.09|Stands
Part|Part|1|0.38,0.25,0.25|534.98,74.67,-309.7|Stands
Wedge|WedgePart|1|0.25,0.38,0.38|534.74,74.67,-309.51|Stands
Wedge|WedgePart|1|0.25,0.38,0.38|535.23,74.67,-309.9|Stands
Part|Part|1|0.38,9.88,1|537.16,75.93,-305.3|Stands
Part|Part|1|0.63,0.25,1|538.98,76.44,-299.74|Stands
Wedge|WedgePart|1|0.25,0.38,0.38|539.52,75.94,-300.16|Stands
Wedge|WedgePart|1|0.25,0.38,0.38|539.22,75.94,-299.93|Stands
Part|Part|1|0.38,0.25,0.25|539.76,75.94,-300.36|Stands
Part|Part|1|0.63,0.25,1|539.76,76.44,-300.36|Stands
Part|Part|1|0.38,0.25,0.25|538.98,75.94,-299.74|Stands
Wedge|WedgePart|1|0.25,0.38,0.38|540.01,75.94,-300.55|Stands
Part|Part|1|0.63,0.25,1|532.58,75.16,-307.91|Stands
Part|Part|1|0.38,0.25,0.25|532.62,74.67,-307.85|Stands
Part|Part|1|0.38,9.88,1|535.59,75.93,-304.06|Stands
Part|Part|1|0.38,9.88,1|536.38,75.93,-304.68|Stands
Wedge|WedgePart|1|0.25,0.38,0.38|533.16,74.67,-308.28|Stands
Wedge|WedgePart|1|0.25,0.38,0.38|538.73,75.94,-299.55|Stands
Part|Part|1|0.38,0.5,1|538.75,76.57,-300.03|Stands
Wedge|WedgePart|1|0.25,0.38,0.38|532.37,74.67,-307.66|Stands
Wedge|WedgePart|1|0.25,0.38,0.38|532.87,74.67,-308.05|Stands
Part|Part|1|0.38,0.25,0.25|533.41,74.67,-308.47|Stands
Part|Part|1|0.63,0.25,1|533.37,75.16,-308.52|Stands
Wedge|WedgePart|1|0.25,0.38,0.38|533.65,74.67,-308.66|Stands
Part|Part|1|0.38,0.5,1|539.53,76.57,-300.65|Stands
Wedge|WedgePart|1|0.25,0.38,0.38|534.5,75.94,-296.23|Stands
Part|Part|1|0.38,9.88,1|531.65,75.93,-300.98|Stands
Part|Part|1|0.63,0.25,1|535.04,76.44,-296.66|Stands
Part|Part|1|0.38,9.88,1|530.86,75.93,-300.36|Stands
Wedge|WedgePart|1|0.25,0.38,0.38|534.79,75.94,-296.46|Stands
Wedge|WedgePart|1|0.25,0.38,0.38|528.93,74.67,-304.96|Stands
Wedge|WedgePart|1|0.25,0.38,0.38|535.28,75.94,-296.85|Stands
Part|Part|1|0.38,0.5,1|534.02,76.57,-296.33|Stands
Wedge|WedgePart|1|0.25,0.38,0.38|534.01,75.94,-295.85|Stands
Part|Part|1|0.38,0.25,0.25|534.25,75.94,-296.04|Stands
Part|Part|1|0.63,0.25,1|534.25,76.44,-296.04|Stands
Wedge|WedgePart|1|0.25,0.38,0.38|528.14,74.67,-304.35|Stands
Part|Part|1|0.38,0.25,0.25|528.68,74.67,-304.77|Stands
Part|Part|1|0.38,0.25,0.25|535.04,75.94,-296.66|Stands
Wedge|WedgePart|1|0.25,0.38,0.38|528.44,74.67,-304.58|Stands
Part|Part|1|0.63,0.25,1|527.86,75.16,-304.21|Stands
Wedge|WedgePart|1|0.25,0.38,0.38|527.65,74.67,-303.96|Stands
Part|Part|1|0.38,0.5,1|534.81,76.57,-296.95|Stands
Part|Part|1|0.63,0.25,1|528.64,75.16,-304.82|Stands
Part|Part|1|0.38,0.25,0.25|527.9,74.67,-304.15|Stands
Part|Part|1|0.5,4.75,0.5|535.26,72.93,-309.15|Stands
Part|Part|1|1,0.5,1|535.26,67.93,-309.15|Stands
Part|Part|1|0.75,2.88,0.75|535.26,69.12,-309.15|Stands
Part|Part|1|0.75,0.25,0.75|540.5,70.8,-302.45|Stands
Part|Part|1|1,0.5,1|533.51,69.93,-296.98|Stands
Part|Part|1|0.75,2.88,0.75|533.51,69.12,-296.98|Stands
Part|Part|1|0.25,0.25,9.75|531.81,75.05,-306.45|Stands
Part|Part|1|0.75,0.25,0.75|528.27,70.8,-303.67|Stands
Part|Part|1|0.75,2.88,0.75|528.27,69.12,-303.67|Stands
Part|Part|1|0.25,0.25,9|532.01,69.3,-306.6|Stands
Part|Part|1|0.25,8.63,0.25|537.8,75.6,-305.9|Stands
Part|Part|1|0.25,8.63,0.25|530.81,75.6,-300.43|Stands
Part|Part|1|0.75,2.88,0.75|540.5,69.12,-302.45|Stands
Part|Part|1|0.25,0.25,9|537.96,68.55,-305.7|Stands
Part|Part|1|0.25,0.25,9|532.01,68.55,-306.6|Stands
Part|Part|1|0.25,0.25,9|530.97,69.3,-300.23|Stands
Part|Part|1|0.25,0.25,9.25|537.25,76.18,-299.91|Stands
Part|Part|1|0.5,5.88,0.5|540.5,73.49,-302.45|Stands
Part|Part|1|0.5,5.88,0.5|533.51,73.49,-296.98|Stands
Part|Part|1|1,0.5,1|528.27,69.93,-303.67|Stands
Part|Part|1|0.5,4.75,0.5|528.27,72.93,-303.67|Stands
Part|Part|1|0.25,0.25,9|530.97,68.55,-300.23|Stands
Part|Part|1|1,0.5,1|533.51,67.93,-296.98|Stands
Part|Part|1|1.5,0.25,7.38|531.76,70.55,-306.41|Stands
Part|Part|1|1,0.5,1|540.5,69.93,-302.45|Stands
Part|Part|1|1.5,0.25,10|537.88,70.55,-305.8|Stands
Part|Part|1|1,0.5,1|535.26,69.93,-309.15|Stands
Part|Part|1|0.25,0.25,9|537.96,69.3,-305.7|Stands
Part|Part|1|1,0.5,1|528.27,67.93,-303.67|Stands
Part|Part|1|1.5,0.25,10|530.89,70.55,-300.33|Stands
Part|Part|1|1,0.5,1|540.5,67.93,-302.45|Stands
Part|Part|1|0.75,0.25,0.75|535.26,70.8,-309.15|Stands
Part|Part|1|0.75,0.25,0.75|533.51,70.8,-296.98|Stands
SellPrompt|MeshPart|1|16.32,0.28,16.36|532.15,67.8,-425.33|Stands
Radius|Part|1|0.17,15.3,15.3|532.15,67.66,-425.33|Stands
GroupReward|MeshPart|1|13.76,0.24,13.79|544.36,67.8,-288.49|Stands
Radius|Part|0|0.14,12.89,12.89|544.32,67.68,-288.27|Stands
TrailShop|MeshPart|1|16.32,0.28,16.36|531.23,67.8,-307.1|Stands
Radius|Part|0|0.17,15.3,15.3|531.17,67.66,-306.84|Stands
Part|Part|0|10.82,36.94,385.2|1758.53,85.56,-439.21|Build/1
Part|Part|0|10.82,36.94,96.66|600.64,85.56,-439.21|Build/1
Part|Part|0|10.82,36.94,211.71|900.78,85.56,-439.21|Build/1
Part|Part|0|10.82,36.94,235.49|1124.38,85.56,-439.21|Build/1
Part|Part|0|10.82,36.94,505.04|2633.09,85.56,-439.21|Build/1
Part|Part|0|10.82,36.94,429.41|2165.88,85.56,-439.21|Build/1
Part|Part|0|10.82,36.94,640.02|3205.53,85.56,-439.21|Build/1
Part|Part|0|10.82,36.94,324.2|1404.03,85.56,-439.21|Build/1
Part|Part|0|10.82,36.94,146.2|722.03,85.56,-439.21|Build/1
Part|Part|0|10.82,36.94,96.7|600.62,85.56,-289.21|Build/1
Part1|Part|0|22.82,36.94,247.21|2256.95,85.56,-283.21|Build/1
Part1|Part|0|22.82,36.94,167.21|2034.74,85.56,-283.21|Build/1
Part|Part|0|10.82,36.94,640.02|3205.53,85.56,-289.21|Build/1
Part|Part|0|10.82,36.94,235.49|1124.4,85.56,-289.21|Build/1
Part|Part|0|10.82,36.94,505.04|2633.09,85.56,-289.21|Build/1
Part1|Part|0|22.82,21.56,15|2125.85,93.25,-283.21|Build/1
Part|Part|0|10.82,36.94,146.2|722.05,85.56,-289.21|Build/1
Part|Part|0|10.82,36.94,211.71|900.8,85.56,-289.21|Build/1
Part|Part|0|10.82,36.94,385.2|1758.55,85.56,-289.21|Build/1
FrozenZoneRight|Part|0|10.82,36.94,324.2|1404.05,85.56,-289.21|Build/1
Part|Part|0|146.09,33.15,158.41|722.56,51,-363.5|Build/1
Part|Part|0|210.96,32.53,165.36|901.08,51.31,-366.06|Build/1
Part|Part|0|97.53,32.82,154.09|600.75,51.17,-366.63|Build/1
Part|Part|0|429.11,34.87,161.39|2165.97,50.14,-363.8|Build/1
Part|Part|0|324.11,33.19,161.01|1404.47,50.98,-363.8|Build/1
Part|Part|0|640.11,34.75,163.88|3205.47,50.2,-363.8|Build/1
Part|Part|0|385.11,33.25,163.08|1758.97,50.95,-363.8|Build/1
Part|Part|0|236.11,33.5,160.28|1124.47,50.83,-363.8|Build/1
Part|Part|0|505.11,35.35,158.75|2632.97,49.9,-363.8|Build/1
Part|Part|1|10.82,2,429.43|2165.85,105.03,-439.21|Build/1
Part|Part|1|10.82,2,211.72|900.79,105.03,-439.21|Build/1
FrozenZoneTop|Part|1|10.82,2,324.22|1404.03,105.03,-289.21|Build/1
Part|Part|1|10.82,2,146.22|722.03,105.03,-289.21|Build/1
Part|Part|1|10.82,2,96.64|600.63,105.03,-289.21|Build/1
Part|Part|1|10.82,2,211.72|900.79,105.03,-289.21|Build/1
Part|Part|1|10.82,2,146.22|722.04,105.03,-439.21|Build/1
Part|Part|1|10.82,2,429.43|2165.87,105.03,-289.21|Build/1
Part|Part|1|10.82,2,385.22|1758.53,105.03,-289.21|Build/1
Part|Part|1|10.82,2,640.07|3205.53,105.03,-289.21|Build/1
Part|Part|1|10.82,2,324.22|1404.04,105.03,-439.21|Build/1
Part|Part|1|10.82,2,235.5|1124.4,105.03,-439.21|Build/1
Part|Part|1|10.82,2,385.22|1758.54,105.03,-439.21|Build/1
Part|Part|1|10.82,2,504.93|2633.13,105.03,-439.21|Build/1
Part|Part|1|10.82,2,504.93|2633.05,105.03,-289.21|Build/1
Part|Part|1|10.82,2,97.1|600.42,105.03,-439.21|Build/1
Part|Part|1|10.82,2,235.5|1124.39,105.03,-289.21|Build/1
Part|Part|1|10.82,2,640.07|3205.53,105.03,-439.21|Build/1
Part|Part|1|155.37,1,6|1242.6,67.21,-360.59|Build/3
Part|Part|1|154.8,1,6|2380.6,67.21,-360.59|Build/3
Part|Part|1|163.14,1,6|649.6,67.21,-360.59|Build/3
Part|Part|1|155.42,1,6|1566.6,67.21,-360.59|Build/3
Part|Part|1|163.14,1,6|795.6,67.21,-360.59|Build/3
Part|Part|1|163.14,1,6|1006.6,67.21,-360.59|Build/3
Part|Part|1|155.58,1,6|1951.6,67.21,-360.59|Build/3
Part|Part|1|23.82,2,740.07|3895.53,105.03,-445.71|Build/CherryBlossomZone
Part|Part|1|23.82,2,740.07|3895.53,105.03,-282.71|Build/CherryBlossomZone
Part|Part|0|740.11,34.75,182|3895.47,50.2,-363.81|Build/CherryBlossomZone
Part|Part|1|154.8,1,4|3525.6,67.21,-360.59|Build/CherryBlossomZone
Part|Part|0|21.82,36.94,740.02|3895.53,85.56,-444.71|Build/CherryBlossomZone
Part|Part|0|22.82,36.94,740.02|3895.53,85.56,-283.21|Build/CherryBlossomZone
Part|Part|1|71.32,25.09,12.32|4170.36,80.12,-438.8|Build/CherryBlossomZone
Part|Part|1|42.32,34.09,8.32|3702.43,84.62,-293.3|Build/CherryBlossomZone
Part|Part|1|51.23,34.09,8.32|3950.97,84.62,-293.29|Build/CherryBlossomZone
Part|Part|1|76.32,27.09,8.32|3598.43,81.12,-292.66|Build/CherryBlossomZone
Part|Part|1|76.32,27.09,8.32|4218.55,81.12,-436.37|Build/CherryBlossomZone
Part|Part|1|49.32,16.8,9.32|4212.94,75.98,-435.15|Build/CherryBlossomZone
Part|Part|1|71.32,25.09,12.32|3898.86,80.12,-291.45|Build/CherryBlossomZone
Part|Part|1|61.32,32.09,8.32|3796.36,83.62,-293.42|Build/CherryBlossomZone
Part|Part|1|59.18,27.09,8.32|3966.98,81.12,-435.86|Build/CherryBlossomZone
Part|Part|1|76.32,27.09,8.32|4131.43,81.12,-292.66|Build/CherryBlossomZone
Part|Part|1|71.32,25.09,12.32|3918.12,80.12,-437.58|Build/CherryBlossomZone
Part|Part|1|49.32,16.8,9.32|3779.17,75.98,-293.74|Build/CherryBlossomZone
Part|Part|1|61.32,32.09,8.32|4065.91,83.62,-293.42|Build/CherryBlossomZone
Part|Part|1|59.18,27.09,8.32|3849.99,81.12,-293.17|Build/CherryBlossomZone
Part|Part|1|42.32,34.09,8.32|3581.55,84.62,-435.74|Build/CherryBlossomZone
Part|Part|1|61.32,26.89,8.32|4006.91,81.02,-293.42|Build/CherryBlossomZone
Part|Part|1|42.32,34.09,8.32|4235.43,84.62,-293.3|Build/CherryBlossomZone
Part|Part|1|71.32,25.09,12.32|3637.36,80.12,-438.8|Build/CherryBlossomZone
Part|Part|1|71.32,25.09,12.32|3646.62,80.12,-290.24|Build/CherryBlossomZone
Part|Part|1|61.32,32.09,8.32|4020.62,83.62,-435.62|Build/CherryBlossomZone
Part|Part|1|61.32,26.89,8.32|3750.06,81.02,-293.42|Build/CherryBlossomZone
Part|Part|1|42.32,34.09,8.32|4114.55,84.62,-435.74|Build/CherryBlossomZone
Part|Part|1|61.32,26.89,8.32|3810.07,81.02,-435.62|Build/CherryBlossomZone
Part|Part|1|76.32,27.09,8.32|3685.55,81.12,-436.37|Build/CherryBlossomZone
Part|Part|1|61.32,32.09,8.32|3751.07,83.62,-435.62|Build/CherryBlossomZone
Part|Part|1|49.32,16.8,9.32|4031.14,75.98,-435.16|Build/CherryBlossomZone
Part|Part|1|61.32,26.89,8.32|4066.91,81.02,-435.62|Build/CherryBlossomZone
Part|Part|1|71.32,25.09,12.32|4179.62,80.12,-290.24|Build/CherryBlossomZone
Part|Part|1|51.23,34.09,8.32|3866.01,84.62,-435.75|Build/CherryBlossomZone
Bamboo|Part|1|0.88,12.25,0.88|4160.56,73.73,-419.44|Build/CherryBlossomZone
Bamboo|Part|1|0.88,17.38,0.88|3608.56,76.29,-315.37|Build/CherryBlossomZone
Bamboo|Part|1|0.88,25.38,0.88|4160.56,80.29,-423.37|Build/CherryBlossomZone
Bamboo|Part|1|0.88,10.38,0.88|3690.56,72.79,-304.44|Build/CherryBlossomZone
Bamboo|Part|1|0.88,25.38,0.88|3817.37,80.29,-327.69|Build/CherryBlossomZone
Bamboo|Part|1|0.88,18.38,0.88|3599.44,76.79,-424.56|Build/CherryBlossomZone
Bamboo|Part|1|0.88,20.75,0.88|3777.44,77.98,-423.44|Build/CherryBlossomZone
Bamboo|Part|1|0.88,12.25,0.88|3813.37,73.73,-330.63|Build/CherryBlossomZone
Bamboo|Part|1|0.88,19.75,0.88|4048.56,77.48,-307.44|Build/CherryBlossomZone
Bamboo|Part|1|0.88,10.75,0.88|4054.44,72.98,-315.44|Build/CherryBlossomZone
Bamboo|Part|1|0.88,9.38,0.88|3611.56,72.29,-319.44|Build/CherryBlossomZone
Bamboo|Part|1|0.88,5.38,0.88|3670.44,70.29,-307.44|Build/CherryBlossomZone
Bamboo|Part|1|0.88,4.38,0.88|3661.56,69.79,-325.44|Build/CherryBlossomZone
Bamboo|Part|1|0.88,12.25,0.88|3779.44,73.73,-428.56|Build/CherryBlossomZone
Bamboo|Part|1|0.88,15.75,0.88|3870.56,75.48,-414.56|Build/CherryBlossomZone
Bamboo|Part|1|0.88,8.38,0.88|3777.44,71.79,-418.44|Build/CherryBlossomZone
Bamboo|Part|1|0.88,15.75,0.88|3820.07,75.48,-324.75|Build/CherryBlossomZone
Bamboo|Part|1|0.88,25.38,0.88|3700.8,80.29,-306.75|Build/CherryBlossomZone
Bamboo|Part|1|0.88,16.75,0.88|4053.44,75.98,-311.56|Build/CherryBlossomZone
Bamboo|Part|1|0.88,10.75,0.88|3765.44,72.98,-316.56|Build/CherryBlossomZone
Bamboo|Part|1|0.88,11.38,0.88|3593.44,73.29,-421.56|Build/CherryBlossomZone
Bamboo|Part|1|0.88,7.75,0.88|3762.56,71.48,-313.44|Build/CherryBlossomZone
Bamboo|Part|1|0.88,18.75,0.88|3874.56,76.98,-410.56|Build/CherryBlossomZone
Bamboo|Part|1|0.88,13.75,0.88|3870.56,74.48,-411.44|Build/CherryBlossomZone
Bamboo|Part|1|0.88,15.38,0.88|3589.56,75.29,-423.56|Build/CherryBlossomZone
Bamboo|Part|1|0.88,13.38,0.88|3698.56,74.29,-427.44|Build/CherryBlossomZone
Bamboo|Part|1|0.88,8.38,0.88|3656.44,71.79,-329.56|Build/CherryBlossomZone
Bamboo|Part|1|0.88,8.38,0.88|3695.56,71.79,-422.56|Build/CherryBlossomZone
Bamboo|Part|1|0.88,15.75,0.88|3698.1,75.48,-303.69|Build/CherryBlossomZone
Meshes/untitled_Cube (2)|MeshPart|1|3.13,7.63,3.13|4018.44,71.39,-301.56|Build/CherryBlossomZone
Meshes/untitled_Cube.001 (1)|MeshPart|1|1.95,1,1.95|4018.44,72.24,-301.56|Build/CherryBlossomZone
Meshes/untitled_Cube (2)|MeshPart|1|3.13,7.63,3.13|3778.56,71.39,-413.56|Build/CherryBlossomZone
Meshes/untitled_Cube.001 (1)|MeshPart|1|1.95,1,1.95|3778.56,72.24,-413.56|Build/CherryBlossomZone
Meshes/untitled_Cube (2)|MeshPart|1|5.58,13.63,5.58|3995.21,74.39,-425.21|Build/CherryBlossomZone
Meshes/untitled_Cube.001 (1)|MeshPart|1|3.48,1.79,3.48|3995.21,75.9,-425.21|Build/CherryBlossomZone
Meshes/untitled_Cube.001 (1)|MeshPart|1|1.95,1,1.95|3612.44,72.24,-304.44|Build/CherryBlossomZone
Meshes/untitled_Cube (2)|MeshPart|1|3.13,7.63,3.13|3612.44,71.39,-304.44|Build/CherryBlossomZone
Meshes/untitled_Cylinder (1)|MeshPart|1|18.07,0.3,18.07|3899.42,67.53,-320.42|Build/CherryBlossomZone
Meshes/untitled_Plane (1)|MeshPart|1|4,0.75,4|3896.44,68.16,-319.85|Build/CherryBlossomZone
Meshes/untitled_Cylinder (1)|MeshPart|1|7.75,0.3,7.75|3615.73,67.75,-411.37|Build/CherryBlossomZone
Meshes/untitled_Cylinder (1)|MeshPart|1|9.44,0.36,9.44|3904.19,67.72,-411.5|Build/CherryBlossomZone
Meshes/untitled_Cylinder (1)|MeshPart|1|5.48,0.21,5.48|3620.42,67.71,-420.21|Build/CherryBlossomZone
Meshes/untitled_Cylinder (1)|MeshPart|1|13.77,0.23,13.77|3652.12,67.72,-308.12|Build/CherryBlossomZone
Meshes/untitled_Plane (1)|MeshPart|1|4.49,0.84,4.49|3655.55,68.34,-306.56|Build/CherryBlossomZone
Meshes/untitled_Plane (1)|MeshPart|1|5.04,0.94,5.04|4122.56,68.43,-308.92|Build/CherryBlossomZone
Meshes/untitled_Cylinder (1)|MeshPart|1|15.45,0.26,15.45|4120.23,67.73,-310.47|Build/CherryBlossomZone
Meshes/untitled_Cylinder (1)|MeshPart|1|5.48,0.21,5.48|4137.26,67.71,-412.74|Build/CherryBlossomZone
Meshes/untitled_Cylinder (1)|MeshPart|1|5.48,0.21,5.48|4007.26,67.71,-309.26|Build/CherryBlossomZone
Meshes/untitled_Cylinder (1)|MeshPart|1|12.84,0.49,12.84|3810.79,67.65,-314.79|Build/CherryBlossomZone
Meshes/untitled_Cylinder (1)|MeshPart|1|5.48,0.21,5.48|3640.44,67.71,-309.78|Build/CherryBlossomZone
Meshes/untitled_Plane (1)|MeshPart|1|2.8,0.52,2.8|3642.88,68.24,-320.21|Build/CherryBlossomZone
Meshes/untitled_Cylinder (1)|MeshPart|1|8.59,0.33,8.59|3644.54,67.77,-318.54|Build/CherryBlossomZone
Meshes/untitled_Cylinder (1)|MeshPart|1|9.44,0.36,9.44|3800.5,67.72,-325.5|Build/CherryBlossomZone
Meshes/untitled_Cylinder (1)|MeshPart|1|8.35,0.32,8.35|3914.21,67.74,-423.21|Build/CherryBlossomZone
Meshes/untitled_Plane (1)|MeshPart|1|4.49,0.84,4.49|3759.67,68.34,-418.55|Build/CherryBlossomZone
Meshes/untitled_Cylinder (1)|MeshPart|1|13.77,0.23,13.77|3758.12,67.72,-415.12|Build/CherryBlossomZone
Meshes/untitled_Plane (1)|MeshPart|1|3.2,0.6,3.2|3885.22,68.13,-306.9|Build/CherryBlossomZone
Meshes/untitled_Cylinder (1)|MeshPart|1|13.77,0.23,13.77|3886.88,67.72,-308.88|Build/CherryBlossomZone
Meshes/untitled_Cylinder.001 (1)|MeshPart|1|11.59,15.43,11.59|3847.6,75.29,-429.39|Build/CherryBlossomZone
Meshes/untitled_Cylinder.002 (2)|MeshPart|1|181.04,15.7,12.12|3847.6,143.25,-363.8|Build/CherryBlossomZone
Meshes/untitled_Cylinder.010|Part|1|7.8,7.19,5.19|3847.6,127.28,-323.07|Build/CherryBlossomZone
Meshes/untitled_Cylinder.006|MeshPart|1|9.45,56.28,9.45|3847.6,103.45,-298.22|Build/CherryBlossomZone
Meshes/untitled_Cylinder.003 (1)|MeshPart|1|9.45,56.28,9.45|3847.6,103.45,-429.39|Build/CherryBlossomZone
Meshes/untitled_Cylinder.008|Part|1|7.8,7.19,5.19|3847.6,127.28,-363.8|Build/CherryBlossomZone
Meshes/untitled_Cylinder.005|MeshPart|1|11.59,15.43,11.59|3847.6,75.29,-298.22|Build/CherryBlossomZone
Meshes/untitled_Cylinder.007|Part|1|132.55,4.34,5.85|3847.6,122.16,-363.8|Build/CherryBlossomZone
Meshes/untitled_Cylinder.009|Part|1|7.8,7.19,5.19|3847.6,127.28,-404.54|Build/CherryBlossomZone
Meshes/untitled_Cylinder.004 (1)|MeshPart|1|152.93,10.72,9.58|3847.6,135.1,-363.8|Build/CherryBlossomZone
Meshes/untitled_Cylinder.005|MeshPart|1|11.59,15.43,11.59|3579.6,75.29,-298.22|Build/CherryBlossomZone
Meshes/untitled_Cylinder.006|MeshPart|1|9.45,56.28,9.45|3579.6,103.45,-298.22|Build/CherryBlossomZone
Meshes/untitled_Cylinder.004 (1)|MeshPart|1|152.93,10.72,9.58|3579.6,135.1,-363.8|Build/CherryBlossomZone
Meshes/untitled_Cylinder.008|Part|1|7.8,7.19,5.19|3579.6,127.28,-363.8|Build/CherryBlossomZone
Meshes/untitled_Cylinder.003 (1)|MeshPart|1|9.45,56.28,9.45|3579.6,103.45,-429.39|Build/CherryBlossomZone
Meshes/untitled_Cylinder.010|Part|1|7.8,7.19,5.19|3579.6,127.28,-323.07|Build/CherryBlossomZone
Meshes/untitled_Cylinder.002 (2)|MeshPart|1|181.04,15.7,12.12|3579.6,143.25,-363.8|Build/CherryBlossomZone
Meshes/untitled_Cylinder.007|Part|1|132.55,4.34,5.85|3579.6,122.16,-363.8|Build/CherryBlossomZone
Meshes/untitled_Cylinder.001 (1)|MeshPart|1|11.59,15.43,11.59|3579.6,75.29,-429.39|Build/CherryBlossomZone
Meshes/untitled_Cylinder.009|Part|1|7.8,7.19,5.19|3579.6,127.28,-404.54|Build/CherryBlossomZone
Meshes/untitled_Cylinder.009|Part|1|7.8,7.19,5.19|4145.6,127.28,-404.54|Build/CherryBlossomZone
Meshes/untitled_Cylinder.006|MeshPart|1|9.45,56.28,9.45|4145.6,103.45,-298.22|Build/CherryBlossomZone
Meshes/untitled_Cylinder.008|Part|1|7.8,7.19,5.19|4145.6,127.28,-363.8|Build/CherryBlossomZone
Meshes/untitled_Cylinder.010|Part|1|7.8,7.19,5.19|4145.6,127.28,-323.07|Build/CherryBlossomZone
Meshes/untitled_Cylinder.004 (1)|MeshPart|1|152.93,10.72,9.58|4145.6,135.1,-363.8|Build/CherryBlossomZone
Meshes/untitled_Cylinder.005|MeshPart|1|11.59,15.43,11.59|4145.6,75.29,-298.22|Build/CherryBlossomZone
Meshes/untitled_Cylinder.007|Part|1|132.55,4.34,5.85|4145.6,122.16,-363.8|Build/CherryBlossomZone
Meshes/untitled_Cylinder.001 (1)|MeshPart|1|11.59,15.43,11.59|4145.6,75.29,-429.39|Build/CherryBlossomZone
Meshes/untitled_Cylinder.002 (2)|MeshPart|1|181.04,15.7,12.12|4145.6,143.25,-363.8|Build/CherryBlossomZone
Meshes/untitled_Cylinder.003 (1)|MeshPart|1|9.45,56.28,9.45|4145.6,103.45,-429.39|Build/CherryBlossomZone
Part|Part|1|1.09,29.5,1.09|3779.03,119.72,-270.19|Build/CherryBlossomZone
Part|Part|1|0.85,25.7,0.85|3784.71,127.47,-277.86|Build/CherryBlossomZone
Part|Part|1|0.84,27.49,0.84|3820.3,131.93,-290.31|Build/CherryBlossomZone
Part|Part|1|0.84,22.8,0.84|3808.35,136.42,-299.32|Build/CherryBlossomZone
Part|Part|1|1.09,23.28,1.09|3789.84,122.84,-261.99|Build/CherryBlossomZone
Part|Part|1|0.84,38.65,0.84|3794.13,128.5,-303.09|Build/CherryBlossomZone
Part|Part|1|19.14,7.79,24.99|3805.92,150.11,-285.25|Build/CherryBlossomZone
Part|Part|1|18.79,9.99,20.46|3798.85,146.25,-292.51|Build/CherryBlossomZone
Part|Part|1|19.47,5.91,15.4|3774.18,135.61,-274.58|Build/CherryBlossomZone
Part|Part|1|19.14,9.99,22.27|3806.01,151.26,-304.46|Build/CherryBlossomZone
Part|Part|1|19.14,9.52,22.27|3790.73,151.03,-278.27|Build/CherryBlossomZone
Part|Part|1|19.47,5.91,15.4|3791.73,137.83,-254.86|Build/CherryBlossomZone
Part|Part|1|19.47,5.91,15.4|3790.89,151.18,-307.46|Build/CherryBlossomZone
Part|Part|1|19.14,7.99,21.9|3813.32,153.6,-281.91|Build/CherryBlossomZone
Part|Part|1|24.32,13.09,19.35|3785.04,137.24,-268.01|Build/CherryBlossomZone
Part|Part|1|19.14,9.99,22.27|3814.58,147.32,-291.24|Build/CherryBlossomZone
Part|Part|1|19.14,11.77,22.27|3792.4,152.15,-295.25|Build/CherryBlossomZone
Part|Part|1|18.79,14.47,20.46|3804.87,140.02,-274.93|Build/CherryBlossomZone
Part|Part|1|18.79,14.47,20.46|3798.04,138.36,-264.63|Build/CherryBlossomZone
Part|Part|1|20.95,10.87,24.99|3801.08,158.65,-289.81|Build/CherryBlossomZone
Part|Part|1|15.64,5.65,18.94|3819.65,152.49,-299.99|Build/CherryBlossomZone
Part|Part|1|23.46,8.96,18.92|3788.37,141.95,-275.17|Build/CherryBlossomZone
Part|Part|1|6.45,11.82,5.61|3797.32,111.5,-276.02|Build/CherryBlossomZone
Part|Part|1|5.17,11.82,4.04|3796.01,120.4,-273.86|Build/CherryBlossomZone
Part|Part|1|3.53,11.82,2.92|3793.89,129.76,-271.22|Build/CherryBlossomZone
Part|Part|1|6.45,11.82,6.45|3798.41,111.53,-279.87|Build/CherryBlossomZone
Part|Part|1|4.47,11.82,4.47|3802.37,118.59,-278.59|Build/CherryBlossomZone
Part|Part|1|5.02,11.82,4.69|3799.36,122.47,-281.29|Build/CherryBlossomZone
Part|Part|1|4,11.82,3.53|3799.62,132.01,-284.03|Build/CherryBlossomZone
Part|Part|1|1.82,1.75,13.47|3796.58,121.65,-266.88|Build/CherryBlossomZone
Part|Part|1|3.05,10.91,3.04|3799.33,139.95,-288.41|Build/CherryBlossomZone
Part|Part|1|1.82,1.75,16.46|3791.36,124.72,-284.71|Build/CherryBlossomZone
Part|Part|1|1.82,1.75,8.68|3804.85,117.35,-281.91|Build/CherryBlossomZone
Part|Part|1|3.49,7.99,2.73|3596.86,123.06,-436.8|Build/CherryBlossomZone
Part|Part|1|4.51,6.01,4.51|3599.33,105.58,-441.52|Build/CherryBlossomZone
Part|Part|1|4.36,7.99,4.36|3600.63,117.06,-439.01|Build/CherryBlossomZone
Part|Part|1|2.7,7.99,2.39|3603,130.9,-440.74|Build/CherryBlossomZone
Part|Part|1|3.02,7.99,3.02|3602.22,121.83,-436.69|Build/CherryBlossomZone
Part|Part|1|2.39,7.99,1.97|3594.64,129.38,-436.27|Build/CherryBlossomZone
Part|Part|1|6.01,3.01,6.01|3600.68,104.08,-438.63|Build/CherryBlossomZone
Part|Part|1|5.13,9.4,5.13|3600.5,109.56,-438.69|Build/CherryBlossomZone
Part|Part|1|2.06,7.37,2.05|3604.66,136.26,-443.19|Build/CherryBlossomZone
Part|Part|1|5.56,5.95,6.01|3598.98,105.55,-437.7|Build/CherryBlossomZone
Part|Part|1|1.23,1.18,9.1|3594.28,123.9,-432.84|Build/CherryBlossomZone
Part|Part|1|4.36,7.99,3.79|3598.46,117.04,-437.41|Build/CherryBlossomZone
Part|Part|1|3.39,7.99,3.17|3601.73,124.46,-439.38|Build/CherryBlossomZone
Part|Part|1|1.23,1.18,5.86|3604.92,120.99,-437.44|Build/CherryBlossomZone
Part|Part|1|4.72,5.61,5.04|3598.93,111.15,-437.83|Build/CherryBlossomZone
Part|Part|1|1.23,1.18,11.12|3598.87,125.97,-444.52|Build/CherryBlossomZone
Part|Part|1|10.56,3.82,12.79|3620.3,144.73,-440.95|Build/CherryBlossomZone
Part|Part|1|15.85,6.05,12.78|3593.33,137.61,-440.66|Build/CherryBlossomZone
Part|Part|1|16.43,8.84,13.07|3588.59,134.43,-438.22|Build/CherryBlossomZone
Part|Part|1|12.7,9.78,13.82|3602.03,136.31,-433.7|Build/CherryBlossomZone
Part|Part|1|12.93,5.39,14.79|3609.44,145.48,-433.93|Build/CherryBlossomZone
Part|Part|1|13.15,3.99,10.41|3608.05,143.85,-456.85|Build/CherryBlossomZone
Part|Part|1|13.15,3.99,10.41|3585.51,133.33,-446.22|Build/CherryBlossomZone
Part|Part|1|12.93,6.43,15.05|3595.87,143.74,-441.34|Build/CherryBlossomZone
Part|Part|1|12.7,9.78,13.82|3594.12,135.19,-431.04|Build/CherryBlossomZone
Part|Part|1|14.15,7.34,16.88|3606.18,148.89,-443.21|Build/CherryBlossomZone
Part|Part|1|12.93,6.75,15.05|3614.87,143.9,-448.99|Build/CherryBlossomZone
Part|Part|1|12.7,6.75,13.82|3606.1,140.52,-445.58|Build/CherryBlossomZone
Part|Part|1|12.93,7.95,15.05|3603.8,144.5,-449.71|Build/CherryBlossomZone
Part|Part|1|12.93,6.75,15.05|3613.97,141.24,-438.38|Build/CherryBlossomZone
Part|Part|1|13.15,3.99,10.41|3586.71,134.83,-428.43|Build/CherryBlossomZone
Part|Part|1|12.93,5.26,16.88|3606.86,143.13,-438.77|Build/CherryBlossomZone
Part|Part|1|0.73,15.73,0.73|3588.65,124.7,-433.02|Build/CherryBlossomZone
Part|Part|1|0.56,18.57,0.56|3616.64,130.85,-435.52|Build/CherryBlossomZone
Part|Part|1|0.56,15.4,0.56|3614,133.88,-445.28|Build/CherryBlossomZone
Part|Part|1|0.56,26.11,0.56|3607.97,128.52,-453.18|Build/CherryBlossomZone
Part|Part|1|0.73,19.93,0.73|3586.28,122.6,-441.88|Build/CherryBlossomZone
Part|Part|1|0.57,17.36,0.57|3592.49,127.83,-443.62|Build/CherryBlossomZone
Part|Part|1|16.17,9.94,18.81|3936.89,158,-440.95|Build/CherryBlossomZone
Part|Part|1|16.17,6.58,21.11|3922.84,156.28,-443|Build/CherryBlossomZone
Part|Part|1|16.17,8.44,18.81|3930.44,157.25,-428.66|Build/CherryBlossomZone
Part|Part|1|16.44,4.99,13.01|3942.9,157.19,-432.47|Build/CherryBlossomZone
Part|Part|1|15.88,8.44,17.29|3931,153.02,-440.41|Build/CherryBlossomZone
Part|Part|1|16.44,4.99,13.01|3942.19,144.03,-463.62|Build/CherryBlossomZone
Part|Part|1|15.88,12.22,17.29|3919.49,147.76,-451.1|Build/CherryBlossomZone
Part|Part|1|19.82,7.57,15.98|3931.86,149.39,-457.51|Build/CherryBlossomZone
Part|Part|1|13.21,4.77,16|3918.51,158.29,-426.54|Build/CherryBlossomZone
Part|Part|1|16.17,8.44,18.81|3918.78,153.92,-435.08|Build/CherryBlossomZone
Part|Part|1|15.88,12.22,17.29|3920.46,146.36,-461.49|Build/CherryBlossomZone
Part|Part|1|16.17,8.04,18.81|3931.35,157.05,-454.26|Build/CherryBlossomZone
Part|Part|1|16.17,6.75,18.5|3915.99,159.23,-442.52|Build/CherryBlossomZone
Part|Part|1|16.44,4.99,13.01|3921.25,145.91,-471.29|Build/CherryBlossomZone
Part|Part|1|20.54,11.06,16.35|3931.49,145.41,-464.17|Build/CherryBlossomZone
Part|Part|1|17.7,9.18,21.11|3928.26,163.49,-441.53|Build/CherryBlossomZone
Part|Part|1|5.45,9.99,4.74|3925.55,123.67,-453.3|Build/CherryBlossomZone
Part|Part|1|6.95,7.44,7.52|3925.61,109.29,-452.56|Build/CherryBlossomZone
Part|Part|1|3.38,9.99,2.99|3927.04,140.99,-446.42|Build/CherryBlossomZone
Part|Part|1|2.98,9.99,2.46|3926.18,139.09,-458.25|Build/CherryBlossomZone
Part|Part|1|5.45,9.99,5.45|3926.27,123.69,-450|Build/CherryBlossomZone
Part|Part|1|6.41,11.76,6.41|3925.97,114.31,-450.31|Build/CherryBlossomZone
Part|Part|1|5.9,7.02,6.31|3925.79,116.3,-452.55|Build/CherryBlossomZone
Part|Part|1|5.64,7.52,5.64|3929.8,109.33,-450.22|Build/CherryBlossomZone
Part|Part|1|1.54,1.48,13.91|3933.46,134.83,-449.22|Build/CherryBlossomZone
Part|Part|1|4.37,9.99,3.41|3925.66,131.19,-455.43|Build/CherryBlossomZone
Part|Part|1|1.54,1.48,7.33|3922.3,128.61,-445.91|Build/CherryBlossomZone
Part|Part|1|4.24,9.99,3.96|3926.13,132.93,-448.56|Build/CherryBlossomZone
Part|Part|1|7.52,3.76,7.52|3925.81,107.46,-450.15|Build/CherryBlossomZone
Part|Part|1|3.78,9.99,3.78|3922.82,129.66,-449.37|Build/CherryBlossomZone
Part|Part|1|2.58,9.21,2.57|3929,147.69,-443.27|Build/CherryBlossomZone
Part|Part|1|1.54,1.48,11.38|3922.45,132.24,-460.4|Build/CherryBlossomZone
Part|Part|1|0.71,32.65,0.71|3938.74,138.02,-434.43|Build/CherryBlossomZone
Part|Part|1|0.92,24.92,0.92|3936.84,130.61,-464.95|Build/CherryBlossomZone
Part|Part|1|0.71,21.71,0.71|3935.67,137.15,-456.97|Build/CherryBlossomZone
Part|Part|1|0.71,19.26,0.71|3926.65,144.72,-431.55|Build/CherryBlossomZone
Part|Part|1|0.71,23.22,0.71|3914.15,140.92,-433.48|Build/CherryBlossomZone
Part|Part|1|0.92,19.66,0.92|3925.51,133.24,-466.73|Build/CherryBlossomZone
Part|Part|1|7.15,13.1,6.22|4001.37,129.31,-446.71|Build/CherryBlossomZone
Part|Part|1|3.91,13.1,3.23|3996.12,149.54,-442.81|Build/CherryBlossomZone
Part|Part|1|7.15,13.1,7.15|4003.82,129.34,-450.4|Build/CherryBlossomZone
Part|Part|1|8.41,15.42,8.41|4003.8,117.03,-449.84|Build/CherryBlossomZone
Part|Part|1|9.12,9.76,9.86|4002.01,110.45,-447.45|Build/CherryBlossomZone
Part|Part|1|4.95,13.1,4.96|4007.57,137.16,-447.71|Build/CherryBlossomZone
Part|Part|1|7.74,9.2,8.27|4001.86,119.65,-447.63|Build/CherryBlossomZone
Part|Part|1|3.38,12.09,3.37|4007.69,160.83,-459.1|Build/CherryBlossomZone
Part|Part|1|2.01,1.94,14.93|3997.49,140.55,-437.32|Build/CherryBlossomZone
Part|Part|1|7.4,9.86,7.4|4000.4,110.51,-453.53|Build/CherryBlossomZone
Part|Part|1|9.86,4.93,9.86|4004.1,108.04,-449.84|Build/CherryBlossomZone
Part|Part|1|2.01,1.94,18.24|3998.02,143.95,-457.9|Build/CherryBlossomZone
Part|Part|1|5.73,13.1,4.48|3999.25,139.17,-444.88|Build/CherryBlossomZone
Part|Part|1|5.56,13.1,5.2|4005.31,141.47,-451.58|Build/CherryBlossomZone
Part|Part|1|2.01,1.94,9.61|4011.31,135.79,-450.38|Build/CherryBlossomZone
Part|Part|1|4.43,13.1,3.92|4006.51,152.03,-454.39|Build/CherryBlossomZone
Part|Part|1|1.2,25.79,1.2|3988.72,141.87,-434.44|Build/CherryBlossomZone
Part|Part|1|0.94,28.48,0.94|3988.69,147,-452.93|Build/CherryBlossomZone
Part|Part|1|1.2,32.69,1.2|3980.09,138.42,-446.77|Build/CherryBlossomZone
Part|Part|1|0.93,25.27,0.93|4020.91,156.92,-467.56|Build/CherryBlossomZone
Part|Part|1|0.93,42.83,0.93|4007.18,148.14,-476.35|Build/CherryBlossomZone
Part|Part|1|0.93,30.46,0.93|4030.46,151.95,-454|Build/CherryBlossomZone
Part|Part|1|21.21,8.64,27.7|4013.56,172.09,-453.53|Build/CherryBlossomZone
Part|Part|1|21.21,10.55,24.68|3995.18,173.1,-451.32|Build/CherryBlossomZone
Part|Part|1|17.33,6.26,20.99|4033.05,174.73,-464.43|Build/CherryBlossomZone
Part|Part|1|21.21,8.85,24.27|4020.24,175.96,-447.5|Build/CherryBlossomZone
Part|Part|1|21.21,11.07,24.68|4024.73,169,-456.92|Build/CherryBlossomZone
Part|Part|1|23.22,12.05,27.7|4010.02,181.55,-459.99|Build/CherryBlossomZone
Part|Part|1|20.83,16.03,22.68|3998.26,159.07,-434.45|Build/CherryBlossomZone
Part|Part|1|20.83,16.03,22.68|4008.96,160.91,-443|Build/CherryBlossomZone
Part|Part|1|21.57,6.55,17.07|4005.25,173.28,-482.06|Build/CherryBlossomZone
Part|Part|1|21.21,11.07,24.68|4020.18,173.36,-473.77|Build/CherryBlossomZone
Part|Part|1|21.21,13.04,24.68|4002.7,174.35,-468.67|Build/CherryBlossomZone
Part|Part|1|26,9.93,20.97|3991.64,163.05,-448.84|Build/CherryBlossomZone
Part|Part|1|26.95,14.5,21.44|3985.7,157.83,-442.43|Build/CherryBlossomZone
Part|Part|1|21.57,6.55,17.07|3976.47,156.02,-453.03|Build/CherryBlossomZone
Part|Part|1|20.83,11.07,22.68|4008.57,167.82,-463.59|Build/CherryBlossomZone
Part|Part|1|21.57,6.55,17.07|3988.29,158.49,-426.28|Build/CherryBlossomZone
Part|Part|1|0.72,33.17,0.72|3660.87,138.54,-294.56|Build/CherryBlossomZone
Part|Part|1|0.72,19.57,0.72|3673.08,145.34,-291.32|Build/CherryBlossomZone
Part|Part|1|0.73,22.06,0.73|3652.79,137.66,-272.91|Build/CherryBlossomZone
Part|Part|1|0.93,25.32,0.93|3647.91,131.01,-266.33|Build/CherryBlossomZone
Part|Part|1|0.93,19.98,0.93|3657.19,133.68,-259.28|Build/CherryBlossomZone
Part|Part|1|0.72,23.59,0.72|3683.33,141.49,-283.59|Build/CherryBlossomZone
Part|Part|1|16.42,10.1,19.11|3659.39,158.84,-287.83|Build/CherryBlossomZone
Part|Part|1|16.42,8.17,19.11|3657.95,157.88,-273.26|Build/CherryBlossomZone
Part|Part|1|16.42,8.57,19.11|3678.42,154.7,-284.39|Build/CherryBlossomZone
Part|Part|1|16.42,6.69,21.45|3670.99,157.09,-279.24|Build/CherryBlossomZone
Part|Part|1|16.71,5.07,13.22|3643.75,144.65,-270.09|Build/CherryBlossomZone
Part|Part|1|16.42,6.85,18.79|3677.34,160.09,-276.38|Build/CherryBlossomZone
Part|Part|1|16.42,8.57,19.11|3671.07,158.08,-295.73|Build/CherryBlossomZone
Part|Part|1|16.71,5.07,13.22|3658.09,158.01,-298.31|Build/CherryBlossomZone
Part|Part|1|13.42,4.85,16.25|3682.77,159.14,-291.9|Build/CherryBlossomZone
Part|Part|1|16.13,8.57,17.56|3664.92,153.78,-285.48|Build/CherryBlossomZone
Part|Part|1|17.98,9.33,21.45|3666.84,164.42,-283.16|Build/CherryBlossomZone
Part|Part|1|20.87,11.23,16.61|3653.07,146.05,-264.45|Build/CherryBlossomZone
Part|Part|1|20.14,7.69,16.24|3655.93,150.09,-270.59|Build/CherryBlossomZone
Part|Part|1|16.71,5.07,13.22|3658.81,146.56,-253.16|Build/CherryBlossomZone
Part|Part|1|16.13,12.42,17.56|3670.09,148.43,-270.39|Build/CherryBlossomZone
Part|Part|1|16.13,12.42,17.56|3664.22,147.01,-261.55|Build/CherryBlossomZone
Part|Part|1|1.56,1.5,7.45|3670.07,128.97,-276.38|Build/CherryBlossomZone
Part|Part|1|4.31,10.15,4.03|3665.36,133.37,-275.85|Build/CherryBlossomZone
Part|Part|1|5.54,10.15,4.82|3663.61,123.96,-271.33|Build/CherryBlossomZone
Part|Part|1|4.44,10.15,3.47|3662.48,131.6,-269.47|Build/CherryBlossomZone
Part|Part|1|7.64,3.82,7.64|3664.89,107.49,-274.28|Build/CherryBlossomZone
Part|Part|1|5.99,7.13,6.41|3663.75,116.47,-272.12|Build/CherryBlossomZone
Part|Part|1|1.56,1.5,14.13|3658.49,135.3,-278.78|Build/CherryBlossomZone
Part|Part|1|3.84,10.15,3.84|3667.94,130.04,-273.53|Build/CherryBlossomZone
Part|Part|1|2.62,9.36,2.61|3665.34,148.37,-281.96|Build/CherryBlossomZone
Part|Part|1|3.43,10.15,3.03|3665.58,141.55,-278.2|Build/CherryBlossomZone
Part|Part|1|3.03,10.15,2.5|3660.67,139.63,-267.2|Build/CherryBlossomZone
Part|Part|1|7.06,7.56,7.64|3663.91,109.35,-272.02|Build/CherryBlossomZone
Part|Part|1|5.54,10.15,5.54|3664.55,123.98,-274.63|Build/CherryBlossomZone
Part|Part|1|6.52,11.94,6.52|3664.67,114.45,-274.21|Build/CherryBlossomZone
Part|Part|1|1.56,1.5,11.56|3662.98,132.66,-263.48|Build/CherryBlossomZone
Part|Part|1|5.73,7.64,5.73|3661.28,109.39,-276.13|Build/CherryBlossomZone
Part|Part|1|0.79,36.6,0.79|3960.09,140.94,-301.61|Build/CherryBlossomZone
Part|Part|1|1.03,22.04,1.03|3938.34,135.58,-269.09|Build/CherryBlossomZone
Part|Part|1|0.79,26.03,0.79|3976.36,144.2,-279.35|Build/CherryBlossomZone
Part|Part|1|0.79,21.59,0.79|3970.33,148.45,-292.18|Build/CherryBlossomZone
Part|Part|1|0.8,24.33,0.8|3941.05,139.97,-284.65|Build/CherryBlossomZone
Part|Part|1|1.03,27.94,1.03|3932.9,132.64,-280.74|Build/CherryBlossomZone
Part|Part|1|6.11,11.2,5.32|3950.8,124.85,-277.54|Build/CherryBlossomZone
Part|Part|1|8.43,4.21,8.43|3953.57,106.68,-279.76|Build/CherryBlossomZone
Part|Part|1|4.75,11.2,4.44|3954.84,135.24,-281.05|Build/CherryBlossomZone
Part|Part|1|6.11,11.2,6.11|3953.41,124.88,-280.28|Build/CherryBlossomZone
Part|Part|1|6.61,7.86,7.07|3951.35,116.6,-278.24|Build/CherryBlossomZone
Part|Part|1|3.34,11.2,2.76|3945.8,142.14,-275.03|Build/CherryBlossomZone
Part|Part|1|7.79,8.34,8.43|3951.45,108.74,-278.06|Build/CherryBlossomZone
Part|Part|1|6.32,8.43,6.32|3951,108.79,-283.42|Build/CherryBlossomZone
Part|Part|1|7.19,13.18,7.19|3953.31,114.37,-279.8|Build/CherryBlossomZone
Part|Part|1|1.72,1.66,12.76|3946.14,134.46,-270.21|Build/CherryBlossomZone
Part|Part|1|1.72,1.66,15.59|3949.64,137.37,-287.45|Build/CherryBlossomZone
Part|Part|1|1.72,1.66,8.22|3959.71,130.39,-279.14|Build/CherryBlossomZone
Part|Part|1|4.23,11.2,4.23|3956.16,131.57,-277.46|Build/CherryBlossomZone
Part|Part|1|4.9,11.2,3.82|3948.75,133.28,-276.31|Build/CherryBlossomZone
Part|Part|1|2.89,10.33,2.88|3957.96,151.79,-287.02|Build/CherryBlossomZone
Part|Part|1|3.79,11.2,3.35|3956.26,144.27,-283.23|Build/CherryBlossomZone
Part|Part|1|22.22,8.49,17.91|3942.93,153.69,-280.77|Build/CherryBlossomZone
Part|Part|1|18.12,9.46,21.09|3970.64,162.5,-297.51|Build/CherryBlossomZone
Part|Part|1|17.79,13.7,19.38|3946.37,150.29,-267.68|Build/CherryBlossomZone
Part|Part|1|18.43,5.6,14.58|3930.78,147.68,-286.55|Build/CherryBlossomZone
Part|Part|1|18.12,9.46,21.09|3971.98,158.77,-282.65|Build/CherryBlossomZone
Part|Part|1|18.43,5.6,14.58|3936.77,149.79,-262.28|Build/CherryBlossomZone
Part|Part|1|18.12,7.56,20.74|3966.8,164.72,-275.4|Build/CherryBlossomZone
Part|Part|1|17.79,13.7,19.38|3956.64,151.86,-273.29|Build/CherryBlossomZone
Part|Part|1|17.79,9.46,19.38|3959.37,157.76,-290.67|Build/CherryBlossomZone
Part|Part|1|18.12,7.38,23.67|3962.07,161.41,-281.46|Build/CherryBlossomZone
Part|Part|1|23.03,12.39,18.32|3936.98,149.22,-276.25|Build/CherryBlossomZone
Part|Part|1|14.81,5.35,17.93|3980.09,163.67,-287.74|Build/CherryBlossomZone
Part|Part|1|19.84,10.29,23.67|3960.04,169.5,-287.42|Build/CherryBlossomZone
Part|Part|1|18.43,5.6,14.58|3959.31,162.43,-306.71|Build/CherryBlossomZone
Part|Part|1|18.12,11.15,21.09|3955.18,163.34,-295.82|Build/CherryBlossomZone
Part|Part|1|18.12,9.02,21.09|3946.27,162.28,-282.33|Build/CherryBlossomZone
Part|Part|1|37.18,10.09,15.32|4095.83,131.62,-257.69|Build/CherryBlossomZone
Part|Part|1|46.18,10.09,27.32|4081.56,124.62,-245.18|Build/CherryBlossomZone
Part|Part|1|45.18,16.09,27.32|3587.2,171.62,-275.33|Build/CherryBlossomZone
Part|Part|1|49.18,10.09,21.32|3735.35,131.62,-459.88|Build/CherryBlossomZone
Part|Part|1|45.18,12.09,27.32|4117.74,126.62,-478.35|Build/CherryBlossomZone
Part|Part|1|49.18,10.09,24.32|3718.28,142.62,-477.6|Build/CherryBlossomZone
Part|Part|1|44.18,10.09,21.32|3697.31,136.62,-463.65|Build/CherryBlossomZone
Part|Part|1|30.18,12.09,27.32|3613.3,169.62,-282.75|Build/CherryBlossomZone
Part|Part|1|45.18,16.09,27.32|4151.26,140.62,-486.8|Build/CherryBlossomZone
Part|Part|1|11,2,6|3892.68,68.58,-423.23|Build/CherryBlossomZone
Part|Part|1|13,3,14|3682.39,69.08,-425.7|Build/CherryBlossomZone
Part|Part|1|13,6,9|3676.17,70.58,-431.19|Build/CherryBlossomZone
Part|Part|1|8,1,7|3919.05,68.08,-330.74|Build/CherryBlossomZone
Part|Part|1|11,2,7|4127.33,68.58,-325.4|Build/CherryBlossomZone
Part|Part|1|6,2,6|3914.99,68.58,-326.07|Build/CherryBlossomZone
Part|Part|1|6,2,9|3712.6,68.58,-326.52|Build/CherryBlossomZone
Part|Part|1|8,1,6|3888.18,68.08,-421.23|Build/CherryBlossomZone
Part|Part|1|8,3,7|4133.17,69.08,-323.52|Build/CherryBlossomZone
Part|Part|1|6,3,8|3710.56,69.08,-320.02|Build/CherryBlossomZone
Part|Part|1|1,3.5,1|3798.5,69.33,-428.5|Build/CherryBlossomZone
Part|Part|1|18,1,0.5|3808,70.08,-428.5|Build/CherryBlossomZone
Part|Part|1|18,1,0.5|3808,68.58,-428.5|Build/CherryBlossomZone
Part|Part|1|1,3.5,1|3817.5,69.33,-428.5|Build/CherryBlossomZone
Part|Part|1|1,3.5,1|3598.5,69.33,-300.5|Build/CherryBlossomZone
Part|Part|1|1,3.5,1|3587.5,69.33,-300.5|Build/CherryBlossomZone
Part|Part|1|10,1,0.5|3593,70.08,-300.5|Build/CherryBlossomZone
Part|Part|1|10,1,0.5|3593,68.58,-300.5|Build/CherryBlossomZone
Part|Part|1|10,1,0.5|4175,70.08,-428.5|Build/CherryBlossomZone
Part|Part|1|1,3.5,1|4169.5,69.33,-428.5|Build/CherryBlossomZone
Part|Part|1|10,1,0.5|4175,68.58,-428.5|Build/CherryBlossomZone
Part|Part|1|1,3.5,1|4180.5,69.33,-428.5|Build/CherryBlossomZone
Part|Part|1|1,3.5,1|4043.5,69.33,-299.5|Build/CherryBlossomZone
Part|Part|1|1,3.5,1|4024.5,69.33,-299.5|Build/CherryBlossomZone
Part|Part|1|18,1,0.5|4034,70.08,-299.5|Build/CherryBlossomZone
Part|Part|1|18,1,0.5|4034,68.58,-299.5|Build/CherryBlossomZone
Meshes/untitled_Plane.001|MeshPart|1|150.99,10.8,20.38|3989.44,108.82,-293.06|Build/CherryBlossomZone
untitled|MeshPart|1|150.21,9.03,18.32|3989.44,107.54,-292.07|Build/CherryBlossomZone
Meshes/untitled_Plane.001|MeshPart|1|150.99,10.8,20.38|3989.44,108.82,-435.06|Build/CherryBlossomZone
untitled|MeshPart|1|150.21,9.03,18.32|3989.44,107.54,-436.06|Build/CherryBlossomZone
Meshes/untitled_Plane.001|MeshPart|1|150.99,10.8,20.38|3707.44,108.82,-293.06|Build/CherryBlossomZone
untitled|MeshPart|1|150.21,9.03,18.32|3707.44,107.54,-292.07|Build/CherryBlossomZone
Meshes/untitled_Plane.001|MeshPart|1|150.99,10.8,20.38|3707.44,108.82,-435.06|Build/CherryBlossomZone
untitled|MeshPart|1|150.21,9.03,18.32|3707.44,107.54,-436.06|Build/CherryBlossomZone
Part3|Part|1|7.31,2.32,9.46|617.65,68.73,-392.97|Build/Props
Part3|Part|1|7.18,6.46,6.38|616.41,70.8,-394.99|Build/Props
Part3|Part|1|9.49,3.87,7.46|615.8,69.51,-399.15|Build/Props
Part3|Part|1|9.72,2.18,6.97|631.83,68.67,-341.35|Build/Props
Part3|Part|1|7.71,5.52,5.9|628.75,70.34,-341.84|Build/Props
Part3|Part|1|10.94,3.64,8.97|627.16,69.4,-339.14|Build/Props
Water|Part|1|2,0.1,4|699.6,67.63,-423.5|Build/Props
Water|Part|1|1,0.1,2|698.6,67.63,-422|Build/Props
Bamboo|Part|1|0.5,8.36,0.5|698.39,71.86,-421.18|Build/Props
Bamboo|Part|1|0.5,12.17,0.5|700.84,73.76,-423.25|Build/Props
Water|Part|1|1,0.1,4|697.6,67.63,-421|Build/Props
Bamboo|Part|1|0.5,6.53,0.5|696.5,70.94,-422.63|Build/Props
Water|Part|1|2,0.1,3|696.1,67.63,-422.5|Build/Props
Bamboo|Part|1|0.5,4.66,0.5|698.8,70.01,-423.71|Build/Props
Petal|Part|1|1.1,0.1,0.5|749.55,67.63,-314.25|Build/Props
Petal|Part|1|1.1,0.1,0.5|749.55,67.63,-314.25|Build/Props
Middle|Part|1|0.5,0.07,0.5|749.55,67.71,-314.25|Build/Props
Petal|Part|1|1.1,0.1,0.5|779.95,67.63,-361.65|Build/Props
Petal|Part|1|1.1,0.1,0.5|779.95,67.63,-361.65|Build/Props
Middle|Part|1|0.5,0.07,0.5|779.95,67.71,-361.65|Build/Props
Petal|Part|1|1.1,0.1,0.5|787.25,67.63,-379.85|Build/Props
Petal|Part|1|1.1,0.1,0.5|787.25,67.63,-379.85|Build/Props
Middle|Part|1|0.5,0.07,0.5|787.25,67.71,-379.85|Build/Props
Bamboo|Part|1|0.5,4.66,0.5|766.95,70.01,-425.14|Build/Props
Water|Part|1|2,0.1,2|766.65,67.63,-425.26|Build/Props
Bamboo|Part|1|0.5,8.56,0.5|765.03,71.95,-424|Build/Props
Water|Part|1|2,0.1,2|764.65,67.63,-424.26|Build/Props
Petal|Part|1|1.1,0.1,0.5|659.16,67.63,-325.35|Build/Props
Middle|Part|1|0.5,0.07,0.5|659.16,67.71,-325.35|Build/Props
Petal|Part|1|1.1,0.1,0.5|659.16,67.63,-325.35|Build/Props
Petal|Part|1|1.1,0.1,0.5|671.15,67.63,-418.35|Build/Props
Middle|Part|1|0.5,0.07,0.5|671.15,67.71,-418.35|Build/Props
Petal|Part|1|1.1,0.1,0.5|671.15,67.63,-418.35|Build/Props
Petal|Part|1|1.1,0.1,0.5|677.65,67.63,-342.15|Build/Props
Middle|Part|1|0.5,0.07,0.5|677.65,67.71,-342.15|Build/Props
Petal|Part|1|1.1,0.1,0.5|677.65,67.63,-342.15|Build/Props
Petal|Part|1|1.1,0.1,0.5|664.75,67.63,-402.65|Build/Props
Petal|Part|1|1.1,0.1,0.5|664.75,67.63,-402.65|Build/Props
Middle|Part|1|0.5,0.07,0.5|664.75,67.71,-402.65|Build/Props
Petal|Part|1|1.1,0.1,0.5|748.05,67.63,-424.95|Build/Props
Middle|Part|1|0.5,0.07,0.5|748.05,67.71,-424.95|Build/Props
Petal|Part|1|1.1,0.1,0.5|748.05,67.63,-424.95|Build/Props
Water|Part|1|3,0.1,2|671.94,67.63,-301.98|Build/Props
Bamboo|Part|1|0.5,8.56,0.5|672.02,71.95,-301.31|Build/Props
Water|Part|1|4,0.1,3|674.44,67.63,-303.48|Build/Props
Bamboo|Part|1|0.5,2.66,0.5|673.85,69.01,-303.95|Build/Props
Bamboo|Part|1|0.5,4.66,0.5|674.73,70.01,-302.33|Build/Props
Part|Part|1|1.83,2.92,1.83|985.21,69.14,-301.21|Build/Props
Part|Part|1|1.43,2.11,1.43|985.21,70.56,-301.21|Build/Props
Part|Part|1|3.2,1.93,3.2|992.89,68.91,-304.4|Build/Props
Part|Part|1|1.64,0.93,1.64|992.89,70.08,-304.4|Build/Props
Part|Part|1|2.67,2.68,2.67|992.89,68.91,-304.4|Build/Props
Part|Part|1|2.34,4.68,2.34|900.68,69.91,-426.11|Build/Props
Part|Part|1|1.94,5.83,1.94|900.57,74.93,-426.14|Build/Props
Part|Part|1|1.25,1.31,1.25|899.81,72.12,-424.97|Build/Props
Part|Part|1|1.14,2.87,1.14|899.52,75.04,-428.21|Build/Props
Part|Part|1|1.4,2.75,1.4|903.46,75.83,-425.39|Build/Props
Part|Part|1|1.37,4.11,1.37|900.45,80.44,-426.07|Build/Props
Part|Part|1|1.57,4.71,1.57|900.47,79.37,-426.1|Build/Props
Part|Part|1|1.25,4.13,1.25|899.03,73.34,-423.71|Build/Props
Part|Part|1|1.14,1.2,1.14|900.03,74.2,-427.14|Build/Props
Part|Part|1|1.04,2.04,1.04|903.51,77.7,-425.36|Build/Props
Part|Part|1|0.86,2.41,0.78|899.4,77.61,-428.19|Build/Props
Part|Part|1|0.9,2.98,0.9|898.9,76.66,-423.54|Build/Props
Part|Part|1|1.4,1.91,1.4|901.8,75.22,-425.67|Build/Props
Part|Part|1|1.02,1.9,0.86|896.36,69.57,-429.5|Build/Props
Part|Part|1|1.51,3.01,1.51|895.24,72.08,-429.65|Build/Props
Part|Part|1|1.43,0.94,1.06|894.41,69.96,-430.71|Build/Props
Part|Part|1|0.63,1.79,0.88|894.27,71.1,-430.88|Build/Props
Part|Part|1|1.02,0.94,1.06|895.29,71.27,-428.66|Build/Props
Part|Part|1|1.77,3.54,1.77|895.24,69.34,-429.65|Build/Props
Part|Part|1|0.72,2.04,0.66|811.84,76.05,-301.73|Build/Props
Part|Part|1|0.96,1.01,0.96|812.37,73.17,-300.84|Build/Props
Part|Part|1|1.16,3.47,1.16|812.73,78.45,-299.94|Build/Props
Part|Part|1|0.76,2.52,0.76|811.42,75.26,-297.8|Build/Props
Part|Part|1|1.18,1.62,1.18|813.87,74.04,-299.6|Build/Props
Part|Part|1|1.05,1.11,1.05|812.18,71.41,-299.01|Build/Props
Part|Part|1|1.64,4.93,1.64|812.82,73.79,-299.99|Build/Props
Part|Part|1|0.96,2.43,0.96|811.94,73.88,-301.75|Build/Props
Part|Part|1|1.18,2.32,1.18|815.27,74.55,-299.36|Build/Props
Part|Part|1|0.88,1.73,0.88|815.31,76.14,-299.33|Build/Props
Part|Part|1|1.05,3.49,1.05|811.52,72.45,-297.94|Build/Props
Part|Part|1|1.98,3.95,1.98|812.92,69.55,-299.97|Build/Props
Part|Part|1|1.33,3.98,1.33|812.74,77.54,-299.96|Build/Props
Godly|Part|1|43.72,0.14,43.72|883.44,67.79,-362.08|Build/Props
Godly|Part|1|56.1,0.14,56.58|883.67,67.65,-362.04|Build/Props
Part|Part|1|2.59,1.56,2.59|806.61,68.66,-299.61|Build/Props
Part|Part|1|1.32,0.75,1.32|806.61,69.6,-299.61|Build/Props
Part|Part|1|2.15,2.16,2.15|806.61,68.66,-299.61|Build/Props
untitled|MeshPart|1|28.95,14.48,28.95|962.95,74.81,-412.23|Build/Props
untitled|MeshPart|1|27.88,13.94,27.88|962.95,75.15,-412.23|Build/Props
Part|Part|1|0.52,1.37,0.52|1130.11,68.26,-305.16|Build/Props
Part|Part|1|0.52,1.34,0.52|1129.12,68.24,-303.82|Build/Props
Part|Part|1|0.52,2.89,0.52|1130.57,69.02,-304.03|Build/Props
Part|Part|1|0.52,2.41,0.52|1214.31,68.78,-415.98|Build/Props
Part|Part|1|0.52,3.36,0.52|1213.26,69.25,-417.74|Build/Props
Part|Part|1|0.52,1.34,0.52|1215.3,68.24,-417.32|Build/Props
Part|Part|1|0.52,1.34,0.52|1182.3,68.24,-428.6|Build/Props
Part|Part|1|0.52,3.36,0.52|1180.26,69.25,-429.02|Build/Props
Part|Part|1|0.52,2.41,0.52|1181.31,68.78,-427.26|Build/Props
Part|Part|1|0.63,9.66,0.63|1046.48,72.41,-305.31|Build/Props
Part|Part|1|0.63,11.51,0.63|1045.92,73.33,-306.69|Build/Props
Part|Part|1|0.63,9.62,0.63|1047.69,72.39,-306.94|Build/Props
Meshes/untitled_Cylinder (1)|MeshPart|1|6.34,0.24,6.34|1088.59,67.72,-302.59|Build/Props
Meshes/untitled_Cylinder (1)|MeshPart|1|14.67,0.56,14.67|1077.82,67.49,-312.79|Build/Props
Part|Part|1|0.45,1.18,0.45|1067.04,68.17,-427.12|Build/Props
Part|Part|1|0.45,2.96,0.45|1068.84,69.06,-426.75|Build/Props
Part|Part|1|0.45,2.12,0.45|1067.91,68.64,-428.3|Build/Props
Part|Part|1|0.63,1.62,0.63|1021.31,68.39,-303.69|Build/Props
Part|Part|1|0.63,1.51,0.63|1021.57,68.33,-301.92|Build/Props
Part|Part|1|0.63,2.49,0.63|1022.94,68.82,-302.48|Build/Props
Petal|Part|1|2.2,0.2,1|1169.59,68.03,-425.08|Build/Props
Middle|Part|1|1,0.14,1|1169.59,68.2,-425.08|Build/Props
Petal|Part|1|2.2,0.2,1|1169.59,68.03,-425.08|Build/Props
Middle|Part|1|1.89,0.26,1.89|1075.85,68.28,-309.85|Build/Props
Petal|Part|1|4.17,0.38,1.89|1075.84,67.96,-309.84|Build/Props
Petal|Part|1|4.17,0.38,1.89|1075.84,67.96,-309.84|Build/Props
Meshes/untitled_Cylinder (1)|MeshPart|1|8.59,0.33,8.59|1168.23,67.77,-423.62|Build/Props
Meshes/untitled_Cylinder (1)|MeshPart|1|9.75,0.37,9.75|1065.79,67.66,-303.21|Build/Props
Part|Part|1|0.45,9.96,0.45|1137.78,72.56,-422.77|Build/Props
Part|Part|1|0.45,8.18,0.45|1137.41,71.67,-420.97|Build/Props
Part|Part|1|0.45,3.63,0.45|1135.15,69.42,-423.66|Build/Props
Part|Part|1|0.45,7.36,0.45|1136.75,71.28,-423.95|Build/Props
Part|Part|1|0.45,9.12,0.45|1136.23,72.14,-421.84|Build/Props
Meshes/untitled_Cylinder (1)|MeshPart|1|6.29,0.24,6.29|1159.78,67.72,-427.62|Build/Props
Part|Part|1|0.75,2.98,0.75|1025.87,69.07,-428.44|Build/Props
Part|Part|1|0.75,1.49,0.75|1024.87,68.32,-428.45|Build/Props
Part|Part|1|0.75,2.24,0.75|1025.87,68.69,-427.46|Build/Props
Part|Part|1|0.8,8.27,0.8|1210.81,86.8,-425.35|Build/Props
Part|Part|1|0.83,6.98,0.83|1199.87,85.15,-428.32|Build/Props
Part|Part|1|0.49,7.9,0.49|1192.07,82.95,-416.7|Build/Props
Part|Part|1|0.49,10.46,0.49|1189.77,82.39,-429.6|Build/Props
Part|Part|1|0.7,7.88,0.7|1199.87,78.09,-428.32|Build/Props
Part|Part|1|0.49,10.4,0.49|1204.01,85.7,-410.04|Build/Props
Part|Part|1|0.49,4.57,0.49|1188.18,84.62,-419.7|Build/Props
Part|Part|1|0.49,6.63,0.49|1206.17,85.33,-428.65|Build/Props
Part|Part|1|0.72,7.53,0.72|1209.94,84.82,-413.77|Build/Props
Part|Part|1|0.49,7.61,0.49|1196.17,84.84,-427.64|Build/Props
Part|Part|1|0.63,8.52,0.63|1210.81,78.68,-425.35|Build/Props
Part|Part|1|0.49,6.89,0.49|1209.9,85.46,-422.13|Build/Props
Part|Part|1|0.49,5.21,0.49|1200.53,88.3,-410.04|Build/Props
Part|Part|1|0.49,8.89,0.49|1211.97,86.46,-418.75|Build/Props
Part|Part|1|0.57,5.97,0.57|1209.94,79.67,-413.77|Build/Props
Part|Part|1|2.74,8,2.66|1197.33,82.87,-422.16|Build/Props
Part|Part|1|5.77,3.21,6.42|1197.82,69.18,-420.21|Build/Props
Part|Part|1|3.24,7.64,3.14|1198.16,76.87,-421.88|Build/Props
Part|Part|1|3.7,7.47,4|1200.06,79.13,-420.07|Build/Props
Part|Part|1|3.7,8.96,4|1200.72,72.05,-420.23|Build/Props
Part|Part|1|5.1,6.35,5.52|1198.27,70.75,-421.55|Build/Props
Part|Part|1|2.4,8.39,2.33|1195.35,90.27,-422.93|Build/Props
Part|Part|1|3.7,12.18,4|1199.29,73.67,-421.13|Build/Props
Part|Part|1|2.72,10.17,2.64|1200.97,85.88,-418.86|Build/Props
Part|Part|1|10.93,5.88,8.7|1190.18,89.25,-422.7|Build/Props
Part|Part|1|9.42,4.89,11.23|1202.31,94.62,-418.31|Build/Props
Part|Part|1|8.6,5.29,10.01|1203.4,91.67,-422.77|Build/Props
Part|Part|1|8.45,6.5,9.2|1190.65,89.84,-416.69|Build/Props
Part|Part|1|10.55,4.03,8.5|1193.65,91.46,-422.37|Build/Props
Part|Part|1|10.67,4.62,9.2|1195.45,89.87,-413.36|Build/Props
Part|Part|1|8.6,3.5,11.23|1201.18,90.78,-415.54|Build/Props
Part|Part|1|8.75,2.66,6.92|1208.37,91.33,-425.21|Build/Props
Part|Part|1|7.14,3.58,7.34|1202.88,89.51,-428.8|Build/Props
Part|Part|1|10.79,5.68,10.01|1195.93,94.99,-420.97|Build/Props
Part|Part|1|8.6,4.49,10.01|1205.03,89.66,-412.74|Build/Props
Part|Part|1|8.45,4.49,9.2|1203.26,89.05,-419.6|Build/Props
Part|Part|1|8.6,3.59,9.84|1200.82,92.39,-411.92|Build/Props
Part|Part|1|8.75,2.66,6.92|1185.58,89.46,-417.92|Build/Props
Part|Part|1|10.55,4.03,8.5|1198.65,90.55,-425.63|Build/Props
Part|Part|1|8.75,2.66,6.92|1191.37,88.49,-428.28|Build/Props
Part|Part|1|7.03,2.54,8.51|1209.44,92.1,-411.91|Build/Props
Part|Part|1|8.6,4.49,10.01|1209.33,91.47,-418.35|Build/Props
Part|Part|1|0.52,1.34,0.52|1228.4,68.24,-300.74|Build/Props
Part|Part|1|0.52,2.41,0.52|1229.74,68.78,-299.75|Build/Props
Part|Part|1|0.52,3.36,0.52|1227.98,69.25,-298.7|Build/Props
Part|Part|1|2.48,4.41,2.48|1278.8,81.14,-414.19|Build/Props
Part|Part|1|2.88,5.12,2.88|1277.41,73.85,-420.95|Build/Props
Part|Part|1|2.94,5.22,2.94|1282.56,80.04,-426.04|Build/Props
Part|Part|1|5.32,5.32,5.32|1280.01,70.1,-421.96|Build/Props
Part|Part|1|4.49,4.49,4.49|1277.86,73.13,-418.9|Build/Props
Part|Part|1|2.12,3.77,2.12|1275.69,77.35,-422.03|Build/Props
Part|Part|1|3.99,7.1,3.99|1281.15,75.17,-423.62|Build/Props
Part|Part|1|3.38,6,3.38|1278.27,77.25,-416.87|Build/Props
Part|Part|1|5.71,5.71,5.71|1277.79,69.17,-419.24|Build/Props
Part|Part|1|7.05,7.05,7.05|1487.45,77.15,-420.41|Build/Props
Part|Part|1|3.9,6.93,3.9|1493.84,89.71,-424.39|Build/Props
Part|Part|1|5.3,9.42,5.3|1490.21,83.62,-422.13|Build/Props
Part|Part|1|8.96,8.96,8.96|1486.98,70.93,-420.11|Build/Props
Part|Part|1|4.61,8.2,4.61|1474.36,87.99,-423.34|Build/Props
Part|Part|1|3.33,5.91,3.33|1484.06,83.78,-415.48|Build/Props
Part|Part|1|6.27,11.14,6.27|1478.69,80.35,-422.61|Build/Props
Part|Part|1|4.52,8.04,4.52|1484.68,78.28,-418.61|Build/Props
Part|Part|1|3.58,5.64,3.58|1470.96,92.5,-423.78|Build/Props
Part|Part|1|8.35,8.35,8.35|1481.75,72.39,-421.86|Build/Props
Part|Part|1|3.24,3.24,3.24|1385.41,68.03,-303.37|Build/Props
Part|Part|1|2.58,4.6,2.58|1391.31,77.95,-303.5|Build/Props
Part|Part|1|5.32,5.32,5.32|1388.91,69.1,-303.17|Build/Props
Part|Part|1|1.79,3.18,1.79|1384.04,74.22,-301.14|Build/Props
Part|Part|1|2.88,5.12,2.88|1385.87,68.76,-304.91|Build/Props
Part|Part|1|3.51,6.25,3.51|1388.91,73.66,-302.94|Build/Props
Part|Part|1|2.43,4.32,2.43|1384.87,71.18,-302.45|Build/Props
Part|Part|1|2.12,3.77,2.12|1385.46,72.26,-306.9|Build/Props
Part|Part|1|9.31,0.59,8.51|1781.66,84.1,-300.59|Build/Props
Part|Part|1|4.65,0.42,2.44|1757.61,67.82,-311.36|Build/Props
Part|Part|1|10.59,8.54,7.37|1769.35,72.25,-295.75|Build/Props
Part|Part|1|1.51,0.45,7.74|1770.67,75.37,-306.23|Build/Props
Part|Part|1|1.72,2.25,3.23|1779.1,76.27,-307.85|Build/Props
Part|Part|1|1.72,0.45,3.23|1779.1,75.37,-310.12|Build/Props
Part|Part|1|2.54,6.66,1.83|1791.36,78.06,-306.15|Build/Props
Part|Part|1|23.82,2.22,23.2|1771.35,68.72,-303.69|Build/Props
Part|Part|1|18.38,6.92,17.74|1788.53,71.07,-305.48|Build/Props
Part|Part|1|9.88,9.44,9.7|1787.22,76.27,-305.92|Build/Props
Part|Part|1|1.72,7.8,3.23|1786.62,80.15,-302.86|Build/Props
Part|Part|1|12.87,9.1,12.09|1781.68,79.26,-300.8|Build/Props
Part|Part|1|2.54,4.4,4|1796.1,72.58,-306.15|Build/Props
Part|Part|1|1.67,3.55,2.9|1769.55,73.82,-303.81|Build/Props
Part|Part|1|8.54,0.45,2.07|1774.18,75.37,-310.7|Build/Props
Part|Part|1|3.15,4.4,2.9|1767.35,70.97,-303.81|Build/Props
Part|Part|1|15.45,5.37,18.24|1773.79,70.3,-305.73|Build/Props
Part|Part|1|23.83,3.1,25.83|1788.35,69.16,-305|Build/Props
Part|Part|1|25.58,5.73,15.84|1781.68,72.55,-304.83|Build/Props
Part|Part|1|10.59,7.91,7.37|1793.39,71.94,-295.75|Build/Props
Part|Part|1|2.54,3.37,4|1798.76,69.3,-306.15|Build/Props
Part|Part|1|7.64,0.5,1.83|1790.02,81.14,-307|Build/Props
Part|Part|1|5.47,0.45,2.16|1773.47,75.37,-311.75|Build/Props
Part|Part|1|2.53,0.5,5.96|1786.73,81.14,-309.55|Build/Props
Part|Part|1|1.72,5.14,2.94|1789.47,78.82,-302.86|Build/Props
Part|Part|1|2.06,1.45,4.91|1762.14,69.49,-306.81|Build/Props
Part|Part|1|4.78,1.45,2.9|1763.5,69.49,-303.81|Build/Props
Part|Part|1|12.35,7.91,5.88|1790.17,74.95,-295.01|Build/Props
Part|Part|1|3.65,2.6,2.44|1760.83,68.91,-311.36|Build/Props
Part|Part|1|19.16,9.61,15.21|1781.68,72.41,-301.74|Build/Props
Part|Part|1|1.72,7.8,3.23|1779.1,80.15,-305.5|Build/Props
Part|Part|1|2.54,0.12,4|1801.76,67.67,-306.15|Build/Props
Part|Part|1|2.54,2.02,2.9|1793.28,74.73,-306.15|Build/Props
Part|Part|1|3.93,1.45,4.91|1763.07,69.49,-310.81|Build/Props
Part|Part|1|9.88,13.01,9.7|1776.22,74.48,-296.92|Build/Props
Part|Part|1|3.57,7.55,3.51|1735.88,67.92,-423.33|Build/Props
Part|Part|1|1.69,7.77,1.61|1730.69,70.68,-426.62|Build/Props
Part|Part|1|2.63,10.87,2.51|1724.01,67.84,-426.67|Build/Props
Part|Part|1|1.69,7.78,1.61|1727.5,67.79,-422.89|Build/Props
Part|Part|1|3.59,12.18,3.28|1718.22,67.78,-427.85|Build/Props
Part|Part|1|3.59,12.18,3.28|1732.71,67.78,-424.92|Build/Props
Part|Part|1|4.7,4.61,7.85|1911.89,69.89,-312.72|Build/Props
Part|Part|1|2.42,11.15,2.31|1916.9,81.23,-316.3|Build/Props
Part|Part|1|5.47,6.44,6.17|1914.71,70.8,-313.98|Build/Props
Part|Part|1|3.77,15.59,3.6|1913.33,90.63,-313.63|Build/Props
Part|Part|1|5.12,10.83,5.04|1913.73,73,-312.38|Build/Props
Part|Part|1|2.42,9.62,2.31|1909.41,88.41,-316.58|Build/Props
Part|Part|1|5.14,17.46,4.7|1913.24,77.91,-313.63|Build/Props
Part|Part|1|2.42,11.16,2.31|1914.2,84.65,-309.4|Build/Props
Part|Part|1|3.57,7.55,3.51|1621.95,71.36,-420.53|Build/Props
Part|Part|1|3.59,12.18,3.28|1621.61,74.78,-421.4|Build/Props
Part|Part|1|2.63,10.87,2.51|1621.67,83.66,-421.4|Build/Props
Part|Part|1|3.28,3.22,5.47|1620.66,69.19,-420.76|Build/Props
Part|Part|1|1.69,6.71,1.61|1618.94,82.1,-423.46|Build/Props
Part|Part|1|3.82,4.49,4.3|1622.63,69.83,-421.64|Build/Props
Part|Part|1|1.69,7.78,1.61|1622.27,79.48,-418.45|Build/Props
Part|Part|1|1.69,7.77,1.61|1624.16,77.1,-423.26|Build/Props
Part|Part|1|4.81,5.65,5.42|1707.98,70.41,-306.12|Build/Props
Part|Part|1|3.31,13.69,3.16|1709.2,87.83,-306.42|Build/Props
Part|Part|1|2.12,9.8,2.03|1708.43,82.57,-310.14|Build/Props
Part|Part|1|4.52,15.34,4.13|1709.28,76.65,-306.42|Build/Props
Part|Part|1|2.12,9.79,2.03|1706.06,79.57,-304.08|Build/Props
Part|Part|1|2.12,8.45,2.03|1712.64,85.87,-303.83|Build/Props
Part|Part|1|4.12,4.05,6.89|1710.46,69.61,-307.22|Build/Props
Part|Part|1|4.49,9.51,4.42|1708.84,72.34,-307.52|Build/Props
Part|Part|1|26.15,0.17,17.63|1868,67.66,-293.14|Build/Props
Part|Part|1|15.8,0.17,7.4|1657.87,67.66,-422.13|Build/Props
Part|Part|1|12.8,0.17,7.4|1761.37,67.66,-432.13|Build/Props
Part|Part|1|7.15,0.17,4.63|1845.5,67.66,-298.64|Build/Props
Part|Part|1|17.8,0.17,12.4|1774.87,67.66,-417.63|Build/Props
Part|Part|1|15.15,0.17,6.63|1631.5,67.66,-296.64|Build/Props
Part|Part|1|27.15,0.17,10.63|1617.5,67.66,-298.64|Build/Props
Part|Part|1|5.65,38.6,20.44|1660.24,86.88,-443.8|Build/Props
Part|Part|1|22.15,0.17,17.63|1862,67.66,-298.14|Build/Props
Part|Part|1|5.65,38.6,20.44|1617.24,86.88,-284.8|Build/Props
Part|Part|1|15.15,0.17,9.63|1602.5,67.66,-302.14|Build/Props
Part|Part|1|14.15,0.17,6.63|1621,67.66,-306.64|Build/Props
Part|Part|1|14.8,0.17,7.4|1676.37,67.66,-432.13|Build/Props
Part|Part|1|8.59,0.17,7.88|1808.47,67.66,-302.65|Build/Props
Part|Part|1|5.87,0.17,3.27|1751.94,67.66,-314.24|Build/Props
Part|Part|1|33.33,0.17,8.4|1779.84,67.66,-430.65|Build/Props
Part|Part|1|23.8,0.17,13.4|1780.87,67.66,-422.13|Build/Props
Part|Part|1|7.57,0.17,7.88|1806.04,67.66,-306.65|Build/Props
Part|Part|1|8.79,0.17,10.91|1752.43,67.66,-308.56|Build/Props
Part|Part|1|5.65,38.6,20.44|1866.24,86.88,-284.8|Build/Props
Part|Part|1|28.8,0.17,13.4|1657.37,67.66,-430.13|Build/Props
Part|Part|1|8.79,0.17,7.74|1749.97,67.66,-304.61|Build/Props
Part|Part|1|5.65,38.6,20.44|1775.24,86.88,-443.8|Build/Props
Meshes/untitled (3)|MeshPart|1|4.9,4.9,4.9|2153.45,103.08,-425.45|Build/Props
Meshes/untitled (3)|MeshPart|1|4.9,4.9,4.9|2144.45,85.08,-413.45|Build/Props
Meshes/untitled (3)|MeshPart|1|4.9,4.9,4.9|2354.45,91.08,-310.45|Build/Props
Meshes/untitled (3)|MeshPart|1|4.9,4.9,4.9|2024.45,84.08,-308.55|Build/Props
Meshes/untitled (3)|MeshPart|1|4.9,4.9,4.9|2348.45,108.08,-303.45|Build/Props
Meshes/untitled (3)|MeshPart|1|4.9,4.9,4.9|2034.55,93.08,-315.55|Build/Props
Meshes/untitled (3)|MeshPart|1|4.9,4.9,4.9|2025.45,101.08,-316.45|Build/Props
Meshes/untitled (3)|MeshPart|1|4.9,4.9,4.9|2344.45,103.08,-318.45|Build/Props
Meshes/untitled (3)|MeshPart|1|4.9,4.9,4.9|2154.45,93.08,-412.45|Build/Props
Meshes/untitled_Cylinder.002 (7)|MeshPart|1|1.73,7.26,0.82|2223.46,68.26,-317.93|Build/Props
Meshes/untitled_Cylinder.007 (1)|MeshPart|1|2.06,10.54,2.59|2226.27,67.87,-315.48|Build/Props
Meshes/untitled_Cylinder.004 (2)|MeshPart|1|2.64,9.78,2.08|2226.71,68.7,-317.01|Build/Props
Meshes/untitled_Cylinder.005 (1)|MeshPart|1|1.45,6.35,1.31|2227.3,68.27,-314.2|Build/Props
Meshes/untitled_Cylinder.006 (1)|MeshPart|1|4.15,6.17,0.92|2228.88,68.07,-314.16|Build/Props
Part|Part|1|5.18,3,5.28|2224.79,69.08,-305.25|Build/Props
Part|Part|1|6,1.94,4.5|2221.34,68.55,-307.24|Build/Props
Part|Part|1|5.18,3,5.28|1991.23,69.08,-302.17|Build/Props
Part|Part|1|6,1.94,4.5|1987.78,68.55,-304.16|Build/Props
Part|Part|1|4.4,2.53,3.78|2140.31,68.72,-417.25|Build/Props
Part|Part|1|5.18,3,5.28|2137.21,69.08,-417.75|Build/Props
Part|Part|1|4.4,1.94,3.78|2139.81,68.55,-415.98|Build/Props
Part|Part|1|6.15,1.18,5.09|2134.31,68.17,-417.24|Build/Props
Part|Part|1|1.9,3.81,1.9|2029.08,68.23,-420.17|Build/Props
Part|Part|1|1.9,3.81,1.9|2031.9,67.72,-423.29|Build/Props
Part|Part|1|1.9,3.81,1.9|2029.48,68.3,-416.61|Build/Props
Part|Part|1|3.81,1.9,1.9|2036.25,67.98,-420.2|Build/Props
Part|Part|1|3.81,3.81,1.9|2033.16,68,-420.05|Build/Props
Part|Part|1|1.9,3.81,1.9|2033.62,67.62,-416.01|Build/Props
Part|Part|1|1.9,3.81,1.9|2353.28,68.48,-324.13|Build/Props
Part|Part|1|1.9,3.81,1.9|2351.37,68.51,-321.37|Build/Props
Part|Part|1|1.9,3.81,1.9|2350.71,67.79,-327.07|Build/Props
Part|Part|1|3.81,1.9,1.9|2345.79,68.73,-325.77|Build/Props
Part|Part|1|1.9,3.81,1.9|2347.1,67.78,-320.59|Build/Props
Part|Part|1|3.81,3.81,1.9|2348.24,68.73,-323.88|Build/Props
Part|Part|1|6,1.5,4.5|2315.41,68.33,-426|Build/Props
Part|Part|1|6,3,4.5|2312.21,69.08,-428.44|Build/Props
Coral|MeshPart|1|9.46,27.8,16.09|2307.95,81.48,-425.33|Build/Props
Coral|MeshPart|1|10.05,29.53,17.09|1999.55,82.34,-305.02|Build/Props
Coral|MeshPart|1|4.1,14.1,3.96|2013.05,74.63,-303.02|Build/Props
Coral|MeshPart|1|4.1,14.1,3.96|2151.05,74.63,-424.98|Build/Props
Coral|MeshPart|1|10.05,29.53,17.09|2138.02,82.34,-422.55|Build/Props
Meshes/untitled_Cylinder.006 (1)|MeshPart|1|4.94,7.34,1.1|2771.16,68.1,-416.89|Build/Props
Meshes/untitled_Cylinder.004 (2)|MeshPart|1|3.13,11.64,2.48|2773.74,68.85,-413.51|Build/Props
Meshes/untitled_Cylinder.007 (1)|MeshPart|1|2.45,12.53,3.08|2774.27,67.87,-415.32|Build/Props
Meshes/untitled_Cylinder.002 (7)|MeshPart|1|2.06,8.64,0.97|2777.61,68.33,-412.42|Build/Props
Meshes/untitled_Cylinder.005 (1)|MeshPart|1|1.72,7.55,1.56|2773.04,68.34,-416.85|Build/Props
Meshes/untitled_Cylinder.002 (7)|MeshPart|1|4.64,19.49,2.2|2501.68,69.45,-308.81|Build/Props
Meshes/untitled_Cylinder.015|MeshPart|1|34.45,62.72,12.96|2810.52,108.67,-309.48|Build/Props
Meshes/untitled_Cylinder.002 (7)|MeshPart|1|4.53,42.59,2.15|2471.41,67.6,-312.82|Build/Props
Meshes/untitled_Cylinder.011|MeshPart|1|38.07,63.33,13.51|2433.31,100.8,-422.55|Build/Props
Meshes/untitled_Cylinder.014|MeshPart|1|30.1,69.13,10.9|2644.56,106.26,-300.15|Build/Props
Meshes/untitled_Cylinder.007 (1)|MeshPart|1|6.45,52.74,12.96|2497.2,84.55,-433.52|Build/Props
Meshes/untitled_Cylinder.006 (1)|MeshPart|1|11.15,16.56,2.48|2487.14,68.93,-318.91|Build/Props
Meshes/untitled_Cylinder.010 (1)|MeshPart|1|11.24,19.74,7.09|2402.45,71.31,-414.64|Build/Props
Meshes/untitled_Cylinder.007 (1)|MeshPart|1|6.45,52.74,12.96|2573.82,96.15,-295.23|Build/Props
Meshes/untitled_Cylinder.012 (2)|MeshPart|1|39.83,69.84,11.08|2418.54,104.02,-297.13|Build/Props
Meshes/untitled_Cylinder.007 (1)|MeshPart|1|5.52,28.28,6.95|2494.14,68.4,-315.37|Build/Props
Meshes/untitled_Cylinder (3)|MeshPart|1|25.76,61.96,9.99|2837.69,109.52,-430.33|Build/Props
Meshes/untitled_Cylinder.009 (1)|MeshPart|1|49.89,65.47,13.32|2710.18,101.55,-426.71|Build/Props
Meshes/untitled_Cylinder.004 (2)|MeshPart|1|5.28,19.61,4.17|2833.36,68.81,-309.5|Build/Props
Meshes/untitled_Cylinder.005 (1)|MeshPart|1|3.89,17.03,3.52|2491.37,69.47,-318.81|Build/Props
Meshes/untitled_Cylinder.006 (1)|MeshPart|1|5,7.43,1.11|2545.5,68.45,-422.74|Build/Props
Meshes/untitled_Cylinder.004 (2)|MeshPart|1|12.05,44.75,9.52|2744.54,88.28,-295.14|Build/Props
Meshes/untitled_Cylinder.010 (1)|MeshPart|1|22.38,56.87,20.42|2591.46,101.49,-424.01|Build/Props
Meshes/untitled_Cylinder.013|MeshPart|1|35.15,61.52,15.83|2519.57,103.79,-309.59|Build/Props
Meshes/untitled_Cylinder (2)|MeshPart|1|23.13,21.37,22.56|2658.12,73.52,-417.35|Build/Props
Meshes/untitled_Cylinder.002 (7)|MeshPart|1|2.68,11.26,1.27|2831.5,70.76,-309.61|Build/Props
Meshes/untitled_Cylinder.007 (1)|MeshPart|1|4.94,25.3,6.22|2545.03,67.87,-423.7|Build/Props
Meshes/untitled_Cylinder.001 (3)|MeshPart|1|7.72,11.14,5.25|2703.69,68.5,-311.69|Build/Props
Meshes/untitled_Cylinder.002 (7)|MeshPart|1|6.16,25.89,2.92|2708.14,67.76,-315.83|Build/Props
Meshes/untitled_Cylinder.007 (1)|MeshPart|1|5.26,43,10.56|2738.03,90.73,-433.52|Build/Props
Meshes/untitled_Cylinder.001 (3)|MeshPart|1|8.58,12.37,5.83|2611.17,67.3,-302.83|Build/Props
Bamboo|Part|1|0.68,6.3,0.68|2673.08,70.72,-430.52|Build/Props
Bamboo|Part|1|0.68,3.6,0.68|2674.27,69.38,-428.34|Build/Props
Bamboo|Part|1|0.68,11.56,0.68|2675.66,73.35,-430.32|Build/Props
Bamboo|Part|1|0.68,6.3,0.68|2793.66,70.72,-428.66|Build/Props
Bamboo|Part|1|0.68,3.6,0.68|2791.48,69.38,-427.48|Build/Props
Bamboo|Part|1|0.68,11.56,0.68|2793.46,73.35,-426.08|Build/Props
Bamboo|Part|1|0.68,11.56,0.68|2737.08,73.35,-298.54|Build/Props
Bamboo|Part|1|0.68,6.3,0.68|2739.66,70.72,-298.34|Build/Props
Bamboo|Part|1|0.68,3.6,0.68|2738.48,69.38,-300.52|Build/Props
Bamboo|Part|1|0.68,3.6,0.68|2770.27,69.38,-426.34|Build/Props
Bamboo|Part|1|0.68,6.3,0.68|2769.08,70.72,-428.52|Build/Props
Bamboo|Part|1|0.68,11.56,0.68|2771.66,73.35,-428.32|Build/Props
Bamboo|Part|1|0.68,3.6,0.68|2523.52,69.38,-425.34|Build/Props
Bamboo|Part|1|0.68,6.3,0.68|2522.34,70.72,-427.52|Build/Props
Bamboo|Part|1|0.68,11.56,0.68|2524.92,73.35,-427.32|Build/Props
Middle|Part|1|3.27,0.45,3.27|2575.92,68.76,-428.92|Build/Props
Petal|Part|1|7.19,0.65,3.27|2575.92,68.21,-428.92|Build/Props
Petal|Part|1|7.19,0.65,3.27|2575.92,68.21,-428.92|Build/Props
Petal|Part|1|7.19,0.65,3.27|2691.02,68.21,-306.69|Build/Props
Middle|Part|1|3.27,0.45,3.27|2691.02,68.76,-306.69|Build/Props
Petal|Part|1|7.19,0.65,3.27|2691.02,68.21,-306.69|Build/Props
Petal|Part|1|5.93,0.54,2.69|2440.2,67.85,-419.2|Build/Props
Middle|Part|1|2.69,0.37,2.69|2440.2,68.3,-419.2|Build/Props
Petal|Part|1|5.93,0.54,2.69|2440.2,67.85,-419.2|Build/Props
Petal|Part|1|5.56,0.51,2.53|2718.74,68.13,-301.88|Build/Props
Middle|Part|1|2.53,0.35,2.53|2718.74,68.56,-301.88|Build/Props
Petal|Part|1|5.56,0.51,2.53|2718.74,68.13,-301.88|Build/Props
Part3|Part|1|7.71,5.52,5.9|2778.61,70.34,-422.74|Build/Props
Part3|Part|1|9.72,2.18,6.97|2777.03,68.67,-424.86|Build/Props
Part3|Part|1|10.94,3.64,8.97|2782.03,69.4,-422.59|Build/Props
Part3|Part|1|5,1.12,11|2732.47,67.32,-296.92|Build/Props
Part3|Part|1|24,1.12,21|2695.97,67.32,-301.92|Build/Props
Part3|Part|1|29,1.12,15|2669.47,67.32,-298.92|Build/Props
Part3|Part|1|22,1.12,18|2718.97,67.32,-300.42|Build/Props
Part3|Part|1|4,1.12,6|2449.97,67.32,-297.42|Build/Props
Part3|Part|1|9,1.12,4|2569.47,67.32,-421.42|Build/Props
Part3|Part|1|24,1.12,6|2439.97,67.32,-432.42|Build/Props
Part3|Part|1|28,1.12,5|2584.97,67.32,-426.92|Build/Props
Part3|Part|1|14,1.12,5|2423.97,67.32,-296.92|Build/Props
Part3|Part|1|17,1.12,8|2439.47,67.32,-298.42|Build/Props
Part3|Part|1|54,1.12,8|2592.97,67.32,-433.42|Build/Props
Part3|Part|1|14,1.12,3|2438.97,67.32,-427.92|Build/Props
Part3|Part|1|64,1.12,9|2554.97,67.32,-295.92|Build/Props
Part3|Part|1|27,1.12,4|2565.47,67.32,-302.42|Build/Props
Part3|Part|1|22.6,24.56,7|2649.26,83.55,-292.43|Build/Props
Part3|Part|1|32.02,34.31,7|2658.39,84.06,-435.99|Build/Props
Part3|Part|1|32.71,5.78,7|2435.67,96.82,-292.58|Build/Props
Part3|Part|1|47.71,26.93,7|2839.44,80.37,-435.96|Build/Props
Part3|Part|1|47.71,11.7,7|2449.19,72.76,-293.41|Build/Props
Part3|Part|1|47.71,16.4,7|2491.93,75.11,-292.41|Build/Props
Part3|Part|1|25.94,7.1,7|2645.4,70.81,-295.45|Build/Props
Part3|Part|1|22,28.12,7|2629.61,80.97,-436.3|Build/Props
Part3|Part|1|47.71,16.4,7|2820.54,75.11,-432.59|Build/Props
Part3|Part|1|22.6,17.91,7|2658.42,76.53,-293.59|Build/Props
Meshes/untitled (4)|MeshPart|1|4.95,0.31,4.7|2914.71,88.75,-433.65|Build/Props
Meshes/untitled (4)|MeshPart|1|4.95,0.31,4.7|3326.55,93.17,-433.65|Build/Props
Meshes/untitled (4)|MeshPart|1|4.95,0.31,4.7|3133.63,95.02,-433.65|Build/Props
Meshes/untitled (4)|MeshPart|1|4.95,0.31,4.7|3391.55,91.02,-433.65|Build/Props
Meshes/untitled (4)|MeshPart|1|4.95,0.31,4.7|3068.04,98.02,-433.65|Build/Props
Meshes/untitled (4)|MeshPart|1|4.95,0.31,4.7|3223.55,86.23,-433.65|Build/Props
Meshes/untitled (4)|MeshPart|1|4.95,0.31,4.7|2964.63,89.02,-433.65|Build/Props
Meshes/untitled (4)|MeshPart|1|4.95,0.31,4.7|3283.55,84.09,-433.65|Build/Props
Meshes/untitled (4)|MeshPart|1|4.95,0.31,4.7|3427.55,84.09,-433.65|Build/Props
Meshes/untitled (4)|MeshPart|1|4.95,0.31,4.7|3101.63,84.23,-433.65|Build/Props
Meshes/untitled (4)|MeshPart|1|4.95,0.31,4.7|3257.55,96.02,-433.65|Build/Props
Meshes/untitled (4)|MeshPart|1|4.95,0.31,4.7|2932.63,97.02,-433.65|Build/Props
Meshes/untitled (4)|MeshPart|1|4.95,0.31,4.7|3189.63,93.17,-433.65|Build/Props
Meshes/untitled (4)|MeshPart|1|4.95,0.31,4.7|2995.93,97.29,-433.65|Build/Props
Meshes/untitled (4)|MeshPart|1|4.95,0.31,4.7|3365.55,88.02,-433.65|Build/Props
Meshes/untitled (4)|MeshPart|1|4.95,0.31,4.7|3160.63,85.23,-433.65|Build/Props
Meshes/untitled (4)|MeshPart|1|4.95,0.31,4.7|3463.55,94.02,-433.65|Build/Props
Meshes/untitled (4)|MeshPart|1|4.95,0.31,4.7|3493.55,89.02,-433.65|Build/Props
Meshes/untitled (4)|MeshPart|1|4.95,0.31,4.7|3035.63,92.17,-433.65|Build/Props
Meshes/untitled (4)|MeshPart|1|4.95,0.31,4.7|3019.22,89.73,-294.78|Build/Props
Meshes/untitled (4)|MeshPart|1|4.95,0.31,4.7|2947.22,92.73,-294.78|Build/Props
Meshes/untitled (4)|MeshPart|1|4.95,0.31,4.7|3375.15,90.87,-294.78|Build/Props
Meshes/untitled (4)|MeshPart|1|4.95,0.31,4.7|3045.22,86.73,-294.78|Build/Props
Meshes/untitled (4)|MeshPart|1|4.95,0.31,4.7|3496.06,87.46,-294.78|Build/Props
Meshes/untitled (4)|MeshPart|1|4.95,0.31,4.7|3221.15,91.87,-294.78|Build/Props
Meshes/untitled (4)|MeshPart|1|4.95,0.31,4.7|3309.15,82.94,-294.78|Build/Props
Meshes/untitled (4)|MeshPart|1|4.95,0.31,4.7|3153.22,94.73,-294.78|Build/Props
Meshes/untitled (4)|MeshPart|1|4.95,0.31,4.7|3250.15,83.94,-294.78|Build/Props
Meshes/untitled (4)|MeshPart|1|4.95,0.31,4.7|3446.15,87.73,-294.78|Build/Props
Meshes/untitled (4)|MeshPart|1|4.95,0.31,4.7|3414.84,96,-294.78|Build/Props
Meshes/untitled (4)|MeshPart|1|4.95,0.31,4.7|2983.22,82.8,-294.78|Build/Props
Meshes/untitled (4)|MeshPart|1|4.95,0.31,4.7|2917.22,87.73,-294.78|Build/Props
Meshes/untitled (4)|MeshPart|1|4.95,0.31,4.7|3127.22,82.8,-294.78|Build/Props
Meshes/untitled (4)|MeshPart|1|4.95,0.31,4.7|3084.22,91.87,-294.78|Build/Props
Meshes/untitled (4)|MeshPart|1|4.95,0.31,4.7|3277.15,93.73,-294.78|Build/Props
Meshes/untitled (4)|MeshPart|1|4.95,0.31,4.7|3478.15,95.73,-294.78|Build/Props
Meshes/untitled (4)|MeshPart|1|4.95,0.31,4.7|3342.73,96.73,-294.78|Build/Props
Meshes/untitled (4)|MeshPart|1|4.95,0.31,4.7|3187.22,84.94,-294.78|Build/Props
Meshes/untitled_Cylinder.024 (1)|MeshPart|1|211.94,67.44,552.49|3186.36,159.94,-371.03|Build/Props
Meshes/untitled_Cylinder.026 (2)|MeshPart|1|186.18,66.2,517.51|3200.66,156.08,-360.16|Build/Props
Meshes/untitled_Cylinder.030 (1)|MeshPart|1|198.25,67.64,579.69|3185.12,158.87,-378.95|Build/Props
Meshes/untitled_Cylinder.028 (2)|MeshPart|1|194.38,67.94,499.52|3208.92,161.26,-378.7|Build/Props
Meshes/untitled_Cylinder.025 (1)|MeshPart|1|166.97,55.29,496.77|3208.98,156.79,-388.5|Build/Props
Meshes/untitled_Cylinder.022 (1)|MeshPart|1|211.76,84.08,541.12|3208.08,157.61,-372.3|Build/Props
Meshes/untitled_Cylinder.023 (1)|MeshPart|1|209.36,85.23,558.99|3189.38,156.46,-372.64|Build/Props
Meshes/untitled_Cylinder.029 (1)|MeshPart|1|201.35,78.72,539.36|3177.83,160.91,-368.18|Build/Props
Meshes/untitled_Cylinder.027 (2)|MeshPart|1|186.82,77.91,529.09|3214.29,158.97,-372.17|Build/Props
Meshes/untitled_Cube.005 (2)|MeshPart|1|59.52,59.52,59.52|3150.34,146.05,-483.88|Build/Props
Meshes/untitled_Cube.005 (2)|MeshPart|1|86.74,86.74,86.74|3150.34,146.05,-483.88|Build/Props
Meshes/untitled_Cube.005 (2)|MeshPart|1|90.03,90.03,90.03|3150.34,146.05,-483.88|Build/Props
Meshes/untitled_Cube.005 (2)|MeshPart|1|75.3,75.3,75.3|3150.34,146.05,-483.88|Build/Props
Meshes/untitled_Cube.005 (2)|MeshPart|1|53.64,53.64,53.64|3150.34,146.05,-483.88|Build/Props
Meshes/untitled_Cube.005 (2)|MeshPart|1|80.26,80.26,80.26|3150.34,146.05,-483.88|Build/Props
Meshes/untitled_Cube.005 (2)|MeshPart|1|64.71,64.71,64.71|3150.34,146.05,-483.88|Build/Props
Meshes/untitled_Cylinder.032|MeshPart|1|147.64,18.16,174.53|3133.14,144.34,-484.21|Build/Props
Meshes/untitled_Cylinder.031|MeshPart|1|155.2,18.16,184.86|3168.73,151.16,-486.22|Build/Props
Meshes/untitled_Cube.006 (1)|MeshPart|1|49.47,49.47,49.47|3150.34,146.05,-483.88|Build/Props
Meshes/untitled_Cylinder.033|MeshPart|1|175.42,10.2,184.86|3143.34,142.78,-487.25|Build/Props
Meshes/untitled_Cube.005 (2)|MeshPart|1|68.9,68.9,68.9|3150.34,146.05,-483.88|Build/Props
Meshes/untitled_Cylinder.021|MeshPart|1|184.86,18.16,153.19|3148.35,141.59,-464.25|Build/Props
RockPile1|MeshPart|1|25.23,2.92,21.32|5801.38,69.04,-301.34|Build/Props
RockPile2|MeshPart|1|18.42,2.24,13.79|5303.21,68.72,-282.1|Build/Props
RockPile1|MeshPart|1|21.23,2.92,20.32|5233.38,69.04,-273.16|Build/Props
RockPile2|MeshPart|1|18.42,2.24,13.79|5655.79,68.72,-289.1|Build/Props
RockPile2|MeshPart|1|18.42,2.24,13.79|5816.23,68.72,-302.25|Build/Props
RockPile2|MeshPart|1|18.42,2.24,13.79|5351.21,68.72,-299.1|Build/Props
RockPile1|MeshPart|1|22.23,2.92,21.32|5998.66,69.04,-298.88|Build/Props
RockPile2|MeshPart|1|18.42,2.24,13.79|5145.21,68.72,-295.1|Build/Props
untitled|MeshPart|1|42.13,104.43,3.1|5551.96,120.08,-262.3|Build/Props
untitled|MeshPart|1|42.13,104.43,3.1|5594.09,120.08,-262.3|Build/Props
Bush1|MeshPart|1|7.61,3.04,5.76|5276.88,69.1,-289.8|Build/Props
Bush2|MeshPart|1|8.46,2.1,5.19|5176.77,68.63,-322.4|Build/Props
Part|Part|1|65,3,8|5573.02,35.08,-144.81|Build/Props
Part|Part|1|65,3,8|5573.02,53.08,-192.81|Build/Props
Part|Part|1|65,3,8|5573.02,32.08,-136.81|Build/Props
Part|Part|1|65,3,8|5573.02,59.08,-208.81|Build/Props
Part|Part|1|65,3,8|5573.02,41.08,-160.81|Build/Props
Part|Part|1|65,3,8|5573.02,68.08,-232.81|Build/Props
Part|Part|1|65,3,8|5573.02,50.08,-184.81|Build/Props
Part|Part|1|65,3,8|5573.02,38.08,-152.81|Build/Props
Part|Part|1|65,3,8|5573.02,62.08,-216.81|Build/Props
Part|Part|1|65,3,8|5573.02,47.08,-176.81|Build/Props
Part|Part|1|65,3,8|5573.02,56.08,-200.81|Build/Props
Part|Part|1|65,3,8|5573.02,44.08,-168.81|Build/Props
Part|Part|1|65,3,8|5573.02,65.08,-224.81|Build/Props
Cylinder.003|MeshPart|1|8.96,11.4,9.74|5802.13,114.9,-293.06|Build/Props
Cylinder.006|MeshPart|1|8.65,11.01,9.35|5802.12,114.74,-293.02|Build/Props
Cylinder.003|MeshPart|1|11.03,14.03,11.99|5500.01,71.56,-295.52|Build/Props
Cylinder.006|MeshPart|1|10.64,13.55,11.51|5500.03,71.36,-295.51|Build/Props
Cylinder.003|MeshPart|1|11.03,14.03,11.99|5836.15,71.56,-302.01|Build/Props
Cylinder.006|MeshPart|1|10.64,13.55,11.51|5836.13,71.36,-302.01|Build/Props
Cylinder.006|MeshPart|1|8.65,11.01,9.35|5343.11,114.74,-293.12|Build/Props
Cylinder.003|MeshPart|1|8.96,11.4,9.74|5343.06,114.9,-293.13|Build/Props
Cylinder.006|MeshPart|1|8.65,11.01,9.35|5966.15,114.74,-293.55|Build/Props
Cylinder.003|MeshPart|1|8.96,11.4,9.74|5966.19,114.9,-293.58|Build/Props
Cylinder.007|MeshPart|1|15.08,15,17.77|5388.65,116.67,-288.38|Build/Props
Cylinder.005|MeshPart|1|14.54,14.53,17.23|5388.65,116.43,-288.31|Build/Props
Cylinder.007|MeshPart|1|15.08,15,17.77|5534.88,116.67,-281.24|Build/Props
Cylinder.005|MeshPart|1|14.54,14.53,17.23|5534.93,116.43,-281.28|Build/Props
Cylinder.003|MeshPart|1|9.47,12.04,10.29|5626.15,70.57,-298.01|Build/Props
Cylinder.006|MeshPart|1|9.13,11.63,9.88|5626.14,70.4,-297.99|Build/Props
Cylinder.006|MeshPart|1|8.65,11.01,9.35|5181.89,114.74,-292.88|Build/Props
Cylinder.003|MeshPart|1|8.96,11.4,9.74|5181.94,114.9,-292.87|Build/Props
Cylinder.005|MeshPart|1|14.54,14.53,17.23|5298.73,116.43,-288.97|Build/Props
Cylinder.007|MeshPart|1|15.08,15,17.77|5298.67,116.67,-288.97|Build/Props
Cylinder.005|MeshPart|1|14.54,14.53,17.23|5757.52,116.43,-288.14|Build/Props
Cylinder.007|MeshPart|1|15.08,15,17.77|5757.46,116.67,-288.11|Build/Props
Cylinder.003|MeshPart|1|9.47,12.04,10.29|5223.46,70.57,-313.1|Build/Props
Cylinder.006|MeshPart|1|9.13,11.63,9.88|5223.48,70.4,-313.09|Build/Props
Cylinder.005|MeshPart|1|14.54,14.53,17.23|5846.12,116.43,-290.4|Build/Props
Cylinder.007|MeshPart|1|15.08,15,17.77|5846.11,116.67,-290.46|Build/Props
Cylinder.005|MeshPart|1|14.63,14.62,17.33|5135.84,116.48,-289.7|Build/Props
Cylinder.007|MeshPart|1|15.17,15.09,17.88|5135.84,116.72,-289.76|Build/Props
Cylinder.007|MeshPart|1|15.08,15,17.77|5922.54,116.67,-290.89|Build/Props
Cylinder.005|MeshPart|1|14.54,14.53,17.23|5922.48,116.43,-290.86|Build/Props
Cylinder.005|MeshPart|1|14.54,14.53,17.23|6007.31,116.43,-288.68|Build/Props
Cylinder.007|MeshPart|1|15.08,15,17.77|6007.25,116.67,-288.66|Build/Props
Cylinder.007|MeshPart|1|13.9,13.83,16.38|5223.89,116.08,-287.74|Build/Props
Cylinder.005|MeshPart|1|13.4,13.39,15.88|5223.83,115.86,-287.73|Build/Props
Cylinder.007|MeshPart|1|15.08,15,17.77|5611.76,116.67,-280.88|Build/Props
Cylinder.005|MeshPart|1|14.54,14.53,17.23|5611.72,116.43,-280.93|Build/Props
Part|Part|1|60,1,41|5481.44,107.08,-256.17|Build/Props
Part|Part|1|60,1,41|5664.02,133.08,-211.32|Build/Props
Part|Part|1|60,1,41|5645.33,114.08,-222.04|Build/Props
Part|Part|1|58,1,35|5291.03,112.08,-227.01|Build/Props
Part|Part|1|60,1,41|5432.44,132.08,-236.17|Build/Props
Part|Part|1|60,1,41|5456.9,151.08,-212.02|Build/Props
Part|Part|1|65,1,33|5979.66,126.08,-247.65|Build/Props
Part|Part|1|82,1,41|5749.29,131.08,-245.85|Build/Props
Part|Part|1|77,1,41|5898.14,108.08,-227.93|Build/Props
Part|Part|1|48,1,23|5165.64,116.08,-263.51|Build/Props
Part|Part|1|24,1,48|5522.44,96.08,-254.72|Build/Props
Part|Part|1|58,1,23|5180.81,129.08,-241.4|Build/Props
Part|Part|1|65,1,33|6003.19,119.08,-260.73|Build/Props
Part|Part|1|45,1,44|5500.99,128.08,-229.31|Build/Props
Part|Part|1|60,1,41|5691.2,151.08,-232|Build/Props
Part|Part|1|15,1,50|5620.66,104.08,-259.94|Build/Props
Part|Part|1|65,1,60|5791.22,136.08,-237.23|Build/Props
Part|Part|1|70,1,23|5239.14,107.08,-233.51|Build/Props
Part|Part|1|41,1,41|5844.75,119.08,-244.25|Build/Props
Part|Part|1|60,1,41|5638.85,91.08,-238.74|Build/Props
Part|Part|1|42,1,23|5348.08,118.08,-270.29|Build/Props
Part|Part|1|66,1,23|5383.9,122.08,-251.29|Build/Props
Part|Part|1|22,1,41|5516.69,110.08,-219.25|Build/Props
Part|Part|1|41,61.1,41|5844.75,88.03,-244.25|Build/Props
Part|Part|1|15,66,50|5620.66,70.58,-259.94|Build/Props
Part|Part|1|42,32,23|5348.08,101.58,-270.29|Build/Props
Part|Part|1|60,45,41|5481.44,84.08,-256.17|Build/Props
Part|Part|1|22,56,41|5516.69,81.58,-219.25|Build/Props
Part|Part|1|65,88.1,33|5979.66,81.53,-247.65|Build/Props
Part|Part|1|82,76.7,41|5749.29,92.23,-245.85|Build/Props
Part|Part|1|99.1,58,41|5909.15,78.58,-228.9|Build/Props
Part|Part|1|65,75.6,60|5791.22,97.78,-237.23|Build/Props
Part|Part|1|60,36,41|5432.44,113.58,-236.17|Build/Props
Part|Part|1|45,31,44|5500.99,112.08,-229.31|Build/Props
Part|Part|1|65,78,33|6003.19,79.58,-260.73|Build/Props
Part|Part|1|58,38,23|5180.81,109.58,-241.4|Build/Props
Part|Part|1|60,56,41|5664.02,104.58,-211.32|Build/Props
Part|Part|1|70,21,23|5239.14,96.08,-233.51|Build/Props
Part|Part|1|60,66,41|5638.85,57.58,-238.74|Build/Props
Part|Part|1|58,26,35|5291.03,98.58,-227.01|Build/Props
Part|Part|1|24,56,48|5522.44,67.58,-254.72|Build/Props
Part|Part|1|60,74,41|5456.9,113.58,-212.02|Build/Props
Part|Part|1|60,108.2,41|5691.2,96.48,-232|Build/Props
Part|Part|1|60,56,41|5645.33,85.58,-222.04|Build/Props
Part|Part|1|66,36,23|5383.9,103.58,-251.29|Build/Props
Part|Part|1|48,25,23|5165.64,103.08,-263.51|Build/Props
Part|Part|1|19,0.5,1.5|5326.52,67.83,-323.56|Build/Props
Part|Part|1|31,0.5,9|5484.02,68.32,-305.31|Build/Props
Part|Part|1|9,0.5,2|5180.5,67.83,-327|Build/Props
Part|Part|1|14,0.5,1|5661.52,67.83,-316.31|Build/Props
Part|Part|1|2,0.5,13|5240.52,68.33,-314.31|Build/Props
Part|Part|1|31,0.5,9|5720.02,68.32,-305.31|Build/Props
Part|Part|1|3,0.5,9|5902.02,67.83,-304.31|Build/Props
Part|Part|1|16,0.5,2|5480.52,67.83,-319.81|Build/Props
Part|Part|1|6.5,0.5,7.5|5245.77,67.83,-291.56|Build/Props
Part|Part|1|22,0.5,7|5449.52,67.83,-318.31|Build/Props
Part|Part|1|15,0.5,4|5503.02,67.83,-313.81|Build/Props
Part|Part|1|23,0.5,3|5938.02,68.33,-320.31|Build/Props
Part|Part|1|2,0.5,9|5238.52,68.33,-313.31|Build/Props
Part|Part|1|18,0.5,8|5967.52,68.33,-295.81|Build/Props
Part|Part|1|4,0.5,14|5866.52,67.83,-307.81|Build/Props
Part|Part|1|10,0.5,3|5166.52,68.33,-320.31|Build/Props
Part|Part|1|24,0.5,3|5177,67.83,-324.5|Build/Props
Part|Part|1|4.5,0.5,5.5|5244.77,67.83,-298.06|Build/Props
Part|Part|1|11,0.5,7|5505.02,68.32,-306.31|Build/Props
Part|Part|1|19,0.5,4|5224.02,67.83,-324.81|Build/Props
Part|Part|1|24,0.5,4|5663.52,67.83,-313.81|Build/Props
Part|Part|1|15,0.5,2|5189.02,68.33,-320.81|Build/Props
Part|Part|1|2,0.5,8|5865.52,67.83,-296.81|Build/Props
Part|Part|1|8.5,0.5,2.5|5256.77,67.83,-285.06|Build/Props
Part|Part|1|13.5,0.5,2.5|5306.27,67.83,-326.56|Build/Props
Part|Part|1|5,0.5,16|5901.02,67.83,-291.81|Build/Props
Part|Part|1|35,0.5,8.5|5478.02,67.83,-314.56|Build/Props
Part|Part|1|10,0.5,4|5247.52,67.83,-285.81|Build/Props
Part|Part|1|24,0.5,9|5710.52,68.32,-289.31|Build/Props
Part|Part|1|4.5,0.5,9|5279.27,67.83,-288.31|Build/Props
Part|Part|1|4,0.5,11|5896.52,67.83,-289.31|Build/Props
Part|Part|1|13.5,0.5,4|5188.77,68.83,-294.81|Build/Props
Part|Part|1|28,0.5,5|5342.52,68.83,-294.31|Build/Props
Part|Part|1|19,0.5,6|5389.02,68.83,-312.81|Build/Props
Part|Part|1|12.5,0.5,5|5343.27,68.83,-299.31|Build/Props
Part|Part|1|4.5,0.5,5.5|5274.77,67.83,-286.56|Build/Props
Part|Part|1|26.5,0.5,2.5|5303.77,67.83,-324.06|Build/Props
Part|Part|1|17,0.5,2|5936.02,67.83,-326.81|Build/Props
Part|Part|1|9,0.5,1|5224.02,68.33,-319.31|Build/Props
Part|Part|1|13,0.5,4|5888.02,67.83,-285.81|Build/Props
Part|Part|1|11,0.5,3|5226.02,67.83,-328.31|Build/Props
Part|Part|1|21,0.5,2|5224.02,68.33,-320.81|Build/Props
Part|Part|1|15,0.5,5|5378.02,68.83,-318.31|Build/Props
Part|Part|1|4,0.5,13|5861.52,68.33,-307.31|Build/Props
Part|Part|1|30,0.5,3|5939.52,67.83,-324.31|Build/Props
Part|Part|1|18,0.5,10|5689.52,68.32,-291.81|Build/Props
Part|Part|1|10,0.5,5|5176.52,68.33,-319.31|Build/Props
Part|Part|1|14,0.5,6|5951.52,68.33,-294.81|Build/Props
Part|Part|1|11,0.5,6|5434.02,68.83,-290.81|Build/Props
Part|Part|1|16,1,2|5188.52,68.08,-298.81|Build/Props
Part|Part|1|13,1,4|5395.02,68.08,-308.81|Build/Props
Part|Part|1|10,1,7|5372.52,68.08,-318.31|Build/Props
Part|Part|1|27,1,5|5186.02,68.08,-295.31|Build/Props
Part|Part|1|31,1,5|5343.02,68.08,-295.31|Build/Props
Part|Part|1|19,1,6|5343.02,68.08,-300.81|Build/Props
Part|Part|1|19,1,3|5428.02,68.08,-289.31|Build/Props
Part|Part|1|3,1,17|5386.02,68.08,-313.31|Build/Props
Part|Part|1|7,1,13|5381.02,68.08,-315.31|Build/Props
Part|Part|1|16,1,5|5434.52,68.08,-293.31|Build/Props
Part|Part|1|5,31,17|5180.02,86.08,-284.31|Build/Props
Part|Part|1|7,3,6|5180.02,107.08,-292.81|Build/Props
Part|Part|1|7,2,6|5180.02,109.58,-292.81|Build/Props
Part|Part|1|3,30,1|5133.02,90.58,-294.31|Build/Props
Part|Part|1|1,30,3|5131.02,90.58,-286.31|Build/Props
Part|Part|1|9,32,9|5136.02,89.58,-289.31|Build/Props
Part|Part|1|3,30,11|5139.02,90.58,-289.31|Build/Props
Part|Part|1|1,30,3|5131.02,90.58,-292.31|Build/Props
Part|Part|1|1,30,3|5141.02,90.58,-292.31|Build/Props
Part|Part|1|3,30,1|5133.02,90.58,-284.31|Build/Props
Part|Part|1|13,2,11|5136.02,108.58,-289.31|Build/Props
Part|Part|1|5,2,9|5136.02,110.58,-289.31|Build/Props
Part|Part|1|9,2,5|5136.02,110.58,-289.31|Build/Props
Part|Part|1|9,2,11|5136.02,106.58,-289.31|Build/Props
Part|Part|1|11,2,13|5136.02,108.58,-289.31|Build/Props
Part|Part|1|11,2,9|5136.02,106.58,-289.31|Build/Props
Part|Part|1|13,1,11|5136.02,70.08,-289.31|Build/Props
Part|Part|1|9,6,11|5136.02,70.58,-289.31|Build/Props
Part|Part|1|13,2,11|5136.02,68.58,-289.31|Build/Props
Part|Part|1|11,2,13|5136.02,68.58,-289.31|Build/Props
Part|Part|1|11,6,9|5136.02,70.58,-289.31|Build/Props
Part|Part|1|11,1,13|5136.02,70.08,-289.31|Build/Props
Part|Part|1|19,2,3|5227.02,104.58,-274.31|Build/Props
Part|Part|1|19,2,2|5226.52,102.58,-274.31|Build/Props
Part|Part|1|19,20,1|5226.02,85.58,-274.31|Build/Props
Part|Part|1|25,34,1|5225.02,84.58,-277.31|Build/Props
Part|Part|1|25,1,1|5227.02,70.08,-277.31|Build/Props
Part|Part|1|17,3,1|5226.02,72.08,-275.31|Build/Props
Part|Part|1|25,2,2|5227.52,68.58,-277.31|Build/Props
Part|Part|1|1,31,2|5226.52,86.08,-283.31|Build/Props
Part|Part|1|19,4,1|5226.02,99.58,-274.31|Build/Props
Part|Part|1|78,1,1|5180.52,70.08,-292.31|Build/Props
Part|Part|1|77,6,2|5180.02,70.58,-290.81|Build/Props
Part|Part|1|77,2,5|5180.02,104.58,-291.31|Build/Props
Part|Part|1|79,32,2|5180.02,85.58,-289.81|Build/Props
Part|Part|1|78,2,2|5180.52,68.58,-291.81|Build/Props
Part|Part|1|77,7,1|5180.02,101.08,-291.31|Build/Props
Part|Part|1|77,20,1|5180.02,85.58,-291.31|Build/Props
Part|Part|1|77,2,1|5180.02,102.58,-292.31|Build/Props
Part|Part|1|9,2,5|5180.02,68.58,-293.31|Build/Props
Part|Part|1|9,1,5|5180.02,71.08,-293.31|Build/Props
Part|Part|1|8,1,4|5180.02,70.08,-293.31|Build/Props
Cube.019|MeshPart|1|5,38,2.39|5180.02,86.58,-294|Build/Props
Part|Part|1|11,2,9|5224.02,106.58,-289.31|Build/Props
Part|Part|1|13,2,11|5224.02,108.58,-289.31|Build/Props
Part|Part|1|5,2,9|5224.02,110.58,-289.31|Build/Props
Part|Part|1|11,2,13|5224.02,108.58,-289.31|Build/Props
Part|Part|1|9,2,11|5224.02,106.58,-289.31|Build/Props
Part|Part|1|9,2,5|5224.02,110.58,-289.31|Build/Props
Part|Part|1|9,32,9|5224.02,89.58,-289.31|Build/Props
Part|Part|1|3,30,1|5227.02,90.58,-294.31|Build/Props
Part|Part|1|3,30,11|5221.02,90.58,-289.31|Build/Props
Part|Part|1|1,30,3|5229.02,90.58,-286.31|Build/Props
Part|Part|1|3,30,1|5227.02,90.58,-284.31|Build/Props
Part|Part|1|1,30,3|5219.02,90.58,-292.31|Build/Props
Part|Part|1|1,30,3|5229.02,90.58,-292.31|Build/Props
Part|Part|1|13,1,11|5224.02,70.08,-289.31|Build/Props
Part|Part|1|9,6,11|5224.02,70.58,-289.31|Build/Props
Part|Part|1|13,2,11|5224.02,68.58,-289.31|Build/Props
Part|Part|1|11,1,13|5224.02,70.08,-289.31|Build/Props
Part|Part|1|11,2,13|5224.02,68.58,-289.31|Build/Props
Part|Part|1|11,6,9|5224.02,70.58,-289.31|Build/Props
Part|Part|1|1,2,2|5165.02,94.58,-291.81|Build/Props
Part|Part|1|12,1,2|5159.52,93.08,-291.81|Build/Props
Part|Part|1|1,2,2|5154.02,94.58,-291.81|Build/Props
Part|Part|1|12,1,2|5159.52,96.08,-291.81|Build/Props
Part|Part|1|10,2,1.1|5159.52,94.58,-291.36|Build/Props
Part|Part|1|7,3,6|5344.02,107.08,-292.81|Build/Props
Part|Part|1|7,2,6|5344.02,109.58,-292.81|Build/Props
Part|Part|1|5,31,17|5344.02,86.08,-284.31|Build/Props
Part|Part|1|11,6,9|5300.02,70.58,-289.31|Build/Props
Part|Part|1|13,1,11|5300.02,70.08,-289.31|Build/Props
Part|Part|1|13,2,11|5300.02,68.58,-289.31|Build/Props
Part|Part|1|11,2,13|5300.02,68.58,-289.31|Build/Props
Part|Part|1|11,1,13|5300.02,70.08,-289.31|Build/Props
Part|Part|1|9,6,11|5300.02,70.58,-289.31|Build/Props
Part|Part|1|1,30,3|5305.02,90.58,-292.31|Build/Props
Part|Part|1|3,30,11|5303.02,90.58,-289.31|Build/Props
Part|Part|1|3,30,1|5297.02,90.58,-284.31|Build/Props
Part|Part|1|1,30,3|5295.02,90.58,-292.31|Build/Props
Part|Part|1|3,30,1|5297.02,90.58,-294.31|Build/Props
Part|Part|1|1,30,3|5295.02,90.58,-286.31|Build/Props
Part|Part|1|9,32,9|5300.02,89.58,-289.31|Build/Props
Part|Part|1|13,2,11|5300.02,108.58,-289.31|Build/Props
Part|Part|1|9,2,11|5300.02,106.58,-289.31|Build/Props
Part|Part|1|11,2,13|5300.02,108.58,-289.31|Build/Props
Part|Part|1|5,2,9|5300.02,110.58,-289.31|Build/Props
Part|Part|1|11,2,9|5300.02,106.58,-289.31|Build/Props
Part|Part|1|9,2,5|5300.02,110.58,-289.31|Build/Props
Part|Part|1|11,6,9|5388.02,70.58,-289.31|Build/Props
Part|Part|1|9,6,11|5388.02,70.58,-289.31|Build/Props
Part|Part|1|13,1,11|5388.02,70.08,-289.31|Build/Props
Part|Part|1|11,2,13|5388.02,68.58,-289.31|Build/Props
Part|Part|1|11,1,13|5388.02,70.08,-289.31|Build/Props
Part|Part|1|13,2,11|5388.02,68.58,-289.31|Build/Props
Part|Part|1|3,30,1|5391.02,90.58,-294.31|Build/Props
Part|Part|1|3,30,1|5391.02,90.58,-284.31|Build/Props
Part|Part|1|3,30,11|5385.02,90.58,-289.31|Build/Props
Part|Part|1|1,30,3|5383.02,90.58,-292.31|Build/Props
Part|Part|1|1,30,3|5393.02,90.58,-292.31|Build/Props
Part|Part|1|9,32,9|5388.02,89.58,-289.31|Build/Props
Part|Part|1|1,30,3|5393.02,90.58,-286.31|Build/Props
Part|Part|1|9,2,11|5388.02,106.58,-289.31|Build/Props
Part|Part|1|9,2,5|5388.02,110.58,-289.31|Build/Props
Part|Part|1|13,2,11|5388.02,108.58,-289.31|Build/Props
Part|Part|1|11,2,13|5388.02,108.58,-289.31|Build/Props
Part|Part|1|5,2,9|5388.02,110.58,-289.31|Build/Props
Part|Part|1|11,2,9|5388.02,106.58,-289.31|Build/Props
Part|Part|1|10,2,1.1|5322.52,94.58,-291.36|Build/Props
Part|Part|1|12,1,2|5322.52,96.08,-291.81|Build/Props
Part|Part|1|12,1,2|5322.52,93.08,-291.81|Build/Props
Part|Part|1|1,2,2|5328.02,94.58,-291.81|Build/Props
Part|Part|1|1,2,2|5317.02,94.58,-291.81|Build/Props
Part|Part|1|8,1,4|5344.02,70.08,-293.31|Build/Props
Part|Part|1|9,1,5|5344.02,71.08,-293.31|Build/Props
Part|Part|1|9,2,5|5344.02,68.58,-293.31|Build/Props
Cube.019|MeshPart|1|5,38,2.39|5344.02,86.58,-294|Build/Props
Part|Part|1|78,1,1|5343.52,70.08,-292.31|Build/Props
Part|Part|1|77,6,2|5344.02,70.58,-290.81|Build/Props
Part|Part|1|78,2,2|5343.52,68.58,-291.81|Build/Props
Part|Part|1|79,32,2|5344.02,85.58,-289.81|Build/Props
Part|Part|1|77,20,1|5344.02,85.58,-291.31|Build/Props
Part|Part|1|77,7,1|5344.02,101.08,-291.31|Build/Props
Part|Part|1|77,2,5|5344.02,104.58,-291.31|Build/Props
Part|Part|1|77,2,1|5344.02,102.58,-292.31|Build/Props
Part|Part|1|19,2,3|5297.02,104.58,-274.31|Build/Props
Part|Part|1|19,20,1|5298.02,85.58,-274.31|Build/Props
Part|Part|1|25,1,1|5297.02,70.08,-277.31|Build/Props
Part|Part|1|1,31,2|5297.52,86.08,-283.31|Build/Props
Part|Part|1|17,3,1|5298.02,72.08,-275.31|Build/Props
Part|Part|1|19,4,1|5298.02,99.58,-274.31|Build/Props
Part|Part|1|25,34,1|5299.02,84.58,-277.31|Build/Props
Part|Part|1|25,2,2|5296.52,68.58,-277.31|Build/Props
Part|Part|1|19,2,2|5297.52,102.58,-274.31|Build/Props
Part|Part|1|7,3,6|5966.02,107.08,-292.81|Build/Props
Part|Part|1|7,2,6|5966.02,109.58,-292.81|Build/Props
Part|Part|1|5,31,17|5966.02,86.08,-284.31|Build/Props
Part|Part|1|3,30,11|6007.02,90.58,-289.31|Build/Props
Part|Part|1|1,30,3|6015.02,90.58,-292.31|Build/Props
Part|Part|1|1,30,3|6015.02,90.58,-286.31|Build/Props
Part|Part|1|1,30,3|6005.02,90.58,-292.31|Build/Props
Part|Part|1|9,32,9|6010.02,89.58,-289.31|Build/Props
Part|Part|1|3,30,1|6013.02,90.58,-284.31|Build/Props
Part|Part|1|3,30,1|6013.02,90.58,-294.31|Build/Props
Part|Part|1|11,2,9|6010.02,106.58,-289.31|Build/Props
Part|Part|1|5,2,9|6010.02,110.58,-289.31|Build/Props
Part|Part|1|9,2,5|6010.02,110.58,-289.31|Build/Props
Part|Part|1|11,2,13|6010.02,108.58,-289.31|Build/Props
Part|Part|1|13,2,11|6010.02,108.58,-289.31|Build/Props
Part|Part|1|9,2,11|6010.02,106.58,-289.31|Build/Props
Part|Part|1|13,2,11|6010.02,68.58,-289.31|Build/Props
Part|Part|1|9,6,11|6010.02,70.58,-289.31|Build/Props
Part|Part|1|11,2,13|6010.02,68.58,-289.31|Build/Props
Part|Part|1|11,1,13|6010.02,70.08,-289.31|Build/Props
Part|Part|1|13,1,11|6010.02,70.08,-289.31|Build/Props
Part|Part|1|11,6,9|6010.02,70.58,-289.31|Build/Props
Part|Part|1|17,3,1|5920.02,72.08,-275.31|Build/Props
Part|Part|1|19,2,2|5919.52,102.58,-274.31|Build/Props
Part|Part|1|19,20,1|5920.02,85.58,-274.31|Build/Props
Part|Part|1|1,31,2|5919.52,86.08,-283.31|Build/Props
Part|Part|1|25,1,1|5919.02,70.08,-277.31|Build/Props
Part|Part|1|25,2,2|5918.52,68.58,-277.31|Build/Props
Part|Part|1|25,34,1|5921.02,84.58,-277.31|Build/Props
Part|Part|1|19,2,3|5919.02,104.58,-274.31|Build/Props
Part|Part|1|19,4,1|5920.02,99.58,-274.31|Build/Props
Part|Part|1|77,20,1|5966.02,85.58,-291.31|Build/Props
Part|Part|1|78,2,2|5965.52,68.58,-291.81|Build/Props
Part|Part|1|77,2,5|5966.02,104.58,-291.31|Build/Props
Part|Part|1|77,2,1|5966.02,102.58,-292.31|Build/Props
Part|Part|1|77,6,2|5966.02,70.58,-290.81|Build/Props
Part|Part|1|79,32,2|5966.02,85.58,-289.81|Build/Props
Part|Part|1|78,1,1|5965.52,70.08,-292.31|Build/Props
Part|Part|1|77,7,1|5966.02,101.08,-291.31|Build/Props
Part|Part|1|1,30,3|5917.02,90.58,-286.31|Build/Props
Part|Part|1|3,30,1|5919.02,90.58,-284.31|Build/Props
Part|Part|1|3,30,11|5925.02,90.58,-289.31|Build/Props
Part|Part|1|3,30,1|5919.02,90.58,-294.31|Build/Props
Part|Part|1|9,32,9|5922.02,89.58,-289.31|Build/Props
Part|Part|1|1,30,3|5917.02,90.58,-292.31|Build/Props
Part|Part|1|1,30,3|5927.02,90.58,-292.31|Build/Props
Part|Part|1|13,2,11|5922.02,108.58,-289.31|Build/Props
Part|Part|1|11,2,13|5922.02,108.58,-289.31|Build/Props
Part|Part|1|5,2,9|5922.02,110.58,-289.31|Build/Props
Part|Part|1|11,2,9|5922.02,106.58,-289.31|Build/Props
Part|Part|1|9,2,11|5922.02,106.58,-289.31|Build/Props
Part|Part|1|9,2,5|5922.02,110.58,-289.31|Build/Props
Part|Part|1|9,6,11|5922.02,70.58,-289.31|Build/Props
Part|Part|1|13,1,11|5922.02,70.08,-289.31|Build/Props
Part|Part|1|11,2,13|5922.02,68.58,-289.31|Build/Props
Part|Part|1|13,2,11|5922.02,68.58,-289.31|Build/Props
Part|Part|1|11,1,13|5922.02,70.08,-289.31|Build/Props
Part|Part|1|11,6,9|5922.02,70.58,-289.31|Build/Props
Part|Part|1|9,2,5|5966.02,68.58,-293.31|Build/Props
Part|Part|1|9,1,5|5966.02,71.08,-293.31|Build/Props
Part|Part|1|8,1,4|5966.02,70.08,-293.31|Build/Props
Cube.019|MeshPart|1|5,38,2.39|5966.02,86.58,-294|Build/Props
Part|Part|1|1,2,2|5992.02,94.58,-291.81|Build/Props
Part|Part|1|12,1,2|5986.52,93.08,-291.81|Build/Props
Part|Part|1|1,2,2|5981.02,94.58,-291.81|Build/Props
Part|Part|1|10,2,1.1|5986.52,94.58,-291.36|Build/Props
Part|Part|1|12,1,2|5986.52,96.08,-291.81|Build/Props
Part|Part|1|7,3,6|5802.02,107.08,-292.81|Build/Props
Part|Part|1|7,2,6|5802.02,109.58,-292.81|Build/Props
Part|Part|1|5,31,17|5802.02,86.08,-284.31|Build/Props
Part|Part|1|11,1,13|5846.02,70.08,-289.31|Build/Props
Part|Part|1|13,2,11|5846.02,68.58,-289.31|Build/Props
Part|Part|1|9,6,11|5846.02,70.58,-289.31|Build/Props
Part|Part|1|11,2,13|5846.02,68.58,-289.31|Build/Props
Part|Part|1|13,1,11|5846.02,70.08,-289.31|Build/Props
Part|Part|1|11,6,9|5846.02,70.58,-289.31|Build/Props
Part|Part|1|3,30,11|5843.02,90.58,-289.31|Build/Props
Part|Part|1|1,30,3|5851.02,90.58,-292.31|Build/Props
Part|Part|1|1,30,3|5841.02,90.58,-292.31|Build/Props
Part|Part|1|3,30,1|5849.02,90.58,-294.31|Build/Props
Part|Part|1|3,30,1|5849.02,90.58,-284.31|Build/Props
Part|Part|1|1,30,3|5851.02,90.58,-286.31|Build/Props
Part|Part|1|9,32,9|5846.02,89.58,-289.31|Build/Props
Part|Part|1|11,2,9|5846.02,106.58,-289.31|Build/Props
Part|Part|1|11,2,13|5846.02,108.58,-289.31|Build/Props
Part|Part|1|5,2,9|5846.02,110.58,-289.31|Build/Props
Part|Part|1|13,2,11|5846.02,108.58,-289.31|Build/Props
Part|Part|1|9,2,11|5846.02,106.58,-289.31|Build/Props
Part|Part|1|9,2,5|5846.02,110.58,-289.31|Build/Props
Part|Part|1|9,6,11|5758.02,70.58,-289.31|Build/Props
Part|Part|1|13,1,11|5758.02,70.08,-289.31|Build/Props
Part|Part|1|11,6,9|5758.02,70.58,-289.31|Build/Props
Part|Part|1|11,1,13|5758.02,70.08,-289.31|Build/Props
Part|Part|1|11,2,13|5758.02,68.58,-289.31|Build/Props
Part|Part|1|13,2,11|5758.02,68.58,-289.31|Build/Props
Part|Part|1|3,30,1|5755.02,90.58,-284.31|Build/Props
Part|Part|1|3,30,11|5761.02,90.58,-289.31|Build/Props
Part|Part|1|3,30,1|5755.02,90.58,-294.31|Build/Props
Part|Part|1|1,30,3|5763.02,90.58,-292.31|Build/Props
Part|Part|1|9,32,9|5758.02,89.58,-289.31|Build/Props
Part|Part|1|1,30,3|5753.02,90.58,-286.31|Build/Props
Part|Part|1|1,30,3|5753.02,90.58,-292.31|Build/Props
Part|Part|1|9,2,5|5758.02,110.58,-289.31|Build/Props
Part|Part|1|9,2,11|5758.02,106.58,-289.31|Build/Props
Part|Part|1|13,2,11|5758.02,108.58,-289.31|Build/Props
Part|Part|1|11,2,13|5758.02,108.58,-289.31|Build/Props
Part|Part|1|11,2,9|5758.02,106.58,-289.31|Build/Props
Part|Part|1|5,2,9|5758.02,110.58,-289.31|Build/Props
Part|Part|1|77,7,1|5802.02,101.08,-291.31|Build/Props
Part|Part|1|78,2,2|5802.52,68.58,-291.81|Build/Props
Part|Part|1|79,32,2|5802.02,85.58,-289.81|Build/Props
Part|Part|1|77,2,5|5802.02,104.58,-291.31|Build/Props
Part|Part|1|77,6,2|5802.02,70.58,-290.81|Build/Props
Part|Part|1|78,1,1|5802.52,70.08,-292.31|Build/Props
Part|Part|1|77,20,1|5802.02,85.58,-291.31|Build/Props
Part|Part|1|77,2,1|5802.02,102.58,-292.31|Build/Props
Part|Part|1|8,1,4|5802.02,70.08,-293.31|Build/Props
Part|Part|1|9,2,5|5802.02,68.58,-293.31|Build/Props
Part|Part|1|9,1,5|5802.02,71.08,-293.31|Build/Props
Cube.019|MeshPart|1|5,38,2.39|5802.02,86.58,-294|Build/Props
Part|Part|1|25,1,1|5849.02,70.08,-277.31|Build/Props
Part|Part|1|25,2,2|5849.52,68.58,-277.31|Build/Props
Part|Part|1|19,20,1|5848.02,85.58,-274.31|Build/Props
Part|Part|1|17,3,1|5848.02,72.08,-275.31|Build/Props
Part|Part|1|19,2,3|5849.02,104.58,-274.31|Build/Props
Part|Part|1|19,4,1|5848.02,99.58,-274.31|Build/Props
Part|Part|1|19,2,2|5848.52,102.58,-274.31|Build/Props
Part|Part|1|1,31,2|5848.52,86.08,-283.31|Build/Props
Part|Part|1|25,34,1|5847.02,84.58,-277.31|Build/Props
Part|Part|1|10,2,1.1|5823.52,94.58,-291.36|Build/Props
Part|Part|1|12,1,2|5823.52,93.08,-291.81|Build/Props
Part|Part|1|12,1,2|5823.52,96.08,-291.81|Build/Props
Part|Part|1|1,2,2|5829.02,94.58,-291.81|Build/Props
Part|Part|1|1,2,2|5818.02,94.58,-291.81|Build/Props
Part|Part|1|13,2,1|5474.52,68.58,-291.31|Build/Props
Part|Part|1|13,1,1|5474.52,70.08,-291.31|Build/Props
Part|Part|1|15,2,5|5474.52,68.58,-288.31|Build/Props
Part|Part|1|15,1,5|5474.52,70.08,-288.31|Build/Props
Part|Part|1|13,6,4|5474.52,70.58,-287.81|Build/Props
Part|Part|1|5,32,4|5478.52,89.58,-287.81|Build/Props
Part|Part|1|5,32,4|5470.52,89.58,-287.81|Build/Props
Part|Part|1|3,37,3|5470.52,89.08,-289.31|Build/Props
Part|Part|1|3,37,3|5478.52,89.08,-289.31|Build/Props
Part|Part|1|15,2,13|5474.52,108.58,-284.31|Build/Props
Part|Part|1|1,4,3|5480.52,111.58,-284.31|Build/Props
Part|Part|1|21,1,1|5456.52,108.58,-286.31|Build/Props
Part|Part|1|11,4,9|5474.52,111.58,-284.31|Build/Props
Part|Part|1|13,2,11|5474.52,106.58,-284.31|Build/Props
Part|Part|1|13,2,1|5474.52,108.58,-291.31|Build/Props
Part|Part|1|9,4,1|5474.52,111.58,-289.31|Build/Props
Cube.009|MeshPart|1|12.94,45.44,12.94|5474.52,136.25,-284.81|Build/Props
Part|Part|1|15,2,5|5438.52,68.58,-288.31|Build/Props
Part|Part|1|15,1,5|5438.52,70.08,-288.31|Build/Props
Part|Part|1|13,2,1|5438.52,68.58,-291.31|Build/Props
Part|Part|1|13,6,4|5438.52,70.58,-287.81|Build/Props
Part|Part|1|13,1,1|5438.52,70.08,-291.31|Build/Props
Part|Part|1|15,2,13|5438.52,108.58,-284.31|Build/Props
Part|Part|1|11,4,9|5438.52,111.58,-284.31|Build/Props
Part|Part|1|9,4,1|5438.52,111.58,-289.31|Build/Props
Part|Part|1|1,4,3|5432.52,111.58,-284.31|Build/Props
Part|Part|1|13,2,1|5438.52,108.58,-291.31|Build/Props
Part|Part|1|13,2,11|5438.52,106.58,-284.31|Build/Props
Part|Part|1|3,37,3|5434.52,89.08,-289.31|Build/Props
Part|Part|1|5,32,4|5442.52,89.58,-287.81|Build/Props
Part|Part|1|5,32,4|5434.52,89.58,-287.81|Build/Props
Part|Part|1|3,37,3|5442.52,89.08,-289.31|Build/Props
Cube.009|MeshPart|1|12.94,45.44,12.94|5438.52,136.25,-284.81|Build/Props
Part|Part|1|49,3,1|5417.02,106.08,-286.31|Build/Props
Part|Part|1|138,2,1|5461.52,68.58,-287.31|Build/Props
Part|Part|1|52,2,2|5502.52,108.58,-285.81|Build/Props
Part|Part|1|53,2,2|5419.02,108.58,-285.81|Build/Props
Part|Part|1|50,6,1|5505.52,70.58,-286.31|Build/Props
Part|Part|1|137,1,2|5461.02,70.08,-286.81|Build/Props
Part|Part|1|49,3,1|5506.02,106.08,-286.31|Build/Props
Part|Part|1|53,40,1|5419.02,87.58,-285.31|Build/Props
Part|Part|1|50,6,1|5417.52,70.58,-286.31|Build/Props
Part|Part|1|58,40,1|5500.52,87.58,-285.31|Build/Props
Cube.017|MeshPart|1|14.48,1.28,1.47|5456.4,108.26,-286.32|Build/Props
Cube.016|MeshPart|1|10.4,29.23,1.46|5456.4,94.24,-286.32|Build/Props
Stairs1|MeshPart|1|4,6,10|5450.02,116.58,-284.81|Build/Props
Stairs1|MeshPart|1|4,6,10|5463.02,116.58,-284.81|Build/Props
Part|Part|1|3,9,4|5456.52,118.08,-284.81|Build/Props
ExtrusionWall|MeshPart|1|25,55,6|5456.52,86.08,-282.8|Build/Props
WallFacade1|MeshPart|1|49,29.07,1.07|5506.02,89.04,-286.34|Build/Props
WallFacade1|MeshPart|1|39,29.07,1.07|5412.02,89.04,-286.34|Build/Props
Part|Part|1|11,4,9|5707.52,111.58,-284.31|Build/Props
Part|Part|1|15,2,13|5707.52,108.58,-284.31|Build/Props
Part|Part|1|1,4,3|5713.52,111.58,-284.31|Build/Props
Part|Part|1|9,4,1|5707.52,111.58,-289.31|Build/Props
Part|Part|1|13,2,1|5707.52,108.58,-291.31|Build/Props
Part|Part|1|13,2,11|5707.52,106.58,-284.31|Build/Props
Part|Part|1|5,32,4|5703.52,89.58,-287.81|Build/Props
Part|Part|1|3,37,3|5703.52,89.08,-289.31|Build/Props
Part|Part|1|5,32,4|5711.52,89.58,-287.81|Build/Props
Part|Part|1|3,37,3|5711.52,89.08,-289.31|Build/Props
Cube.009|MeshPart|1|12.94,45.44,12.94|5707.52,136.25,-284.81|Build/Props
Part|Part|1|13,1,1|5707.52,70.08,-291.31|Build/Props
Part|Part|1|15,1,5|5707.52,70.08,-288.31|Build/Props
Part|Part|1|13,6,4|5707.52,70.58,-287.81|Build/Props
Part|Part|1|15,2,5|5707.52,68.58,-288.31|Build/Props
Part|Part|1|13,2,1|5707.52,68.58,-291.31|Build/Props
Cube.009|MeshPart|1|12.94,45.44,12.94|5671.52,136.25,-284.81|Build/Props
Part|Part|1|11,4,9|5671.52,111.58,-284.31|Build/Props
Part|Part|1|1,4,3|5665.52,111.58,-284.31|Build/Props
Part|Part|1|13,2,11|5671.52,106.58,-284.31|Build/Props
Part|Part|1|13,2,1|5671.52,108.58,-291.31|Build/Props
Part|Part|1|15,2,13|5671.52,108.58,-284.31|Build/Props
Part|Part|1|21,1,1|5689.52,108.58,-286.31|Build/Props
Part|Part|1|9,4,1|5671.52,111.58,-289.31|Build/Props
Part|Part|1|5,32,4|5675.52,89.58,-287.81|Build/Props
Part|Part|1|3,37,3|5667.52,89.08,-289.31|Build/Props
Part|Part|1|5,32,4|5667.52,89.58,-287.81|Build/Props
Part|Part|1|3,37,3|5675.52,89.08,-289.31|Build/Props
Part|Part|1|15,2,5|5671.52,68.58,-288.31|Build/Props
Part|Part|1|13,2,1|5671.52,68.58,-291.31|Build/Props
Part|Part|1|13,6,4|5671.52,70.58,-287.81|Build/Props
Part|Part|1|15,1,5|5671.52,70.08,-288.31|Build/Props
Part|Part|1|13,1,1|5671.52,70.08,-291.31|Build/Props
Part|Part|1|53,2,2|5727.02,108.58,-285.81|Build/Props
Part|Part|1|53,40,1|5727.02,87.58,-285.31|Build/Props
Part|Part|1|50,6,1|5728.52,70.58,-286.31|Build/Props
Part|Part|1|50,6,1|5640.52,70.58,-286.31|Build/Props
Part|Part|1|138,2,1|5684.52,68.58,-287.31|Build/Props
Part|Part|1|137,1,2|5685.02,70.08,-286.81|Build/Props
Part|Part|1|52,2,2|5643.52,108.58,-285.81|Build/Props
Part|Part|1|49,3,1|5729.02,106.08,-286.31|Build/Props
Part|Part|1|49,3,1|5640.02,106.08,-286.31|Build/Props
Part|Part|1|58,40,1|5645.52,87.58,-285.31|Build/Props
Cube.016|MeshPart|1|10.4,29.23,1.46|5689.65,94.24,-286.32|Build/Props
Cube.017|MeshPart|1|14.48,1.28,1.47|5689.65,108.26,-286.32|Build/Props
Stairs1|MeshPart|1|4,6,10|5696.02,116.58,-284.81|Build/Props
WallFacade1|MeshPart|1|39,29.07,1.07|5734.02,89.04,-286.34|Build/Props
Part|Part|1|3,9,4|5689.52,118.08,-284.81|Build/Props
ExtrusionWall|MeshPart|1|25,55,6|5689.52,86.08,-282.8|Build/Props
WallFacade1|MeshPart|1|49,29.07,1.07|5640.02,89.04,-286.34|Build/Props
Stairs1|MeshPart|1|4,6,10|5683.02,116.58,-284.81|Build/Props
Part|Part|1|37,1,1|5262.02,68.08,-283.31|Build/Props
Part|Part|1|2,1,2|5282.02,68.58,-283.31|Build/Props
Part|Part|1|1,1,36|5242.02,68.08,-302.81|Build/Props
Part|Part|1|2,1.1,2|5171.52,68.13,-322.31|Build/Props
Part|Part|1|103,1,1|5189.02,68.08,-322.31|Build/Props
Part|Part|1|2,1.1,2|5206.52,68.13,-322.31|Build/Props
Part|Part|1|1,1,26|5136.02,68.08,-307.81|Build/Props
Part|Part|1|3,1,3|5282.02,68.08,-283.31|Build/Props
Part|Part|1|2,1,2|5242.02,68.58,-283.31|Build/Props
Part|Part|1|1,1,36|5282.02,68.08,-302.81|Build/Props
Part|Part|1|7,1,53|5535.02,68.08,-285.31|Build/Props
Part|Part|1|1,1,26|5388.02,68.08,-307.81|Build/Props
Part|Part|1|3,1,3|5242.02,68.08,-283.31|Build/Props
Part|Part|1|2,1.1,2|5317.52,68.13,-322.31|Build/Props
Part|Part|1|2,1.1,2|5352.52,68.13,-322.31|Build/Props
Part|Part|1|103,1,1|5335.02,68.08,-322.31|Build/Props
Stairs1|MeshPart|1|1,8,110|5477.52,69.07,-308.81|Build/Props
Stairs1|MeshPart|1|1,8,110|5443.52,68.08,-314.81|Build/Props
Part|Part|1|7,1,53|5611.02,68.08,-285.31|Build/Props
Part|Part|1|103,1,1|5957.02,68.08,-322.31|Build/Props
Part|Part|1|69,1,7|5573.02,68.08,-262.31|Build/Props
Part|Part|1|1,1,26|6010.02,68.08,-307.81|Build/Props
Part|Part|1|2,1,2|5904.02,68.58,-283.31|Build/Props
Part|Part|1|1,1,36|5864.02,68.08,-302.81|Build/Props
Part|Part|1|2,1.1,2|5828.52,68.13,-322.31|Build/Props
Part|Part|1|2,1.1,2|5939.52,68.13,-322.31|Build/Props
Part|Part|1|2,1,2|5864.02,68.58,-283.31|Build/Props
Part|Part|1|1,1,36|5904.02,68.08,-302.81|Build/Props
Part|Part|1|2,1.1,2|5974.52,68.13,-322.31|Build/Props
Part|Part|1|3,1,3|5864.02,68.08,-283.31|Build/Props
Part|Part|1|3,1,3|5904.02,68.08,-283.31|Build/Props
Part|Part|1|1,1,26|5758.02,68.08,-307.81|Build/Props
Part|Part|1|103,1,1|5811.02,68.08,-322.31|Build/Props
Part|Part|1|37,1,1|5884.02,68.08,-283.31|Build/Props
Part|Part|1|2,1.1,2|5793.52,68.13,-322.31|Build/Props
Stairs1|MeshPart|1|1,8,110|5669.52,68.08,-307.81|Build/Props
Stairs1|MeshPart|1|1,8,110|5702.52,68.08,-314.81|Build/Props
Cube.011|MeshPart|1|15.61,35.65,15.61|5316.05,157.4,-277|Build/Props
Cube.012|MeshPart|1|19.33,39.23,19.33|5316.05,161.59,-277|Build/Props
Cube.014|MeshPart|1|19.49,68.44,19.49|5316.05,161.2,-277|Build/Props
Part|Part|1|6,30,6|5321.05,105.03,-282|Build/Props
Part|Part|1|6,30,6|5321.05,105.03,-272|Build/Props
Part|Part|1|4,33,4|5323.05,106.53,-270|Build/Props
Part|Part|1|6,30,6|5311.05,105.03,-272|Build/Props
Part|Part|1|22,2,22|5316.05,126.03,-277|Build/Props
Part|Part|1|12,30,12|5316.05,105.03,-277|Build/Props
Part|Part|1|16,3,16|5316.05,121.53,-277|Build/Props
Part|Part|1|4,33,4|5309.05,106.53,-284|Build/Props
Part|Part|1|4,33,4|5323.05,106.53,-284|Build/Props
Part|Part|1|4,33,4|5309.05,106.53,-270|Build/Props
Part|Part|1|6,30,6|5311.05,105.03,-282|Build/Props
Part|Part|1|18,2,18|5316.05,124.03,-277|Build/Props
Cube.011|MeshPart|1|15.61,35.65,15.61|5943.05,157.4,-271|Build/Props
Cube.012|MeshPart|1|19.33,39.23,19.33|5943.05,161.59,-271|Build/Props
Cube.014|MeshPart|1|19.49,68.44,19.49|5943.05,161.2,-271|Build/Props
Part|Part|1|4,33,4|5936.05,106.53,-264|Build/Props
Part|Part|1|6,30,6|5948.05,105.03,-266|Build/Props
Part|Part|1|4,33,4|5936.05,106.53,-278|Build/Props
Part|Part|1|12,30,12|5943.05,105.03,-271|Build/Props
Part|Part|1|6,30,6|5938.05,105.03,-276|Build/Props
Part|Part|1|22,2,22|5943.05,126.03,-271|Build/Props
Part|Part|1|6,30,6|5938.05,105.03,-266|Build/Props
Part|Part|1|6,30,6|5948.05,105.03,-276|Build/Props
Part|Part|1|18,2,18|5943.05,124.03,-271|Build/Props
Part|Part|1|4,33,4|5950.05,106.53,-264|Build/Props
Part|Part|1|4,33,4|5950.05,106.53,-278|Build/Props
Part|Part|1|16,3,16|5943.05,121.53,-271|Build/Props
Cube.012|MeshPart|1|19.33,39.23,19.33|5830,161.59,-277|Build/Props
Cube.011|MeshPart|1|15.61,35.65,15.61|5830,157.4,-277|Build/Props
Cube.014|MeshPart|1|19.49,68.44,19.49|5830,161.2,-277|Build/Props
Part|Part|1|6,30,6|5835,105.03,-282|Build/Props
Part|Part|1|4,33,4|5823,106.53,-284|Build/Props
Part|Part|1|4,33,4|5837,106.53,-284|Build/Props
Part|Part|1|6,30,6|5835,105.03,-272|Build/Props
Part|Part|1|22,2,22|5830,126.03,-277|Build/Props
Part|Part|1|12,30,12|5830,105.03,-277|Build/Props
Part|Part|1|6,30,6|5825,105.03,-272|Build/Props
Part|Part|1|4,33,4|5837,106.53,-270|Build/Props
Part|Part|1|6,30,6|5825,105.03,-282|Build/Props
Part|Part|1|16,3,16|5830,121.53,-277|Build/Props
Part|Part|1|4,33,4|5823,106.53,-270|Build/Props
Part|Part|1|18,2,18|5830,124.03,-277|Build/Props
Cube.011|MeshPart|1|15.61,35.65,15.61|5203,157.4,-271|Build/Props
Cube.012|MeshPart|1|19.33,39.23,19.33|5203,161.59,-271|Build/Props
Cube.014|MeshPart|1|19.49,68.44,19.49|5203,161.2,-271|Build/Props
Part|Part|1|4,33,4|5210,106.53,-264|Build/Props
Part|Part|1|4,33,4|5210,106.53,-278|Build/Props
Part|Part|1|4,33,4|5196,106.53,-278|Build/Props
Part|Part|1|6,30,6|5208,105.03,-276|Build/Props
Part|Part|1|4,33,4|5196,106.53,-264|Build/Props
Part|Part|1|6,30,6|5208,105.03,-266|Build/Props
Part|Part|1|12,30,12|5203,105.03,-271|Build/Props
Part|Part|1|18,2,18|5203,124.03,-271|Build/Props
Part|Part|1|16,3,16|5203,121.53,-271|Build/Props
Part|Part|1|6,30,6|5198,105.03,-266|Build/Props
Part|Part|1|6,30,6|5198,105.03,-276|Build/Props
Part|Part|1|22,2,22|5203,126.03,-271|Build/Props
Cylinder.002|MeshPart|1|6.77,6.87,1.64|5439.16,154.46,-283.95|Build/Props
Cylinder|MeshPart|1|2.08,48.49,2.08|5450.15,140.44,-264.91|Build/Props
Cylinder|MeshPart|1|2.08,48.49,2.08|5486.58,140.44,-263.71|Build/Props
Cylinder.002|MeshPart|1|6.77,6.87,1.64|5475.6,154.46,-282.74|Build/Props
Cylinder|MeshPart|1|2.08,48.49,2.08|5659.46,140.44,-263.71|Build/Props
Cylinder.002|MeshPart|1|6.77,6.87,1.64|5670.45,154.46,-282.74|Build/Props
Cylinder|MeshPart|1|2.08,48.49,2.08|5695.9,140.44,-264.91|Build/Props
Cylinder.002|MeshPart|1|6.77,6.87,1.64|5706.89,154.46,-283.95|Build/Props
Cylinder.002|MeshPart|1|6.77,6.87,1.64|5212.75,100.14,-293.54|Build/Props
Cylinder|MeshPart|1|2.08,48.49,2.08|5212.74,74.07,-293.54|Build/Props
Cylinder|MeshPart|1|2.08,48.49,2.08|5932.56,79.33,-293.84|Build/Props
Cylinder|MeshPart|1|2.08,48.49,2.08|5501.56,83.98,-292.62|Build/Props
Meshes/untitled_Cylinder.023 (1)|MeshPart|1|197.54,118.11,774.63|5602.84,260.48,-264.86|Build/Props
Clouds1.001|MeshPart|1|812.55,345.94,378.89|5556.19,312.6,-35.57|Build/Props
Part|Part|1|4,14.99,1.33|5647.66,128.74,-269.33|Build/Props
Part|Part|1|1.33,14.99,4|5637,128.74,-258.67|Build/Props
Part|Part|1|4,14.99,1.33|5647.66,128.74,-256|Build/Props
Part|Part|1|4,14.99,1.33|5639.67,128.74,-256|Build/Props
Part|Part|1|4,14.99,1.33|5639.67,128.74,-269.33|Build/Props
Part|Part|1|12,17.66,12|5643.66,127.4,-262.66|Build/Props
Part|Part|1|1.33,14.99,4|5650.33,128.74,-258.67|Build/Props
Part|Part|1|1.33,14.99,4|5650.33,128.74,-266.66|Build/Props
Part|Part|1|1.33,14.99,4|5637,128.74,-266.66|Build/Props
Part|Part|1|6.66,8.67,12|5643.66,145.9,-262.66|Build/Props
Part|Part|1|14.66,2.67,12|5643.66,137.56,-262.66|Build/Props
Part|Part|1|12,7.67,6.66|5643.66,145.4,-262.66|Build/Props
Part|Part|1|17.33,2.67,14.66|5643.66,140.23,-262.66|Build/Props
Part|Part|1|12,2.67,14.66|5643.66,137.56,-262.66|Build/Props
Part|Part|1|14.66,2.67,17.33|5643.66,140.23,-262.66|Build/Props
Part|Part|1|17.33,1.33,14.66|5643.66,113.91,-262.66|Build/Props
Part|Part|1|17.33,50.67,14.66|5643.66,87.91,-262.66|Build/Props
Part|Part|1|14.66,1.33,17.33|5643.66,113.91,-262.66|Build/Props
Part|Part|1|12,8,14.66|5643.66,114.58,-262.66|Build/Props
Part|Part|1|14.66,50.67,17.33|5643.66,87.91,-262.66|Build/Props
Part|Part|1|14.66,8,12|5643.66,114.58,-262.66|Build/Props
Cube.030|MeshPart|1|64.86,41.04,16.12|5643.17,168.2,-263.53|Build/Props
Cube.025|MeshPart|1|19.83,35.18,13.19|5643.17,168.2,-263.53|Build/Props
Cube.033|MeshPart|1|66.41,28.6,9.7|5641.98,179.43,-265.59|Build/Props
Part|Part|1|11,1,13|5611.02,70.08,-281.31|Build/Props
Part|Part|1|11,2,13|5611.02,68.58,-281.31|Build/Props
Part|Part|1|13,2,11|5611.02,68.58,-281.31|Build/Props
Part|Part|1|13,1,11|5611.02,70.08,-281.31|Build/Props
Part|Part|1|11,6,9|5611.02,70.58,-281.31|Build/Props
Part|Part|1|9,6,11|5611.02,70.58,-281.31|Build/Props
Part|Part|1|1,30,3|5606.02,90.58,-284.31|Build/Props
Part|Part|1|3,30,1|5614.02,90.58,-276.31|Build/Props
Part|Part|1|3,30,1|5608.02,90.58,-276.31|Build/Props
Part|Part|1|1,30,3|5606.02,90.58,-278.31|Build/Props
Part|Part|1|1,30,3|5616.02,90.58,-278.31|Build/Props
Part|Part|1|9,32,9|5611.02,89.58,-281.31|Build/Props
Part|Part|1|1,30,3|5616.02,90.58,-284.31|Build/Props
Part|Part|1|3,30,1|5614.02,90.58,-286.31|Build/Props
Part|Part|1|3,30,1|5608.02,90.58,-286.31|Build/Props
Part|Part|1|9,2,5|5611.02,110.58,-281.31|Build/Props
Part|Part|1|13,2,11|5611.02,108.58,-281.31|Build/Props
Part|Part|1|11,2,13|5611.02,108.58,-281.31|Build/Props
Part|Part|1|11,2,9|5611.02,106.58,-281.31|Build/Props
Part|Part|1|5,2,9|5611.02,110.58,-281.31|Build/Props
Part|Part|1|9,2,11|5611.02,106.58,-281.31|Build/Props
Part|Part|1|14.66,8,12|5502.38,114.58,-262.66|Build/Props
Part|Part|1|12,8,14.66|5502.38,114.58,-262.66|Build/Props
Part|Part|1|14.66,50.67,17.33|5502.38,87.91,-262.66|Build/Props
Part|Part|1|14.66,1.33,17.33|5502.38,113.91,-262.66|Build/Props
Part|Part|1|17.33,50.67,14.66|5502.38,87.91,-262.66|Build/Props
Part|Part|1|17.33,1.33,14.66|5502.38,113.91,-262.66|Build/Props
Part|Part|1|4,14.99,1.33|5498.39,128.74,-256|Build/Props
Part|Part|1|1.33,14.99,4|5495.72,128.74,-258.67|Build/Props
Part|Part|1|1.33,14.99,4|5509.05,128.74,-266.66|Build/Props
Part|Part|1|1.33,14.99,4|5509.05,128.74,-258.67|Build/Props
Part|Part|1|4,14.99,1.33|5506.38,128.74,-256|Build/Props
Part|Part|1|4,14.99,1.33|5506.38,128.74,-269.33|Build/Props
Part|Part|1|1.33,14.99,4|5495.72,128.74,-266.66|Build/Props
Part|Part|1|4,14.99,1.33|5498.39,128.74,-269.33|Build/Props
Part|Part|1|12,17.66,12|5502.38,127.4,-262.66|Build/Props
Part|Part|1|17.33,2.67,14.66|5502.38,140.23,-262.66|Build/Props
Part|Part|1|6.66,8.67,12|5502.38,145.9,-262.66|Build/Props
Part|Part|1|12,7.67,6.66|5502.38,145.4,-262.66|Build/Props
Part|Part|1|12,2.67,14.66|5502.38,137.56,-262.66|Build/Props
Part|Part|1|14.66,2.67,17.33|5502.38,140.23,-262.66|Build/Props
Part|Part|1|14.66,2.67,12|5502.38,137.56,-262.66|Build/Props
Cube.030|MeshPart|1|64.86,41.04,16.12|5502.88,168.2,-263.53|Build/Props
Cube.025|MeshPart|1|19.83,35.18,13.19|5502.88,168.2,-263.53|Build/Props
Cube.033|MeshPart|1|66.41,28.6,9.7|5504.07,179.43,-265.59|Build/Props
Part|Part|1|14.66,1.33,17.33|5261.66,113.91,-246.66|Build/Props
Part|Part|1|17.33,1.33,14.66|5261.66,113.91,-246.66|Build/Props
Part|Part|1|17.33,50.67,14.66|5261.66,87.91,-246.66|Build/Props
Part|Part|1|12,8,14.66|5261.66,114.58,-246.66|Build/Props
Part|Part|1|14.66,8,12|5261.66,114.58,-246.66|Build/Props
Part|Part|1|14.66,50.67,17.33|5261.66,87.91,-246.66|Build/Props
Cube.025|MeshPart|1|28.05,49.75,18.66|5261.67,141.66,-246.66|Build/Props
Cube.030|MeshPart|1|91.73,58.04,22.8|5261.67,141.66,-246.66|Build/Props
Cube.033|MeshPart|1|93.92,40.45,13.72|5261.67,157.55,-250.02|Build/Props
Part|Part|1|14.66,8,12|5884.38,114.58,-246.66|Build/Props
Part|Part|1|17.33,1.33,14.66|5884.38,113.91,-246.66|Build/Props
Part|Part|1|12,8,14.66|5884.38,114.58,-246.66|Build/Props
Part|Part|1|14.66,1.33,17.33|5884.38,113.91,-246.66|Build/Props
Part|Part|1|17.33,50.67,14.66|5884.38,87.91,-246.66|Build/Props
Part|Part|1|14.66,50.67,17.33|5884.38,87.91,-246.66|Build/Props
Cube.025|MeshPart|1|28.05,49.75,18.66|5884.38,141.66,-246.66|Build/Props
Cube.030|MeshPart|1|91.73,58.04,22.8|5884.38,141.66,-246.66|Build/Props
Cube.033|MeshPart|1|93.92,40.45,13.72|5884.38,157.55,-250.02|Build/Props
Part|Part|1|3,30,1|5532.02,90.58,-286.31|Build/Props
Part|Part|1|1,30,3|5530.02,90.58,-284.31|Build/Props
Part|Part|1|3,30,1|5538.02,90.58,-276.31|Build/Props
Part|Part|1|3,30,1|5532.02,90.58,-276.31|Build/Props
Part|Part|1|3,30,1|5538.02,90.58,-286.31|Build/Props
Part|Part|1|1,30,3|5540.02,90.58,-284.31|Build/Props
Part|Part|1|1,30,3|5540.02,90.58,-278.31|Build/Props
Part|Part|1|9,32,9|5535.02,89.58,-281.31|Build/Props
Part|Part|1|1,30,3|5530.02,90.58,-278.31|Build/Props
Part|Part|1|11,1,13|5535.02,70.08,-281.31|Build/Props
Part|Part|1|9,6,11|5535.02,70.58,-281.31|Build/Props
Part|Part|1|13,1,11|5535.02,70.08,-281.31|Build/Props
Part|Part|1|11,6,9|5535.02,70.58,-281.31|Build/Props
Part|Part|1|13,2,11|5535.02,68.58,-281.31|Build/Props
Part|Part|1|11,2,13|5535.02,68.58,-281.31|Build/Props
Part|Part|1|9,2,5|5535.02,110.58,-281.31|Build/Props
Part|Part|1|9,2,11|5535.02,106.58,-281.31|Build/Props
Part|Part|1|5,2,9|5535.02,110.58,-281.31|Build/Props
Part|Part|1|11,2,9|5535.02,106.58,-281.31|Build/Props
Part|Part|1|11,2,13|5535.02,108.58,-281.31|Build/Props
Part|Part|1|13,2,11|5535.02,108.58,-281.31|Build/Props
Part|Part|1|2,2,2|5273.52,100.58,-266.81|Build/Props
Part|Part|1|22,2,1.1|5261.52,100.58,-266.36|Build/Props
Part|Part|1|2,2,2|5249.52,100.58,-266.81|Build/Props
Part|Part|1|26,2,1|5261.52,98.58,-267.31|Build/Props
Part|Part|1|71,2,1|5261.02,102.58,-267.31|Build/Props
Part|Part|1|72,20,1|5261.52,85.58,-266.31|Build/Props
Part|Part|1|72,7,1|5261.52,101.08,-266.31|Build/Props
Part|Part|1|78,1,1|5264.52,70.08,-267.31|Build/Props
Part|Part|1|77,6,2|5264.02,70.58,-265.81|Build/Props
Part|Part|1|74,32,2|5261.52,85.58,-264.81|Build/Props
Part|Part|1|70,2,5|5260.52,104.58,-266.31|Build/Props
Part|Part|1|78,2,2|5264.52,68.58,-266.81|Build/Props
Part|Part|1|2,2,2|5896.52,100.58,-266.81|Build/Props
Part|Part|1|22,2,1.1|5884.52,100.58,-266.36|Build/Props
Part|Part|1|2,2,2|5872.52,100.58,-266.81|Build/Props
Part|Part|1|26,2,1|5884.52,98.58,-267.31|Build/Props
Part|Part|1|72,20,1|5884.52,85.58,-266.31|Build/Props
Part|Part|1|78,2,2|5881.52,68.58,-266.81|Build/Props
Part|Part|1|71,2,1|5885.02,102.58,-267.31|Build/Props
Part|Part|1|74,32,2|5884.52,85.58,-264.81|Build/Props
Part|Part|1|70,2,5|5885.52,104.58,-266.31|Build/Props
Part|Part|1|78,1,1|5881.52,70.08,-267.31|Build/Props
Part|Part|1|72,7,1|5884.52,101.08,-266.31|Build/Props
Part|Part|1|77,6,2|5882.02,70.58,-265.81|Build/Props
Lava|MeshPart|1|873,0.5,90|5573.02,67.83,-276.8|Build/Props
Lavafalls|MeshPart|1|885,108.64,30.81|5573.02,121.9,-279.4|Build/Props
Floor|MeshPart|1|916,34.75,117.17|5588.52,50.2,-319.39|Build/Props
Floor|MeshPart|1|916,0.85,34.2|5588.52,66.53,-360.87|Build/Props
Cube.018|MeshPart|1|9.33,34.53,9.33|5413.34,119.84,-273.66|Build/Props
Cube.018|MeshPart|1|9.33,34.53,9.33|5782.95,153.84,-245.59|Build/Props
Cube.018|MeshPart|1|9.33,34.53,9.33|5157.34,119.84,-284.66|Build/Props
Cube.018|MeshPart|1|9.33,34.53,9.33|5996.65,143.84,-259.35|Build/Props
Cube.017|MeshPart|1|12.14,1.07,1.24|5945.05,101.14,-292.13|Build/Props
Cube.016|MeshPart|1|8.72,24.51,1.22|5945.05,89.38,-292.13|Build/Props
Cube.017|MeshPart|1|12.14,1.07,1.24|5364.05,101.14,-292.13|Build/Props
Cube.016|MeshPart|1|8.72,24.51,1.22|5364.05,89.38,-292.13|Build/Props
Cube.016|MeshPart|1|8.72,24.51,1.22|5781.05,89.38,-292.13|Build/Props
Cube.017|MeshPart|1|12.14,1.07,1.24|5781.05,101.14,-292.13|Build/Props
Cube.017|MeshPart|1|12.14,1.07,1.24|5200.05,101.14,-292.13|Build/Props
Cube.016|MeshPart|1|8.72,24.51,1.22|5200.05,89.38,-292.13|Build/Props
Cube.016|MeshPart|1|10.98,30.88,1.54|6015.96,134.15,-306.64|Build/Props
Cube.017|MeshPart|1|15.29,1.35,1.56|6015.96,148.96,-306.64|Build/Props
RockPile2|MeshPart|1|18.42,2.24,13.79|5198.68,68.72,-416.78|Build/Props
RockPile2|MeshPart|1|19.92,2.24,17.79|5323.74,68.72,-429.08|Build/Props
RockPile1|MeshPart|1|20.23,2.92,21.32|5529.12,69.04,-436.66|Build/Props
RockPile1|MeshPart|1|20.23,2.92,21.32|5732.88,69.04,-440.34|Build/Props
Cube.001|MeshPart|1|13.72,26.64,1.4|5822.55,88.47,-436.51|Build/Props
Cube|MeshPart|1|9.85,26.25,1.38|5822.55,88.62,-436.51|Build/Props
Cube.001|MeshPart|1|13.72,26.64,1.4|5159.05,88.47,-436.51|Build/Props
Cube|MeshPart|1|9.85,26.25,1.38|5159.05,88.62,-436.51|Build/Props
Cube.001|MeshPart|1|13.72,26.64,1.4|5986.55,88.47,-436.51|Build/Props
Cube|MeshPart|1|9.85,26.25,1.38|5986.55,88.62,-436.51|Build/Props
Cube.001|MeshPart|1|13.72,26.64,1.4|5323.55,88.47,-436.51|Build/Props
Cube|MeshPart|1|9.85,26.25,1.38|5323.55,88.62,-436.51|Build/Props
Floor|MeshPart|1|916,0.85,34.05|5588.52,66.53,-364.69|Build/Props
Waterfalls|MeshPart|1|885,108.64,30.81|5573.02,121.9,-449.02|Build/Props
Water|MeshPart|1|873,0.5,55|5573.02,67.82,-434.12|Build/Props
Floor|MeshPart|1|916,34.75,119.14|5588.52,50.2,-407.24|Build/Props
Bush2|MeshPart|1|5.31,2.04,5.05|5811.33,69.6,-409.62|Build/Props
Bush1|MeshPart|1|5.82,2.4,4.63|5141.68,69.78,-412.91|Build/Props
Bush2|MeshPart|1|6.46,2.1,5.19|5308.9,70.13,-430.77|Build/Props
Bush1|MeshPart|1|7.61,3.04,5.76|5344.8,69.6,-405.62|Build/Props
Bush1|MeshPart|1|7.61,3.04,5.76|5651.66,70.6,-438.12|Build/Props
Part|Part|1|3,5,3|5758.02,112.08,-439.3|Build/Props
Part|Part|1|2.05,5.86,2.05|5758.12,115.33,-439.2|Build/Props
Fern1|MeshPart|1|25.72,6.72,22.28|5758.04,120.55,-439.27|Build/Props
Part|Part|1|3.32,2.34,3.32|5758.42,119.67,-439.38|Build/Props
Part|Part|1|2.64,3.84,2.64|5758.42,119.67,-439.38|Build/Props
Part|Part|1|3,5,3|5846.02,112.08,-439.3|Build/Props
Fern1|MeshPart|1|25.72,6.72,22.28|5846.04,120.55,-439.27|Build/Props
Part|Part|1|2.05,5.86,2.05|5846.12,115.33,-439.2|Build/Props
Part|Part|1|3.32,2.34,3.32|5846.42,119.67,-439.38|Build/Props
Part|Part|1|2.64,3.84,2.64|5846.42,119.67,-439.38|Build/Props
Part|Part|1|2.64,3.84,2.64|6010.42,119.67,-439.38|Build/Props
Part|Part|1|2.05,5.86,2.05|6010.12,115.33,-439.2|Build/Props
Part|Part|1|3.32,2.34,3.32|6010.42,119.67,-439.38|Build/Props
Fern1|MeshPart|1|25.72,6.72,22.28|6010.04,120.55,-439.27|Build/Props
Part|Part|1|3,5,3|6010.02,112.08,-439.3|Build/Props
Fern1|MeshPart|1|25.72,6.72,22.28|5236.7,83.61,-452.23|Build/Props
Part|Part|1|2.54,5.77,2.54|5234.07,73.6,-454.87|Build/Props
Part|Part|1|2.05,5.86,2.05|5234.84,78.4,-453.68|Build/Props
Part|Part|1|3,4,3|5233.81,69.58,-455.25|Build/Props
Part|Part|1|2.64,3.84,2.64|5235.95,82.43,-452.44|Build/Props
Part|Part|1|3.32,2.34,3.32|5235.95,82.43,-452.44|Build/Props
Part|Part|1|3,5,3|5136.02,114.08,-439.31|Build/Props
Part|Part|1|2.64,3.84,2.64|5136.09,121.67,-438.91|Build/Props
Fern1|MeshPart|1|25.72,6.72,22.28|5135.99,122.55,-439.29|Build/Props
Part|Part|1|3.32,2.34,3.32|5136.09,121.67,-438.91|Build/Props
Part|Part|1|2.05,5.86,2.05|5135.91,117.33,-439.21|Build/Props
Fern1|MeshPart|1|25.72,6.72,22.28|5535.09,120.41,-439.73|Build/Props
Part|Part|1|3,5,3|5535.02,112.08,-439.31|Build/Props
Part|Part|1|3.32,2.34,3.32|5534.95,119.67,-439.7|Build/Props
Part|Part|1|2.05,5.86,2.05|5535.13,115.33,-439.4|Build/Props
Part|Part|1|2.64,3.84,2.64|5534.95,119.67,-439.7|Build/Props
Part|Part|1|2.05,5.86,2.05|5388.12,115.33,-439.2|Build/Props
Fern1|MeshPart|1|25.72,6.72,22.28|5388.04,120.55,-439.27|Build/Props
Part|Part|1|3,5,3|5388.02,112.08,-439.3|Build/Props
Part|Part|1|3.32,2.34,3.32|5388.42,119.67,-439.38|Build/Props
Part|Part|1|2.64,3.84,2.64|5388.42,119.67,-439.38|Build/Props
Part|Part|1|3.32,2.34,3.32|5300.42,112.67,-439.38|Build/Props
Fern1|MeshPart|1|25.72,6.72,22.28|5300.04,113.55,-439.27|Build/Props
Part|Part|1|2.64,3.84,2.64|5300.42,112.67,-439.38|Build/Props
Part|Part|1|3.32,2.34,3.32|5224.42,119.67,-439.38|Build/Props
Part|Part|1|3,5,3|5224.02,112.08,-439.3|Build/Props
Part|Part|1|2.64,3.84,2.64|5224.42,119.67,-439.38|Build/Props
Part|Part|1|2.05,5.86,2.05|5224.12,115.33,-439.2|Build/Props
Fern1|MeshPart|1|25.72,6.72,22.28|5224.04,120.55,-439.27|Build/Props
Fern1|MeshPart|1|25.72,6.72,22.28|5921.99,122.55,-439.29|Build/Props
Part|Part|1|3,5,3|5922.02,114.08,-439.31|Build/Props
Part|Part|1|2.05,5.86,2.05|5921.91,117.33,-439.21|Build/Props
Part|Part|1|2.64,3.84,2.64|5922.09,121.67,-438.91|Build/Props
Part|Part|1|3.32,2.34,3.32|5922.09,121.67,-438.91|Build/Props
Part|Part|1|83,1,35|5954.83,124.08,-498.97|Build/Props
Part|Part|1|44,1,69|5498.16,158.08,-538.89|Build/Props
Part|Part|1|64,1,35|5828.4,127.08,-504.66|Build/Props
Part|Part|1|40,1,41|5628,126.08,-463.5|Build/Props
Part|Part|1|83,1,35|6007.13,114.08,-467.82|Build/Props
Part|Part|1|78,1,41|5476.58,134.08,-479.26|Build/Props
Part|Part|1|83,1,35|5882.5,115.08,-495.5|Build/Props
Part|Part|1|54,1,41|5156.47,117.08,-472.59|Build/Props
Part|Part|1|47,1,37|5739.37,127.08,-467.77|Build/Props
Part|Part|1|90,1,56|5684.27,138.08,-484.82|Build/Props
Part|Part|1|50,1,41|5279.88,107.08,-495.4|Build/Props
Part|Part|1|78,1,69|5452.15,141.08,-520.02|Build/Props
Part|Part|1|56,1,41|5367.98,121.08,-467.41|Build/Props
Part|Part|1|67,1,41|5186.93,126.08,-499.45|Build/Props
Part|Part|1|65,1,51|5785.43,119.08,-476.76|Build/Props
Part|Part|1|65,1,41|5409.35,127.08,-484.12|Build/Props
Part|Part|1|50,1,41|5212.16,112.08,-490.73|Build/Props
Part|Part|1|78,1,69|5652.79,158.08,-523.17|Build/Props
Part|Part|1|90,80.3,56|5684.27,97.43,-484.82|Build/Props
Part|Part|1|83,65.5,35|5954.83,90.83,-498.97|Build/Props
Part|Part|1|78,36,41|5476.58,115.58,-479.26|Build/Props
Part|Part|1|44,71,69|5498.16,122.08,-538.89|Build/Props
Part|Part|1|54,19,41|5156.47,107.08,-472.59|Build/Props
Part|Part|1|67,28,41|5186.93,111.58,-499.45|Build/Props
Part|Part|1|78,80,69|5452.15,100.58,-520.02|Build/Props
Part|Part|1|50,44,41|5212.16,89.58,-490.73|Build/Props
Part|Part|1|50,39,41|5279.88,87.08,-495.4|Build/Props
Part|Part|1|64,67.3,35|5828.4,92.93,-504.66|Build/Props
Part|Part|1|83,54.6,35|6007.13,86.28,-467.82|Build/Props
Part|Part|1|83,55.9,35|5882.5,86.63,-495.5|Build/Props
Part|Part|1|47,69.3,37|5739.37,91.93,-467.77|Build/Props
Part|Part|1|65,57,41|5409.35,98.08,-484.12|Build/Props
Part|Part|1|78,36,69|5652.79,139.58,-523.17|Build/Props
Part|Part|1|40,58,41|5628,96.58,-463.5|Build/Props
Part|Part|1|56,40,41|5367.98,100.58,-467.41|Build/Props
Part|Part|1|65,61.4,51|5785.43,87.88,-476.76|Build/Props
Part|Part|1|4,0.5,11|5901.52,67.83,-408.31|Build/Props
Part|Part|1|26,0.5,2|5969.52,67.83,-404.81|Build/Props
Part|Part|1|22,0.5,6|5998.52,68.33,-426.62|Build/Props
Part|Part|1|23,0.5,18|5845.02,68.33,-440.62|Build/Props
Part|Part|1|14,0.5,3|5144.52,68.33,-409.12|Build/Props
Part|Part|1|13,0.5,9|5395.02,68.83,-422.12|Build/Props
Part|Part|1|9,0.5,8|5142.02,68.33,-414.62|Build/Props
Part|Part|1|21,0.5,3|5367.02,68.83,-408.12|Build/Props
Part|Part|1|17,0.5,6|5348.02,68.83,-409.62|Build/Props
Part|Part|1|8,0.5,6|5430.52,68.83,-438.62|Build/Props
Part|Part|1|7,0.5,6|5238.02,68.33,-413.62|Build/Props
Part|Part|1|10,0.5,6|5763.52,68.33,-409.62|Build/Props
Part|Part|1|16,0.5,9|5651.52,68.83,-438.12|Build/Props
Part|Part|1|10,0.5,2|5145.52,67.83,-401.62|Build/Props
Part|Part|1|3,0.5,13|5280.02,67.83,-438.12|Build/Props
Part|Part|1|7,0.5,17|5141.02,68.33,-427.12|Build/Props
Part|Part|1|14,0.5,2|5332.52,68.83,-407.62|Build/Props
Part|Part|1|10,0.5,9|5221.52,68.33,-424.12|Build/Props
Part|Part|1|10,0.5,9|5241.52,68.83,-459.12|Build/Props
Part|Part|1|8,0.5,4|5639.52,68.83,-438.62|Build/Props
Part|Part|1|10,0.5,2|5842.52,67.83,-404.81|Build/Props
Part|Part|1|12,0.5,2|5809.52,68.33,-414.62|Build/Props
Part|Part|1|18,0.5,3|5145.52,67.83,-404.12|Build/Props
Part|Part|1|23,0.5,4|5807.02,68.33,-411.62|Build/Props
Part|Part|1|14,0.5,17|5854.52,68.33,-458.12|Build/Props
Part|Part|1|8,0.5,2|5918.52,67.83,-404.81|Build/Props
Part|Part|1|46,0.5,3|5809.52,68.33,-408.12|Build/Props
Part|Part|1|15,0.5,13|5750.02,67.83,-408.31|Build/Props
Part|Part|1|10,0.5,10|5752.52,68.83,-422.62|Build/Props
Part|Part|1|5,0.5,8|6007.02,68.33,-414.62|Build/Props
Part|Part|1|26,0.5,9|5219.52,68.33,-433.12|Build/Props
Part|Part|1|4.5,0.5,4|5298.27,68.83,-431.62|Build/Props
Part|Part|1|15,0.5,5|5872.02,67.83,-439.31|Build/Props
Part|Part|1|9,0.5,6|5681.02,67.83,-413.81|Build/Props
Part|Part|1|73,0.5,2|5342.02,67.83,-404.62|Build/Props
Part|Part|1|13,0.5,2|5741.02,68.83,-418.62|Build/Props
Part|Part|1|26,0.5,2|5342.52,67.83,-398.62|Build/Props
Part|Part|1|5,0.5,9|5867.02,67.83,-432.31|Build/Props
Part|Part|1|24,0.5,5|5647.52,67.83,-414.31|Build/Props
Part|Part|1|13,0.5,9|5441.02,68.83,-437.12|Build/Props
Part|Part|1|17,0.5,2|5187.02,68.83,-413.62|Build/Props
Part|Part|1|6,0.5,2|5154.52,68.33,-408.62|Build/Props
Part|Part|1|33,0.5,17|5993.02,68.33,-438.12|Build/Props
Part|Part|1|27,0.5,6|5182.02,68.83,-409.62|Build/Props
Part|Part|1|7,0.5,5|5213.02,68.33,-426.12|Build/Props
Part|Part|1|6,0.5,9|5761.52,68.33,-417.12|Build/Props
Part|Part|1|28,0.5,7|5438,67.83,-412|Build/Props
Part|Part|1|2,0.5,13|5902.52,67.83,-420.31|Build/Props
Part|Part|1|17,0.5,4|5233.02,68.33,-408.62|Build/Props
Part|Part|1|13,0.5,5|6003.02,68.33,-421.12|Build/Props
Part|Part|1|3,0.5,11|5240.02,68.33,-422.12|Build/Props
Part|Part|1|13,0.5,17|5307.02,68.83,-430.12|Build/Props
Part|Part|1|27,0.5,4|5465.5,67.83,-413.5|Build/Props
Part|Part|1|18,0.5,5|5818.52,67.83,-403.31|Build/Props
Part|Part|1|2,0.5,14|5865.52,67.83,-420.81|Build/Props
Part|Part|1|11,0.5,5|5176.02,68.33,-433.12|Build/Props
Part|Part|1|11,0.5,12|5241.02,67.83,-409.62|Build/Props
Part|Part|1|8,0.5,2|5782.52,68.33,-407.62|Build/Props
Part|Part|1|17,0.5,7|5668.02,67.83,-413.31|Build/Props
Part|Part|1|14,0.5,3|5202.52,68.83,-409.12|Build/Props
Part|Part|1|18,0.5,8|5733.52,67.83,-410.81|Build/Props
Part|Part|1|12,0.5,3|5763.52,67.83,-404.31|Build/Props
Part|Part|1|25,0.5,3|5877.02,67.83,-443.31|Build/Props
Part|Part|1|15,0.5,1|5971.02,67.83,-403.31|Build/Props
Part|Part|1|11,0.5,3|5909.02,67.83,-404.31|Build/Props
Part|Part|1|45,0.5,4|5347.02,67.83,-401.62|Build/Props
Part|Part|1|7,0.5,6|5275.02,67.83,-441.62|Build/Props
Part|Part|1|8,0.5,15|5232.52,68.83,-456.12|Build/Props
Part|Part|1|3,0.5,8|5244.02,67.83,-419.62|Build/Props
Part|Part|1|9,0.5,4|5406.02,68.83,-419.62|Build/Props
Part|Part|1|14,1,4|5395.52,68.08,-425.62|Build/Props
Part|Part|1|22,1,5|5369.52,68.08,-409.12|Build/Props
Part|Part|1|21,1,8|5348.02,68.08,-410.62|Build/Props
Part|Part|1|14,1,3|5330.52,68.08,-408.12|Build/Props
Part|Part|1|9,1,7|5429.02,68.08,-438.12|Build/Props
Part|Part|1|26,1,4|5744.52,68.08,-419.62|Build/Props
Part|Part|1|13,1,8|5751.02,68.08,-425.62|Build/Props
Part|Part|1|11,1,7|5171.02,68.08,-411.12|Build/Props
Part|Part|1|23,1,12|5238.02,68.08,-458.62|Build/Props
Part|Part|1|35,1,7|5650.02,68.08,-438.12|Build/Props
Part|Part|1|13,1,9|5233.02,68.08,-448.12|Build/Props
Part|Part|1|30,1,9|5305.52,68.08,-433.12|Build/Props
Part|Part|1|21,1,4|5651.02,68.08,-432.62|Build/Props
Part|Part|1|21,1,9|5306.02,68.08,-424.12|Build/Props
Part|Part|1|13,1,4|5205.02,68.08,-409.62|Build/Props
Part|Part|1|22,1,9|5187.52,68.08,-412.12|Build/Props
Part|Part|1|24,1,6|5400.52,68.08,-420.62|Build/Props
Part|Part|1|16,1,10|5441.52,68.08,-436.62|Build/Props
Meshes/untitled_Cylinder (1)|MeshPart|1|3.92,0.22,3.92|5677.5,68.19,-432.79|Build/Props
Meshes/untitled_Cylinder (1)|MeshPart|1|3.92,0.22,3.92|5740.5,68.19,-425.21|Build/Props
Meshes/untitled_Cylinder (1)|MeshPart|1|8.43,0.15,8.43|5821.64,68.15,-428.36|Build/Props
Meshes/untitled_Cylinder (1)|MeshPart|1|8.79,0.19,8.79|5428.11,68.17,-428|Build/Props
Meshes/untitled_Cylinder (1)|MeshPart|1|3.19,0.14,3.19|5292.32,68.15,-418.08|Build/Props
Meshes/untitled_Cylinder (1)|MeshPart|1|5.22,0.23,5.22|5297.89,68.19,-415.11|Build/Props
Meshes/untitled_Cylinder (1)|MeshPart|1|6.14,0.19,6.14|5516.09,68.17,-434.89|Build/Props
Meshes/untitled_Cylinder (1)|MeshPart|1|6.14,0.19,6.14|5683.11,68.17,-434.11|Build/Props
Stairs1|MeshPart|1|1,8,110|5446.52,67.08,-410.62|Build/Props
Stairs1|MeshPart|1|1,8,110|5699.52,67.08,-410.62|Build/Props
Part|Part|1|7,2,6|5180.02,109.58,-435.62|Build/Props
Part|Part|1|5,31,17|5180.02,86.08,-444.12|Build/Props
Part|Part|1|7,3,6|5180.02,107.08,-435.62|Build/Props
Part|Part|1|77,2,1|5180.02,102.58,-436.12|Build/Props
Part|Part|1|78,1,1|5180.52,70.08,-436.12|Build/Props
Part|Part|1|79,32,2|5180.02,85.58,-438.62|Build/Props
Part|Part|1|78,2,2|5180.52,68.58,-436.62|Build/Props
Part|Part|1|77,7,1|5180.02,101.08,-437.12|Build/Props
Part|Part|1|77,2,5|5180.02,104.58,-437.12|Build/Props
Part|Part|1|77,6,2|5180.02,70.58,-437.62|Build/Props
Part|Part|1|77,20,1|5180.02,85.58,-437.12|Build/Props
Part|Part|1|13,2,11|5224.02,108.58,-439.12|Build/Props
Part|Part|1|11,2,13|5224.02,108.58,-439.12|Build/Props
Part|Part|1|5,2,9|5224.02,110.58,-439.12|Build/Props
Part|Part|1|9,2,5|5224.02,110.58,-439.12|Build/Props
Part|Part|1|11,2,9|5224.02,106.58,-439.12|Build/Props
Part|Part|1|9,2,11|5224.02,106.58,-439.12|Build/Props
Part|Part|1|1,30,3|5229.02,90.58,-442.12|Build/Props
Part|Part|1|3,30,1|5227.02,90.58,-444.12|Build/Props
Part|Part|1|3,30,1|5227.02,90.58,-434.12|Build/Props
Part|Part|1|3,30,11|5221.02,90.58,-439.12|Build/Props
Part|Part|1|1,30,3|5229.02,90.58,-436.12|Build/Props
Part|Part|1|1,30,3|5219.02,90.58,-436.12|Build/Props
Part|Part|1|9,32,9|5224.02,89.58,-439.12|Build/Props
Part|Part|1|11,1,13|5224.02,70.08,-439.12|Build/Props
Part|Part|1|13,1,11|5224.02,70.08,-439.12|Build/Props
Part|Part|1|9,6,11|5224.02,70.58,-439.12|Build/Props
Part|Part|1|13,2,11|5224.02,68.58,-439.12|Build/Props
Part|Part|1|11,2,13|5224.02,68.58,-439.12|Build/Props
Part|Part|1|11,6,9|5224.02,70.58,-439.12|Build/Props
Part|Part|1|12,1,2|5200.52,96.08,-436.62|Build/Props
Part|Part|1|1,2,2|5206.02,94.58,-436.62|Build/Props
Part|Part|1|10,2,1.1|5200.52,94.58,-437.07|Build/Props
Part|Part|1|1,2,2|5195.02,94.58,-436.62|Build/Props
Part|Part|1|12,1,2|5200.52,93.08,-436.62|Build/Props
Cube.009|MeshPart|1|19.49,68.44,19.49|5316.05,161.2,-451.43|Build/Props
Part|Part|1|22,2,22|5316.05,126.03,-451.43|Build/Props
Part|Part|1|12,30,12|5316.05,105.03,-451.43|Build/Props
Part|Part|1|4,33,4|5309.05,106.53,-444.43|Build/Props
Part|Part|1|4,33,4|5309.05,106.53,-458.43|Build/Props
Part|Part|1|6,30,6|5321.05,105.03,-456.43|Build/Props
Part|Part|1|6,30,6|5311.05,105.03,-446.43|Build/Props
Part|Part|1|18,2,18|5316.05,124.03,-451.43|Build/Props
Part|Part|1|6,30,6|5311.05,105.03,-456.43|Build/Props
Part|Part|1|6,30,6|5321.05,105.03,-446.43|Build/Props
Part|Part|1|16,3,16|5316.05,121.53,-451.43|Build/Props
Part|Part|1|4,33,4|5323.05,106.53,-458.43|Build/Props
Part|Part|1|4,33,4|5323.05,106.53,-444.43|Build/Props
Part|Part|1|25,1,1|5227.02,70.08,-451.12|Build/Props
Part|Part|1|1,31,2|5226.52,86.08,-445.12|Build/Props
Part|Part|1|19,2,2|5226.52,102.58,-454.12|Build/Props
Part|Part|1|19,2,3|5227.02,104.58,-454.12|Build/Props
Part|Part|1|19,4,1|5226.02,99.58,-454.12|Build/Props
Part|Part|1|25,34,1|5225.02,84.58,-451.12|Build/Props
Part|Part|1|17,3,1|5226.02,72.08,-453.12|Build/Props
Part|Part|1|25,2,2|5227.52,68.58,-451.12|Build/Props
Part|Part|1|19,20,1|5226.02,85.58,-454.12|Build/Props
Part|Part|1|9,2,5|5180.02,68.58,-435.12|Build/Props
Part|Part|1|9,1,5|5180.02,71.08,-435.12|Build/Props
Part|Part|1|8,1,4|5180.02,70.08,-435.12|Build/Props
Cube.019|MeshPart|1|5,38,2.39|5180.02,86.58,-434.43|Build/Props
Cube.009|MeshPart|1|19.49,68.44,19.49|5203,161.2,-457.43|Build/Props
Part|Part|1|6,30,6|5208,105.03,-462.43|Build/Props
Part|Part|1|6,30,6|5198,105.03,-452.43|Build/Props
Part|Part|1|18,2,18|5203,124.03,-457.43|Build/Props
Part|Part|1|22,2,22|5203,126.03,-457.43|Build/Props
Part|Part|1|16,3,16|5203,121.53,-457.43|Build/Props
Part|Part|1|6,30,6|5198,105.03,-462.43|Build/Props
Part|Part|1|12,30,12|5203,105.03,-457.43|Build/Props
Part|Part|1|4,33,4|5210,106.53,-450.43|Build/Props
Part|Part|1|4,33,4|5196,106.53,-464.43|Build/Props
Part|Part|1|4,33,4|5210,106.53,-464.43|Build/Props
Part|Part|1|6,30,6|5208,105.03,-452.43|Build/Props
Part|Part|1|4,33,4|5196,106.53,-450.43|Build/Props
Part|Part|1|1,30,3|5131.02,90.58,-442.12|Build/Props
Part|Part|1|3,30,1|5133.02,90.58,-434.12|Build/Props
Part|Part|1|3,30,1|5133.02,90.58,-444.12|Build/Props
Part|Part|1|9,32,9|5136.02,89.58,-439.12|Build/Props
Part|Part|1|3,30,11|5139.02,90.58,-439.12|Build/Props
Part|Part|1|1,30,3|5131.02,90.58,-436.12|Build/Props
Part|Part|1|1,30,3|5141.02,90.58,-436.12|Build/Props
Part|Part|1|9,2,5|5136.02,110.58,-439.12|Build/Props
Part|Part|1|11,2,13|5136.02,108.58,-439.12|Build/Props
Part|Part|1|9,2,11|5136.02,106.58,-439.12|Build/Props
Part|Part|1|5,2,9|5136.02,110.58,-439.12|Build/Props
Part|Part|1|13,2,11|5136.02,108.58,-439.12|Build/Props
Part|Part|1|11,2,9|5136.02,106.58,-439.12|Build/Props
Part|Part|1|11,1,13|5136.02,70.08,-439.12|Build/Props
Part|Part|1|13,1,11|5136.02,70.08,-439.12|Build/Props
Part|Part|1|11,6,9|5136.02,70.58,-439.12|Build/Props
Part|Part|1|13,2,11|5136.02,68.58,-439.12|Build/Props
Part|Part|1|9,6,11|5136.02,70.58,-439.12|Build/Props
Part|Part|1|11,2,13|5136.02,68.58,-439.12|Build/Props
Part|Part|1|7,2,6|5344.02,109.58,-435.62|Build/Props
Part|Part|1|7,3,6|5344.02,107.08,-435.62|Build/Props
Part|Part|1|5,31,17|5344.02,86.08,-444.12|Build/Props
Part|Part|1|8,1,4|5344.02,70.08,-435.12|Build/Props
Part|Part|1|9,2,5|5344.02,68.58,-435.12|Build/Props
Part|Part|1|9,1,5|5344.02,71.08,-435.12|Build/Props
Cube.019|MeshPart|1|5,38,2.39|5344.02,86.58,-434.43|Build/Props
Part|Part|1|1,30,3|5383.02,90.58,-436.12|Build/Props
Part|Part|1|9,32,9|5388.02,89.58,-439.12|Build/Props
Part|Part|1|1,30,3|5393.02,90.58,-436.12|Build/Props
Part|Part|1|3,30,1|5391.02,90.58,-444.12|Build/Props
Part|Part|1|3,30,11|5385.02,90.58,-439.12|Build/Props
Part|Part|1|3,30,1|5391.02,90.58,-434.12|Build/Props
Part|Part|1|1,30,3|5393.02,90.58,-442.12|Build/Props
Part|Part|1|11,2,13|5388.02,108.58,-439.12|Build/Props
Part|Part|1|13,2,11|5388.02,108.58,-439.12|Build/Props
Part|Part|1|5,2,9|5388.02,110.58,-439.12|Build/Props
Part|Part|1|9,2,11|5388.02,106.58,-439.12|Build/Props
Part|Part|1|11,2,9|5388.02,106.58,-439.12|Build/Props
Part|Part|1|9,2,5|5388.02,110.58,-439.12|Build/Props
Part|Part|1|13,1,11|5388.02,70.08,-439.12|Build/Props
Part|Part|1|9,6,11|5388.02,70.58,-439.12|Build/Props
Part|Part|1|13,2,11|5388.02,68.58,-439.12|Build/Props
Part|Part|1|11,1,13|5388.02,70.08,-439.12|Build/Props
Part|Part|1|11,6,9|5388.02,70.58,-439.12|Build/Props
Part|Part|1|11,2,13|5388.02,68.58,-439.12|Build/Props
Part|Part|1|11,2,13|5300.02,108.58,-439.12|Build/Props
Part|Part|1|13,2,11|5300.02,108.58,-439.12|Build/Props
Part|Part|1|9,2,5|5300.02,110.58,-439.12|Build/Props
Part|Part|1|9,2,11|5300.02,106.58,-439.12|Build/Props
Part|Part|1|5,2,9|5300.02,110.58,-439.12|Build/Props
Part|Part|1|11,2,9|5300.02,106.58,-439.12|Build/Props
Part|Part|1|11,1,13|5300.02,70.08,-439.12|Build/Props
Part|Part|1|11,2,13|5300.02,68.58,-439.12|Build/Props
Part|Part|1|13,2,11|5300.02,68.58,-439.12|Build/Props
Part|Part|1|13,1,11|5300.02,70.08,-439.12|Build/Props
Part|Part|1|11,6,9|5300.02,70.58,-439.12|Build/Props
Part|Part|1|9,6,11|5300.02,70.58,-439.12|Build/Props
Part|Part|1|1,30,3|5295.02,90.58,-436.12|Build/Props
Part|Part|1|3,30,1|5297.02,90.58,-434.12|Build/Props
Part|Part|1|3,30,1|5297.02,90.58,-444.12|Build/Props
Part|Part|1|1,30,3|5305.02,90.58,-436.12|Build/Props
Part|Part|1|9,32,9|5300.02,89.58,-439.12|Build/Props
Part|Part|1|3,30,11|5303.02,90.58,-439.12|Build/Props
Part|Part|1|1,30,3|5295.02,90.58,-442.12|Build/Props
Part|Part|1|19,2,2|5297.52,102.58,-454.12|Build/Props
Part|Part|1|1,31,2|5297.52,86.08,-445.12|Build/Props
Part|Part|1|25,1,1|5297.02,70.08,-451.12|Build/Props
Part|Part|1|19,4,1|5298.02,99.58,-454.12|Build/Props
Part|Part|1|19,2,3|5297.02,104.58,-454.12|Build/Props
Part|Part|1|19,20,1|5298.02,85.58,-454.12|Build/Props
Part|Part|1|25,34,1|5299.02,84.58,-451.12|Build/Props
Part|Part|1|25,2,2|5296.52,68.58,-451.12|Build/Props
Part|Part|1|17,3,1|5298.02,72.08,-453.12|Build/Props
Part|Part|1|12,1,2|5364.52,96.08,-436.62|Build/Props
Part|Part|1|1,2,2|5370.02,94.58,-436.62|Build/Props
Part|Part|1|1,2,2|5359.02,94.58,-436.62|Build/Props
Part|Part|1|12,1,2|5364.52,93.08,-436.62|Build/Props
Part|Part|1|10,2,1.1|5364.52,94.58,-437.07|Build/Props
Part|Part|1|77,2,1|5344.02,102.58,-436.12|Build/Props
Part|Part|1|78,1,1|5343.52,70.08,-436.12|Build/Props
Part|Part|1|77,6,2|5344.02,70.58,-437.62|Build/Props
Part|Part|1|77,2,5|5344.02,104.58,-437.12|Build/Props
Part|Part|1|79,32,2|5344.02,85.58,-438.62|Build/Props
Part|Part|1|77,7,1|5344.02,101.08,-437.12|Build/Props
Part|Part|1|78,2,2|5343.52,68.58,-436.62|Build/Props
Part|Part|1|77,20,1|5344.02,85.58,-437.12|Build/Props
Part|Part|1|7,2,6|5966.02,109.58,-435.62|Build/Props
Part|Part|1|7,3,6|5966.02,107.08,-435.62|Build/Props
Part|Part|1|5,31,17|5966.02,86.08,-444.12|Build/Props
Cube.009|MeshPart|1|19.49,68.44,19.49|5830,161.2,-451.43|Build/Props
Part|Part|1|6,30,6|5825,105.03,-446.43|Build/Props
Part|Part|1|6,30,6|5835,105.03,-456.43|Build/Props
Part|Part|1|4,33,4|5823,106.53,-458.43|Build/Props
Part|Part|1|4,33,4|5823,106.53,-444.43|Build/Props
Part|Part|1|4,33,4|5837,106.53,-444.43|Build/Props
Part|Part|1|12,30,12|5830,105.03,-451.43|Build/Props
Part|Part|1|6,30,6|5835,105.03,-446.43|Build/Props
Part|Part|1|4,33,4|5837,106.53,-458.43|Build/Props
Part|Part|1|16,3,16|5830,121.53,-451.43|Build/Props
Part|Part|1|22,2,22|5830,126.03,-451.43|Build/Props
Part|Part|1|18,2,18|5830,124.03,-451.43|Build/Props
Part|Part|1|6,30,6|5825,105.03,-456.43|Build/Props
Part|Part|1|3,30,1|6013.02,90.58,-444.12|Build/Props
Part|Part|1|9,32,9|6010.02,89.58,-439.12|Build/Props
Part|Part|1|3,30,11|6007.02,90.58,-439.12|Build/Props
Part|Part|1|1,30,3|6005.02,90.58,-436.12|Build/Props
Part|Part|1|1,30,3|6015.02,90.58,-442.12|Build/Props
Part|Part|1|1,30,3|6015.02,90.58,-436.12|Build/Props
Part|Part|1|3,30,1|6013.02,90.58,-434.12|Build/Props
Part|Part|1|13,2,11|6010.02,108.58,-439.12|Build/Props
Part|Part|1|11,2,13|6010.02,108.58,-439.12|Build/Props
Part|Part|1|5,2,9|6010.02,110.58,-439.12|Build/Props
Part|Part|1|9,2,5|6010.02,110.58,-439.12|Build/Props
Part|Part|1|9,2,11|6010.02,106.58,-439.12|Build/Props
Part|Part|1|11,2,9|6010.02,106.58,-439.12|Build/Props
Part|Part|1|11,6,9|6010.02,70.58,-439.12|Build/Props
Part|Part|1|13,2,11|6010.02,68.58,-439.12|Build/Props
Part|Part|1|11,2,13|6010.02,68.58,-439.12|Build/Props
Part|Part|1|9,6,11|6010.02,70.58,-439.12|Build/Props
Part|Part|1|13,1,11|6010.02,70.08,-439.12|Build/Props
Part|Part|1|11,1,13|6010.02,70.08,-439.12|Build/Props
Part|Part|1|77,2,1|5966.02,102.58,-436.12|Build/Props
Part|Part|1|78,1,1|5965.52,70.08,-436.12|Build/Props
Part|Part|1|77,6,2|5966.02,70.58,-437.62|Build/Props
Part|Part|1|79,32,2|5966.02,85.58,-438.62|Build/Props
Part|Part|1|77,20,1|5966.02,85.58,-437.12|Build/Props
Part|Part|1|77,2,5|5966.02,104.58,-437.12|Build/Props
Part|Part|1|77,7,1|5966.02,101.08,-437.12|Build/Props
Part|Part|1|78,2,2|5965.52,68.58,-436.62|Build/Props
Cube.009|MeshPart|1|19.49,68.44,19.49|5943.05,161.2,-457.43|Build/Props
Part|Part|1|6,30,6|5938.05,105.03,-462.43|Build/Props
Part|Part|1|22,2,22|5943.05,126.03,-457.43|Build/Props
Part|Part|1|4,33,4|5950.05,106.53,-464.43|Build/Props
Part|Part|1|6,30,6|5948.05,105.03,-462.43|Build/Props
Part|Part|1|4,33,4|5936.05,106.53,-450.43|Build/Props
Part|Part|1|12,30,12|5943.05,105.03,-457.43|Build/Props
Part|Part|1|18,2,18|5943.05,124.03,-457.43|Build/Props
Part|Part|1|6,30,6|5948.05,105.03,-452.43|Build/Props
Part|Part|1|16,3,16|5943.05,121.53,-457.43|Build/Props
Part|Part|1|6,30,6|5938.05,105.03,-452.43|Build/Props
Part|Part|1|4,33,4|5936.05,106.53,-464.43|Build/Props
Part|Part|1|4,33,4|5950.05,106.53,-450.43|Build/Props
Part|Part|1|13,2,11|5922.02,108.58,-439.12|Build/Props
Part|Part|1|11,2,13|5922.02,108.58,-439.12|Build/Props
Part|Part|1|5,2,9|5922.02,110.58,-439.12|Build/Props
Part|Part|1|11,2,9|5922.02,106.58,-439.12|Build/Props
Part|Part|1|9,2,11|5922.02,106.58,-439.12|Build/Props
Part|Part|1|9,2,5|5922.02,110.58,-439.12|Build/Props
Part|Part|1|13,1,11|5922.02,70.08,-439.12|Build/Props
Part|Part|1|11,1,13|5922.02,70.08,-439.12|Build/Props
Part|Part|1|11,6,9|5922.02,70.58,-439.12|Build/Props
Part|Part|1|9,6,11|5922.02,70.58,-439.12|Build/Props
Part|Part|1|11,2,13|5922.02,68.58,-439.12|Build/Props
Part|Part|1|13,2,11|5922.02,68.58,-439.12|Build/Props
Part|Part|1|3,30,11|5925.02,90.58,-439.12|Build/Props
Part|Part|1|1,30,3|5917.02,90.58,-442.12|Build/Props
Part|Part|1|3,30,1|5919.02,90.58,-444.12|Build/Props
Part|Part|1|1,30,3|5927.02,90.58,-436.12|Build/Props
Part|Part|1|1,30,3|5917.02,90.58,-436.12|Build/Props
Part|Part|1|9,32,9|5922.02,89.58,-439.12|Build/Props
Part|Part|1|3,30,1|5919.02,90.58,-434.12|Build/Props
Part|Part|1|25,1,1|5919.02,70.08,-451.12|Build/Props
Part|Part|1|1,31,2|5919.52,86.08,-445.12|Build/Props
Part|Part|1|19,2,2|5919.52,102.58,-454.12|Build/Props
Part|Part|1|17,3,1|5920.02,72.08,-453.12|Build/Props
Part|Part|1|19,4,1|5920.02,99.58,-454.12|Build/Props
Part|Part|1|25,34,1|5921.02,84.58,-451.12|Build/Props
Part|Part|1|19,20,1|5920.02,85.58,-454.12|Build/Props
Part|Part|1|19,2,3|5919.02,104.58,-454.12|Build/Props
Part|Part|1|25,2,2|5918.52,68.58,-451.12|Build/Props
Part|Part|1|8,1,4|5966.02,70.08,-435.12|Build/Props
Part|Part|1|9,1,5|5966.02,71.08,-435.12|Build/Props
Part|Part|1|9,2,5|5966.02,68.58,-435.12|Build/Props
Cube.019|MeshPart|1|5,38,2.39|5966.02,86.58,-434.43|Build/Props
Part|Part|1|12,1,2|5945.52,96.08,-436.62|Build/Props
Part|Part|1|1,2,2|5951.02,94.58,-436.62|Build/Props
Part|Part|1|1,2,2|5940.02,94.58,-436.62|Build/Props
Part|Part|1|12,1,2|5945.52,93.08,-436.62|Build/Props
Part|Part|1|10,2,1.1|5945.52,94.58,-437.07|Build/Props
Part|Part|1|5,31,17|5802.02,86.08,-444.12|Build/Props
Part|Part|1|7,3,6|5802.02,107.08,-435.62|Build/Props
Part|Part|1|7,2,6|5802.02,109.58,-435.62|Build/Props
Part|Part|1|1,31,2|5848.52,86.08,-445.12|Build/Props
Part|Part|1|25,34,1|5847.02,84.58,-451.12|Build/Props
Part|Part|1|19,4,1|5848.02,99.58,-454.12|Build/Props
Part|Part|1|19,2,2|5848.52,102.58,-454.12|Build/Props
Part|Part|1|25,2,2|5849.52,68.58,-451.12|Build/Props
Part|Part|1|17,3,1|5848.02,72.08,-453.12|Build/Props
Part|Part|1|19,20,1|5848.02,85.58,-454.12|Build/Props
Part|Part|1|25,1,1|5849.02,70.08,-451.12|Build/Props
Part|Part|1|19,2,3|5849.02,104.58,-454.12|Build/Props
Part|Part|1|13,2,11|5846.02,108.58,-439.12|Build/Props
Part|Part|1|11,2,13|5846.02,108.58,-439.12|Build/Props
Part|Part|1|9,2,5|5846.02,110.58,-439.12|Build/Props
Part|Part|1|11,2,9|5846.02,106.58,-439.12|Build/Props
Part|Part|1|5,2,9|5846.02,110.58,-439.12|Build/Props
Part|Part|1|9,2,11|5846.02,106.58,-439.12|Build/Props
Part|Part|1|3,30,1|5849.02,90.58,-444.12|Build/Props
Part|Part|1|1,30,3|5841.02,90.58,-436.12|Build/Props
Part|Part|1|1,30,3|5851.02,90.58,-442.12|Build/Props
Part|Part|1|9,32,9|5846.02,89.58,-439.12|Build/Props
Part|Part|1|1,30,3|5851.02,90.58,-436.12|Build/Props
Part|Part|1|3,30,11|5843.02,90.58,-439.12|Build/Props
Part|Part|1|3,30,1|5849.02,90.58,-434.12|Build/Props
Part|Part|1|13,1,11|5846.02,70.08,-439.12|Build/Props
Part|Part|1|11,6,9|5846.02,70.58,-439.12|Build/Props
Part|Part|1|11,2,13|5846.02,68.58,-439.12|Build/Props
Part|Part|1|9,6,11|5846.02,70.58,-439.12|Build/Props
Part|Part|1|11,1,13|5846.02,70.08,-439.12|Build/Props
Part|Part|1|13,2,11|5846.02,68.58,-439.12|Build/Props
Part|Part|1|11,2,13|5758.02,108.58,-439.12|Build/Props
Part|Part|1|13,2,11|5758.02,108.58,-439.12|Build/Props
Part|Part|1|9,2,5|5758.02,110.58,-439.12|Build/Props
Part|Part|1|5,2,9|5758.02,110.58,-439.12|Build/Props
Part|Part|1|11,2,9|5758.02,106.58,-439.12|Build/Props
Part|Part|1|9,2,11|5758.02,106.58,-439.12|Build/Props
Part|Part|1|3,30,11|5761.02,90.58,-439.12|Build/Props
Part|Part|1|3,30,1|5755.02,90.58,-444.12|Build/Props
Part|Part|1|1,30,3|5763.02,90.58,-436.12|Build/Props
Part|Part|1|9,32,9|5758.02,89.58,-439.12|Build/Props
Part|Part|1|1,30,3|5753.02,90.58,-436.12|Build/Props
Part|Part|1|1,30,3|5753.02,90.58,-442.12|Build/Props
Part|Part|1|3,30,1|5755.02,90.58,-434.12|Build/Props
Part|Part|1|13,1,11|5758.02,70.08,-439.12|Build/Props
Part|Part|1|11,1,13|5758.02,70.08,-439.12|Build/Props
Part|Part|1|9,6,11|5758.02,70.58,-439.12|Build/Props
Part|Part|1|11,2,13|5758.02,68.58,-439.12|Build/Props
Part|Part|1|13,2,11|5758.02,68.58,-439.12|Build/Props
Part|Part|1|11,6,9|5758.02,70.58,-439.12|Build/Props
Part|Part|1|8,1,4|5802.02,70.08,-435.12|Build/Props
Part|Part|1|9,1,5|5802.02,71.08,-435.12|Build/Props
Part|Part|1|9,2,5|5802.02,68.58,-435.12|Build/Props
Cube.019|MeshPart|1|5,38,2.39|5802.02,86.58,-434.43|Build/Props
Part|Part|1|1,2,2|5776.02,94.58,-436.62|Build/Props
Part|Part|1|1,2,2|5787.02,94.58,-436.62|Build/Props
Part|Part|1|12,1,2|5781.52,96.08,-436.62|Build/Props
Part|Part|1|10,2,1.1|5781.52,94.58,-437.07|Build/Props
Part|Part|1|12,1,2|5781.52,93.08,-436.62|Build/Props
Part|Part|1|78,1,1|5802.52,70.08,-436.12|Build/Props
Part|Part|1|77,2,1|5802.02,102.58,-436.12|Build/Props
Part|Part|1|79,32,2|5802.02,85.58,-438.62|Build/Props
Part|Part|1|77,6,2|5802.02,70.58,-437.62|Build/Props
Part|Part|1|77,20,1|5802.02,85.58,-437.12|Build/Props
Part|Part|1|77,7,1|5802.02,101.08,-437.12|Build/Props
Part|Part|1|77,2,5|5802.02,104.58,-437.12|Build/Props
Part|Part|1|78,2,2|5802.52,68.58,-436.62|Build/Props
Part|Part|1|15,2,13|5438.52,108.58,-444.12|Build/Props
Part|Part|1|13,2,1|5438.52,108.58,-437.12|Build/Props
Part|Part|1|1,4,3|5432.52,111.58,-444.12|Build/Props
Part|Part|1|9,4,1|5438.52,111.58,-439.12|Build/Props
Part|Part|1|13,2,11|5438.52,106.58,-444.12|Build/Props
Part|Part|1|11,4,9|5438.52,111.58,-444.12|Build/Props
Cube.009|MeshPart|1|12.94,45.44,12.94|5438.52,136.25,-443.62|Build/Props
Part|Part|1|5,32,4|5442.52,89.58,-440.62|Build/Props
Part|Part|1|3,37,3|5442.52,89.08,-439.12|Build/Props
Part|Part|1|5,32,4|5434.52,89.58,-440.62|Build/Props
Part|Part|1|3,37,3|5434.52,89.08,-439.12|Build/Props
Part|Part|1|13,1,1|5438.52,70.08,-437.12|Build/Props
Part|Part|1|15,1,5|5438.52,70.08,-440.12|Build/Props
Part|Part|1|13,6,4|5438.52,70.58,-440.62|Build/Props
Part|Part|1|15,2,5|5438.52,68.58,-440.12|Build/Props
Part|Part|1|13,2,1|5438.52,68.58,-437.12|Build/Props
Cube.001|MeshPart|1|15.26,29.62,1.55|5456.4,94.01,-442.11|Build/Props
Cube|MeshPart|1|10.96,29.19,1.54|5456.4,94.17,-442.11|Build/Props
Part|Part|1|53,2,2|5419.02,108.58,-442.62|Build/Props
Part|Part|1|52,2,2|5502.52,108.58,-442.62|Build/Props
Part|Part|1|49,3,1|5417.02,106.08,-442.12|Build/Props
Part|Part|1|58,40,1|5500.52,87.58,-443.12|Build/Props
Part|Part|1|137,1,2|5461.02,70.08,-441.62|Build/Props
Part|Part|1|50,6,1|5417.52,70.58,-442.12|Build/Props
Part|Part|1|49,3,1|5506.02,106.08,-442.12|Build/Props
Part|Part|1|138,2,1|5461.52,68.58,-441.12|Build/Props
Part|Part|1|50,6,1|5505.52,70.58,-442.12|Build/Props
Part|Part|1|53,40,1|5419.02,87.58,-443.12|Build/Props
Cube.009|MeshPart|1|12.94,45.44,12.94|5474.52,136.25,-443.62|Build/Props
Part|Part|1|5,32,4|5478.52,89.58,-440.62|Build/Props
Part|Part|1|3,37,3|5470.52,89.08,-439.12|Build/Props
Part|Part|1|3,37,3|5478.52,89.08,-439.12|Build/Props
Part|Part|1|5,32,4|5470.52,89.58,-440.62|Build/Props
Part|Part|1|15,1,5|5474.52,70.08,-440.12|Build/Props
Part|Part|1|13,6,4|5474.52,70.58,-440.62|Build/Props
Part|Part|1|15,2,5|5474.52,68.58,-440.12|Build/Props
Part|Part|1|13,1,1|5474.52,70.08,-437.12|Build/Props
Part|Part|1|13,2,1|5474.52,68.58,-437.12|Build/Props
Part|Part|1|15,2,13|5474.52,108.58,-444.12|Build/Props
Part|Part|1|21,1,1|5456.52,108.58,-442.12|Build/Props
Part|Part|1|1,4,3|5480.52,111.58,-444.12|Build/Props
Part|Part|1|11,4,9|5474.52,111.58,-444.12|Build/Props
Part|Part|1|9,4,1|5474.52,111.58,-439.12|Build/Props
Part|Part|1|13,2,11|5474.52,106.58,-444.12|Build/Props
Part|Part|1|13,2,1|5474.52,108.58,-437.12|Build/Props
Stairs1|MeshPart|1|4,6,10|5450.02,116.58,-443.62|Build/Props
WallFacade1|MeshPart|1|39,29.07,1.07|5412.02,89.04,-442.09|Build/Props
WallFacade1|MeshPart|1|49,29.07,1.07|5506.02,89.04,-442.09|Build/Props
ExtrusionWall|MeshPart|1|25,55,6|5456.52,86.08,-445.62|Build/Props
Stairs1|MeshPart|1|4,6,10|5463.02,116.58,-443.62|Build/Props
Part|Part|1|3,9,4|5456.52,118.08,-443.62|Build/Props
Part|Part|1|5,32,4|5667.52,89.58,-440.62|Build/Props
Part|Part|1|3,37,3|5675.52,89.08,-439.12|Build/Props
Part|Part|1|3,37,3|5667.52,89.08,-439.12|Build/Props
Part|Part|1|5,32,4|5675.52,89.58,-440.62|Build/Props
Part|Part|1|15,1,5|5671.52,70.08,-440.12|Build/Props
Part|Part|1|13,1,1|5671.52,70.08,-437.12|Build/Props
Part|Part|1|13,6,4|5671.52,70.58,-440.62|Build/Props
Part|Part|1|13,2,1|5671.52,68.58,-437.12|Build/Props
Part|Part|1|15,2,5|5671.52,68.58,-440.12|Build/Props
Part|Part|1|15,2,13|5671.52,108.58,-444.12|Build/Props
Part|Part|1|1,4,3|5665.52,111.58,-444.12|Build/Props
Part|Part|1|13,2,1|5671.52,108.58,-437.12|Build/Props
Part|Part|1|21,1,1|5689.52,108.58,-442.12|Build/Props
Part|Part|1|13,2,11|5671.52,106.58,-444.12|Build/Props
Part|Part|1|9,4,1|5671.52,111.58,-439.12|Build/Props
Part|Part|1|11,4,9|5671.52,111.58,-444.12|Build/Props
Cube.009|MeshPart|1|12.94,45.44,12.94|5671.52,136.25,-443.62|Build/Props
Part|Part|1|1,4,3|5713.52,111.58,-444.12|Build/Props
Part|Part|1|15,2,13|5707.52,108.58,-444.12|Build/Props
Part|Part|1|9,4,1|5707.52,111.58,-439.12|Build/Props
Part|Part|1|13,2,11|5707.52,106.58,-444.12|Build/Props
Part|Part|1|13,2,1|5707.52,108.58,-437.12|Build/Props
Part|Part|1|11,4,9|5707.52,111.58,-444.12|Build/Props
Part|Part|1|5,32,4|5703.52,89.58,-440.62|Build/Props
Part|Part|1|5,32,4|5711.52,89.58,-440.62|Build/Props
Part|Part|1|3,37,3|5703.52,89.08,-439.12|Build/Props
Part|Part|1|3,37,3|5711.52,89.08,-439.12|Build/Props
Part|Part|1|13,1,1|5707.52,70.08,-437.12|Build/Props
Part|Part|1|15,1,5|5707.52,70.08,-440.12|Build/Props
Part|Part|1|13,6,4|5707.52,70.58,-440.62|Build/Props
Part|Part|1|13,2,1|5707.52,68.58,-437.12|Build/Props
Part|Part|1|15,2,5|5707.52,68.58,-440.12|Build/Props
Cube.009|MeshPart|1|12.94,45.44,12.94|5707.52,136.25,-443.62|Build/Props
Part|Part|1|137,1,2|5685.02,70.08,-441.62|Build/Props
Part|Part|1|52,2,2|5643.52,108.58,-442.62|Build/Props
Part|Part|1|53,40,1|5727.02,87.58,-443.12|Build/Props
Part|Part|1|53,2,2|5727.02,108.58,-442.62|Build/Props
Part|Part|1|50,6,1|5728.52,70.58,-442.12|Build/Props
Part|Part|1|138,2,1|5684.52,68.58,-441.12|Build/Props
Part|Part|1|49,3,1|5729.02,106.08,-442.12|Build/Props
Part|Part|1|58,40,1|5645.52,87.58,-443.12|Build/Props
Part|Part|1|49,3,1|5640.02,106.08,-442.12|Build/Props
Part|Part|1|50,6,1|5640.52,70.58,-442.12|Build/Props
Cube.001|MeshPart|1|15.26,29.62,1.55|6015.75,134.64,-421.44|Build/Props
Cube|MeshPart|1|10.96,29.19,1.54|6015.75,134.81,-421.44|Build/Props
Cube.001|MeshPart|1|15.26,29.62,1.55|5689.65,94.01,-442.11|Build/Props
Cube|MeshPart|1|10.96,29.19,1.54|5689.65,94.17,-442.11|Build/Props
ExtrusionWall|MeshPart|1|25,55,6|5689.52,86.08,-445.62|Build/Props
Stairs1|MeshPart|1|4,6,10|5696.02,116.58,-443.62|Build/Props
WallFacade1|MeshPart|1|39,29.07,1.07|5734.02,89.04,-442.09|Build/Props
WallFacade1|MeshPart|1|49,29.07,1.07|5640.02,89.04,-442.09|Build/Props
Part|Part|1|3,9,4|5689.52,118.08,-443.62|Build/Props
Stairs1|MeshPart|1|4,6,10|5683.02,116.58,-443.62|Build/Props
Part|Part|1|3,1,3|5242.02,68.08,-445.12|Build/Props
Part|Part|1|3,1,3|5282.02,68.08,-445.12|Build/Props
Part|Part|1|2,1,2|5282.02,68.58,-445.12|Build/Props
Part|Part|1|1,1,26|5388.02,68.08,-420.62|Build/Props
Part|Part|1|3,1,26|5136.02,68.08,-420.62|Build/Props
Part|Part|1|2,1.1,2|5352.52,68.13,-406.12|Build/Props
Part|Part|1|4,1.1,4|5206.52,68.13,-406.12|Build/Props
Part|Part|1|4,1.1,4|5171.52,68.13,-406.12|Build/Props
Part|Part|1|2,1,2|5242.02,68.58,-445.12|Build/Props
Part|Part|1|103,1,3|5189.02,68.08,-406.12|Build/Props
Part|Part|1|37,1,1|5262.02,68.08,-445.12|Build/Props
Part|Part|1|1,1,36|5282.02,68.08,-425.62|Build/Props
Part|Part|1|2,1.1,2|5317.52,68.13,-406.12|Build/Props
Part|Part|1|103,1,1|5335.02,68.08,-406.12|Build/Props
Part|Part|1|83,1,8|5573.02,68.08,-422.62|Build/Props
Part|Part|1|1,1,36|5242.02,68.08,-425.62|Build/Props
Stairs1|MeshPart|1|1,8,110|5443.52,68.08,-413.62|Build/Props
Stairs1|MeshPart|1|1,8,110|5476.52,68.08,-420.62|Build/Props
Part|Part|1|37,1,1|5884.02,68.08,-445.12|Build/Props
Part|Part|1|2,1.1,2|5939.52,68.13,-406.12|Build/Props
Part|Part|1|1,1,26|5758.02,68.08,-420.62|Build/Props
Part|Part|1|2,1,2|5864.02,68.58,-445.12|Build/Props
Part|Part|1|2,1.1,2|5974.52,68.13,-406.12|Build/Props
Part|Part|1|2,1.1,2|5828.52,68.13,-406.12|Build/Props
Part|Part|1|103,1,1|5811.02,68.08,-406.12|Build/Props
Part|Part|1|1,1,26|6010.02,68.08,-420.62|Build/Props
Part|Part|1|103,1,1|5957.02,68.08,-406.12|Build/Props
Part|Part|1|2,1.1,2|5793.52,68.13,-406.12|Build/Props
Part|Part|1|3,1,3|5904.02,68.08,-445.12|Build/Props
Part|Part|1|2,1,2|5904.02,68.58,-445.12|Build/Props
Part|Part|1|1,1,36|5904.02,68.08,-425.62|Build/Props
Part|Part|1|1,1,36|5864.02,68.08,-425.62|Build/Props
Part|Part|1|3,1,3|5864.02,68.08,-445.12|Build/Props
Stairs1|MeshPart|1|1,8,110|5669.52,68.08,-420.62|Build/Props
Stairs1|MeshPart|1|1,8,110|5702.52,68.08,-413.62|Build/Props
Part|Part|1|1,2,3|5559.52,115.58,-437.62|Build/Props
Part|Part|1|1,2,3|5586.52,115.58,-437.62|Build/Props
Part|Part|1|28,1,3|5573.02,117.08,-437.62|Build/Props
Part|Part|1|28,1,3|5573.02,114.08,-437.62|Build/Props
Part|Part|1|26,2,2.1|5573.02,115.58,-438.07|Build/Props
Part|Part|1|68,2,2|5573.52,108.58,-437.62|Build/Props
Stairs1|Part|1|6,1,35|5573.02,123.08,-440.62|Build/Props
Stairs1|MeshPart|1|34,13,20|5593.52,115.08,-459.62|Build/Props
Stairs1|Part|1|34,12,21|5573.02,115.58,-459.62|Build/Props
Stairs1|MeshPart|1|4,13,20|5551.52,116.08,-440.62|Build/Props
Stairs1|MeshPart|1|4,13,20|5551.52,116.08,-478.62|Build/Props
Stairs1|Part|1|42,50,59|5573.02,85.58,-459.62|Build/Props
Stairs1|MeshPart|1|4,13,20|5594.52,116.08,-440.62|Build/Props
Stairs1|MeshPart|1|4,13,20|5594.52,116.08,-478.62|Build/Props
Stairs1|Part|1|4,13,23|5573.02,116.08,-440.62|Build/Props
Stairs1|MeshPart|1|26,94,45|5542.02,129.08,-493.88|Build/Props
Stairs1|MeshPart|1|26,104,45|5610.02,134.08,-495.62|Build/Props
Stairs1|Part|1|4,13,23|5573.02,116.08,-478.62|Build/Props
Stairs1|MeshPart|1|26,104,45|5536.02,134.08,-495.62|Build/Props
Stairs1|MeshPart|1|34,13,20|5552.52,115.08,-459.62|Build/Props
Stairs1|MeshPart|1|26,94,45|5604.02,129.08,-493.88|Build/Props
Part|Part|1|65,6,1|5573.02,70.58,-437.12|Build/Props
Part|Part|1|67,40,1|5573.02,87.58,-438.12|Build/Props
Part|Part|1|66,2,1|5572.52,68.58,-436.12|Build/Props
Part|Part|1|65,3,1|5573.02,106.08,-437.12|Build/Props
Part|Part|1|65,3,8|5573.02,291.07,-717.63|Build/Props
Part|Part|1|65,3,8|5573.02,321.07,-762.63|Build/Props
Part|Part|1|65,3,8|5573.02,315.07,-753.63|Build/Props
Part|Part|1|65,3,8|5573.02,207.07,-591.63|Build/Props
Part|Part|1|65,3,8|5573.02,159.07,-519.63|Build/Props
Part|Part|1|65,3,8|5573.02,153.07,-510.63|Build/Props
Part|Part|1|65,3,8|5573.02,171.07,-537.63|Build/Props
Part|Part|1|65,3,8|5573.02,177.07,-546.63|Build/Props
Part|Part|1|65,3,8|5573.02,165.07,-528.63|Build/Props
Part|Part|1|65,3,8|5573.02,303.07,-735.63|Build/Props
Part|Part|1|65,3,8|5573.02,345.07,-798.63|Build/Props
Part|Part|1|65,3,8|5573.02,339.07,-789.63|Build/Props
Part|Part|1|65,3,8|5573.02,309.07,-744.63|Build/Props
Part|Part|1|65,3,8|5573.02,249.07,-654.63|Build/Props
Part|Part|1|65,3,8|5573.02,255.07,-663.63|Build/Props
Part|Part|1|65,3,8|5573.02,327.07,-771.63|Build/Props
Part|Part|1|65,3,8|5573.02,333.07,-780.63|Build/Props
Part|Part|1|65,3,8|5573.02,279.07,-699.63|Build/Props
Part|Part|1|65,3,8|5573.02,225.07,-618.63|Build/Props
Part|Part|1|65,3,8|5573.02,237.07,-636.63|Build/Props
Part|Part|1|65,3,8|5573.02,243.07,-645.63|Build/Props
Part|Part|1|65,3,8|5573.02,231.07,-627.63|Build/Props
Part|Part|1|65,3,8|5573.02,195.07,-573.63|Build/Props
Part|Part|1|65,3,8|5573.02,189.07,-564.63|Build/Props
Part|Part|1|65,3,8|5573.02,213.07,-600.63|Build/Props
Part|Part|1|65,3,8|5573.02,201.07,-582.63|Build/Props
Part|Part|1|65,3,8|5573.02,285.07,-708.63|Build/Props
Part|Part|1|65,3,8|5573.02,273.07,-690.63|Build/Props
Part|Part|1|65,3,8|5573.02,297.07,-726.63|Build/Props
Part|Part|1|65,3,8|5573.02,219.07,-609.63|Build/Props
Part|Part|1|65,3,8|5573.02,183.07,-555.63|Build/Props
Part|Part|1|65,3,8|5573.02,261.07,-672.63|Build/Props
Part|Part|1|65,3,8|5573.02,267.07,-681.63|Build/Props
untitled|MeshPart|1|890.61,290.1,436.04|5589.21,286.58,-688.4|Build/Props
Part|Part|1|1,30,3|5616.02,90.58,-442.12|Build/Props
Part|Part|1|3,30,1|5614.02,90.58,-434.12|Build/Props
Part|Part|1|1,30,3|5616.02,90.58,-436.12|Build/Props
Part|Part|1|3,30,1|5608.02,90.58,-434.12|Build/Props
Part|Part|1|9,32,9|5611.02,89.58,-439.12|Build/Props
Part|Part|1|1,30,3|5606.02,90.58,-436.12|Build/Props
Part|Part|1|11,2,13|5611.02,108.58,-439.12|Build/Props
Part|Part|1|13,2,11|5611.02,108.58,-439.12|Build/Props
Part|Part|1|9,2,5|5611.02,110.58,-439.12|Build/Props
Part|Part|1|9,2,11|5611.02,106.58,-439.12|Build/Props
Part|Part|1|5,2,9|5611.02,110.58,-439.12|Build/Props
Part|Part|1|11,2,9|5611.02,106.58,-439.12|Build/Props
Part|Part|1|13,1,11|5611.02,70.08,-439.12|Build/Props
Part|Part|1|13,2,11|5611.02,68.58,-439.12|Build/Props
Part|Part|1|11,6,9|5611.02,70.58,-439.12|Build/Props
Part|Part|1|11,2,13|5611.02,68.58,-439.12|Build/Props
Part|Part|1|9,6,11|5611.02,70.58,-439.12|Build/Props
Part|Part|1|11,1,13|5611.02,70.08,-439.12|Build/Props
Cube.029|MeshPart|1|73,58.05,22.81|5261.66,145.2,-481.76|Build/Props
Cube.024|MeshPart|1|68.61,49.76,18.66|5261.66,145.2,-481.76|Build/Props
Part|Part|1|17.33,1.33,14.66|5261.66,113.91,-481.76|Build/Props
Part|Part|1|14.66,1.33,17.33|5261.66,113.91,-481.76|Build/Props
Part|Part|1|17.33,50.67,14.66|5261.66,87.91,-481.76|Build/Props
Part|Part|1|14.66,50.67,17.33|5261.66,87.91,-481.76|Build/Props
Part|Part|1|14.66,8,12|5261.66,114.58,-481.76|Build/Props
Part|Part|1|12,8,14.66|5261.66,114.58,-481.76|Build/Props
Part|Part|1|1,30,3|5530.02,90.58,-442.12|Build/Props
Part|Part|1|1,30,3|5530.02,90.58,-436.12|Build/Props
Part|Part|1|3,30,1|5532.02,90.58,-434.12|Build/Props
Part|Part|1|1,30,3|5540.02,90.58,-436.12|Build/Props
Part|Part|1|9,32,9|5535.02,89.58,-439.12|Build/Props
Part|Part|1|3,30,1|5538.02,90.58,-434.12|Build/Props
Part|Part|1|13,2,11|5535.02,108.58,-439.12|Build/Props
Part|Part|1|11,2,13|5535.02,108.58,-439.12|Build/Props
Part|Part|1|9,2,5|5535.02,110.58,-439.12|Build/Props
Part|Part|1|9,2,11|5535.02,106.58,-439.12|Build/Props
Part|Part|1|5,2,9|5535.02,110.58,-439.12|Build/Props
Part|Part|1|11,2,9|5535.02,106.58,-439.12|Build/Props
Part|Part|1|13,1,11|5535.02,70.08,-439.12|Build/Props
Part|Part|1|11,1,13|5535.02,70.08,-439.12|Build/Props
Part|Part|1|11,6,9|5535.02,70.58,-439.12|Build/Props
Part|Part|1|9,6,11|5535.02,70.58,-439.12|Build/Props
Part|Part|1|11,2,13|5535.02,68.58,-439.12|Build/Props
Part|Part|1|13,2,11|5535.02,68.58,-439.12|Build/Props
Cube.029|MeshPart|1|73,58.05,22.81|5883.66,145.2,-481.76|Build/Props
Cube.024|MeshPart|1|68.61,49.76,18.66|5883.66,145.2,-481.76|Build/Props
Part|Part|1|17.33,1.33,14.66|5883.66,113.91,-481.76|Build/Props
Part|Part|1|14.66,1.33,17.33|5883.66,113.91,-481.76|Build/Props
Part|Part|1|17.33,50.67,14.66|5883.66,87.91,-481.76|Build/Props
Part|Part|1|14.66,50.67,17.33|5883.66,87.91,-481.76|Build/Props
Part|Part|1|14.66,8,12|5883.66,114.58,-481.76|Build/Props
Part|Part|1|12,8,14.66|5883.66,114.58,-481.76|Build/Props
Cube.029|MeshPart|1|73,58.05,22.81|5573.02,150.6,-455.62|Build/Props
Cube.024|MeshPart|1|68.61,49.76,18.66|5573.02,150.6,-455.62|Build/Props
Part|Part|1|2,2,2|5273.52,100.58,-461.62|Build/Props
Part|Part|1|2,2,2|5249.52,100.58,-461.62|Build/Props
Part|Part|1|22,2,1.1|5261.52,100.58,-462.07|Build/Props
Part|Part|1|26,2,1|5261.52,98.58,-461.12|Build/Props
Part|Part|1|78,1,1|5264.52,70.08,-461.12|Build/Props
Part|Part|1|71,2,1|5261.02,102.58,-461.12|Build/Props
Part|Part|1|78,2,2|5264.52,68.58,-461.62|Build/Props
Part|Part|1|77,6,2|5264.02,70.58,-462.62|Build/Props
Part|Part|1|74,32,2|5261.52,85.58,-463.62|Build/Props
Part|Part|1|70,2,5|5260.52,104.58,-462.12|Build/Props
Part|Part|1|72,7,1|5261.52,101.08,-462.12|Build/Props
Part|Part|1|72,20,1|5261.52,85.58,-462.12|Build/Props
Part|Part|1|2,2,2|5896.52,100.58,-461.62|Build/Props
Part|Part|1|2,2,2|5872.52,100.58,-461.62|Build/Props
Part|Part|1|26,2,1|5884.52,98.58,-461.12|Build/Props
Part|Part|1|22,2,1.1|5884.52,100.58,-462.07|Build/Props
Part|Part|1|71,2,1|5885.02,102.58,-461.12|Build/Props
Part|Part|1|78,1,1|5881.52,70.08,-461.12|Build/Props
Part|Part|1|70,2,5|5885.52,104.58,-462.12|Build/Props
Part|Part|1|72,20,1|5884.52,85.58,-462.12|Build/Props
Part|Part|1|78,2,2|5881.52,68.58,-461.62|Build/Props
Part|Part|1|74,32,2|5884.52,85.58,-463.62|Build/Props
Part|Part|1|77,6,2|5882.02,70.58,-462.62|Build/Props
Part|Part|1|72,7,1|5884.52,101.08,-462.12|Build/Props
Fern1|MeshPart|1|12.95,3.39,11.22|5179.52,112.27,-435.39|Build/Props
Fern1|MeshPart|1|13.88,3.63,12.03|5213.6,70.15,-428.5|Build/Props
Vine1|MeshPart|1|7.61,17.45,9.34|5770.67,110.92,-443.8|Build/Props
Vine1|MeshPart|1|8.65,20.85,10.62|5334.69,108.62,-445.68|Build/Props
Grass2|MeshPart|1|6.72,2.4,7.36|5221.52,69.78,-428.3|Build/Props
Vine1|MeshPart|1|8.65,20.85,10.62|5419.31,113.7,-449.32|Build/Props
Grass1|MeshPart|1|3.2,4.05,2.15|5278.02,70.1,-442.47|Build/Props
Grass1|MeshPart|1|3.48,4.7,2.33|5443.19,71.42,-434.88|Build/Props
Vine1|MeshPart|1|8.69,21.34,9.58|5990.79,111.5,-443.66|Build/Props
Vine1|MeshPart|1|8.65,16.85,10.62|5408.31,111.7,-451.68|Build/Props
Vine2|MeshPart|1|2.28,23.71,2.62|5816.86,114.43,-442.31|Build/Props
Grass2|MeshPart|1|6.72,2.4,7.36|5752.84,70.28,-421.98|Build/Props
Grass2|MeshPart|1|3.94,3.76,4.32|5395.36,70.96,-421.15|Build/Props
Grass1|MeshPart|1|3.48,4.7,2.33|5817.36,70.42,-403.31|Build/Props
Part|Part|1|32.86,21.25,29.07|4328.89,114.65,-469.77|Build/Props
Part|Part|1|35.1,30,29.07|4329.26,111.03,-256.38|Build/Props
Part|Part|1|44.18,16,29.07|5085.82,112.03,-466.72|Build/Props
Part|Part|1|33.96,17.17,29.07|5057.82,112.61,-471.79|Build/Props
Part|Part|1|35.1,30,29.07|4764.29,119.03,-483.96|Build/Props
Part|Part|1|28.82,14.24,29.07|4854.65,111.15,-465.31|Build/Props
Part|Part|1|21.57,40.84,21.07|4465.69,142.17,-472.7|Build/Props
Part|Part|1|35.1,30,29.07|4625.52,119.03,-486.12|Build/Props
Part|Part|1|32.47,22.57,29.07|4451.57,115.31,-460.06|Build/Props
Part|Part|1|19.86,39.25,29.07|4338.67,123.65,-475.55|Build/Props
Part|Part|1|28.1,30,18.07|4790.47,117.03,-249.26|Build/Props
Part|Part|1|28.82,33,29.07|4869.29,114.53,-477.2|Build/Props
Part|Part|1|22.36,36,24.76|4619.26,122.03,-476.56|Build/Props
Part|Part|1|37.1,30,35.07|5033.31,104.03,-256.53|Build/Props
Part|Part|1|36.63,36.83,29.07|4461.78,122.44,-481.15|Build/Props
Part|Part|1|32.86,29.84,29.07|4477.73,118.95,-465.34|Build/Props
Part|Part|1|28.94,21.78,29.07|4607.64,114.92,-474.14|Build/Props
Part|Part|1|32.86,24.45,29.07|4339.52,116.25,-458.98|Build/Props
Part|Part|1|33.96,25.03,29.07|5074.18,116.54,-474.8|Build/Props
Part|Part|1|36.63,9.25,29.07|4669.91,117.65,-491.85|Build/Props
Part|Part|1|53.1,30,29.07|4365.17,107.03,-260.5|Build/Props
Part|Part|1|41.1,30,29.07|4775,107.03,-251.11|Build/Props
Part|Part|1|10.76,9.29,7.37|4444.97,94.29,-438.11|Build/Props
Part|Part|1|18.42,22.05,10.84|4706.59,79.13,-292.2|Build/Props
Part|Part|1|14.34,20.37,7.37|4766.19,78.29,-440.78|Build/Props
Part|Part|1|11.31,25.06,8.84|4899.57,80.63,-292.65|Build/Props
Part|Part|1|13.24,31.29,7.37|4464.59,83.75,-439.06|Build/Props
Part|Part|1|13.5,17.56,7.37|4983.75,76.88,-441.71|Build/Props
Part|Part|1|9.86,10.46,7.37|4304.48,74.95,-437.97|Build/Props
Part|Part|1|21.24,21.07,7.37|4880.31,78.64,-441.69|Build/Props
Part|Part|1|21.24,14.65,7.37|4892.1,75.43,-440.68|Build/Props
Part|Part|1|29.45,14.06,8.84|4917.81,75.13,-291.08|Build/Props
Part|Part|1|24.72,15.92,8.62|4343.94,76.06,-290.52|Build/Props
Part|Part|1|21.24,10.43,7.37|4481.1,73.31,-438.09|Build/Props
Part|Part|1|16.47,8.68,6.46|4632.77,69.7,-438.81|Build/Props
Part|Part|1|16.45,21.06,8.84|5016.82,78.63,-296.34|Build/Props
Part|Part|1|21.24,21.07,7.37|4614.86,78.64,-437.69|Build/Props
Part|Part|1|13.5,11.06,8.84|4987.85,73.63,-440.5|Build/Props
Part|Part|1|18.26,10.92,8.62|4387.12,73.56,-290.94|Build/Props
Part|Part|1|18.52,9.29,7.37|4373.1,74.36,-434.73|Build/Props
Part|Part|1|18.26,10.92,7.62|4475.29,73.56,-292.59|Build/Props
Part|Part|1|9.86,18.45,7.37|4312.56,78.94,-439.11|Build/Props
Part|Part|1|18.42,29.91,8.84|4526.81,83.06,-288.37|Build/Props
Part|Part|1|16.34,23.97,8.84|5102.64,80.09,-441.67|Build/Props
Part|Part|1|18.42,22.05,8.84|4623.45,79.13,-291.63|Build/Props
Part|Part|1|8.51,27.56,6.91|4516.82,81.88,-438.5|Build/Props
Part|Part|1|16.45,11.06,8.84|5034.9,73.63,-440.66|Build/Props
Part|Part|1|15.21,21.84,7.62|4485.17,79.02,-291.74|Build/Props
Part|Part|1|11.31,25.06,8.84|4815.88,80.63,-286.18|Build/Props
Part|Part|1|10.26,17.92,8.62|4380.38,77.06,-290.66|Build/Props
Part|Part|1|18.42,19.38,8.84|4753.58,77.79,-285.9|Build/Props
Part|Part|1|36.63,2,29.07|4461.78,141.86,-481.15|Build/Props
Part|Part|1|28.82,2,29.07|4854.65,119.27,-465.31|Build/Props
Part|Part|1|32.47,2,29.07|4451.57,127.6,-460.06|Build/Props
Part|Part|1|22.36,2,24.76|4619.26,141.02,-476.56|Build/Props
Part|Part|1|33.96,2,29.07|5074.18,130.06,-474.8|Build/Props
Part|Part|1|28.1,2,18.07|4790.47,133.02,-249.26|Build/Props
Part|Part|1|35.1,2,29.07|4764.29,135.02,-483.96|Build/Props
Part|Part|1|35.1,2,29.07|4625.52,135.02,-486.12|Build/Props
Part|Part|1|28.82,2,29.07|4869.29,132.02,-477.2|Build/Props
Part|Part|1|32.86,2,29.07|4477.73,134.86,-465.34|Build/Props
Part|Part|1|35.1,2,29.07|4329.26,127.02,-256.38|Build/Props
Part|Part|1|33.96,2,29.07|5057.82,122.19,-471.79|Build/Props
Part|Part|1|41.1,2,29.07|4775,123.02,-251.11|Build/Props
Part|Part|1|53.1,2,29.07|4365.17,123.02,-260.5|Build/Props
Part|Part|1|44.18,2,29.07|5085.82,121.02,-466.72|Build/Props
Part|Part|1|32.86,2,29.07|4339.52,129.48,-458.98|Build/Props
Part|Part|1|19.86,2,29.07|4338.67,144.28,-475.55|Build/Props
Part|Part|1|32.86,2,29.07|4328.89,126.28,-469.77|Build/Props
Part|Part|1|28.94,2,29.07|4607.64,126.81,-474.14|Build/Props
Part|Part|1|21.57,2,21.07|4465.69,163.58,-472.7|Build/Props
Part|Part|1|37.1,2,35.07|5033.31,120.02,-256.53|Build/Props
Part|Part|0|14.82,36.94,351.52|4933.28,85.56,-448.21|Build/Props
Part|Part|0|14.82,36.94,371.52|4451.28,85.56,-448.21|Build/Props
Part|Part|1|16.82,2,371.57|4451.28,105.03,-449.21|Build/Props
Part|Part|1|16.82,2,865.07|4698.03,105.03,-279.21|Build/Props
Part|Part|0|15.82,36.94,865.02|4698.03,85.56,-279.71|Build/Props
Part|Part|1|16.82,2,351.57|4933.28,105.03,-449.21|Build/Props
Meshes/untitled_Cylinder.004 (2)|MeshPart|1|6.15,22.82,4.86|4890.72,68.48,-410.16|Build/Props
Meshes/untitled_Cylinder.001 (3)|MeshPart|1|6.91,9.96,4.7|4330.54,70.27,-310.18|Build/Props
Meshes/untitled_Cylinder.001 (3)|MeshPart|1|3.78,5.45,2.57|4415.29,69.45,-407.9|Build/Props
Meshes/untitled_Cylinder.004 (2)|MeshPart|1|6.15,22.82,4.86|4663.25,68.42,-317.36|Build/Props
Meshes/untitled_Cylinder.001 (3)|MeshPart|1|5.14,7.41,3.49|4418.48,69.83,-409.13|Build/Props
Meshes/untitled_Cylinder.002 (7)|MeshPart|1|4.25,17.86,2.01|4420.2,67.72,-405.71|Build/Props
MainSideWall|MeshPart|1|871,51.87,55|4699.91,93.51,-459.3|Build/Props
untitled|MeshPart|1|872,50.55,42|4690.47,92.76,-278.8|Build/Props
Part|Part|1|39,2,27|4273.97,109.58,-280.3|Build/Props
Part|Part|1|38,2,23|4833.41,102.58,-451.31|Build/Props
Part|Part|1|38,2,28|5038.47,104.97,-282.8|Build/Props
Part|Part|1|40,2,28|4475.41,105.58,-450.81|Build/Props
Part|Part|1|29,2,24|4734.91,113.58,-470.8|Build/Props
Part|Part|1|29,2,31|4996.91,108.58,-454.31|Build/Props
Part|Part|1|38,2,28|4352.41,116.58,-448.81|Build/Props
Part|Part|1|36,2,25|4530.41,93.58,-450.31|Build/Props
Part|Part|1|15,2,11|4433.97,97.75,-287.3|Build/Props
Part|Part|1|26,2,25|4743.41,107.58,-470.3|Build/Props
Part|Part|1|38,2,27|4301.41,113.58,-451.31|Build/Props
Part|Part|1|23,2,29|5114.97,100.58,-281.3|Build/Props
Part|Part|1|23,2,36|4311.91,106.58,-453.81|Build/Props
Part|Part|1|19,2,23|4528.97,114.23,-280.3|Build/Props
Part|Part|1|23,2,36|5078.97,106.58,-277.8|Build/Props
Part|Part|1|39,2,16|4659.91,115.68,-474.8|Build/Props
Part|Part|1|24,2,13|4507.47,104.11,-286.3|Build/Props
Part|Part|1|17,2,34|4571.91,109.58,-452.81|Build/Props
Part|Part|1|33,2,23|4592.97,119.04,-280.3|Build/Props
Part|Part|1|32,2,10|4698.47,105.09,-289.8|Build/Props
Part|Part|1|29,2,25|5053.91,103.58,-450.31|Build/Props
Part|Part|1|36,2,28|4608.41,102.58,-448.81|Build/Props
Part|Part|1|24,2,24|4883.41,113.58,-450.81|Build/Props
Part|Part|1|28,2,36|5024.47,99.58,-281.8|Build/Props
Part|Part|1|33,2,23|4797.91,110.58,-451.31|Build/Props
Part|Part|1|10,2,27|4317.47,103.01,-280.3|Build/Props
Part|Part|1|23,2,29|4451.91,116.58,-450.31|Build/Props
Part|Part|1|31,2,29|4502.91,114.58,-450.31|Build/Props
Part|Part|1|23,2,29|4275.91,100.58,-450.31|Build/Props
Part|Part|1|10,2,25|5073.41,97.58,-450.31|Build/Props
Part|Part|1|38,2,25|4769.41,101.58,-450.31|Build/Props
Part|Part|1|33,2,29|4918.97,105.58,-280.3|Build/Props
Part|Part|1|34,2,24|4932.41,105.58,-450.81|Build/Props
Part|Part|1|38,2,23|4557.47,109.43,-280.3|Build/Props
Part|Part|1|23,2,29|4938.97,101.36,-281.3|Build/Props
Part|Part|1|23,2,33|4906.91,111.58,-453.31|Build/Props
Part|Part|1|31,2,29|4887.97,114.58,-281.3|Build/Props
Part|Part|1|36,2,24|4764.41,113.58,-450.81|Build/Props
Part|Part|1|15,2,24|4956.91,98.58,-450.81|Build/Props
Part|Part|1|27,2,27|4759.97,113.07,-275.31|Build/Props
Part|Part|1|38,2,27|5089.47,113.58,-280.3|Build/Props
Part|Part|1|43,2,25|4988.97,94.53,-281.3|Build/Props
Part|Part|1|38,2,25|5116.41,109.58,-450.31|Build/Props
Part|Part|1|26,2,25|4651.47,107.58,-276.3|Build/Props
Part|Part|1|32,2,39|4629.41,105.58,-458.31|Build/Props
Part|Part|1|38,2,23|4612.47,102.3,-284.3|Build/Props
Part|Part|1|28,2,36|4366.41,99.58,-449.81|Build/Props
Part|Part|1|42,2,25|4853.47,93.58,-281.3|Build/Props
Part|Part|1|41,2,26|4597.91,117.58,-449.81|Build/Props
Part|Part|1|36,2,24|4626.47,113.58,-280.8|Build/Props
Part|Part|1|29,2,26|5025.91,112.58,-449.81|Build/Props
Part|Part|1|41,2,26|4783.97,107.93,-270.8|Build/Props
Part|Part|1|36,2,28|4795.47,102.58,-277.8|Build/Props
Part|Part|1|29,2,31|4393.97,104.17,-277.3|Build/Props
Part|Part|1|29,2,26|4364.97,112.58,-281.8|Build/Props
Part|Part|1|28,2,25|4336.47,110.13,-281.31|Build/Props
Part|Part|1|19,2,23|4861.91,106.58,-451.31|Build/Props
Part|Part|1|39,2,21|4728.97,112.53,-273.3|Build/Props
Part|Part|1|61,2,25|4392.91,110.58,-450.31|Build/Props
Part|Part|1|23,2,33|4483.97,109.6,-278.3|Build/Props
Part|Part|1|31,2,11|4456.97,104.57,-287.3|Build/Props
Part|Part|1|3,15,0.5|4386.97,95.67,-293.05|Build/Props
Part|Part|1|2,12,0.5|4704.47,98.09,-295.05|Build/Props
Part|Part|1|2,28,0.5|4272.97,94.58,-294.05|Build/Props
Part|Part|1|2,18,0.5|4473.41,95.58,-436.56|Build/Props
Part|Part|1|2,13,0.5|4972.04,97.53,-440.55|Build/Props
Part|Part|1|1,10,0.5|4503.91,108.58,-435.56|Build/Props
Part|Part|1|1,9,0.5|4877.91,108.08,-438.55|Build/Props
Part|Part|1|2,14,0.5|4942.41,97.58,-438.55|Build/Props
Part|Part|1|1,13,0.5|4911.97,91.08,-295.05|Build/Props
Part|Part|1|2,16,0.5|4887.41,97.58,-438.56|Build/Props
Part|Part|1|1,9,0.5|4623.97,96.8,-296.05|Build/Props
Part|Part|1|2,22,0.5|4455.41,104.58,-435.56|Build/Props
Part|Part|1|1,14,0.5|4934.97,93.36,-296.05|Build/Props
Part|Part|1|7,5,0.5|5099.97,110.08,-294.05|Build/Props
Part|Part|1|2,12,0.5|5091.04,98.03,-440.55|Build/Props
Part|Part|1|2,19,0.5|4796.41,100.08,-439.55|Build/Props
Part|Part|1|5,16,0.5|4317.91,97.58,-435.56|Build/Props
Part|Part|1|1,23,0.5|4586.91,105.08,-436.56|Build/Props
Part|Part|1|1,16,0.5|4821.91,93.58,-439.55|Build/Props
Part|Part|1|2,7,0.5|4911.47,101.08,-295.05|Build/Props
Part|Part|1|1,9,0.5|4846.91,88.08,-439.55|Build/Props
Part|Part|1|3,16,0.5|4741.04,96.03,-287.87|Build/Props
Part|Part|1|5,4,0.5|4717.94,78.12,-438.07|Build/Props
Part|Part|1|1,10,0.5|4920.97,99.58,-295.05|Build/Props
Part|Part|1|2,8,0.5|4766.47,97.07,-289.05|Build/Props
Part|Part|1|4,18,0.5|4400.41,98.58,-437.56|Build/Props
Part|Part|1|2,18,0.5|4637.47,103.58,-293.05|Build/Props
Part|Part|1|1,10,0.5|4752.97,97.07,-289.05|Build/Props
Part|Part|1|2,9,0.5|4846.41,97.08,-439.55|Build/Props
Part|Part|1|1,16,0.5|4573.91,100.58,-435.56|Build/Props
Part|Part|1|2,17,0.5|4880.47,94.08,-296.05|Build/Props
Part|Part|1|1,9,0.5|4595.97,113.54,-292.05|Build/Props
Part|Part|1|3,12,0.5|4661.41,108.68,-466.55|Build/Props
Part|Part|1|2,9,0.5|4895.47,109.08,-296.05|Build/Props
Part|Part|1|2,7,0.5|4358.41,95.08,-431.56|Build/Props
Part|Part|1|3,10,0.5|4601.91,111.58,-436.56|Build/Props
Part|Part|1|2,21,0.5|4651.41,104.18,-466.55|Build/Props
Part|Part|1|1,23,0.5|4370.97,100.08,-295.05|Build/Props
Part|Part|1|2,10,0.5|4618.41,96.58,-434.56|Build/Props
Part|Part|1|2,6,0.5|4561.47,105.43,-292.05|Build/Props
Part|Part|1|2,16,0.5|4480.47,100.6,-295.05|Build/Props
Part|Part|1|3,21,0.5|4611.97,90.8,-296.05|Build/Props
Part|Part|1|2,10,0.5|4769.41,95.58,-437.55|Build/Props
Part|Part|1|6,14,0.5|4658.47,99.58,-289.05|Build/Props
Part|Part|1|2,8,0.5|4412.41,105.58,-437.56|Build/Props
Part|Part|1|5,7,0.5|4511.97,99.61,-293.05|Build/Props
Part|Part|1|1,12,0.5|5021.91,87.58,-436.55|Build/Props
Part|Part|1|1,11,0.5|4435.02,87.53,-440.55|Build/Props
Part|Part|1|1,10,0.5|4991.91,102.58,-438.55|Build/Props
Part|Part|1|5,5,0.5|4727.04,101.53,-287.87|Build/Props
Part|Part|1|1,27,0.5|4509.91,100.08,-435.56|Build/Props
Part|Part|1|4,9,0.5|5073.47,101.08,-296.05|Build/Props
Part|Part|1|1,10,0.5|4454.91,88.58,-435.56|Build/Props
Part|Part|1|1,6,0.5|4930.91,101.58,-438.55|Build/Props
Part|Part|1|2,11,0.5|4786.47,85.08,-292.05|Build/Props
Part|Part|1|2,4,0.5|4599.41,99.58,-434.56|Build/Props
Part|Part|1|1,15,0.5|4280.91,84.08,-435.56|Build/Props
Part|Part|1|2,18,0.5|4494.41,104.58,-435.56|Build/Props
Part|Part|1|2,10,0.5|4370.41,93.58,-431.56|Build/Props
Part|Part|1|3,11,0.5|4786.97,96.08,-292.05|Build/Props
Part|Part|1|1,12,0.5|4809.91,103.58,-439.55|Build/Props
Part|Part|1|2,12,0.5|4360.41,109.58,-434.56|Build/Props
Part|Part|1|2,17,0.5|4804.47,93.08,-292.05|Build/Props
Part|Part|1|7,6,0.5|4351.91,112.58,-434.56|Build/Props
Part|Part|1|1,14,0.5|4900.91,103.58,-436.55|Build/Props
Part|Part|1|2,11,0.5|4434.52,98.53,-440.55|Build/Props
Part|Part|1|3,17,0.5|4291.91,104.08,-437.56|Build/Props
Part|Part|1|2,10,0.5|4753.47,107.07,-289.05|Build/Props
Part|Part|1|1,20,0.5|4337.97,99.13,-294.05|Build/Props
Part|Part|1|1,9,0.5|4894.97,100.08,-296.05|Build/Props
Part|Part|1|2,13,0.5|5083.47,99.08,-296.05|Build/Props
Part|Part|1|1,4,0.5|4654.25,82.2,-429.68|Build/Props
Part|Part|1|2,13,0.5|5002.47,87.03,-294.05|Build/Props
Part|Part|1|2,8,0.5|4842.47,88.58,-294.05|Build/Props
Part|Part|1|1,21,0.5|4335.91,105.08,-434.56|Build/Props
Part|Part|1|1,8,0.5|4271.91,95.58,-435.56|Build/Props
Part|Part|1|2,11,0.5|4358.47,106.08,-295.06|Build/Props
Part|Part|1|2,18,0.5|4545.47,99.43,-292.05|Build/Props
Part|Part|1|2,7,0.5|4667.03,76.62,-438.07|Build/Props
Part|Part|1|1,8,0.5|4766.97,89.07,-289.05|Build/Props
Part|Part|1|1,19,0.5|5002.91,98.08,-438.55|Build/Props
Part|Part|1|1,10,0.5|4321.97,87.01,-294.05|Build/Props
Part|Part|1|3,11,0.5|4387.91,104.08,-437.56|Build/Props
Part|Part|1|5,7,0.5|4981.97,90.03,-294.05|Build/Props
Part|Part|1|2,10,0.5|4321.47,97.01,-294.05|Build/Props
Part|Part|1|9,2,0.5|4397.91,108.58,-437.56|Build/Props
Part|Part|1|1,4,0.5|4720.09,82.2,-441.64|Build/Props
Part|Part|1|1,10,0.5|4636.97,89.58,-293.05|Build/Props
Part|Part|1|4,11,0.5|4766.47,106.57,-289.06|Build/Props
Part|Part|1|5,7,0.5|4886.91,109.08,-438.56|Build/Props
Part|Part|1|1,11,0.5|4616.97,107.08,-293.05|Build/Props
Part|Part|1|2,14,0.5|4526.41,85.58,-437.56|Build/Props
Part|Part|1|3,14,0.5|4657.97,85.58,-289.05|Build/Props
Part|Part|1|1,15,0.5|4284.91,92.08,-435.56|Build/Props
Part|Part|1|4,15,0.5|5115.47,92.08,-296.05|Build/Props
Part|Part|1|4,7,0.5|4525.52,100.53,-440.55|Build/Props
Part|Part|1|2,3,0.5|5017.47,97.08,-300.05|Build/Props
Part|Part|1|1,8,0.5|4842.97,80.58,-294.05|Build/Props
Part|Part|1|2,16,0.5|4863.41,97.58,-439.55|Build/Props
Part|Part|1|2,13,0.5|5050.47,97.47,-297.05|Build/Props
Part|Part|1|1,7,0.5|4552.02,100.53,-440.55|Build/Props
Part|Part|1|3,9,0.5|4717.94,71.62,-438.07|Build/Props
Part|Part|1|2,16,0.5|4444.47,95.57,-293.05|Build/Props
Part|Part|1|2,8,0.5|4280.41,95.58,-435.56|Build/Props
Part|Part|1|1,13,0.5|4522.97,106.73,-292.05|Build/Props
Part|Part|1|3,7,0.5|4307.91,102.08,-435.56|Build/Props
Part|Part|1|2,8,0.5|4704.44,76.12,-438.07|Build/Props
Part|Part|1|2,18,0.5|5022.41,102.58,-436.55|Build/Props
Part|Part|1|2,17,0.5|4640.41,96.08,-438.56|Build/Props
Part|Part|1|2,19,0.5|4584.47,108.54,-292.05|Build/Props
Part|Part|1|1,15,0.5|4270.91,92.08,-435.56|Build/Props
Part|Part|1|1,16,0.5|4500.97,95.11,-293.05|Build/Props
Part|Part|1|1,14,0.5|4602.97,94.3,-296.05|Build/Props
Part|Part|1|1,11,0.5|4445.91,110.08,-435.56|Build/Props
Part|Part|1|3,14,0.5|4339.91,108.58,-434.56|Build/Props
Part|Part|1|2,13,0.5|4387.41,92.08,-437.56|Build/Props
Part|Part|1|3,7,0.5|4982.97,83.03,-294.05|Build/Props
Part|Part|1|1,10,0.5|4489.97,103.6,-295.05|Build/Props
Part|Part|1|2,7,0.5|4540.41,89.08,-437.56|Build/Props
Part|Part|1|2,8,0.5|4911.41,106.58,-436.55|Build/Props
Part|Part|1|2,9,0.5|4401.47,98.67,-293.05|Build/Props
Part|Part|1|1,9,0.5|4483.91,100.08,-436.56|Build/Props
Part|Part|1|3,12,0.5|5114.91,102.58,-437.55|Build/Props
Part|Part|1|1,5,0.5|4682.53,77.62,-438.07|Build/Props
Part|Part|1|3,10,0.5|4753.91,107.58,-438.55|Build/Props
Part|Part|1|2,4,0.5|4688.59,82.2,-441.64|Build/Props
Part|Part|1|1,9,0.5|5029.97,94.08,-300.05|Build/Props
Part|Part|1|2,13,0.5|4284.47,102.08,-294.05|Build/Props
Part|Part|1|1,12,0.5|5051.91,96.58,-437.55|Build/Props
Part|Part|1|3,11,0.5|4879.97,108.08,-296.05|Build/Props
Part|Part|1|1,11,0.5|4863.97,87.08,-294.05|Build/Props
Part|Part|1|1,8,0.5|4692.97,100.09,-295.05|Build/Props
untitled|MeshPart|1|134.28,3.52,89.74|4337.82,65.82,-362.84|Build/Props
untitled|MeshPart|1|126.88,3.52,89.74|4460.85,65.82,-368.7|Build/Props
untitled|MeshPart|1|90.88,3.52,128.74|4719.56,65.82,-364.37|Build/Props
untitled|MeshPart|1|156.88,3.52,90.74|4840.32,65.82,-363.35|Build/Props
untitled|MeshPart|1|172.88,3.52,88.74|5006.7,65.82,-364.61|Build/Props
untitled|MeshPart|1|90.88,3.52,128.74|4600.35,65.82,-364.7|Build/Props
untitled|MeshPart|1|112.88,0.06,50.39|4826.05,67.66,-434.84|Build/Props
untitled|MeshPart|1|86.88,0.06,64.73|4670.96,67.61,-437.54|Build/Props
untitled|MeshPart|1|112.88,0.06,50.39|4993.95,67.66,-445.22|Build/Props
untitled|MeshPart|1|151.88,0.06,50.39|5039.91,67.66,-291.66|Build/Props
untitled|MeshPart|1|126.88,0.06,56.39|4537.44,67.61,-286.93|Build/Props
untitled|MeshPart|1|165.88,0.06,49.39|4842.74,67.66,-292.13|Build/Props
untitled|MeshPart|1|145.07,0.06,45.51|4336.55,67.61,-302.47|Build/Props
untitled|MeshPart|1|134.07,0.06,51.51|4331.05,67.61,-432.47|Build/Props
untitled|MeshPart|1|126.88,0.06,66.39|4519.56,67.61,-435.17|Build/Props
Meshes/untitled_Part3.008 (2)|MeshPart|1|54.18,2.41,63.53|4667.63,66.65,-438.33|Build/Props
Meshes/untitled_Part3.008 (2)|MeshPart|1|41.42,2.41,84.22|4983.38,66.65,-283.09|Build/Props
Meshes/untitled_Part3.008 (2)|MeshPart|1|66.06,2.41,45.51|4433.94,66.65,-438.77|Build/Props
Meshes/untitled_Part3.008 (2)|MeshPart|1|62.27,2.41,63.53|4722.2,66.65,-441.88|Build/Props
Meshes/untitled_Part3.008 (2)|MeshPart|1|48.52,2.41,71.21|4918.34,66.65,-448.37|Build/Props
Meshes/untitled_Part3.008 (2)|MeshPart|1|109.07,0.61,49.51|4347.53,67.51,-296.25|Build/Props
Meshes/untitled_Part3.008 (2)|MeshPart|1|66.06,2.41,45.51|4608.15,66.65,-441.32|Build/Props
Meshes/untitled_Part3.008 (2)|MeshPart|1|46.55,0.61,41.5|4290.69,67.65,-436.06|Build/Props
Meshes/untitled_Part3.008 (2)|MeshPart|1|93.07,0.61,53.51|4340.95,67.51,-436.77|Build/Props
Meshes/untitled_Part3.008 (2)|MeshPart|1|84.07,2.41,45.51|4630.96,66.65,-280.17|Build/Props
Meshes/untitled_Part3.008 (2)|MeshPart|1|38.42,2.41,89.22|4823.39,66.65,-291.22|Build/Props
Meshes/untitled_Part3.008 (2)|MeshPart|1|84.07,2.41,45.51|4823.96,66.65,-440.17|Build/Props
Meshes/untitled_Part3.008 (2)|MeshPart|1|41.42,2.41,84.22|4986.81,66.65,-446.27|Build/Props
Meshes/untitled_Part3.008 (2)|MeshPart|1|90.05,2.41,53.51|4512.34,66.65,-434.07|Build/Props
Meshes/untitled_Part3.008 (2)|MeshPart|1|51.07,0.61,50.51|5087.45,67.51,-447.77|Build/Props
Meshes/untitled_Part3.008 (2)|MeshPart|1|46.18,2.41,63.53|4540.72,66.65,-283.15|Build/Props
Part|Part|1|1,5.7,1|4451.5,72.16,-297.5|Build/Props
Part|Part|1|1,9.65,1|4797.5,72.4,-436.5|Build/Props
Part|Part|1|1,3.7,1|4971.73,69.53,-312.13|Build/Props
Part|Part|1|1,3.7,1|4447.5,69.43,-320.5|Build/Props
Part|Part|1|1,8.5,1|4749.5,72.83,-432.5|Build/Props
Part|Part|1|1,5.7,1|4862.5,70.16,-307.5|Build/Props
Part|Part|1|1,4.7,1|4972.5,69.66,-298.5|Build/Props
Part|Part|1|1,5.7,1|4460.5,72.16,-296.5|Build/Props
Part|Part|1|1,5.7,1|4417.5,70.43,-413.5|Build/Props
Part|Part|1|1,8.67,1|4552.5,72.91,-432.5|Build/Props
Part|Part|1|1,3.84,1|4449.5,69.49,-424.5|Build/Props
Part|Part|1|1,5.7,1|4661.91,70.43,-310.31|Build/Props
Part|Part|1|1,9.7,1|4960.5,72.16,-291.5|Build/Props
Part|Part|1|1,5,1|4410.5,70.81,-294.5|Build/Props
Part|Part|1|1,9.7,1|4455.5,74.16,-295.5|Build/Props
Part|Part|1|1,3.7,1|4755.5,69.43,-422.5|Build/Props
Part|Part|1|1,5.71,1|4588.5,70.71,-429.5|Build/Props
Part|Part|1|1,9.5,1|4643.5,72.6,-433.5|Build/Props
Part|Part|1|1,5.7,1|5026.5,70.16,-305.5|Build/Props
Part|Part|1|1,10,1|4332.5,73.31,-299.5|Build/Props
Part|Part|1|1,5.7,1|4518.5,71.16,-295.5|Build/Props
Part|Part|1|1,3.7,1|4426.5,69.43,-314.5|Build/Props
Part|Part|1|1,6.42,1|4548.88,71.79,-430.42|Build/Props
Part|Part|1|1,9.65,1|5068.5,72.4,-433.5|Build/Props
Part|Part|1|1,5.08,1|4460.5,70.12,-417.5|Build/Props
Part|Part|1|1,6.7,1|4586.5,70.66,-296.5|Build/Props
Part|Part|1|1,6.27,1|4641.21,70.99,-430.34|Build/Props
Part|Part|1|1,6.7,1|4668.5,70.66,-289.5|Build/Props
Part|Part|1|1,4.7,1|4660.5,69.93,-314.5|Build/Props
Part|Part|1|1,4.7,1|4673.5,69.66,-293.5|Build/Props
Part|Part|1|1,9.7,1|4769.5,72.16,-294.5|Build/Props
Part|Part|1|1,5.65,1|4851.5,70.4,-435.5|Build/Props
Part|Part|1|1,5.5,1|4918.5,71.33,-428.5|Build/Props
Part|Part|1|1,5,1|4335.5,70.81,-301.5|Build/Props
Part|Part|1|1,3.7,1|4413.5,69.43,-410.5|Build/Props
Part|Part|1|1,10,1|4304.91,73.31,-425.31|Build/Props
Part|Part|1|1,9.7,1|4869.5,72.16,-296.5|Build/Props
Part|Part|1|1,7,1|4416.5,71.81,-291.5|Build/Props
Part|Part|1|1,6.7,1|5084.5,71.93,-299|Build/Props
Part|Part|1|1,5.65,1|4847.5,70.4,-428.5|Build/Props
Part|Part|1|1,3.5,1|4585.5,69.6,-423.5|Build/Props
Part|Part|1|1,7.7,1|4776.5,71.16,-297.5|Build/Props
Part|Part|1|1,5.65,1|4302.5,71.13,-426.5|Build/Props
Part|Part|1|1,6.7,1|5018.5,70.66,-303.5|Build/Props
Part|Part|1|1,4.7,1|5089.5,70.93,-297.5|Build/Props
Part|Part|1|1,4.7,1|4508.5,69.66,-295.5|Build/Props
Part|Part|1|1,7.7,1|4465.5,71.43,-419.5|Build/Props
Part|Part|1|1,7.7,1|4409.5,72.16,-433.5|Build/Props
Part|Part|1|1,5.65,1|4280.5,71.13,-432.5|Build/Props
Part|Part|1|1,4.7,1|4514.5,69.66,-298.5|Build/Props
Part|Part|1|1,3.65,1|5064.5,69.4,-431.5|Build/Props
Part|Part|1|1,9.7,1|5024.5,72.16,-301.5|Build/Props
Part|Part|1|1,2.7,1|4428.5,68.93,-317.5|Build/Props
Part|Part|1|1,5.65,1|5071.5,70.4,-433.5|Build/Props
Part|Part|1|1,6.5,1|4746.5,71.83,-429.5|Build/Props
Part|Part|1|1,9.65,1|4348.5,73.13,-432.5|Build/Props
Part|Part|1|1,8.5,1|4922.5,72.83,-429.5|Build/Props
Part|Part|1|1,7.7,1|4978.5,71.16,-296.5|Build/Props
Part|Part|1|1,5.7,1|4756.5,70.43,-426.5|Build/Props
Part|Part|1|1,2.7,1|4883.5,68.93,-414.5|Build/Props
Part|Part|1|1,10,1|4377.5,73.31,-429.5|Build/Props
Part|Part|1|1,3.5,1|4484.78,69.6,-427.46|Build/Props
Part|Part|1|1,4.7,1|4886.5,69.93,-413.5|Build/Props
Part|Part|1|1,9.65,1|4523.5,73.4,-433.5|Build/Props
Part|Part|1|1,7.65,1|4343.5,71.64,-431.5|Build/Props
Part|Part|1|1,5.7,1|4444.5,70.43,-315.5|Build/Props
Part|Part|1|1,5.65,1|4800.5,70.4,-433.5|Build/Props
Part|Part|1|1,5.7,1|4855.5,70.16,-304.5|Build/Props
Part|Part|1|1,4.65,1|4991.5,69.9,-433.5|Build/Props
Part|Part|1|3.09,0.56,2.49|4550.76,83.7,-303.26|Build/Props
Part|Part|1|3.09,0.56,3.51|4549.15,84.73,-298.26|Build/Props
Part|Part|1|3.09,0.56,2.94|4549.99,84.49,-300.81|Build/Props
Part|Part|1|3.09,0.56,1.66|4551.31,81.66,-305.26|Build/Props
Part|Part|1|1.64,0.56,4.05|4548.5,84.06,-296.41|Build/Props
Part|Part|1|1.64,0.56,2.65|4548.06,83.38,-295.2|Build/Props
Part|Part|1|3.07,0.56,4.31|4544.76,83.23,-293.83|Build/Props
Part|Part|1|3.09,0.56,3.86|4539.65,84.16,-295.04|Build/Props
Part|Part|1|3.09,0.56,2.99|4537.16,83.4,-295.69|Build/Props
Part|Part|1|3.09,0.56,5.2|4542.27,84.37,-294.39|Build/Props
Part|Part|1|3.09,0.56,4.63|4552.14,83.01,-295.6|Build/Props
Part|Part|1|1.64,0.56,5.18|4550.32,82.46,-294.8|Build/Props
Part|Part|1|3.09,0.56,3.62|4556.82,81.7,-297.87|Build/Props
Part|Part|1|1.64,0.56,3.78|4549.1,81.85,-294.29|Build/Props
Part|Part|1|3.09,0.56,4.07|4554.56,82.64,-296.75|Build/Props
Part|Part|1|3.09,0.56,2.79|4558.53,79.56,-298.82|Build/Props
Part|Part|1|3.09,0.56,2.86|4543.71,82.85,-300.91|Build/Props
Part|Part|1|3.09,0.56,4.19|4544.91,83.4,-298.56|Build/Props
Part|Part|1|3.07,0.56,3.31|4546.13,82.61,-296.17|Build/Props
Part|Part|1|3.09,0.56,1.99|4542.58,81.75,-303.09|Build/Props
Part|Part|1|2.54,5.77,2.54|4547.09,71.99,-292.91|Build/Props
Part|Part|1|3.32,2.34,3.32|4547.47,81.67,-293.42|Build/Props
Part|Part|1|2.64,3.84,2.64|4547.47,81.67,-293.42|Build/Props
Part|Part|1|3,4,3|4547.22,69.58,-292.35|Build/Props
Part|Part|1|2.05,5.86,2.05|4547.17,77.33,-293.24|Build/Props
Part|Part|1|3.09,0.56,2.32|4396.02,78.86,-439.56|Build/Props
Part|Part|1|3.09,0.56,3.61|4395.31,81.75,-435.01|Build/Props
Part|Part|1|3.09,0.56,3.16|4395.71,80.92,-437.53|Build/Props
Part|Part|1|3.09,0.56,4.17|4394.88,82.02,-432.36|Build/Props
Part|Part|1|3.09,0.56,3.86|4401.85,83.14,-431.8|Build/Props
Part|Part|1|3.09,0.56,2.99|4404.28,82.17,-432.41|Build/Props
Part|Part|1|3.07,0.56,4.31|4396.72,82.64,-430.42|Build/Props
Part|Part|1|3.09,0.56,5.2|4399.27,83.57,-431.13|Build/Props
Part|Part|1|3.09,0.56,1.99|4397.8,81.01,-419.52|Build/Props
Part|Part|1|3.09,0.56,2.86|4396.96,82.19,-421.79|Build/Props
Part|Part|1|3.09,0.56,4.19|4396.04,82.84,-424.24|Build/Props
Part|Part|1|3.07,0.56,3.31|4395.03,82.14,-426.76|Build/Props
Part|Part|1|3.09,0.56,3.62|4384.19,81.79,-426.17|Build/Props
Part|Part|1|3.09,0.56,4.63|4389.14,82.87,-427.92|Build/Props
Part|Part|1|3.09,0.56,4.07|4386.6,82.61,-427.03|Build/Props
Part|Part|1|1.64,0.56,5.18|4391,82.22,-428.54|Build/Props
Part|Part|1|1.64,0.56,3.78|4392.23,81.56,-428.94|Build/Props
Part|Part|1|3.09,0.56,2.79|4382.28,79.73,-425.43|Build/Props
Part|Part|1|1.64,0.56,2.65|4393.26,83.02,-427.9|Build/Props
Part|Part|1|3.09,0.56,1.66|4388.9,81.37,-418.25|Build/Props
Part|Part|1|3.09,0.56,2.49|4389.76,83.4,-420.15|Build/Props
Part|Part|1|3.09,0.56,3.51|4391.92,84.39,-424.95|Build/Props
Part|Part|1|3.09,0.56,2.94|4390.81,84.18,-422.5|Build/Props
Part|Part|1|1.64,0.56,4.05|4392.73,83.71,-426.73|Build/Props
Part|Part|1|3.09,0.56,4.19|4390.05,81.42,-433.44|Build/Props
Part|Part|1|3.07,0.56,3.31|4392.03,81.87,-431.51|Build/Props
Part|Part|1|3.09,0.56,2.86|4388.47,79.77,-434.88|Build/Props
Part|Part|1|3.09,0.56,1.99|4387.16,77.71,-436.01|Build/Props
Part|Part|1|3,4,3|4393.66,69.22,-430.87|Build/Props
Part|Part|1|2.54,5.77,2.54|4393.85,71.63,-430.26|Build/Props
Part|Part|1|2.64,3.84,2.64|4393.93,81.3,-429.64|Build/Props
Part|Part|1|2.05,5.86,2.05|4394.02,76.95,-429.86|Build/Props
Part|Part|1|3.32,2.34,3.32|4393.93,81.3,-429.64|Build/Props
Part|Part|1|11.35,2.04,7.29|4497.06,165.22,-476.61|Build/Props
Part|Part|1|11.35,2.04,15.4|4511.87,168.55,-464.11|Build/Props
Part|Part|1|11.35,2.04,10.5|4504.13,167.88,-470.27|Build/Props
Part|Part|1|11.26,2.04,12.15|4520,164.47,-459.35|Build/Props
Part|Part|1|11.35,2.04,12.87|4521.7,167.79,-471.38|Build/Props
Part|Part|1|11.35,2.04,10.8|4518.87,168.59,-480.85|Build/Props
Part|Part|1|11.35,2.04,9.14|4516.45,167.32,-490.32|Build/Props
Part|Part|1|6.02,2.04,9.72|4525.9,161.03,-461.24|Build/Props
Part|Part|1|6.02,2.04,14.85|4524.16,164.23,-465.14|Build/Props
Part|Part|1|11.35,2.04,6.09|4515.16,161.32,-499.06|Build/Props
Part|Part|1|11.35,2.04,13.28|4554.66,150.74,-429.11|Build/Props
Part|Part|1|11.35,2.04,14.94|4547.88,154.88,-434.94|Build/Props
Part|Part|1|11.35,2.04,17.01|4540.96,157.1,-441.67|Build/Props
Part|Part|1|11.35,2.04,10.23|4560.6,142.5,-425.83|Build/Props
Part|Part|1|6.02,2.04,13.86|4533.15,154.07,-451.47|Build/Props
Part|Part|1|6.02,2.04,18.99|4536.19,155.79,-447.44|Build/Props
Part|Part|1|11.35,2.04,9.14|4565.87,161.71,-454.85|Build/Props
Part|Part|1|11.35,2.04,10.8|4556.26,163.8,-454.21|Build/Props
Part|Part|1|11.35,2.04,12.87|4546.35,163.87,-454.09|Build/Props
Part|Part|1|6.02,2.04,9.72|4534.86,158.18,-455.46|Build/Props
Part|Part|1|6.02,2.04,14.85|4539.37,160.96,-454.78|Build/Props
Part|Part|1|11.35,2.04,6.09|4574.03,155.06,-456.66|Build/Props
Part|Part|1|11.35,2.04,10.5|4523.97,158.72,-425.84|Build/Props
Part|Part|1|11.35,2.04,7.29|4523.34,153.09,-417.77|Build/Props
Part|Part|1|11.26,2.04,12.15|4526.39,161.52,-445.05|Build/Props
Part|Part|1|11.35,2.04,15.4|4524.9,162.53,-434.94|Build/Props
Part|Part|1|11.26,2.04,12.15|4533.74,166.36,-460.11|Build/Props
Part|Part|1|11.35,2.04,15.4|4539.91,172.41,-465.68|Build/Props
Part|Part|1|11.35,2.04,10.5|4546.82,173.76,-472.64|Build/Props
Part|Part|1|11.35,2.04,7.29|4553.61,173.01,-479.75|Build/Props
Part|Part|1|11.35,2.04,8.53|4485.02,142.58,-450.9|Build/Props
Part|Part|1|11.35,2.04,13.24|4499.89,155.88,-450.56|Build/Props
Part|Part|1|11.35,2.04,15.3|4509.33,158.66,-451.7|Build/Props
Part|Part|1|6.02,2.04,17.29|4516.69,157.76,-453.31|Build/Props
Part|Part|1|11.35,2.04,11.58|4491.21,151.23,-450.02|Build/Props
Part|Part|1|6.02,2.04,12.15|4521.67,156.32,-454.61|Build/Props
Part|Part|1|6.24,17.81,6.24|4529.75,144.81,-458.88|Build/Props
Part|Part|1|10.08,7.1,10.08|4528.19,157.53,-455.56|Build/Props
Part|Part|1|8.03,11.69,8.03|4528.19,157.53,-455.56|Build/Props
Part|Part|1|7.74,24.59,7.74|4531.94,125.5,-462.48|Build/Props
Part|Part|1|9.12,18.24,9.12|4532.92,105.04,-463.66|Build/Props
Part|Part|1|4.3,0.77,3.98|4926.54,97.05,-303.83|Build/Props
Part|Part|1|4.27,0.77,4.6|4923.01,94.25,-309.71|Build/Props
Part|Part|1|4.3,0.77,2.76|4928.6,96.77,-300.72|Build/Props
Part|Part|1|4.3,0.77,5.83|4924.55,96.54,-306.97|Build/Props
Part|Part|1|4.3,0.77,3.46|4918.37,92.49,-298.29|Build/Props
Part|Part|1|4.3,0.77,4.87|4919.73,93.31,-305.56|Build/Props
Part|Part|1|2.28,0.77,5.62|4920.57,92.21,-308.08|Build/Props
Part|Part|1|2.28,0.77,3.68|4921.2,91.16,-309.69|Build/Props
Part|Part|1|4.3,0.77,4.09|4918.94,93.28,-301.89|Build/Props
Part|Part|1|4.3,0.77,2.31|4918.36,89.97,-295.12|Build/Props
Part|Part|1|4.3,0.77,4.09|4931.92,95.1,-313.46|Build/Props
Part|Part|1|2.28,0.77,5.62|4925.68,93.45,-312.83|Build/Props
Part|Part|1|4.3,0.77,2.31|4938.95,92.35,-313.3|Build/Props
Part|Part|1|4.3,0.77,4.87|4928.19,94.79,-313.21|Build/Props
Part|Part|1|2.28,0.77,3.68|4924.09,92.23,-312.51|Build/Props
Part|Part|1|4.3,0.77,3.46|4935.62,94.62,-313.56|Build/Props
Part|Part|1|2.28,0.77,5.25|4919.87,89.6,-310.65|Build/Props
Part|Part|1|4.3,0.77,5.66|4912.53,89.9,-306.6|Build/Props
Part|Part|1|4.3,0.77,6.44|4915.6,90.75,-308.59|Build/Props
Part|Part|1|4.3,0.77,3.88|4908.1,85.22,-302.67|Build/Props
Part|Part|1|2.28,0.77,7.19|4918.13,90.25,-309.87|Build/Props
Part|Part|1|4.3,0.77,5.03|4909.81,88.34,-304.59|Build/Props
Part|Part|1|4.3,0.77,5.8|4921.96,91.34,-319.43|Build/Props
Part|Part|1|4.3,0.77,3.23|4923.7,85.25,-328.47|Build/Props
Part|Part|1|2.28,0.77,6.55|4921.93,91,-316.58|Build/Props
Part|Part|1|4.3,0.77,4.39|4922.86,88.52,-326.26|Build/Props
Part|Part|1|4.3,0.77,5.01|4922.33,90.28,-323.01|Build/Props
Part|Part|1|2.28,0.77,4.6|4921.99,90.45,-314.63|Build/Props
Part|Part|1|4.3,0.77,2.76|4908.25,89.23,-317.11|Build/Props
Part|Part|1|4.3,0.77,5.83|4914.46,92.8,-315.09|Build/Props
Part|Part|1|4.3,0.77,3.98|4911.18,91.36,-316.2|Build/Props
Part|Part|1|4.27,0.77,4.6|4918.07,92.42,-313.69|Build/Props
Part|Part|1|4.3,0.77,3.98|4929.25,94.83,-319.79|Build/Props
Part|Part|1|4.3,0.77,2.76|4932.18,93.82,-321.87|Build/Props
Part|Part|1|4.27,0.77,4.6|4923.88,93.54,-314.85|Build/Props
Part|Part|1|4.3,0.77,5.83|4926.33,95.08,-317.45|Build/Props
Part|Part|1|2.36,6.75,2.36|4922.89,86.09,-311.29|Build/Props
Part|Part|1|2.93,9.31,2.93|4924.04,78.78,-310.17|Build/Props
Part|Part|1|3.45,6.91,3.45|4924.39,71.03,-309.71|Build/Props
Part|Part|1|3.04,4.43,3.04|4921.8,90.91,-312.14|Build/Props
Part|Part|1|3.82,2.69,3.82|4921.8,90.91,-312.14|Build/Props
Part|Part|1|11.35,2.04,15.4|4941.69,165.49,-466.18|Build/Props
Part|Part|1|11.26,2.04,12.15|4942.75,157.22,-460.16|Build/Props
Part|Part|1|11.35,2.04,10.5|4939.9,169.7,-474.97|Build/Props
Part|Part|1|11.35,2.04,7.29|4937.91,171.9,-484.37|Build/Props
Part|Part|1|11.26,2.04,12.15|4950.95,148.18,-447.7|Build/Props
Part|Part|1|11.35,2.04,15.4|4958.42,147.03,-440.74|Build/Props
Part|Part|1|11.35,2.04,10.5|4965.37,141.59,-436.23|Build/Props
Part|Part|1|11.35,2.04,7.29|4971.65,134.68,-433.07|Build/Props
Part|Part|1|11.35,2.04,9.14|4965.36,159.89,-483.89|Build/Props
Part|Part|1|11.35,2.04,10.8|4960.42,159.38,-475.38|Build/Props
Part|Part|1|6.02,2.04,14.85|4950.34,152.56,-463.32|Build/Props
Part|Part|1|11.35,2.04,12.87|4954.88,156.95,-467.53|Build/Props
Part|Part|1|6.02,2.04,9.72|4947.22,148.91,-460.99|Build/Props
Part|Part|1|11.35,2.04,6.09|4968.52,155.91,-493.28|Build/Props
Part|Part|1|11.35,2.04,10.23|4986.23,135.27,-469.85|Build/Props
Part|Part|1|11.35,2.04,14.94|4971.5,145.46,-461.07|Build/Props
Part|Part|1|11.35,2.04,17.01|4962.02,147.02,-458.62|Build/Props
Part|Part|1|11.35,2.04,13.28|4980.16,142.21,-464.47|Build/Props
Part|Part|1|6.02,2.04,18.99|4954.57,145.58,-458.42|Build/Props
Part|Part|1|6.02,2.04,13.86|4949.52,143.88,-458.74|Build/Props
Part|Part|1|11.35,2.04,15.3|4935.77,142.35,-438.81|Build/Props
Part|Part|1|6.02,2.04,17.29|4938.64,143.61,-445.73|Build/Props
Part|Part|1|11.35,2.04,8.53|4922.6,120.83,-424.21|Build/Props
Part|Part|1|6.02,2.04,12.15|4940.41,143.69,-450.76|Build/Props
Part|Part|1|11.35,2.04,13.24|4931.34,137.15,-431.63|Build/Props
Part|Part|1|11.35,2.04,11.58|4926.85,130.46,-425.96|Build/Props
Part|Part|1|11.26,2.04,12.15|4935.56,151.87,-449.56|Build/Props
Part|Part|1|11.35,2.04,10.5|4917.55,153.04,-442.01|Build/Props
Part|Part|1|11.35,2.04,7.29|4908.31,149.84,-440.72|Build/Props
Part|Part|1|11.35,2.04,15.4|4927.01,154.55,-444.53|Build/Props
Part|Part|1|11.35,2.04,12.87|4926.63,157.53,-456.41|Build/Props
Part|Part|1|6.02,2.04,9.72|4937.36,150.38,-456.25|Build/Props
Part|Part|1|11.35,2.04,10.8|4917.24,159.22,-459.08|Build/Props
Part|Part|1|11.35,2.04,6.09|4900.16,154.52,-468.26|Build/Props
Part|Part|1|6.02,2.04,14.85|4933.16,153.68,-456.03|Build/Props
Part|Part|1|11.35,2.04,9.14|4908.08,159.04,-462.71|Build/Props
Part|Part|1|7.74,24.59,7.74|4939.78,118.25,-472.43|Build/Props
Part|Part|1|9.12,18.24,9.12|4939.37,99.2,-480.04|Build/Props
Part|Part|1|10.08,7.1,10.08|4943.34,146.64,-456.02|Build/Props
Part|Part|1|8.03,11.69,8.03|4943.34,146.64,-456.02|Build/Props
Part|Part|1|6.24,17.81,6.24|4941.5,135.49,-462.91|Build/Props
Part|Part|1|4.71,2.14,4.71|4947.78,94.73,-438.85|Build/Props
Part|Part|1|5.38,1.72,6.17|4949.34,96.02,-437.27|Build/Props
Part|Part|1|3.87,1.08,4.4|4951.05,97.46,-435.53|Build/Props
Part|Part|1|6.56,1.18,3.52|4338.27,168.25,-473.87|Build/Props
Part|Part|1|6.56,1.18,6.24|4336.88,172.44,-463.23|Build/Props
Part|Part|1|3.48,1.18,5.61|4337.03,168.08,-451.2|Build/Props
Part|Part|1|3.48,1.18,8.58|4336.82,169.93,-453.66|Build/Props
Part|Part|1|6.56,1.18,5.28|4337.33,171.71,-468.86|Build/Props
Part|Part|1|6.56,1.18,7.43|4336.65,171.98,-457.53|Build/Props
Part|Part|1|6.56,1.18,6.06|4329.33,166.74,-432.23|Build/Props
Part|Part|1|6.56,1.18,4.21|4327.48,163.49,-427.94|Build/Props
Part|Part|1|6.5,1.18,7.02|4334.26,168.36,-442.27|Build/Props
Part|Part|1|6.56,1.18,8.89|4331.55,168.95,-437.03|Build/Props
Part|Part|1|6.56,1.18,4.21|4324.17,170.5,-465.01|Build/Props
Part|Part|1|6.56,1.18,6.06|4326.84,172.03,-460.22|Build/Props
Part|Part|1|6.56,1.18,8.89|4329.91,172.42,-455.41|Build/Props
Part|Part|1|6.5,1.18,7.02|4333.46,170.06,-451.28|Build/Props
Part|Part|1|6.56,1.18,4.93|4312.77,157.42,-453.23|Build/Props
Part|Part|1|6.56,1.18,8.84|4326.19,166.71,-449.1|Build/Props
Part|Part|1|6.56,1.18,7.65|4320.82,165.11,-450.25|Build/Props
Part|Part|1|3.48,1.18,9.99|4330.52,166.19,-448.6|Build/Props
Part|Part|1|3.48,1.18,7.02|4333.48,165.36,-448.37|Build/Props
Part|Part|1|6.56,1.18,6.69|4315.99,162.42,-451.59|Build/Props
Part|Part|1|6.56,1.18,9.82|4341.59,165.81,-437.69|Build/Props
Part|Part|1|6.56,1.18,8.63|4344.1,164.52,-432.71|Build/Props
Part|Part|1|6.56,1.18,7.67|4346.71,162.14,-428.25|Build/Props
Part|Part|1|6.56,1.18,5.91|4349.34,157.38,-425.35|Build/Props
Part|Part|1|3.48,1.18,10.97|4340.07,165.05,-441.73|Build/Props
Part|Part|1|3.48,1.18,8|4339.16,164.06,-444.51|Build/Props
Part|Part|1|6.56,1.18,7.43|4346.86,169.72,-443.46|Build/Props
Part|Part|1|6.56,1.18,6.24|4352.29,169.68,-441.67|Build/Props
Part|Part|1|3.48,1.18,5.61|4340.84,166.43,-446.36|Build/Props
Part|Part|1|3.48,1.18,8.58|4343.18,168.04,-445.15|Build/Props
Part|Part|1|6.56,1.18,3.52|4362.46,164.63,-439.67|Build/Props
Part|Part|1|6.56,1.18,5.28|4357.67,168.47,-440.21|Build/Props
Part|Part|1|6.5,1.18,7.02|4341.1,171.16,-449.12|Build/Props
Part|Part|1|6.56,1.18,8.89|4345.52,174.65,-451|Build/Props
Part|Part|1|6.56,1.18,6.06|4350.6,175.43,-453.5|Build/Props
Part|Part|1|6.56,1.18,4.21|4355.64,175,-456.11|Build/Props
Part|Part|1|5.82,4.1,5.82|4337.22,166.06,-447.67|Build/Props
Part|Part|1|3.6,10.29,3.6|4338.7,158.71,-449.19|Build/Props
Part|Part|1|4.47,14.2,4.47|4340.57,147.56,-450.75|Build/Props
Part|Part|1|5.27,10.53,5.27|4341.33,135.74,-451.21|Build/Props
Part|Part|1|4.64,6.75,4.64|4337.22,166.06,-447.67|Build/Props
Part|Part|1|5.38,1.72,6.17|4352.2,87.9,-431.8|Build/Props
Part|Part|1|3.87,1.08,4.4|4349.88,89.27,-430.92|Build/Props
Part|Part|1|4.71,2.14,4.71|4354.31,86.68,-432.6|Build/Props
Part|Part|1|4.71,2.14,4.71|4419.62,103.68,-292.02|Build/Props
Part|Part|1|3.87,1.08,4.4|4424.05,106.27,-293.7|Build/Props
Part|Part|1|5.38,1.72,6.17|4421.72,104.91,-292.82|Build/Props
Part|Part|1|3.73,0.67,5.06|4746.46,89.49,-414.42|Build/Props
Part|Part|1|3.73,0.67,2.4|4744.14,86.38,-409.24|Build/Props
Part|Part|1|3.73,0.67,3.45|4745.2,88.24,-411.68|Build/Props
Part|Part|1|3.71,0.67,4|4748.01,89.16,-417.4|Build/Props
Part|Part|1|3.73,0.67,3.45|4743.78,91.25,-427.63|Build/Props
Part|Part|1|3.71,0.67,4|4747.55,90.13,-422.53|Build/Props
Part|Part|1|3.73,0.67,5.06|4745.53,91.47,-424.89|Build/Props
Part|Part|1|3.73,0.67,2.4|4742.26,90.37,-430.36|Build/Props
Part|Part|1|3.73,0.67,3.37|4756.6,82.9,-407.76|Build/Props
Part|Part|1|1.98,0.67,4.56|4750.8,86.71,-418.68|Build/Props
Part|Part|1|3.73,0.67,4.37|4755.1,85.61,-409.42|Build/Props
Part|Part|1|1.98,0.67,6.25|4751.31,87.27,-417.1|Build/Props
Part|Part|1|3.73,0.67,5.59|4752.18,87.7,-414.79|Build/Props
Part|Part|1|3.73,0.67,4.92|4753.61,86.97,-411.96|Build/Props
Part|Part|1|3.73,0.67,2.81|4735.76,82.92,-423.65|Build/Props
Part|Part|1|3.73,0.67,5.03|4743.41,88.22,-421.3|Build/Props
Part|Part|1|3.73,0.67,4.36|4740.35,87.3,-421.95|Build/Props
Part|Part|1|1.98,0.67,4|4747.56,87.45,-420.88|Build/Props
Part|Part|1|3.73,0.67,3.81|4737.6,85.77,-422.71|Build/Props
Part|Part|1|1.98,0.67,5.69|4745.88,87.92,-421.01|Build/Props
Part|Part|1|1.98,0.67,3.2|4751.76,88.06,-419.73|Build/Props
Part|Part|1|3.73,0.67,4.23|4755.19,89.93,-418.08|Build/Props
Part|Part|1|3.73,0.67,3.55|4758.28,89.91,-417.06|Build/Props
Part|Part|1|3.73,0.67,3.01|4761.34,89.22,-416.23|Build/Props
Part|Part|1|1.98,0.67,4.89|4753.09,88.97,-419.04|Build/Props
Part|Part|1|3.73,0.67,2|4764.07,87.03,-415.92|Build/Props
Part|Part|1|3.73,0.67,5.06|4754.42,92.74,-422.37|Build/Props
Part|Part|1|3.71,0.67,4|4751.91,90.75,-421.3|Build/Props
Part|Part|1|3.73,0.67,3.45|4757.32,93.18,-423.8|Build/Props
Part|Part|1|3.73,0.67,2.4|4760.19,92.94,-425.29|Build/Props
Part|Part|1|3.73,0.67,4.23|4749.37,91.22,-426.1|Build/Props
Part|Part|1|3.73,0.67,3.55|4749.5,91.48,-429.34|Build/Props
Part|Part|1|1.98,0.67,4.89|4749.46,90.05,-423.89|Build/Props
Part|Part|1|3.73,0.67,2|4750.29,89.09,-435.41|Build/Props
Part|Part|1|1.98,0.67,3.2|4749.59,89,-422.49|Build/Props
Part|Part|1|3.73,0.67,3.01|4749.76,91.06,-432.55|Build/Props
Part|Part|1|3,6,3|4752.03,70.58,-422.5|Build/Props
Part|Part|1|2.05,5.86,2.05|4750.53,83.66,-421.35|Build/Props
Part|Part|1|2.64,3.84,2.64|4749.69,87.85,-420.48|Build/Props
Part|Part|1|3.32,2.34,3.32|4749.69,87.85,-420.48|Build/Props
Part|Part|1|2.54,8.09,2.54|4751.6,77.31,-422.23|Build/Props
Part|Part|1|9.06,1.63,7.3|4457.81,156.42,-263.59|Build/Props
Part|Part|1|9.06,1.63,8.63|4450.04,157.43,-264.21|Build/Props
Part|Part|1|4.81,1.63,11.86|4436.81,153.95,-264.29|Build/Props
Part|Part|1|9.06,1.63,10.27|4442.16,156.79,-264.53|Build/Props
Part|Part|1|9.06,1.63,4.86|4464.75,151.63,-262.29|Build/Props
Part|Part|1|4.81,1.63,7.76|4433.41,151.4,-264|Build/Props
Part|Part|1|9.06,1.63,11.93|4407.85,146.48,-254.23|Build/Props
Part|Part|1|4.81,1.63,15.16|4420.32,147.22,-259.8|Build/Props
Part|Part|1|9.06,1.63,10.6|4401.68,143.19,-250.62|Build/Props
Part|Part|1|9.06,1.63,13.58|4414.73,148.26,-257.7|Build/Props
Part|Part|1|4.81,1.63,11.06|4424.15,145.84,-261.06|Build/Props
Part|Part|1|9.06,1.63,8.17|4397.67,136.6,-246.98|Build/Props
Part|Part|1|9.06,1.63,8.38|4445.87,156.87,-278.09|Build/Props
Part|Part|1|8.99,1.63,9.7|4433.51,154.14,-268.94|Build/Props
Part|Part|1|9.06,1.63,12.29|4439.22,157.4,-273.84|Build/Props
Part|Part|1|9.06,1.63,5.82|4452.49,154.74,-281.78|Build/Props
Part|Part|1|9.06,1.63,10.27|4422.71,153.66,-250.41|Build/Props
Part|Part|1|4.81,1.63,11.86|4425.04,151.34,-255.5|Build/Props
Part|Part|1|4.81,1.63,7.76|4426.72,149.12,-258.73|Build/Props
Part|Part|1|9.06,1.63,7.3|4418.22,151.94,-235.48|Build/Props
Part|Part|1|9.06,1.63,8.63|4420.23,153.61,-242.9|Build/Props
Part|Part|1|9.06,1.63,4.86|4417.46,146.63,-228.85|Build/Props
Part|Part|1|4.81,1.63,13.8|4429.81,148.79,-273|Build/Props
Part|Part|1|9.06,1.63,6.81|4436.21,136.67,-297.54|Build/Props
Part|Part|1|9.06,1.63,9.24|4433.94,143.57,-293.09|Build/Props
Part|Part|1|9.06,1.63,12.22|4430.51,149.51,-278.98|Build/Props
Part|Part|1|9.06,1.63,10.57|4432.1,147.29,-286.41|Build/Props
Part|Part|1|4.81,1.63,9.7|4429.5,147.63,-268.91|Build/Props
Part|Part|1|9.06,1.63,8.38|4436.59,161.56,-245.24|Build/Props
Part|Part|1|9.06,1.63,5.82|4440.2,160.96,-238.27|Build/Props
Part|Part|1|9.06,1.63,12.29|4433.12,160.48,-252.27|Build/Props
Part|Part|1|8.99,1.63,9.7|4430.52,155.65,-258.37|Build/Props
Part|Part|1|9.06,1.63,12.29|4413.81,152.6,-271.58|Build/Props
Part|Part|1|8.99,1.63,9.7|4421.06,151.79,-267.83|Build/Props
Part|Part|1|9.06,1.63,5.82|4401.25,145.06,-277.21|Build/Props
Part|Part|1|9.06,1.63,8.38|4407.18,149.55,-274.64|Build/Props
Part|Part|1|8.05,5.67,8.05|4428.53,148.61,-263.74|Build/Props
Part|Part|1|6.41,9.33,6.41|4428.53,148.61,-263.74|Build/Props
Part|Part|1|6.18,19.63,6.18|4432.78,123.04,-259.11|Build/Props
Part|Part|1|7.28,14.56,7.28|4433.42,106.7,-258.06|Build/Props
Part|Part|1|4.98,14.22,4.98|4430.63,138.45,-261.7|Build/Props
Part|Part|1|5.46,1.85,12.56|4849.79,149.48,-275.65|Build/Props
Part|Part|1|10.29,1.85,9.28|4828.23,131.11,-297.28|Build/Props
Part|Part|1|5.46,1.85,17.22|4847.34,149.78,-279.82|Build/Props
Part|Part|1|10.29,1.85,15.42|4843.53,149.17,-285.52|Build/Props
Part|Part|1|10.29,1.85,13.55|4838.09,145.08,-291.38|Build/Props
Part|Part|1|10.29,1.85,12.04|4832.79,139.55,-295.97|Build/Props
Part|Part|1|10.29,1.85,9.79|4828.18,156.72,-277.43|Build/Props
Part|Part|1|5.46,1.85,8.81|4847.63,153.86,-273.32|Build/Props
Part|Part|1|5.46,1.85,13.46|4843.47,155.76,-274.93|Build/Props
Part|Part|1|10.29,1.85,11.66|4837.1,157.56,-276.78|Build/Props
Part|Part|1|10.29,1.85,8.29|4819.59,154.27,-277.11|Build/Props
Part|Part|1|10.29,1.85,5.52|4812.46,148.25,-274.56|Build/Props
Part|Part|1|10.29,1.85,5.52|4860.95,168.5,-234.62|Build/Props
Part|Part|1|5.46,1.85,13.46|4855.96,162.29,-265.53|Build/Props
Part|Part|1|10.29,1.85,9.79|4858.95,170.23,-252.51|Build/Props
Part|Part|1|5.46,1.85,8.81|4854.97,158.44,-268.28|Build/Props
Part|Part|1|10.29,1.85,11.66|4857.37,167.06,-260.77|Build/Props
Part|Part|1|10.29,1.85,8.29|4860.29,171.55,-243.78|Build/Props
Part|Part|1|5.46,1.85,11.02|4859.68,153.11,-272.58|Build/Props
Part|Part|1|10.29,1.85,7.73|4893.79,143.23,-269.61|Build/Props
Part|Part|1|10.29,1.85,12|4879.69,153.54,-274.29|Build/Props
Part|Part|1|5.46,1.85,15.67|4864.2,154.46,-273.66|Build/Props
Part|Part|1|10.29,1.85,13.87|4870.93,155.47,-274.71|Build/Props
Part|Part|1|10.29,1.85,10.5|4887.81,150.06,-272.96|Build/Props
Part|Part|1|10.21,1.85,11.02|4847.71,162.18,-271.17|Build/Props
Part|Part|1|10.29,1.85,9.52|4834.31,170.52,-263.08|Build/Props
Part|Part|1|10.29,1.85,6.61|4827.56,171,-257.24|Build/Props
Part|Part|1|10.29,1.85,13.96|4841.28,168.26,-268.28|Build/Props
Part|Part|1|10.29,1.85,9.52|4873.28,168.31,-260.4|Build/Props
Part|Part|1|10.29,1.85,13.96|4866.87,166.8,-266.51|Build/Props
Part|Part|1|10.21,1.85,11.02|4860.25,161.46,-270.3|Build/Props
Part|Part|1|10.29,1.85,6.61|4879.17,168.06,-253.68|Build/Props
Part|Part|1|10.21,1.85,11.02|4856.06,155,-282.52|Build/Props
Part|Part|1|10.29,1.85,9.52|4860.25,148.22,-298.37|Build/Props
Part|Part|1|10.29,1.85,6.61|4861.93,141.46,-303.97|Build/Props
Part|Part|1|10.29,1.85,13.96|4858.32,153.61,-291.45|Build/Props
Part|Part|1|8.27,16.53,8.27|4851.63,109.65,-253.11|Build/Props
Part|Part|1|9.14,6.44,9.14|4853.65,153.86,-272.55|Build/Props
Part|Part|1|7.01,22.29,7.01|4851.45,127.28,-259.04|Build/Props
Part|Part|1|7.28,10.59,7.28|4853.65,153.86,-272.55|Build/Props
Part|Part|1|5.65,16.15,5.65|4852.66,143.43,-266.69|Build/Props
Part|Part|1|5.65,0.22,4.2|5068.78,68,-299.68|Build/Props
Part|Part|1|4.35,0.36,9.85|5065.08,68.07,-301.25|Build/Props
Part|Part|1|5.65,0.47,5.7|5043.28,68.8,-304.63|Build/Props
Part|Part|1|10,0.67,11|5042.67,68.22,-305.04|Build/Props
Part|Part|1|5.16,0.22,3.48|5076.11,68,-300.13|Build/Props
Part|Part|1|5.65,1.22,4.2|4337.07,67.5,-416.15|Build/Props
Part|Part|1|5.16,1.22,3.48|4329.73,67.5,-415.7|Build/Props
Part|Part|1|4.35,1.36,9.85|4340.76,67.57,-414.58|Build/Props
Part|Part|1|5.65,1.47,5.7|4349.51,68.3,-418.7|Build/Props
Part|Part|1|10,1.67,11|4350.12,67.72,-418.28|Build/Props
Part|Part|1|3.72,1.4,5.74|4657.83,68.27,-305.56|Build/Props
Part|Part|1|3.51,0.51,1.83|4864.9,67.83,-432.54|Build/Props
Part|Part|1|7.35,1.16,6.31|4418.14,68.43,-428.22|Build/Props
Part|Part|1|2.94,0.42,6.82|4966.76,67.79,-430.69|Build/Props
Part|Part|1|2.97,0.79,3.04|4444.5,68.33,-423.57|Build/Props
Part|Part|1|4.52,1.03,4.97|4426.4,68.05,-302.38|Build/Props
Part|Part|1|3.04,0.51,1.62|4558.59,67.83,-415.73|Build/Props
Part|Part|1|5.58,0.56,3.17|4972.78,67.86,-432.55|Build/Props
Part|Part|1|7.18,0.64,3.48|4475.93,68.9,-434.29|Build/Props
Part|Part|1|4,0.51,4.37|4553.87,67.83,-414.7|Build/Props
Part|Part|1|2.75,0.88,2.4|4929.1,68.88,-314.9|Build/Props
Part|Part|1|1.17,0.42,3.33|5098.19,67.79,-428.09|Build/Props
Part|Part|1|3.83,1.03,2.91|4417.44,68.05,-302.32|Build/Props
Part|Part|1|3.72,0.95,4.05|4656.46,68.05,-307.18|Build/Props
Part|Part|1|3.62,0.93,3.53|4552.58,68.04,-413.79|Build/Props
Part|Part|1|4.35,0.36,5.32|4444.63,67.76,-423.48|Build/Props
Part|Part|1|10,0.67,3.46|4404.87,67.91,-428.06|Build/Props
Part|Part|1|5.06,0.8,5.7|4568.61,67.98,-421.96|Build/Props
Part|Part|1|4.52,1.47,6.31|4432.27,68.27,-302.75|Build/Props
Part|Part|1|3.17,0.78,4.21|4776.12,67.97,-402.11|Build/Props
Part|Part|1|1.5,0.41,1.83|4545.27,67.78,-325.29|Build/Props
Part|Part|1|5.11,0.51,3.39|4573.06,67.83,-421.58|Build/Props
Part|Part|1|2.86,1.03,1.78|4412.65,68.05,-304.35|Build/Props
Part|Part|1|2.34,0.42,5.57|5103.26,67.79,-430|Build/Props
Part|Part|1|9.49,1.78,5.7|4422.57,68.74,-430.46|Build/Props
Part|Part|1|7.84,1.77,6.61|4315.59,68.52,-299.29|Build/Props
Part|Part|1|3.4,0.74,3.83|4926.53,67.95,-318.37|Build/Props
Part|Part|1|9.49,1.28,6.7|4310.72,68.28,-299.13|Build/Props
Part|Part|1|5.11,1.21,3.39|4870.3,68.18,-433.55|Build/Props
Part|Part|1|1.78,0.45,3.05|4771.38,67.8,-401.93|Build/Props
Part|Part|1|3.11,0.59,2.36|4552.38,67.87,-324.95|Build/Props
Part|Part|1|4.13,1.01,4.33|4928.48,68.09,-315.46|Build/Props
Part|Part|1|6.4,0.74,3.83|5051.32,67.95,-423.89|Build/Props
Part|Part|1|3.72,0.95,6.05|4780.11,68.05,-400.74|Build/Props
Part|Part|1|1.69,0.6,2.36|4550.8,68.62,-321.23|Build/Props
Part|Part|1|6.4,0.74,3.83|4549.55,67.95,-321.75|Build/Props
Meshes/untitled_Cube.003 (1)|MeshPart|1|2.73,0.93,2.73|4323.52,83.17,-425.99|Build/Props
Meshes/untitled_Cube.009 (1)|MeshPart|1|4.12,1.8,4.12|4323.52,84.54,-425.99|Build/Props
Meshes/untitled_Cube.008 (1)|Part|1|3.25,1.74,3.25|4323.52,71.92,-425.99|Build/Props
Meshes/untitled_Cube.007 (1)|Part|1|3.44,0.7,3.44|4323.52,82.36,-425.99|Build/Props
Meshes/untitled_Cube.004 (1)|Part|1|1.16,5.62,1.16|4323.52,78.39,-425.99|Build/Props
Meshes/untitled_Cube.005 (3)|Part|1|1.67,2.79,1.67|4323.52,74.19,-425.99|Build/Props
Meshes/untitled_Cube.006 (2)|Part|1|2.64,0.81,2.64|4323.52,81.6,-425.99|Build/Props
Meshes/untitled_Cube.004 (1)|Part|1|1.16,5.62,1.16|4323.52,78.39,-300.99|Build/Props
Meshes/untitled_Cube.009 (1)|MeshPart|1|4.12,1.8,4.12|4323.52,84.54,-300.99|Build/Props
Meshes/untitled_Cube.003 (1)|MeshPart|1|2.73,0.93,2.73|4323.52,83.17,-300.99|Build/Props
Meshes/untitled_Cube.005 (3)|Part|1|1.67,2.79,1.67|4323.52,74.19,-300.99|Build/Props
Meshes/untitled_Cube.008 (1)|Part|1|3.25,1.74,3.25|4323.52,71.92,-300.99|Build/Props
Meshes/untitled_Cube.006 (2)|Part|1|2.64,0.81,2.64|4323.52,81.6,-300.99|Build/Props
Meshes/untitled_Cube.007 (1)|Part|1|3.44,0.7,3.44|4323.52,82.36,-300.99|Build/Props
Meshes/untitled_Cube.008 (1)|Part|1|3.25,1.74,3.25|5055.52,71.92,-425.99|Build/Props
Meshes/untitled_Cube.004 (1)|Part|1|1.16,5.62,1.16|5055.52,78.39,-425.99|Build/Props
Meshes/untitled_Cube.009 (1)|MeshPart|1|4.12,1.8,4.12|5055.52,84.54,-425.99|Build/Props
Meshes/untitled_Cube.005 (3)|Part|1|1.67,2.79,1.67|5055.52,74.19,-425.99|Build/Props
Meshes/untitled_Cube.006 (2)|Part|1|2.64,0.81,2.64|5055.52,81.6,-425.99|Build/Props
Meshes/untitled_Cube.007 (1)|Part|1|3.44,0.7,3.44|5055.52,82.36,-425.99|Build/Props
Meshes/untitled_Cube.003 (1)|MeshPart|1|2.73,0.93,2.73|5055.52,83.17,-425.99|Build/Props
Meshes/untitled_Cube.008 (1)|Part|1|3.25,1.74,3.25|4810.52,71.92,-300.99|Build/Props
Meshes/untitled_Cube.004 (1)|Part|1|1.16,5.62,1.16|4810.52,78.39,-300.99|Build/Props
Meshes/untitled_Cube.006 (2)|Part|1|2.64,0.81,2.64|4810.52,81.6,-300.99|Build/Props
Meshes/untitled_Cube.005 (3)|Part|1|1.67,2.79,1.67|4810.52,74.19,-300.99|Build/Props
Meshes/untitled_Cube.007 (1)|Part|1|3.44,0.7,3.44|4810.52,82.36,-300.99|Build/Props
Meshes/untitled_Cube.009 (1)|MeshPart|1|4.12,1.8,4.12|4810.52,84.54,-300.99|Build/Props
Meshes/untitled_Cube.003 (1)|MeshPart|1|2.73,0.93,2.73|4810.52,83.17,-300.99|Build/Props
Meshes/untitled_Cube.006 (2)|Part|1|2.64,0.81,2.64|4945.52,81.6,-425.99|Build/Props
Meshes/untitled_Cube.003 (1)|MeshPart|1|2.73,0.93,2.73|4945.52,83.17,-425.99|Build/Props
Meshes/untitled_Cube.009 (1)|MeshPart|1|4.12,1.8,4.12|4945.52,84.54,-425.99|Build/Props
Meshes/untitled_Cube.005 (3)|Part|1|1.67,2.79,1.67|4945.52,74.19,-425.99|Build/Props
Meshes/untitled_Cube.004 (1)|Part|1|1.16,5.62,1.16|4945.52,78.39,-425.99|Build/Props
Meshes/untitled_Cube.007 (1)|Part|1|3.44,0.7,3.44|4945.52,82.36,-425.99|Build/Props
Meshes/untitled_Cube.008 (1)|Part|1|3.25,1.74,3.25|4945.52,71.92,-425.99|Build/Props
Meshes/untitled_Cube.006 (2)|Part|1|2.64,0.81,2.64|5055.52,81.6,-300.99|Build/Props
Meshes/untitled_Cube.004 (1)|Part|1|1.16,5.62,1.16|5055.52,78.39,-300.99|Build/Props
Meshes/untitled_Cube.007 (1)|Part|1|3.44,0.7,3.44|5055.52,82.36,-300.99|Build/Props
Meshes/untitled_Cube.009 (1)|MeshPart|1|4.12,1.8,4.12|5055.52,84.54,-300.99|Build/Props
Meshes/untitled_Cube.005 (3)|Part|1|1.67,2.79,1.67|5055.52,74.19,-300.99|Build/Props
Meshes/untitled_Cube.003 (1)|MeshPart|1|2.73,0.93,2.73|5055.52,83.17,-300.99|Build/Props
Meshes/untitled_Cube.008 (1)|Part|1|3.25,1.74,3.25|5055.52,71.92,-300.99|Build/Props
Meshes/untitled_Cube.009 (1)|MeshPart|1|4.12,1.8,4.12|4945.52,84.54,-300.99|Build/Props
Meshes/untitled_Cube.005 (3)|Part|1|1.67,2.79,1.67|4945.52,74.19,-300.99|Build/Props
Meshes/untitled_Cube.006 (2)|Part|1|2.64,0.81,2.64|4945.52,81.6,-300.99|Build/Props
Meshes/untitled_Cube.003 (1)|MeshPart|1|2.73,0.93,2.73|4945.52,83.17,-300.99|Build/Props
Meshes/untitled_Cube.008 (1)|Part|1|3.25,1.74,3.25|4945.52,71.92,-300.99|Build/Props
Meshes/untitled_Cube.007 (1)|Part|1|3.44,0.7,3.44|4945.52,82.36,-300.99|Build/Props
Meshes/untitled_Cube.004 (1)|Part|1|1.16,5.62,1.16|4945.52,78.39,-300.99|Build/Props
Meshes/untitled_Cube.009 (1)|MeshPart|1|4.12,1.8,4.12|4466.52,84.54,-300.99|Build/Props
Meshes/untitled_Cube.003 (1)|MeshPart|1|2.73,0.93,2.73|4466.52,83.17,-300.99|Build/Props
Meshes/untitled_Cube.004 (1)|Part|1|1.16,5.62,1.16|4466.52,78.39,-300.99|Build/Props
Meshes/untitled_Cube.008 (1)|Part|1|3.25,1.74,3.25|4466.52,71.92,-300.99|Build/Props
Meshes/untitled_Cube.007 (1)|Part|1|3.44,0.7,3.44|4466.52,82.36,-300.99|Build/Props
Meshes/untitled_Cube.006 (2)|Part|1|2.64,0.81,2.64|4466.52,81.6,-300.99|Build/Props
Meshes/untitled_Cube.005 (3)|Part|1|1.67,2.79,1.67|4466.52,74.19,-300.99|Build/Props
Meshes/untitled_Cube.009 (1)|MeshPart|1|4.12,1.8,4.12|4593.52,84.54,-425.99|Build/Props
Meshes/untitled_Cube.003 (1)|MeshPart|1|2.73,0.93,2.73|4593.52,83.17,-425.99|Build/Props
Meshes/untitled_Cube.008 (1)|Part|1|3.25,1.74,3.25|4593.52,71.92,-425.99|Build/Props
Meshes/untitled_Cube.005 (3)|Part|1|1.67,2.79,1.67|4593.52,74.19,-425.99|Build/Props
Meshes/untitled_Cube.007 (1)|Part|1|3.44,0.7,3.44|4593.52,82.36,-425.99|Build/Props
Meshes/untitled_Cube.004 (1)|Part|1|1.16,5.62,1.16|4593.52,78.39,-425.99|Build/Props
Meshes/untitled_Cube.006 (2)|Part|1|2.64,0.81,2.64|4593.52,81.6,-425.99|Build/Props
Meshes/untitled_Cube.009 (1)|MeshPart|1|4.12,1.8,4.12|4593.52,84.54,-300.99|Build/Props
Meshes/untitled_Cube.007 (1)|Part|1|3.44,0.7,3.44|4593.52,82.36,-300.99|Build/Props
Meshes/untitled_Cube.003 (1)|MeshPart|1|2.73,0.93,2.73|4593.52,83.17,-300.99|Build/Props
Meshes/untitled_Cube.006 (2)|Part|1|2.64,0.81,2.64|4593.52,81.6,-300.99|Build/Props
Meshes/untitled_Cube.005 (3)|Part|1|1.67,2.79,1.67|4593.52,74.19,-300.99|Build/Props
Meshes/untitled_Cube.004 (1)|Part|1|1.16,5.62,1.16|4593.52,78.39,-300.99|Build/Props
Meshes/untitled_Cube.008 (1)|Part|1|3.25,1.74,3.25|4593.52,71.92,-300.99|Build/Props
Meshes/untitled_Cube.009 (1)|MeshPart|1|4.12,1.8,4.12|4466.52,84.54,-425.99|Build/Props
Meshes/untitled_Cube.003 (1)|MeshPart|1|2.73,0.93,2.73|4466.52,83.17,-425.99|Build/Props
Meshes/untitled_Cube.005 (3)|Part|1|1.67,2.79,1.67|4466.52,74.19,-425.99|Build/Props
Meshes/untitled_Cube.004 (1)|Part|1|1.16,5.62,1.16|4466.52,78.39,-425.99|Build/Props
Meshes/untitled_Cube.006 (2)|Part|1|2.64,0.81,2.64|4466.52,81.6,-425.99|Build/Props
Meshes/untitled_Cube.007 (1)|Part|1|3.44,0.7,3.44|4466.52,82.36,-425.99|Build/Props
Meshes/untitled_Cube.008 (1)|Part|1|3.25,1.74,3.25|4466.52,71.92,-425.99|Build/Props
Meshes/untitled_Cube.009 (1)|MeshPart|1|4.12,1.8,4.12|4810.52,84.54,-425.99|Build/Props
Meshes/untitled_Cube.005 (3)|Part|1|1.67,2.79,1.67|4810.52,74.19,-425.99|Build/Props
Meshes/untitled_Cube.004 (1)|Part|1|1.16,5.62,1.16|4810.52,78.39,-425.99|Build/Props
Meshes/untitled_Cube.008 (1)|Part|1|3.25,1.74,3.25|4810.52,71.92,-425.99|Build/Props
Meshes/untitled_Cube.003 (1)|MeshPart|1|2.73,0.93,2.73|4810.52,83.17,-425.99|Build/Props
Meshes/untitled_Cube.006 (2)|Part|1|2.64,0.81,2.64|4810.52,81.6,-425.99|Build/Props
Meshes/untitled_Cube.007 (1)|Part|1|3.44,0.7,3.44|4810.52,82.36,-425.99|Build/Props
untitled|MeshPart|1|21.83,5.71,18.92|4312.46,71.36,-427.92|Build/Props
untitled|MeshPart|1|21.83,5.71,18.92|4436.38,69.75,-317.63|Build/Props
untitled|MeshPart|1|22.28,5.82,19.3|5001.76,71.14,-301.33|Build/Props
untitled|MeshPart|1|21.83,5.71,18.92|4294.54,71.36,-300.21|Build/Props
untitled|MeshPart|1|21.83,5.71,18.92|4664.11,98.97,-456.39|Build/Props
untitled|MeshPart|1|21.83,5.71,18.92|4824.83,70.71,-427.94|Build/Props
untitled|MeshPart|1|21.83,5.71,18.92|4919.32,89.75,-435.46|Build/Props
untitled|MeshPart|1|21.83,5.71,18.92|4682.61,92.38,-296.5|Build/Props
untitled|MeshPart|1|21.83,5.71,18.92|4486.85,88.58,-434.59|Build/Props
untitled|MeshPart|1|21.83,5.71,18.92|4438.93,69.57,-432.38|Build/Props
untitled|MeshPart|1|16.39,4.29,14.2|4539.9,70.68,-298.35|Build/Props
untitled|MeshPart|1|21.83,5.71,18.92|4334.19,69.57,-426.62|Build/Props
untitled|MeshPart|1|20.78,5.43,18|4993.15,71.04,-299.16|Build/Props
Part|Part|1|21,1,7|4546.5,68.08,-292.5|Build/Props
Part|Part|1|20,1,9|4600,68.08,-426.5|Build/Props
Part|Part|1|15.4,2,10.54|4305.56,69.58,-432.52|Build/Props
Part|Part|1|16,1,14|4445,68.08,-296|Build/Props
Part|Part|1|22,1,17|4464,68.08,-297.5|Build/Props
Part|Part|1|26,1,17|4727,68.08,-440.5|Build/Props
Part|Part|1|34,1,11|4744,68.08,-292.5|Build/Props
Part|Part|1|21,1,9|4782.5,68.08,-435.5|Build/Props
Part|Part|1|8,1,19|4744,68.08,-430.5|Build/Props
Part|Part|1|28,1,10|4454,69.08,-295|Build/Props
Part|Part|1|36,1,13|4463,68.08,-433.5|Build/Props
Part|Part|1|5.86,3.45,5.37|4810.48,69.33,-425.99|Build/Props
Part|Part|1|36,1,16|4848,68.08,-295|Build/Props
Part|Part|1|15,1,3|4587.5,68.08,-292.5|Build/Props
Part|Part|1|18.46,3.91,10|4455.94,69.37,-291.27|Build/Props
Part|Part|1|25,1,11|5090.5,68.08,-293.5|Build/Props
Part|Part|1|16,1,14|5087,68.08,-436|Build/Props
Part|Part|1|20,3.19,12|4912.85,70.17,-437|Build/Props
Part|Part|1|7,1,3|5098.5,68.08,-433.5|Build/Props
Part|Part|1|9,1,10|4279.91,68.08,-435.81|Build/Props
Part|Part|1|26.46,3.37,10|5026.45,69.09,-295.37|Build/Props
Part|Part|1|26.46,2.14,15|4705.43,68.48,-293.96|Build/Props
Part|Part|1|15,1,12|4267.91,68.08,-434.81|Build/Props
Part|Part|1|18.88,3.36,12|4781.59,70.26,-442.24|Build/Props
Part|Part|1|31,1,16|4694.5,68.08,-288|Build/Props
Part|Part|1|26,1,3|5035,68.08,-429.5|Build/Props
Part|Part|1|16,1,2|4664,68.08,-292|Build/Props
Part|Part|1|28,1,12|4322.41,69.08,-437.81|Build/Props
Part|Part|1|5.86,3.45,5.37|4466.48,69.33,-300.99|Build/Props
Part|Part|1|23,1,17|4877.5,68.08,-295.5|Build/Props
Part|Part|1|26,1,18|4287,68.08,-291|Build/Props
Part|Part|1|18.46,2.14,10|4558.55,68.48,-288.4|Build/Props
Part|Part|1|13,1,7|4324.5,68.08,-300.5|Build/Props
Part|Part|1|48,1,6|4690,68.08,-436|Build/Props
Part|Part|1|5.86,3.45,5.37|4593.48,69.33,-300.99|Build/Props
Part|Part|1|26,1,8|4399,68.08,-435|Build/Props
Part|Part|1|24,1,12|4760,68.08,-434|Build/Props
Part|Part|1|27,1,11|4665.5,68.08,-285.5|Build/Props
Part|Part|1|20,1,12|4395,69.08,-439|Build/Props
Part|Part|1|36,1,15|4550,68.08,-434.5|Build/Props
Part|Part|1|18.46,3.91,14|4307.93,69.37,-289.06|Build/Props
Part|Part|1|12.77,3.18,10.54|4283.21,68.16,-439.07|Build/Props
Part|Part|1|30,1,8|4912,68.08,-431|Build/Props
Part|Part|1|12,1,11|4597,69.08,-294.5|Build/Props
Part|Part|1|19,1,8|5104.5,68.08,-439|Build/Props
Part|Part|1|23,1,7|4492.5,68.08,-433.5|Build/Props
Part|Part|1|10,1,2|5041,68.08,-427|Build/Props
Part|Part|1|5.86,3.45,5.37|4323.48,69.33,-300.99|Build/Props
Part|Part|1|34,1,12|4369,68.08,-433|Build/Props
Part|Part|1|12,1,14|4891,68.08,-438|Build/Props
Part|Part|1|26.46,3.37,15|4725.7,69.09,-287.85|Build/Props
Part|Part|1|25.51,1.66,12|4764.72,69.4,-439.82|Build/Props
Part|Part|1|5.86,3.45,5.37|4593.48,69.33,-425.99|Build/Props
Part|Part|1|5.86,3.45,5.37|4945.48,69.33,-425.99|Build/Props
Part|Part|1|17,1,6|4287.5,68.08,-303|Build/Props
Part|Part|1|23.46,1.91,12|4389.27,70.53,-440.87|Build/Props
Part|Part|1|5.86,3.45,5.37|5055.48,69.33,-425.99|Build/Props
Part|Part|1|50,1,16|4315.41,68.08,-435.81|Build/Props
Part|Part|1|9,1,17|4649.5,68.08,-448.5|Build/Props
Part|Part|1|18.46,3.91,12|4389.86,69.37,-290.91|Build/Props
Part|Part|1|11,1,3|4547.5,68.08,-297.5|Build/Props
Part|Part|1|40,1,3|4316.41,68.08,-426.31|Build/Props
Part|Part|1|26,1,16|4424,68.08,-290|Build/Props
Part|Part|1|20,2,12|4320.41,70.58,-439.81|Build/Props
Part|Part|1|18,1,16|4852,69.08,-293|Build/Props
Part|Part|1|33,1,8|4388.5,69.08,-295|Build/Props
Part|Part|1|14,1,3|4310.41,68.08,-423.31|Build/Props
Part|Part|1|8,1,11|4286,69.08,-296.5|Build/Props
Part|Part|1|15,1,5|4327.5,69.08,-293.5|Build/Props
Part|Part|1|19,1,20|4364.5,68.08,-292|Build/Props
Part|Part|1|28,1,6|4690,68.08,-431|Build/Props
Part|Part|1|18,1,3|4597,68.08,-300.5|Build/Props
Part|Part|1|23,1,13|4900.5,68.08,-293.5|Build/Props
Part|Part|1|17,1,16|4772.5,69.08,-291|Build/Props
Part|Part|1|15.61,3.93,10.54|4271.41,68.54,-436.93|Build/Props
Part|Part|1|48,1,11|5007,68.08,-292.5|Build/Props
Part|Part|1|24,1,15|4773,68.08,-294.5|Build/Props
Part|Part|1|13,1,6|4365.5,69.08,-294|Build/Props
Part|Part|1|26,1,5|4549,68.08,-424.5|Build/Props
Part|Part|1|5.86,3.45,5.37|5055.48,69.33,-300.99|Build/Props
Part|Part|1|11.87,1.66,12|4900.3,69.4,-438.2|Build/Props
Part|Part|1|37,1,22|4392.5,68.08,-293|Build/Props
Part|Part|1|5.86,3.45,5.37|4466.48,69.33,-425.99|Build/Props
Part|Part|1|39,1,7|4602.5,68.08,-434.5|Build/Props
Part|Part|1|11.87,1.66,12|4605.26,69.4,-437.82|Build/Props
Part|Part|1|19,1,7|4520.5,68.08,-431.5|Build/Props
Part|Part|1|9,1,5|4521.5,68.08,-425.5|Build/Props
Part|Part|1|10,1,5|4615,68.08,-428.5|Build/Props
Part|Part|1|16,1,6|4628,68.08,-294|Build/Props
Part|Part|1|35,1,4|4327.5,68.08,-295|Build/Props
Part|Part|1|5.86,3.45,5.37|4945.48,69.33,-300.99|Build/Props
Part|Part|1|28,1,12|4371,69.08,-436|Build/Props
Part|Part|1|22,1,5|4464,68.08,-424.5|Build/Props
Part|Part|1|17,1,3|5090.5,68.08,-300.5|Build/Props
Part|Part|1|5.86,3.45,5.37|4810.48,69.33,-300.99|Build/Props
Part|Part|1|14,1,8|4529,68.08,-293|Build/Props
Part|Part|1|5.86,3.45,5.37|4323.48,69.33,-425.99|Build/Props
Part|Part|1|26.46,2.56,10|5035.55,68.69,-438.37|Build/Props
Part|Part|1|28,1,5|5017,68.08,-300.5|Build/Props
Part|Part|1|41,1,8|5032.5,68.08,-435|Build/Props
Part|Part|1|28,1,5|4598,68.08,-296.5|Build/Props
Part|Part|1|31.06,6.9,11.77|5037,107.42,-285.92|Build/Props
Part|Part|1|27.82,7.96,9.9|5037,108.76,-285.92|Build/Props
Part|Part|1|26.06,4.9,9.77|4393.97,114.02,-448.7|Build/Props
Part|Part|1|16.82,5.96,7.9|4760.41,139.82,-476.29|Build/Props
Part|Part|1|18.06,6.9,11.77|4538.55,113.88,-277.4|Build/Props
Part|Part|1|20.06,4.9,9.77|4760.41,138.47,-476.29|Build/Props
Part|Part|1|14.82,7.96,9.9|4538.55,115.23,-277.4|Build/Props
Part|Part|1|22.82,5.96,7.9|4393.97,115.37,-448.7|Build/Props
Part|Part|1|8.66,2.73,5.07|5001.88,69.22,-434|Build/Props
Part|Part|1|6.29,2.53,4.88|4540.41,70.56,-434.01|Build/Props
Part|Part|1|8.66,2.73,5.07|4643.14,69.22,-292.54|Build/Props
Part|Part|1|7.02,2.73,3.47|5001.88,70.22,-434|Build/Props
Part|Part|1|13.23,1.98,2.86|4456.05,69.78,-431.01|Build/Props
Part|Part|1|9.23,1.98,2.86|5100.23,69.78,-298.99|Build/Props
Part|Part|1|8.66,1.73,4.07|4817.21,70.44,-432.87|Build/Props
Part|Part|1|7.02,2.73,3.47|4643.14,70.22,-292.54|Build/Props
Part|Part|1|7.66,1.73,6.07|4541.71,69.44,-432.87|Build/Props
Part|Part|1|7.66,2.53,6.07|4540.41,69.84,-434.01|Build/Props
Part|Part|1|10.66,1.73,6.07|4817.21,69.44,-432.87|Build/Props
Part|Part|1|14.46,1.98,3.97|4456.05,68.57,-431.01|Build/Props
Part|Part|1|4.51,2.41,4.61|4646.48,68.28,-293.44|Build/Props
Part|Part|1|4.51,2.41,4.61|4998.78,68.28,-432.48|Build/Props
Part|Part|1|10.46,1.98,3.97|5100.23,68.57,-298.99|Build/Props
Part|Part|1|7.5,3,7.5|4755.56,116.08,-450.81|Build/Props
Part|Part|1|6,4.5,3|4755.56,119.83,-452.31|Build/Props
Part|Part|1|1.5,1.5,1.5|4757.06,125.83,-449.31|Build/Props
Part|Part|1|3,7.5,4.5|4756.31,121.33,-450.81|Build/Props
Part|Part|1|1.5,6,3|4754.06,120.58,-451.56|Build/Props
Part|Part|1|3,4.5,3|4756.31,127.33,-451.56|Build/Props
Part|Part|1|1.5,3,1.5|4755.56,131.08,-452.31|Build/Props
Part|Part|1|4.5,3,3|4756.31,119.08,-449.31|Build/Props
Part|Part|1|7.5,3,7.5|4671.34,85.7,-449.64|Build/Props
Part|Part|1|6,4.5,6|4671.34,89.45,-449.64|Build/Props
Part|Part|1|4.5,27,4.5|4671.34,105.2,-449.64|Build/Props
Part|Part|1|6,4.5,6|4671.34,120.95,-449.64|Build/Props
Part|Part|1|7.5,3,7.5|4671.34,124.7,-449.64|Build/Props
Part|Part|1|10.62,4.25,10.62|4565,69.7,-437.64|Build/Props
Part|Part|1|8.49,6.37,8.49|4565,75.01,-437.64|Build/Props
Part|Part|1|10.62,4.25,10.62|4565,124.91,-437.64|Build/Props
Part|Part|1|8.49,6.37,8.49|4565,119.6,-437.64|Build/Props
Part|Part|1|4.25,4.25,4.25|4563.44,92.96,-436.6|Build/Props
Part|Part|1|6.37,12.74,6.37|4565,84.57,-437.64|Build/Props
Part|Part|1|2.12,10.62,6.37|4567.13,96.24,-437.64|Build/Props
Part|Part|1|6.37,14.87,6.37|4565,108.98,-437.64|Build/Props
Part|Part|1|2.12,6.38,4.25|4562.88,98.36,-438.7|Build/Props
Part|Part|1|5.83,4.37,5.83|4492.47,68.04,-416.68|Build/Props
Part|Part|1|2.91,1.46,1.46|4514.2,67.31,-419.07|Build/Props
Part|Part|1|4.37,14.57,4.37|4501.88,68.04,-417.71|Build/Props
Part|Part|1|2.91,4.37,2.91|4511.38,67.31,-418.02|Build/Props
Part|Part|1|2.91,2.91,2.91|4510.5,68.77,-419.39|Build/Props
Part|Part|1|7.29,2.91,7.29|4488.85,68.04,-416.28|Build/Props
Part|Part|1|2.12,16.99,6.37|4833,107.92,-437.64|Build/Props
Part|Part|1|2.12,10.62,2.12|4830.88,94.12,-435.52|Build/Props
Part|Part|1|4.25,6.37,6.37|4835.13,119.6,-438.7|Build/Props
Part|Part|1|2.12,6.38,2.12|4830.88,113.23,-435.52|Build/Props
Part|Part|1|2.12,10.62,4.25|4835.13,104.73,-438.7|Build/Props
Part|Part|1|2.12,38.22,4.25|4830.88,97.3,-438.7|Build/Props
Part|Part|1|8.49,2.12,8.49|4831.94,123.84,-438.7|Build/Props
Part|Part|1|2.12,6.38,2.12|4835.13,113.23,-439.77|Build/Props
Part|Part|1|4.25,21.24,6.37|4834.06,88.81,-437.64|Build/Props
Part|Part|1|4.25,6.37,8.49|4830.88,119.6,-437.64|Build/Props
Part|Part|1|8.49,6.37,8.49|4833,75.01,-437.64|Build/Props
Part|Part|1|10.62,4.25,10.62|4833,69.7,-437.64|Build/Props
Part|Part|1|4.25,23.36,6.37|4572.94,104.73,-292.31|Build/Props
Part|Part|1|8.49,6.37,8.49|4571.88,75.01,-292.31|Build/Props
Part|Part|1|10.62,4.25,10.62|4571.88,69.7,-292.31|Build/Props
Part|Part|1|4.25,14.87,6.37|4570.82,85.63,-292.31|Build/Props
Part|Part|1|2.12,14.87,4.25|4574,85.63,-291.25|Build/Props
Part|Part|1|4.25,6.37,8.49|4574,119.6,-292.31|Build/Props
Part|Part|1|8.49,2.12,8.49|4572.94,123.84,-291.25|Build/Props
Part|Part|1|4.25,6.37,6.37|4569.76,119.6,-291.25|Build/Props
Part|Part|1|2.12,14.87,4.25|4569.76,108.98,-291.25|Build/Props
Part|Part|1|6.37,38.21,6.37|4424.19,97.3,-290.64|Build/Props
Part|Part|1|10.61,4.25,10.61|4424.19,69.7,-290.64|Build/Props
Part|Part|1|10.61,4.25,10.61|4424.19,124.9,-290.64|Build/Props
Part|Part|1|8.49,6.37,8.49|4424.19,75.01,-290.64|Build/Props
Part|Part|1|8.49,6.37,8.49|4424.19,119.59,-290.64|Build/Props
Part|Part|1|4.25,14.87,4.25|4830.94,94.12,-291.25|Build/Props
Part|Part|1|6.37,14.87,6.37|4829.88,108.98,-292.31|Build/Props
Part|Part|1|8.49,6.37,8.49|4829.88,75.01,-292.31|Build/Props
Part|Part|1|4.25,8.5,2.12|4830.89,90.9,-294.38|Build/Props
Part|Part|1|2.12,14.87,6.37|4827.76,94.12,-292.31|Build/Props
Part|Part|1|10.62,4.25,10.62|4829.88,69.7,-292.31|Build/Props
Part|Part|1|6.37,8.5,6.37|4829.88,82.44,-292.31|Build/Props
Part|Part|1|8.49,6.37,8.49|4829.88,119.6,-292.31|Build/Props
Part|Part|1|10.62,4.25,10.62|4829.88,124.91,-292.31|Build/Props
Part|Part|1|6.37,33.97,4.25|4424.19,99.43,-440.37|Build/Props
Part|Part|1|6.37,4.25,6.37|4424.19,80.32,-439.31|Build/Props
Part|Part|1|4.25,6.38,2.12|4425.25,113.23,-437.19|Build/Props
Part|Part|1|4.25,16.99,2.12|4423.13,101.55,-437.19|Build/Props
Part|Part|1|8.49,6.37,8.49|4424.19,75.01,-439.31|Build/Props
Part|Part|1|10.62,4.25,10.62|4424.19,124.91,-439.31|Build/Props
Part|Part|1|2.76,2.13,4.25|4421.49,84.11,-436.6|Build/Props
Part|Part|1|8.49,6.37,8.49|4424.19,119.6,-439.31|Build/Props
Part|Part|1|4.25,10.62,2.12|4425.25,87.75,-437.19|Build/Props
Part|Part|1|10.62,4.25,10.62|4424.19,69.7,-439.31|Build/Props
Part|Part|1|4.25,2.12,2.12|5078.28,106.85,-438.99|Build/Props
Part|Part|1|8.49,6.37,8.49|5079.34,75.01,-438.99|Build/Props
Part|Part|1|4.25,6.37,4.25|5078.28,102.61,-440.05|Build/Props
Part|Part|1|4.25,4.25,4.25|5080.4,101.54,-437.93|Build/Props
Part|Part|1|10.61,4.25,10.61|5079.34,69.7,-438.99|Build/Props
Part|Part|1|6.37,21.23,6.37|5079.34,88.81,-438.99|Build/Props
Part|Part|1|1,2,1|4628.96,68.33,-299.44|Build/Props
Part|Part|1|2,1,1|4625.31,69.83,-301.14|Build/Props
Part|Part|1|4,3,4|4619.41,69.33,-299.64|Build/Props
Part|Part|1|5,2,5|4616.92,69.33,-299.42|Build/Props
Part|Part|1|1,3,2|4626.43,68.33,-299.73|Build/Props
Part|Part|1|3,4,3|4622.9,69.33,-299.93|Build/Props
Part|Part|1|1,2,1|4625.97,69.33,-299.19|Build/Props
Part|Part|1|10.61,4.25,10.61|4961.69,124.9,-439.31|Build/Props
Part|Part|1|6.37,38.21,6.37|4961.69,97.3,-439.31|Build/Props
Part|Part|1|8.49,6.37,8.49|4961.69,119.59,-439.31|Build/Props
Part|Part|1|8.49,6.37,8.49|4961.69,75.01,-439.31|Build/Props
Part|Part|1|10.61,4.25,10.61|4961.69,69.7,-439.31|Build/Props
Part|Part|1|1,2,1|4353.86,69.31,-306.92|Build/Props
Part|Part|1|3,4,3|4351.43,69.31,-308.94|Build/Props
Part|Part|1|4,3,4|4348.17,69.31,-310.21|Build/Props
Part|Part|1|5,2,5|4345.84,69.31,-311.12|Build/Props
Part|Part|1|1,3,2|4354.51,68.31,-307.2|Build/Props
Part|Part|1|2,1,1|4354.12,69.81,-308.96|Build/Props
Part|Part|1|1,2,1|4356.66,68.31,-305.83|Build/Props
Part|Part|1|6,4.5,6|4718.13,89.45,-449.64|Build/Props
Part|Part|1|3,4.5,3|4717.38,108.95,-450.39|Build/Props
Part|Part|1|7.5,3,7.5|4718.13,85.7,-449.64|Build/Props
Part|Part|1|4.5,15,4.5|4718.13,99.2,-449.64|Build/Props
Part|Part|1|3,3,3|4718.88,108.2,-448.89|Build/Props
Part|Part|1|3,1.5,1.5|4717.38,111.95,-449.64|Build/Props
Part|Part|1|2.5,5,2.5|4295.91,142.08,-454.81|Build/Props
Part|Part|1|5,12.5,7.5|4297.16,125.83,-452.31|Build/Props
Part|Part|1|2.5,2.5,2.5|4298.41,133.33,-449.81|Build/Props
Part|Part|1|10,7.5,5|4295.91,123.33,-454.81|Build/Props
Part|Part|1|12.5,5,12.5|4295.91,117.08,-452.31|Build/Props
Part|Part|1|5,7.5,5|4297.16,135.83,-453.56|Build/Props
Part|Part|1|7.5,5,5|4297.16,122.08,-449.81|Build/Props
Part|Part|1|2.5,10,5|4293.41,124.58,-453.56|Build/Props
Part|Part|1|2,1,1|4368.47,69.79,-306.33|Build/Props
Part|Part|1|5,2,5|4382.97,69.29,-306.49|Build/Props
Part|Part|1|2,3,2|4370.48,69.79,-305.85|Build/Props
Part|Part|1|2,2,2|4370.97,68.79,-306.86|Build/Props
Part|Part|1|3,7,3|4375.47,69.29,-306.41|Build/Props
Part|Part|1|4,3,4|4380.47,69.29,-306.46|Build/Props
Part|Part|1|6.37,4.25,6.37|4970.25,80.32,-290.64|Build/Props
Part|Part|1|8.49,6.37,8.49|4970.25,119.59,-290.64|Build/Props
Part|Part|1|10.61,4.25,10.61|4970.25,124.9,-290.64|Build/Props
Part|Part|1|4.25,10.62,2.12|4969.19,111.1,-292.76|Build/Props
Part|Part|1|4.25,23.36,2.12|4971.32,94.12,-292.76|Build/Props
Part|Part|1|6.37,33.97,4.25|4970.25,99.42,-289.58|Build/Props
Part|Part|1|2.12,14.87,2.12|4968.13,89.87,-292.76|Build/Props
Part|Part|1|8.49,6.37,8.49|4970.25,75.01,-290.64|Build/Props
Part|Part|1|10.61,4.25,10.61|4970.25,69.7,-290.64|Build/Props
Part|Part|1|1.5,3,1.5|4633.91,121.58,-449.31|Build/Props
Part|Part|1|1.5,4.5,3|4635.41,122.33,-450.06|Build/Props
Part|Part|1|6,4.5,6|4633.91,111.83,-450.81|Build/Props
Part|Part|1|3,1.5,1.5|4633.16,120.83,-452.31|Build/Props
Part|Part|1|4.5,6,4.5|4633.91,117.08,-450.81|Build/Props
Part|Part|1|7.5,3,7.5|4633.91,108.08,-450.81|Build/Props
Part|Part|1|1.5,3,1.5|4635.41,126.08,-449.31|Build/Props
Vines|MeshPart|1|83.49,19.92,4.66|4566.99,133.84,-453.95|Build/Props
Vines|MeshPart|1|171.75,14.67,1.89|4930.21,122.61,-261.78|Build/Props
Vines|MeshPart|1|98.53,19.92,4.66|4421.64,131.63,-464.01|Build/Props
Vines|MeshPart|1|98.55,16.83,1.89|4395.42,130.76,-473.66|Build/Props
Vines|MeshPart|1|98.25,9.9,1.89|4578.39,131.2,-226.46|Build/Props
Vines|MeshPart|1|60.91,16.25,4.66|4392.16,127.5,-264.23|Build/Props
Vines|MeshPart|1|98.55,16.83,1.89|4395.42,130.76,-473.66|Build/Props
Vines|MeshPart|1|47.22,16.83,1.89|4408.09,126.21,-263.06|Build/Props
Vines|MeshPart|1|88.8,9.78,1.89|4798.1,117.73,-457.88|Build/Props
Vines|MeshPart|1|113.67,14.67,1.89|4888.58,124.4,-449.75|Build/Props
Vines|MeshPart|1|143.25,9.9,1.89|4542.89,141.94,-473.66|Build/Props
Vines|MeshPart|1|47.53,15.57,4.66|4810.2,116.84,-276.4|Build/Props
Vines|MeshPart|1|98.25,9.9,1.89|4395.2,134.81,-473.66|Build/Props
Vines|MeshPart|1|98.55,16.83,1.89|4580.54,127.78,-226.17|Build/Props
Vines|MeshPart|1|111.01,16.83,1.89|4992.56,118.61,-467.92|Build/Props
Vines|MeshPart|1|65.33,19.92,4.66|4910.47,128.26,-471.15|Build/Props
Vines|MeshPart|1|80.09,18.16,4.66|4729.42,141.77,-232.45|Build/Props
Part|Part|1|39.86,52.78,59.25|4707.93,104.42,-205.38|Build/Props
Part|Part|1|29.36,102.01,35.39|4666.85,162.04,-197.06|Build/Props
Part|Part|1|5.47,47.76,6.35|4664.63,206.41,-208.63|Build/Props
Part|Part|1|5.47,6.56,15.07|4664.63,177.22,-223.83|Build/Props
Part|Part|1|11.25,18.47,4.46|4649.83,191.77,-208.34|Build/Props
Part|Part|1|12.46,31.87,6.35|4657.22,198.47,-200.63|Build/Props
Part|Part|1|5.47,31.99,6.35|4664.63,198.53,-213.63|Build/Props
Part|Part|1|3.17,58.6,15.01|4699.94,145.96,-219.67|Build/Props
Part|Part|1|3.17,53.42,23.79|4624.94,113.37,-235.06|Build/Props
Part|Part|1|61.86,61.78,34.25|4634.84,108.92,-229.06|Build/Props
Part|Part|1|22.86,73.78,26.25|4623.34,114.92,-216.06|Build/Props
Part|Part|1|19.86,111.78,26.25|4647.84,133.92,-216.06|Build/Props
Part|Part|1|39.86,101.78,42.25|4649.84,128.92,-213.06|Build/Props
Part|Part|1|7.17,25.09,3.46|4654.94,151.21,-240.92|Build/Props
Part|Part|1|5.3,52.6,10.9|4691,165.96,-206.16|Build/Props
Part|Part|1|23.98,38.39,6.89|4618.31,140.71,-184.67|Build/Props
Part|Part|1|13.55,52.39,6.89|4721.63,105.13,-218.31|Build/Props
Part|Part|1|9.12,2.81,3.46|4653.96,162.35,-237.92|Build/Props
Part|Part|1|3.17,58.6,26.01|4699.94,115.96,-236.17|Build/Props
Part|Part|1|11.38,58.6,7.08|4693.96,145.96,-214.18|Build/Props
Part|Part|1|19.78,6.56,4.4|4653.48,177.22,-229.17|Build/Props
Part|Part|1|72.86,80.78,38.25|4643.34,118.42,-175.06|Build/Props
Part|Part|1|7.17,53.42,4.79|4654.94,113.37,-244.56|Build/Props
Part|Part|1|32.24,24.54,8.89|4627.44,140.64,-214.13|Build/Props
Part|Part|1|11.25,13.39,4.46|4642.83,184.21,-223.45|Build/Props
Part|Part|1|16.24,14.39,6.89|4707.98,138,-218.31|Build/Props
Part|Part|1|6.12,19.56,5.68|4646.65,170.72,-231.81|Build/Props
Part|Part|1|44.82,52.39,3.89|4675.59,166.13,-191.06|Build/Props
Part|Part|1|32.24,13.39,6.89|4631.44,162.21,-184.67|Build/Props
Part|Part|1|17.17,1.53,16.1|4664.64,230.06,-199.05|Build/Props
Part|Part|1|39.86,89.78,56.25|4635.84,122.92,-196.06|Build/Props
Part|Part|1|5.3,60.6,10.9|4676.84,183.52,-192.88|Build/Props
Part|Part|1|53.86,52.78,59.25|4594.07,104.42,-189.38|Build/Props
Part|Part|1|39.86,121.78,42.25|4664.84,138.92,-197.06|Build/Props
Part|Part|1|5.3,35.12,4.45|4672.72,212.25,-192.88|Build/Props
Part|Part|1|5.3,60.6,10.9|4680.45,169.96,-202.65|Build/Props
Part|Part|1|39.86,66.78,59.25|4695.93,111.42,-217.38|Build/Props
Part|Part|1|5.47,27.27,6.35|4664.63,187.58,-216.47|Build/Props
Part|Part|1|27.86,72.78,38.25|4677.93,114.42,-235.88|Build/Props
Part|Part|1|41.86,95.78,30.25|4684.07,125.92,-210.88|Build/Props
Part|Part|1|6.12,2.81,5.68|4646.65,162.35,-236.81|Build/Props
Part|Part|1|24.86,113.78,26.25|4684.57,134.92,-197.12|Build/Props
Part|Part|1|19.34,56.61,22.45|4664.56,200.99,-199.23|Build/Props
Part|Part|1|40.86,40.78,26.25|4660.34,142.42,-229.06|Build/Props
Meshes/untitled_Cube.019|MeshPart|0|81.4,26.53,45.11|4694.73,97.47,-468.69|Build/Props
Meshes/untitled_Cube.021|Part|0|39.89,4.5,30.09|4694.73,122.26,-476.21|Build/Props
Meshes/untitled_Cube.017|MeshPart|0|115.32,2.09,49.36|4694.73,81.16,-466.57|Build/Props
Meshes/untitled_Cube.017|MeshPart|0|115.32,2,49.36|4694.73,83.2,-466.57|Build/Props
Meshes/untitled_Cube.020|Part|0|33.51,9.69,26.9|4694.73,115.16,-477.8|Build/Props
Meshes/untitled_Cube.018 (2)|MeshPart|0|122.45,10.54,52.92|4694.73,72.85,-464.79|Build/Props
Meshes/untitled_Cube.016|MeshPart|0|31.9,6.55,26.09|4694.73,127.78,-478.2|Build/Props
Meshes/untitled_Cube.018 (2)|MeshPart|0|122.45,2,52.92|4694.73,79.12,-464.79|Build/Props
Cube.038|MeshPart|0|2.23,4.84,1.21|-3496.84,17294.66,15710.14|Build/FuseBiomeZone
Cube.037|MeshPart|0|2.23,4.84,1.21|-3496.84,17294.66,15712.36|Build/FuseBiomeZone
Cube.005|MeshPart|0|30.68,13.97,14.41|-3503.28,17296.49,15711.25|Build/FuseBiomeZone
Cube.027|MeshPart|1|5.33,4.07,5.33|-3465.5,17292.56,15749.75|Build/FuseBiomeZone
Cube.026|MeshPart|1|5.85,3.14,5.85|-3465.5,17288.95,15749.75|Build/FuseBiomeZone
Cube.028|MeshPart|1|4.9,2.3,4.9|-3465.5,17295.74,15749.75|Build/FuseBiomeZone
Cube.028|MeshPart|1|4.9,2.3,4.9|-3465.5,17295.74,15672.75|Build/FuseBiomeZone
Cube.026|MeshPart|1|5.85,3.14,5.85|-3465.5,17288.95,15672.75|Build/FuseBiomeZone
Cube.027|MeshPart|1|5.33,4.07,5.33|-3465.5,17292.56,15672.75|Build/FuseBiomeZone
Cube.026|MeshPart|1|5.54,2.97,5.54|-3520.16,17293.99,15735.75|Build/FuseBiomeZone
Cube.028|MeshPart|1|4.64,2.18,4.64|-3520.16,17300.42,15735.75|Build/FuseBiomeZone
Cube.027|MeshPart|1|5.05,3.85,5.05|-3520.16,17297.4,15735.75|Build/FuseBiomeZone
Cube.027|MeshPart|1|5.31,4.05,5.31|-3508.5,17297.65,15674.82|Build/FuseBiomeZone
Cube.028|MeshPart|1|4.88,2.29,4.88|-3508.5,17300.82,15674.82|Build/FuseBiomeZone
Cube.026|MeshPart|1|5.83,3.13,5.83|-3508.5,17294.06,15674.82|Build/FuseBiomeZone
Cube.028|MeshPart|1|4.64,2.18,4.64|-3520.16,17300.42,15686.75|Build/FuseBiomeZone
Cube.026|MeshPart|1|5.54,2.97,5.54|-3520.16,17293.99,15686.75|Build/FuseBiomeZone
Cube.027|MeshPart|1|5.05,3.85,5.05|-3520.16,17297.4,15686.75|Build/FuseBiomeZone
Cube.028|MeshPart|1|4.88,2.29,4.88|-3508.5,17300.82,15747.68|Build/FuseBiomeZone
Cube.026|MeshPart|1|5.83,3.13,5.83|-3508.5,17294.06,15747.68|Build/FuseBiomeZone
Cube.027|MeshPart|1|5.31,4.05,5.31|-3508.5,17297.65,15747.68|Build/FuseBiomeZone
Cube.068|MeshPart|0|58,2,7.5|-3487.25,17287.5,15711.25|Build/FuseBiomeZone
Cube.068|MeshPart|0|58,3,7.5|-3490.25,17288,15711.25|Build/FuseBiomeZone
Cube.121|MeshPart|0|58,23,7.5|-3479.25,17275,15711.25|Build/FuseBiomeZone
Cube.069|MeshPart|0|58,23,7.5|-3484.25,17276,15711.25|Build/FuseBiomeZone
Cube.019|MeshPart|1|1.93,53.12,13.15|-3538.12,17333.23,15834.27|Build/FuseBiomeZone
Plane|MeshPart|1|11.23,23.43,0.01|-3538.15,17343.89,15834.31|Build/FuseBiomeZone
Cube.021|MeshPart|1|1.13,43.15,18.11|-3538.12,17338.26,15834.27|Build/FuseBiomeZone
Plane|MeshPart|1|15.19,31.69,0.01|-3702.84,17338.11,15738.64|Build/FuseBiomeZone
Cube.021|MeshPart|1|1.53,58.37,24.49|-3702.79,17330.49,15738.6|Build/FuseBiomeZone
Cube.018|MeshPart|1|7.97,150.58,26.59|-3706.49,17298.27,15740.74|Build/FuseBiomeZone
Cube.019|MeshPart|1|2.61,71.84,17.78|-3702.79,17323.68,15738.6|Build/FuseBiomeZone
Cube.019|MeshPart|1|1.24,34.15,8.45|-3434.68,17297.85,15806.32|Build/FuseBiomeZone
Cube.021|MeshPart|1|0.73,27.75,11.64|-3434.68,17301.09,15806.32|Build/FuseBiomeZone
Cube.018|MeshPart|1|3.79,71.58,12.64|-3434.68,17285.77,15808.35|Build/FuseBiomeZone
Cube.019|MeshPart|1|1.64,45.13,11.17|-3477.65,17302.23,15773.07|Build/FuseBiomeZone
Cube.018|MeshPart|1|5.01,94.58,16.7|-3477.65,17286.27,15775.76|Build/FuseBiomeZone
Plane|MeshPart|1|9.54,19.91,0.01|-3477.65,17311.29,15773.11|Build/FuseBiomeZone
Cube.021|MeshPart|1|0.96,36.66,15.38|-3477.65,17306.51,15773.07|Build/FuseBiomeZone
Cube.018|MeshPart|1|5.43,102.58,18.12|-3608.2,17285.27,15763.4|Build/FuseBiomeZone
Cube.019|MeshPart|1|1.78,48.94,12.11|-3606.75,17302.58,15760.87|Build/FuseBiomeZone
Cube.021|MeshPart|1|1.04,39.76,16.69|-3606.75,17307.22,15760.87|Build/FuseBiomeZone
Plane|MeshPart|1|10.35,21.59,0.01|-3606.77,17312.41,15760.91|Build/FuseBiomeZone
Cube.021|MeshPart|1|1.04,39.76,16.69|-3606.75,17307.22,15661.63|Build/FuseBiomeZone
Cube.018|MeshPart|1|5.43,102.58,18.12|-3608.2,17285.27,15659.1|Build/FuseBiomeZone
Plane|MeshPart|1|9.54,19.91,0.01|-3606.75,17311.14,15661.62|Build/FuseBiomeZone
Cube.019|MeshPart|1|1.78,48.94,12.11|-3606.75,17302.58,15661.63|Build/FuseBiomeZone
Cube.021|MeshPart|1|1.13,43.15,18.11|-3538.12,17338.26,15588.23|Build/FuseBiomeZone
Plane|MeshPart|1|9.54,19.91,0.01|-3538.13,17341.31,15588.22|Build/FuseBiomeZone
Cube.019|MeshPart|1|1.93,53.12,13.15|-3538.12,17333.23,15588.23|Build/FuseBiomeZone
Cube.018|MeshPart|1|5.01,94.58,16.7|-3477.65,17286.27,15646.74|Build/FuseBiomeZone
Cube.019|MeshPart|1|1.64,45.13,11.17|-3477.65,17302.23,15649.43|Build/FuseBiomeZone
Cube.021|MeshPart|1|0.96,36.66,15.38|-3477.65,17306.51,15649.43|Build/FuseBiomeZone
Cube.019|MeshPart|1|1.24,34.15,8.45|-3434.68,17297.85,15616.18|Build/FuseBiomeZone
Cube.018|MeshPart|1|3.79,71.58,12.64|-3434.68,17285.77,15614.15|Build/FuseBiomeZone
Cube.021|MeshPart|1|0.73,27.75,11.64|-3434.68,17301.09,15616.18|Build/FuseBiomeZone
Cube.019|MeshPart|1|2.61,71.84,17.78|-3702.79,17323.68,15683.9|Build/FuseBiomeZone
Cube.018|MeshPart|1|7.97,150.58,26.59|-3706.49,17298.27,15681.76|Build/FuseBiomeZone
Plane|MeshPart|1|12.62,26.32,0.01|-3702.82,17336.96,15683.88|Build/FuseBiomeZone
Cube.021|MeshPart|1|1.53,58.37,24.49|-3702.79,17330.49,15683.9|Build/FuseBiomeZone
Cube.025|MeshPart|1|38.52,108.52,159.02|-3275.34,17513.52,15588.78|Build/FuseBiomeZone
Cube.024|MeshPart|1|89.67,107.97,38.52|-3303.67,17499.42,15475.48|Build/FuseBiomeZone
Cube.022|MeshPart|1|51.27,126.43,51.27|-3256.33,17619.13,15492.04|Build/FuseBiomeZone
Cube.023|MeshPart|1|71.82,17.56,71.82|-3247.27,17550.6,15495.3|Build/FuseBiomeZone
Cube.022|MeshPart|1|51.27,126.43,51.27|-3238,17480.49,15498.63|Build/FuseBiomeZone
Cube.022|MeshPart|1|51.27,126.43,51.27|-3219.26,17338.68,15505.37|Build/FuseBiomeZone
Cube.025|MeshPart|1|38.52,108.52,159.02|-3321.46,17357.81,15468.29|Build/FuseBiomeZone
Cube.023|MeshPart|1|71.82,17.56,71.82|-3228.68,17409.98,15501.98|Build/FuseBiomeZone
Cube.022|MeshPart|1|51.27,126.43,51.27|-3206.94,17634.36,15870.1|Build/FuseBiomeZone
Cube.024|MeshPart|1|89.67,107.97,38.52|-3269.49,17384.79,15892.13|Build/FuseBiomeZone
Cube.024|MeshPart|1|89.67,107.97,38.52|-3231.4,17526.79,15802.98|Build/FuseBiomeZone
Cube.025|MeshPart|1|38.52,108.52,159.02|-3242.36,17385.22,15771.59|Build/FuseBiomeZone
Cube.023|MeshPart|1|71.82,17.56,71.82|-3206.94,17423.16,15870.1|Build/FuseBiomeZone
Cube.023|MeshPart|1|71.82,17.56,71.82|-3206.94,17565.16,15870.1|Build/FuseBiomeZone
Cube.025|MeshPart|1|38.52,108.52,159.02|-3280.24,17527.22,15896.78|Build/FuseBiomeZone
Cube.022|MeshPart|1|51.27,126.43,51.27|-3206.94,17351.16,15870.1|Build/FuseBiomeZone
Cube.022|MeshPart|1|51.27,126.43,51.27|-3206.94,17494.36,15870.1|Build/FuseBiomeZone
Cube.025|MeshPart|1|38.52,108.52,159.02|-3583.87,17366.9,15950.58|Build/FuseBiomeZone
Cube.023|MeshPart|1|71.82,17.56,71.82|-3685.87,17404.83,15927.05|Build/FuseBiomeZone
Cube.022|MeshPart|1|51.27,241.43,51.27|-3685.87,17275.33,15927.05|Build/FuseBiomeZone
Cube.024|MeshPart|1|89.67,107.97,38.52|-3670.54,17366.46,15862.53|Build/FuseBiomeZone
Cube.022|MeshPart|1|51.27,126.43,51.27|-3685.87,17476.03,15927.05|Build/FuseBiomeZone
Cube.023|MeshPart|1|71.82,17.56,71.82|-3685.87,17546.83,15927.05|Build/FuseBiomeZone
Cube.025|MeshPart|1|38.52,108.52,159.02|-3453.69,17508.9,15980.62|Build/FuseBiomeZone
Cube.025|MeshPart|1|38.52,108.52,159.02|-3595.56,17508.9,15947.88|Build/FuseBiomeZone
Cube.024|MeshPart|1|89.67,107.97,38.52|-3670.54,17508.46,15862.53|Build/FuseBiomeZone
Cube.022|MeshPart|1|51.27,126.43,51.27|-3685.87,17616.03,15927.05|Build/FuseBiomeZone
Cube.023|MeshPart|1|71.82,17.56,71.82|-3734.95,17404.82,15452.95|Build/FuseBiomeZone
Cube.025|MeshPart|1|38.52,108.52,159.02|-3630.3,17366.88,15455.45|Build/FuseBiomeZone
Cube.022|MeshPart|1|51.27,241.43,51.27|-3734.95,17275.32,15452.94|Build/FuseBiomeZone
Cube.024|MeshPart|1|89.67,107.97,38.52|-3736.1,17366.45,15519.25|Build/FuseBiomeZone
Cube.025|MeshPart|1|38.52,108.52,159.02|-3341.78,17604.81,15286.69|Build/FuseBiomeZone
Cube.025|MeshPart|1|38.52,108.52,159.02|-3402.24,17508.89,15382.15|Build/FuseBiomeZone
Cube.025|MeshPart|1|38.52,108.52,159.02|-3481.48,17604.81,15245.66|Build/FuseBiomeZone
Cube.025|MeshPart|1|38.52,108.52,159.02|-3546.71,17508.89,15400.25|Build/FuseBiomeZone
Cube.025|MeshPart|1|38.52,108.52,159.02|-3820.3,17563.89,15458.78|Build/FuseBiomeZone
Cube.025|MeshPart|1|38.52,108.52,159.02|-3901.37,17563.89,15330.2|Build/FuseBiomeZone
Cylinder.005|MeshPart|1|17,93.14,19.63|-3411.27,17496.01,16270.37|Build/FuseBiomeZone
Cube.029|MeshPart|1|161.82,211.75,155.66|-3471.44,17354.03,16277.16|Build/FuseBiomeZone
Cylinder.005|MeshPart|1|12.73,57.32,14.7|-3813.69,17517.9,15907.74|Build/FuseBiomeZone
Cylinder.004|MeshPart|1|91.34,172.82,105.47|-3784.15,17485.76,15379.94|Build/FuseBiomeZone
Cylinder.005|MeshPart|1|19.42,106.39,22.43|-3696.03,17608.8,15901.3|Build/FuseBiomeZone
Cylinder.005|MeshPart|1|19.42,106.39,22.43|-3664.03,17466.8,15913.81|Build/FuseBiomeZone
Cylinder.005|MeshPart|1|16.18,78.51,18.68|-3721.82,17455.2,15363.64|Build/FuseBiomeZone
Cube.029|MeshPart|1|133.52,174.72,128.44|-3868.58,17416.38,15860.11|Build/FuseBiomeZone
Cylinder.005|MeshPart|1|16.18,78.51,18.68|-3872.97,17528.49,15815.19|Build/FuseBiomeZone
Cylinder.004|MeshPart|1|66.5,125.82,76.79|-3871.59,17558.02,15869.93|Build/FuseBiomeZone
Cube.029|MeshPart|1|138.92,181.79,133.63|-3867.06,17409.87,15857.77|Build/FuseBiomeZone
Cylinder.005|MeshPart|1|14.03,76.85,16.2|-3824.76,17533.54,15884.11|Build/FuseBiomeZone
Cylinder.004|MeshPart|1|54.18,63.39,62.56|-3734.43,17371.83,15570.88|Build/FuseBiomeZone
Cylinder.005|MeshPart|1|64.08,311,73.99|-3251,17426.69,16245.21|Build/FuseBiomeZone
Cylinder.005|MeshPart|1|19.6,95.15,22.64|-3507.13,17489.9,16235.72|Build/FuseBiomeZone
Cube.029|MeshPart|1|312.4,408.8,300.51|-3240.78,17642.18,16488.54|Build/FuseBiomeZone
Cylinder.005|MeshPart|1|100.53,487.92,116.08|-3385.04,17515.15,15032.5|Build/FuseBiomeZone
Cylinder.005|MeshPart|1|35.93,174.39,41.49|-3349.35,17358.39,15945.94|Build/FuseBiomeZone
Cylinder.005|MeshPart|1|15.42,69.47,17.81|-3552.67,17477.06,16247.63|Build/FuseBiomeZone
Cylinder.005|MeshPart|1|64.08,311,73.99|-3251,17426.69,15177.29|Build/FuseBiomeZone
Cylinder.005|MeshPart|1|12.73,57.32,14.7|-3909.36,17517.9,15801.6|Build/FuseBiomeZone
Cylinder.004|MeshPart|1|54.18,102.51,62.56|-3734.43,17450.6,15570.88|Build/FuseBiomeZone
Cylinder.005|MeshPart|1|25.38,123.19,29.31|-3356.35,17332.78,16028.56|Build/FuseBiomeZone
Cylinder.004|MeshPart|1|80.6,152.49,93.07|-3467.57,17525.69,16289|Build/FuseBiomeZone
Cube.029|MeshPart|1|168.36,220.32,161.95|-3471.56,17346.13,16273.79|Build/FuseBiomeZone
Cylinder.005|MeshPart|1|92.51,448.98,106.82|-3882.04,17220.76,15184.5|Build/FuseBiomeZone
Cylinder.005|MeshPart|1|78.76,382.23,90.94|-3557.04,17462.31,15088.5|Build/FuseBiomeZone
Cylinder.004|MeshPart|1|38.81,90.41,44.82|-3734.43,17324.47,15570.88|Build/FuseBiomeZone
Cylinder.005|MeshPart|1|14.03,76.85,16.2|-3792.34,17459.2,15438.64|Build/FuseBiomeZone
Cylinder.005|MeshPart|1|25.44,123.46,29.37|-3348.69,17371.92,15797.53|Build/FuseBiomeZone
Cylinder.005|MeshPart|1|15.42,69.47,17.81|-3383.81,17477.06,16286.06|Build/FuseBiomeZone
Cube.029|MeshPart|1|312.4,408.8,300.51|-3993.25,17574.94,16458.05|Build/FuseBiomeZone
Cube.029|MeshPart|1|154.72,202.46,148.83|-3786,17319.55,15396.8|Build/FuseBiomeZone
Cylinder.005|MeshPart|1|100.53,487.92,116.08|-3134.04,17515.15,16217.52|Build/FuseBiomeZone
Cylinder.005|MeshPart|1|12.73,57.32,14.7|-3851.26,17446.55,15430.16|Build/FuseBiomeZone
Cube.029|MeshPart|1|160.98,210.65,154.85|-3782.94,17312,15395.77|Build/FuseBiomeZone
Cylinder.005|MeshPart|1|12.73,57.32,14.7|-3732.88,17443.49,15537.38|Build/FuseBiomeZone
Cylinder.011|MeshPart|1|19.58,21.88,49.73|-3508.57,17296.41,15667.9|Build/FuseBiomeZone
Cylinder.003|MeshPart|1|19.58,21.88,49.73|-3474.78,17281.13,15761.69|Build/FuseBiomeZone
Cylinder.010|MeshPart|1|30.03,9.04,0.73|-3419.01,17313.29,15711.71|Build/FuseBiomeZone
Cube.014|MeshPart|1|110.47,12.59,15.51|-3539.44,17308.6,15711.25|Build/FuseBiomeZone
Cylinder.003|MeshPart|1|16.06,17.94,40.78|-3435.52,17295.41,15779.31|Build/FuseBiomeZone
Cylinder.003|MeshPart|1|19.58,21.88,49.73|-3508.57,17296.41,15754.6|Build/FuseBiomeZone
Cylinder.010|MeshPart|1|83.51,25.15,2.04|-3544.2,17298.64,15711.06|Build/FuseBiomeZone
Cylinder.002|MeshPart|1|60.92,197.82,64.39|-3543.88,17259.31,15741.71|Build/FuseBiomeZone
Cylinder|MeshPart|1|60.92,197.82,64.39|-3543.88,17259.31,15680.79|Build/FuseBiomeZone
Cube.030|MeshPart|1|127.01,53.07,4.78|-3536.18,17281.77,15711.25|Build/FuseBiomeZone
Cube.020|MeshPart|1|26.33,55.18,18.76|-3542.39,17320.39,15692.83|Build/FuseBiomeZone
Cube.036|MeshPart|1|27.02,55.79,17.96|-3541.28,17319.43,15730.84|Build/FuseBiomeZone
Cube.008|MeshPart|1|2.15,29.14,29.14|-3542.81,17320.18,15711.25|Build/FuseBiomeZone
Cube.011|MeshPart|1|13.89,29.14,29.14|-3542.81,17320.18,15719.08|Build/FuseBiomeZone
Cube.010|MeshPart|1|13.89,29.14,29.14|-3542.81,17320.18,15703.42|Build/FuseBiomeZone
Cube.007|MeshPart|1|11.82,26.59,26.59|-3542.81,17320.18,15719.03|Build/FuseBiomeZone
Cube.013|MeshPart|1|11.82,26.59,26.59|-3542.81,17320.18,15703.47|Build/FuseBiomeZone
Emblem|MeshPart|1|13.38,64.8,8.29|-3542.92,17322.83,15711.25|Build/FuseBiomeZone
Cube.009|MeshPart|1|18,35.16,15.94|-3533.13,17323.25,15771.23|Build/FuseBiomeZone
Cube.032|MeshPart|1|15.28,35.85,13.69|-3533.75,17319.96,15770.79|Build/FuseBiomeZone
Cube.033|MeshPart|1|8.31,28.41,8.14|-3534.32,17320.57,15770.88|Build/FuseBiomeZone
Cube.035|MeshPart|1|8.31,28.41,8.14|-3534.32,17320.57,15651.62|Build/FuseBiomeZone
Cube.031|MeshPart|1|18,35.16,15.94|-3533.13,17323.25,15651.27|Build/FuseBiomeZone
Cube.034|MeshPart|1|15.28,35.85,13.69|-3533.75,17319.96,15651.71|Build/FuseBiomeZone
Cube.014|MeshPart|1|19.49,68.44,19.49|-3371.25,17367.72,15666.5|Build/FuseBiomeZone
Cube.012|MeshPart|1|19.33,39.23,19.33|-3371.25,17368.12,15666.5|Build/FuseBiomeZone
Cube.011|MeshPart|1|15.61,35.65,15.61|-3371.25,17363.93,15666.5|Build/FuseBiomeZone
Cube.014|MeshPart|1|19.49,68.44,19.49|-3380.25,17350.72,15624|Build/FuseBiomeZone
Cube.011|MeshPart|1|15.61,35.65,15.61|-3380.25,17346.93,15624|Build/FuseBiomeZone
Cube.012|MeshPart|1|19.33,39.23,19.33|-3380.25,17351.12,15624|Build/FuseBiomeZone
Cube.009|MeshPart|1|19.49,68.44,19.49|-3380.25,17350.72,15798.5|Build/FuseBiomeZone
Cube.009|MeshPart|1|19.49,68.44,19.49|-3371.25,17367.72,15756|Build/FuseBiomeZone
Cylinder.005|MeshPart|1|22.49,22.47,26.64|-3361.94,17335.91,15637.3|Build/FuseBiomeZone
Cylinder.007|MeshPart|1|23.32,23.2,27.48|-3362.1,17336.25,15637.29|Build/FuseBiomeZone
Cylinder.006|MeshPart|1|15.02,19.12,16.24|-3405.78,17330.62,15683.68|Build/FuseBiomeZone
Cylinder.003|MeshPart|1|15.57,19.8,16.91|-3405.78,17330.9,15683.71|Build/FuseBiomeZone
Cylinder.006|MeshPart|1|17.13,21.81,18.53|-3364.96,17349.1,15686.93|Build/FuseBiomeZone
Cylinder.003|MeshPart|1|17.76,22.59,19.29|-3365.07,17349.4,15686.91|Build/FuseBiomeZone
Cylinder.007|MeshPart|1|15.02,14.95,17.71|-3403.11,17318.03,15642.71|Build/FuseBiomeZone
Cylinder.005|MeshPart|1|14.49,14.48,17.17|-3403.09,17317.79,15642.77|Build/FuseBiomeZone
Cube.036|MeshPart|1|78.26,161.58,52.03|-3391.24,17285.9,16006.63|Build/FuseBiomeZone
Cube.020|MeshPart|1|76.33,159.96,54.38|-3524.88,17239.67,15852.28|Build/FuseBiomeZone
Cube.036|MeshPart|1|168.65,348.22,112.13|-3254.24,17262.31,15937.1|Build/FuseBiomeZone
Cube.036|MeshPart|1|372.58,769.27,247.71|-3001.58,17416.24,16376.7|Build/FuseBiomeZone
Cube.036|MeshPart|1|307.97,635.86,204.75|-3642.82,17087.37,16238.38|Build/FuseBiomeZone
Cube.036|MeshPart|1|106.08,219.03,70.53|-3729.28,17330.9,16052.41|Build/FuseBiomeZone
Cube.036|MeshPart|1|43.41,89.62,28.86|-3424.13,17250.79,15834.61|Build/FuseBiomeZone
Cube.036|MeshPart|1|168.65,348.22,112.13|-3189.36,17298.43,16115.88|Build/FuseBiomeZone
Cube.020|MeshPart|1|88.96,186.42,63.37|-3658.2,17227.44,15850.46|Build/FuseBiomeZone
Cube.036|MeshPart|1|307.97,635.86,204.75|-3577.27,16976.71,15999.1|Build/FuseBiomeZone
Cube.036|MeshPart|1|70.99,146.57,47.2|-3475.34,17246.91,15927.35|Build/FuseBiomeZone
Cube.036|MeshPart|1|43.41,89.62,28.86|-3491.97,17232.86,15804.59|Build/FuseBiomeZone
Cube.036|MeshPart|1|70.99,146.57,47.2|-3495.96,17280.41,15977.08|Build/FuseBiomeZone
Cube.036|MeshPart|1|372.58,769.27,247.71|-3896.64,17428.65,16218.65|Build/FuseBiomeZone
Cube.036|MeshPart|1|96.92,200.11,64.44|-3786.32,17232.38,15835.96|Build/FuseBiomeZone
Cube.036|MeshPart|1|106.08,219.03,70.53|-3513.17,17330.88,16124.01|Build/FuseBiomeZone
Cube.036|MeshPart|1|97.03,200.34,64.51|-3694.72,17288.16,15969.46|Build/FuseBiomeZone
Cube.036|MeshPart|1|96.92,200.11,64.44|-3786.32,17232.38,15586.54|Build/FuseBiomeZone
Cube.036|MeshPart|1|78.26,161.58,52.03|-3391.24,17285.9,15415.87|Build/FuseBiomeZone
Cube.036|MeshPart|1|70.99,146.57,47.2|-3495.96,17280.41,15445.42|Build/FuseBiomeZone
Cube.036|MeshPart|1|106.08,219.03,70.53|-3513.17,17330.88,15298.49|Build/FuseBiomeZone
Cube.036|MeshPart|1|168.65,348.22,112.13|-3189.36,17298.43,15306.63|Build/FuseBiomeZone
Cube.036|MeshPart|1|70.99,146.57,47.2|-3475.34,17246.91,15495.15|Build/FuseBiomeZone
Cube.036|MeshPart|1|168.65,348.22,112.13|-3254.24,17262.31,15485.4|Build/FuseBiomeZone
Cube.036|MeshPart|1|307.97,635.86,204.75|-3642.82,17087.37,15184.12|Build/FuseBiomeZone
Cube.036|MeshPart|1|372.58,769.27,247.71|-3001.58,17416.24,15045.8|Build/FuseBiomeZone
Cube.020|MeshPart|1|76.33,159.96,54.38|-3524.88,17239.67,15570.22|Build/FuseBiomeZone
Cube.036|MeshPart|1|97.03,200.34,64.51|-3694.72,17288.16,15453.04|Build/FuseBiomeZone
Cube.036|MeshPart|1|234.43,484.02,155.86|-3682.94,17718.6,15492.69|Build/FuseBiomeZone
Cube.036|MeshPart|1|106.08,219.03,70.53|-3729.28,17330.9,15370.09|Build/FuseBiomeZone
Cube.036|MeshPart|1|372.58,769.27,247.71|-3896.64,17428.65,15203.85|Build/FuseBiomeZone
Cube.020|MeshPart|1|88.96,186.42,63.37|-3658.2,17227.44,15572.04|Build/FuseBiomeZone
Cube.036|MeshPart|1|234.43,484.02,155.86|-3702.94,17694.65,15234.54|Build/FuseBiomeZone
Cube.036|MeshPart|1|43.41,89.62,28.86|-3491.97,17232.86,15617.91|Build/FuseBiomeZone
Cube.036|MeshPart|1|307.97,635.86,204.75|-3577.27,16976.71,15423.4|Build/FuseBiomeZone
Cube.036|MeshPart|1|234.43,484.02,155.86|-3479.09,17705.67,15470.2|Build/FuseBiomeZone
Cube.036|MeshPart|1|43.41,89.62,28.86|-3424.13,17250.79,15587.89|Build/FuseBiomeZone
Part|Part|1|2.05,5.86,2.05|-3402.87,17334.25,15735.77|Build/FuseBiomeZone
Part|Part|1|3,5,3|-3402.78,17331,15735.88|Build/FuseBiomeZone
Part|Part|1|2.64,3.84,2.64|-3403.17,17338.6,15735.95|Build/FuseBiomeZone
Fern1|MeshPart|1|25.72,6.72,22.28|-3402.8,17339.47,15735.84|Build/FuseBiomeZone
Part|Part|1|3.32,2.34,3.32|-3403.17,17338.6,15735.95|Build/FuseBiomeZone
Part|Part|1|2.72,7.76,2.72|-3402.14,17318.11,15789.14|Build/FuseBiomeZone
Part|Part|1|3.97,6.62,3.97|-3402.29,17313.81,15789.26|Build/FuseBiomeZone
Part|Part|1|4.39,3.09,4.39|-3402.38,17323.86,15788.74|Build/FuseBiomeZone
Fern1|MeshPart|1|34.04,8.9,29.49|-3402.24,17325.03,15789.23|Build/FuseBiomeZone
Part|Part|1|3.5,5.09,3.5|-3402.38,17323.86,15788.74|Build/FuseBiomeZone
Cube.174|MeshPart|0|6,13,19|-3402.5,17317.5,15701|Build/FuseBiomeZone
Cube.182|MeshPart|0|6,14,1|-3419.5,17322.5,15696.25|Build/FuseBiomeZone
Cube.174|MeshPart|0|6,13,7|-3402.5,17315.5,15700.75|Build/FuseBiomeZone
Cube.183|MeshPart|0|6,14,2|-3402,17332.5,15721.25|Build/FuseBiomeZone
Cube.174|MeshPart|0|6,13,7|-3402.5,17315.5,15721.75|Build/FuseBiomeZone
Cube.181|MeshPart|0|6,14,3|-3418.5,17322.5,15702.25|Build/FuseBiomeZone
Cube.183|MeshPart|0|6,14,2|-3402,17332.5,15701.25|Build/FuseBiomeZone
Cube.176|MeshPart|0|6,14,3|-3418.5,17322.5,15720.25|Build/FuseBiomeZone
Cube.175|MeshPart|0|11,6,6|-3390,17317.5,15704.75|Build/FuseBiomeZone
Cube.183|MeshPart|0|6,14,2|-3380,17338.5,15701.25|Build/FuseBiomeZone
Cube.175|MeshPart|0|11,6,6|-3390,17317.5,15717.75|Build/FuseBiomeZone
Cube.177|MeshPart|0|6,14,1|-3419.5,17322.5,15726.25|Build/FuseBiomeZone
Cube.183|MeshPart|0|6,14,2|-3380,17338.5,15721.25|Build/FuseBiomeZone
Cube.174|MeshPart|0|6,13,19|-3402.5,17317.5,15721.5|Build/FuseBiomeZone
Cylinder.006|MeshPart|1|19.76,0.62,19.76|-3461.57,17286.14,15699.17|Build/FuseBiomeZone
Cylinder.008|MeshPart|1|19.76,0.62,19.76|-3461.57,17286.14,15723.33|Build/FuseBiomeZone
Cube.040|MeshPart|0|17.86,32.16,0.51|-3387.25,17302.58,15711.25|Build/FuseBiomeZone
MainPart|MeshPart|0|66,3.93,139.25|-3417.37,17284.15,15711.25|Build/FuseBiomeZone
Cube.039|MeshPart|0|11,13,3.68|-3414.84,17297,15730.75|Build/FuseBiomeZone
MainPart|MeshPart|1|66,3.93,139.25|-3417.37,17284.2,15711.25|Build/FuseBiomeZone
Cube.042|MeshPart|0|52.78,0.57,52.3|-3460.85,17286.12,15711.25|Build/FuseBiomeZone
Cube.041|MeshPart|0|24,34,13|-3380.78,17302.94,15711.25|Build/FuseBiomeZone
Plane|MeshPart|1|19.65,32.48,12.19|-3380.09,17302.74,15711.25|Build/FuseBiomeZone
Cube.006|MeshPart|0|11,13,3.68|-3414.84,17297,15691.75|Build/FuseBiomeZone
FireCLoud|MeshPart|1|1331.73,542.42,1003.07|-3347.74,17507.5,15294.67|Build/FuseBiomeZone
NormalCloud|MeshPart|1|1377.45,598.68,1002.14|-3320,17967.77,15932.21|Build/FuseBiomeZone
Cube.054|Part|1|20,29,27|-3386.5,17265,15614.25|Build/FuseBiomeZone
Cube.065|Part|1|25,9,28|-3384,17320,15751.75|Build/FuseBiomeZone
Cube.062|Part|1|9,4,25|-3388.5,17330.5,15726.75|Build/FuseBiomeZone
Cube.052|Part|1|27,36,14|-3396,17298.5,15666.75|Build/FuseBiomeZone
Cube.047|Part|1|50,35,29|-3358.79,17282,15819.25|Build/FuseBiomeZone
Cube.053|Part|1|51,29,14|-3407,17265,15638.75|Build/FuseBiomeZone
Cube.060|Part|1|18,9,34|-3390,17323,15691.25|Build/FuseBiomeZone
Cube.058|Part|1|18,15,14|-3404,17313,15737.25|Build/FuseBiomeZone
Cube.050|Part|0|46,24,14|-3405,17292.5,15668.25|Build/FuseBiomeZone
Cube.055|Part|1|45,35,40|-3389,17281,15881.75|Build/FuseBiomeZone
Cube.047|Part|1|27,35,37|-3375.5,17298,15797.75|Build/FuseBiomeZone
Cube.049|Part|1|31,30,27|-3355.5,17312.5,15785.75|Build/FuseBiomeZone
Cube.062|Part|1|9,4,25|-3388.5,17330.5,15695.75|Build/FuseBiomeZone
Cube.046|Part|1|20,29,27|-3386.5,17265,15808.25|Build/FuseBiomeZone
Cube.055|Part|1|45,35,40|-3396.76,17268,15862.64|Build/FuseBiomeZone
Cube.044|Part|1|27,36,14|-3396,17298.5,15755.75|Build/FuseBiomeZone
Cube.045|Part|1|51,29,14|-3407,17265,15783.75|Build/FuseBiomeZone
Cube.059|Part|1|18,15,14|-3404,17313,15685.25|Build/FuseBiomeZone
Cube.055|Part|1|58,35,49|-3336.5,17303,15625.25|Build/FuseBiomeZone
Cube.055|Part|1|58,35,49|-3352.72,17278,15610.94|Build/FuseBiomeZone
Cube.048|Part|1|41,35,18|-3375,17315,15759.75|Build/FuseBiomeZone
Cube.063|Part|1|18,9,34|-3390,17323,15731.25|Build/FuseBiomeZone
Cube.043|Part|1|46,29,14|-3401,17295,15778.25|Build/FuseBiomeZone
Cube.064|Part|1|21,11,25|-3363.5,17334,15689.75|Build/FuseBiomeZone
Cube.051|Part|1|46,29,14|-3401,17295,15644.25|Build/FuseBiomeZone
Cube.057|Part|1|31,30,27|-3355.5,17312.5,15636.75|Build/FuseBiomeZone
Cube.061|Part|1|25,9,28|-3384,17320,15670.75|Build/FuseBiomeZone
Cube.002|Part|0|46,24,14|-3405,17292.5,15754.25|Build/FuseBiomeZone
Cube.064|Part|1|21,11,25|-3363.5,17334,15732.75|Build/FuseBiomeZone
Cube.047|Part|1|62,35,29|-3340.92,17298,15813.14|Build/FuseBiomeZone
Cube.056|Part|1|41,35,18|-3375,17315,15662.75|Build/FuseBiomeZone
Cube.055|Part|1|27,35,37|-3375.5,17298,15624.75|Build/FuseBiomeZone
Cube.047|Part|1|27,1,37|-3375.5,17316,15797.75|Build/FuseBiomeZone
Cube.054|Part|1|20,1,27|-3386.5,17280,15614.25|Build/FuseBiomeZone
Cube.053|Part|1|51,1,14|-3407,17280,15638.75|Build/FuseBiomeZone
Cube.057|Part|1|31,1,27|-3355.5,17328,15636.75|Build/FuseBiomeZone
Cube.058|Part|1|18,1,14|-3404,17321,15737.25|Build/FuseBiomeZone
Cube.047|Part|1|50,1,29|-3358.79,17300,15819.25|Build/FuseBiomeZone
Cube.055|Part|1|58,1,49|-3352.72,17296,15610.94|Build/FuseBiomeZone
Cube.047|Part|1|62,1,29|-3340.92,17316,15813.14|Build/FuseBiomeZone
Cube.049|Part|1|31,1,27|-3355.5,17328,15785.75|Build/FuseBiomeZone
Cube.048|Part|1|41,1,18|-3375,17333,15759.75|Build/FuseBiomeZone
Cube.055|Part|1|58,1,49|-3336.5,17321,15625.25|Build/FuseBiomeZone
Cube.046|Part|1|20,1,27|-3386.5,17280,15808.25|Build/FuseBiomeZone
Cube.056|Part|1|41,1,18|-3375,17333,15662.75|Build/FuseBiomeZone
Cube.062|Part|1|9,1,25|-3388.5,17333,15726.75|Build/FuseBiomeZone
Cube.062|Part|1|9,1,25|-3388.5,17333,15695.75|Build/FuseBiomeZone
Cube.002|Part|1|46,1,14|-3405,17305,15754.25|Build/FuseBiomeZone
Cube.064|Part|1|21,1,25|-3363.5,17340,15732.75|Build/FuseBiomeZone
Cube.052|Part|1|27,1,14|-3396,17317,15666.75|Build/FuseBiomeZone
Cube.059|Part|1|18,1,14|-3404,17321,15685.25|Build/FuseBiomeZone
Cube.043|Part|1|46,1,14|-3401,17310,15778.25|Build/FuseBiomeZone
Cube.050|Part|1|46,1,14|-3405,17305,15668.25|Build/FuseBiomeZone
Cube.055|Part|1|45,1,40|-3389,17299,15881.75|Build/FuseBiomeZone
Cube.060|Part|1|18,1,34|-3390,17328,15691.25|Build/FuseBiomeZone
Cube.064|Part|1|21,1,25|-3363.5,17340,15689.75|Build/FuseBiomeZone
Cube.045|Part|1|51,1,14|-3407,17280,15783.75|Build/FuseBiomeZone
Cube.051|Part|1|46,1,14|-3401,17310,15644.25|Build/FuseBiomeZone
Cube.065|Part|1|25,1,28|-3384,17325,15751.75|Build/FuseBiomeZone
Cube.061|Part|1|25,1,28|-3384,17325,15670.75|Build/FuseBiomeZone
Cube.063|Part|1|18,1,34|-3390,17328,15731.25|Build/FuseBiomeZone
Cube.044|Part|1|27,1,14|-3396,17317,15755.75|Build/FuseBiomeZone
Cube.055|Part|1|45,1,40|-3396.76,17286,15862.64|Build/FuseBiomeZone
Cube.055|Part|1|27,1,37|-3375.5,17316,15624.75|Build/FuseBiomeZone
Cube.077|Part|0|23,69,34|-3435,17248,15760.75|Build/FuseBiomeZone
Cube.154|Part|0|11,2,6|-3415,17304.5,15691.75|Build/FuseBiomeZone
Cube.148|Part|1|6,9,16|-3404,17325,15703.25|Build/FuseBiomeZone
Cube.142|Part|0|1,28,6|-3396,17300.5,15697.75|Build/FuseBiomeZone
Cube.079|Part|0|2,1,14|-3429,17284,15674.25|Build/FuseBiomeZone
Cube.066|Part|0|68,73,7|-3511.5,17253,15711.25|Build/FuseBiomeZone
Cube.147|Part|1|6,9,16|-3404,17325,15719.25|Build/FuseBiomeZone
Cube|Part|0|72,73,15|-3500.5,17253,15711.25|Build/FuseBiomeZone
Cube.082|Part|0|11,3,4|-3415,17288,15730.75|Build/FuseBiomeZone
Cube.077|Part|0|3,70,34|-3435,17248.5,15648.75|Build/FuseBiomeZone
Cube.096|Part|0|9,46,6|-3415,17282.5,15785.75|Build/FuseBiomeZone
Cube.092|Part|0|15,2,7|-3415.5,17308.5,15740.75|Build/FuseBiomeZone
Cube.146|Part|0|10,2,16|-3404,17323.5,15711.25|Build/FuseBiomeZone
Cube.079|Part|0|3,49,34|-3435,17259,15671.75|Build/FuseBiomeZone
Cube.125|Part|0|2,25,70|-3458,17274,15741.25|Build/FuseBiomeZone
Cube.166|Part|1|7,79,7|-3508.5,17253,15747.75|Build/FuseBiomeZone
Cube.114|Part|1|19,5,7|-3415.5,17312,15636.75|Build/FuseBiomeZone
Cube.074|Part|0|4,73,16|-3485,17250,15675.25|Build/FuseBiomeZone
Cube.130|Part|0|2,0.2,31|-3433.5,17282.6,15652.25|Build/FuseBiomeZone
Cube.126|Part|1|1,25,64|-3405,17274,15719.75|Build/FuseBiomeZone
Cube.083|Part|0|2,28,6|-3415,17300.5,15724.25|Build/FuseBiomeZone
Cube.136|Part|0|3,4,7|-3402.5,17288.5,15726.75|Build/FuseBiomeZone
Cube.149|Part|0|12,1,3|-3418.5,17329,15711.25|Build/FuseBiomeZone
Cube.109|Part|0|78.25,1,9|-3415.5,17315,15662.38|Build/FuseBiomeZone
Cube.168|Part|1|2,2,19|-3385.5,17334.5,15701.25|Build/FuseBiomeZone
Cube.144|Part|0|4,1,7|-3402.5,17291,15696.25|Build/FuseBiomeZone
Cube.090|Part|0|11,3,4|-3415,17288,15691.75|Build/FuseBiomeZone
Cube.158|Part|0|11,9,5|-3414.5,17310,15730.75|Build/FuseBiomeZone
Cube.067|Part|0|62,73,3|-3516.5,17253,15711.25|Build/FuseBiomeZone
Cube.164|Part|1|2,2,19|-3385.5,17334.5,15721.25|Build/FuseBiomeZone
Cube.143|Part|0|1,28,7|-3402.5,17300.5,15693.75|Build/FuseBiomeZone
Cube.159|Part|1|20,24.62,39|-3392.5,17273.81,15711.25|Build/FuseBiomeZone
Cube.070|Part|0|2,73,81|-3452.5,17250,15744.25|Build/FuseBiomeZone
Cube.130|Part|0|19,0.2,2|-3450,17282.6,15660.75|Build/FuseBiomeZone
Cube.127|Part|1|20,25,2|-3424,17274,15730.25|Build/FuseBiomeZone
Cube.130|Part|0|19,0.2,2|-3450,17282.6,15761.75|Build/FuseBiomeZone
Cube.115|Part|1|4,16,6|-3415,17251.5,15639.25|Build/FuseBiomeZone
Cube.124|Part|0|22,25,49|-3397.5,17274,15690.25|Build/FuseBiomeZone
Cube.172|Part|1|7,75,7|-3465.5,17251,15749.75|Build/FuseBiomeZone
Cube.073|Part|0|2,73,81|-3452.5,17250,15678.25|Build/FuseBiomeZone
Cube.077|Part|0|23,69,34|-3435,17248,15661.75|Build/FuseBiomeZone
Cube.106|Part|0|11,2,7|-3415.5,17306.5,15681.75|Build/FuseBiomeZone
Cube.136|Part|0|4,1,7|-3402.5,17291,15726.25|Build/FuseBiomeZone
Cube.160|Part|0|2,34,6|-3390,17303.5,15724.25|Build/FuseBiomeZone
Cube.091|Part|0|11,2,7|-3415.5,17306.5,15740.75|Build/FuseBiomeZone
Cube.124|Part|0|20,25,14|-3380,17274,15711.25|Build/FuseBiomeZone
Cube.072|Part|0|50,73,2|-3519,17253,15711.25|Build/FuseBiomeZone
Cube.167|Part|1|7,79,7|-3520.5,17253,15686.75|Build/FuseBiomeZone
Cube.102|Part|0|5,46,1|-3418.5,17282.5,15785.75|Build/FuseBiomeZone
Cube.169|Part|1|2,2,22|-3362,17340.5,15701.25|Build/FuseBiomeZone
Cube.098|Part|1|15,2,7|-3415.5,17308.5,15785.75|Build/FuseBiomeZone
Cube.132|Part|0|1,28,6|-3409,17300.5,15724.75|Build/FuseBiomeZone
Cube.074|Part|0|1,25,12|-3487,17274,15679.75|Build/FuseBiomeZone
Cube.080|Part|0|9,19,6|-3415,17296,15740.75|Build/FuseBiomeZone
Cube.131|Part|0|4,28,1|-3406.5,17300.5,15727.25|Build/FuseBiomeZone
Cube.123|Part|0|22,25,49|-3397.5,17274,15732.25|Build/FuseBiomeZone
Cube.153|Part|0|22,1,6|-3414,17329,15711.25|Build/FuseBiomeZone
Cube.088|Part|0|9,19,6|-3415,17296,15681.75|Build/FuseBiomeZone
Cube.155|Part|0|11,9,5|-3414.5,17310,15691.75|Build/FuseBiomeZone
Cube.141|Part|0|4,28,1|-3398.5,17300.5,15695.25|Build/FuseBiomeZone
Cube.077|Part|0|26,70,3|-3453.5,17248.5,15660.25|Build/FuseBiomeZone
Cube.089|Part|0|11,1,6|-3415,17290,15691.75|Build/FuseBiomeZone
Cube.077|Part|1|23,69,34|-3435,17248.06,15661.75|Build/FuseBiomeZone
Cube.133|Part|0|4,28,1|-3398.5,17300.5,15727.25|Build/FuseBiomeZone
Cube.120|Part|0|30,73,6|-3415,17250,15662.25|Build/FuseBiomeZone
Cube.166|Part|1|7,79,7|-3508.5,17253,15674.75|Build/FuseBiomeZone
Cube.116|Part|1|3,9,6|-3415,17255,15635.75|Build/FuseBiomeZone
Cube.145|Part|0|3,1,7|-3402.5,17306,15695.75|Build/FuseBiomeZone
Cube.078|Part|0|2,1,14|-3429,17285,15746.25|Build/FuseBiomeZone
Cube.123|Part|1|20,35,1|-3373.5,17303,15711.25|Build/FuseBiomeZone
Cube.135|Part|0|1,28,7|-3402.5,17300.5,15728.75|Build/FuseBiomeZone
Cube.077|Part|0|3,70,34|-3435,17248.5,15773.75|Build/FuseBiomeZone
Cube.134|Part|0|1,28,6|-3396,17300.5,15724.75|Build/FuseBiomeZone
Cube.112|Part|1|11,2,7|-3415.5,17306.5,15636.75|Build/FuseBiomeZone
Cube.117|Part|0|5,46,1|-3418.5,17282.5,15636.75|Build/FuseBiomeZone
Cube.130|Part|1|20,25,2|-3424,17274,15692.25|Build/FuseBiomeZone
Cube.150|Part|1|10,5,15|-3403.5,17327,15711.25|Build/FuseBiomeZone
Cube.113|Part|1|15,2,7|-3415.5,17308.5,15636.75|Build/FuseBiomeZone
Cube.122|Part|0|2,25,15|-3485.5,17274,15681.25|Build/FuseBiomeZone
Cube.111|Part|0|9,46,6|-3415,17282.5,15636.75|Build/FuseBiomeZone
Cube.084|Part|0|4,25,30|-3451,17274,15675.25|Build/FuseBiomeZone
Cube.167|Part|1|7,79,7|-3520.5,17253,15735.75|Build/FuseBiomeZone
Cube.156|Part|0|11,2,6|-3415,17304.5,15730.75|Build/FuseBiomeZone
Cube.104|Part|0|30,25,6|-3415,17274,15760.25|Build/FuseBiomeZone
Cube.079|Part|0|3,49,34|-3435,17259,15750.75|Build/FuseBiomeZone
Cube.138|Part|0|2,2,10|-3388,17319.79,15711.25|Build/FuseBiomeZone
Cube.139|Part|0|4,28,1|-3406.5,17300.5,15695.25|Build/FuseBiomeZone
Cube.094|Part|0|78.25,1,9|-3415.5,17315,15760.13|Build/FuseBiomeZone
Cube.077|Part|1|23,69,34|-3435,17248.06,15760.75|Build/FuseBiomeZone
Cube.157|Part|0|2,34,6|-3390,17303.5,15698.25|Build/FuseBiomeZone
Cube.137|Part|0|3,1,7|-3402.5,17306,15726.75|Build/FuseBiomeZone
Cube.099|Part|1|19,5,7|-3415.5,17312,15785.75|Build/FuseBiomeZone
Cube.097|Part|1|11,2,7|-3415.5,17306.5,15785.75|Build/FuseBiomeZone
Cube.076|Part|0|4,3,4|-3420,17285,15675.25|Build/FuseBiomeZone
Cube.128|Part|1|2,25,55|-3450.5,17274,15681.25|Build/FuseBiomeZone
Cube.107|Part|0|15,2,7|-3415.5,17308.5,15681.75|Build/FuseBiomeZone
Cube.161|Part|1|24,2,1|-3419.5,17330.5,15711.25|Build/FuseBiomeZone
Cube.129|Part|1|1,25,64|-3405,17274,15702.75|Build/FuseBiomeZone
Cube.137|Part|0|2,6,7|-3402.5,17309.5,15727.25|Build/FuseBiomeZone
Cube.076|Part|0|4,3,4|-3420,17285,15747.25|Build/FuseBiomeZone
Cube.077|Part|0|26,70,3|-3453.5,17248.5,15762.25|Build/FuseBiomeZone
Cube.071|Part|0|4,73,16|-3485,17250,15747.25|Build/FuseBiomeZone
Cube.110|Part|1|70,2,1|-3419.5,17316.5,15658.25|Build/FuseBiomeZone
Cube.108|Part|0|19,5,7|-3415.5,17312,15681.75|Build/FuseBiomeZone
Cube.140|Part|0|1,28,6|-3409,17300.5,15697.75|Build/FuseBiomeZone
Cube.076|Part|0|4,73,30|-3451,17250,15747.25|Build/FuseBiomeZone
Cube.152|Part|0|1,13,5|-3414.5,17322,15721.75|Build/FuseBiomeZone
Cube.151|Part|0|1,13,5|-3414.5,17322,15700.75|Build/FuseBiomeZone
Cube.163|Part|1|71,2,1|-3411.5,17316.5,15658.75|Build/FuseBiomeZone
Cube.081|Part|0|11,1,6|-3415,17290,15730.75|Build/FuseBiomeZone
Cube.093|Part|0|19,5,7|-3415.5,17312,15740.75|Build/FuseBiomeZone
Cube.118|Part|0|5,19,1|-3418.5,17296,15681.75|Build/FuseBiomeZone
Cube.138|Part|0|10,2,10|-3391,17321.5,15711.25|Build/FuseBiomeZone
Cube.165|Part|1|2,2,22|-3362,17340.5,15721.25|Build/FuseBiomeZone
Cube.145|Part|0|2,6,7|-3402.5,17309.5,15695.25|Build/FuseBiomeZone
Cube.172|Part|1|7,75,7|-3465.5,17251,15672.75|Build/FuseBiomeZone
Cube.130|Part|0|2,0.2,31|-3433.5,17282.6,15770.25|Build/FuseBiomeZone
Cube.079|Part|0|2,1,14|-3429,17284,15748.25|Build/FuseBiomeZone
Cube.105|Part|0|2,28,6|-3415,17300.5,15698.25|Build/FuseBiomeZone
Cube.100|Part|1|4,16,6|-3415,17251.5,15783.25|Build/FuseBiomeZone
Cube.074|Part|0|1,25,12|-3487,17274,15742.75|Build/FuseBiomeZone
Cube.095|Part|1|70,2,1|-3419.5,17316.5,15764.25|Build/FuseBiomeZone
Cube.101|Part|1|3,9,6|-3415,17255,15786.75|Build/FuseBiomeZone
Cube.162|Part|1|71,2,1|-3411.5,17316.5,15763.75|Build/FuseBiomeZone
Cube.144|Part|0|3,4,7|-3402.5,17288.5,15695.75|Build/FuseBiomeZone
Cube.086|Part|0|2,1,14|-3429,17285,15676.25|Build/FuseBiomeZone
Cube.103|Part|0|5,19,1|-3418.5,17296,15740.75|Build/FuseBiomeZone
part|Part|0|17,3,4.19|-3509.58,17291,15688|Build/FuseBiomeZone
part|Part|0|54,3,7|-3513.5,17291,15711.25|Build/FuseBiomeZone
part|Part|0|17,3,4.19|-3509.58,17291,15734.5|Build/FuseBiomeZone
part|Part|0|17,1,3|-3503.2,17290,15732.79|Build/FuseBiomeZone
part|Part|0|13,3,4.6|-3511.7,17291,15736.75|Build/FuseBiomeZone
part|Part|0|17,2,3|-3506.1,17290.5,15688.93|Build/FuseBiomeZone
part|Part|1|19,1,3|-3503.98,17290,15692.61|Build/FuseBiomeZone
part|Part|1|19,1,3|-3503.98,17290,15729.89|Build/FuseBiomeZone
part|Part|1|15,2,3|-3506.36,17290.5,15732.6|Build/FuseBiomeZone
part|Part|0|13,3,4.6|-3511.7,17291,15685.75|Build/FuseBiomeZone
part|Part|1|15,2,3|-3506.36,17290.5,15689.9|Build/FuseBiomeZone
part|Part|0|17,1,3|-3503.2,17290,15689.71|Build/FuseBiomeZone
part|Part|0|17,2,3|-3506.1,17290.5,15733.57|Build/FuseBiomeZone
part|Part|1|15,2,3.19|-3509.35,17291.5,15733.4|Build/FuseBiomeZone
part|Part|1|15,2,3.19|-3509.35,17291.5,15689.1|Build/FuseBiomeZone
part|Part|1|1,1,3|-3516.5,17290,15680.75|Build/FuseBiomeZone
part|Part|1|7,1,1|-3493.5,17290,15743.75|Build/FuseBiomeZone
part|Part|1|26,1,1|-3417.5,17287,15762.25|Build/FuseBiomeZone
part|Part|1|1,1,14|-3484,17287,15748.75|Build/FuseBiomeZone
part|Part|1|1,1,1|-3465.5,17287,15745.75|Build/FuseBiomeZone
part|Part|1|1,1,26|-3449,17287,15748.75|Build/FuseBiomeZone
part|Part|1|5,1,1|-3436.5,17287,15676.75|Build/FuseBiomeZone
part|Part|1|1,1,1|-3465.5,17287,15676.75|Build/FuseBiomeZone
part|Part|1|1,1,4|-3419,17287,15673.75|Build/FuseBiomeZone
part|Part|1|1,1,4|-3419,17287,15748.75|Build/FuseBiomeZone
part|Part|1|5,1,1|-3436.5,17287,15745.75|Build/FuseBiomeZone
part|Part|1|1,1,4|-3492,17290,15739.75|Build/FuseBiomeZone
part|Part|1|1,1,5|-3414.5,17287,15647.75|Build/FuseBiomeZone
part|Part|1|1,1,26|-3449,17287,15673.75|Build/FuseBiomeZone
part|Part|1|1,1,12|-3500,17290,15675.75|Build/FuseBiomeZone
part|Part|1|6,1,1|-3421.5,17287,15676.25|Build/FuseBiomeZone
part|Part|1|7,1,1|-3493.5,17290,15678.75|Build/FuseBiomeZone
part|Part|1|1,1,12|-3500,17290,15746.75|Build/FuseBiomeZone
part|Part|1|1,1,4|-3492,17290,15682.75|Build/FuseBiomeZone
part|Part|1|6,1,1|-3421.5,17287,15746.25|Build/FuseBiomeZone
part|Part|1|1,1,2|-3517.5,17290,15682.25|Build/FuseBiomeZone
part|Part|1|1,1,14|-3484,17287,15673.75|Build/FuseBiomeZone
part|Part|1|1,1,12|-3471,17287,15677.75|Build/FuseBiomeZone
part|Part|1|1,1,37|-3436.5,17284,15774.75|Build/FuseBiomeZone
part|Part|1|1,1,2|-3517.5,17290,15740.25|Build/FuseBiomeZone
part|Part|1|25,1,1|-3454.5,17284,15761.75|Build/FuseBiomeZone
part|Part|1|25,1,1|-3454.5,17284,15660.75|Build/FuseBiomeZone
part|Part|1|4,1,1|-3477.5,17287,15676.25|Build/FuseBiomeZone
part|Part|1|1,1,42|-3519.5,17290,15711.25|Build/FuseBiomeZone
part|Part|1|26,1,1|-3417.5,17287,15660.25|Build/FuseBiomeZone
part|Part|1|1,1,3|-3514.5,17290,15679.75|Build/FuseBiomeZone
part|Part|1|1,1,3|-3516.5,17290,15741.75|Build/FuseBiomeZone
part|Part|1|1,1,12|-3471,17287,15744.75|Build/FuseBiomeZone
part|Part|1|1,1,3|-3513.5,17290,15744.75|Build/FuseBiomeZone
part|Part|1|4,1,1|-3477.5,17287,15746.25|Build/FuseBiomeZone
part|Part|1|1,1,3|-3513.5,17290,15677.75|Build/FuseBiomeZone
part|Part|1|1,1,3|-3514.5,17290,15742.75|Build/FuseBiomeZone
part|Part|1|1,1,37|-3436.5,17284,15647.75|Build/FuseBiomeZone
part|Part|1|1,1,5|-3414.5,17287,15774.75|Build/FuseBiomeZone
Cube|Part|1|1,2,2|-3500.5,17323,15710.75|Build/FuseBiomeZone
Cube|Part|1|2,2,2|-3500.5,17320,15711.25|Build/FuseBiomeZone
Waterfalls|MeshPart|0|563.11,312.18,324.63|-3534.8,17417.85,15853.09|Build/FuseBiomeZone
Lavafalls|MeshPart|0|500.42,317,264.85|-3542.44,17452.11,15535.05|Build/FuseBiomeZone
Lava|MeshPart|0|67.92,24.95,88.06|-3385.05,17328.25,15667.22|Build/FuseBiomeZone
Water|MeshPart|0|67.92,25.15,88.06|-3385.05,17328.15,15755.28|Build/FuseBiomeZone
Part|Part|0|865.11,34.75,182|4697.97,50.2,-363.81|Build/TitanTempleZone
Part|Part|0|186.19,2,8.56|556.54,105.03,-190.76|Build/MainMap
Part|Part|0|8.56,36.94,183.92|556.54,85.56,-191.92|Build/MainMap
Part|Part|0|8.56,36.94,185.31|556.3,85.56,-532.28|Build/MainMap
Part|Part|0|529.04,2,8.56|320.57,105.03,-360.07|Build/MainMap
Part|Part|0|182.5,2,8.56|556.18,105.03,-534.8|Build/MainMap
Part|Part|0|244.27,2,8.56|438.32,105.03,-626.11|Build/MainMap
Part|Part|0|8.56,36.94,244.31|438.31,85.56,-626.11|Build/MainMap
Part|Part|0|8.56,36.94,246.23|437.7,85.56,-102.14|Build/MainMap
Part|Part|0|243.14,2,8.56|439.25,105.03,-102.14|Build/MainMap
Part|Part|0|8.56,36.94,526.87|320.57,85.56,-361.16|Build/MainMap
Part|Part|0|14.96,1,517.41|544.58,67.08,-364.87|Build/MainMap
Part|Part|0|215.16,1,518.5|429.52,67.08,-364.1|Build/MainMap
Part|Part|1|4.78,2.72,5.59|1238.02,68.93,-445.86|Build/MainMap
Part|Part|1|4.78,4.23,5.59|1236.46,69.69,-449.01|Build/MainMap
Part|Part|1|4.78,1.31,5.59|1233.99,68.23,-446.28|Build/MainMap
Part|Part|1|4.78,2.12,5.59|1232.7,68.63,-449.69|Build/MainMap
Cylinder.034|MeshPart|1|11.44,2.3,11.44|6513.32,17124.38,15644.91|Build/EnchantedTreeInterior
Cylinder.035|MeshPart|1|9.27,0.53,9.27|6513.32,17125.5,15644.91|Build/EnchantedTreeInterior
Cylinder.034|MeshPart|1|11.44,2.3,11.44|6551.94,17124.38,15660.9|Build/EnchantedTreeInterior
Cylinder.035|MeshPart|1|9.27,0.53,9.27|6551.94,17125.5,15660.9|Build/EnchantedTreeInterior
Cylinder.034|MeshPart|1|11.44,2.3,11.44|6513.32,17124.38,15754.13|Build/EnchantedTreeInterior
Cylinder.035|MeshPart|1|9.27,0.53,9.27|6513.32,17125.5,15754.13|Build/EnchantedTreeInterior
Cylinder.035|MeshPart|1|9.27,0.53,9.27|6551.94,17125.5,15738.13|Build/EnchantedTreeInterior
Cylinder.034|MeshPart|1|11.44,2.3,11.44|6551.94,17124.38,15738.13|Build/EnchantedTreeInterior
GlowingFlower|MeshPart|1|27.64,17,27.63|6472.39,17252.6,15670.89|Build/EnchantedTreeInterior
GlowingFlower|MeshPart|1|18.48,13.8,18.47|6576.06,17151.45,15683.18|Build/EnchantedTreeInterior
GlowingFlower|MeshPart|1|18.48,9.83,18.47|6552.79,17181.09,15650.06|Build/EnchantedTreeInterior
GlowingFlower|MeshPart|1|42.79,13.48,42.78|6459.71,17317.4,15741.75|Build/EnchantedTreeInterior
GlowingFlower|MeshPart|1|18.48,5.82,18.47|6546.96,17140.41,15756.49|Build/EnchantedTreeInterior
GlowingFlower|MeshPart|1|17.53,5.52,17.53|6076.07,17032.5,15678.92|Build/EnchantedTreeInterior
GlowingFlower|MeshPart|1|7.26,2.29,7.26|6054.62,17020.86,15774.31|Build/EnchantedTreeInterior
GlowingFlower|MeshPart|1|42.79,13.48,42.78|6532.14,17210.16,15797.89|Build/EnchantedTreeInterior
GlowingFlower|MeshPart|1|15.04,5.33,15.03|6080.81,17240.55,15707.85|Build/EnchantedTreeInterior
GlowingFlower|MeshPart|1|19.26,6.07,19.25|6137.43,17075.79,15699.54|Build/EnchantedTreeInterior
GlowingFlower|MeshPart|1|47.77,16.94,47.75|6433.9,17145.82,15624.7|Build/EnchantedTreeInterior
GlowingFlower|MeshPart|1|16.35,5.15,16.35|6141.97,17059.94,15723.03|Build/EnchantedTreeInterior
GlowingFlower|MeshPart|1|42.79,13.48,42.78|6425.17,17181.66,15767.31|Build/EnchantedTreeInterior
GlowingFlower|MeshPart|1|10.48,3.3,10.48|6119.76,17042.44,15795.99|Build/EnchantedTreeInterior
GlowingFlower|MeshPart|1|10.48,3.3,10.48|6056.23,17024.37,15798.8|Build/EnchantedTreeInterior
GlowingFlower|MeshPart|1|9.75,3.07,9.75|6091.24,17018.64,15663.43|Build/EnchantedTreeInterior
GlowingFlower|MeshPart|1|9.75,3.07,9.75|6052.86,17011.97,15671.16|Build/EnchantedTreeInterior
GlowingFlower|MeshPart|1|17.53,5.52,17.53|6078.81,17085.45,15711.95|Build/EnchantedTreeInterior
GlowingFlower|MeshPart|1|12.99,6.91,12.99|6569.01,17129.68,15661.79|Build/EnchantedTreeInterior
GlowingFlower|MeshPart|1|11.51,3.62,11.5|6074.6,17103,15694.61|Build/EnchantedTreeInterior
GlowingFlower|MeshPart|1|16.34,5.8,16.34|6074.91,17160.11,15702.29|Build/EnchantedTreeInterior
GlowingFlower|MeshPart|1|21.09,7.48,21.09|6084.25,17199.45,15688.21|Build/EnchantedTreeInterior
GlowingFlower|MeshPart|1|9.75,3.07,9.75|6027.86,17014.54,15772.23|Build/EnchantedTreeInterior
GlowingFlower|MeshPart|1|9.75,3.07,9.75|6061.05,17009.9,15724.39|Build/EnchantedTreeInterior
Leaves1|MeshPart|1|0.81,95.84,44.47|6565.9,17123.47,15738.58|Build/EnchantedTreeInterior
Leaves2|MeshPart|1|2.88,29.09,22.79|6016.12,17094.83,15665.86|Build/EnchantedTreeInterior
Leaves1|MeshPart|1|1.88,31.96,21.24|6128.79,17034.44,15752.72|Build/EnchantedTreeInterior
Leaves2|MeshPart|1|4.66,36.84,28.89|6125.56,17060.98,15640.61|Build/EnchantedTreeInterior
Leaves2|MeshPart|1|1.31,13.18,10.33|5984.92,17013.26,15610.25|Build/EnchantedTreeInterior
Leaves2|MeshPart|1|7.47,35.03,27.45|6069.82,17081.48,15602.58|Build/EnchantedTreeInterior
Leaves2|MeshPart|1|7.47,35.03,27.45|6039.46,17105.67,15770.74|Build/EnchantedTreeInterior
Leaves1|MeshPart|1|3.44,79.9,53.09|5977.6,16998.16,15654.81|Build/EnchantedTreeInterior
Leaves1|MeshPart|1|3.51,95.22,56.5|5947.54,16998.09,15729.37|Build/EnchantedTreeInterior
Leaves1|MeshPart|1|3.35,39.56,26.28|6009.62,17095.65,15706.39|Build/EnchantedTreeInterior
Leaves1|MeshPart|1|0.81,75.87,44.47|6456.69,17123.49,15657.8|Build/EnchantedTreeInterior
Leaves1|MeshPart|1|2.64,31.15,20.7|5967.92,17021.92,15593.09|Build/EnchantedTreeInterior
Leaves1|MeshPart|1|0.81,75.87,44.47|6546.1,17123.49,15644.42|Build/EnchantedTreeInterior
Leaves1|MeshPart|1|0.81,75.87,44.47|6470.07,17123.48,15747.21|Build/EnchantedTreeInterior
Leaves1|MeshPart|1|30.76,244.18,162.24|6559.02,17267.33,15466.72|Build/EnchantedTreeInterior
Leaves1|MeshPart|1|49.71,244.18,162.24|5996.61,17113.7,16014.98|Build/EnchantedTreeInterior
Leaves1|MeshPart|1|0.69,68.6,50.06|6387.18,17122.11,15741.39|Build/EnchantedTreeInterior
Leaves2|MeshPart|1|10.14,32.15,25.2|6556.03,17200.04,15697.61|Build/EnchantedTreeInterior
Leaves2|MeshPart|1|10.14,32.15,25.2|6513.93,17200.04,15660.46|Build/EnchantedTreeInterior
Leaves2|MeshPart|1|4.66,56.61,44.37|6511.33,17193.01,15737.97|Build/EnchantedTreeInterior
Leaves1|MeshPart|1|3.98,46.94,31.19|6588,17157.2,15709.92|Build/EnchantedTreeInterior
Leaves1|MeshPart|1|5.12,18.64,14.08|6017.04,17010.88,15608.72|Build/EnchantedTreeInterior
Leaves1|MeshPart|1|3.35,39.56,26.28|6163.47,17054.05,15645.03|Build/EnchantedTreeInterior
Leaves1|MeshPart|1|0.31,46.69,37.57|6105.32,17122.42,15738.42|Build/EnchantedTreeInterior
Leaves1|MeshPart|1|0.81,46.69,34.07|6309.28,17128.7,15698.38|Build/EnchantedTreeInterior
Leaves1|MeshPart|1|2.43,43.5,26.03|6025.47,17109.16,15741.9|Build/EnchantedTreeInterior
Leaves1|MeshPart|1|1.19,68.6,50.06|6384.68,17122.36,15659.98|Build/EnchantedTreeInterior
Leaves2|MeshPart|1|2.7,27.23,21.34|6061.13,17023.52,15608.58|Build/EnchantedTreeInterior
Mushroom|MeshPart|1|12.33,9.73,13.62|6480.65,17147.85,15643.5|Build/EnchantedTreeInterior
Mushroom|MeshPart|1|12.33,9.73,13.62|6567.78,17161.22,15734.74|Build/EnchantedTreeInterior
Mushroom|MeshPart|1|12.94,14.68,14.29|6078.46,17200.36,15709.4|Build/EnchantedTreeInterior
Mushroom|MeshPart|1|12.94,14.68,14.29|6074.26,17127.04,15688.4|Build/EnchantedTreeInterior
Mushroom|MeshPart|1|12.94,14.68,14.29|6131.82,17093.45,15676.88|Build/EnchantedTreeInterior
Mushroom|MeshPart|1|7.29,5.75,8.05|6452.09,17164.51,15678.25|Build/EnchantedTreeInterior
Mushroom|MeshPart|1|7.29,5.75,8.05|6500.54,17126.07,15627.45|Build/EnchantedTreeInterior
Mushroom|MeshPart|1|88.47,93.22,97.71|6440.38,17061.76,15802.68|Build/EnchantedTreeInterior
Mushroom|MeshPart|1|7.29,5.75,8.05|6063.36,17006.4,15654.23|Build/EnchantedTreeInterior
Mushroom|MeshPart|1|11.13,10.87,12.3|6185.36,17098.16,15688|Build/EnchantedTreeInterior
Mushroom|MeshPart|1|16.39,12.92,18.1|6084.69,17020.73,15738.53|Build/EnchantedTreeInterior
Mushroom|MeshPart|1|7.29,5.75,8.05|6063.36,17017.89,15670.21|Build/EnchantedTreeInterior
Cylinder.020|MeshPart|1|2.46,3.15,2.84|6034.05,17000.81,15596.97|Build/EnchantedTreeInterior
Cylinder.021|MeshPart|1|2.45,3.56,2.74|6034.05,17000.81,15596.97|Build/EnchantedTreeInterior
Cylinder.021|MeshPart|1|1.76,2.31,1.97|6003.96,17000.26,15609.01|Build/EnchantedTreeInterior
Cylinder.020|MeshPart|1|1.77,2.01,2.05|6003.96,17000.26,15609.01|Build/EnchantedTreeInterior
Cylinder.021|MeshPart|1|1.76,2.31,1.97|6007.96,17000.26,15608.51|Build/EnchantedTreeInterior
Cylinder.020|MeshPart|1|1.77,2.01,2.05|6007.96,17000.26,15608.51|Build/EnchantedTreeInterior
Cylinder.020|MeshPart|1|4.19,5.36,4.84|5835.68,17010.18,15733.65|Build/EnchantedTreeInterior
Cylinder.021|MeshPart|1|4.17,6.06,4.66|5835.68,17010.18,15733.65|Build/EnchantedTreeInterior
Cylinder.021|MeshPart|1|1.76,2.31,1.97|5991.96,17000.26,15608.51|Build/EnchantedTreeInterior
Cylinder.020|MeshPart|1|1.77,2.01,2.05|5991.96,17000.26,15608.51|Build/EnchantedTreeInterior
Cylinder.020|MeshPart|1|1.77,2.01,2.05|5999.96,17000.26,15609.51|Build/EnchantedTreeInterior
Cylinder.021|MeshPart|1|1.76,2.31,1.97|5999.96,17000.26,15609.51|Build/EnchantedTreeInterior
Cylinder.021|MeshPart|1|1.76,2.31,1.97|5995.96,17000.26,15609.01|Build/EnchantedTreeInterior
Cylinder.020|MeshPart|1|1.77,2.01,2.05|5995.96,17000.26,15609.01|Build/EnchantedTreeInterior
Cylinder.021|MeshPart|1|2.45,3.56,2.74|6035.41,17004.31,15597.24|Build/EnchantedTreeInterior
Cylinder.020|MeshPart|1|2.46,3.15,2.84|6035.41,17004.31,15597.24|Build/EnchantedTreeInterior
Cylinder.020|MeshPart|1|2.46,3.15,2.84|6036.63,17000.81,15597.48|Build/EnchantedTreeInterior
Cylinder.021|MeshPart|1|2.45,3.56,2.74|6036.63,17000.81,15597.48|Build/EnchantedTreeInterior
Cylinder.020|MeshPart|1|4.19,5.36,4.84|5832.85,17010.18,15729.49|Build/EnchantedTreeInterior
Cylinder.021|MeshPart|1|4.17,6.06,4.66|5832.85,17010.18,15729.49|Build/EnchantedTreeInterior
Cube.113|MeshPart|1|2.61,2.61,2.61|5844.48,17011.07,15736.85|Build/EnchantedTreeInterior
Cube.112|MeshPart|1|2.56,2.56,2.56|5844.48,17011.07,15736.85|Build/EnchantedTreeInterior
Cube.112|MeshPart|1|2.56,2.56,2.56|5843.34,17008.46,15663.55|Build/EnchantedTreeInterior
Cube.113|MeshPart|1|2.61,2.61,2.61|5843.34,17008.46,15663.55|Build/EnchantedTreeInterior
Cube.112|MeshPart|1|2.56,2.56,2.56|6016.25,17000.32,15602.46|Build/EnchantedTreeInterior
Cube.113|MeshPart|1|2.61,2.61,2.61|6016.25,17000.32,15602.46|Build/EnchantedTreeInterior
Cube.112|MeshPart|1|2.56,2.56,2.56|6019.75,17000.32,15605.21|Build/EnchantedTreeInterior
Cube.113|MeshPart|1|2.61,2.61,2.61|6019.75,17000.32,15605.21|Build/EnchantedTreeInterior
Cube.113|MeshPart|1|2.61,2.61,2.61|5845.9,17008.46,15737.95|Build/EnchantedTreeInterior
Cube.112|MeshPart|1|2.56,2.56,2.56|5845.9,17008.46,15737.95|Build/EnchantedTreeInterior
Cube.112|MeshPart|1|2.56,2.56,2.56|5846.67,17008.46,15662.13|Build/EnchantedTreeInterior
Cube.113|MeshPart|1|2.61,2.61,2.61|5846.67,17008.46,15662.13|Build/EnchantedTreeInterior
Cube.112|MeshPart|1|2.56,2.56,2.56|5844.44,17011.07,15662.13|Build/EnchantedTreeInterior
Cube.113|MeshPart|1|2.61,2.61,2.61|5844.44,17011.07,15662.13|Build/EnchantedTreeInterior
Cube.112|MeshPart|1|2.56,2.56,2.56|5981.33,17000.36,15599.72|Build/EnchantedTreeInterior
Cube.113|MeshPart|1|2.61,2.61,2.61|5981.33,17000.36,15599.72|Build/EnchantedTreeInterior
Cube.113|MeshPart|1|2.61,2.61,2.61|5977.65,17000.36,15600.45|Build/EnchantedTreeInterior
Cube.112|MeshPart|1|2.56,2.56,2.56|5977.65,17000.36,15600.45|Build/EnchantedTreeInterior
Cube.112|MeshPart|1|2.56,2.56,2.56|5979.53,17002.87,15599.85|Build/EnchantedTreeInterior
Cube.113|MeshPart|1|2.61,2.61,2.61|5979.53,17002.87,15599.85|Build/EnchantedTreeInterior
Cube.112|MeshPart|1|3.73,3.73,3.73|6018.34,17003.67,15603.8|Build/EnchantedTreeInterior
Cube.113|MeshPart|1|3.8,3.8,3.8|6018.34,17003.67,15603.8|Build/EnchantedTreeInterior
Cube.112|MeshPart|1|2.56,2.56,2.56|5844.47,17008.46,15734.62|Build/EnchantedTreeInterior
Cube.113|MeshPart|1|2.61,2.61,2.61|5844.47,17008.46,15734.62|Build/EnchantedTreeInterior
Vine2|MeshPart|1|3.82,79.85,23.97|6023.2,16999.39,15679.59|Build/EnchantedTreeInterior
Vine1|MeshPart|1|3.14,83.24,24.99|6123.81,17073.76,15617.15|Build/EnchantedTreeInterior
Vine1|MeshPart|1|3.23,67.5,20.26|6420.95,17141.6,15689.38|Build/EnchantedTreeInterior
Vine2|MeshPart|1|2.03,80.79,24.25|6133.97,17122.76,15701.02|Build/EnchantedTreeInterior
Vine2|MeshPart|1|3.81,79.72,23.93|6580.52,17158.96,15681.83|Build/EnchantedTreeInterior
Vine2|MeshPart|1|3.53,136.09,37.65|5903.21,16999.28,15672.7|Build/EnchantedTreeInterior
Vine2|MeshPart|1|5.61,117.27,35.2|6555.52,17160.97,15750.34|Build/EnchantedTreeInterior
Vine2|MeshPart|1|14.95,360.47,108.2|5936.84,16983.01,15906.1|Build/EnchantedTreeInterior
Vine1|MeshPart|1|4.74,99.12,29.75|6446.12,17159.55,15691.59|Build/EnchantedTreeInterior
Vine2|MeshPart|1|2.03,80.79,24.25|6367.2,17122.76,15701.02|Build/EnchantedTreeInterior
Vine2|MeshPart|1|11.75,245.84,73.8|6416.72,16979.83,15754.72|Build/EnchantedTreeInterior
Vine2|MeshPart|1|4.25,126.46,37.96|5977.6,16999.27,15725.4|Build/EnchantedTreeInterior
Vine2|MeshPart|1|3.69,81.09,24.34|6113.68,17031.62,15782.5|Build/EnchantedTreeInterior
Vine2|MeshPart|1|4.04,75.92,25.34|6075.02,17075.05,15696.08|Build/EnchantedTreeInterior
Vine2|MeshPart|1|10.52,220.07,66.06|6357.54,16974.51,15708.54|Build/EnchantedTreeInterior
Vine2|MeshPart|1|6.84,142.98,42.92|6058.03,16999.3,15763.76|Build/EnchantedTreeInterior
Vine2|MeshPart|1|4.04,75.92,25.34|6070.94,17017.63,15666.79|Build/EnchantedTreeInterior
Vine2|MeshPart|1|3.71,77.6,23.29|6479.11,17157.34,15642.01|Build/EnchantedTreeInterior
Vine2|MeshPart|1|2.92,60.99,18.31|6087.12,17034.45,15631.21|Build/EnchantedTreeInterior
Vine2|MeshPart|1|20.64,431.72,129.59|5858.34,17077.13,15835.16|Build/EnchantedTreeInterior
Vine2|MeshPart|1|10.86,227.25,68.21|5831.08,17047.09,15666.96|Build/EnchantedTreeInterior
Vine1|MeshPart|1|2.27,47.41,14.23|6018.45,17033.49,15590.88|Build/EnchantedTreeInterior
Vine2|MeshPart|1|21.7,523.31,157.08|6240.8,17170.7,16047.42|Build/EnchantedTreeInterior
Vine2|MeshPart|1|3.85,80.62,24.2|5971.93,16999.3,15791.35|Build/EnchantedTreeInterior
Vine2|MeshPart|1|23.07,482.6,144.86|6187.97,17162.61,15347.48|Build/EnchantedTreeInterior
Vine2|MeshPart|1|25.79,621.85,186.66|6002.66,17281.47,15396.2|Build/EnchantedTreeInterior
Vine1|MeshPart|1|2.33,61.85,18.57|6029.85,17006.01,15788.29|Build/EnchantedTreeInterior
Vine2|MeshPart|1|2.26,63.67,19.11|6069.2,17017.29,15785.34|Build/EnchantedTreeInterior
Vine2|MeshPart|1|25.79,621.85,186.66|5836.25,17216.98,15532.2|Build/EnchantedTreeInterior
Vine2|MeshPart|1|21.7,523.31,157.08|6554.13,17205.84,15922.53|Build/EnchantedTreeInterior
Vine2|MeshPart|1|3.23,67.64,20.3|5948.89,17034.75,15602.77|Build/EnchantedTreeInterior
Vine2|MeshPart|1|40.28,971.28,291.55|6254.56,16980.01,15710.21|Build/EnchantedTreeInterior
Vine1|MeshPart|1|3.23,67.5,20.26|6420.77,17141.39,15709.15|Build/EnchantedTreeInterior
Vine2|MeshPart|1|3.23,67.64,20.3|5828.44,17007.56,15663.29|Build/EnchantedTreeInterior
Vine2|MeshPart|1|3.23,67.64,20.3|5836.15,17007.71,15722.47|Build/EnchantedTreeInterior
Vine1|MeshPart|1|4.54,94.9,28.49|6467.19,17159.04,15745.81|Build/EnchantedTreeInterior
Vine1|MeshPart|1|2.15,44.98,13.5|6511.24,17129.78,15774.15|Build/EnchantedTreeInterior
Vine2|MeshPart|1|22.43,540.81,162.34|5935.39,16983.01,15507.65|Build/EnchantedTreeInterior
Cylinder.087|MeshPart|1|1.5,4.32,4.95|5976.89,17010.48,15607.94|Build/EnchantedTreeInterior
Cylinder.086|MeshPart|1|1.33,1.52,1.43|5977.1,17006.6,15609|Build/EnchantedTreeInterior
Cylinder.085|MeshPart|1|2.02,4.24,2.33|5977.1,17006.2,15609|Build/EnchantedTreeInterior
Cylinder.085|MeshPart|1|10.84,22.81,12.52|6324.62,17146.89,15650.81|Build/EnchantedTreeInterior
Cylinder.086|MeshPart|1|7.14,8.17,7.7|6324.62,17144.74,15650.81|Build/EnchantedTreeInterior
Cylinder.087|MeshPart|1|8.09,23.25,26.63|6324.62,17123.86,15656.62|Build/EnchantedTreeInterior
Cylinder.086|MeshPart|1|7.14,8.17,7.7|6324.62,17144.74,15748.43|Build/EnchantedTreeInterior
Cylinder.087|MeshPart|1|8.09,23.25,26.63|6324.62,17123.86,15742.62|Build/EnchantedTreeInterior
Cylinder.085|MeshPart|1|10.84,22.81,12.52|6324.62,17146.89,15748.43|Build/EnchantedTreeInterior
Cylinder.085|MeshPart|1|10.84,22.81,12.52|6178.62,17146.89,15650.81|Build/EnchantedTreeInterior
Cylinder.086|MeshPart|1|7.14,8.17,7.7|6178.62,17144.74,15650.81|Build/EnchantedTreeInterior
Cylinder.087|MeshPart|1|8.09,23.25,26.63|6178.62,17123.86,15656.62|Build/EnchantedTreeInterior
Cylinder.087|MeshPart|1|8.09,23.25,26.63|5839.74,17056.54,15664.11|Build/EnchantedTreeInterior
Cylinder.085|MeshPart|1|10.84,22.81,12.52|5845.55,17033.51,15664.11|Build/EnchantedTreeInterior
Cylinder.086|MeshPart|1|7.14,8.17,7.7|5845.55,17035.65,15664.11|Build/EnchantedTreeInterior
Cylinder.086|MeshPart|1|7.14,8.17,7.7|6178.62,17144.74,15748.43|Build/EnchantedTreeInterior
Cylinder.085|MeshPart|1|10.84,22.81,12.52|6178.62,17146.89,15748.43|Build/EnchantedTreeInterior
Cylinder.087|MeshPart|1|8.09,23.25,26.63|6178.62,17123.86,15742.62|Build/EnchantedTreeInterior
Cylinder.086|MeshPart|1|7.14,8.17,7.7|5845.55,17035.65,15734.11|Build/EnchantedTreeInterior
Cylinder.085|MeshPart|1|10.84,22.81,12.52|5845.55,17033.51,15734.11|Build/EnchantedTreeInterior
Cylinder.087|MeshPart|1|8.09,23.25,26.63|5839.74,17056.54,15734.11|Build/EnchantedTreeInterior
Cylinder.085|MeshPart|1|2.02,4.24,2.33|6022.47,17006.2,15608.94|Build/EnchantedTreeInterior
Cylinder.086|MeshPart|1|1.33,1.52,1.43|6022.47,17006.6,15608.94|Build/EnchantedTreeInterior
Cylinder.087|MeshPart|1|1.5,4.32,4.95|6022.89,17010.48,15607.94|Build/EnchantedTreeInterior
Cylinder.087|MeshPart|1|5.9,16.94,19.41|6174.55,17088.47,15702.94|Build/EnchantedTreeInterior
Cylinder.085|MeshPart|1|7.9,16.62,9.12|6169.26,17071.99,15703.2|Build/EnchantedTreeInterior
Cylinder.086|MeshPart|1|5.2,5.95,5.61|6169.36,17073.55,15703.2|Build/EnchantedTreeInterior
Cylinder.085|MeshPart|1|2.72,5.73,3.14|6372.89,17130.78,15724.81|Build/EnchantedTreeInterior
Cylinder.086|MeshPart|1|1.79,2.05,1.93|6372.89,17131.32,15724.81|Build/EnchantedTreeInterior
Cylinder.087|MeshPart|1|2.03,5.84,6.69|6374.35,17136.57,15724.81|Build/EnchantedTreeInterior
Cylinder.086|MeshPart|1|1.33,1.52,1.43|6015.39,17006.6,15602.02|Build/EnchantedTreeInterior
Cylinder.085|MeshPart|1|2.02,4.24,2.33|6015.39,17006.2,15602.02|Build/EnchantedTreeInterior
Cylinder.087|MeshPart|1|1.5,4.32,4.95|6015.39,17010.48,15600.94|Build/EnchantedTreeInterior
Cylinder.085|MeshPart|1|2.72,5.73,3.14|6372.89,17130.78,15674.87|Build/EnchantedTreeInterior
Cylinder.086|MeshPart|1|1.79,2.05,1.93|6372.89,17131.32,15674.87|Build/EnchantedTreeInterior
Cylinder.087|MeshPart|1|2.03,5.84,6.69|6374.35,17136.57,15674.87|Build/EnchantedTreeInterior
Cylinder.087|MeshPart|1|1.5,4.32,4.95|5984.89,17010.48,15600.94|Build/EnchantedTreeInterior
Cylinder.085|MeshPart|1|2.02,4.24,2.33|5984.89,17006.2,15602.02|Build/EnchantedTreeInterior
Cylinder.086|MeshPart|1|1.33,1.52,1.43|5984.89,17006.6,15602.02|Build/EnchantedTreeInterior
Part|Part|0|148.96,52.66,176.14|6257.8,17225.66,16945.4|Build/EnchantedTreeInterior
Part|Part|0|148.96,54.91,176.14|6257.8,17224.54,16945.4|Build/EnchantedTreeInterior
Part|Part|0|148.96,56.88,176.14|6257.8,17223.55,16945.4|Build/EnchantedTreeInterior
Part|Part|0|148.96,47.59,176.14|6257.8,17228.2,16945.4|Build/EnchantedTreeInterior
Part|Part|0|148.96,49.56,176.14|6257.8,17227.21,16945.4|Build/EnchantedTreeInterior
Part|Part|0|1022.81,354.37,1000.56|6146.22,17643.58,15742.28|Build/EnchantedTreeInterior
Part|Part|0|1022.81,369.05,1000.56|6146.22,17636.24,15742.28|Build/EnchantedTreeInterior
Part|Part|0|1022.81,392.12,1000.56|6146.22,17624.71,15742.28|Build/EnchantedTreeInterior
Part|Part|0|1022.81,423.57,1000.56|6146.22,17608.98,15742.28|Build/EnchantedTreeInterior
Part|Part|0|1022.81,408.89,1000.56|6146.22,17616.32,15742.28|Build/EnchantedTreeInterior
Part|Part|0|961.46,100.88,918.93|6251.43,16935.8,15698.15|Build/EnchantedTreeInterior
Part|Part|0|983.46,93.39,918.93|6262.43,16932.05,15698.15|Build/EnchantedTreeInterior
Part|Part|0|967.46,97.39,918.93|6254.43,16934.05,15698.15|Build/EnchantedTreeInterior
Part|Part|0|1006.46,87.9,918.93|6273.93,16929.31,15698.15|Build/EnchantedTreeInterior
Part|Part|0|964.46,84.4,918.93|6252.93,16927.56,15698.15|Build/EnchantedTreeInterior
Cube.014|MeshPart|1|0.07,0.04,0.05|6013.61,17000.52,15594.87|Build/EnchantedTreeInterior
Cube.005|MeshPart|1|1.53,2.08,1.52|6012.86,17000.3,15595|Build/EnchantedTreeInterior
Cube.007|MeshPart|1|1.32,1.66,1.53|6013.39,17000.09,15595.05|Build/EnchantedTreeInterior
Cube.004|MeshPart|1|2.55,1.93,1.95|6013.95,17000.14,15594.92|Build/EnchantedTreeInterior
Cube.003|MeshPart|1|1.52,1.53,0.96|6012.96,17000.13,15594.56|Build/EnchantedTreeInterior
Cube.002|MeshPart|1|0.74,0.61,0.34|6013.58,17000.13,15594.84|Build/EnchantedTreeInterior
Cube.011|MeshPart|1|0.26,0.4,0.1|6014.28,17000.63,15594.64|Build/EnchantedTreeInterior
Cube.012|MeshPart|1|0.19,0.3,0.08|6013.22,17000.33,15594.56|Build/EnchantedTreeInterior
Cube.013|MeshPart|1|0.07,0.04,0.05|6013.68,17000.52,15594.87|Build/EnchantedTreeInterior
Cube.008|MeshPart|1|1.83,1.89,2.03|6013.52,17000.12,15594.92|Build/EnchantedTreeInterior
Cube.009|MeshPart|1|2.56,1.29,1.02|6013.89,17000.4,15594.92|Build/EnchantedTreeInterior
Cube.010|MeshPart|1|1.04,0.95,0.1|6014.63,17000.44,15594.67|Build/EnchantedTreeInterior
Cube.001|MeshPart|1|0.07,0.15,0.17|6013.68,17000.61,15594.88|Build/EnchantedTreeInterior
Cube.006|MeshPart|1|1.58,1.34,1.48|6013.67,17000,15594.89|Build/EnchantedTreeInterior
Cube.015|MeshPart|1|0.09,0.22,0.09|6013.9,17000.76,15594.97|Build/EnchantedTreeInterior
Cube.016|MeshPart|1|0.05,0.15,0.13|6013.67,17000.58,15594.88|Build/EnchantedTreeInterior
Handle|MeshPart|1|1.9,0.82,2|5999.51,17003.62,15603.53|Build/EnchantedTreeInterior
Handle|MeshPart|1|2.21,1.8,0.81|5999.52,17003.86,15603.94|Build/EnchantedTreeInterior
Handle|MeshPart|1|1.27,0.26,0.96|5999.51,17003.27,15603.17|Build/EnchantedTreeInterior
Handle|MeshPart|1|1.5,0.98,0.71|5999.5,17003.35,15603.04|Build/EnchantedTreeInterior
Handle|MeshPart|1|0.35,1.27,0.1|5999.51,17002.01,15603.06|Build/EnchantedTreeInterior
Handle|MeshPart|1|0.27,0.65,0.04|6000.02,17002.27,15603.04|Build/EnchantedTreeInterior
LeftLowerArm|MeshPart|0|1,1.05,1|6000.89,17002.18,15603.58|Build/EnchantedTreeInterior
RightHand|MeshPart|0|1,0.3,1|5998.63,17002.43,15604.34|Build/EnchantedTreeInterior
RightLowerArm|MeshPart|0|1,1.05,1|5998.35,17002.43,15603.78|Build/EnchantedTreeInterior
LeftUpperLeg|MeshPart|0|1,1.22,1|6000.04,17000.98,15602.47|Build/EnchantedTreeInterior
RightFoot|MeshPart|0|1,0.3,1|5998.83,16999.96,15603.13|Build/EnchantedTreeInterior
LeftHand|MeshPart|0|1,0.3,1|6000.8,17002.01,15604.18|Build/EnchantedTreeInterior
LowerTorso|MeshPart|0|2,0.4,1|5999.49,17001.19,15602.2|Build/EnchantedTreeInterior
RightUpperLeg|MeshPart|0|1,1.22,1|5998.98,17000.94,15602.3|Build/EnchantedTreeInterior
Head|MeshPart|1|1,1,1|5999.5,17003.21,15602.9|Build/EnchantedTreeInterior
LeftLowerLeg|MeshPart|0|1,1.19,1|6000.14,17000.49,15602.8|Build/EnchantedTreeInterior
LeftFoot|MeshPart|0|1,0.3,1|6000.25,16999.85,15602.85|Build/EnchantedTreeInterior
RightLowerLeg|MeshPart|0|1,1.19,1|5998.92,17000.52,15602.81|Build/EnchantedTreeInterior
LeftUpperArm|MeshPart|0|1,1.17,1|6000.88,17002.32,15603.03|Build/EnchantedTreeInterior
UpperTorso|MeshPart|0|2,1.6,1|5999.49,17002.12,15602.46|Build/EnchantedTreeInterior
RightUpperArm|MeshPart|0|1,1.17,1|5998.15,17002.43,15603.23|Build/EnchantedTreeInterior
Cube.030|MeshPart|0|0.41,0.48,1.46|5988.96,17004.31,15594.52|Build/EnchantedTreeInterior
Cube.003|MeshPart|0|0.77,0.35,2.4|5989.01,17003.84,15594.58|Build/EnchantedTreeInterior
Cube.032|MeshPart|0|1.18,0.71,2.1|5989.06,17003.73,15593.85|Build/EnchantedTreeInterior
Cube.023|MeshPart|0|0.58,0.49,1.28|5988.9,17004.4,15594.39|Build/EnchantedTreeInterior
Cube.002|MeshPart|0|1.15,0.7,1.95|5989.07,17003.72,15593.77|Build/EnchantedTreeInterior
Cube.022|MeshPart|0|0.49,0.32,1.11|5988.94,17004.52,15594.74|Build/EnchantedTreeInterior
Cube.028|MeshPart|0|0.36,0.22,1|5989.03,17004.24,15594.53|Build/EnchantedTreeInterior
Cube.031|MeshPart|0|1.19,0.71,2.15|5989.06,17003.72,15593.87|Build/EnchantedTreeInterior
Cube.006|MeshPart|0|0.71,0.09,0.41|5988.94,17003.98,15595.57|Build/EnchantedTreeInterior
Cube.005|MeshPart|0|1.03,0.6,1.57|5988.99,17004.07,15594.51|Build/EnchantedTreeInterior
Cube.026|MeshPart|0|0.38,0.4,1|5989.01,17004.34,15594.51|Build/EnchantedTreeInterior
Cube.001|MeshPart|0|1.15,1,2.99|5989.02,17003.87,15594.29|Build/EnchantedTreeInterior
Cube.027|MeshPart|0|0.34,0.38,0.98|5989.01,17004.34,15594.52|Build/EnchantedTreeInterior
Cube.004|MeshPart|0|0.88,0.34,1.96|5988.99,17004.05,15594.52|Build/EnchantedTreeInterior
Cube.029|MeshPart|0|0.41,0.42,1.01|5989,17004.42,15594.51|Build/EnchantedTreeInterior
Handle|MeshPart|1|2.23,1.74,2.07|6007.3,16999.96,15593.53|Build/EnchantedTreeInterior
Handle|MeshPart|1|1.64,1.95,2.21|6007.72,17000.16,15593.58|Build/EnchantedTreeInterior
Handle|MeshPart|1|1.47,1.02,1.54|6007.25,17000,15593.55|Build/EnchantedTreeInterior
Handle|MeshPart|1|1.54,0.33,0.17|6008.05,17000.83,15593.44|Build/EnchantedTreeInterior
Handle|MeshPart|1|1.28,0.96,1.4|6008.36,17000.16,15593.53|Build/EnchantedTreeInterior
Handle|MeshPart|1|1.55,1.18,1.66|6007.19,16999.95,15593.53|Build/EnchantedTreeInterior
Handle|MeshPart|1|0.27,0.65,0.04|6008.85,17000.94,15593.24|Build/EnchantedTreeInterior
Handle|MeshPart|1|3.48,3.59,0.54|6009.58,16999.84,15593.34|Build/EnchantedTreeInterior
Handle|MeshPart|1|1.26,0.42,0.81|6007.8,17000.34,15593.63|Build/EnchantedTreeInterior
Handle|MeshPart|1|3.99,3.34,0.63|6009.47,16999.8,15593.33|Build/EnchantedTreeInterior
LeftUpperLeg|MeshPart|0|1,1.22,1|6010.87,17000.81,15593.08|Build/EnchantedTreeInterior
RightUpperArm|MeshPart|0|1,1.17,1|6009.23,16999.83,15594.96|Build/EnchantedTreeInterior
LeftFoot|MeshPart|0|1,0.3,1|6012.28,17001.06,15593.08|Build/EnchantedTreeInterior
RightUpperLeg|MeshPart|0|1,1.22,1|6010.93,17000.48,15594.02|Build/EnchantedTreeInterior
RightFoot|MeshPart|0|1,0.3,1|6012.34,17000.73,15594.02|Build/EnchantedTreeInterior
RightHand|MeshPart|0|1,0.3,1|6010.43,17000.04,15594.96|Build/EnchantedTreeInterior
LeftHand|MeshPart|0|1,0.3,1|6010.25,17001.05,15592.14|Build/EnchantedTreeInterior
RightLowerArm|MeshPart|0|1,1.05,1|6009.81,16999.93,15594.96|Build/EnchantedTreeInterior
LeftLowerArm|MeshPart|0|1,1.05,1|6009.63,17000.95,15592.14|Build/EnchantedTreeInterior
LeftLowerLeg|MeshPart|0|1,1.19,1|6011.64,17000.95,15593.08|Build/EnchantedTreeInterior
UpperTorso|MeshPart|0|2,1.6,1|6009.31,17000.37,15593.55|Build/EnchantedTreeInterior
Head|MeshPart|1|1.2,1.2,1.24|6007.94,17000.13,15593.55|Build/EnchantedTreeInterior
RightLowerLeg|MeshPart|0|1,1.19,1|6011.7,17000.61,15594.02|Build/EnchantedTreeInterior
LowerTorso|MeshPart|0|2,0.4,1|6010.29,17000.54,15593.55|Build/EnchantedTreeInterior
LeftUpperArm|MeshPart|0|1,1.17,1|6009.05,17000.84,15592.14|Build/EnchantedTreeInterior
Circle.005|MeshPart|0|3.82,0.04,3.82|5993.09,17012.43,15594.98|Build/EnchantedTreeInterior
Circle.005|MeshPart|0|3.82,0.04,3.82|6007.29,17012.43,15594.98|Build/EnchantedTreeInterior
Circle.005|MeshPart|0|3.82,0.04,3.82|6000.19,17012.43,15593.47|Build/EnchantedTreeInterior
Cylinder.020|MeshPart|1|1.77,2.01,2.05|5999.52,17000.04,15601.88|Build/EnchantedTreeInterior
Cylinder.021|MeshPart|1|1.76,2.31,1.97|5999.52,17000.04,15601.88|Build/EnchantedTreeInterior
Cube.016|MeshPart|0|0.94,0.3,0.94|5992.08,17004.16,15605.91|Build/EnchantedTreeInterior
Cube.004|MeshPart|0|1.85,1.98,1.85|5992.08,17003.02,15605.91|Build/EnchantedTreeInterior
Cube.004|MeshPart|0|1.85,1.98,1.85|6008.08,17003.02,15605.91|Build/EnchantedTreeInterior
Cube.016|MeshPart|0|0.94,0.3,0.94|6008.08,17004.16,15605.91|Build/EnchantedTreeInterior
Cube.004|MeshPart|0|1.85,1.98,1.85|5986.72,17007.33,15594.49|Build/EnchantedTreeInterior
Cube.016|MeshPart|0|0.94,0.3,0.94|5986.72,17008.47,15594.49|Build/EnchantedTreeInterior
Cube.004|MeshPart|0|1.85,1.98,1.85|6013.72,17003.83,15594.49|Build/EnchantedTreeInterior
Cube.016|MeshPart|0|0.94,0.3,0.94|6013.72,17004.97,15594.49|Build/EnchantedTreeInterior
Cube.004|MeshPart|0|3.03,3.77,3.03|6010.25,17003.91,15602.87|Build/EnchantedTreeInterior
Cube.016|MeshPart|0|1.29,0.57,1.29|6010.25,17006.08,15602.87|Build/EnchantedTreeInterior
Cube.016|MeshPart|0|0.94,0.3,0.94|6009.22,17008.47,15594.49|Build/EnchantedTreeInterior
Cube.004|MeshPart|0|1.85,1.98,1.85|6009.22,17007.33,15594.49|Build/EnchantedTreeInterior
Cube.016|MeshPart|0|0.94,0.3,0.94|5994.22,17004.97,15592.49|Build/EnchantedTreeInterior
Cube.004|MeshPart|0|1.85,1.98,1.85|5994.22,17003.83,15592.49|Build/EnchantedTreeInterior
Cube.016|MeshPart|0|1.29,0.57,1.29|5989.75,17006.08,15602.87|Build/EnchantedTreeInterior
Cube.004|MeshPart|0|3.03,3.77,3.03|5989.75,17003.91,15602.87|Build/EnchantedTreeInterior
Cube.004|MeshPart|0|1.85,1.98,1.85|5996.72,17003.83,15592.49|Build/EnchantedTreeInterior
Cube.016|MeshPart|0|0.94,0.3,0.94|5996.72,17004.97,15592.49|Build/EnchantedTreeInterior
Cylinder.011|MeshPart|0|52.62,16.33,6.46|6000.19,17007.23,15606.42|Build/EnchantedTreeInterior
Cube.008|MeshPart|0|23.49,2.3,6.34|6000.2,17000.22,15604.1|Build/EnchantedTreeInterior
Cylinder.008|MeshPart|0|63.06,4.47,23.79|6000.19,17017.63,15600.08|Build/EnchantedTreeInterior
Cylinder.016|MeshPart|0|33.34,17.62,5.68|6000.19,17007.88,15599.28|Build/EnchantedTreeInterior
Cube.007|MeshPart|0|24.76,0.66,7.55|6000.2,17001.7,15604.13|Build/EnchantedTreeInterior
Cylinder.012|MeshPart|0|43.68,16.33,8.82|6000.19,17007.23,15592.59|Build/EnchantedTreeInterior
Cylinder.014|MeshPart|0|19.41,2.67,2.01|6000.19,17012.47,15593.96|Build/EnchantedTreeInterior
BrockMindControlHelmet|MeshPart|0|1.55,1.5,1.62|6006.96,17006.72,15592.48|Build/EnchantedTreeInterior
Circle.007|MeshPart|0|8.69,0.08,8.69|6513.32,17122.56,15699.52|Build/EnchantedTreeInterior
Circle.007|MeshPart|0|7.57,0.07,7.57|6513.32,17113.75,15699.52|Build/EnchantedTreeInterior
Cylinder.033|MeshPart|0|10.85,8.74,10.85|6513.32,17118.15,15699.52|Build/EnchantedTreeInterior
Circle.006|MeshPart|0|0.14,7.22,3.61|6390.02,17139.04,15701.32|Build/EnchantedTreeInterior
Cube.082|MeshPart|0|3.21,40.26,9.83|6391.69,17143.8,15704.43|Build/EnchantedTreeInterior
Cube.070|MeshPart|0|3.21,40.26,9.83|6391.69,17143.8,15694.6|Build/EnchantedTreeInterior
Circle.004|MeshPart|0|0.14,7.22,3.61|6390.02,17139.04,15697.71|Build/EnchantedTreeInterior
Cylinder.145|MeshPart|0|4.52,9.48,5.22|6215.63,17133.54,15688.55|Build/EnchantedTreeInterior
Cylinder.146|MeshPart|0|2.93,9.7,3.39|6215.63,17138.73,15688.55|Build/EnchantedTreeInterior
Plane.005|MeshPart|1|55.12,13.26,94.56|6509.41,17117.84,15699.31|Build/EnchantedTreeInterior
Plane.010|MeshPart|1|69.86,15.82,57.68|6524.65,17118.77,15685.02|Build/EnchantedTreeInterior
Plane.004|MeshPart|1|95.77,13.99,54.44|6513.66,17117.62,15694.02|Build/EnchantedTreeInterior
Plane.006|MeshPart|1|226.74,14.15,235.77|6004.71,17005.72,15699.52|Build/EnchantedTreeInterior
Plane.009|MeshPart|1|63.91,8.56,73.62|6495.96,17114.92,15709|Build/EnchantedTreeInterior
Plane.007|MeshPart|1|75.78,14.69,68.46|6507.45,17117.92,15687.75|Build/EnchantedTreeInterior
Plane.008|MeshPart|1|52.7,10.58,71.71|6528.43,17120.48,15709.54|Build/EnchantedTreeInterior
Cylinder.026|MeshPart|0|13.37,4.5,15.12|6635.71,16987.58,15467.52|Build/EnchantedTreeInterior
Cylinder.025|MeshPart|0|13.23,3.57,13.23|6634.84,16987.11,15467.52|Build/EnchantedTreeInterior
Cylinder.024|MeshPart|0|9.17,16.5,9.17|6634.84,16996.74,15467.52|Build/EnchantedTreeInterior
Cylinder.145|MeshPart|0|4.52,9.48,5.22|6215.63,17133.54,15710.55|Build/EnchantedTreeInterior
Cylinder.146|MeshPart|0|2.93,9.7,3.39|6215.63,17138.73,15710.55|Build/EnchantedTreeInterior
Cube.017|MeshPart|0|1.89,8.5,28.95|6000.24,17023.8,15607.79|Build/EnchantedTreeInterior
Text.001|MeshPart|0|21.71,0.23,3.89|6000.24,17023.8,15608.43|Build/EnchantedTreeInterior
Text|MeshPart|0|14.09,0.22,3.46|6071.01,17033.35,15700.07|Build/EnchantedTreeInterior
Cube.017|MeshPart|0|1.45,7,21.55|6071.52,17033.35,15700.07|Build/EnchantedTreeInterior
Cube.012|MeshPart|0|73.8,35.93,40.74|5802.57,17025.03,15699.39|Build/EnchantedTreeInterior
Cube.016|MeshPart|0|0.29,18.16,18.15|5829.33,17016.15,15699.39|Build/EnchantedTreeInterior
Cylinder.146|MeshPart|0|2.93,9.7,3.39|6287.06,17138.73,15688.55|Build/EnchantedTreeInterior
Cylinder.145|MeshPart|0|4.52,9.48,5.22|6287.06,17133.54,15688.55|Build/EnchantedTreeInterior
Cylinder.146|MeshPart|0|2.93,9.7,3.39|6287.06,17138.73,15710.55|Build/EnchantedTreeInterior
Cylinder.145|MeshPart|0|4.52,9.48,5.22|6287.06,17133.54,15710.55|Build/EnchantedTreeInterior
Cube.005|MeshPart|0|79.06,126.55,52.32|6045.58,17072.93,15776.52|Build/EnchantedTreeInterior
Cube.009|MeshPart|0|57.9,69.52,69.92|6401.87,17157.09,15699.52|Build/EnchantedTreeInterior
Cylinder.028|MeshPart|0|70.51,15.69,70.52|6513.32,17227.53,15699.52|Build/EnchantedTreeInterior
Plane.002|MeshPart|1|185.69,62.67,151.15|6496.05,17154.2,15699.52|Build/EnchantedTreeInterior
Cylinder.030|MeshPart|0|141.98,28.95,133.58|6511.76,17202.03,15699.93|Build/EnchantedTreeInterior
Cylinder.029|MeshPart|0|158.29,36.85,150.39|6509.37,17104.79,15699.52|Build/EnchantedTreeInterior
Cylinder.027|MeshPart|0|163.75,149.01,161.3|6512.1,17160.87,15699.52|Build/EnchantedTreeInterior
Plane.001|MeshPart|1|131.68,62.35,134.01|6514.46,17152.42,15698.79|Build/EnchantedTreeInterior
Plane|MeshPart|0|343.33,139.62,138.53|6249.29,17048.79,15699.67|Build/EnchantedTreeInterior
Circle.005|MeshPart|0|30.98,0.3,30.98|6000.2,17000.02,15699.52|Build/EnchantedTreeInterior
Spiral|MeshPart|0|158.82,125.77,206.29|6087,17059.45,15696.71|Build/EnchantedTreeInterior
Spiral.002|MeshPart|0|121.99,332.43,108.93|6090.21,17132.56,15711.02|Build/EnchantedTreeInterior
Spiral.003|MeshPart|0|127.13,333.09,114.44|6418.54,17133.27,15705.88|Build/EnchantedTreeInterior
Spiral.004|MeshPart|0|162.06,132.82,212.11|6088.29,17065.24,15696.72|Build/EnchantedTreeInterior
Plane.003|MeshPart|1|183.9,52.18,150.12|6496.44,17149.38,15699.52|Build/EnchantedTreeInterior
Cylinder.010|MeshPart|0|236.64,0.85,102.86|6015.65,17037.12,15606.22|Build/EnchantedTreeInterior
Spiral.009|MeshPart|1|144.16,67.66,145.29|6512.51,17151.91,15699.77|Build/EnchantedTreeInterior
Cylinder.009|MeshPart|0|32.69,0.45,32.69|6000.2,16999.65,15699.52|Build/EnchantedTreeInterior
Cylinder.022|MeshPart|0|89.04,22.16,89.04|6513.32,17106.54,15699.52|Build/EnchantedTreeInterior
Circle|MeshPart|0|115.63,321.54,141.4|6092.18,17127.11,15697.93|Build/EnchantedTreeInterior
Circle.001|MeshPart|0|2.44,29.89,27.9|6078.6,17014.02,15698.91|Build/EnchantedTreeInterior
Cylinder.031|MeshPart|0|138.38,61.92,138.38|6513.32,17160.04,15699.52|Build/EnchantedTreeInterior
Cylinder.105|MeshPart|0|142.95,78.58,142.95|6513.32,17162.49,15699.52|Build/EnchantedTreeInterior
Cylinder.018|MeshPart|0|17.77,5.99,20.09|6064.59,17007.84,15699.52|Build/EnchantedTreeInterior
Cylinder.032|MeshPart|1|112.61,96.49,112.62|6513.32,17171.45,15699.52|Build/EnchantedTreeInterior
Cube.002|MeshPart|0|81.22,133.46,54.48|6045.58,17065.8,15776.52|Build/EnchantedTreeInterior
Cylinder.019|MeshPart|0|12.18,0.57,12.18|6063.43,17009.33,15699.52|Build/EnchantedTreeInterior
Cube.001|MeshPart|0|229.2,10.25,237.6|6004.4,17004.19,15699.52|Build/EnchantedTreeInterior
Cylinder.101|MeshPart|0|137.95,18.09,137.95|6513.32,17161.82,15699.52|Build/EnchantedTreeInterior
Cube.003|MeshPart|0|227.7,3.32,236.36|6004.53,17011.43,15699.52|Build/EnchantedTreeInterior
Circle.003|MeshPart|1|222.56,540.15,281.02|6520.63,17141.13,15698.09|Build/EnchantedTreeInterior
Cube.004|MeshPart|0|229.64,8.39,237.98|6004.37,17013.51,15699.52|Build/EnchantedTreeInterior
Spiral.006|MeshPart|0|159.18,117.63,210.47|6088.96,17066.92,15696.85|Build/EnchantedTreeInterior
Spiral.007|MeshPart|1|283.71,589.96,286.23|6511.8,17142.02,15710.38|Build/EnchantedTreeInterior
Circle.003|MeshPart|1|224.56,525.17,287.02|6520.63,17141.13,15698.09|Build/EnchantedTreeInterior
Cylinder.022|MeshPart|0|89.04,22.16,89.04|6513.32,17083.06,15699.52|Build/EnchantedTreeInterior
Circle.002|MeshPart|0|197.01,408.93,192.27|6418.49,17083.42,15702.05|Build/EnchantedTreeInterior
Cylinder.001|MeshPart|1|188.49,0.54,188.49|6000.2,16999.34,15699.52|Build/EnchantedTreeInterior
Cylinder.023|MeshPart|0|4.36,1.18,69.5|6368.67,17160.63,15699.52|Build/EnchantedTreeInterior
Cylinder.015|MeshPart|0|17.58,4.74,17.58|6063.43,17007.22,15699.52|Build/EnchantedTreeInterior
Cube.013|MeshPart|0|33.46,80.16,78.97|6381.25,17162.41,15699.52|Build/EnchantedTreeInterior
Cylinder.013|MeshPart|0|237.49,7.47,104.43|6015.89,17036.02,15606.29|Build/EnchantedTreeInterior
Cube|MeshPart|0|28.68,7.01,49.24|6060.26,17002.57,15699.52|Build/EnchantedTreeInterior
Cylinder|MeshPart|0|613.68,249.84,263.76|6115.79,17003.88,15686.67|Build/EnchantedTreeInterior
Circle|MeshPart|0|114.63,324.54,139.4|6092.18,17128.61,15697.93|Build/EnchantedTreeInterior
Circle.005|MeshPart|0|17.82,0.17,17.82|6064.63,17019.8,15699.52|Build/EnchantedTreeInterior
Cylinder.004|MeshPart|0|47.07,5.78,55.11|6070.18,17001.96,15699.52|Build/EnchantedTreeInterior
Cube.010|MeshPart|0|16.37,61.18,60.29|6384.38,17152.92,15699.52|Build/EnchantedTreeInterior
Cylinder.002|MeshPart|1|86.56,0.35,86.56|6000.2,16999.25,15699.52|Build/EnchantedTreeInterior
Cylinder.003|MeshPart|0|75.55,44.77,99.33|5846.32,16988.39,15699.52|Build/EnchantedTreeInterior
Cube.006|MeshPart|0|80.79,131.48,54.05|6045.58,17075.01,15776.52|Build/EnchantedTreeInterior
Spiral.007|MeshPart|1|282.71,591.96,285.23|6511.8,17143.02,15710.38|Build/EnchantedTreeInterior
Circle.008|MeshPart|0|950.18,789.23,915.99|6259.6,17325.29,15685.04|Build/EnchantedTreeInterior
Circle.008|MeshPart|0|979.15,846.66,956.95|6259.6,17303.06,15679.05|Build/EnchantedTreeInterior
Circle.015|MeshPart|0|1022.81,860.2,917.04|6245.91,17325,15721.41|Build/EnchantedTreeInterior
Cylinder|MeshPart|0|4.04,3.19,4.04|6219.47,17160.94,16974.18|Build/EnchantedTreeInterior
Cylinder|MeshPart|0|4.04,3.19,4.04|6224.66,17160.94,16984.9|Build/EnchantedTreeInterior
Cylinder|MeshPart|0|4.04,3.19,4.04|6254.2,17160.94,16960.35|Build/EnchantedTreeInterior
Cylinder|MeshPart|0|4.04,3.19,4.04|6262.47,17160.94,16974.18|Build/EnchantedTreeInterior
Cylinder|MeshPart|0|4.04,3.19,4.04|6278.36,17165.54,16955.04|Build/EnchantedTreeInterior
Cube.112|MeshPart|1|2.56,2.56,2.56|6214.3,17160.65,16966.71|Build/EnchantedTreeInterior
Cube.113|MeshPart|1|2.61,2.61,2.61|6214.3,17160.65,16966.71|Build/EnchantedTreeInterior
Cube.112|MeshPart|1|2.56,2.56,2.56|6215.24,17160.65,16969.63|Build/EnchantedTreeInterior
Cube.113|MeshPart|1|2.61,2.61,2.61|6215.24,17160.65,16969.63|Build/EnchantedTreeInterior
Cylinder.021|MeshPart|1|2.62,3.81,2.93|6245.4,17161.25,16967.13|Build/EnchantedTreeInterior
Cylinder.020|MeshPart|1|2.64,3.37,3.04|6245.4,17161.25,16967.13|Build/EnchantedTreeInterior
Cube.113|MeshPart|1|2.61,2.61,2.61|6214.09,17163.26,16968.53|Build/EnchantedTreeInterior
Cube.112|MeshPart|1|2.56,2.56,2.56|6214.09,17163.26,16968.53|Build/EnchantedTreeInterior
Cube.112|MeshPart|1|2.56,2.56,2.56|6255.4,17160.65,16982.58|Build/EnchantedTreeInterior
Cube.113|MeshPart|1|2.61,2.61,2.61|6255.4,17160.65,16982.58|Build/EnchantedTreeInterior
Cylinder.021|MeshPart|1|2.62,3.81,2.93|6228.57,17161.25,16945.57|Build/EnchantedTreeInterior
Cylinder.020|MeshPart|1|2.64,3.37,3.04|6228.57,17161.25,16945.57|Build/EnchantedTreeInterior
Cylinder.021|MeshPart|1|2.62,3.81,2.93|6230.69,17161.25,16942.89|Build/EnchantedTreeInterior
Cylinder.020|MeshPart|1|2.64,3.37,3.04|6230.69,17161.25,16942.89|Build/EnchantedTreeInterior
Cube.113|MeshPart|1|2.61,2.61,2.61|6240.56,17160.65,16997.11|Build/EnchantedTreeInterior
Cube.112|MeshPart|1|2.56,2.56,2.56|6240.56,17160.65,16997.11|Build/EnchantedTreeInterior
Cube.113|MeshPart|1|2.61,2.61,2.61|6243.4,17160.65,16998.28|Build/EnchantedTreeInterior
Cube.112|MeshPart|1|2.56,2.56,2.56|6243.4,17160.65,16998.28|Build/EnchantedTreeInterior
Cylinder.020|MeshPart|1|2.64,3.37,3.04|6229.49,17165.06,16944.08|Build/EnchantedTreeInterior
Cylinder.021|MeshPart|1|2.62,3.81,2.93|6229.49,17165.06,16944.08|Build/EnchantedTreeInterior
Cube.113|MeshPart|1|2.61,2.61,2.61|6241.81,17163.26,16998.45|Build/EnchantedTreeInterior
Cube.112|MeshPart|1|2.56,2.56,2.56|6241.81,17163.26,16998.45|Build/EnchantedTreeInterior
Cube.579|MeshPart|0|1.52,3.94,1.75|6260.26,17187.68,16960.88|Build/EnchantedTreeInterior
Cube.578|MeshPart|0|1.02,2.6,1.02|6260.26,17187.02,16960.88|Build/EnchantedTreeInterior
Part|Part|0|0.38,35.88,0.38|6260.26,17207.33,16960.88|Build/EnchantedTreeInterior
Cube.577|MeshPart|0|1.75,3.39,1.75|6260.26,17187.04,16960.88|Build/EnchantedTreeInterior
Cube.577|MeshPart|0|1.75,3.39,1.75|6268.26,17179.04,16966.88|Build/EnchantedTreeInterior
Cube.579|MeshPart|0|1.52,3.94,1.75|6268.26,17179.68,16966.88|Build/EnchantedTreeInterior
Part|Part|0|0.38,35.88,0.38|6268.26,17199.33,16966.88|Build/EnchantedTreeInterior
Cube.578|MeshPart|0|1.02,2.6,1.02|6268.26,17179.02,16966.88|Build/EnchantedTreeInterior
Cube.578|MeshPart|0|1.02,2.6,1.02|6255.26,17173.02,16955.88|Build/EnchantedTreeInterior
Part|Part|0|0.38,35.88,0.38|6255.26,17193.33,16955.88|Build/EnchantedTreeInterior
Cube.579|MeshPart|0|1.52,3.94,1.75|6255.26,17173.68,16955.88|Build/EnchantedTreeInterior
Cube.577|MeshPart|0|1.75,3.39,1.75|6255.26,17173.04,16955.88|Build/EnchantedTreeInterior
Cube.577|MeshPart|0|1.75,3.39,1.75|6262.26,17179.04,16907.88|Build/EnchantedTreeInterior
Cube.579|MeshPart|0|1.52,3.94,1.75|6262.26,17179.68,16907.88|Build/EnchantedTreeInterior
Cube.578|MeshPart|0|1.02,2.6,1.02|6262.26,17179.02,16907.88|Build/EnchantedTreeInterior
Part|Part|0|0.38,35.88,0.38|6262.26,17199.33,16907.88|Build/EnchantedTreeInterior
Cube.577|MeshPart|0|1.75,3.39,1.75|6231.26,17176.04,16896.88|Build/EnchantedTreeInterior
Part|Part|0|0.38,35.88,0.38|6231.26,17196.33,16896.88|Build/EnchantedTreeInterior
Cube.578|MeshPart|0|1.02,2.6,1.02|6231.26,17176.02,16896.88|Build/EnchantedTreeInterior
Cube.579|MeshPart|0|1.52,3.94,1.75|6231.26,17176.68,16896.88|Build/EnchantedTreeInterior
Cube.577|MeshPart|0|1.75,3.39,1.75|6270.26,17173.04,16977.88|Build/EnchantedTreeInterior
Cube.579|MeshPart|0|1.52,3.94,1.75|6270.26,17173.68,16977.88|Build/EnchantedTreeInterior
Cube.578|MeshPart|0|1.02,2.6,1.02|6270.26,17173.02,16977.88|Build/EnchantedTreeInterior
Part|Part|0|0.38,35.88,0.38|6270.26,17193.33,16977.88|Build/EnchantedTreeInterior
Cube.577|MeshPart|0|1.75,3.39,1.75|6250.26,17174.04,16981.88|Build/EnchantedTreeInterior
Cube.579|MeshPart|0|1.52,3.94,1.75|6250.26,17174.68,16981.88|Build/EnchantedTreeInterior
Cube.578|MeshPart|0|1.02,2.6,1.02|6250.26,17174.02,16981.88|Build/EnchantedTreeInterior
Part|Part|0|0.38,35.88,0.38|6250.26,17194.33,16981.88|Build/EnchantedTreeInterior
Cube.577|MeshPart|0|1.75,3.39,1.75|6260.26,17180.04,16978.88|Build/EnchantedTreeInterior
Cube.579|MeshPart|0|1.52,3.94,1.75|6260.26,17180.68,16978.88|Build/EnchantedTreeInterior
Cube.578|MeshPart|0|1.02,2.6,1.02|6260.26,17180.02,16978.88|Build/EnchantedTreeInterior
Part|Part|0|0.38,35.88,0.38|6260.26,17200.33,16978.88|Build/EnchantedTreeInterior
Cube.579|MeshPart|0|1.52,3.94,1.75|6239.54,17185.68,16927.79|Build/EnchantedTreeInterior
Cube.578|MeshPart|0|1.02,2.6,1.02|6239.54,17185.02,16927.79|Build/EnchantedTreeInterior
Part|Part|0|0.38,35.88,0.38|6239.54,17205.33,16927.79|Build/EnchantedTreeInterior
Cube.577|MeshPart|0|1.75,3.39,1.75|6239.54,17185.04,16927.79|Build/EnchantedTreeInterior
Cylinder.001|MeshPart|0|0.22,4.54,4.54|6279.61,17173.32,16989.06|Build/EnchantedTreeInterior
Cylinder.001|MeshPart|0|0.22,4.54,4.54|6279.68,17177.94,16950.44|Build/EnchantedTreeInterior
Cylinder.001|MeshPart|0|0.22,4.54,4.54|6279.68,17177.94,16944.44|Build/EnchantedTreeInterior
Cylinder.001|MeshPart|0|0.22,4.54,4.54|6279.68,17171.94,16950.44|Build/EnchantedTreeInterior
Cylinder.001|MeshPart|0|0.22,4.54,4.54|6279.68,17171.94,16944.44|Build/EnchantedTreeInterior
Cylinder.001|MeshPart|0|0.22,4.54,4.54|6279.68,17171.94,16956.44|Build/EnchantedTreeInterior
Cylinder.001|MeshPart|0|0.14,2.79,2.79|6279.68,17170.82,16992.06|Build/EnchantedTreeInterior
Cylinder.001|MeshPart|0|0.22,4.54,4.54|6279.68,17177.94,16956.44|Build/EnchantedTreeInterior
Handle|MeshPart|1|1.66,0.63,1.96|6232,17160.07,16996.71|Build/EnchantedTreeInterior
Handle|MeshPart|1|1.46,2.1,2.3|6232.13,17160.13,16996.37|Build/EnchantedTreeInterior
Handle|MeshPart|1|1.76,1.74,1.99|6232.42,17160.27,16996.83|Build/EnchantedTreeInterior
RightLowerArm|MeshPart|0|0.9,0.72,0.95|6233.28,17159.68,16996.41|Build/EnchantedTreeInterior
Head|MeshPart|1|0.95,0.95,0.95|6232.41,17160.25,16997.07|Build/EnchantedTreeInterior
UpperTorso|MeshPart|0|1.8,1.35,0.95|6233.31,17160.32,16997.74|Build/EnchantedTreeInterior
LeftFoot|MeshPart|0|0.9,0.23,0.95|6235.76,17160.08,16997.79|Build/EnchantedTreeInterior
LowerTorso|MeshPart|0|1.8,0.45,0.95|6234.07,17160.24,16998.21|Build/EnchantedTreeInterior
RightUpperLeg|MeshPart|0|0.9,0.86,0.95|6234.58,17159.79,16998.55|Build/EnchantedTreeInterior
RightFoot|MeshPart|0|0.9,0.23,0.95|6235.72,17159.67,16999.06|Build/EnchantedTreeInterior
LeftLowerLeg|MeshPart|0|0.9,0.72,0.95|6235.42,17160.32,16998.02|Build/EnchantedTreeInterior
RightUpperArm|MeshPart|0|0.9,0.86,0.95|6233.01,17159.69,16997.15|Build/EnchantedTreeInterior
LeftLowerArm|MeshPart|0|0.9,0.72,0.95|6233.93,17159.95,16997.1|Build/EnchantedTreeInterior
LeftUpperArm|MeshPart|0|0.9,0.86,0.95|6233.81,17160.72,16997.07|Build/EnchantedTreeInterior
LeftHand|MeshPart|0|0.9,0.23,0.95|6234.01,17159.48,16997.11|Build/EnchantedTreeInterior
RightHand|MeshPart|0|0.9,0.23,0.95|6233.45,17159.68,16995.97|Build/EnchantedTreeInterior
RightLowerLeg|MeshPart|0|0.9,0.72,0.95|6235.29,17159.72,16998.87|Build/EnchantedTreeInterior
LeftUpperLeg|MeshPart|0|0.9,0.86,0.95|6234.75,17160.58,16998.24|Build/EnchantedTreeInterior
Handle|MeshPart|1|2.79,2.89,0.4|6255.35,17177.95,16957.51|Build/EnchantedTreeInterior
Handle|MeshPart|1|1.69,1.75,1.43|6255.24,17178.15,16956.76|Build/EnchantedTreeInterior
Handle|MeshPart|1|2.17,1.86,1.82|6255.25,17179.37,16957|Build/EnchantedTreeInterior
RightUpperLeg|MeshPart|0|0.67,1.32,0.82|6255.66,17176.86,16956.09|Build/EnchantedTreeInterior
LeftHand|MeshPart|0|0.76,0.94,0.75|6254.9,17178.7,16955.76|Build/EnchantedTreeInterior
LeftLowerArm|MeshPart|0|0.81,0.91,0.86|6254.48,17178.56,16955.98|Build/EnchantedTreeInterior
LowerTorso|MeshPart|0|1.65,0.5,1|6255.23,17177.03,16956.5|Build/EnchantedTreeInterior
Head|MeshPart|1|1.2,1.2,1.2|6255.2,17179.2,16956.96|Build/EnchantedTreeInterior
RightLowerArm|MeshPart|0|0.81,0.91,0.86|6256.06,17178.64,16955.72|Build/EnchantedTreeInterior
LeftUpperArm|MeshPart|0|0.66,1.07,0.81|6254.26,17178.53,16956.52|Build/EnchantedTreeInterior
LeftLowerLeg|MeshPart|0|0.71,0.9,0.88|6254.67,17176.72,16955.81|Build/EnchantedTreeInterior
LeftFoot|MeshPart|0|0.79,0.45,1.19|6254.75,17176.21,16955.75|Build/EnchantedTreeInterior
LeftUpperLeg|MeshPart|0|0.67,1.32,0.82|6254.68,17177,16956.15|Build/EnchantedTreeInterior
RightFoot|MeshPart|0|0.79,0.45,1.19|6255.65,17175.97,16955.82|Build/EnchantedTreeInterior
RightLowerLeg|MeshPart|0|0.71,0.9,0.88|6255.66,17176.5,16955.81|Build/EnchantedTreeInterior
RightHand|MeshPart|0|0.76,0.94,0.75|6255.61,17178.88,16955.69|Build/EnchantedTreeInterior
UpperTorso|MeshPart|0|2,1.84,1.11|6255.23,17177.87,16956.69|Build/EnchantedTreeInterior
RightUpperArm|MeshPart|0|0.66,1.07,0.81|6256.41,17178.62,16956.08|Build/EnchantedTreeInterior
Handle|MeshPart|1|0.8,0.41,0.87|6220.73,17164.48,16973.59|Build/EnchantedTreeInterior
Handle|MeshPart|1|1.74,1.84,1.42|6220.42,17165.11,16973.65|Build/EnchantedTreeInterior
Handle|MeshPart|1|1.42,0.97,1.4|6220.16,17166.03,16973.64|Build/EnchantedTreeInterior
Handle|MeshPart|1|1.63,1.49,0.99|6219.83,17165.7,16973.82|Build/EnchantedTreeInterior
LeftUpperArm|MeshPart|0|0.7,1.23,0.85|6219.77,17163.81,16973.16|Build/EnchantedTreeInterior
LeftHand|MeshPart|0|0.7,0.32,0.85|6219.69,17162.63,16973.01|Build/EnchantedTreeInterior
LeftLowerArm|MeshPart|0|0.7,1.1,0.85|6219.69,17163.21,16973.16|Build/EnchantedTreeInterior
RightUpperArm|MeshPart|0|0.7,1.23,0.85|6220.78,17163.86,16974.6|Build/EnchantedTreeInterior
RightLowerArm|MeshPart|0|0.7,1.1,0.85|6220.7,17163.26,16974.67|Build/EnchantedTreeInterior
LeftLowerLeg|MeshPart|0|0.7,1.25,0.85|6222.05,17162.18,16972.68|Build/EnchantedTreeInterior
LeftUpperLeg|MeshPart|0|0.7,1.28,0.85|6221.36,17162.49,16972.96|Build/EnchantedTreeInterior
Head|MeshPart|1|0.95,0.95,0.95|6220.47,17165.09,16973.63|Build/EnchantedTreeInterior
RightHand|MeshPart|0|0.7,0.32,0.85|6220.76,17162.63,16974.78|Build/EnchantedTreeInterior
RightLowerLeg|MeshPart|0|0.7,1.25,0.85|6221.99,17162.09,16973.52|Build/EnchantedTreeInterior
RightUpperLeg|MeshPart|0|0.7,1.28,0.85|6221.64,17162.54,16973.63|Build/EnchantedTreeInterior
RightFoot|MeshPart|0|0.7,0.31,0.85|6221.91,17161.41,16973.56|Build/EnchantedTreeInterior
LeftFoot|MeshPart|0|0.7,0.31,0.85|6222.64,17161.96,16972.43|Build/EnchantedTreeInterior
UpperTorso|MeshPart|0|1.4,1.68,0.85|6220.85,17163.84,16973.54|Build/EnchantedTreeInterior
LowerTorso|MeshPart|0|1.4,0.42,0.85|6221.05,17162.82,16973.46|Build/EnchantedTreeInterior
Handle|MeshPart|1|1.49,1.02,1.47|6234.73,17164.61,16937.64|Build/EnchantedTreeInterior
Handle|MeshPart|1|1.24,0.82,1.74|6234.72,17164.17,16937.53|Build/EnchantedTreeInterior
Handle|MeshPart|1|0.74,4.47,0.74|6234.91,17162.62,16936.72|Build/EnchantedTreeInterior
Handle|MeshPart|1|1.38,0.71,1.29|6234.69,17163,16937.32|Build/EnchantedTreeInterior
RightUpperLeg|MeshPart|0|1,1.22,1|6234.33,17160.88,16938.08|Build/EnchantedTreeInterior
LeftUpperLeg|MeshPart|0|1,1.22,1|6235.38,17160.91,16937.74|Build/EnchantedTreeInterior
RightUpperArm|MeshPart|0|1,1.17,1|6234.15,17162.5,16938.22|Build/EnchantedTreeInterior
LeftFoot|MeshPart|0|1,0.3,1|6235.36,17160.61,16936.62|Build/EnchantedTreeInterior
LeftLowerLeg|MeshPart|0|1,1.19,1|6235.41,17160.55,16937.27|Build/EnchantedTreeInterior
LeftUpperArm|MeshPart|0|1,1.17,1|6235.23,17162.61,16938.07|Build/EnchantedTreeInterior
RightHand|MeshPart|0|1,0.3,1|6235.24,17162.54,16937.97|Build/EnchantedTreeInterior
RightLowerArm|MeshPart|0|1,1.05,1|6234.68,17162.44,16938.23|Build/EnchantedTreeInterior
LeftLowerArm|MeshPart|0|1,1.05,1|6234.73,17162.54,16938.29|Build/EnchantedTreeInterior
LeftHand|MeshPart|0|1,0.3,1|6234.1,17162.57,16938.29|Build/EnchantedTreeInterior
UpperTorso|MeshPart|0|2,1.6,1|6234.74,17162.44,16937.53|Build/EnchantedTreeInterior
LowerTorso|MeshPart|0|2,0.4,1|6234.82,17161.49,16937.84|Build/EnchantedTreeInterior
Head|MeshPart|1|1,1,1|6234.7,17163.69,16937.41|Build/EnchantedTreeInterior
RightLowerLeg|MeshPart|0|1,1.19,1|6234.32,17160.12,16938.27|Build/EnchantedTreeInterior
RightFoot|MeshPart|0|1,0.3,1|6234.31,17159.48,16938.38|Build/EnchantedTreeInterior
Handle|Part|1|2.33,2.18,1.52|6263.48,17163.69,16973.65|Build/EnchantedTreeInterior
Handle|Part|1|1.72,2.11,1.62|6263.22,17165.03,16973.83|Build/EnchantedTreeInterior
Handle|Part|1|1,1,1|6263.6,17162.67,16973.58|Build/EnchantedTreeInterior
Handle|Part|1|1,1,1|6263.49,17163.95,16973.59|Build/EnchantedTreeInterior
Hat|Part|1|1.23,1.23,1.23|6263.35,17165.55,16973.72|Build/EnchantedTreeInterior
Glasses|Part|1|1.23,0.74,0.99|6263.45,17165.69,16973.66|Build/EnchantedTreeInterior
Head|Part|0|2,1,1|6263.23,17165.01,16973.8|Build/EnchantedTreeInterior
Torso|Part|0|2,2,1|6263.49,17163.56,16973.64|Build/EnchantedTreeInterior
Antlers|Part|1|1.25,2.49,1.25|6262.97,17166.23,16973.95|Build/EnchantedTreeInterior
Left Arm|Part|0|1,2,1|6263.75,17163.37,16972.42|Build/EnchantedTreeInterior
Left Leg|Part|0|1,2,1|6263.95,17162,16972.78|Build/EnchantedTreeInterior
Right Leg|Part|0|1,2,1|6264.41,17162.07,16974.02|Build/EnchantedTreeInterior
Right Arm|Part|0|1,2,1|6263.47,17163.39,16975.23|Build/EnchantedTreeInterior
mesh_node.013|MeshPart|0|3.1,2.25,1.06|6277.06,17167.86,16945.78|Build/EnchantedTreeInterior
mesh_node.006|MeshPart|0|1.71,0.42,1.9|6277.64,17170.93,16945.57|Build/EnchantedTreeInterior
mesh_node.012|MeshPart|0|5.03,5.93,3.84|6279.37,17167.98,16944.81|Build/EnchantedTreeInterior
mesh_node.005|MeshPart|0|3.16,1.74,0.39|6277.56,17171.4,16945.56|Build/EnchantedTreeInterior
mesh_node.007|MeshPart|0|1.63,0.53,0.06|6276.65,17170.17,16945.93|Build/EnchantedTreeInterior
mesh_node.017|MeshPart|0|3.6,2.65,4.56|6278.76,17166.09,16945.08|Build/EnchantedTreeInterior
mesh_node.018|MeshPart|0|4.87,5.91,3.85|6279.36,17167.96,16944.81|Build/EnchantedTreeInterior
mesh_node.019|MeshPart|0|4.07,4.34,1.4|6277.2,17165.81,16945.7|Build/EnchantedTreeInterior
mesh_node.014|MeshPart|0|2.42,1.41,2.18|6277.57,17169.51,16945.55|Build/EnchantedTreeInterior
mesh_node.016|MeshPart|0|7.6,4.71,4.37|6274.34,17166.45,16945.68|Build/EnchantedTreeInterior
mesh_node.015|MeshPart|0|6.17,5.27,1.04|6277.99,17166.54,16945.38|Build/EnchantedTreeInterior
Cylinder.001|MeshPart|0|2.25,0.39,2.14|6277.04,17166.65,16945.81|Build/EnchantedTreeInterior
Cylinder.002|MeshPart|0|1.52,0.32,1.45|6277.03,17163.83,16945.81|Build/EnchantedTreeInterior
Cube.001|MeshPart|0|1.08,1.31,0.07|6272.51,17166,16947.49|Build/EnchantedTreeInterior
mesh_node.024|MeshPart|0|8.56,2.38,3.45|6274.37,17169.18,16947.32|Build/EnchantedTreeInterior
Cube.004|MeshPart|0|1.35,1.75,0.14|6272.51,17165.82,16947.37|Build/EnchantedTreeInterior
Cylinder|MeshPart|0|0.35,2.47,0.33|6277.07,17165.23,16945.8|Build/EnchantedTreeInterior
mesh_node.023|MeshPart|0|7.92,3.64,4.12|6274.62,17167.14,16945.54|Build/EnchantedTreeInterior
mesh_node.025|MeshPart|0|0.61,0.47,0.7|6274.31,17164.11,16944.96|Build/EnchantedTreeInterior
mesh_node.011|MeshPart|0|7.14,4.62,4.36|6274.18,17166.49,16945.65|Build/EnchantedTreeInterior
mesh_node|MeshPart|0|9.42,6.49,4.87|6274.57,17167.33,16946.36|Build/EnchantedTreeInterior
mesh_node.020|MeshPart|0|3.43,3.55,2.36|6273.55,17165.78,16946.95|Build/EnchantedTreeInterior
mesh_node.021|MeshPart|0|8.35,0.82,3.87|6274.11,17164.25,16947.23|Build/EnchantedTreeInterior
Cube.003|MeshPart|0|1.25,0.49,0.3|6276.9,17168.88,16945.84|Build/EnchantedTreeInterior
mesh_node.008|MeshPart|0|1.41,0.47,0.62|6277.01,17170.22,16945.79|Build/EnchantedTreeInterior
mesh_node.009|MeshPart|0|2.42,1.81,2.33|6277.42,17170.32,16945.61|Build/EnchantedTreeInterior
Cube.005|MeshPart|0|0.54,0.14,2.75|6278.36,17169.03,16949.45|Build/EnchantedTreeInterior
Cube.002|MeshPart|0|1.19,0.04,0.79|6275.19,17169.04,16942.71|Build/EnchantedTreeInterior
Cube|MeshPart|0|0.62,0.14,2.75|6275.45,17169.03,16942.4|Build/EnchantedTreeInterior
mesh_node.003|MeshPart|0|2.18,0.67,0.2|6276.67,17170.17,16945.92|Build/EnchantedTreeInterior
Cube.006|MeshPart|0|1.15,0.03,1.25|6278.01,17169.03,16949.62|Build/EnchantedTreeInterior
mesh_node.001|MeshPart|0|4.04,5.18,4.45|6278.51,17167.41,16945.18|Build/EnchantedTreeInterior
mesh_node.004|MeshPart|0|3.07,1.38,3.2|6277.69,17171.11,16945.54|Build/EnchantedTreeInterior
mesh_node.002|MeshPart|0|8.73,5.72,1.22|6278.01,17166.5,16945.37|Build/EnchantedTreeInterior
Bell|MeshPart|0|1.09,0.96,3.47|6269.33,17169.35,16977.04|Build/EnchantedTreeInterior
mesh_node.004|MeshPart|0|5.63,2.74,2.1|6273.42,17169.29,16975.56|Build/EnchantedTreeInterior
mesh_node.003|MeshPart|0|6.97,1.61,1.19|6272.33,17169.18,16974.83|Build/EnchantedTreeInterior
mesh_node.002|MeshPart|0|1.78,0.58,1.45|6272.25,17170.79,16974.77|Build/EnchantedTreeInterior
mesh_node.007|MeshPart|0|1.04,0.31,0.3|6271.9,17170.72,16974.54|Build/EnchantedTreeInterior
mesh_node.006|MeshPart|0|1.43,0.45,0.17|6271.76,17170.78,16974.44|Build/EnchantedTreeInterior
mesh_node.005|MeshPart|0|4,1.32,0.37|6272.34,17171.24,16974.83|Build/EnchantedTreeInterior
Cube|MeshPart|0|0.9,0.86,0.21|6271.85,17170.69,16974.51|Build/EnchantedTreeInterior
Bell.004|MeshPart|0|0.17,0.17,2.43|6269.8,17169.35,16977.27|Build/EnchantedTreeInterior
Bell.003|MeshPart|0|0.99,0.99,2.3|6268.85,17169.35,16976.64|Build/EnchantedTreeInterior
Bell.002|MeshPart|0|0.07,0.25,0.93|6269.68,17169.33,16976.78|Build/EnchantedTreeInterior
Bell.001|MeshPart|0|0.46,0.26,2.06|6270.07,17169.35,16977.32|Build/EnchantedTreeInterior
mesh_node.001|MeshPart|0|2.12,2.67,2.86|6272.38,17171.46,16974.82|Build/EnchantedTreeInterior
mesh_node|MeshPart|0|2.35,4.55,0.99|6272.64,17166.2,16975.04|Build/EnchantedTreeInterior
mesh_node.008|MeshPart|0|2,2.38,1.35|6273.03,17169.94,16974.44|Build/EnchantedTreeInterior
mesh_node.009|MeshPart|0|7.84,7.6,1.62|6272.36,17167.74,16974.85|Build/EnchantedTreeInterior
mesh_node.010|MeshPart|0|4.17,5.59,2.49|6272.97,17169.17,16975.26|Build/EnchantedTreeInterior
mesh_node.014|MeshPart|0|4.73,6.88,0.26|6273.76,17167.13,16976.29|Build/EnchantedTreeInterior
mesh_node.012|MeshPart|0|0.78,10.31,1.85|6274.09,17168.57,16976.26|Build/EnchantedTreeInterior
mesh_node.008|MeshPart|0|1.72,0.45,1.76|6273.96,17173.06,16967.1|Build/EnchantedTreeInterior
mesh_node.013|MeshPart|0|0.98,0.66,0.54|6274.62,17173.14,16976.27|Build/EnchantedTreeInterior
mesh_node.010|MeshPart|0|4.74,10.53,2.12|6274.25,17168.96,16976.29|Build/EnchantedTreeInterior
mesh_node.007|MeshPart|0|0.8,1.56,1.1|6273.99,17170.94,16967.19|Build/EnchantedTreeInterior
Cube|MeshPart|0|1.31,0.09,0.63|6273.26,17167.05,16976.27|Build/EnchantedTreeInterior
Cube.001|MeshPart|0|1.11,2.41,0.37|6273.71,17165.4,16977.31|Build/EnchantedTreeInterior
Cube.002|MeshPart|0|1.05,0.79,0.15|6273.59,17165.43,16977.32|Build/EnchantedTreeInterior
Cube.004|MeshPart|0|2.62,1.55,0.25|6273.53,17167.16,16976.31|Build/EnchantedTreeInterior
mesh_node.011|MeshPart|0|0.38,6.99,1.57|6273.69,17169.54,16976.27|Build/EnchantedTreeInterior
mesh_node.009|MeshPart|0|1.36,1.31,1.11|6274.02,17171,16967.19|Build/EnchantedTreeInterior
mesh_node.004|MeshPart|0|3.15,1.39,3.18|6273.97,17173.21,16967.11|Build/EnchantedTreeInterior
mesh_node.006|MeshPart|0|1.64,2.44,1.39|6274.08,17170.44,16967.19|Build/EnchantedTreeInterior
mesh_node.005|MeshPart|0|1.64,0.63,1.23|6273.57,17172.46,16967.19|Build/EnchantedTreeInterior
mesh_node.001|MeshPart|0|0.75,0.1,0.18|6273.13,17172.01,16967.19|Build/EnchantedTreeInterior
mesh_node|MeshPart|0|10.49,9.62,2.68|6273.75,17168.72,16967.19|Build/EnchantedTreeInterior
mesh_node.003|MeshPart|0|1.3,0.42,0.09|6273.03,17172.37,16967.19|Build/EnchantedTreeInterior
Cube.003|MeshPart|0|0.59,1.84,0.13|6273.59,17165.65,16977.41|Build/EnchantedTreeInterior
mesh_node.002|MeshPart|0|3.79,6.33,1.52|6275.1,17168.47,16967.19|Build/EnchantedTreeInterior
Cube.006|MeshPart|1|2.27,0.42,5.87|6271.56,17169.7,16962.81|Build/EnchantedTreeInterior
Cube.005|MeshPart|1|2.03,0.1,1.86|6269.82,17169.71,16962.81|Build/EnchantedTreeInterior
Cube.004|MeshPart|1|2.71,0.92,1.84|6269.53,17169.45,16962.7|Build/EnchantedTreeInterior
Cube.003|MeshPart|1|2.77,1.01,6.1|6271.43,17169.47,16962.81|Build/EnchantedTreeInterior
BanjoFirefly_ShoulderDecor|MeshPart|1|4.15,2.4,2.26|6272.78,17170.66,16958.18|Build/EnchantedTreeInterior
BanjoFirefly_Mouth|MeshPart|1|0.98,0.32,0.24|6271.85,17171.1,16958.18|Build/EnchantedTreeInterior
Plane|MeshPart|1|2.18,0.25,4.78|6270.93,17169.66,16962.32|Build/EnchantedTreeInterior
Cube.007|MeshPart|1|0.59,0.06,5.36|6271.65,17169.87,16962.81|Build/EnchantedTreeInterior
BanjoFirefly_ClothInside|MeshPart|1|1.45,3.22,1.37|6272.76,17169.28,16958.18|Build/EnchantedTreeInterior
Cube.001|MeshPart|1|2.57,0.38,5.71|6271.76,17169.69,16962.63|Build/EnchantedTreeInterior
BanjoFirefly_faceBlush|MeshPart|1|1.32,0.13,0.14|6272.13,17171.05,16958.18|Build/EnchantedTreeInterior
BanjoFirefly_Wings_Inside|MeshPart|1|3.81,3.61,1.34|6274.39,17168.11,16958.15|Build/EnchantedTreeInterior
BanjoFirefly_Wings_Outside|MeshPart|1|3.83,3.78,1.38|6274.39,17168.19,16958.15|Build/EnchantedTreeInterior
BanjoFirefly_Glasses_Glass|MeshPart|1|1.51,0.5,0.23|6271.82,17171.57,16958.18|Build/EnchantedTreeInterior
BanjoFirefly_Glasses_Corp|MeshPart|1|1.67,0.32,0.25|6271.79,17171.7,16958.18|Build/EnchantedTreeInterior
BanjoFirefly_Eyes|MeshPart|1|1.42,0.76,0.41|6272.01,17171.54,16958.18|Build/EnchantedTreeInterior
BanjoFirefly_ClothTop|MeshPart|1|7.23,6.5,2.15|6273.06,17167.88,16958.18|Build/EnchantedTreeInterior
BanjoFirefly_Body|MeshPart|1|10.37,8.91,3.32|6272.28,17168.47,16958.18|Build/EnchantedTreeInterior
BanjoFirefly_Banjoobelt|MeshPart|1|2.03,2.21,1.94|6272.89,17169.56,16958.19|Build/EnchantedTreeInterior
Banjo|MeshPart|1|2.67,0.89,6.32|6271.59,17169.47,16962.81|Build/EnchantedTreeInterior
BanjoFirefly_Hairs|MeshPart|1|1.74,2.24,2.57|6273.02,17172.38,16958.18|Build/EnchantedTreeInterior
BanjoFirefly_Lightwhisckers|MeshPart|1|4.18,0.27,0.26|6270.67,17172.47,16958.18|Build/EnchantedTreeInterior
BanjoFirefly_ClothDecor_FloversCentre|MeshPart|1|2.31,4.8,0.24|6272.25,17167.81,16958.18|Build/EnchantedTreeInterior
BanjoFirefly_ClothDecor_Flovers|MeshPart|1|2.47,4.85,0.37|6272.28,17167.67,16958.18|Build/EnchantedTreeInterior
BanjoFirefly_ClothCecor_Herbs|MeshPart|1|6.88,5.43,1.27|6272.65,17167.6,16958.18|Build/EnchantedTreeInterior
Vine2|MeshPart|1|3.04,73.29,22|6240.49,17159.33,16901.11|Build/EnchantedTreeInterior
Leaves1|MeshPart|1|0.43,36.46,23.13|6222.19,17159.48,16919.04|Build/EnchantedTreeInterior
Leaves1|MeshPart|1|3.26,22.11,14.02|6258.73,17184.69,16883.46|Build/EnchantedTreeInterior
Vine2|MeshPart|1|3.04,73.29,22|6240.49,17159.33,16980.03|Build/EnchantedTreeInterior
Leaves1|MeshPart|1|0.43,36.46,23.13|6262.95,17159.48,16957.54|Build/EnchantedTreeInterior
Leaves1|MeshPart|1|0.43,36.46,23.13|6263.99,17159.48,16890.7|Build/EnchantedTreeInterior
Leaves1|MeshPart|1|6.26,22.11,14.02|6259.42,17178.92,16997.6|Build/EnchantedTreeInterior
Leaves1|MeshPart|1|1.26,22.11,14.02|6279.16,17180.89,16957.7|Build/EnchantedTreeInterior
Circle|MeshPart|0|5.98,1.32,5.75|6231.95,17164.88,16912.9|Build/EnchantedTreeInterior
Cylinder.005|MeshPart|0|6.78,2.26,7.13|6231.93,17164.25,16912.8|Build/EnchantedTreeInterior
Cylinder.004|MeshPart|0|3.56,4.13,3.74|6231.93,17161.09,16912.8|Build/EnchantedTreeInterior
Cylinder.005|MeshPart|0|6.78,2.26,7.13|6244.93,17164.25,16918.8|Build/EnchantedTreeInterior
Circle|MeshPart|0|5.98,1.32,5.75|6244.95,17164.88,16918.9|Build/EnchantedTreeInterior
Cylinder.004|MeshPart|0|3.56,4.13,3.74|6244.93,17161.09,16918.8|Build/EnchantedTreeInterior
Cylinder.004|MeshPart|0|3.56,4.13,3.74|6218.93,17161.09,16903.8|Build/EnchantedTreeInterior
Cylinder.005|MeshPart|0|6.78,2.26,7.13|6218.93,17164.25,16903.8|Build/EnchantedTreeInterior
Circle|MeshPart|0|5.98,1.32,5.75|6218.95,17164.88,16903.9|Build/EnchantedTreeInterior
Cylinder.005|MeshPart|0|6.78,2.26,7.13|6257.93,17164.25,16912.8|Build/EnchantedTreeInterior
Cylinder.004|MeshPart|0|3.56,4.13,3.74|6257.93,17161.09,16912.8|Build/EnchantedTreeInterior
Circle|MeshPart|0|5.98,1.32,5.75|6257.95,17164.88,16912.9|Build/EnchantedTreeInterior
Cylinder.005|MeshPart|0|6.01,2,6.32|6230.25,17163.98,16989.48|Build/EnchantedTreeInterior
Cylinder.004|MeshPart|0|3.16,3.66,3.32|6230.25,17161.18,16989.48|Build/EnchantedTreeInterior
Circle|MeshPart|0|5.3,1.17,5.1|6230.27,17164.54,16989.57|Build/EnchantedTreeInterior
Part|Part|0|5,8.5,25.63|6282.29,17184.69,16973.25|Build/EnchantedTreeInterior
Part|Part|0|5.5,2.88,14.5|6282.29,17165.38,16993.06|Build/EnchantedTreeInterior
Part|Part|0|5.5,2.88,25.5|6282.29,17165.38,16947.94|Build/EnchantedTreeInterior
Part|Part|0|7,3,59.88|6282.29,17184.69,16973.25|Build/EnchantedTreeInterior
Part|Part|0|5,25,14|6282.29,17176.44,16993.06|Build/EnchantedTreeInterior
Part|Part|0|2.63,17.25,31.88|6283.48,17172.57,16974.5|Build/EnchantedTreeInterior
Part|Part|0|5,25,36|6282.29,17176.44,16952.44|Build/EnchantedTreeInterior
Part|Part|0|102.75,2.25,133.5|6250.05,17157.98,16941.45|Build/EnchantedTreeInterior
Cylinder.005|MeshPart|0|4.19,1.39,4.41|6260.53,17163.64,16951.43|Build/EnchantedTreeInterior
Cylinder.004|MeshPart|0|2.2,2.55,2.31|6260.53,17161.68,16951.43|Build/EnchantedTreeInterior
Circle|MeshPart|0|3.69,0.81,3.55|6260.55,17164.03,16951.5|Build/EnchantedTreeInterior
Cube|MeshPart|0|81.88,1.49,79.3|6247.53,17158.6,16896.91|Build/EnchantedTreeInterior
Cube.330|MeshPart|0|27.98,5.04,68.9|6282.55,17161.42,16969.99|Build/EnchantedTreeInterior
Cube|MeshPart|0|81.88,1.49,79.3|6242.68,17158.6,16974.53|Build/EnchantedTreeInterior
Cylinder.004|MeshPart|0|3.84,4.45,4.04|6232.3,17161.57,16955.9|Build/EnchantedTreeInterior
Circle|MeshPart|0|6.45,1.42,6.2|6232.32,17165.66,16956.02|Build/EnchantedTreeInterior
Cylinder.005|MeshPart|0|7.32,2.43,7.69|6232.3,17164.98,16955.9|Build/EnchantedTreeInterior
Cube.002|MeshPart|0|1.48,1.7,26.94|6281.5,17179.09,16973.3|Build/EnchantedTreeInterior
Plane.001|MeshPart|0|0.67,15.66,23.66|6281.3,17172.41,16973.21|Build/EnchantedTreeInterior
Cylinder.005|MeshPart|0|6.01,2,6.32|6252.47,17163.98,16994.18|Build/EnchantedTreeInterior
Circle|MeshPart|0|5.3,1.17,5.1|6252.49,17164.54,16994.28|Build/EnchantedTreeInterior
Cylinder.004|MeshPart|0|3.16,3.66,3.32|6252.47,17161.18,16994.18|Build/EnchantedTreeInterior
Circle.008|MeshPart|0|98.77,56.58,156.47|6249.83,17179.56,16930.12|Build/EnchantedTreeInterior
Circle.008|MeshPart|0|96.77,52.83,154.22|6249.83,17180.94,16930.25|Build/EnchantedTreeInterior
Circle.001|MeshPart|0|108.34,58.86,162.68|6248.47,17178.55,16930.17|Build/EnchantedTreeInterior
Cylinder.005|MeshPart|0|3.48,1.16,3.66|6252.7,17162.03,16966.39|Build/EnchantedTreeInterior
Circle|MeshPart|0|3.07,0.68,2.95|6252.71,17162.35,16966.45|Build/EnchantedTreeInterior
Cylinder.004|MeshPart|0|1.83,2.12,1.92|6252.7,17160.41,16966.39|Build/EnchantedTreeInterior
Circle|MeshPart|0|4.37,0.96,4.2|6262.71,17163.63,16985.47|Build/EnchantedTreeInterior
Cylinder.005|MeshPart|0|4.96,1.65,5.21|6262.7,17163.17,16985.39|Build/EnchantedTreeInterior
Cylinder.004|MeshPart|0|2.6,3.02,2.74|6262.7,17160.85,16985.39|Build/EnchantedTreeInterior
Cylinder.007|MeshPart|0|25,0.24,25|6284.29,17164.06,16973.19|Build/EnchantedTreeInterior
Cylinder.007|MeshPart|0|25,0.24,25|6260.51,17159.46,16973.24|Build/EnchantedTreeInterior
Cylinder.004|MeshPart|0|3.56,4.13,3.74|6270.93,17161.09,16903.8|Build/EnchantedTreeInterior
Cylinder.005|MeshPart|0|6.78,2.26,7.13|6270.93,17164.25,16903.8|Build/EnchantedTreeInterior
Circle|MeshPart|0|5.98,1.32,5.75|6270.95,17164.88,16903.9|Build/EnchantedTreeInterior
arched wooden door|MeshPart|0|9.65,13.24,2.68|6243.9,17164.15,16935.92|Build/EnchantedTreeInterior
long wall deep moss.005|MeshPart|0|80.77,38.48,2.42|6243.9,17177.07,16935.08|Build/EnchantedTreeInterior
long wall deep moss.004|MeshPart|0|87.21,38.55,2.42|6243.9,17177.07,16935.08|Build/EnchantedTreeInterior
long wall deep moss.003|MeshPart|0|90.99,39.39,5.56|6243.9,17177.31,16935.13|Build/EnchantedTreeInterior
long wall deep moss.001|MeshPart|0|91.43,38.74,4.93|6243.9,17177.17,16935.13|Build/EnchantedTreeInterior
long wall deep moss.007|MeshPart|0|92.16,38.85,5.23|6243.9,17177.02,16935.13|Build/EnchantedTreeInterior
outer door frame|MeshPart|0|12.67,14.75,4.8|6243.9,17164.95,16935.02|Build/EnchantedTreeInterior
long wall deep moss.006|MeshPart|0|92.85,37.95,0.4|6244.19,17177.19,16934.97|Build/EnchantedTreeInterior
long wall deep moss.002|MeshPart|0|94.99,38.41,2.42|6243.9,17177.11,16935.08|Build/EnchantedTreeInterior
woven root wall.004|MeshPart|0|48.67,42.33,5.71|6279.69,17179.51,16913.81|Build/EnchantedTreeInterior
woven root wall|MeshPart|0|48.17,42.92,5.92|6279.31,17179.83,16913.98|Build/EnchantedTreeInterior
woven root wall.005|MeshPart|0|45.23,42.21,4.56|6280.26,17179.68,16912.57|Build/EnchantedTreeInterior
woven root wall.001|MeshPart|0|49.17,41.85,4.6|6282.22,17179.61,16914.14|Build/EnchantedTreeInterior
woven root wall.002|MeshPart|0|47.65,42.01,4.6|6280.22,17179.57,16916.82|Build/EnchantedTreeInterior
long wall deep moss.005|MeshPart|0|80.77,38.48,2.42|6246.9,17177.07,16878.08|Build/EnchantedTreeInterior
long wall deep moss.002|MeshPart|0|94.99,38.41,2.42|6246.9,17177.11,16878.08|Build/EnchantedTreeInterior
long wall deep moss.004|MeshPart|0|87.21,38.55,2.42|6246.9,17177.07,16878.08|Build/EnchantedTreeInterior
long wall deep moss.003|MeshPart|0|90.99,39.39,5.56|6246.9,17177.31,16878.13|Build/EnchantedTreeInterior
long wall deep moss.001|MeshPart|0|91.43,38.74,4.93|6246.9,17177.17,16878.13|Build/EnchantedTreeInterior
MushroomExitGlow|MeshPart|1|0.3,15.63,11.09|6246.9,17164.55,16877.33|Build/EnchantedTreeInterior
long wall deep moss.007|MeshPart|0|92.16,38.85,5.23|6246.9,17177.02,16878.13|Build/EnchantedTreeInterior
outer door frame|MeshPart|0|12.67,14.75,4.8|6246.9,17164.95,16878.02|Build/EnchantedTreeInterior
long wall deep moss.006|MeshPart|0|92.85,37.95,0.4|6247.19,17177.19,16877.97|Build/EnchantedTreeInterior
woven root wall.005|MeshPart|0|45.23,42.21,4.56|6212.85,17179.68,16950|Build/EnchantedTreeInterior
woven root wall|MeshPart|0|48.17,42.92,5.92|6214.18,17179.83,16948.92|Build/EnchantedTreeInterior
woven root wall.004|MeshPart|0|48.67,42.33,5.71|6213.76,17179.51,16948.98|Build/EnchantedTreeInterior
woven root wall.001|MeshPart|0|49.17,41.85,4.6|6211.44,17179.61,16947.93|Build/EnchantedTreeInterior
woven root wall.002|MeshPart|0|47.65,42.01,4.6|6214.13,17179.57,16945.95|Build/EnchantedTreeInterior
woven root wall.001|MeshPart|0|49.17,41.85,4.6|6211.9,17179.61,16918.31|Build/EnchantedTreeInterior
woven root wall|MeshPart|0|48.17,42.92,5.92|6212.55,17179.83,16915.47|Build/EnchantedTreeInterior
woven root wall.004|MeshPart|0|48.67,42.33,5.71|6212.65,17179.51,16915.88|Build/EnchantedTreeInterior
woven root wall.005|MeshPart|0|45.23,42.21,4.56|6213.78,17179.68,16916.66|Build/EnchantedTreeInterior
woven root wall.002|MeshPart|0|47.65,42.01,4.6|6209.6,17179.57,16915.88|Build/EnchantedTreeInterior
Part|Part|0|916,34.75,206|5588.52,50.2,-363.81|Build/LightDarkZone
Star Boy.002|MeshPart|1|2.02,2.11,2.11|539.86,77.54,-403.3|Build/StarHandler
Star Boy.001|MeshPart|1|3.73,4.94,1.86|539.66,70.62,-403.09|Build/StarHandler
Star Boy|MeshPart|1|6.82,5.61,3.86|540.15,71.12,-403.61|Build/StarHandler
Star|MeshPart|1|1.62,1.44,0.48|540,67.5,-403.45|Build/StarHandler
Eyebalck|MeshPart|1|0.72,0.24,0.04|539.85,67.46,-403.29|Build/StarHandler
Star Boy.007|MeshPart|1|0.62,0.95,0.23|539.21,77.36,-402.6|Build/StarHandler
Star Boy.006|MeshPart|1|2.76,0.31,0.43|538.96,74.5,-402.33|Build/StarHandler
eye|MeshPart|1|0.56,0.05,0.01|539.86,67.54,-403.3|Build/StarHandler
Star Boy.005|MeshPart|1|1.99,0.85,0.78|538.72,74.89,-402.07|Build/StarHandler
Star Boy.004|MeshPart|1|8.58,9.76,3.31|539.57,72.31,-402.99|Build/StarHandler
Star Boy.003|MeshPart|1|7.94,5.77,4.21|540.12,70.66,-403.58|Build/StarHandler
Cube.070|MeshPart|1|2.4,15.44,6.34|6872.06,75.04,-310.98|Build/EnchantedForestZone
Key|MeshPart|1|0.08,1.68,0.51|6869.15,74.31,-311.88|Build/EnchantedForestZone
Key|MeshPart|1|0.08,1.68,0.51|6868.64,74.31,-311.88|Build/EnchantedForestZone
Cube.082|MeshPart|1|2.4,15.44,6.34|6865.73,75.04,-310.98|Build/EnchantedForestZone
Cube.080|MeshPart|1|2.05,17.64,17.06|6868.89,76.14,-311.22|Build/EnchantedForestZone
Plane.011|MeshPart|1|130.34,149.02,197.15|6868.74,141.39,-265.5|Build/EnchantedForestZone
Cube.066|MeshPart|1|77.08,126.25,118.67|6869.94,130.5,-295.53|Build/EnchantedForestZone
Plane.017|MeshPart|1|0.49,15.77,15.05|6868.77,75.22,-308.84|Build/EnchantedForestZone
Cube.050|MeshPart|1|212.43,140.36,292.86|6855.53,223.57,-243.6|Build/EnchantedForestZone
Plane.014|MeshPart|1|6.07,26.61,15.14|6870.66,112.88,-278.03|Build/EnchantedForestZone
Plane.018|MeshPart|1|57.89,116.69,92.18|6859.38,129.18,-297.57|Build/EnchantedForestZone
Union|UnionOperation|1|917,147.77,218|6529.77,128.46,-363.81|Build/EnchantedForestZone
Part|Part|1|53.63,1,35|6354.66,77.52,-451.91|Build/EnchantedForestZone
Part|Part|1|43.13,1,35|6359.83,97.39,-464.2|Build/EnchantedForestZone
Part|Part|1|966,32.75,201.75|6529.52,49.2,-362.93|Build/EnchantedForestZone
Part|Part|1|26.5,1,35|6161.52,96.02,-465.33|Build/EnchantedForestZone
Part|Part|1|48.5,1,41|6947.53,92.02,-274.28|Build/EnchantedForestZone
Part|Part|1|29.5,1,35|6086.02,103.02,-456.33|Build/EnchantedForestZone
Part|Part|1|31,2,27|6540.14,150.89,-474.34|Build/EnchantedForestZone
Part|Part|1|45,2,27|6538.14,201.35,-486.34|Build/EnchantedForestZone
Part|Part|1|43.13,1,35|6699.22,97.39,-263.41|Build/EnchantedForestZone
Part|Part|1|30,1,35|6972.78,103.02,-271.28|Build/EnchantedForestZone
Part|Part|1|31,2,27|6361.91,88.89,-272.03|Build/EnchantedForestZone
Part|Part|1|32.75,2,35|6422.02,89.02,-461.2|Build/EnchantedForestZone
Part|Part|1|31,2,27|6697.14,88.89,-455.58|Build/EnchantedForestZone
Part|Part|1|31,2,36|6293.91,89.89,-265.53|Build/EnchantedForestZone
Part|Part|1|32,2,36|6117.41,89.39,-265.87|Build/EnchantedForestZone
Part|Part|1|48.5,1,41|6111.52,92.02,-453.33|Build/EnchantedForestZone
Part|Part|1|31,2,27|6518.91,150.89,-253.27|Build/EnchantedForestZone
Part|Part|1|53.63,1,35|6704.39,77.52,-275.7|Build/EnchantedForestZone
Part|Part|1|45,2,27|6520.91,201.35,-241.27|Build/EnchantedForestZone
Part|Part|1|32.75,2,35|6637.03,89.02,-266.41|Build/EnchantedForestZone
Part|Part|1|32,2,36|6941.64,89.39,-461.74|Build/EnchantedForestZone
Part|Part|1|88.63,1,35|6242.08,88.02,-463.08|Build/EnchantedForestZone
Part|Part|1|31,2,36|6765.14,89.89,-462.08|Build/EnchantedForestZone
Part|Part|1|52,53,70|6147.22,89.93,-228.91|Build/EnchantedForestZone
Part|Part|1|54,53,72|6147.22,88.93,-228.91|Build/EnchantedForestZone
Part|Part|1|64,74,70|6110.14,99.43,-206.14|Build/EnchantedForestZone
Part|Part|1|62,74,68|6110.14,100.43,-206.14|Build/EnchantedForestZone
Part|Part|1|65,25,56|7045.57,75.93,-398.94|Build/EnchantedForestZone
Part|Part|1|67,25,58|7045.57,74.93,-398.94|Build/EnchantedForestZone
Part|Part|1|110,54,98|6417.41,95.58,-197.45|Build/EnchantedForestZone
Part|Part|1|112,54,100|6417.41,94.58,-197.45|Build/EnchantedForestZone
Part|Part|1|54,96,50|6387.76,100.43,-500.01|Build/EnchantedForestZone
Part|Part|1|52,96,48|6387.76,101.43,-500.01|Build/EnchantedForestZone
Part|Part|1|46,37,67|7041.07,80.93,-428.44|Build/EnchantedForestZone
Part|Part|1|44,37,65|7041.07,81.93,-428.44|Build/EnchantedForestZone
Part|Part|1|35,30,73|7052.66,78.43,-357.51|Build/EnchantedForestZone
Part|Part|1|37,30,75|7052.66,77.43,-357.51|Build/EnchantedForestZone
Part|Part|1|35,6,28|7017.45,65.43,-370.8|Build/EnchantedForestZone
Part|Part|1|33,6,26|7017.45,66.43,-370.8|Build/EnchantedForestZone
Part|Part|1|51,80,72|6323.67,102.43,-508.7|Build/EnchantedForestZone
Part|Part|1|49,80,70|6323.67,103.43,-508.7|Build/EnchantedForestZone
Part|Part|1|31,14,32|7010.59,64.43,-343.83|Build/EnchantedForestZone
Part|Part|1|33,14,34|7010.59,63.43,-343.83|Build/EnchantedForestZone
Part|Part|1|64,35,61|6377.41,86.08,-233.95|Build/EnchantedForestZone
Part|Part|1|66,35,63|6377.41,85.08,-233.95|Build/EnchantedForestZone
Part|Part|1|29,18,69|7044.09,72.43,-392.83|Build/EnchantedForestZone
Part|Part|1|31,18,71|7044.09,71.43,-392.83|Build/EnchantedForestZone
Part|Part|1|71,16,48|7020.48,71.43,-423.16|Build/EnchantedForestZone
Part|Part|1|73,16,50|7020.48,70.43,-423.16|Build/EnchantedForestZone
Part|Part|1|66,65,63|6165.83,94.93,-194.2|Build/EnchantedForestZone
Part|Part|1|64,65,61|6165.83,95.93,-194.2|Build/EnchantedForestZone
Part|Part|1|67,42,48|6341.67,109.43,-500.7|Build/EnchantedForestZone
Part|Part|1|69,42,50|6341.67,108.43,-500.7|Build/EnchantedForestZone
Part|Part|1|54,28,53|7023.64,66.43,-301.11|Build/EnchantedForestZone
Part|Part|1|52,28,51|7023.64,67.43,-301.11|Build/EnchantedForestZone
Part|Part|1|64,79,70|6224.91,120.93,-197.47|Build/EnchantedForestZone
Part|Part|1|62,79,68|6224.91,121.93,-197.47|Build/EnchantedForestZone
Part|Part|1|28,21,61|7030.09,72.93,-335.33|Build/EnchantedForestZone
Part|Part|1|26,21,59|7030.09,73.93,-335.33|Build/EnchantedForestZone
Part|Part|1|45,81,71|6274.52,93.93,-497.2|Build/EnchantedForestZone
Part|Part|1|47,81,73|6274.52,92.93,-497.2|Build/EnchantedForestZone
Part|Part|1|33,12,29|7014.95,69.43,-399.8|Build/EnchantedForestZone
Part|Part|1|35,12,31|7014.95,68.43,-399.8|Build/EnchantedForestZone
Part|Part|1|32,60,31|7025.09,93.43,-292.33|Build/EnchantedForestZone
Part|Part|1|34,60,33|7025.09,92.43,-292.33|Build/EnchantedForestZone
Part|Part|1|50,35,85|7047.09,79.93,-311.33|Build/EnchantedForestZone
Part|Part|1|48,35,83|7047.09,80.93,-311.33|Build/EnchantedForestZone
Part|Part|1|52,60,57|7040.92,93.43,-445.95|Build/EnchantedForestZone
Part|Part|1|54,60,59|7040.92,92.43,-445.95|Build/EnchantedForestZone
Part|Part|1|64,60,70|6311.91,92.43,-221.47|Build/EnchantedForestZone
Part|Part|1|62,60,68|6311.91,93.43,-221.47|Build/EnchantedForestZone
Part|Part|1|72,65,72|6186.17,94.93,-497.7|Build/EnchantedForestZone
Part|Part|1|70,65,70|6186.17,95.93,-497.7|Build/EnchantedForestZone
Part|Part|1|66,70,63|6268.83,97.43,-194.2|Build/EnchantedForestZone
Part|Part|1|64,70,61|6268.83,98.43,-194.2|Build/EnchantedForestZone
Part|Part|1|64,86,70|6232.25,105.43,-520.47|Build/EnchantedForestZone
Part|Part|1|62,86,68|6232.25,106.43,-520.47|Build/EnchantedForestZone
Part|Part|1|71,90,67|6385.91,113.58,-181.95|Build/EnchantedForestZone
Part|Part|1|73,90,69|6385.91,112.58,-181.95|Build/EnchantedForestZone
sagterrain.027|MeshPart|1|991.52,66,80.44|6526.92,92.58,-264.37|Build/EnchantedForestZone
sagterrain.130|MeshPart|1|989.02,124,111.56|6526.96,122.58,-250.05|Build/EnchantedForestZone
sagterrain.129|MeshPart|1|573,88,122.01|6726.03,109.58,-243.83|Build/EnchantedForestZone
sagterrain.120|MeshPart|1|856,135,96|6569.53,133.08,-258.83|Build/EnchantedForestZone
sagterrain.025|MeshPart|1|955,44,56.24|6519.03,83.58,-270.39|Build/EnchantedForestZone
Part|Part|1|52,69,48|6083.63,87.93,-231.6|Build/EnchantedForestZone
Part|Part|1|54,69,50|6083.63,86.93,-231.6|Build/EnchantedForestZone
Part|Part|1|64,84,70|6327.91,123.43,-197.47|Build/EnchantedForestZone
Part|Part|1|62,84,68|6327.91,124.43,-197.47|Build/EnchantedForestZone
Part|Part|1|64,105,61|6284.83,134.93,-170.2|Build/EnchantedForestZone
Part|Part|1|66,105,63|6284.83,133.93,-170.2|Build/EnchantedForestZone
Part|Part|1|69,27,50|6216.67,100.93,-489.7|Build/EnchantedForestZone
Part|Part|1|67,27,48|6216.67,101.93,-489.7|Build/EnchantedForestZone
Part|Part|1|64,74,70|6948.91,99.43,-521.47|Build/EnchantedForestZone
Part|Part|1|62,74,68|6948.91,100.43,-521.47|Build/EnchantedForestZone
Part|Part|1|67,15,48|6125.72,95.93,-236.91|Build/EnchantedForestZone
Part|Part|1|69,15,50|6125.72,94.93,-236.91|Build/EnchantedForestZone
Part|Part|1|154,43,48|7054.59,84.93,-364.33|Build/EnchantedForestZone
Part|Part|1|156,43,50|7054.59,83.93,-364.33|Build/EnchantedForestZone
Part|Part|1|50,67,70|7068.17,95.93,-347.01|Build/EnchantedForestZone
Part|Part|1|48,67,68|7068.17,96.93,-347.01|Build/EnchantedForestZone
Part|Part|1|73,76,69|6435.91,105.58,-203.95|Build/EnchantedForestZone
Part|Part|1|71,76,67|6435.91,106.58,-203.95|Build/EnchantedForestZone
sagterrain.130|MeshPart|1|989.02,124,111.56|6532.09,122.58,-477.57|Build/EnchantedForestZone
sagterrain.027|MeshPart|1|991.52,66,80.44|6532.12,92.58,-463.24|Build/EnchantedForestZone
sagterrain.025|MeshPart|1|955,44,56.24|6540.01,83.58,-457.22|Build/EnchantedForestZone
sagterrain.129|MeshPart|1|573,88,122.01|6333.01,109.58,-483.78|Build/EnchantedForestZone
sagterrain.120|MeshPart|1|856,135,96|6489.51,133.08,-468.78|Build/EnchantedForestZone
Part|Part|1|45,81,71|6784.53,93.93,-230.41|Build/EnchantedForestZone
Part|Part|1|47,81,189.9|6842.09,92.93,-240.56|Build/EnchantedForestZone
Part|Part|1|52,53,70|6911.83,89.93,-498.7|Build/EnchantedForestZone
Part|Part|1|54,53,72|6911.83,88.93,-498.7|Build/EnchantedForestZone
Part|Part|1|54,69,50|6975.42,86.93,-496.01|Build/EnchantedForestZone
Part|Part|1|52,69,48|6975.42,87.93,-496.01|Build/EnchantedForestZone
Part|Part|1|52,85,42|7058.59,104.93,-393.33|Build/EnchantedForestZone
Part|Part|1|50,85,40|7058.59,105.93,-393.33|Build/EnchantedForestZone
Part|Part|1|64,101,70|6701.8,112.93,-196.14|Build/EnchantedForestZone
Part|Part|1|62,101,68|6701.8,113.93,-196.14|Build/EnchantedForestZone
Part|Part|1|54,55,70|6627.63,89.93,-218.84|Build/EnchantedForestZone
Part|Part|1|52,55,68|6627.63,90.93,-218.84|Build/EnchantedForestZone
Part|Part|1|54,96,50|6671.29,100.43,-227.6|Build/EnchantedForestZone
Part|Part|1|52,96,48|6671.29,101.43,-227.6|Build/EnchantedForestZone
Part|Part|1|67,15,48|6933.33,95.93,-490.7|Build/EnchantedForestZone
Part|Part|1|69,15,50|6933.33,94.93,-490.7|Build/EnchantedForestZone
Part|Part|1|52,55,68|6431.42,90.93,-508.77|Build/EnchantedForestZone
Part|Part|1|54,55,70|6431.42,89.93,-508.77|Build/EnchantedForestZone
Part|Part|1|67,42,48|6717.38,109.43,-226.91|Build/EnchantedForestZone
Part|Part|1|69,42,50|6717.38,108.43,-226.91|Build/EnchantedForestZone
Part|Part|1|64,101,70|6357.25,112.93,-531.47|Build/EnchantedForestZone
Part|Part|1|62,101,68|6357.25,113.93,-531.47|Build/EnchantedForestZone
Part|Part|1|49,80,70|6735.38,103.43,-218.91|Build/EnchantedForestZone
Part|Part|1|51,80,72|6735.38,102.43,-218.91|Build/EnchantedForestZone
untitled|MeshPart|1|91.88,3.52,53.74|6806.6,65.82,-375|Build/EnchantedForestZone
untitled|MeshPart|1|140.88,3.52,60.74|6567.45,65.82,-350.04|Build/EnchantedForestZone
untitled|MeshPart|1|172.88,3.52,88.74|6241.7,65.82,-364.61|Build/EnchantedForestZone
untitled|MeshPart|1|74.88,3.52,40.74|6103.92,65.82,-332.81|Build/EnchantedForestZone
untitled|MeshPart|1|75.88,3.52,43.74|6703.86,65.82,-340.23|Build/EnchantedForestZone
untitled|MeshPart|1|44.88,3.52,42.74|6320.93,65.82,-339.12|Build/EnchantedForestZone
untitled|MeshPart|1|60.88,3.52,33.74|6144.08,65.82,-385.95|Build/EnchantedForestZone
untitled|MeshPart|1|47.38,3.52,73.74|6885.95,65.82,-385.15|Build/EnchantedForestZone
untitled|MeshPart|1|26.38,3.52,53.74|6914.06,65.82,-331.96|Build/EnchantedForestZone
untitled|MeshPart|1|120.88,3.52,42.74|6409.26,65.82,-340.45|Build/EnchantedForestZone
untitled|MeshPart|1|24.88,3.52,22.74|6484.75,65.82,-334.87|Build/EnchantedForestZone
untitled|MeshPart|1|111.88,3.52,24.74|6439.94,65.82,-398.5|Build/EnchantedForestZone
untitled|MeshPart|1|108.88,3.52,80.74|6997.5,65.82,-363.82|Build/EnchantedForestZone
untitled|MeshPart|1|68.88,3.52,33.74|6506.22,65.82,-384.54|Build/EnchantedForestZone
roots|MeshPart|1|356.97,294.82,373.55|6626.22,127.1,-388.64|Build/EnchantedForestZone
roots|MeshPart|1|333.41,275.36,348.89|6334.85,136.83,-346.51|Build/EnchantedForestZone
Plane.015|MeshPart|1|5.78,48.22,16.72|6165.65,130.22,-449.68|Build/EnchantedForestZone
Plane.015|MeshPart|1|4.76,39.71,13.77|7030.68,152.34,-332.71|Build/EnchantedForestZone
Plane.015|MeshPart|1|6.41,53.41,18.52|7023.32,181.3,-399.33|Build/EnchantedForestZone
Plane.015|MeshPart|1|3.67,30.59,10.61|6153.54,141.39,-265.77|Build/EnchantedForestZone
Plane.015|MeshPart|1|5.42,45.16,15.66|6795.79,161.68,-288.98|Build/EnchantedForestZone
Plane.015|MeshPart|1|8.53,71.14,24.67|6885.29,171.91,-318.85|Build/EnchantedForestZone
Plane.015|MeshPart|1|9.21,76.8,26.63|6831.29,153.12,-278.6|Build/EnchantedForestZone
Plane.015|MeshPart|1|9.67,80.61,27.95|6842.41,155.02,-208.48|Build/EnchantedForestZone
Plane.015|MeshPart|1|3.19,26.58,9.22|6202.4,137.64,-444.81|Build/EnchantedForestZone
Plane.015|MeshPart|1|6.41,53.41,18.52|7025.68,144.49,-277.71|Build/EnchantedForestZone
Plane.015|MeshPart|1|4.81,40.11,13.91|6593.28,132.07,-432.15|Build/EnchantedForestZone
Plane.015|MeshPart|1|5.95,49.65,17.21|6759.29,163.58,-269.35|Build/EnchantedForestZone
Plane.015|MeshPart|1|6.35,52.97,18.37|6955.29,151.9,-306.1|Build/EnchantedForestZone
Plane.015|MeshPart|1|7.62,63.53,22.03|6907.79,180.48,-275.85|Build/EnchantedForestZone
Leaf|Part|1|24.88,8.67,26.38|6193.84,126.34,-248.46|Build/EnchantedForestZone
Color2|Part|1|3.02,17.9,2.83|6181.63,113.66,-261.49|Build/EnchantedForestZone
Leaf|Part|1|21.86,13,24.5|6187.65,128.6,-256.87|Build/EnchantedForestZone
Color2|Part|1|3.02,17.71,3.02|6188.29,114.2,-257.17|Build/EnchantedForestZone
Leaf|Part|1|28.27,8.67,26.38|6193.25,126.28,-271.47|Build/EnchantedForestZone
Leaf|Part|1|21.48,7.73,32.32|6176.32,124.07,-266.92|Build/EnchantedForestZone
Leaf|Part|1|20.82,7.35,28.93|6173.99,127.28,-265.25|Build/EnchantedForestZone
Wedge|WedgePart|1|4.15,4.15,4.9|6187.62,97.65,-260.27|Build/EnchantedForestZone
Color1|WedgePart|1|4.33,6.78,3.58|6188.41,98.97,-263.23|Build/EnchantedForestZone
Color1|Part|1|3.39,9.23,3.77|6186.35,104.53,-262.05|Build/EnchantedForestZone
Color2|Part|1|2.45,17.53,2.45|6188.93,113.31,-265.15|Build/EnchantedForestZone
Color1|WedgePart|1|4.33,5.28,4.9|6184.25,98.21,-260.83|Build/EnchantedForestZone
Leaf|Part|1|21.01,8.48,28.36|6177.04,126.07,-259.57|Build/EnchantedForestZone
Leaf|Part|1|19.6,14.32,18.84|6194.14,125.98,-271.43|Build/EnchantedForestZone
Color1|Part|1|4.15,4.71,4.33|6186.54,97.93,-262.15|Build/EnchantedForestZone
Color1|WedgePart|1|3.96,9.61,4.9|6185.09,100.38,-264.47|Build/EnchantedForestZone
Color2|Part|1|2.71,23.94,2.71|6461.62,136.6,-460.68|Build/EnchantedForestZone
Color1|Part|1|4.97,8.13,5.42|6455.59,111.83,-458.97|Build/EnchantedForestZone
Color1|WedgePart|1|5.65,3.61,4.52|6452.59,104.38,-457.28|Build/EnchantedForestZone
Leaf|Part|1|18.52,7.91,28.46|6455.46,143.18,-445.48|Build/EnchantedForestZone
Leaf|Part|1|23.49,9.94,24.39|6446.9,147.86,-474.88|Build/EnchantedForestZone
Color1|WedgePart|1|4.97,5.65,4.52|6457.29,105.4,-456.32|Build/EnchantedForestZone
Color1|Part|1|5.87,5.65,6.1|6455.52,105.4,-459.22|Build/EnchantedForestZone
Color1|Part|1|3.61,8.13,4.52|6455.14,124.48,-459.05|Build/EnchantedForestZone
Color2|Part|1|2.94,16.04,2.71|6454.64,132.52,-454.78|Build/EnchantedForestZone
Leaf|Part|1|22.13,7.91,25.75|6450.69,142.56,-450.38|Build/EnchantedForestZone
Color1|Part|1|4.52,5.87,5.42|6455.14,117.93,-459.05|Build/EnchantedForestZone
Leaf|Part|1|24.39,7.23,25.3|6445.49,148.78,-465.35|Build/EnchantedForestZone
Leaf|Part|1|24.39,12.65,20.78|6467.1,147.38,-456|Build/EnchantedForestZone
Wedge|WedgePart|1|4.97,5.65,4.52|6458.24,105.4,-461.42|Build/EnchantedForestZone
Leaf|Part|1|26.2,13.55,13.55|6467.03,147.55,-463.18|Build/EnchantedForestZone
Color1|WedgePart|1|5.87,5.42,5.42|6453.29,105.28,-462.35|Build/EnchantedForestZone
Color2|Part|1|2.94,23.26,2.94|6451.17,135.42,-463.22|Build/EnchantedForestZone
Color1|WedgePart|1|3.27,7.94,4.05|6407.57,106.54,-445.22|Build/EnchantedForestZone
Color2|Part|1|2.49,14.79,2.34|6410.16,117.52,-442.48|Build/EnchantedForestZone
Color2|Part|1|2.49,14.64,2.49|6413.46,117.96,-448.14|Build/EnchantedForestZone
Color1|Part|1|2.8,7.63,3.11|6409.51,109.97,-446.35|Build/EnchantedForestZone
Color2|Part|1|2.02,14.48,2.02|6406.85,117.23,-448.36|Build/EnchantedForestZone
Color1|Part|1|3.43,3.89,3.58|6409.43,104.52,-446.5|Build/EnchantedForestZone
Leaf|Part|1|18.06,10.74,20.24|6413.74,129.86,-447.62|Build/EnchantedForestZone
Wedge|WedgePart|1|3.43,3.43,4.05|6410.94,104.29,-447.46|Build/EnchantedForestZone
Leaf|Part|1|17.21,6.07,23.9|6407.35,128.77,-436.02|Build/EnchantedForestZone
Leaf|Part|1|23.36,7.16,21.8|6401.47,127.95,-451.68|Build/EnchantedForestZone
Leaf|Part|1|17.75,6.38,26.7|6405.88,126.12,-437.88|Build/EnchantedForestZone
Leaf|Part|1|16.19,11.83,15.57|6401.47,127.7,-452.42|Build/EnchantedForestZone
Leaf|Part|1|17.36,7.01,23.43|6411.92,127.77,-438.76|Build/EnchantedForestZone
Color1|WedgePart|1|3.58,5.61,2.96|6408.46,105.38,-448.01|Build/EnchantedForestZone
Color1|WedgePart|1|3.58,4.36,4.05|6410.6,104.75,-444.66|Build/EnchantedForestZone
Leaf|Part|1|20.55,7.16,21.8|6420.44,128,-453.06|Build/EnchantedForestZone
Color2|Part|1|2.34,16.73,2.34|6551.44,197.51,-233.28|Build/EnchantedForestZone
Leaf|Part|1|26.99,8.28,25.19|6547.6,209.89,-227.07|Build/EnchantedForestZone
Leaf|Part|1|20.51,7.38,30.86|6563.55,207.78,-232.17|Build/EnchantedForestZone
Leaf|Part|1|23.75,8.28,25.19|6546.01,209.95,-248.98|Build/EnchantedForestZone
Color2|Part|1|2.88,17.09,2.7|6558.24,197.85,-237.1|Build/EnchantedForestZone
Color2|Part|1|2.88,16.91,2.88|6551.69,198.36,-240.92|Build/EnchantedForestZone
Color1|Part|1|3.24,8.82,3.6|6553.77,189.12,-236.36|Build/EnchantedForestZone
Leaf|Part|1|20.06,8.1,27.08|6562.53,209.69,-239.14|Build/EnchantedForestZone
Color1|WedgePart|1|4.14,5.04,4.68|6555.71,183.09,-237.62|Build/EnchantedForestZone
Leaf|Part|1|18.71,13.67,17.99|6546.75,209.61,-227.06|Build/EnchantedForestZone
Color1|WedgePart|1|3.78,9.18,4.68|6555.07,185.16,-234.11|Build/EnchantedForestZone
Color1|Part|1|3.96,4.5,4.14|6553.59,182.83,-236.26|Build/EnchantedForestZone
Color1|WedgePart|1|4.14,6.48,3.42|6551.85,183.81,-235.14|Build/EnchantedForestZone
Wedge|WedgePart|1|3.96,3.96,4.68|6552.48,182.56,-238|Build/EnchantedForestZone
Leaf|Part|1|19.88,7.02,27.62|6565.69,210.84,-233.86|Build/EnchantedForestZone
Leaf|Part|1|20.87,12.42,23.39|6552.29,212.11,-241.24|Build/EnchantedForestZone
Color2|Part|1|3.84,22.82,3.6|6327.4,131.63,-258.83|Build/EnchantedForestZone
Color2|Part|1|3.84,22.58,3.84|6321,132.31,-266.66|Build/EnchantedForestZone
Leaf|Part|1|31.71,11.05,33.63|6317.64,147.79,-279.39|Build/EnchantedForestZone
Color1|Part|1|5.28,6.01,5.53|6321.2,111.58,-259.94|Build/EnchantedForestZone
Leaf|Part|1|24.98,18.26,24.02|6308.35,147.33,-251.63|Build/EnchantedForestZone
Color1|WedgePart|1|5.04,12.25,6.25|6322.05,114.7,-256.56|Build/EnchantedForestZone
Wedge|WedgePart|1|5.28,5.28,6.25|6320.61,111.22,-262.64|Build/EnchantedForestZone
Color2|Part|1|3.12,22.34,3.12|6317.12,131.18,-257.22|Build/EnchantedForestZone
Leaf|Part|1|26.54,9.37,36.87|6335.22,148.98,-251.3|Build/EnchantedForestZone
Leaf|Part|1|36.03,11.05,33.63|6309.42,147.72,-251.23|Build/EnchantedForestZone
Color1|WedgePart|1|5.53,8.65,4.56|6318.5,112.9,-259.36|Build/EnchantedForestZone
Color1|WedgePart|1|5.53,6.73,6.25|6324.48,111.94,-260.65|Build/EnchantedForestZone
Color1|Part|1|4.32,11.77,4.8|6321.46,119.98,-259.98|Build/EnchantedForestZone
Leaf|Part|1|26.78,10.81,36.15|6333.72,147.44,-259.38|Build/EnchantedForestZone
Leaf|Part|1|27.39,9.85,41.2|6331.74,144.9,-250.17|Build/EnchantedForestZone
Leaf|Part|1|27.87,16.58,31.23|6321.89,150.67,-266.78|Build/EnchantedForestZone
Wood|Part|1|2.73,4.79,3.76|6146.03,116.44,-454.09|Build/EnchantedForestZone
Leaves|Part|1|15.62,5.73,12.67|6141.85,135.77,-454.17|Build/EnchantedForestZone
Leaves|Part|1|15.62,5.34,13.25|6153.04,135.61,-456.67|Build/EnchantedForestZone
Leaves|Part|1|11.29,5.21,10.11|6148.37,134.62,-460.58|Build/EnchantedForestZone
Leaves|Part|1|12.26,5.57,12.94|6154.7,135.5,-446.45|Build/EnchantedForestZone
Leaves|Part|1|13.58,4.43,10.66|6149.47,138.49,-455.29|Build/EnchantedForestZone
Leaves|Part|1|12.73,6.65,11.14|6150.77,139.29,-450.5|Build/EnchantedForestZone
Wood|Part|1|3.24,2.01,1.69|6149.14,125.79,-451.35|Build/EnchantedForestZone
Wood|Part|1|13.84,1.66,1.34|6146.97,128.86,-456.74|Build/EnchantedForestZone
Leaves|Part|1|13.2,5.84,12.6|6148.1,134.26,-451.43|Build/EnchantedForestZone
Wood|Part|1|2.85,5.11,3.29|6148.87,116.93,-452.71|Build/EnchantedForestZone
Wood|Part|1|6.4,1.66,1.34|6148.23,129.36,-448.94|Build/EnchantedForestZone
Wood|Part|1|2.54,4.39,2.74|6149.16,121.06,-452.83|Build/EnchantedForestZone
Wood|Part|1|1.97,2.99,2.33|6148.57,120.45,-452.66|Build/EnchantedForestZone
Wood|Part|1|2.73,4.79,2.6|6151.19,116.44,-451.66|Build/EnchantedForestZone
Wood|Part|1|2.07,3.13,5.43|6147.37,115.61,-449.5|Build/EnchantedForestZone
Leaves|Part|1|15.03,6.26,13.62|6146.67,136.68,-447.16|Build/EnchantedForestZone
Wood|Part|1|2.73,4.79,2.6|6149.96,116.44,-455.07|Build/EnchantedForestZone
Wood|Part|1|14.42,1.63,1.31|6153.11,128.16,-451.36|Build/EnchantedForestZone
Wood|Part|1|1.87,9.73,2.06|6150.37,127.77,-453.25|Build/EnchantedForestZone
Leaves|Part|1|21.41,20.29,9.19|6737.33,138.68,-262.45|Build/EnchantedForestZone
Leaves|Part|1|11.87,14.26,5.81|6737.34,125.73,-262.43|Build/EnchantedForestZone
Wood|Part|1|4.35,7.34,3.73|6734.95,113.26,-258.72|Build/EnchantedForestZone
Wood|Part|1|4.35,7.34,6.12|6740.39,113.25,-267.08|Build/EnchantedForestZone
Wood|Part|1|5.05,5.05,10.4|6737.35,114.78,-262.41|Build/EnchantedForestZone
Leaves|Part|1|25.89,24.77,8.63|6737.33,130.95,-262.44|Build/EnchantedForestZone
Leaves|Part|1|16.92,15.81,11.25|6737.32,146,-262.46|Build/EnchantedForestZone
Leaves|Part|1|6.84,6.85,8.18|6737.31,161.25,-262.49|Build/EnchantedForestZone
Wood|Part|1|4.35,5.23,6.08|6742.59,112.21,-260.26|Build/EnchantedForestZone
Wood|Part|1|4.6,4.61,41.55|6737.33,130.36,-262.44|Build/EnchantedForestZone
Wood|Part|1|4.35,7.34,3.73|6733.67,113.25,-264.79|Build/EnchantedForestZone
Leaves|Part|1|11.32,10.62,8.89|6737.24,154.44,-262.32|Build/EnchantedForestZone
Wood|Part|1|6.53,9.93,7.73|6283.42,155.67,-515.08|Build/EnchantedForestZone
Wood|Part|1|6.88,10.41,18.05|6277.72,139.59,-524.75|Build/EnchantedForestZone
Wood|Part|1|9.06,15.92,8.63|6275.38,142.34,-510.34|Build/EnchantedForestZone
Wood|Part|1|21.25,5.51,4.45|6274.48,185.28,-523.68|Build/EnchantedForestZone
Leaves|Part|1|40.73,18.51,42.98|6254.58,205.65,-512.09|Build/EnchantedForestZone
Wood|Part|1|10.76,6.68,5.63|6278.84,173.4,-516.3|Build/EnchantedForestZone
Leaves|Part|1|45.12,14.72,35.43|6288.36,215.6,-507.26|Build/EnchantedForestZone
Leaves|Part|1|43.87,19.41,41.85|6281.21,201.55,-518.83|Build/EnchantedForestZone
Wood|Part|1|45.97,5.51,4.45|6297.32,183.61,-510.72|Build/EnchantedForestZone
Leaves|Part|1|37.49,17.32,33.6|6304.35,202.73,-499.11|Build/EnchantedForestZone
Leaves|Part|1|51.88,19.02,42.1|6301.3,206.55,-529.34|Build/EnchantedForestZone
Leaves|Part|1|51.88,17.74,44.02|6284.53,206.02,-495.15|Build/EnchantedForestZone
Leaves|Part|1|42.3,22.09,37|6273.26,218.25,-513.86|Build/EnchantedForestZone
Wood|Part|1|9.48,16.99,10.93|6282.91,143.98,-514.18|Build/EnchantedForestZone
Wood|Part|1|6.2,32.32,6.85|6281.22,180,-509.17|Build/EnchantedForestZone
Wood|Part|1|47.92,5.4,4.34|6270.63,181.29,-505.99|Build/EnchantedForestZone
Wood|Part|1|8.45,14.6,9.1|6282.65,157.71,-513.18|Build/EnchantedForestZone
Wood|Part|1|9.06,15.92,12.48|6292.42,142.34,-518.68|Build/EnchantedForestZone
Wood|Part|1|9.06,15.92,8.63|6286.78,142.34,-506.47|Build/EnchantedForestZone
Leaves|Part|1|49.93,20.81,45.26|6273.12,209.58,-531.41|Build/EnchantedForestZone
Wood|Part|1|5.47,9.62,5.22|6477.75,189.39,-258.18|Build/EnchantedForestZone
Leaves|Part|1|24.61,11.19,25.97|6479.62,227.66,-270.66|Build/EnchantedForestZone
Leaves|Part|1|27.27,8.89,21.41|6475.38,233.67,-250.48|Build/EnchantedForestZone
Wood|Part|1|12.84,3.33,2.69|6485.83,215.35,-258.2|Build/EnchantedForestZone
Wood|Part|1|5.73,10.27,6.6|6479.77,190.38,-253.49|Build/EnchantedForestZone
Leaves|Part|1|26.51,11.73,25.29|6482.64,225.18,-254.33|Build/EnchantedForestZone
Wood|Part|1|27.78,3.33,2.69|6477.12,214.33,-244.94|Build/EnchantedForestZone
Leaves|Part|1|31.35,10.72,26.6|6468.23,227.88,-253.26|Build/EnchantedForestZone
Leaves|Part|1|22.66,10.47,20.3|6469.84,225.89,-241.15|Build/EnchantedForestZone
Leaves|Part|1|31.35,11.49,25.44|6488.19,228.2,-241.8|Build/EnchantedForestZone
Leaves|Part|1|25.56,13.35,22.36|6479.96,235.27,-259.33|Build/EnchantedForestZone
Wood|Part|1|3.95,6,4.67|6480.29,197.45,-253.15|Build/EnchantedForestZone
Wood|Part|1|28.96,3.26,2.63|6475.31,212.93,-261.22|Build/EnchantedForestZone
Wood|Part|1|6.5,4.04,3.4|6481.21,208.17,-255.86|Build/EnchantedForestZone
Wood|Part|1|5.11,8.82,5.5|6479.17,198.68,-253.69|Build/EnchantedForestZone
Wood|Part|1|5.47,9.62,5.22|6474.96,189.39,-251.46|Build/EnchantedForestZone
Wood|Part|1|4.16,6.29,10.91|6486.35,187.73,-256.21|Build/EnchantedForestZone
Leaves|Part|1|30.17,12.58,27.35|6490.54,230.03,-258.72|Build/EnchantedForestZone
Wood|Part|1|3.75,19.53,4.14|6476.82,212.15,-254.71|Build/EnchantedForestZone
Wood|Part|1|5.47,9.62,7.54|6482.11,189.4,-247.58|Build/EnchantedForestZone
Color1|WedgePart|1|3.27,7.94,4.05|6651.48,106.54,-282.39|Build/EnchantedForestZone
Leaf|Part|1|16.19,11.83,15.57|6657.58,127.7,-275.19|Build/EnchantedForestZone
Color1|WedgePart|1|3.58,5.61,2.96|6650.59,105.38,-279.6|Build/EnchantedForestZone
Color1|Part|1|3.43,3.89,3.58|6649.62,104.52,-281.11|Build/EnchantedForestZone
Leaf|Part|1|18.06,10.74,20.24|6645.31,129.86,-279.99|Build/EnchantedForestZone
Leaf|Part|1|17.21,6.07,23.9|6651.7,128.77,-291.59|Build/EnchantedForestZone
Wedge|WedgePart|1|3.43,3.43,4.05|6648.11,104.29,-280.15|Build/EnchantedForestZone
Leaf|Part|1|20.55,7.16,21.8|6638.61,128,-274.55|Build/EnchantedForestZone
Color2|Part|1|2.49,14.79,2.34|6648.89,117.52,-285.13|Build/EnchantedForestZone
Color2|Part|1|2.49,14.64,2.49|6645.59,117.96,-279.47|Build/EnchantedForestZone
Color1|WedgePart|1|3.58,4.36,4.05|6648.45,104.75,-282.95|Build/EnchantedForestZone
Leaf|Part|1|17.36,7.01,23.43|6647.13,127.77,-288.85|Build/EnchantedForestZone
Color1|Part|1|2.8,7.63,3.11|6649.54,109.97,-281.26|Build/EnchantedForestZone
Leaf|Part|1|17.75,6.38,26.7|6653.17,126.12,-289.73|Build/EnchantedForestZone
Leaf|Part|1|23.36,7.16,21.8|6657.58,127.95,-275.93|Build/EnchantedForestZone
Color2|Part|1|2.02,14.48,2.02|6652.2,117.23,-279.25|Build/EnchantedForestZone
Wood|Part|1|2.21,2.22,4.56|6597.85,90.11,-290.93|Build/EnchantedForestZone
Wood|Part|1|2.02,2.02,18.21|6597.84,96.94,-290.94|Build/EnchantedForestZone
Wood|Part|1|1.91,3.22,1.63|6596.08,89.44,-291.68|Build/EnchantedForestZone
Leaves|Part|1|9.38,8.89,4.03|6597.84,100.58,-290.94|Build/EnchantedForestZone
Wood|Part|1|1.91,2.29,2.66|6600.28,88.98,-290.39|Build/EnchantedForestZone
Leaves|Part|1|4.96,4.66,3.9|6597.81,107.49,-290.88|Build/EnchantedForestZone
Leaves|Part|1|7.42,6.93,4.93|6597.84,103.79,-290.95|Build/EnchantedForestZone
Leaves|Part|1|11.35,10.86,3.78|6597.84,97.2,-290.94|Build/EnchantedForestZone
Leaves|Part|1|3,3,3.59|6597.83,110.48,-290.96|Build/EnchantedForestZone
Wood|Part|1|1.91,3.22,2.68|6598.82,89.44,-293.17|Build/EnchantedForestZone
Leaves|Part|1|5.2,6.25,2.55|6597.84,94.91,-290.93|Build/EnchantedForestZone
Wood|Part|1|1.91,3.22,1.63|6597.09,89.44,-289.15|Build/EnchantedForestZone
Wood|Part|1|5.52,9.71,5.27|6180.36,119.44,-454.82|Build/EnchantedForestZone
Wood|Part|1|3.99,6.06,4.72|6185.26,127.57,-457.71|Build/EnchantedForestZone
Wood|Part|1|12.97,3.36,2.71|6179.81,145.64,-462.96|Build/EnchantedForestZone
Wood|Part|1|5.78,10.37,6.67|6184.95,120.43,-457.16|Build/EnchantedForestZone
Leaves|Part|1|27.53,8.98,21.62|6188.27,164.14,-452.94|Build/EnchantedForestZone
Leaves|Part|1|31.65,10.82,26.86|6185.94,158.29,-445.55|Build/EnchantedForestZone
Leaves|Part|1|22.88,10.57,20.5|6198.03,156.28,-447.97|Build/EnchantedForestZone
Leaves|Part|1|24.85,11.29,26.22|6167.66,158.07,-455.89|Build/EnchantedForestZone
Wood|Part|1|3.78,19.72,4.18|6183.92,142.41,-454.11|Build/EnchantedForestZone
Wood|Part|1|5.16,8.91,5.55|6184.79,128.81,-456.55|Build/EnchantedForestZone
Leaves|Part|1|25.81,13.48,22.57|6179.06,165.75,-456.97|Build/EnchantedForestZone
Leaves|Part|1|31.65,11.6,25.69|6196.17,158.61,-466.42|Build/EnchantedForestZone
Leaves|Part|1|26.77,11.84,25.54|6183.91,155.56,-460|Build/EnchantedForestZone
Wood|Part|1|4.2,6.35,11.01|6181.78,117.76,-463.62|Build/EnchantedForestZone
Wood|Part|1|29.24,3.3,2.65|6177.46,143.2,-452.17|Build/EnchantedForestZone
Wood|Part|1|5.52,9.71,7.61|6190.75,119.44,-459.91|Build/EnchantedForestZone
Wood|Part|1|5.52,9.71,5.27|6187.31,119.44,-452.46|Build/EnchantedForestZone
Leaves|Part|1|30.46,12.7,27.61|6178.98,160.46,-467.68|Build/EnchantedForestZone
Wood|Part|1|28.05,3.36,2.71|6193.74,144.62,-455.06|Build/EnchantedForestZone
Wood|Part|1|6.56,4.08,3.43|6182.47,138.39,-458.46|Build/EnchantedForestZone
Leaf|Part|1|25.7,13.29,13.29|6920.32,141.7,-465.73|Build/EnchantedForestZone
Color1|Part|1|4.87,7.98,5.32|6925.51,106.66,-454.95|Build/EnchantedForestZone
Color2|Part|1|2.88,15.73,2.66|6929.7,126.95,-454.43|Build/EnchantedForestZone
Color1|Part|1|5.76,5.54,5.98|6925.28,100.34,-454.86|Build/EnchantedForestZone
Leaf|Part|1|23.93,12.41,20.39|6927.33,141.54,-466.48|Build/EnchantedForestZone
Leaf|Part|1|18.17,7.76,27.92|6938.7,137.42,-456.11|Build/EnchantedForestZone
Leaf|Part|1|23.93,7.09,24.82|6920.24,142.91,-444.49|Build/EnchantedForestZone
Leaf|Part|1|23.04,9.75,23.93|6910.81,142.01,-444.97|Build/EnchantedForestZone
Color1|WedgePart|1|5.54,3.55,4.43|6927.45,99.35,-452.19|Build/EnchantedForestZone
Color1|WedgePart|1|4.87,5.54,4.43|6927.94,100.34,-456.87|Build/EnchantedForestZone
Color1|Part|1|3.55,7.98,4.43|6925.48,119.07,-454.51|Build/EnchantedForestZone
Wedge|WedgePart|1|4.87,5.54,4.43|6922.87,100.34,-457.31|Build/EnchantedForestZone
Color1|Part|1|4.43,5.76,5.32|6925.48,112.64,-454.51|Build/EnchantedForestZone
Leaf|Part|1|21.71,7.76,25.26|6934.37,136.8,-450.98|Build/EnchantedForestZone
Color2|Part|1|2.66,23.49,2.66|6923.27,130.95,-460.68|Build/EnchantedForestZone
Color2|Part|1|2.88,22.82,2.88|6921.78,129.8,-450.24|Build/EnchantedForestZone
Color1|WedgePart|1|5.76,5.32,5.32|6922.44,100.23,-452.39|Build/EnchantedForestZone
Color2|Part|1|2.79,24.68,2.79|6847.88,149.65,-443.33|Build/EnchantedForestZone
Color1|Part|1|5.12,8.38,5.59|6845.33,124.12,-449.27|Build/EnchantedForestZone
Leaf|Part|1|24.22,10.25,25.15|6860.43,161.27,-460.27|Build/EnchantedForestZone
Color2|Part|1|3.03,16.53,2.79|6840.91,145.45,-449.67|Build/EnchantedForestZone
Color1|Part|1|4.66,6.05,5.59|6845.34,130.41,-449.73|Build/EnchantedForestZone
Color1|Part|1|3.73,8.38,4.66|6845.34,137.16,-449.73|Build/EnchantedForestZone
Color1|Part|1|6.05,5.82,6.29|6845.56,117.48,-449.37|Build/EnchantedForestZone
Leaf|Part|1|22.82,8.15,26.55|6835.89,155.8,-453.13|Build/EnchantedForestZone
Leaf|Part|1|25.15,13.04,21.42|6843.82,160.77,-437.1|Build/EnchantedForestZone
Leaf|Part|1|27.01,13.97,13.97|6851.16,160.94,-438.12|Build/EnchantedForestZone
Color2|Part|1|3.03,23.99,3.03|6849.08,148.44,-454.34|Build/EnchantedForestZone
Leaf|Part|1|25.15,7.45,26.08|6850.5,162.22,-460.44|Build/EnchantedForestZone
Wedge|WedgePart|1|5.12,5.82,4.66|6848.18,117.48,-446.88|Build/EnchantedForestZone
Color1|WedgePart|1|5.12,5.82,4.66|6842.84,117.48,-447.17|Build/EnchantedForestZone
Leaf|Part|1|19.1,8.15,29.34|6831.51,156.45,-447.6|Build/EnchantedForestZone
Color1|WedgePart|1|5.82,3.73,4.66|6843.2,116.44,-452.1|Build/EnchantedForestZone
Color1|WedgePart|1|6.05,5.59,5.59|6848.47,117.37,-452.06|Build/EnchantedForestZone
Leaf|Part|1|24.93,10.55,25.89|6997.98,162.64,-451.13|Build/EnchantedForestZone
Color1|WedgePart|1|5.27,5.99,4.79|6989.48,117.57,-472.03|Build/EnchantedForestZone
Color1|Part|1|5.27,8.63,5.75|6990.92,124.4,-469.01|Build/EnchantedForestZone
Leaf|Part|1|19.66,8.39,30.21|6992.82,157.67,-483.21|Build/EnchantedForestZone
Leaf|Part|1|25.89,7.67,26.85|7000.72,163.62,-460.97|Build/EnchantedForestZone
Leaf|Part|1|25.89,13.42,22.05|6979.18,162.13,-473.65|Build/EnchantedForestZone
Color1|WedgePart|1|5.99,3.84,4.79|6994.3,116.49,-470.4|Build/EnchantedForestZone
Color2|Part|1|3.12,17.02,2.88|6992.46,146.35,-473.3|Build/EnchantedForestZone
Color1|Part|1|6.23,5.99,6.47|6990.97,117.57,-468.75|Build/EnchantedForestZone
Color1|WedgePart|1|6.23,5.75,5.75|6992.9,117.45,-465.16|Build/EnchantedForestZone
Color1|Part|1|4.79,6.23,5.75|6991.38,130.87,-468.87|Build/EnchantedForestZone
Leaf|Part|1|23.49,8.39,27.33|6997.2,157.01,-477.42|Build/EnchantedForestZone
Wedge|WedgePart|1|5.27,5.99,4.79|6987.81,117.57,-466.78|Build/EnchantedForestZone
Leaf|Part|1|27.81,14.38,14.38|6978.31,162.3,-466.08|Build/EnchantedForestZone
Color1|Part|1|3.84,8.63,4.79|6991.38,137.82,-468.87|Build/EnchantedForestZone
Color2|Part|1|3.12,24.69,3.12|6995.01,149.44,-463.96|Build/EnchantedForestZone
Color2|Part|1|2.88,25.41,2.88|6984.34,150.68,-468|Build/EnchantedForestZone
Wood|Part|1|3.37,5.68,4.74|6464.86,117.42,-507.68|Build/EnchantedForestZone
Wood|Part|1|3.37,5.68,2.89|6470.36,117.42,-507.69|Build/EnchantedForestZone
Leaves|Part|1|13.1,12.24,8.71|6468.26,142.78,-510.3|Build/EnchantedForestZone
Leaves|Part|1|9.19,11.04,4.5|6468.26,127.09,-510.33|Build/EnchantedForestZone
Wood|Part|1|3.56,3.57,32.17|6468.26,130.67,-510.33|Build/EnchantedForestZone
Wood|Part|1|3.37,5.68,2.89|6470.93,117.43,-512.46|Build/EnchantedForestZone
Leaves|Part|1|20.04,19.18,6.68|6468.26,131.13,-510.32|Build/EnchantedForestZone
Leaves|Part|1|5.3,5.3,6.34|6468.26,154.59,-510.28|Build/EnchantedForestZone
Wood|Part|1|3.37,4.05,4.71|6464.94,116.62,-513.22|Build/EnchantedForestZone
Wood|Part|1|3.91,3.91,8.05|6468.25,118.61,-510.35|Build/EnchantedForestZone
Leaves|Part|1|8.77,8.22,6.88|6468.35,149.32,-510.38|Build/EnchantedForestZone
Leaves|Part|1|16.57,15.71,7.11|6468.26,137.12,-510.31|Build/EnchantedForestZone
Leaves|Part|1|43.66,19.31,41.65|7046.4,176.28,-308.11|Build/EnchantedForestZone
Wood|Part|1|21.15,5.48,4.43|7039.3,160.09,-303.89|Build/EnchantedForestZone
Wood|Part|1|45.75,5.48,4.43|7060.17,158.43,-319.62|Build/EnchantedForestZone
Leaves|Part|1|44.9,14.65,35.26|7059.79,190.26,-310.06|Build/EnchantedForestZone
Wood|Part|1|9.43,16.91,10.88|7051.32,118.98,-307.83|Build/EnchantedForestZone
Leaves|Part|1|42.1,21.98,36.82|7047.78,192.9,-298.88|Build/EnchantedForestZone
Leaves|Part|1|37.32,17.24,33.44|7073.55,177.46,-321.45|Build/EnchantedForestZone
Leaves|Part|1|40.53,18.42,42.77|7042.01,180.36,-281.13|Build/EnchantedForestZone
Leaves|Part|1|51.63,17.65,43.81|7069.33,180.73,-301.78|Build/EnchantedForestZone
Leaves|Part|1|51.63,18.93,41.9|7044.74,181.25,-330.62|Build/EnchantedForestZone
Wood|Part|1|6.5,9.88,7.69|7050.69,130.62,-308.65|Build/EnchantedForestZone
Wood|Part|1|6.17,32.16,6.82|7055.21,154.83,-304.3|Build/EnchantedForestZone
Wood|Part|1|47.69,5.38,4.32|7053.93,156.12,-293.37|Build/EnchantedForestZone
Wood|Part|1|8.41,14.53,9.06|7052.13,132.65,-307.2|Build/EnchantedForestZone
Wood|Part|1|6.84,10.36,17.96|7039.61,114.61,-307.27|Build/EnchantedForestZone
Wood|Part|1|9.01,15.84,8.59|7051.84,117.35,-299.43|Build/EnchantedForestZone
Wood|Part|1|9.01,15.84,8.59|7059.88,117.35,-308.31|Build/EnchantedForestZone
Leaves|Part|1|49.69,20.71,45.04|7031.71,184.28,-305.7|Build/EnchantedForestZone
Wood|Part|1|9.01,15.84,12.42|7050.97,117.36,-318.29|Build/EnchantedForestZone
Wood|Part|1|10.71,6.65,5.6|7047.76,148.27,-304.95|Build/EnchantedForestZone
Leaves|Part|1|31.35,11.49,25.44|6570.86,228.2,-485.81|Build/EnchantedForestZone
Leaves|Part|1|22.66,10.47,20.3|6589.21,225.89,-486.46|Build/EnchantedForestZone
Leaves|Part|1|31.35,10.72,26.6|6590.82,227.88,-474.35|Build/EnchantedForestZone
Wood|Part|1|3.95,6,4.67|6578.76,197.45,-474.46|Build/EnchantedForestZone
Wood|Part|1|3.75,19.53,4.14|6582.23,212.15,-472.9|Build/EnchantedForestZone
Wood|Part|1|28.96,3.26,2.63|6583.74,212.93,-466.39|Build/EnchantedForestZone
Wood|Part|1|4.16,6.29,10.91|6572.7,187.73,-471.4|Build/EnchantedForestZone
Leaves|Part|1|27.27,8.89,21.41|6583.67,233.67,-477.13|Build/EnchantedForestZone
Wood|Part|1|12.84,3.33,2.69|6573.22,215.35,-469.41|Build/EnchantedForestZone
Wood|Part|1|6.5,4.04,3.4|6577.84,208.17,-471.75|Build/EnchantedForestZone
Wood|Part|1|5.47,9.62,5.22|6581.3,189.39,-469.43|Build/EnchantedForestZone
Leaves|Part|1|30.17,12.58,27.35|6568.51,230.03,-468.89|Build/EnchantedForestZone
Wood|Part|1|5.47,9.62,5.22|6584.08,189.39,-476.15|Build/EnchantedForestZone
Wood|Part|1|5.47,9.62,7.54|6576.94,189.4,-480.03|Build/EnchantedForestZone
Leaves|Part|1|25.56,13.35,22.36|6579.09,235.27,-468.28|Build/EnchantedForestZone
Leaves|Part|1|26.51,11.73,25.29|6576.41,225.18,-473.28|Build/EnchantedForestZone
Leaves|Part|1|24.61,11.19,25.97|6579.43,227.66,-456.95|Build/EnchantedForestZone
Wood|Part|1|5.73,10.27,6.6|6579.28,190.38,-474.12|Build/EnchantedForestZone
Wood|Part|1|27.78,3.33,2.69|6581.93,214.33,-482.67|Build/EnchantedForestZone
Wood|Part|1|5.11,8.82,5.5|6579.88,198.68,-473.93|Build/EnchantedForestZone
Wood|Part|1|45.97,5.51,4.45|6761.72,183.61,-216.89|Build/EnchantedForestZone
Leaves|Part|1|43.87,19.41,41.85|6777.84,201.55,-208.78|Build/EnchantedForestZone
Leaves|Part|1|51.88,19.02,42.1|6757.74,206.55,-198.27|Build/EnchantedForestZone
Wood|Part|1|10.76,6.68,5.63|6780.21,173.4,-211.31|Build/EnchantedForestZone
Wood|Part|1|6.88,10.41,18.05|6781.33,139.59,-202.86|Build/EnchantedForestZone
Wood|Part|1|9.06,15.92,12.48|6766.63,142.34,-208.93|Build/EnchantedForestZone
Leaves|Part|1|42.3,22.09,37|6785.79,218.25,-213.75|Build/EnchantedForestZone
Wood|Part|1|8.45,14.6,9.1|6776.39,157.71,-214.43|Build/EnchantedForestZone
Wood|Part|1|9.06,15.92,8.63|6772.27,142.34,-221.14|Build/EnchantedForestZone
Leaves|Part|1|40.73,18.51,42.98|6804.47,205.65,-215.52|Build/EnchantedForestZone
Wood|Part|1|6.53,9.93,7.73|6775.63,155.67,-212.53|Build/EnchantedForestZone
Leaves|Part|1|45.12,14.72,35.43|6770.69,215.6,-220.35|Build/EnchantedForestZone
Leaves|Part|1|37.49,17.32,33.6|6754.7,202.73,-228.5|Build/EnchantedForestZone
Wood|Part|1|9.06,15.92,8.63|6783.67,142.34,-217.27|Build/EnchantedForestZone
Leaves|Part|1|51.88,17.74,44.02|6774.52,206.02,-232.46|Build/EnchantedForestZone
Wood|Part|1|21.25,5.51,4.45|6784.57,185.28,-203.93|Build/EnchantedForestZone
Leaves|Part|1|49.93,20.81,45.26|6785.93,209.58,-196.2|Build/EnchantedForestZone
Wood|Part|1|6.2,32.32,6.85|6777.83,180,-218.44|Build/EnchantedForestZone
Wood|Part|1|9.48,16.99,10.93|6776.14,143.98,-213.44|Build/EnchantedForestZone
Wood|Part|1|47.92,5.4,4.34|6788.42,181.29,-221.62|Build/EnchantedForestZone
Color1|Part|1|3.24,8.82,3.6|6505.28,189.12,-491.25|Build/EnchantedForestZone
Color1|WedgePart|1|4.14,6.48,3.42|6507.2,183.81,-492.47|Build/EnchantedForestZone
Color1|Part|1|3.96,4.5,4.14|6505.46,182.83,-491.35|Build/EnchantedForestZone
Color1|WedgePart|1|3.78,9.18,4.68|6503.98,185.16,-493.5|Build/EnchantedForestZone
Leaf|Part|1|18.71,13.67,17.99|6512.3,209.61,-500.55|Build/EnchantedForestZone
Leaf|Part|1|19.88,7.02,27.62|6493.35,210.84,-493.75|Build/EnchantedForestZone
Leaf|Part|1|26.99,8.28,25.19|6511.45,209.89,-500.54|Build/EnchantedForestZone
Leaf|Part|1|20.51,7.38,30.86|6495.5,207.78,-495.44|Build/EnchantedForestZone
Leaf|Part|1|20.06,8.1,27.08|6496.52,209.69,-488.47|Build/EnchantedForestZone
Color1|WedgePart|1|4.14,5.04,4.68|6503.34,183.09,-489.99|Build/EnchantedForestZone
Color2|Part|1|2.34,16.73,2.34|6507.61,197.51,-494.33|Build/EnchantedForestZone
Wedge|WedgePart|1|3.96,3.96,4.68|6506.57,182.56,-489.61|Build/EnchantedForestZone
Color2|Part|1|2.88,17.09,2.7|6500.81,197.85,-490.51|Build/EnchantedForestZone
Leaf|Part|1|20.87,12.42,23.39|6506.76,212.11,-486.37|Build/EnchantedForestZone
Color2|Part|1|2.88,16.91,2.88|6507.35,198.36,-486.69|Build/EnchantedForestZone
Leaf|Part|1|23.75,8.28,25.19|6513.04,209.95,-478.63|Build/EnchantedForestZone
Color1|WedgePart|1|9.03,5.78,7.22|7048.91,151.32,-410.33|Build/EnchantedForestZone
Leaf|Part|1|37.55,15.88,38.99|7075.62,220.82,-422.99|Build/EnchantedForestZone
Color1|Part|1|9.39,9.03,9.75|7052.58,152.94,-406.1|Build/EnchantedForestZone
Leaf|Part|1|41.88,21.66,21.66|7061.24,220.32,-388.66|Build/EnchantedForestZone
Color2|Part|1|4.69,25.63,4.33|7045.36,196.3,-406.56|Build/EnchantedForestZone
Color1|Part|1|5.78,13,7.22|7052.23,183.45,-406.66|Build/EnchantedForestZone
Leaf|Part|1|35.38,12.64,41.16|7037.57,212.35,-411.93|Build/EnchantedForestZone
Wedge|WedgePart|1|7.94,9.03,7.22|7056.63,152.94,-402.24|Build/EnchantedForestZone
Leaf|Part|1|38.99,11.55,40.43|7060.23,222.29,-423.25|Build/EnchantedForestZone
Color1|WedgePart|1|9.39,8.66,8.66|7057.08,152.76,-410.27|Build/EnchantedForestZone
Color2|Part|1|4.33,38.27,4.33|7056.16,202.82,-396.73|Build/EnchantedForestZone
Leaf|Part|1|38.99,20.22,33.21|7049.87,220.06,-387.08|Build/EnchantedForestZone
Color1|WedgePart|1|7.94,9.03,7.22|7048.35,152.94,-402.69|Build/EnchantedForestZone
Color1|Part|1|7.94,13,8.66|7052.2,163.23,-405.93|Build/EnchantedForestZone
Leaf|Part|1|29.6,12.64,45.49|7030.79,213.34,-403.35|Build/EnchantedForestZone
Color2|Part|1|4.69,37.18,4.69|7058.02,200.94,-413.81|Build/EnchantedForestZone
Color1|Part|1|7.22,9.39,8.66|7052.23,172.98,-406.66|Build/EnchantedForestZone
Color2|Part|1|3.12,22.34,3.12|6741.93,131.18,-470.39|Build/EnchantedForestZone
Leaf|Part|1|26.78,10.81,36.15|6725.33,147.44,-468.23|Build/EnchantedForestZone
Color1|WedgePart|1|5.04,12.25,6.25|6737,114.7,-471.05|Build/EnchantedForestZone
Leaf|Part|1|24.98,18.26,24.02|6750.7,147.33,-475.99|Build/EnchantedForestZone
Leaf|Part|1|26.54,9.37,36.87|6723.83,148.98,-476.31|Build/EnchantedForestZone
Leaf|Part|1|36.03,11.05,33.63|6749.63,147.72,-476.38|Build/EnchantedForestZone
Leaf|Part|1|27.39,9.85,41.2|6727.3,144.9,-477.44|Build/EnchantedForestZone
Wedge|WedgePart|1|5.28,5.28,6.25|6738.43,111.22,-464.97|Build/EnchantedForestZone
Leaf|Part|1|27.87,16.58,31.23|6737.16,150.67,-460.83|Build/EnchantedForestZone
Leaf|Part|1|31.71,11.05,33.63|6741.41,147.79,-448.22|Build/EnchantedForestZone
Color1|WedgePart|1|5.53,6.73,6.25|6734.56,111.94,-466.96|Build/EnchantedForestZone
Color1|Part|1|4.32,11.77,4.8|6737.59,119.98,-467.63|Build/EnchantedForestZone
Color1|WedgePart|1|5.53,8.65,4.56|6740.55,112.9,-468.25|Build/EnchantedForestZone
Color1|Part|1|5.28,6.01,5.53|6737.85,111.58,-467.67|Build/EnchantedForestZone
Color2|Part|1|3.84,22.58,3.84|6738.05,132.31,-460.95|Build/EnchantedForestZone
Color2|Part|1|3.84,22.82,3.6|6731.65,131.63,-468.78|Build/EnchantedForestZone
Wood|Part|1|4.35,7.34,3.73|6325.38,113.25,-455.82|Build/EnchantedForestZone
Wood|Part|1|4.6,4.61,41.55|6321.71,130.36,-458.17|Build/EnchantedForestZone
Wood|Part|1|4.35,7.34,3.73|6324.1,113.26,-461.89|Build/EnchantedForestZone
Wood|Part|1|4.35,7.34,6.12|6318.65,113.25,-453.53|Build/EnchantedForestZone
Wood|Part|1|5.05,5.05,10.4|6321.7,114.78,-458.2|Build/EnchantedForestZone
Leaves|Part|1|11.32,10.62,8.89|6321.81,154.44,-458.29|Build/EnchantedForestZone
Leaves|Part|1|21.41,20.29,9.19|6321.72,138.68,-458.16|Build/EnchantedForestZone
Wood|Part|1|4.35,5.23,6.08|6316.45,112.21,-460.35|Build/EnchantedForestZone
Leaves|Part|1|25.89,24.77,8.63|6321.71,130.95,-458.17|Build/EnchantedForestZone
Leaves|Part|1|16.92,15.81,11.25|6321.73,146,-458.15|Build/EnchantedForestZone
Leaves|Part|1|6.84,6.85,8.18|6321.74,161.25,-458.12|Build/EnchantedForestZone
Leaves|Part|1|11.87,14.26,5.81|6321.71,125.73,-458.18|Build/EnchantedForestZone
Color2|Part|1|3.73,22.15,3.5|6887.02,117.95,-466.53|Build/EnchantedForestZone
Leaf|Part|1|27.04,16.09,30.31|6879.58,136.43,-472.25|Build/EnchantedForestZone
Color1|Part|1|4.2,11.42,4.66|6881.19,106.65,-465.84|Build/EnchantedForestZone
Color2|Part|1|3.03,21.68,3.03|6878,117.52,-462|Build/EnchantedForestZone
Color1|WedgePart|1|5.36,6.53,6.06|6883.79,98.84,-467.35|Build/EnchantedForestZone
Leaf|Part|1|26.58,9.56,39.98|6893.6,130.83,-459.81|Build/EnchantedForestZone
Leaf|Part|1|34.97,10.72,32.64|6872.65,133.56,-454.19|Build/EnchantedForestZone
Color1|Part|1|5.13,5.83,5.36|6880.96,98.49,-465.72|Build/EnchantedForestZone
Leaf|Part|1|25.76,9.09,35.79|6896.48,134.79,-461.88|Build/EnchantedForestZone
Wedge|WedgePart|1|5.13,5.13,6.06|6879.62,98.14,-468.05|Build/EnchantedForestZone
Color1|WedgePart|1|5.36,8.39,4.43|6878.63,99.77,-464.38|Build/EnchantedForestZone
Color2|Part|1|3.73,21.92,3.73|6878.79,118.61,-471.87|Build/EnchantedForestZone
Leaf|Part|1|30.77,10.72,32.64|6871.92,133.64,-482.65|Build/EnchantedForestZone
Leaf|Part|1|26,10.49,35.09|6892.7,133.3,-468.91|Build/EnchantedForestZone
Color1|WedgePart|1|4.9,11.89,6.06|6882.75,101.52,-462.85|Build/EnchantedForestZone
Leaf|Part|1|24.25,17.72,23.31|6871.54,133.2,-454.24|Build/EnchantedForestZone
Leaf|Part|1|24.39,7.23,25.3|6616.56,148.78,-262.26|Build/EnchantedForestZone
Color1|Part|1|4.97,8.13,5.42|6606.46,111.83,-268.64|Build/EnchantedForestZone
Color1|Part|1|5.87,5.65,6.1|6606.53,105.4,-268.39|Build/EnchantedForestZone
Color2|Part|1|2.71,23.94,2.71|6600.43,136.6,-266.93|Build/EnchantedForestZone
Leaf|Part|1|24.39,12.65,20.78|6594.95,147.38,-271.61|Build/EnchantedForestZone
Leaf|Part|1|23.49,9.94,24.39|6615.15,147.86,-252.73|Build/EnchantedForestZone
Color1|WedgePart|1|5.65,3.61,4.52|6609.46,104.38,-270.33|Build/EnchantedForestZone
Color1|WedgePart|1|4.97,5.65,4.52|6604.76,105.4,-271.29|Build/EnchantedForestZone
Leaf|Part|1|26.2,13.55,13.55|6595.01,147.55,-264.43|Build/EnchantedForestZone
Color2|Part|1|2.94,16.04,2.71|6607.4,132.52,-272.83|Build/EnchantedForestZone
Color1|Part|1|3.61,8.13,4.52|6606.91,124.48,-268.56|Build/EnchantedForestZone
Color1|WedgePart|1|5.87,5.42,5.42|6608.75,105.28,-265.26|Build/EnchantedForestZone
Color2|Part|1|2.94,23.26,2.94|6610.87,135.42,-264.39|Build/EnchantedForestZone
Color1|Part|1|4.52,5.87,5.42|6606.91,117.93,-268.56|Build/EnchantedForestZone
Wedge|WedgePart|1|4.97,5.65,4.52|6603.81,105.4,-266.19|Build/EnchantedForestZone
Leaf|Part|1|22.13,7.91,25.75|6611.36,142.56,-277.23|Build/EnchantedForestZone
Leaf|Part|1|18.52,7.91,28.46|6606.59,143.18,-282.13|Build/EnchantedForestZone
Color1|Part|1|4.66,6.05,5.59|6213.71,130.41,-277.88|Build/EnchantedForestZone
Color1|WedgePart|1|6.05,5.59,5.59|6210.58,117.37,-275.55|Build/EnchantedForestZone
Leaf|Part|1|25.15,13.04,21.42|6215.23,160.77,-290.51|Build/EnchantedForestZone
Color2|Part|1|2.79,24.68,2.79|6211.17,149.65,-284.28|Build/EnchantedForestZone
Color1|Part|1|3.73,8.38,4.66|6213.71,137.16,-277.88|Build/EnchantedForestZone
Color2|Part|1|3.03,23.99,3.03|6209.97,148.44,-273.27|Build/EnchantedForestZone
Leaf|Part|1|27.01,13.97,13.97|6207.89,160.94,-289.49|Build/EnchantedForestZone
Color1|Part|1|6.05,5.82,6.29|6213.49,117.48,-278.24|Build/EnchantedForestZone
Color1|WedgePart|1|5.12,5.82,4.66|6216.21,117.48,-280.44|Build/EnchantedForestZone
Color2|Part|1|3.03,16.53,2.79|6218.14,145.45,-277.94|Build/EnchantedForestZone
Color1|WedgePart|1|5.82,3.73,4.66|6215.85,116.44,-275.51|Build/EnchantedForestZone
Leaf|Part|1|24.22,10.25,25.15|6198.62,161.27,-267.34|Build/EnchantedForestZone
Leaf|Part|1|19.1,8.15,29.34|6227.54,156.45,-280.01|Build/EnchantedForestZone
Color1|Part|1|5.12,8.38,5.59|6213.72,124.12,-278.35|Build/EnchantedForestZone
Leaf|Part|1|25.15,7.45,26.08|6208.55,162.22,-267.17|Build/EnchantedForestZone
Leaf|Part|1|22.82,8.15,26.55|6223.16,155.8,-274.48|Build/EnchantedForestZone
Wedge|WedgePart|1|5.12,5.82,4.66|6210.86,117.48,-280.73|Build/EnchantedForestZone
Leaf|Part|1|23.58,8.22,25.01|6380.44,135.74,-278.24|Build/EnchantedForestZone
Color2|Part|1|2.32,16.61,2.32|6379.34,123.39,-261.78|Build/EnchantedForestZone
Color2|Part|1|2.86,16.79,2.86|6382.52,124.23,-268.67|Build/EnchantedForestZone
Leaf|Part|1|20.72,12.33,23.22|6383.19,137.88,-268.73|Build/EnchantedForestZone
Wedge|WedgePart|1|3.93,3.93,4.64|6382.11,108.54,-265.7|Build/EnchantedForestZone
Color1|Part|1|3.22,8.75,3.57|6382.65,115.06,-263.7|Build/EnchantedForestZone
Leaf|Part|1|19.92,8.04,26.88|6391.74,135.48,-262.85|Build/EnchantedForestZone
Color1|WedgePart|1|4.11,5,4.64|6384.92,109.08,-264.09|Build/EnchantedForestZone
Leaf|Part|1|26.79,8.22,25.01|6373.42,135.68,-257.59|Build/EnchantedForestZone
Leaf|Part|1|20.36,7.32,30.64|6389.97,133.59,-256.08|Build/EnchantedForestZone
Leaf|Part|1|19.74,6.97,27.42|6392.59,136.62,-256.8|Build/EnchantedForestZone
Leaf|Part|1|18.58,13.58,17.86|6372.64,135.4,-257.91|Build/EnchantedForestZone
Color1|WedgePart|1|4.11,6.43,3.39|6380.43,109.79,-263.33|Build/EnchantedForestZone
Color2|Part|1|2.86,16.97,2.68|6387.03,123.72,-262.65|Build/EnchantedForestZone
Color1|WedgePart|1|3.75,9.11,4.64|6382.98,111.13,-261.14|Build/EnchantedForestZone
Color1|Part|1|3.93,4.47,4.11|6382.45,108.81,-263.67|Build/EnchantedForestZone
Leaves|Part|1|35.46,11.57,27.85|6444.7,166.52,-271.41|Build/EnchantedForestZone
Leaves|Part|1|29.47,13.61,26.41|6433.83,156.4,-262.42|Build/EnchantedForestZone
Wood|Part|1|8.46,5.25,4.42|6454.2,133.35,-275.45|Build/EnchantedForestZone
Wood|Part|1|4.88,25.4,5.38|6448.31,138.53,-275.97|Build/EnchantedForestZone
Leaves|Part|1|33.25,17.36,29.08|6454.18,168.6,-280.24|Build/EnchantedForestZone
Wood|Part|1|36.13,4.33,3.5|6444.4,141.37,-263.87|Build/EnchantedForestZone
Wood|Part|1|37.67,4.25,3.41|6449.33,139.55,-284.6|Build/EnchantedForestZone
Leaves|Part|1|32.01,14.55,33.78|6458.74,158.7,-294.27|Build/EnchantedForestZone
Leaves|Part|1|40.78,13.94,34.6|6437.16,158.99,-277.96|Build/EnchantedForestZone
Wood|Part|1|16.7,4.33,3.5|6460.88,142.69,-276.29|Build/EnchantedForestZone
Wood|Part|1|7.12,12.51,6.78|6450.98,108.93,-279.81|Build/EnchantedForestZone
Leaves|Part|1|39.25,16.36,35.57|6466.88,161.79,-274.86|Build/EnchantedForestZone
Leaves|Part|1|40.78,14.95,33.09|6456.59,159.4,-255.18|Build/EnchantedForestZone
Wood|Part|1|7.12,12.51,6.78|6444.62,108.93,-272.8|Build/EnchantedForestZone
Leaves|Part|1|34.48,15.25,32.9|6455.28,155.48,-272.95|Build/EnchantedForestZone
Wood|Part|1|6.64,11.47,7.15|6450.75,121.01,-273.68|Build/EnchantedForestZone
Wood|Part|1|7.12,12.51,9.81|6451.67,108.94,-264.92|Build/EnchantedForestZone
Wood|Part|1|7.45,13.36,8.59|6451.39,110.22,-273.18|Build/EnchantedForestZone
Wood|Part|1|5.13,7.81,6.07|6451.88,119.41,-272.53|Build/EnchantedForestZone
Wood|Part|1|5.41,8.18,14.19|6460.64,106.77,-273.62|Build/EnchantedForestZone
Color1|WedgePart|1|3.9,2.5,3.12|6996.91,125.82,-256.64|Build/EnchantedForestZone
Wedge|WedgePart|1|3.43,3.9,3.12|6999.75,126.52,-260.55|Build/EnchantedForestZone
Leaf|Part|1|16.85,4.99,17.48|6990.53,156.5,-260.45|Build/EnchantedForestZone
Leaf|Part|1|12.79,5.46,19.66|7001.28,152.63,-249.47|Build/EnchantedForestZone
Leaf|Part|1|15.29,5.46,17.79|6997.1,152.2,-251.7|Build/EnchantedForestZone
Color1|Part|1|2.5,5.62,3.12|6998.21,139.71,-258.34|Build/EnchantedForestZone
Leaf|Part|1|18.1,9.36,9.36|7005.16,155.64,-263.56|Build/EnchantedForestZone
Color2|Part|1|2.03,16.07,2.03|6994.72,147.27,-260.25|Build/EnchantedForestZone
Color2|Part|1|2.03,11.08,1.87|6998.78,145.26,-255.42|Build/EnchantedForestZone
Leaf|Part|1|16.23,6.87,16.85|6989.46,155.86,-267.02|Build/EnchantedForestZone
Color1|WedgePart|1|3.43,3.9,3.12|7000.2,126.52,-256.99|Build/EnchantedForestZone
Color1|Part|1|4.06,3.9,4.21|6998.42,126.52,-258.53|Build/EnchantedForestZone
Leaf|Part|1|16.85,8.74,14.36|7006.72,155.53,-258.85|Build/EnchantedForestZone
Color2|Part|1|1.87,16.54,1.87|7002.13,148.08,-260.78|Build/EnchantedForestZone
Color1|WedgePart|1|4.06,3.74,3.74|6996.3,126.45,-260.12|Build/EnchantedForestZone
Color1|Part|1|3.43,5.62,3.74|6998.52,130.97,-258.38|Build/EnchantedForestZone
Color1|Part|1|3.12,4.06,3.74|6998.21,135.18,-258.34|Build/EnchantedForestZone
Leaves|Part|1|20.04,19.18,6.68|6590.79,131.13,-217.29|Build/EnchantedForestZone
Leaves|Part|1|13.1,12.24,8.71|6590.79,142.78,-217.31|Build/EnchantedForestZone
Leaves|Part|1|5.3,5.3,6.34|6590.79,154.59,-217.33|Build/EnchantedForestZone
Wood|Part|1|3.91,3.91,8.05|6590.79,118.61,-217.26|Build/EnchantedForestZone
Wood|Part|1|3.37,5.68,2.89|6588.68,117.42,-219.92|Build/EnchantedForestZone
Wood|Part|1|3.56,3.57,32.17|6590.79,130.67,-217.28|Build/EnchantedForestZone
Wood|Part|1|3.37,5.68,2.89|6588.12,117.43,-215.15|Build/EnchantedForestZone
Leaves|Part|1|9.19,11.04,4.5|6590.79,127.09,-217.28|Build/EnchantedForestZone
Wood|Part|1|3.37,5.68,4.74|6594.18,117.42,-219.93|Build/EnchantedForestZone
Wood|Part|1|3.37,4.05,4.71|6594.11,116.62,-214.39|Build/EnchantedForestZone
Leaves|Part|1|8.77,8.22,6.88|6590.7,149.32,-217.23|Build/EnchantedForestZone
Leaves|Part|1|16.57,15.71,7.11|6590.79,137.12,-217.3|Build/EnchantedForestZone
Wood|Part|1|7.12,12.51,9.81|6607.38,108.94,-462.69|Build/EnchantedForestZone
Wood|Part|1|5.41,8.18,14.19|6598.41,106.77,-453.99|Build/EnchantedForestZone
Leaves|Part|1|39.25,16.36,35.57|6592.17,161.79,-452.75|Build/EnchantedForestZone
Wood|Part|1|6.64,11.47,7.15|6608.3,121.01,-453.93|Build/EnchantedForestZone
Wood|Part|1|37.67,4.25,3.41|6609.72,139.55,-443.01|Build/EnchantedForestZone
Wood|Part|1|7.12,12.51,6.78|6614.42,108.93,-454.81|Build/EnchantedForestZone
Wood|Part|1|4.88,25.4,5.38|6610.73,138.53,-451.64|Build/EnchantedForestZone
Leaves|Part|1|34.48,15.25,32.9|6603.77,155.48,-454.66|Build/EnchantedForestZone
Leaves|Part|1|32.01,14.55,33.78|6600.31,158.7,-433.34|Build/EnchantedForestZone
Wood|Part|1|36.13,4.33,3.5|6614.65,141.37,-463.74|Build/EnchantedForestZone
Wood|Part|1|7.12,12.51,6.78|6608.07,108.93,-447.8|Build/EnchantedForestZone
Wood|Part|1|8.46,5.25,4.42|6604.85,133.35,-452.16|Build/EnchantedForestZone
Wood|Part|1|7.45,13.36,8.59|6607.66,110.22,-454.43|Build/EnchantedForestZone
Wood|Part|1|5.13,7.81,6.07|6607.16,119.41,-455.08|Build/EnchantedForestZone
Leaves|Part|1|29.47,13.61,26.41|6625.22,156.4,-465.19|Build/EnchantedForestZone
Leaves|Part|1|35.46,11.57,27.85|6614.35,166.52,-456.2|Build/EnchantedForestZone
Wood|Part|1|16.7,4.33,3.5|6598.17,142.69,-451.32|Build/EnchantedForestZone
Leaves|Part|1|33.25,17.36,29.08|6604.87,168.6,-447.37|Build/EnchantedForestZone
Leaves|Part|1|40.78,13.94,34.6|6621.89,158.99,-449.65|Build/EnchantedForestZone
Leaves|Part|1|40.78,14.95,33.09|6602.46,159.4,-472.43|Build/EnchantedForestZone
Leaf|Part|1|18.17,7.76,27.92|6126.46,156.27,-251.48|Build/EnchantedForestZone
Color1|WedgePart|1|5.76,5.32,5.32|6142.73,119.09,-255.19|Build/EnchantedForestZone
Leaf|Part|1|23.93,12.41,20.39|6137.83,160.39,-241.11|Build/EnchantedForestZone
Color2|Part|1|2.88,22.82,2.88|6143.38,148.66,-257.34|Build/EnchantedForestZone
Color2|Part|1|2.66,23.49,2.66|6141.89,149.81,-246.9|Build/EnchantedForestZone
Color1|Part|1|3.55,7.98,4.43|6139.68,137.92,-253.07|Build/EnchantedForestZone
Color2|Part|1|2.88,15.73,2.66|6135.46,145.81,-253.15|Build/EnchantedForestZone
Leaf|Part|1|25.7,13.29,13.29|6144.84,160.55,-241.85|Build/EnchantedForestZone
Wedge|WedgePart|1|4.87,5.54,4.43|6142.29,119.2,-250.27|Build/EnchantedForestZone
Leaf|Part|1|21.71,7.76,25.26|6130.79,155.66,-256.6|Build/EnchantedForestZone
Color1|Part|1|4.87,7.98,5.32|6139.65,125.52,-252.63|Build/EnchantedForestZone
Color1|WedgePart|1|5.54,3.55,4.43|6137.71,118.2,-255.39|Build/EnchantedForestZone
Leaf|Part|1|23.04,9.75,23.93|6154.35,160.86,-262.62|Build/EnchantedForestZone
Color1|WedgePart|1|4.87,5.54,4.43|6137.22,119.2,-250.72|Build/EnchantedForestZone
Color1|Part|1|5.76,5.54,5.98|6139.88,119.2,-252.72|Build/EnchantedForestZone
Color1|Part|1|4.43,5.76,5.32|6139.68,131.5,-253.07|Build/EnchantedForestZone
Leaf|Part|1|23.93,7.09,24.82|6144.92,161.76,-263.09|Build/EnchantedForestZone
Color1|WedgePart|1|4.11,6.43,3.39|6678.62,109.79,-464.28|Build/EnchantedForestZone
Color1|Part|1|3.22,8.75,3.57|6676.4,115.06,-463.91|Build/EnchantedForestZone
Color1|WedgePart|1|4.11,5,4.64|6674.13,109.08,-463.52|Build/EnchantedForestZone
Leaf|Part|1|18.58,13.58,17.86|6686.41,135.4,-469.7|Build/EnchantedForestZone
Leaf|Part|1|19.92,8.04,26.88|6667.31,135.48,-464.76|Build/EnchantedForestZone
Color2|Part|1|2.32,16.61,2.32|6679.71,123.39,-465.83|Build/EnchantedForestZone
Leaf|Part|1|20.36,7.32,30.64|6669.08,133.59,-471.53|Build/EnchantedForestZone
Color1|WedgePart|1|3.75,9.11,4.64|6676.07,111.13,-466.47|Build/EnchantedForestZone
Color1|Part|1|3.93,4.47,4.11|6676.6,108.81,-463.94|Build/EnchantedForestZone
Color2|Part|1|2.86,16.97,2.68|6672.02,123.72,-464.96|Build/EnchantedForestZone
Leaf|Part|1|20.72,12.33,23.22|6675.86,137.88,-458.88|Build/EnchantedForestZone
Leaf|Part|1|23.58,8.22,25.01|6678.61,135.74,-449.37|Build/EnchantedForestZone
Color2|Part|1|2.86,16.79,2.86|6676.53,124.23,-458.94|Build/EnchantedForestZone
Leaf|Part|1|26.79,8.22,25.01|6685.63,135.68,-470.02|Build/EnchantedForestZone
Leaf|Part|1|19.74,6.97,27.42|6666.46,136.62,-470.81|Build/EnchantedForestZone
Wedge|WedgePart|1|3.93,3.93,4.64|6676.94,108.54,-461.91|Build/EnchantedForestZone
Wood|Part|1|4.89,8.25,4.19|6952.35,131.7,-238.37|Build/EnchantedForestZone
Wood|Part|1|4.89,8.25,6.88|6944.63,131.71,-236.34|Build/EnchantedForestZone
Leaves|Part|1|29.1,27.84,9.7|6948.43,151.6,-241.3|Build/EnchantedForestZone
Leaves|Part|1|7.69,7.7,9.2|6948.45,185.66,-241.24|Build/EnchantedForestZone
Wood|Part|1|4.89,8.25,4.19|6951.4,131.72,-245.28|Build/EnchantedForestZone
Leaves|Part|1|19.02,17.77,12.64|6948.44,168.51,-241.27|Build/EnchantedForestZone
Wood|Part|1|5.17,5.18,46.7|6948.43,150.94,-241.3|Build/EnchantedForestZone
Leaves|Part|1|12.73,11.94,9.99|6948.54,178.01,-241.42|Build/EnchantedForestZone
Leaves|Part|1|13.34,16.03,6.53|6948.42,145.74,-241.31|Build/EnchantedForestZone
Wood|Part|1|5.67,5.68,11.69|6948.42,133.43,-241.33|Build/EnchantedForestZone
Wood|Part|1|4.89,5.88,6.83|6942.7,130.53,-244.16|Build/EnchantedForestZone
Leaves|Part|1|24.06,22.81,10.32|6948.43,160.29,-241.29|Build/EnchantedForestZone
Leaves|Part|1|13.58,4.43,10.66|6909.58,138.49,-272.32|Build/EnchantedForestZone
Wood|Part|1|6.4,1.66,1.34|6910.82,129.36,-278.67|Build/EnchantedForestZone
Leaves|Part|1|12.26,5.57,12.94|6904.35,135.5,-281.16|Build/EnchantedForestZone
Wood|Part|1|13.84,1.66,1.34|6912.08,128.86,-270.87|Build/EnchantedForestZone
Leaves|Part|1|12.73,6.65,11.14|6908.28,139.29,-277.11|Build/EnchantedForestZone
Leaves|Part|1|15.62,5.73,12.67|6917.2,135.77,-273.44|Build/EnchantedForestZone
Leaves|Part|1|15.62,5.34,13.25|6906.01,135.61,-270.94|Build/EnchantedForestZone
Leaves|Part|1|11.29,5.21,10.11|6910.68,134.62,-267.03|Build/EnchantedForestZone
Wood|Part|1|2.73,4.79,2.6|6907.86,116.44,-275.95|Build/EnchantedForestZone
Wood|Part|1|3.24,2.01,1.69|6909.91,125.79,-276.26|Build/EnchantedForestZone
Wood|Part|1|2.54,4.39,2.74|6909.89,121.06,-274.78|Build/EnchantedForestZone
Wood|Part|1|14.42,1.63,1.31|6905.94,128.16,-276.25|Build/EnchantedForestZone
Wood|Part|1|2.07,3.13,5.43|6911.68,115.61,-278.11|Build/EnchantedForestZone
Leaves|Part|1|13.2,5.84,12.6|6910.95,134.26,-276.18|Build/EnchantedForestZone
Wood|Part|1|2.85,5.11,3.29|6910.17,116.93,-274.9|Build/EnchantedForestZone
Wood|Part|1|1.97,2.99,2.33|6910.48,120.45,-274.95|Build/EnchantedForestZone
Leaves|Part|1|15.03,6.26,13.62|6912.38,136.68,-280.45|Build/EnchantedForestZone
Wood|Part|1|2.73,4.79,3.76|6913.02,116.44,-273.52|Build/EnchantedForestZone
Wood|Part|1|1.87,9.73,2.06|6908.68,127.77,-274.36|Build/EnchantedForestZone
Wood|Part|1|2.73,4.79,2.6|6909.09,116.44,-272.54|Build/EnchantedForestZone
Leaves|Part|1|19.02,17.77,12.64|6110.61,168.51,-486.34|Build/EnchantedForestZone
Leaves|Part|1|7.69,7.7,9.2|6110.6,185.66,-486.37|Build/EnchantedForestZone
Leaves|Part|1|13.34,16.03,6.53|6110.63,145.74,-486.3|Build/EnchantedForestZone
Wood|Part|1|4.89,8.25,6.88|6114.42,131.71,-491.27|Build/EnchantedForestZone
Wood|Part|1|4.89,8.25,4.19|6107.65,131.72,-482.33|Build/EnchantedForestZone
Leaves|Part|1|29.1,27.84,9.7|6110.62,151.6,-486.31|Build/EnchantedForestZone
Wood|Part|1|5.17,5.18,46.7|6110.62,150.94,-486.31|Build/EnchantedForestZone
Wood|Part|1|4.89,8.25,4.19|6106.7,131.7,-489.24|Build/EnchantedForestZone
Wood|Part|1|5.67,5.68,11.69|6110.63,133.43,-486.28|Build/EnchantedForestZone
Leaves|Part|1|24.06,22.81,10.32|6110.62,160.29,-486.32|Build/EnchantedForestZone
Leaves|Part|1|12.73,11.94,9.99|6110.51,178.01,-486.19|Build/EnchantedForestZone
Wood|Part|1|4.89,5.88,6.83|6116.35,130.53,-483.45|Build/EnchantedForestZone
Cube|MeshPart|1|7.34,10.27,13.24|6083.89,72.71,-404.5|Build/EnchantedForestZone
Cube|MeshPart|1|13.4,18.77,24.19|6992.81,76.96,-357.61|Build/EnchantedForestZone
Cube|MeshPart|1|8.21,11.49,14.81|6713.92,73.32,-326.39|Build/EnchantedForestZone
Cube|MeshPart|1|8.21,11.49,14.81|6525.94,73.32,-329.84|Build/EnchantedForestZone
Cube|MeshPart|1|8.21,11.49,14.81|6611.95,73.32,-406.83|Build/EnchantedForestZone
Cube|MeshPart|1|8.21,11.49,14.81|6309.7,73.32,-401.49|Build/EnchantedForestZone
Cube|MeshPart|1|8.21,11.49,14.81|6989.07,73.32,-403.21|Build/EnchantedForestZone
Cube|MeshPart|1|8.21,11.49,14.81|6909.27,73.32,-331.54|Build/EnchantedForestZone
Cube|MeshPart|1|8.21,11.49,14.81|6753.48,73.32,-409.56|Build/EnchantedForestZone
Cube|MeshPart|1|8.21,11.49,14.81|6594.27,73.32,-321.54|Build/EnchantedForestZone
Cube|MeshPart|1|10.96,15.35,19.79|6294.93,75.25,-318.84|Build/EnchantedForestZone
Cube|MeshPart|1|7.34,10.27,13.24|6107.89,72.71,-313.5|Build/EnchantedForestZone
Cube|MeshPart|1|10.96,15.35,19.79|6455.09,75.25,-403.3|Build/EnchantedForestZone
Cube|MeshPart|1|8.8,12.33,15.88|6187.21,73.74,-408.65|Build/EnchantedForestZone
Cylinder.002|MeshPart|1|3.5,10.27,10.23|6950.33,82.71,-438.42|Build/EnchantedForestZone
Cylinder.001|MeshPart|1|11.85,9.35,13.09|6236.2,119.25,-263.12|Build/EnchantedForestZone
Cylinder.001|MeshPart|1|9.58,7.56,10.58|6904.95,103.35,-444.22|Build/EnchantedForestZone
Cylinder.001|MeshPart|1|17.51,13.81,19.33|7062.52,74.48,-60.81|Build/EnchantedForestZone
Plane.009|MeshPart|1|36.56,13.73,36.69|6237.66,112.44,-448.8|Build/EnchantedForestZone
Cylinder.030|MeshPart|1|3.66,7.71,3.92|6535.86,73.43,-281.7|Build/EnchantedForestZone
Cylinder.031|MeshPart|1|10.17,9.67,12.77|6048.21,72.41,-664.88|Build/EnchantedForestZone
Cylinder.001|MeshPart|1|13.65,10.76,15.07|6174.06,74.96,-428.11|Build/EnchantedForestZone
Cylinder.001|MeshPart|1|18.95,14.95,20.93|6669.56,156.9,-240.53|Build/EnchantedForestZone
Cylinder.031|MeshPart|1|5.6,5.32,7.02|7004.72,117.24,-454.02|Build/EnchantedForestZone
Cylinder.001|MeshPart|1|21.23,16.74,23.44|6153.99,107.62,-282.9|Build/EnchantedForestZone
Plane.009|MeshPart|1|25.22,9.47,25.31|6032.7,72.31,-664.56|Build/EnchantedForestZone
Cylinder.031|MeshPart|1|10.17,9.67,12.77|7010.84,72.41,-62.73|Build/EnchantedForestZone
Plane.009|MeshPart|1|71.43,26.82,71.68|6680.06,126.99,-279.39|Build/EnchantedForestZone
Cylinder.031|MeshPart|1|30.66,29.16,38.48|6472.64,78.16,-296.38|Build/EnchantedForestZone
Cylinder.031|MeshPart|1|20.07,19.09,25.2|6948.04,137.12,-264.59|Build/EnchantedForestZone
Cylinder.001|MeshPart|1|52.09,41.08,57.53|6612.52,119.11,-270.7|Build/EnchantedForestZone
Cylinder.002|MeshPart|1|6.04,17.72,17.65|7042.32,76.46,-62.15|Build/EnchantedForestZone
Cylinder.002|MeshPart|1|5.09,14.93,14.87|6318.91,108.04,-291.07|Build/EnchantedForestZone
Cylinder.031|MeshPart|1|33.83,32.17,42.46|7036.89,134.08,-432.95|Build/EnchantedForestZone
Cylinder.001|MeshPart|1|24.09,19,26.61|6280.53,143.93,-482.76|Build/EnchantedForestZone
Cylinder.002|MeshPart|1|6.04,17.72,17.65|6016.73,76.46,-665.46|Build/EnchantedForestZone
Cylinder.001|MeshPart|1|17.51,13.81,19.33|5996.52,74.48,-666.81|Build/EnchantedForestZone
Plane.009|MeshPart|1|25.57,9.6,25.66|6931.38,132.38,-264.57|Build/EnchantedForestZone
Cylinder.001|MeshPart|1|42.5,33.51,46.93|7047.95,147.19,-345.18|Build/EnchantedForestZone
Cylinder.031|MeshPart|1|14.08,13.4,17.68|6492.69,173.27,-471.44|Build/EnchantedForestZone
Cylinder.031|MeshPart|1|6.16,5.86,7.74|6548.6,78.51,-295.73|Build/EnchantedForestZone
Cylinder.002|MeshPart|1|9.31,27.29,27.18|6780.5,114.22,-288.07|Build/EnchantedForestZone
Cylinder.001|MeshPart|1|60.35,47.59,66.65|6536.1,222.15,-493.04|Build/EnchantedForestZone
Plane.009|MeshPart|1|15.22,5.72,15.28|6608.46,78.43,-430.55|Build/EnchantedForestZone
Cylinder.002|MeshPart|1|12.21,35.8,35.65|7004.85,102.33,-343.44|Build/EnchantedForestZone
Plane.009|MeshPart|1|64.94,24.39,65.17|7016.54,99.19,-389.57|Build/EnchantedForestZone
Plane.009|MeshPart|1|24.89,9.35,24.98|6784,111.25,-448.92|Build/EnchantedForestZone
Cylinder.031|MeshPart|1|10.24,9.74,12.86|6237.09,154.3,-501.78|Build/EnchantedForestZone
Cylinder.030|MeshPart|1|16.4,34.52,17.54|7059.08,165.69,-385.42|Build/EnchantedForestZone
Cylinder.030|MeshPart|1|3.62,7.63,3.87|6561.3,188.39,-465.76|Build/EnchantedForestZone
Cylinder.001|MeshPart|1|60.35,47.59,66.65|6992.54,129.37,-459.53|Build/EnchantedForestZone
Cylinder.030|MeshPart|1|6.38,13.42,6.82|6857.33,76.29,-429.94|Build/EnchantedForestZone
Cylinder.001|MeshPart|1|60.35,47.59,66.65|6803.54,129.37,-467.53|Build/EnchantedForestZone
Cylinder.001|MeshPart|1|60.35,47.59,66.65|6522.95,222.15,-234.57|Build/EnchantedForestZone
Plane.009|MeshPart|1|20.19,7.58,20.26|6572.4,93.37,-446.53|Build/EnchantedForestZone
Cylinder.030|MeshPart|1|3.62,7.63,3.87|6497.75,188.39,-261.85|Build/EnchantedForestZone
Cylinder.030|MeshPart|1|12.41,26.13,13.27|6998.04,92.5,-425.78|Build/EnchantedForestZone
Cylinder.030|MeshPart|1|5.92,12.47,6.33|6417.58,86.81,-293.33|Build/EnchantedForestZone
Plane.009|MeshPart|1|17.7,6.65,17.76|6964.2,99.9,-440.16|Build/EnchantedForestZone
Cylinder.002|MeshPart|1|5.09,14.93,14.87|6740.14,108.04,-436.54|Build/EnchantedForestZone
Cylinder.030|MeshPart|1|6.38,13.42,6.82|6201.72,76.29,-297.67|Build/EnchantedForestZone
Cylinder.030|MeshPart|1|16.4,34.52,17.54|6656.85,111.34,-438.08|Build/EnchantedForestZone
Cylinder.030|MeshPart|1|4.33,9.11,4.63|6159.58,74.13,-433.39|Build/EnchantedForestZone
Plane.009|MeshPart|1|46.09,17.31,46.26|6579.33,121.23,-279.15|Build/EnchantedForestZone
Cylinder.031|MeshPart|1|5.6,5.32,7.02|6054.33,117.24,-273.59|Build/EnchantedForestZone
Plane.009|MeshPart|1|71.43,26.82,71.68|6378.99,126.99,-448.22|Build/EnchantedForestZone
Cylinder.001|MeshPart|1|27.1,21.37,29.93|6990.99,135.26,-265.9|Build/EnchantedForestZone
Cylinder.031|MeshPart|1|9.28,8.83,11.65|6265.56,82.99,-292.91|Build/EnchantedForestZone
Cylinder.030|MeshPart|1|3.66,7.71,3.92|6523.19,73.43,-445.91|Build/EnchantedForestZone
Cylinder.001|MeshPart|1|18.95,14.95,20.93|6389.49,156.9,-487.08|Build/EnchantedForestZone
Cylinder.001|MeshPart|1|24.09,19,26.61|6778.52,143.93,-244.85|Build/EnchantedForestZone
Cylinder.030|MeshPart|1|10.92,23,11.68|6191.13,125.1,-442.69|Build/EnchantedForestZone
Plane.009|MeshPart|1|56.49,21.21,56.69|6636.27,112.39,-461.87|Build/EnchantedForestZone
Cylinder.030|MeshPart|1|5.92,12.47,6.33|6641.47,86.81,-434.28|Build/EnchantedForestZone
Cylinder.031|MeshPart|1|14.08,13.4,17.68|6566.36,173.27,-256.17|Build/EnchantedForestZone
Cylinder.002|MeshPart|1|5.25,15.38,15.32|6560.57,77.27,-434.97|Build/EnchantedForestZone
Cylinder.001|MeshPart|1|52.09,41.08,57.53|6446.53,119.11,-456.91|Build/EnchantedForestZone
Cylinder.030|MeshPart|1|10.33,21.75,11.05|6110.64,91.45,-429.91|Build/EnchantedForestZone
Plane.009|MeshPart|1|20.19,7.58,20.26|6486.65,93.37,-281.08|Build/EnchantedForestZone
Plane.009|MeshPart|1|15.22,5.72,15.28|6450.58,78.43,-297.06|Build/EnchantedForestZone
Cylinder.030|MeshPart|1|11.35,23.91,12.14|7019.71,135.38,-298.16|Build/EnchantedForestZone
Cylinder.031|MeshPart|1|10.91,10.38,13.69|6277.87,91.76,-433.26|Build/EnchantedForestZone
Plane.009|MeshPart|1|24.89,9.35,24.98|6275.05,111.25,-278.69|Build/EnchantedForestZone
Plane.009|MeshPart|1|56.49,21.21,56.69|6422.78,112.39,-265.74|Build/EnchantedForestZone
Cylinder.002|MeshPart|1|9.31,27.29,27.18|6278.55,114.22,-439.54|Build/EnchantedForestZone
Cylinder.001|MeshPart|1|60.35,47.59,66.65|6255.51,129.37,-260.08|Build/EnchantedForestZone
Cylinder.001|MeshPart|1|11.85,9.35,13.09|6822.85,119.25,-464.49|Build/EnchantedForestZone
Plane.009|MeshPart|1|17.7,6.65,17.76|6094.85,99.9,-287.45|Build/EnchantedForestZone
Plane.009|MeshPart|1|26.71,10.03,26.81|6995.36,117.59,-285.49|Build/EnchantedForestZone
Cylinder.002|MeshPart|1|3.5,10.27,10.23|6108.72,82.71,-289.19|Build/EnchantedForestZone
Cylinder.031|MeshPart|1|10.91,10.38,13.69|6781.18,91.76,-294.35|Build/EnchantedForestZone
Plane.009|MeshPart|1|25.22,9.47,25.31|7026.35,72.31,-63.05|Build/EnchantedForestZone
Cylinder.002|MeshPart|1|5.25,15.38,15.32|6498.48,77.27,-292.64|Build/EnchantedForestZone
Cylinder.031|MeshPart|1|15.59,14.83,19.57|7017.11,105.85,-320.69|Build/EnchantedForestZone
Cylinder.031|MeshPart|1|9.28,8.83,11.65|6793.49,82.99,-434.7|Build/EnchantedForestZone
Cylinder.031|MeshPart|1|30.66,29.16,38.48|6586.41,78.16,-431.23|Build/EnchantedForestZone
Cylinder.031|MeshPart|1|20.07,19.09,25.2|6111.01,137.12,-463.02|Build/EnchantedForestZone
Plane.009|MeshPart|1|25.57,9.6,25.66|6127.67,132.38,-463.04|Build/EnchantedForestZone
Cylinder.030|MeshPart|1|5.98,12.58,6.39|6061.63,73.89,-663.76|Build/EnchantedForestZone
Cylinder.031|MeshPart|1|6.16,5.86,7.74|6510.45,78.51,-431.88|Build/EnchantedForestZone
Cylinder.030|MeshPart|1|5.98,12.58,6.39|6997.42,73.89,-63.85|Build/EnchantedForestZone
Plane.009|MeshPart|1|46.09,17.31,46.26|6479.72,121.23,-448.47|Build/EnchantedForestZone
Plane.009|MeshPart|1|36.56,13.73,36.69|6821.39,112.44,-278.81|Build/EnchantedForestZone
Cylinder.030|MeshPart|1|16.4,34.52,17.54|6402.2,111.34,-289.53|Build/EnchantedForestZone
Cylinder.030|MeshPart|1|5.59,11.78,5.98|6948.41,86.47,-296.71|Build/EnchantedForestZone
Cube.046|MeshPart|1|9.18,35.58,9.18|6899.62,180.5,-319.38|Build/EnchantedForestZone
Cube.047|MeshPart|1|5.35,8.72,5.35|6899.62,173.08,-319.38|Build/EnchantedForestZone
Cube.048|MeshPart|1|1.43,15.83,1.43|6899.62,190.38,-319.38|Build/EnchantedForestZone
Cube.047|MeshPart|1|1.23,2.01,1.23|6534.68,78.89,-305.88|Build/EnchantedForestZone
Cube.046|MeshPart|1|2.11,8.2,2.11|6534.68,80.6,-305.88|Build/EnchantedForestZone
Cube.040|MeshPart|1|9.47,16.45,1.7|6534.68,77.8,-302.81|Build/EnchantedForestZone
Cube.048|MeshPart|1|0.33,3.65,0.33|6534.68,82.87,-305.88|Build/EnchantedForestZone
Cube.047|MeshPart|1|5.35,8.72,5.35|6280.43,168.08,-476.23|Build/EnchantedForestZone
Cube.048|MeshPart|1|1.43,15.83,1.43|6280.43,185.38,-476.23|Build/EnchantedForestZone
Cube.046|MeshPart|1|9.18,35.58,9.18|6280.43,175.5,-476.23|Build/EnchantedForestZone
Cube.048|MeshPart|1|0.33,3.65,0.33|6830.68,80.87,-326.88|Build/EnchantedForestZone
Cube.047|MeshPart|1|1.23,2.01,1.23|6830.68,76.89,-326.88|Build/EnchantedForestZone
Cube.046|MeshPart|1|2.11,8.2,2.11|6830.68,78.6,-326.88|Build/EnchantedForestZone
Cube.040|MeshPart|1|9.47,16.45,1.7|6830.68,75.8,-323.81|Build/EnchantedForestZone
Cube.048|MeshPart|1|0.33,3.65,0.33|6228.68,82.87,-306.88|Build/EnchantedForestZone
Cube.047|MeshPart|1|1.23,2.01,1.23|6228.68,78.89,-306.88|Build/EnchantedForestZone
Cube.046|MeshPart|1|2.11,8.2,2.11|6228.68,80.6,-306.88|Build/EnchantedForestZone
Cube.040|MeshPart|1|9.47,16.45,1.7|6228.68,77.8,-303.81|Build/EnchantedForestZone
Cube.048|MeshPart|1|0.33,3.65,0.33|6803.52,82.87,-303.88|Build/EnchantedForestZone
Cube.047|MeshPart|1|1.23,2.01,1.23|6803.52,78.89,-303.88|Build/EnchantedForestZone
Cube.046|MeshPart|1|2.11,8.2,2.11|6803.52,80.6,-303.88|Build/EnchantedForestZone
Cube.040|MeshPart|1|9.47,16.45,1.7|6803.52,77.8,-300.81|Build/EnchantedForestZone
Cube.040|MeshPart|1|9.47,16.45,1.7|6933.52,77.8,-304.81|Build/EnchantedForestZone
Cube.048|MeshPart|1|0.33,3.65,0.33|6933.52,82.87,-307.88|Build/EnchantedForestZone
Cube.047|MeshPart|1|1.23,2.01,1.23|6933.52,78.89,-307.88|Build/EnchantedForestZone
Cube.046|MeshPart|1|2.11,8.2,2.11|6933.52,80.6,-307.88|Build/EnchantedForestZone
Cube.047|MeshPart|1|1.23,2.01,1.23|6133.52,76.89,-314.88|Build/EnchantedForestZone
Cube.046|MeshPart|1|2.11,8.2,2.11|6133.52,78.6,-314.88|Build/EnchantedForestZone
Cube.040|MeshPart|1|9.47,16.45,1.7|6133.52,75.8,-311.81|Build/EnchantedForestZone
Cube.048|MeshPart|1|0.33,3.65,0.33|6133.52,80.87,-314.88|Build/EnchantedForestZone
Cube.048|MeshPart|1|0.91,10.04,0.91|6988.74,146.52,-273.38|Build/EnchantedForestZone
Cube.046|MeshPart|1|5.82,22.58,5.82|6988.74,140.25,-273.38|Build/EnchantedForestZone
Cube.047|MeshPart|1|3.39,5.53,3.39|6988.74,135.54,-273.38|Build/EnchantedForestZone
Cube.046|MeshPart|1|2.11,8.2,2.11|6699.52,80.6,-301.88|Build/EnchantedForestZone
Cube.040|MeshPart|1|9.47,16.45,1.7|6699.52,77.8,-298.81|Build/EnchantedForestZone
Cube.047|MeshPart|1|1.23,2.01,1.23|6699.52,78.89,-301.88|Build/EnchantedForestZone
Cube.048|MeshPart|1|0.33,3.65,0.33|6699.52,82.87,-301.88|Build/EnchantedForestZone
Cube.047|MeshPart|1|1.23,2.01,1.23|6886.37,76.89,-327.88|Build/EnchantedForestZone
Cube.040|MeshPart|1|9.47,16.45,1.7|6886.37,75.8,-324.81|Build/EnchantedForestZone
Cube.046|MeshPart|1|2.11,8.2,2.11|6886.37,78.6,-327.88|Build/EnchantedForestZone
Cube.048|MeshPart|1|0.33,3.65,0.33|6886.37,80.87,-327.88|Build/EnchantedForestZone
Cube.046|MeshPart|1|7.11,27.58,7.11|6842.68,138.85,-429.43|Build/EnchantedForestZone
Cube.047|MeshPart|1|4.15,6.76,4.15|6842.68,133.09,-429.43|Build/EnchantedForestZone
Cube.048|MeshPart|1|1.11,12.27,1.11|6842.68,146.51,-429.43|Build/EnchantedForestZone
Cube.047|MeshPart|1|3.24,5.29,3.24|6737.18,121.85,-432.68|Build/EnchantedForestZone
Cube.048|MeshPart|1|0.87,9.6,0.87|6737.18,132.34,-432.68|Build/EnchantedForestZone
Cube.046|MeshPart|1|5.56,21.58,5.56|6737.18,126.35,-432.68|Build/EnchantedForestZone
Cube.046|MeshPart|1|9.18,35.58,9.18|6778.62,175.5,-251.38|Build/EnchantedForestZone
Cube.048|MeshPart|1|1.43,15.83,1.43|6778.62,185.38,-251.38|Build/EnchantedForestZone
Cube.047|MeshPart|1|5.35,8.72,5.35|6778.62,168.08,-251.38|Build/EnchantedForestZone
Cube.047|MeshPart|1|1.23,2.01,1.23|6376.52,78.89,-302.88|Build/EnchantedForestZone
Cube.048|MeshPart|1|0.33,3.65,0.33|6376.52,82.87,-302.88|Build/EnchantedForestZone
Cube.046|MeshPart|1|2.11,8.2,2.11|6376.52,80.6,-302.88|Build/EnchantedForestZone
Cube.040|MeshPart|1|9.47,16.45,1.7|6376.52,77.8,-299.81|Build/EnchantedForestZone
Cube.048|MeshPart|1|0.33,3.65,0.33|6830.37,82.87,-420.73|Build/EnchantedForestZone
Cube.047|MeshPart|1|1.23,2.01,1.23|6830.37,78.89,-420.73|Build/EnchantedForestZone
Cube.046|MeshPart|1|2.11,8.2,2.11|6830.37,80.6,-420.73|Build/EnchantedForestZone
Cube.040|MeshPart|1|9.47,16.45,1.7|6830.37,77.8,-423.81|Build/EnchantedForestZone
Cube.048|MeshPart|1|0.33,3.65,0.33|6925.52,80.87,-412.73|Build/EnchantedForestZone
Cube.047|MeshPart|1|1.23,2.01,1.23|6925.52,76.89,-412.73|Build/EnchantedForestZone
Cube.046|MeshPart|1|2.11,8.2,2.11|6925.52,78.6,-412.73|Build/EnchantedForestZone
Cube.040|MeshPart|1|9.47,16.45,1.7|6925.52,75.8,-415.81|Build/EnchantedForestZone
Cube.047|MeshPart|1|3.24,5.29,3.24|6321.87,121.85,-294.93|Build/EnchantedForestZone
Cube.048|MeshPart|1|0.87,9.6,0.87|6321.87,132.34,-294.93|Build/EnchantedForestZone
Cube.046|MeshPart|1|5.56,21.58,5.56|6321.87,126.35,-294.93|Build/EnchantedForestZone
Cube.046|MeshPart|1|5.82,22.58,5.82|6176.1,139.84,-440.45|Build/EnchantedForestZone
Cube.048|MeshPart|1|0.91,10.04,0.91|6176.1,146.11,-440.45|Build/EnchantedForestZone
Cube.047|MeshPart|1|3.39,5.53,3.39|6176.1,135.13,-440.45|Build/EnchantedForestZone
Cube.046|MeshPart|1|7.11,27.58,7.11|6216.37,138.85,-298.18|Build/EnchantedForestZone
Cube.048|MeshPart|1|1.11,12.27,1.11|6216.37,146.51,-298.18|Build/EnchantedForestZone
Cube.047|MeshPart|1|4.15,6.76,4.15|6216.37,133.09,-298.18|Build/EnchantedForestZone
Cube.047|MeshPart|1|5.35,8.72,5.35|6486.11,196.64,-278|Build/EnchantedForestZone
Cube.046|MeshPart|1|9.18,35.58,9.18|6486.11,204.06,-278|Build/EnchantedForestZone
Cube.048|MeshPart|1|1.43,15.83,1.43|6486.11,213.94,-278|Build/EnchantedForestZone
Cube.047|MeshPart|1|1.23,2.01,1.23|6682.52,78.89,-424.73|Build/EnchantedForestZone
Cube.048|MeshPart|1|0.33,3.65,0.33|6682.52,82.87,-424.73|Build/EnchantedForestZone
Cube.046|MeshPart|1|2.11,8.2,2.11|6682.52,80.6,-424.73|Build/EnchantedForestZone
Cube.040|MeshPart|1|9.47,16.45,1.7|6682.52,77.8,-427.81|Build/EnchantedForestZone
Cube.047|MeshPart|1|1.23,2.01,1.23|6524.37,78.89,-421.73|Build/EnchantedForestZone
Cube.048|MeshPart|1|0.33,3.65,0.33|6524.37,82.87,-421.73|Build/EnchantedForestZone
Cube.046|MeshPart|1|2.11,8.2,2.11|6524.37,80.6,-421.73|Build/EnchantedForestZone
Cube.040|MeshPart|1|9.47,16.45,1.7|6524.37,77.8,-424.81|Build/EnchantedForestZone
Cube.047|MeshPart|1|1.23,2.01,1.23|6568.37,78.89,-421.73|Build/EnchantedForestZone
Cube.046|MeshPart|1|2.11,8.2,2.11|6568.37,80.6,-421.73|Build/EnchantedForestZone
Cube.040|MeshPart|1|9.47,16.45,1.7|6568.37,77.8,-424.81|Build/EnchantedForestZone
Cube.048|MeshPart|1|0.33,3.65,0.33|6568.37,82.87,-421.73|Build/EnchantedForestZone
Cube.040|MeshPart|1|9.47,16.45,1.7|6359.52,77.8,-428.81|Build/EnchantedForestZone
Cube.046|MeshPart|1|2.11,8.2,2.11|6359.52,80.6,-425.73|Build/EnchantedForestZone
Cube.048|MeshPart|1|0.33,3.65,0.33|6359.52,82.87,-425.73|Build/EnchantedForestZone
Cube.047|MeshPart|1|1.23,2.01,1.23|6359.52,78.89,-425.73|Build/EnchantedForestZone
Cube.046|MeshPart|1|2.11,8.2,2.11|6125.52,80.6,-419.73|Build/EnchantedForestZone
Cube.040|MeshPart|1|9.47,16.45,1.7|6125.52,77.8,-422.81|Build/EnchantedForestZone
Cube.048|MeshPart|1|0.33,3.65,0.33|6125.52,82.87,-419.73|Build/EnchantedForestZone
Cube.047|MeshPart|1|1.23,2.01,1.23|6125.52,78.89,-419.73|Build/EnchantedForestZone
Cube.046|MeshPart|1|2.11,8.2,2.11|6205.52,80.6,-419.73|Build/EnchantedForestZone
Cube.040|MeshPart|1|9.47,16.45,1.7|6205.52,77.8,-422.81|Build/EnchantedForestZone
Cube.048|MeshPart|1|0.33,3.65,0.33|6205.52,82.87,-419.73|Build/EnchantedForestZone
Cube.047|MeshPart|1|1.23,2.01,1.23|6205.52,78.89,-419.73|Build/EnchantedForestZone
Cube.040|MeshPart|1|9.47,16.45,1.7|6255.52,77.8,-426.81|Build/EnchantedForestZone
Cube.046|MeshPart|1|2.11,8.2,2.11|6255.52,80.6,-423.73|Build/EnchantedForestZone
Cube.048|MeshPart|1|0.33,3.65,0.33|6255.52,82.87,-423.73|Build/EnchantedForestZone
Cube.047|MeshPart|1|1.23,2.01,1.23|6255.52,78.89,-423.73|Build/EnchantedForestZone
Cube.047|MeshPart|1|5.35,8.72,5.35|6572.94,196.64,-449.61|Build/EnchantedForestZone
Cube.048|MeshPart|1|1.43,15.83,1.43|6572.94,213.94,-449.61|Build/EnchantedForestZone
Cube.046|MeshPart|1|9.18,35.58,9.18|6572.94,204.06,-449.61|Build/EnchantedForestZone
Cube.040|MeshPart|1|9.47,16.45,1.7|6490.68,77.8,-302.81|Build/EnchantedForestZone
Cube.046|MeshPart|1|2.11,8.2,2.11|6490.68,80.6,-305.88|Build/EnchantedForestZone
Cube.048|MeshPart|1|0.33,3.65,0.33|6490.68,82.87,-305.88|Build/EnchantedForestZone
Cube.047|MeshPart|1|1.23,2.01,1.23|6490.68,78.89,-305.88|Build/EnchantedForestZone
Part|Part|1|12,3.75,47|6304.52,64.7,-446.31|Build/EnchantedForestZone
Part|Part|1|160,36.75,33|6347.52,51.2,-450.31|Build/EnchantedForestZone
Part|Part|1|20,2.75,8|6613.52,66.2,-417.81|Build/EnchantedForestZone
Part|Part|1|27,3.75,47|6330.02,64.7,-446.31|Build/EnchantedForestZone
Part|Part|1|966,34.75,92|6529.52,50.2,-363.81|Build/EnchantedForestZone
Part|Part|1|41,3.75,19|6459.02,64.7,-407.31|Build/EnchantedForestZone
Part|Part|1|20,3.75,4|6457.52,64.7,-418.81|Build/EnchantedForestZone
Part|Part|1|11,2.75,21|6052.02,66.2,-420.31|Build/EnchantedForestZone
Part|Part|1|22.5,3.75,44|6277.27,64.7,-447.81|Build/EnchantedForestZone
Part|Part|1|100,2.75,4|6334.52,66.2,-411.81|Build/EnchantedForestZone
Part|Part|1|37,36.75,33|6191.02,51.2,-450.31|Build/EnchantedForestZone
Part|Part|1|55,3.75,42|6508.02,64.7,-444.81|Build/EnchantedForestZone
Part|Part|1|58,2.75,8|6951.52,66.2,-417.81|Build/EnchantedForestZone
Part|Part|1|28,3.75,20|6274.52,64.7,-407.81|Build/EnchantedForestZone
Part|Part|1|56,2.75,8|6756.52,66.2,-413.81|Build/EnchantedForestZone
Part|Part|1|60,36.75,39|6940.52,51.2,-280.31|Build/EnchantedForestZone
Part|Part|1|28,3.75,4|6424.52,64.7,-411.81|Build/EnchantedForestZone
Part|Part|1|4,2.75,24|7010.52,66.2,-421.81|Build/EnchantedForestZone
Part|Part|1|40,3.75,20|6744.52,64.7,-411.81|Build/EnchantedForestZone
Part|Part|1|47,3.75,47|6111.02,64.7,-443.31|Build/EnchantedForestZone
Part|Part|1|21,3.75,5|6299.02,64.7,-413.31|Build/EnchantedForestZone
Part|Part|1|22,2.75,46|6204.52,65.2,-443.81|Build/EnchantedForestZone
Part|Part|1|24,3.75,16|6448.52,64.7,-434.81|Build/EnchantedForestZone
Part|Part|1|160,2.75,4|6928.52,66.2,-411.81|Build/EnchantedForestZone
Part|Part|1|41,3.75,16|6511.02,64.7,-405.81|Build/EnchantedForestZone
Part|Part|1|12,2.75,7|6063.52,66.2,-427.31|Build/EnchantedForestZone
Part|Part|1|24,3.75,21|6224.52,64.7,-295.31|Build/EnchantedForestZone
Part|Part|1|160,36.75,33|6711.52,51.2,-277.31|Build/EnchantedForestZone
Part|Part|1|12,3.75,4|6700.52,64.7,-311.81|Build/EnchantedForestZone
Part|Part|1|21,4.75,4|6925.02,67.2,-301.81|Build/EnchantedForestZone
Part|Part|1|11,2.75,21|7007.02,66.2,-307.31|Build/EnchantedForestZone
Part|Part|1|8,2.75,4|6061.52,66.2,-421.81|Build/EnchantedForestZone
Part|Part|1|58,36.75,33|6075.52,51.2,-277.31|Build/EnchantedForestZone
Part|Part|1|19,4.75,8|6383.02,67.2,-295.81|Build/EnchantedForestZone
Part|Part|1|36,3.75,16|6990.52,64.7,-321.81|Build/EnchantedForestZone
Part|Part|1|19,4.75,4|6612.02,67.2,-295.81|Build/EnchantedForestZone
Part|Part|1|96,36.75,33|6575.52,51.2,-277.31|Build/EnchantedForestZone
Part|Part|1|24,36.75,39|6812.52,51.2,-280.31|Build/EnchantedForestZone
Part|Part|1|36,36.75,39|6240.52,51.2,-447.31|Build/EnchantedForestZone
Part|Part|1|23.5,3.75,44|6248.27,64.7,-447.81|Build/EnchantedForestZone
Part|Part|1|56,4.75,10|6203.52,67.2,-298.81|Build/EnchantedForestZone
Part|Part|1|16,3.75,16|6806.52,64.7,-321.81|Build/EnchantedForestZone
Part|Part|1|96,36.75,33|6483.52,51.2,-450.31|Build/EnchantedForestZone
Part|Part|1|56,2.75,8|6302.52,66.2,-313.81|Build/EnchantedForestZone
Part|Part|1|137,36.75,33|6852.02,51.2,-450.31|Build/EnchantedForestZone
Part|Part|1|16,3.75,24|6879.52,64.7,-431.81|Build/EnchantedForestZone
Part|Part|1|21,3.75,5|6760.02,64.7,-314.31|Build/EnchantedForestZone
Part|Part|1|58,2.75,8|6107.52,66.2,-309.81|Build/EnchantedForestZone
Part|Part|1|75,36.75,39|6126.02,51.2,-447.31|Build/EnchantedForestZone
Part|Part|1|19,4.75,4|6447.02,67.2,-431.81|Build/EnchantedForestZone
Part|Part|1|22.5,3.75,44|6781.77,64.7,-279.81|Build/EnchantedForestZone
Part|Part|1|966,30.75,202|6529.52,48.2,-363.81|Build/EnchantedForestZone
Part|Part|1|16,3.75,24|6179.52,64.7,-295.81|Build/EnchantedForestZone
Part|Part|1|56,4.75,10|6855.52,67.2,-428.81|Build/EnchantedForestZone
Part|Part|1|44,2.75,4|6463.52,66.2,-411.81|Build/EnchantedForestZone
Part|Part|1|51,2.75,4|6439.02,66.2,-315.81|Build/EnchantedForestZone
Part|Part|1|40,3.75,24|6120.52,64.7,-313.81|Build/EnchantedForestZone
Part|Part|1|51,2.75,4|6620.02,66.2,-411.81|Build/EnchantedForestZone
Part|Part|1|58,36.75,33|6983.52,51.2,-450.31|Build/EnchantedForestZone
Part|Part|1|19,4.75,8|6676.02,67.2,-431.81|Build/EnchantedForestZone
Part|Part|1|72,4.75,4|6392.52,67.2,-431.81|Build/EnchantedForestZone
Part|Part|1|40,3.75,20|6448.52,64.7,-319.81|Build/EnchantedForestZone
Part|Part|1|16,3.75,16|6252.52,64.7,-405.81|Build/EnchantedForestZone
Part|Part|1|47,3.75,47|6948.02,64.7,-284.31|Build/EnchantedForestZone
Part|Part|1|24,3.75,16|6610.52,64.7,-292.81|Build/EnchantedForestZone
Part|Part|1|42,4.75,4|6772.52,67.2,-295.81|Build/EnchantedForestZone
Part|Part|1|27,3.75,47|6729.02,64.7,-281.31|Build/EnchantedForestZone
Part|Part|1|23.5,3.75,44|6810.77,64.7,-279.81|Build/EnchantedForestZone
Part|Part|1|84,34.75,53|6865.52,50.2,-287.31|Build/EnchantedForestZone
Part|Part|1|55,3.75,42|6551.02,64.7,-282.81|Build/EnchantedForestZone
Part|Part|1|14,4.75,8|6493.52,67.2,-297.81|Build/EnchantedForestZone
Part|Part|1|24,3.75,21|6396.52,64.7,-295.31|Build/EnchantedForestZone
Part|Part|1|20,2.75,4|6552.52,65.2,-305.81|Build/EnchantedForestZone
Part|Part|1|24,3.75,21|6834.52,64.7,-432.31|Build/EnchantedForestZone
Part|Part|1|39,3.75,44|6670.02,64.7,-447.81|Build/EnchantedForestZone
Part|Part|1|31,36.75,39|6062.02,51.2,-447.31|Build/EnchantedForestZone
Part|Part|1|14,4.75,8|6538.52,67.2,-297.81|Build/EnchantedForestZone
Part|Part|1|41,3.75,19|6600.02,64.7,-320.31|Build/EnchantedForestZone
Part|Part|1|100,2.75,4|6724.52,66.2,-315.81|Build/EnchantedForestZone
Part|Part|1|33,3.75,19|6394.02,64.7,-407.31|Build/EnchantedForestZone
Part|Part|1|100,2.75,4|6180.52,66.2,-411.81|Build/EnchantedForestZone
Part|Part|1|12,3.75,4|6358.52,64.7,-415.81|Build/EnchantedForestZone
Part|Part|1|36,3.75,16|6068.52,64.7,-405.81|Build/EnchantedForestZone
Part|Part|1|42,4.75,4|6286.52,67.2,-431.81|Build/EnchantedForestZone
Part|Part|1|40,3.75,20|6610.52,64.7,-407.81|Build/EnchantedForestZone
Part|Part|1|40,4.75,10|6188.52,67.2,-428.81|Build/EnchantedForestZone
Part|Part|1|160,2.75,4|6130.52,66.2,-315.81|Build/EnchantedForestZone
Part|Part|1|14,4.75,8|6520.52,67.2,-429.81|Build/EnchantedForestZone
Part|Part|1|40,3.75,24|6938.52,64.7,-413.81|Build/EnchantedForestZone
Part|Part|1|137,36.75,33|6207.02,51.2,-277.31|Build/EnchantedForestZone
Part|Part|1|33,3.75,42|6645.02,64.7,-281.81|Build/EnchantedForestZone
Part|Part|1|12,3.75,47|6754.52,64.7,-281.31|Build/EnchantedForestZone
Part|Part|1|39,3.75,44|6389.02,64.7,-279.81|Build/EnchantedForestZone
Part|Part|1|20,2.75,8|6445.52,66.2,-309.81|Build/EnchantedForestZone
Part|Part|1|20,2.75,15|6802.52,66.2,-310.31|Build/EnchantedForestZone
Part|Part|1|28,3.75,4|6634.52,64.7,-315.81|Build/EnchantedForestZone
Part|Part|1|31,36.75,33|6723.02,51.2,-450.31|Build/EnchantedForestZone
Part|Part|1|14,4.75,8|6565.52,67.2,-429.81|Build/EnchantedForestZone
Part|Part|1|20,2.75,4|6506.52,65.2,-421.81|Build/EnchantedForestZone
Part|Part|1|33,3.75,42|6414.02,64.7,-445.81|Build/EnchantedForestZone
Part|Part|1|28,4.75,4|6137.52,67.2,-425.81|Build/EnchantedForestZone
Part|Part|1|72,4.75,4|6666.52,67.2,-295.81|Build/EnchantedForestZone
Part|Part|1|28,3.75,20|6784.52,64.7,-319.81|Build/EnchantedForestZone
Part|Part|1|37,3.75,21|6490.02,64.7,-295.31|Build/EnchantedForestZone
Part|Part|1|4,2.75,24|6048.52,66.2,-305.81|Build/EnchantedForestZone
Part|Part|1|40,3.75,20|6314.52,64.7,-315.81|Build/EnchantedForestZone
Part|Part|1|31,36.75,39|6997.02,51.2,-280.31|Build/EnchantedForestZone
Part|Part|1|33,3.75,19|6665.02,64.7,-320.31|Build/EnchantedForestZone
Part|Part|1|41,3.75,16|6548.02,64.7,-321.81|Build/EnchantedForestZone
Part|Part|1|109,2.75,4|6874.02,66.2,-315.81|Build/EnchantedForestZone
Part|Part|1|80,3.75,20|6194.52,64.7,-407.81|Build/EnchantedForestZone
Part|Part|1|24,3.75,21|6662.52,64.7,-432.31|Build/EnchantedForestZone
Part|Part|1|44,2.75,4|6595.52,66.2,-315.81|Build/EnchantedForestZone
Part|Part|1|31,36.75,33|6336.02,51.2,-277.31|Build/EnchantedForestZone
Part|Part|1|20,3.75,4|6601.52,64.7,-308.81|Build/EnchantedForestZone
Part|Part|1|133,36.75,33|6439.02,51.2,-277.31|Build/EnchantedForestZone
Part|Part|1|133,36.75,33|6620.02,51.2,-450.31|Build/EnchantedForestZone
Part|Part|1|12,2.75,7|6995.52,66.2,-300.31|Build/EnchantedForestZone
Part|Part|1|37,3.75,21|6569.02,64.7,-432.31|Build/EnchantedForestZone
WispVisual|MeshPart|1|16.32,0.28,16.36|6495.3,67.5,-329.4|Build/EnchantedForestZone
Radius|Part|0|0.17,15.3,15.3|6495.27,67.5,-329.4|Build/EnchantedForestZone
WispVisual|MeshPart|1|16.77,0.29,16.8|537.3,67.56,-401.19|Build/WispVisual
Radius|Part|1|0.17,15.72,15.72|537.26,67.56,-401.19|Build/WispVisual
Shaft|MeshPart|1|3.02,7.18,0.43|6000.2,17008.88,15700.14|World/Machines
Hoop|MeshPart|1|2.43,3.25,2.14|5999.29,17010.73,15700.55|World/Machines
Handle|MeshPart|1|0.61,1.27,0.63|6000.2,17005.75,15699.57|World/Machines
ShaftInner|MeshPart|1|3.05,7.19,0.41|6000.2,17008.88,15700.14|World/Machines
Leaf|MeshPart|1|0.57,1.02,0.31|6000.07,17009.16,15701.27|World/Machines
Frame|MeshPart|1|2.83,6.99,0.65|6000.13,17008.91,15700.1|World/Machines
Meshes/Steal an Egg Fuse Machine_Cube.002|MeshPart|1|4.59,6.03,1.83|541.78,71.29,-456.31|World/Machines
Cube.015|MeshPart|1|6.72,6.64,0.86|541.21,71.6,-446.11|World/Machines
Cylinder.003|MeshPart|1|8.47,8.84,6.23|543,73.4,-442.99|World/Machines
Cylinder.004|MeshPart|1|15.49,5.39,6.83|543.96,76.48,-447.27|World/Machines
Cube.005|MeshPart|1|10.33,0.54,9.47|543.96,68.54,-446.11|World/Machines
Cylinder.001|MeshPart|1|4.25,0.72,4.25|543.96,79.54,-446.11|World/Machines
Cube.006|MeshPart|1|3.52,2.55,1.42|541.53,69.55,-453.59|World/Machines
Meshes/Steal an Egg Fuse Machine_Cube.038|Part|1|3.71,0.72,1.52|541.48,68.64,-453.59|World/Machines
Cube.014|MeshPart|1|7.16,6.86,2.7|541.79,71.71,-446.11|World/Machines
Cylinder.005|MeshPart|1|15.52,5.07,7.71|543.96,76.82,-450.01|World/Machines
Meshes/Steal an Egg Fuse Machine_Cube.004|MeshPart|1|0.86,2.52,0.08|542.01,73.09,-452.43|World/Machines
Cube.019|MeshPart|1|5.6,4.97,5.2|543.41,71.8,-455.57|World/Machines
Cube.007|Part|1|0.25,1.36,0.24|540.87,70.8,-457.35|World/Machines
Text|MeshPart|1|2.87,3.87,2.96|542.02,72.03,-446.09|World/Machines
Cube.009|MeshPart|1|19.93,2.52,2.25|548.31,69.71,-450.07|World/Machines
Meshes/Steal an Egg Fuse Machine_Cube.003|MeshPart|1|1.46,3.37,0.9|542.36,73.09,-452.43|World/Machines
Cube.012|MeshPart|1|17.86,8.13,8.67|543.96,72.34,-450.27|World/Machines
Cube.020|MeshPart|1|20.51,0.3,11.58|543.96,68.13,-450.05|World/Machines
Meshes/Steal an Egg Fuse Machine_Cylinder.012|MeshPart|1|3.42,2.8,0.1|541.99,72.31,-456.43|World/Machines
Cube.011|MeshPart|1|7.61,7.12,3.04|541.62,71.84,-446.11|World/Machines
Cube.010|MeshPart|1|17.43,8.3,8.67|543.96,73.15,-450.25|World/Machines
Cube.018|MeshPart|1|4.57,1.75,1.28|540.79,70.96,-455.27|World/Machines
Cylinder|MeshPart|1|17.11,10.44,3.91|544.44,72.89,-447.04|World/Machines
Cube|MeshPart|1|21.11,0.77,12.18|543.96,68.06,-450.05|World/Machines
Cube.008|MeshPart|1|1.85,4.26,3.64|544.44,70.92,-439.58|World/Machines
Meshes/Steal an Egg Fuse Machine_Cube.017|MeshPart|1|6.3,3.84,0.03|542.03,72.58,-455.12|World/Machines
Cube.013|MeshPart|1|7.27,6.17,2.85|541.71,72.12,-446.11|World/Machines
Part_3|Part|0|0.73,13.65,0.49|548.11,77.89,-279.17|World/Leaderboards
Part_2|Part|0|10.53,0.73,0.49|548.11,70.7,-274.27|World/Leaderboards
Part|Part|0|0.73,13.65,0.49|548.11,77.89,-269.38|World/Leaderboards
Leaderboard|Part|0|8.57,13.47,0.24|548.24,77.98,-274.27|World/Leaderboards
LeaderboardTItle|Part|0|11.02,1.84,0.98|548.05,85.94,-274.27|World/Leaderboards
Part_23|Part|0|0.74,13.47,0.51|548.11,77.98,-279.17|World/Leaderboards
Part_21|Part|0|11.02,1.22,0.61|547.01,68.19,-274.27|World/Leaderboards
Part_9|Part|0|11.63,2.45,1.22|548.24,85.94,-274.27|World/Leaderboards
Part_10|Part|0|11.02,1.22,0.62|548.24,70.64,-274.27|World/Leaderboards
Part_22|Part|0|11.02,0.61,2.45|548.24,67.88,-274.27|World/Leaderboards
Part_6|Part|0|0.98,2.08,0.31|548.24,69.01,-275.93|World/Leaderboards
Part_7|Part|0|10.54,0.7,0.68|548.2,70.64,-274.27|World/Leaderboards
Part_16|Part|0|0.61,1.22,3.06|548.24,68.19,-268.46|World/Leaderboards
Part|Part|0|0.98,0.92,1.84|548.05,85.94,-268.3|World/Leaderboards
Part_2|Part|0|1.22,1.22,2.45|548.24,85.94,-267.84|World/Leaderboards
Part_5|Part|0|1.22,0.31,0.98|548.24,69.01,-274.27|World/Leaderboards
Part_19|Part|0|1.16,0.92,1.84|548.14,85.94,-280.24|World/Leaderboards
Part_20|Part|0|0.61,1.22,3.06|548.24,68.19,-280.09|World/Leaderboards
Part_18|Part|0|1.22,1.22,2.45|548.24,85.94,-280.7|World/Leaderboards
Part_13|Part|0|0.61,3.67,0.61|548.24,69.72,-277.95|World/Leaderboards
Part_11|Part|0|5.39,1.96,0.98|548.24,70.15,-274.27|World/Leaderboards
Part_24|Part|0|0.74,13.47,0.39|548.05,77.98,-269.38|World/Leaderboards
Part_12|Part|0|11.02,1.22,0.61|549.46,68.19,-274.27|World/Leaderboards
Part_14|Part|0|1.22,13.47,0.61|548.24,77.98,-279.17|World/Leaderboards
Part_17|Part|0|0.98,2.08,0.31|548.24,69.01,-272.62|World/Leaderboards
Part_15|Part|0|3.67,0.61,0.61|548.24,69.72,-274.27|World/Leaderboards
Part_4|Part|0|1.22,13.47,0.61|548.24,77.98,-269.38|World/Leaderboards
Part_8|Part|0|7.96,0.61,1.22|548.24,87.47,-274.27|World/Leaderboards
Part_3|Part|0|0.61,3.67,0.61|548.24,69.72,-270.6|World/Leaderboards
Spiral.005|MeshPart|1|5.74,17.62,15.63|535.9,76.43,-325.68|World/HalloweenDimensionPortal
Spiral.003|MeshPart|1|6.07,17.62,17.16|535.72,76.39,-324.85|World/HalloweenDimensionPortal
Cube.033|MeshPart|1|9.48,13.77,18.03|536.36,74.48,-325.69|World/HalloweenDimensionPortal
Cylinder.004|MeshPart|1|4.46,4.89,18.13|534.49,70.11,-324.86|World/HalloweenDimensionPortal
Cube.159|MeshPart|1|6.1,2.37,4.92|546.88,72.19,-287.91|Chest
Cube.148|MeshPart|1|6.62,3.67,5.17|547.02,69.36,-287.93|Chest
]==]

local BIOME_DATA = [==[
Forest|93.38,151.36|599.85,67.65,-363.94|16|77,153,83
Lake|139.57,150.21|722.51,67.73,-363.94|18|72,157,188
Desert|204.66,151.09|901.14,67.72,-368.63|20|210,175,112
Jungle|229.99,150.27|1124.71,67.53,-363.94|23|65,142,85
Snow|318.21,150.21|1405.13,67.97,-363.81|26|178,215,231
Volcano|379.43,150.05|1759.32,67.61,-363.94|29|177,73,47
Abyss Ocean|423.05,150.05|2166.06,67.61,-363.94|32|37,72,125
Prehistoric|502.18,150.87|2634.38,67.61,-363.94|35|132,135,83
Cosmic|641.96,150.41|3206.75,67.61,-363.94|38|99,75,165
Cherry Blossom|676,150|3928,67.6,-363.8|41|218,139,174
Titan Temple|860,150|4698,67.6,-363.8|44|173,145,87
Light Dark|893.5,150|5577.25,67.6,-363.8|48|91,90,111
Enchanted Forest|1089.93,194.8|6524,67.6,-365|52|66,133,102
]==]

local PLOT_DATA = [==[
1|471.75,73.88,-364.37|444.74,68.20,-363.94|407.64,67.68,-364.37|112.67,49.34|482.33,67.68,-374.65|438.19,109.97,-364.41
2|471.75,73.88,-283.37|444.74,68.20,-282.94|438.99,67.68,-283.37|49.96,49.34|481.73,67.68,-303.65|438.19,109.97,-283.41
3|471.75,73.88,-202.37|444.74,68.20,-201.94|407.64,67.68,-202.37|112.67,49.34|480.22,67.68,-240.29|438.19,109.97,-202.41
4|471.75,73.88,-444.02|444.74,68.20,-443.59|407.64,67.68,-444.02|112.67,49.34|482.13,67.68,-429.30|438.19,109.97,-444.06
5|472.67,73.88,-523.47|445.66,68.20,-523.04|408.56,67.68,-523.48|112.67,49.34|480.36,67.68,-487.05|439.11,109.97,-523.51
6|522.33,73.88,-230.43|522.76,68.20,-203.42|522.33,67.68,-166.41|112.47,49.34|532.05,67.68,-241.41|522.29,109.97,-196.86
7|522.32,73.88,-497.61|521.89,68.20,-524.62|522.33,67.68,-530.37|49.96,49.34|528.61,67.68,-487.62|522.37,109.97,-531.17
]==]

local EGG_SPAWN_DATA = [==[
600.22,68.35,-332.65
605.00,68.56,-326.50
592.97,68.02,-332.40
590.60,70.30,-325.56
597.27,68.19,-324.29
4020.23,68.71,-399.90
4031.48,68.38,-392.44
3391.78,68.81,-320.76
949.87,68.13,-320.15
953.16,69.21,-328.17
3387.75,68.07,-328.96
1193.21,68.86,-405.35
4793.96,69.51,-333.21
1189.00,69.05,-413.38
2813.61,68.27,-402.16
2281.59,67.76,-323.05
2820.17,69.27,-400.95
2284.54,68.69,-331.42
3385.18,68.91,-321.92
5659.06,71.05,-333.21
1883.41,68.37,-393.76
4034.63,68.63,-399.01
957.64,69.11,-322.31
2275.01,67.76,-324.24
4790.75,69.39,-326.72
750.29,68.19,-411.61
743.71,68.33,-412.79
1500.40,68.93,-312.66
2805.79,67.91,-400.04
5662.22,69.76,-324.72
2289.35,68.24,-325.23
4797.20,69.84,-324.72
4024.26,68.89,-393.11
4801.09,70.70,-332.57
1495.21,71.64,-319.22
747.92,68.53,-404.77
2277.31,69.19,-331.15
1195.53,68.10,-412.24
1181.14,68.05,-411.29
735.90,68.17,-410.67
2817.80,69.14,-394.11
1871.38,70.47,-399.67
740.70,68.22,-404.49
6700.75,69.67,-353.77
5655.84,69.59,-326.72
6693.56,69.94,-354.40
1492.41,69.56,-310.71
6704.74,70.93,-347.02
3399.78,68.14,-323.07
6696.72,69.74,-345.92
4805.27,69.67,-325.89
1486.03,69.01,-311.70
1488.20,69.48,-318.74
943.28,70.14,-321.34
2810.60,67.96,-393.86
3394.97,68.04,-329.24
4028.32,68.38,-400.93
1876.14,68.30,-393.54
1879.19,67.73,-401.79
1885.77,69.56,-400.61
945.58,68.36,-328.26
1186.00,68.48,-405.07
5670.24,69.71,-325.84
6690.34,69.50,-347.92
]==]

local BIOMES = {}
for line in string.gmatch(BIOME_DATA, "[^\n]+") do
    local f = string.split(line, "|")
    local pos = v3(f[3])
    local size = string.split(f[2], ",")
    local rgb = string.split(f[5], ",")
    table.insert(BIOMES, {
        name = f[1], sizeX = tonumber(size[1]), sizeZ = tonumber(size[2]),
        position = pos, requiredSpeed = tonumber(f[4]),
        color = Color3.fromRGB(tonumber(rgb[1]), tonumber(rgb[2]), tonumber(rgb[3])),
        index = #BIOMES + 1,
    })
end

table.sort(BIOMES, function(a, b) return a.position.X < b.position.X end)
for i, zone in ipairs(BIOMES) do zone.index = i end

local PLOTS = {}
for line in string.gmatch(PLOT_DATA, "[^\n]+") do
    local f = string.split(line, "|")
    local areaSize = string.split(f[5], ",")
    PLOTS[tonumber(f[1])] = {
        id = tonumber(f[1]), spawn = v3(f[2]), center = v3(f[3]),
        petCenter = v3(f[4]), petSizeX = tonumber(areaSize[1]), petSizeZ = tonumber(areaSize[2]),
        treadmill = v3(f[6]), sign = v3(f[7]),
    }
end

local EGG_SPAWNS = {}
for line in string.gmatch(EGG_SPAWN_DATA, "[^\n]+") do
    table.insert(EGG_SPAWNS, v3(line))
end

local function biomeAtX(x)
    local best, distance = BIOMES[1], math.huge
    for _, zone in ipairs(BIOMES) do
        local left = zone.position.X - zone.sizeX / 2
        local right = zone.position.X + zone.sizeX / 2
        if x >= left and x <= right then return zone end
        local d = math.min(math.abs(x - left), math.abs(x - right))
        if d < distance then best, distance = zone, d end
    end
    return best
end

local PALETTE = {
    Hub = {base = Color3.fromRGB(80, 103, 139), accent = Color3.fromRGB(245, 190, 76), rock = Color3.fromRGB(90, 96, 110), leaf = Color3.fromRGB(78, 145, 99)},
    Forest = {base = Color3.fromRGB(93, 151, 81), accent = Color3.fromRGB(179, 214, 108), rock = Color3.fromRGB(101, 116, 86), leaf = Color3.fromRGB(49, 117, 64)},
    Lake = {base = Color3.fromRGB(74, 145, 177), accent = Color3.fromRGB(137, 218, 226), rock = Color3.fromRGB(82, 117, 135), leaf = Color3.fromRGB(69, 133, 125)},
    Desert = {base = Color3.fromRGB(206, 171, 108), accent = Color3.fromRGB(246, 214, 139), rock = Color3.fromRGB(149, 113, 74), leaf = Color3.fromRGB(119, 139, 73)},
    Jungle = {base = Color3.fromRGB(61, 132, 75), accent = Color3.fromRGB(160, 204, 91), rock = Color3.fromRGB(86, 106, 77), leaf = Color3.fromRGB(35, 105, 54)},
    Snow = {base = Color3.fromRGB(175, 213, 230), accent = Color3.fromRGB(232, 247, 255), rock = Color3.fromRGB(125, 157, 175), leaf = Color3.fromRGB(124, 176, 176)},
    Volcano = {base = Color3.fromRGB(133, 67, 55), accent = Color3.fromRGB(255, 112, 49), rock = Color3.fromRGB(62, 54, 56), leaf = Color3.fromRGB(93, 76, 53)},
    ["Abyss Ocean"] = {base = Color3.fromRGB(36, 67, 119), accent = Color3.fromRGB(77, 193, 221), rock = Color3.fromRGB(38, 50, 81), leaf = Color3.fromRGB(49, 103, 129)},
    Prehistoric = {base = Color3.fromRGB(126, 129, 75), accent = Color3.fromRGB(197, 173, 106), rock = Color3.fromRGB(103, 96, 68), leaf = Color3.fromRGB(81, 126, 62)},
    Cosmic = {base = Color3.fromRGB(83, 65, 142), accent = Color3.fromRGB(196, 128, 255), rock = Color3.fromRGB(57, 54, 104), leaf = Color3.fromRGB(111, 83, 169)},
    ["Cherry Blossom"] = {base = Color3.fromRGB(207, 137, 168), accent = Color3.fromRGB(255, 202, 224), rock = Color3.fromRGB(139, 115, 133), leaf = Color3.fromRGB(119, 163, 112)},
    ["Titan Temple"] = {base = Color3.fromRGB(157, 132, 79), accent = Color3.fromRGB(255, 220, 132), rock = Color3.fromRGB(108, 99, 78), leaf = Color3.fromRGB(111, 121, 78)},
    ["Light Dark"] = {base = Color3.fromRGB(85, 83, 112), accent = Color3.fromRGB(201, 194, 255), rock = Color3.fromRGB(47, 45, 67), leaf = Color3.fromRGB(112, 87, 146)},
    ["Enchanted Forest"] = {base = Color3.fromRGB(58, 121, 91), accent = Color3.fromRGB(161, 247, 191), rock = Color3.fromRGB(66, 92, 86), leaf = Color3.fromRGB(46, 156, 108)},
}

local function inferredColor(name, sourceTag, position)
    local zone = biomeAtX(position.X)
    local pal = PALETTE[zone and zone.name] or PALETTE.Hub
    if sourceTag == "Stands" or string.find(sourceTag, "Plots", 1, true) or position.X < 553 then
        pal = PALETTE.Hub
    end
    local lower = string.lower(name)
    if string.find(lower, "color1", 1, true) or string.find(lower, "accent", 1, true) then return pal.accent end
    if string.find(lower, "color2", 1, true) or string.find(lower, "trunk", 1, true) or string.find(lower, "rock", 1, true) then return pal.rock end
    if string.find(lower, "tree", 1, true) or string.find(lower, "leaf", 1, true) or string.find(lower, "bush", 1, true) then return pal.leaf end
    if string.find(lower, "glass", 1, true) or string.find(lower, "crystal", 1, true) then return pal.accent end
    return pal.base
end

local function inferredMaterial(name, sourceTag, position)
    local lower = string.lower(name)
    if string.find(lower, "lava", 1, true) or string.find(lower, "glow", 1, true) or string.find(lower, "light", 1, true) then
        return Enum.Material.Neon
    end
    if string.find(lower, "water", 1, true) or string.find(lower, "ice", 1, true) then return Enum.Material.Glass end
    if string.find(lower, "rock", 1, true) or string.find(lower, "stone", 1, true) then return Enum.Material.Rock end
    local zone = biomeAtX(position.X)
    if zone and zone.name == "Snow" then return Enum.Material.Snow end
    if zone and zone.name == "Desert" then return Enum.Material.Sand end
    if zone and (zone.name == "Forest" or zone.name == "Jungle" or zone.name == "Enchanted Forest") then return Enum.Material.Grass end
    return Enum.Material.SmoothPlastic
end

-- Build walkable ground strips using the 13 exact guard-zone bounds as the footprint reference.
for _, zone in ipairs(BIOMES) do
    local floor = makePart(biomeFolder, zone.name .. "Ground", Vector3.new(zone.sizeX, 1.2, zone.sizeZ),
        CFrame.new(zone.position.X, zone.position.Y - 1.0, zone.position.Z),
        zone.color, Enum.Material.Grass, true, true)
    floor.Transparency = 0.02
    local sign = makeAnchor(biomeFolder, zone.name .. "SignAnchor",
        Vector3.new(zone.position.X, zone.position.Y + 15, zone.position.Z + zone.sizeZ / 2 - 12))
    billboard(sign, string.upper(zone.name) .. "  •  SPEED " .. zone.requiredSpeed .. "+",
        Color3.fromRGB(255, 255, 255), UDim2.fromOffset(250, 48))
end

-- Create speed-check gates at the start of every biome after Forest.
local gateDebounce = {}
for i = 2, #BIOMES do
    local zone = BIOMES[i]
    local gateX = zone.position.X - zone.sizeX / 2 - 2
    local gate = makePart(biomeFolder, zone.name .. "SpeedGate", Vector3.new(2, 22, zone.sizeZ),
        CFrame.new(gateX, zone.position.Y + 10, zone.position.Z),
        zone.color, Enum.Material.ForceField, true, true)
    gate.Transparency = 0.72
    gate.CanTouch = true
    gate.Touched:Connect(function(hit)
        local character = hit and hit.Parent
        if not character then return end
        local player = Players:GetPlayerFromCharacter(character)
        if not player then return end
        local root = character:FindFirstChild("HumanoidRootPart")
        if not root then return end
        local now = os.clock()
        if gateDebounce[player] and now - gateDebounce[player] < 0.8 then return end
        gateDebounce[player] = now
        local stats = player:FindFirstChild("leaderstats")
        local speed = stats and stats:FindFirstChild("Speed")
        if speed and speed.Value >= zone.requiredSpeed then
            root.CFrame = root.CFrame + Vector3.new(root.Position.X < gateX and 8 or -8, 2, 0)
        else
            if root.Position.X < gateX then
                root.CFrame = CFrame.new(gateX - 5, root.Position.Y + 1, root.Position.Z)
            else
                root.CFrame = root.CFrame + Vector3.new(-8, 1, 0)
            end
            local pg = player:FindFirstChildOfClass("PlayerGui")
            local hud = pg and pg:FindFirstChild("EggRushHUD")
            local note = hud and hud:FindFirstChild("Notice", true)
            if note then note.Text = "Locked! Upgrade speed to " .. zone.requiredSpeed; note.Visible = true end
        end
    end)
    local gateLabel = makeAnchor(biomeFolder, zone.name .. "GateLabel", Vector3.new(gateX, zone.position.Y + 23, zone.position.Z))
    billboard(gateLabel, "REQUIRES " .. zone.requiredSpeed .. " SPEED", Color3.fromRGB(255, 224, 126))
end

-- Render the reconstructed static map. Original rotations and mesh IDs were not present in the dump.
local geometryGroups = {}
local builtParts = 0
local function getGroup(name)
    if not geometryGroups[name] then
        local folder = Instance.new("Folder")
        folder.Name = string.gsub(name, "/", "_")
        folder.Parent = geometryFolder
        geometryGroups[name] = folder
    end
    return geometryGroups[name]
end

for line in string.gmatch(MAP_DATA, "[^\n]+") do
    local f = string.split(line, "|")
    if #f >= 6 then
        local name, className, noCollide = f[1], f[2], f[3] == "1"
        local size, position = v3(f[4]), v3(f[5])
        local group = getGroup(f[6])
        local part
        if className == "WedgePart" then
            part = Instance.new("WedgePart")
        else
            part = Instance.new("Part")
            if className == "MeshPart" then
                local maxXZ = math.max(size.X, size.Z)
                local minXZ = math.max(0.01, math.min(size.X, size.Z))
                if math.abs(size.X - size.Y) < 0.35 * math.max(size.X, size.Y)
                    and math.abs(size.Y - size.Z) < 0.35 * math.max(size.Y, size.Z) then
                    part.Shape = Enum.PartType.Ball
                elseif maxXZ / minXZ < 1.25 and size.Y > maxXZ * 1.65 then
                    part.Shape = Enum.PartType.Cylinder
                end
            end
        end
        part.Name = name
        part.Size = size
        part.Position = position
        part.Anchored = true
        part.CanCollide = not noCollide
        part.CanTouch = false
        part.CanQuery = false
        part.CastShadow = true
        part.Color = inferredColor(name, f[6], position)
        part.Material = inferredMaterial(name, f[6], position)
        part.TopSurface = Enum.SurfaceType.Smooth
        part.BottomSurface = Enum.SurfaceType.Smooth
        part.Parent = group
        builtParts += 1
        if builtParts % CONFIG.MapBuildYieldEvery == 0 then task.wait() end
    end
end

print("[StealAnEgg Rebuild] Reconstructed " .. builtParts .. " visible map parts from source positions/sizes.")

-- Known pet names surfaced by the uploaded snapshot. Pet meshes were not supplied, so the game uses procedural pet models.
local PET_POOLS = {
    ["Forest"] = {"Whiskers", "Pegasus", "Crowshade"},
    ["Lake"] = {"Jellyfish", "Shelltide Voyager", "Moon Whale"},
    ["Desert"] = {"Scarecrow", "Haunted Scorpio", "Chest Monster", "Hollowbat"},
    ["Jungle"] = {"World Spirit", "Rotshroom", "Cursed Plant"},
    ["Snow"] = {"Pegasus", "Moon Whale", "Starry Fox"},
    ["Volcano"] = {"Frankenstein Kong", "CandyCorn", "Candlefang", "Jesterpop", "Ghost Reaper"},
    ["Abyss Ocean"] = {"Jellyfish", "Shelltide Voyager", "Moon Whale"},
    ["Prehistoric"] = {"Chest Monster", "Skeleton Mage", "Frankenstein Kong", "Graveyard Golem", "Wolf"},
    ["Cosmic"] = {"Cosmos Fox", "Cosmos Lion", "Starry Fox", "Royal Skywhale"},
    ["Cherry Blossom"] = {"Petal Beetle", "Prism Gecko", "Cosmos Fox"},
    ["Titan Temple"] = {"Archangel", "World Spirit", "Royal Skywhale"},
    ["Light Dark"] = {"Light 3", "Dark 5", "BloodBloom"},
    ["Enchanted Forest"] = {"Petal Beetle", "Prism Gecko", "Starry Fox", "Cosmos Fox", "Cosmos Lion", "Pumpkin Golem", "Hollowbat"},
}
local RARITY = {
    Common = {multiplier = 1, color = Color3.fromRGB(224, 224, 224), weight = 60},
    Rare = {multiplier = 2.4, color = Color3.fromRGB(83, 174, 255), weight = 25},
    Epic = {multiplier = 6, color = Color3.fromRGB(184, 99, 255), weight = 10},
    Legendary = {multiplier = 16, color = Color3.fromRGB(255, 190, 61), weight = 4},
    Mythic = {multiplier = 45, color = Color3.fromRGB(255, 91, 120), weight = 1},
}
local MUTATIONS = {
    Normal = {multiplier = 1, color = nil},
    Golden = {multiplier = 2.2, color = Color3.fromRGB(255, 207, 57)},
    Rainbow = {multiplier = 3.5, color = Color3.fromRGB(255, 111, 224)},
    Void = {multiplier = 5, color = Color3.fromRGB(83, 65, 130)},
}

local function rollRarity(zoneIndex, luck)
    local r = RANDOM:NextNumber()
    local boost = math.clamp((zoneIndex - 1) * 0.006 + (luck and 0.08 or 0), 0, 0.18)
    if r < 0.01 + boost * 0.12 then return "Mythic" end
    if r < 0.05 + boost * 0.25 then return "Legendary" end
    if r < 0.15 + boost * 0.45 then return "Epic" end
    if r < 0.40 + boost * 0.65 then return "Rare" end
    return "Common"
end

local function rollMutation(luck)
    local r = RANDOM:NextNumber()
    if r < (luck and 0.012 or 0.004) then return "Void" end
    if r < (luck and 0.04 or 0.015) then return "Rainbow" end
    if r < (luck and 0.11 or 0.05) then return "Golden" end
    return "Normal"
end

local function rollPet(zone, eggRarity, luck, rebirths)
    local pool = PET_POOLS[zone.name] or PET_POOLS.Forest
    local petName = pool[RANDOM:NextInteger(1, #pool)]
    local rarity = eggRarity
    if rarity == "Common" and RANDOM:NextNumber() < 0.16 then rarity = "Rare" end
    if rarity == "Rare" and RANDOM:NextNumber() < 0.10 then rarity = "Epic" end
    if zone.index >= 10 and RANDOM:NextNumber() < 0.05 then rarity = "Legendary" end
    local mutation = rollMutation(luck)
    local zoneMultiplier = 1 + (zone.index - 1) * 0.55
    local income = math.floor(2.5 * zoneMultiplier * RARITY[rarity].multiplier * MUTATIONS[mutation].multiplier )
    return {name = petName, zone = zone.name, rarity = rarity, mutation = mutation, income = math.max(1, income)}
end

local function rollEgg(zone, luck)
    local rarity = rollRarity(zone.index, luck)
    local rarityValue = ({Common = 1, Rare = 2, Epic = 4, Legendary = 8, Mythic = 16})[rarity]
    return {
        id = HttpService:GenerateGUID(false),
        name = zone.name .. " Egg",
        zone = zone.name,
        zoneIndex = zone.index,
        rarity = rarity,
        value = math.floor(25 * zone.index * rarityValue),
        hatchSeconds = CONFIG.HatchSecondsBase + zone.index * 4 + rarityValue * 2,
    }
end

local function petColor(pet)
    local mutation = MUTATIONS[pet.mutation or "Normal"]
    if mutation and mutation.color then return mutation.color end
    local rarity = RARITY[pet.rarity or "Common"]
    return rarity and rarity.color or Color3.fromRGB(200, 210, 220)
end

local function makeEggVisual(parent, position, eggData, anchored)
    local model = Instance.new("Model")
    model.Name = "Egg_" .. tostring(eggData.rarity or "Common")
    model.Parent = parent
    local shell = makePart(model, "EggShell", Vector3.new(2.5, 3.3, 2.5), CFrame.new(position),
        RARITY[eggData.rarity or "Common"].color, Enum.Material.SmoothPlastic, anchored ~= false, false)
    shell.Shape = Enum.PartType.Ball
    shell.CanTouch = false
    shell.CanCollide = false
    shell.Massless = true
    model.PrimaryPart = shell
    billboard(shell, (eggData.rarity or "Common") .. " • " .. (eggData.name or "Egg"), Color3.new(1,1,1), UDim2.fromOffset(190, 42))
    return model, shell
end

local function makePetVisual(parent, position, petData, anchored)
    local model = Instance.new("Model")
    model.Name = "Pet_" .. tostring(petData.name):gsub("%W", "")
    model.Parent = parent
    local color = petColor(petData)
    local canAnchor = anchored ~= false
    local body = makePart(model, "Body", Vector3.new(2.8, 2.2, 2.4), CFrame.new(position), color,
        Enum.Material.SmoothPlastic, canAnchor, false)
    body.Shape = Enum.PartType.Ball
    body.CanTouch = false
    body.CanCollide = false
    body.Massless = true
    model.PrimaryPart = body
    local head = makePart(model, "Head", Vector3.new(1.65, 1.5, 1.5), CFrame.new(position + Vector3.new(0, 0.8, -0.75)), color,
        Enum.Material.SmoothPlastic, canAnchor, false)
    head.Shape = Enum.PartType.Ball
    head.CanTouch = false; head.CanCollide = false; head.Massless = true
    local eyeColor = Color3.fromRGB(28, 30, 40)
    for side = -1, 1, 2 do
        local eye = makePart(model, "Eye", Vector3.new(0.22, 0.25, 0.12),
            CFrame.new(position + Vector3.new(side * 0.38, 0.96, -1.43)), eyeColor, Enum.Material.SmoothPlastic, canAnchor, false)
        eye.CanCollide = false; eye.CanTouch = false; eye.Massless = true
        local ear = makePart(model, "Ear", Vector3.new(0.38, 0.85, 0.32),
            CFrame.new(position + Vector3.new(side * 0.48, 1.78, -0.66)) * CFrame.Angles(0, 0, math.rad(side * -12)), color,
            Enum.Material.SmoothPlastic, canAnchor, false)
        ear.CanCollide = false; ear.CanTouch = false; ear.Massless = true
    end
    local tail = makePart(model, "Tail", Vector3.new(0.65, 0.65, 1.15),
        CFrame.new(position + Vector3.new(0, 0.25, 1.35)), color, Enum.Material.SmoothPlastic, canAnchor, false)
    tail.Shape = Enum.PartType.Ball; tail.CanCollide = false; tail.CanTouch = false; tail.Massless = true
    if not canAnchor then
        for _, child in ipairs(model:GetChildren()) do
            if child:IsA("BasePart") and child ~= body then
                local weld = Instance.new("WeldConstraint")
                weld.Part0 = body; weld.Part1 = child; weld.Parent = body
            end
        end
    end
    local labelColor = color
    billboard(body, (petData.mutation and petData.mutation ~= "Normal" and petData.mutation .. " " or "") .. petData.name .. "\n" .. petData.rarity,
        labelColor, UDim2.fromOffset(190, 52))
    return model, body
end

local playerData = {}
local baseByPlayer = {}
local baseByModel = {}
local fieldEggState = {}
local stealCooldowns = {}
local shieldCooldowns = {}
local noticeCounters = {}
local mountedVisuals = {}
local plotById = {}

local function dataFor(player) return playerData[player] end
local function cashValue(player)
    local stats = player:FindFirstChild("leaderstats")
    return stats and stats:FindFirstChild("Cash")
end
local function speedValue(player)
    local stats = player:FindFirstChild("leaderstats")
    return stats and stats:FindFirstChild("Speed")
end
local function rebirthValue(player)
    local stats = player:FindFirstChild("leaderstats")
    return stats and stats:FindFirstChild("Rebirths")
end
local function notify(player, message)
    local pg = player:FindFirstChildOfClass("PlayerGui")
    local gui = pg and pg:FindFirstChild("EggRushHUD")
    local label = gui and gui:FindFirstChild("Notice", true)
    if not label then return end
    noticeCounters[player] = (noticeCounters[player] or 0) + 1
    local token = noticeCounters[player]
    label.Text = tostring(message)
    label.Visible = true
    task.delay(3, function()
        if label and label.Parent and noticeCounters[player] == token then label.Visible = false end
    end)
end

local function getPlayerZone(player)
    local character = player.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    if not root then return BIOMES[1] end
    return biomeAtX(root.Position.X)
end

local function createHUD(player)
    local gui = Instance.new("ScreenGui")
    gui.Name = "EggRushHUD"
    gui.ResetOnSpawn = false
    gui.DisplayOrder = 20
    gui.Parent = player:WaitForChild("PlayerGui")
    local panel = Instance.new("Frame")
    panel.Name = "MainPanel"
    panel.Size = UDim2.new(0, 330, 0, 162)
    panel.Position = UDim2.new(0, 12, 0, 12)
    panel.BackgroundColor3 = Color3.fromRGB(21, 25, 39)
    panel.BackgroundTransparency = 0.08
    panel.BorderSizePixel = 0
    panel.Parent = gui
    local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(0, 12); corner.Parent = panel
    local stroke = Instance.new("UIStroke"); stroke.Color = Color3.fromRGB(100, 130, 185); stroke.Transparency = 0.25; stroke.Parent = panel
    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, -20, 0, 27); title.Position = UDim2.fromOffset(10, 5)
    title.BackgroundTransparency = 1; title.Font = Enum.Font.GothamBlack; title.TextSize = 19
    title.TextXAlignment = Enum.TextXAlignment.Left; title.TextColor3 = Color3.fromRGB(255, 217, 91)
    title.Text = "🥚 STEAL AN EGG"; title.Parent = panel
    local stats = Instance.new("TextLabel")
    stats.Name = "Stats"; stats.Size = UDim2.new(1, -20, 0, 100); stats.Position = UDim2.fromOffset(10, 34)
    stats.BackgroundTransparency = 1; stats.Font = Enum.Font.GothamSemibold; stats.TextSize = 14
    stats.TextXAlignment = Enum.TextXAlignment.Left; stats.TextYAlignment = Enum.TextYAlignment.Top
    stats.TextColor3 = Color3.fromRGB(239, 243, 255); stats.TextWrapped = true; stats.Parent = panel
    local help = Instance.new("TextLabel")
    help.Size = UDim2.new(1, -20, 0, 19); help.Position = UDim2.fromOffset(10, 139)
    help.BackgroundTransparency = 1; help.Font = Enum.Font.Gotham; help.TextSize = 11
    help.TextXAlignment = Enum.TextXAlignment.Left; help.TextColor3 = Color3.fromRGB(173, 188, 215)
    help.Text = "Pick up field eggs • Hatch at your plot • Protect your pets"; help.Parent = panel
    local notice = Instance.new("TextLabel")
    notice.Name = "Notice"; notice.Size = UDim2.new(0, 440, 0, 44)
    notice.Position = UDim2.new(0.5, -220, 0, 12); notice.BackgroundColor3 = Color3.fromRGB(22, 25, 39)
    notice.BackgroundTransparency = 0.04; notice.BorderSizePixel = 0; notice.Visible = false
    notice.Font = Enum.Font.GothamBold; notice.TextSize = 17; notice.TextColor3 = Color3.fromRGB(255, 230, 140)
    notice.TextWrapped = true; notice.Parent = gui
    local noticeCorner = Instance.new("UICorner"); noticeCorner.CornerRadius = UDim.new(0, 10); noticeCorner.Parent = notice
    task.spawn(function()
        while player.Parent and gui.Parent do
            local d = dataFor(player)
            if d then
                local eggs = #d.eggInventory + (d.carryEgg and 1 or 0)
                local pets = #d.petInventory
                local zone = getPlayerZone(player)
                local petPreview = {}
                for i = 1, math.min(2, #d.petInventory) do
                    table.insert(petPreview, d.petInventory[i].name or "Pet")
                end
                local previewText = #petPreview > 0 and table.concat(petPreview, ", ") or "None"
                stats.Text = string.format("Cash: $%s\nSpeed: %d   Rebirths: %d\nEggs: %d   Pets: %d   Zone: %s\nCarrying: %s\nCollection: %s",
                    tostring((cashValue(player) and cashValue(player).Value) or 0),
                    (speedValue(player) and speedValue(player).Value) or 16,
                    (rebirthValue(player) and rebirthValue(player).Value) or 0,
                    eggs, pets, zone.name, d.carryEgg and d.carryEgg.name or "Nothing", previewText)
            end
            task.wait(0.5)
        end
    end)
end

local function applyPlayerSpeed(player)
    local data = dataFor(player)
    local character = player.Character
    local hum = character and character:FindFirstChildOfClass("Humanoid")
    if data and hum then hum.WalkSpeed = math.clamp(data.speed or CONFIG.StartingWalkSpeed, 16, 100) end
end

local function carryVisual(player)
    local d = dataFor(player)
    if not d or not d.carryEgg or not player.Character then return end
    local root = player.Character:FindFirstChild("HumanoidRootPart")
    if not root then return end
    local oldCarry = player.Character:FindFirstChild("CarriedEggVisual")
    if oldCarry then oldCarry:Destroy() end
    local model, shell = makeEggVisual(player.Character, root.Position + Vector3.new(0, 0.2, -2.4), d.carryEgg, false)
    model.Name = "CarriedEggVisual"
    shell.Anchored = false
    local weld = Instance.new("WeldConstraint")
    weld.Part0 = root; weld.Part1 = shell; weld.Parent = shell
end

local function clearCarryVisual(player)
    local char = player.Character
    local model = char and char:FindFirstChild("CarriedEggVisual")
    if model then model:Destroy() end
end

local function giveCash(player, amount)
    local cash = cashValue(player)
    if cash then cash.Value = math.max(0, cash.Value + math.floor(amount)) end
end

local function petInventoryValue(pet)
    local base = math.max(10, (pet.income or 1) * 30)
    return math.floor(base * 0.7)
end

local function removeSlotVisual(slotState)
    if slotState and slotState.visual and slotState.visual.Parent then slotState.visual:Destroy() end
    slotState.visual = nil
end

local function plotLabel(base, text)
    if base.ownerLabel then base.ownerLabel.Text = text end
end

local function freeSlot(base)
    for _, slot in ipairs(base.slots) do if not slot.data then return slot end end
    return nil
end

local function updatePromptForSlot(base, slot)
    local d = slot.data
    if not d then
        slot.prompt.ActionText = "Place Egg"
        slot.prompt.ObjectText = "Empty Egg Stand"
    elseif d.kind == "Egg" then
        slot.prompt.ActionText = base.owner and "Collect / Cancel Egg" or "Steal Egg"
        slot.prompt.ObjectText = d.egg.name .. " • " .. d.egg.rarity
    elseif d.kind == "Pet" then
        slot.prompt.ActionText = base.owner and "Collect Pet" or "Steal Pet"
        slot.prompt.ObjectText = d.pet.name .. " • " .. d.pet.rarity
    end
end

local function hatchIfReady(base, slot)
    if not slot.data or slot.data.kind ~= "Egg" then return end
    local eggState = slot.data
    if os.time() < (eggState.hatchAt or 0) then return end
    slot.data = {kind = "Pet", pet = deepCopy(eggState.hatchResult)}
    removeSlotVisual(eggState)
    local pos = slot.pad.Position + Vector3.new(0, 2.4, 0)
    local visual = makePetVisual(slot.pad, pos, slot.data.pet, true)
    slot.data.visual = visual
    updatePromptForSlot(base, slot)
    if base.owner then notify(base.owner, "Hatched: " .. slot.data.pet.name .. "!") end
end

local function renderSlot(base, slot)
    removeSlotVisual(slot.data)
    if not slot.data then
        updatePromptForSlot(base, slot)
        return
    end
    if slot.data.kind == "Egg" then
        local p = slot.pad.Position + Vector3.new(0, 2.0, 0)
        local eggModel = makeEggVisual(slot.pad, p, slot.data.egg, true)
        slot.data.visual = eggModel
        local remaining = math.max(0, (slot.data.hatchAt or os.time()) - os.time())
        if remaining <= 0 then task.defer(hatchIfReady, base, slot) end
        updatePromptForSlot(base, slot)
    elseif slot.data.kind == "Pet" then
        slot.data.visual = makePetVisual(slot.pad, slot.pad.Position + Vector3.new(0, 2.4, 0), slot.data.pet, true)
        updatePromptForSlot(base, slot)
    end
end

local function setCarry(player, eggData)
    local d = dataFor(player)
    if not d then return false end
    if d.carryEgg then notify(player, "You are already carrying an egg."); return false end
    d.carryEgg = deepCopy(eggData)
    carryVisual(player)
    return true
end

local function clearCarry(player)
    local d = dataFor(player)
    if not d then return end
    d.carryEgg = nil
    clearCarryVisual(player)
end

local function getOrCreatePlotFolder(id)
    local f = Instance.new("Folder")
    f.Name = "PlotRuntime_" .. id
    f.Parent = baseFolder
    return f
end

local function mountBestPet(player)
    local d = dataFor(player)
    if not d then return end
    local existing = mountedVisuals[player]
    if existing and existing.Parent then
        existing:Destroy(); mountedVisuals[player] = nil; d.mountedPet = nil
        notify(player, "Pet unmounted.")
        return
    end
    if not d.mountedPet then
        local best
        for _, pet in ipairs(d.petInventory) do
            if not best or (pet.income or 0) > (best.income or 0) then best = pet end
        end
        if not best then notify(player, "Collect or hatch a pet first."); return end
        d.mountedPet = deepCopy(best)
    end
    local character = player.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    if not root then return end
    local model, body = makePetVisual(character, root.Position + Vector3.new(2, 1, 3), d.mountedPet, false)
    model.Name = "MountedPetVisual"
    body.Anchored = false
    body.CanCollide = false
    body.Massless = true
    local weld = Instance.new("Weld")
    weld.Part0 = root; weld.Part1 = body
    weld.C0 = CFrame.new(2.5, 1.0, 3.2)
    weld.Parent = body
    mountedVisuals[player] = model
    notify(player, "Mounted " .. d.mountedPet.name .. ".")
end

local function createBase(id)
    local info = PLOTS[id]
    local folder = getOrCreatePlotFolder(id)
    local base = {id = id, info = info, folder = folder, owner = nil, shield = true, slots = {}, lastShieldToggle = 0}
    baseByModel[folder] = base
    local signAnchor = makeAnchor(folder, "OwnerSign", info.sign + Vector3.new(0, 1, 0))
    base.ownerLabel = billboard(signAnchor, "UNCLAIMED PLOT " .. id, Color3.fromRGB(255, 255, 255), UDim2.fromOffset(260, 56))
    local shieldVisual = makePart(folder, "ShieldVisual", Vector3.new(2, 14, info.petSizeZ + 8),
        CFrame.new(info.center.X + 25, info.center.Y + 7, info.center.Z),
        Color3.fromRGB(80, 205, 255), Enum.Material.ForceField, true, false)
    shieldVisual.Transparency = 0.78
    base.shieldVisual = shieldVisual

    -- Six collection/hatching pads placed inside the real PetArea footprint.
    local width = info.petSizeX
    local xOffsets = {-width * 0.30, 0, width * 0.30}
    local zOffsets = {-info.petSizeZ * 0.22, info.petSizeZ * 0.22}
    local index = 0
    for row = 1, 2 do
        for col = 1, 3 do
            index += 1
            local pos = info.petCenter + Vector3.new(xOffsets[col], 1.1, zOffsets[row])
            local pad = makePart(folder, "EggPetSlot_" .. index, Vector3.new(7.2, 0.7, 7.2),
                CFrame.new(pos), Color3.fromRGB(48, 55, 74), Enum.Material.Metal, true, true)
            local rim = makePart(folder, "SlotRim_" .. index, Vector3.new(7.6, 0.18, 7.6),
                CFrame.new(pos + Vector3.new(0, 0.42, 0)), Color3.fromRGB(255, 198, 80), Enum.Material.Neon, true, false)
            rim.Transparency = 0.2
            local pr = prompt(pad, "Place Egg", "Empty Egg Stand", 0.35, 11)
            local slot = {index = index, pad = pad, prompt = pr, data = nil, base = base}
            table.insert(base.slots, slot)
            pr.Triggered:Connect(function(player)
                local d = dataFor(player)
                if not d then return end
                if base.owner == player then
                    hatchIfReady(base, slot)
                    if not slot.data then
                        if d.carryEgg then
                            local egg = deepCopy(d.carryEgg)
                            clearCarry(player)
                            local pet = rollPet(BIOMES[egg.zoneIndex] or BIOMES[1], egg.rarity, (d.luckUntil or 0) > os.time(), d.rebirths)
                            slot.data = {
                                kind = "Egg", egg = egg,
                                hatchAt = os.time() + egg.hatchSeconds,
                                hatchResult = pet,
                            }
                            renderSlot(base, slot)
                            notify(player, "Egg placed! Hatch in " .. egg.hatchSeconds .. " seconds.")
                        elseif #d.eggInventory > 0 then
                            local egg = table.remove(d.eggInventory, 1)
                            local pet = rollPet(BIOMES[egg.zoneIndex] or BIOMES[1], egg.rarity, (d.luckUntil or 0) > os.time(), d.rebirths)
                            slot.data = {kind = "Egg", egg = egg, hatchAt = os.time() + egg.hatchSeconds, hatchResult = pet}
                            renderSlot(base, slot)
                            notify(player, "Incubating " .. egg.name .. ".")
                        else
                            notify(player, "Pick up a field egg first.")
                        end
                    elseif slot.data.kind == "Egg" then
                        if d.carryEgg then notify(player, "Hands full. Return your carried egg first."); return end
                        local egg = deepCopy(slot.data.egg)
                        removeSlotVisual(slot.data); slot.data = nil
                        setCarry(player, egg); updatePromptForSlot(base, slot)
                        notify(player, "Egg collected. Bring it back when ready.")
                    elseif slot.data.kind == "Pet" then
                        if #d.petInventory >= CONFIG.MaxPetInventory then notify(player, "Pet inventory is full."); return end
                        table.insert(d.petInventory, deepCopy(slot.data.pet))
                        local petName = slot.data.pet.name
                        removeSlotVisual(slot.data); slot.data = nil
                        updatePromptForSlot(base, slot)
                        notify(player, "Collected " .. petName .. " into pet inventory.")
                    end
                else
                    if not base.owner then notify(player, "This plot is unclaimed."); return end
                    if base.shield then notify(player, "That plot shield is active!"); return end
                    local now = os.clock()
                    if stealCooldowns[player] and now - stealCooldowns[player] < CONFIG.StealCooldown then
                        notify(player, "Steal cooldown: " .. math.ceil(CONFIG.StealCooldown - (now - stealCooldowns[player])) .. "s"); return
                    end
                    if not slot.data then notify(player, "This stand is empty."); return end
                    if slot.data.kind == "Egg" then
                        if d.carryEgg then notify(player, "You are already carrying an egg."); return end
                        local egg = deepCopy(slot.data.egg)
                        removeSlotVisual(slot.data); slot.data = nil
                        updatePromptForSlot(base, slot)
                        setCarry(player, egg)
                        stealCooldowns[player] = now
                        notify(player, "Egg stolen! Escape back to your plot.")
                        notify(base.owner, player.Name .. " stole one of your eggs!")
                    else
                        if #d.petInventory >= CONFIG.MaxPetInventory then notify(player, "Pet inventory is full."); return end
                        local pet = deepCopy(slot.data.pet)
                        removeSlotVisual(slot.data); slot.data = nil
                        updatePromptForSlot(base, slot)
                        table.insert(d.petInventory, pet)
                        stealCooldowns[player] = now
                        notify(player, "Stole " .. pet.name .. "!")
                        notify(base.owner, player.Name .. " stole your " .. pet.name .. "!")
                    end
                end
            end)
        end
    end

    local boardAnchor = makeAnchor(folder, "PetManagementBoard", info.center + Vector3.new(0, 3, 0))
    local board = makePart(folder, "PetManagementBoardVisual", Vector3.new(7, 5, 1),
        CFrame.new(info.center + Vector3.new(0, 2.7, 0)), Color3.fromRGB(55, 79, 125), Enum.Material.Wood, true, true)
    billboard(board, "PET MANAGEMENT", Color3.fromRGB(255, 235, 151), UDim2.fromOffset(190, 42))
    local petPrompt = prompt(board, "Place Best Pet", "Pet Inventory", 0.3, 12)
    petPrompt.Triggered:Connect(function(player)
        if base.owner ~= player then notify(player, "This isn't your plot."); return end
        local d = dataFor(player)
        if not d then return end
        local free = freeSlot(base)
        if not free then notify(player, "All six stands are occupied."); return end
        if #d.petInventory == 0 then
            notify(player, "Your pet inventory is empty.")
            return
        end
        table.sort(d.petInventory, function(a, b) return (a.income or 0) > (b.income or 0) end)
        local pet = table.remove(d.petInventory, 1)
        free.data = {kind = "Pet", pet = deepCopy(pet)}
        renderSlot(base, free)
        notify(player, "Placed " .. pet.name .. ". It now earns cash.")
    end)
    local mountPrompt = prompt(board, "Mount / Unmount Best Pet", "Pet Mount", 0.3, 12)
    mountPrompt.Triggered:Connect(function(player)
        if base.owner ~= player then notify(player, "This isn't your plot."); return end
        mountBestPet(player)
    end)

    -- Shield toggle is attached to the original plot's front edge, relative to its marker.
    local shieldAnchor = makeAnchor(folder, "ShieldPromptAnchor", info.center + Vector3.new(25, 4, 0))
    local shieldPrompt = prompt(shieldAnchor, "Disable Shield", "Plot Protection", 0.4, 12)
    shieldPrompt.Triggered:Connect(function(player)
        if base.owner ~= player then notify(player, "Only the plot owner can control the shield."); return end
        local now = os.clock()
        if now - (shieldCooldowns[player] or 0) < CONFIG.ShieldToggleCooldown then
            notify(player, "Wait before toggling the shield again."); return
        end
        shieldCooldowns[player] = now
        base.shield = not base.shield
        base.shieldVisual.Transparency = base.shield and 0.45 or 0.9
        shieldPrompt.ActionText = base.shield and "Disable Shield" or "Enable Shield"
        notify(player, base.shield and "Plot shield enabled." or "Plot shield disabled. Your pets can be stolen!")
    end)

    -- The source plot has a real treadmill marker; its exact position is used here.
    local treadmillAnchor = makeAnchor(folder, "TreadmillPromptAnchor", info.treadmill + Vector3.new(0, 3, 0))
    local treadmillPrompt = prompt(treadmillAnchor, "Train +2 Speed", "Treadmill Upgrade", 0.5, 12)
    treadmillPrompt.Triggered:Connect(function(player)
        if base.owner ~= player then notify(player, "Use the treadmill at your own plot."); return end
        local d = dataFor(player); local cash = cashValue(player)
        if not d or not cash then return end
        local nextSpeed = d.speed + 2
        local price = math.floor(150 + (d.speed - CONFIG.StartingWalkSpeed) * 95 + d.rebirths * 250)
        if cash.Value < price then notify(player, "Need $" .. price .. " for the next speed upgrade."); return end
        cash.Value -= price; d.speed = nextSpeed
        local sv = speedValue(player); if sv then sv.Value = nextSpeed end
        applyPlayerSpeed(player)
        notify(player, "Speed upgraded to " .. nextSpeed .. "!")
    end)

    return base
end

for id = 1, 7 do plotById[id] = createBase(id) end

local function assignBase(player, preferredId)
    if preferredId and plotById[preferredId] and not plotById[preferredId].owner then
        local base = plotById[preferredId]
        base.owner = player; baseByPlayer[player] = base
        plotLabel(base, player.DisplayName .. "'s PLOT")
        base.shield = true; base.shieldVisual.Transparency = 0.45
        return base
    end
    for id = 1, 7 do
        local base = plotById[id]
        if not base.owner then
            base.owner = player; baseByPlayer[player] = base
            plotLabel(base, player.DisplayName .. "'s PLOT")
            base.shield = true; base.shieldVisual.Transparency = 0.45
            return base
        end
    end
    return nil
end

local function savePayload(player)
    local d = dataFor(player)
    if not d then return nil end
    local slots = {}
    local base = baseByPlayer[player]
    if base then
        for i, slot in ipairs(base.slots) do
            if slot.data then
                hatchIfReady(base, slot)
                slots[i] = deepCopy(slot.data)
                slots[i].visual = nil
            end
        end
    end
    local cash = cashValue(player)
    return {
        version = 1,
        cash = cash and cash.Value or d.cash or CONFIG.StartingCash,
        speed = d.speed,
        rebirths = d.rebirths,
        eggInventory = d.eggInventory,
        petInventory = d.petInventory,
        carryEgg = d.carryEgg,
        slots = slots,
        preferredPlot = base and base.id or d.preferredPlot,
        lastSaved = os.time(),
        lastDaily = d.lastDaily or 0,
        luckUntil = d.luckUntil or 0,
        mountedPet = d.mountedPet,
    }
end

local function savePlayer(player)
    local payload = savePayload(player)
    if not payload then return false end
    local key = "player_" .. player.UserId
    local ok, err = pcall(function()
        DATASTORE:UpdateAsync(key, function() return payload end)
    end)
    if not ok then warn("[StealAnEgg Rebuild] Save failed for " .. player.Name .. ": " .. tostring(err)) end
    return ok
end

local function loadPlayer(player)
    local result
    local ok, err = pcall(function() result = DATASTORE:GetAsync("player_" .. player.UserId) end)
    if not ok then warn("[StealAnEgg Rebuild] Load failed for " .. player.Name .. ": " .. tostring(err)) end
    if type(result) ~= "table" then return {
        cash = CONFIG.StartingCash, speed = CONFIG.StartingWalkSpeed, rebirths = 0,
        eggInventory = {}, petInventory = {}, carryEgg = nil, slots = {}, preferredPlot = nil,
        lastDaily = 0, luckUntil = 0, mountedPet = nil,
    } end
    local d = {
        cash = safeNumber(result.cash, CONFIG.StartingCash, 0, 2^31 - 1),
        speed = safeNumber(result.speed, CONFIG.StartingWalkSpeed, 16, 100),
        rebirths = safeNumber(result.rebirths, 0, 0, 100000),
        eggInventory = type(result.eggInventory) == "table" and result.eggInventory or {},
        petInventory = type(result.petInventory) == "table" and result.petInventory or {},
        carryEgg = type(result.carryEgg) == "table" and result.carryEgg or nil,
        slots = type(result.slots) == "table" and result.slots or {},
        preferredPlot = tonumber(result.preferredPlot),
        lastDaily = safeNumber(result.lastDaily, 0, 0, os.time()),
        luckUntil = safeNumber(result.luckUntil, 0, 0, os.time() + 86400),
        mountedPet = type(result.mountedPet) == "table" and result.mountedPet or nil,
    }
    -- Offline earnings are capped and discounted to avoid runaway progression.
    local elapsed = math.clamp(os.time() - safeNumber(result.lastSaved, os.time(), 0, os.time()), 0, CONFIG.MaxOfflineHours * 3600)
    local offlineRate = 0
    for _, slot in pairs(d.slots) do
        if type(slot) == "table" then
            if slot.kind == "Egg" and (slot.hatchAt or 0) <= os.time() then
                slot = {kind = "Pet", pet = slot.hatchResult}
            end
            if slot.kind == "Pet" and type(slot.pet) == "table" then offlineRate += (slot.pet.income or 0) / CONFIG.IncomeTickSeconds end
        end
    end
    d.cash += math.floor(offlineRate * elapsed * CONFIG.OfflineIncomeRate * (1 + d.rebirths * 0.25))
    return d
end

local function renderLoadedBase(player, base, d)
    for i, slot in ipairs(base.slots) do
        local saved = d.slots[i]
        if type(saved) == "table" then
            if saved.kind == "Egg" and (saved.hatchAt or 0) <= os.time() and type(saved.hatchResult) == "table" then
                saved = {kind = "Pet", pet = saved.hatchResult}
            end
            slot.data = deepCopy(saved)
            renderSlot(base, slot)
            if slot.data.kind == "Egg" then
                local waitTime = math.max(0, slot.data.hatchAt - os.time())
                task.delay(waitTime, function()
                    if slot.data and slot.data.kind == "Egg" then hatchIfReady(base, slot) end
                end)
            end
        end
    end
end

local function createSellStand()
    local pos = Vector3.new(532.15, 67.8, -425.33) -- exact SellPrompt pad position in workspace.txt
    local anchor = makeAnchor(systemFolder, "SellStandAnchor", pos + Vector3.new(0, 2.5, 0))
    local labelPart = makePart(systemFolder, "SellStand", Vector3.new(7, 5, 3), CFrame.new(pos + Vector3.new(0, 2.5, 0)),
        Color3.fromRGB(58, 138, 111), Enum.Material.SmoothPlastic, true, true)
    billboard(labelPart, "SELL PETS", Color3.fromRGB(245, 255, 210))
    local pr = prompt(anchor, "Sell Pet Inventory", "Pet Seller", 0.5, 14)
    pr.Triggered:Connect(function(player)
        local d = dataFor(player)
        if not d then return end
        if #d.petInventory == 0 then notify(player, "No pets in your inventory to sell."); return end
        local earned = 0
        for _, pet in ipairs(d.petInventory) do earned += petInventoryValue(pet) end
        local count = #d.petInventory
        table.clear(d.petInventory)
        giveCash(player, earned)
        notify(player, "Sold " .. count .. " pets for $" .. earned .. ".")
    end)
end
createSellStand()

local function createHubPrompts()
    -- These stand positions are taken from the uploaded Stands.Pads entries.
    local trailPos = Vector3.new(531.23, 67.8, -307.1)
    local trail = makeAnchor(systemFolder, "TrailShopAnchor", trailPos + Vector3.new(0, 2, 0))
    billboard(trail, "LUCKY TRAIL SHOP", Color3.fromRGB(255, 224, 134))
    prompt(trail, "Buy 10m Luck Boost ($2,000)", "Trail Shop", 0.5, 12).Triggered:Connect(function(player)
        local cash = cashValue(player); local d = dataFor(player)
        if not cash or not d then return end
        if cash.Value < 2000 then notify(player, "Need $2,000 for a Luck Boost."); return end
        cash.Value -= 2000; d.luckUntil = os.time() + 600
        notify(player, "Luck Boost active for 10 minutes!")
    end)
    local rewardPos = Vector3.new(544.36, 67.8, -288.49)
    local reward = makeAnchor(systemFolder, "GroupRewardAnchor", rewardPos + Vector3.new(0, 2, 0))
    billboard(reward, "DAILY REWARD", Color3.fromRGB(255, 235, 130))
    prompt(reward, "Claim Daily $1,000", "Daily Reward", 0.5, 12).Triggered:Connect(function(player)
        local d = dataFor(player)
        if not d then return end
        local now = os.time()
        if now - (d.lastDaily or 0) < 86400 then
            notify(player, "Daily reward available in " .. math.ceil((86400 - (now - d.lastDaily)) / 3600) .. "h.")
            return
        end
        d.lastDaily = now; giveCash(player, 1000 + d.rebirths * 250)
        notify(player, "Daily reward claimed!")
    end)
    local rebirth = makePart(systemFolder, "RebirthAltar", Vector3.new(10, 2, 10),
        CFrame.new(548, 68, -365), Color3.fromRGB(143, 80, 210), Enum.Material.Neon, true, true)
    billboard(rebirth, "REBIRTH ALTAR", Color3.fromRGB(236, 208, 255))
    prompt(rebirth, "Rebirth ($500,000 + 40 Speed)", "Rebirth", 1, 14).Triggered:Connect(function(player)
        local d = dataFor(player); local cash = cashValue(player); local speed = speedValue(player)
        if not d or not cash or not speed then return end
        if cash.Value < CONFIG.RebirthCash or d.speed < CONFIG.RebirthSpeed then
            notify(player, "Requires $500,000 and 40 Speed."); return
        end
        d.rebirths += 1; d.speed = CONFIG.StartingWalkSpeed; cash.Value = CONFIG.StartingCash
        speed.Value = d.speed
        local rv = rebirthValue(player); if rv then rv.Value = d.rebirths end
        applyPlayerSpeed(player)
        notify(player, "REBIRTH " .. d.rebirths .. "! Pet income multiplier increased.")
    end)
end
createHubPrompts()

local function pickupFieldEgg(state, player)
    local d = dataFor(player)
    if not d or state.taken then return end
    if d.carryEgg then notify(player, "Return your current egg to your plot first."); return end
    local zone = state.zone
    if (d.speed or CONFIG.StartingWalkSpeed) < zone.requiredSpeed then
        notify(player, zone.name .. " requires " .. zone.requiredSpeed .. " Speed."); return
    end
    state.taken = true
    if state.model and state.model.Parent then state.model:Destroy() end
    state.model = nil
    local egg = deepCopy(state.eggData)
    setCarry(player, egg)
    notify(player, "Picked up " .. egg.rarity .. " " .. egg.name .. ". Return to your plot!")
    task.delay(CONFIG.FieldEggRespawnSeconds, function()
        if not world.Parent then return end
        state.taken = false
        local newData = rollEgg(zone, false)
        local model, shell = makeEggVisual(eggFolder, state.position, newData, true)
        model.Name = "FieldEgg_" .. zone.index .. "_" .. state.id
        state.model = model; state.eggData = newData
        state.prompt = prompt(shell, "Pick Up Egg", newData.rarity .. " " .. zone.name, 0.45, 10)
        state.prompt.Triggered:Connect(function(p) pickupFieldEgg(state, p) end)
    end)
end

for index, position in ipairs(EGG_SPAWNS) do
    local zone = biomeAtX(position.X)
    local state = {id = index, position = position + Vector3.new(0, 0.9, 0), zone = zone, taken = false}
    state.eggData = rollEgg(zone, false)
    local model, shell = makeEggVisual(eggFolder, state.position, state.eggData, true)
    model.Name = "FieldEgg_" .. zone.index .. "_" .. index
    state.model = model
    state.prompt = prompt(shell, "Pick Up Egg", state.eggData.rarity .. " " .. zone.name, 0.45, 10)
    state.prompt.Triggered:Connect(function(player) pickupFieldEgg(state, player) end)
    table.insert(fieldEggState, state)
end

local function createLeaderstats(player, d)
    local stats = Instance.new("Folder"); stats.Name = "leaderstats"; stats.Parent = player
    local cash = Instance.new("IntValue"); cash.Name = "Cash"; cash.Value = d.cash; cash.Parent = stats
    local speed = Instance.new("IntValue"); speed.Name = "Speed"; speed.Value = d.speed; speed.Parent = stats
    local rebirths = Instance.new("IntValue"); rebirths.Name = "Rebirths"; rebirths.Value = d.rebirths; rebirths.Parent = stats
end

local function setupPlayer(player)
    local d = loadPlayer(player)
    playerData[player] = d
    createLeaderstats(player, d)
    createHUD(player)
    local base = assignBase(player, d.preferredPlot)
    if not base then
        notify(player, "All 7 plots are occupied. You can spectate but cannot own a plot in this server.")
    else
        renderLoadedBase(player, base, d)
    end
    player.CharacterAdded:Connect(function(character)
        task.wait(0.35)
        applyPlayerSpeed(player)
        if baseByPlayer[player] then
            local root = character:WaitForChild("HumanoidRootPart", 8)
            if root then root.CFrame = CFrame.new(baseByPlayer[player].info.spawn + Vector3.new(0, 3, 0)) end
        end
        if d.carryEgg then carryVisual(player) end
        if d.mountedPet then
            task.wait(0.3)
            local root = character:FindFirstChild("HumanoidRootPart")
            if root then
                local model, body = makePetVisual(character, root.Position + Vector3.new(2, 1, 3), d.mountedPet, false)
                model.Name = "MountedPetVisual"; body.Anchored = false
                local weld = Instance.new("Weld"); weld.Part0 = root; weld.Part1 = body; weld.C0 = CFrame.new(2.5, 1, 3.2); weld.Parent = body
                mountedVisuals[player] = model
            end
        end
    end)
    if player.Character then task.spawn(function()
        task.wait(0.4)
        local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
        if root and baseByPlayer[player] then root.CFrame = CFrame.new(baseByPlayer[player].info.spawn + Vector3.new(0, 3, 0)) end
        applyPlayerSpeed(player); if d.carryEgg then carryVisual(player) end
    end) end
    notify(player, "Welcome! Collect a field egg and bring it to an empty stand at your plot.")
    if d.cash > CONFIG.StartingCash then notify(player, "Welcome back! Offline earnings have been added.") end
end

Players.PlayerAdded:Connect(setupPlayer)
for _, player in ipairs(Players:GetPlayers()) do task.spawn(setupPlayer, player) end

-- Cash from displayed pets, paid every interval. Eggs do not generate income until hatched.
task.spawn(function()
    while world.Parent do
        task.wait(CONFIG.IncomeTickSeconds)
        for player, base in pairs(baseByPlayer) do
            local d = dataFor(player)
            local cash = cashValue(player)
            if d and cash and base then
                local income = 0
                for _, slot in ipairs(base.slots) do
                    hatchIfReady(base, slot)
                    if slot.data and slot.data.kind == "Pet" then income += (slot.data.pet.income or 0) end
                end
                if income > 0 then
                    local boost = 1 + d.rebirths * 0.25
                    cash.Value += math.floor(income * boost)
                end
            end
        end
    end
end)

-- Persist player progress periodically and when leaving.
task.spawn(function()
    while world.Parent do
        task.wait(CONFIG.AutosaveSeconds)
        for _, player in ipairs(Players:GetPlayers()) do task.spawn(savePlayer, player) end
    end
end)

Players.PlayerRemoving:Connect(function(player)
    savePlayer(player)
    local base = baseByPlayer[player]
    if base then
        for _, slot in ipairs(base.slots) do
            removeSlotVisual(slot.data); slot.data = nil
            updatePromptForSlot(base, slot)
        end
        base.owner = nil; base.shield = true; base.shieldVisual.Transparency = 0.78
        plotLabel(base, "UNCLAIMED PLOT " .. base.id)
    end
    local mount = mountedVisuals[player]
    if mount and mount.Parent then mount:Destroy() end
    mountedVisuals[player] = nil
    baseByPlayer[player] = nil
    playerData[player] = nil
    stealCooldowns[player] = nil
    shieldCooldowns[player] = nil
    noticeCounters[player] = nil
    gateDebounce[player] = nil
end)

game:BindToClose(function()
    local pending = 0
    for _, player in ipairs(Players:GetPlayers()) do
        pending += 1
        task.spawn(function()
            savePlayer(player)
            pending -= 1
        end)
    end
    local started = os.clock()
    while pending > 0 and os.clock() - started < 20 do task.wait(0.1) end
end)

print("[StealAnEgg Rebuild] Production prototype ready. Geometry=" .. builtParts .. ", plots=" .. #PLOTS .. ", biomes=" .. #BIOMES .. ", egg spawns=" .. #EGG_SPAWNS)
