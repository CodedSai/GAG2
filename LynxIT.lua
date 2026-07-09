-- RollbackControls (compact) — keeps Rollback & Cancel Rollback controls
-- Small movable/resizable GUI + Seed selector + Plant Grid Once
-- Whitelist check preserved elsewhere; drop into StarterPlayerScripts or StarterGui

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local HttpService = game:GetService("HttpService")

local player = Players.LocalPlayer
if not player then return end
local playerGui = player:WaitForChild("PlayerGui")

-- Guard / single-run
local EXISTING_NAME = "RollbackControlsGorgeous"
local RUN_ATTR = "RollbackControlsRunning"
if playerGui:GetAttribute(RUN_ATTR) then
    if playerGui:FindFirstChild(EXISTING_NAME) then return end
end
playerGui:SetAttribute(RUN_ATTR, true)

-- Helpers
local function create(class, props)
    local inst = Instance.new(class)
    if props then for k,v in pairs(props) do inst[k] = v end end
    return inst
end

local conns = {}
local function track(c) if c then table.insert(conns, c) end return c end
local function cleanup()
    for _,c in ipairs(conns) do if c and c.Connected then pcall(function() c:Disconnect() end) end end
    conns = {}
    pcall(function() playerGui:SetAttribute(RUN_ATTR, nil) end)
end

local function notify(title, text, dur, ok)
    dur = dur or 2
    local gui = create("ScreenGui",{Name="RC_Notify_"..math.random(1,9999), ResetOnSpawn=false, Parent=playerGui})
    local f = create("Frame", {Size=UDim2.new(0,260,0,66), Position=UDim2.new(1,-280,0,18), BackgroundColor3 = ok and Color3.fromRGB(30,60,30) or Color3.fromRGB(60,30,30), Parent=gui})
    create("UICorner",{CornerRadius=UDim.new(0,8), Parent=f})
    create("TextLabel",{Parent=f, Position=UDim2.new(0,8,0,6), Size=UDim2.new(1,-16,0,18), BackgroundTransparency=1, Text=title, Font=Enum.Font.GothamBold, TextSize=14, TextColor3=Color3.new(1,1,1)})
    create("TextLabel",{Parent=f, Position=UDim2.new(0,8,0,26), Size=UDim2.new(1,-16,0,34), BackgroundTransparency=1, Text=text, Font=Enum.Font.Gotham, TextSize=12, TextColor3=Color3.new(1,1,1), TextWrapped=true})
    pcall(function() TweenService:Create(f, TweenInfo.new(0.22), {Position = UDim2.new(1,-280,0,18)}):Play() end)
    delay(dur, function() if gui and gui.Parent then pcall(function() gui:Destroy() end) end end)
end

-- Remote helpers (existing behavior)
local function getPacketRemote()
    local ok, res = pcall(function()
        local sm = ReplicatedStorage:FindFirstChild("SharedModules")
        if not sm then return nil end
        local packet = sm:FindFirstChild("Packet")
        if not packet then return nil end
        return packet:FindFirstChild("RemoteEvent")
    end)
    return ok and res or nil
end
local PACKET_REMOTE = getPacketRemote()
local REMOTE_ID = 54
local function safeFire(id, payload)
    if PACKET_REMOTE then
        pcall(function() PACKET_REMOTE:FireServer(id, payload) end)
        return true
    end
    return false
end

-- SEED_PAYLOADS mapping (adjust to your game's payloads)
local SEED_PAYLOADS = {
    ["Carrot Mega"] = "PLANT:CARROT_MEGA",
    ["Carrot"] = "PLANT:CARROT",
    ["Mega Seed"] = "PLANT:MEGA_SEED",
}
local Seeds = {}
for k,_ in pairs(SEED_PAYLOADS) do table.insert(Seeds, k) end
table.sort(Seeds)
local selectedSeed = Seeds[1] or "Carrot Mega"

-- Planting (tries Networking -> ReplicaSet -> Packet, else uses REMOTE payload)
local NetworkingModule
pcall(function()
    local sm = ReplicatedStorage:FindFirstChild("SharedModules")
    if sm then local m = sm:FindFirstChild("Networking") if m and m:IsA("ModuleScript") then NetworkingModule = require(m) end end
end)
local function getReplicaSet() local rem = ReplicatedStorage:FindFirstChild("RemoteEvents") return rem and rem:FindFirstChild("ReplicaSet") or nil end
local function tryPlantAt(pos, seedName, plot)
    if NetworkingModule and NetworkingModule.Plant and NetworkingModule.Plant.PlantSeed then
        local ok = pcall(function() NetworkingModule.Plant.PlantSeed:Fire(pos, seedName, plot) end)
        if ok then return true end
    end
    local replica = getReplicaSet()
    if replica then
        local ok = pcall(function() replica:FireServer(4, {"Inventory","Seeds", seedName}, 2) end)
        if ok then return true end
    end
    local packet = getPacketRemote()
    if packet then
        local ok = pcall(function()
            local payload = tostring(seedName) .. "$" .. HttpService:GenerateGUID(false)
            local payloadObj = payload
            local okBuf, buf = pcall(function() if typeof(buffer) == "table" and type(buffer.fromstring) == "function" then return buffer.fromstring(payload) end end)
            if okBuf and buf then payloadObj = buf end
            packet:FireServer(payloadObj)
        end)
        if ok then return true end
    end
    -- last resort: send mapped REMOTE payload via PACKET_REMOTE if available
    local rem = getPacketRemote()
    local mapping = SEED_PAYLOADS[seedName]
    if rem and mapping then
        pcall(function() rem:FireServer(REMOTE_ID, mapping) end)
        return true
    end
    return false, "No plant method"
end

local function getPlot()
    local gardens = Workspace:FindFirstChild("Gardens")
    if not gardens then return nil end
    for _,g in ipairs(gardens:GetChildren()) do
        if tostring(g:GetAttribute("OwnerUserId")) == tostring(player.UserId) then return g end
    end
    return nil
end

local function plantGrid(rows, cols, seedName)
    local plot = getPlot()
    if not plot then return false, "Plot not found" end
    local ref = plot:FindFirstChild("PlotSizeReference") or plot:FindFirstChild("SpawnPoint")
    if not ref or not ref:IsA("BasePart") then return false, "Plot reference missing" end
    rows = math.max(1, math.floor(rows or 6))
    cols = math.max(1, math.floor(cols or 6))
    local cf, sz = ref.CFrame, ref.Size
    local topY = ref.Position.Y + sz.Y/2 + 1
    for r = 1, rows do
        for c = 1, cols do
            local fx = (r / (rows + 1) - 0.5) * sz.X * 0.9
            local fz = (c / (cols + 1) - 0.5) * sz.Z * 0.9
            local world = cf * CFrame.new(fx, 0, fz)
            local pos = Vector3.new(world.X, topY, world.Z)
            pcall(function() tryPlantAt(pos, seedName, plot) end)
            task.wait(0.03)
        end
    end
    return true
end

-- Compact GUI (small, movable, resizable)
local W, H = 260, 140
local MIN_W, MIN_H = 220, 110

local old = playerGui:FindFirstChild(EXISTING_NAME)
if old then old:Destroy() end

local gui = create("ScreenGui", {Name = EXISTING_NAME, ResetOnSpawn = false, Parent = playerGui})
local frame = create("Frame", {Parent = gui, Size = UDim2.new(0, W, 0, H), Position = UDim2.new(0, 16, 0, 16), BackgroundColor3 = Color3.fromRGB(22,24,26)})
create("UICorner",{CornerRadius=UDim.new(0,8), Parent = frame})
create("UIStroke",{Color=Color3.fromRGB(38,42,48), Thickness=1, Parent = frame})

local title = create("TextLabel", {Parent = frame, Position = UDim2.new(0,8,0,6), Size = UDim2.new(1,-16,0,18), BackgroundTransparency=1, Text="Rollback Controls", Font=Enum.Font.GothamBold, TextSize=14, TextColor3=Color3.fromRGB(240,240,245), TextXAlignment=Enum.TextXAlignment.Left})
local sub = create("TextLabel", {Parent = frame, Position = UDim2.new(0,8,0,24), Size = UDim2.new(1,-16,0,12), BackgroundTransparency=1, Text="small | movable | resizable", Font=Enum.Font.Gotham, TextSize=10, TextColor3=Color3.fromRGB(170,170,170), TextXAlignment=Enum.TextXAlignment.Left})

local content = create("Frame", {Parent = frame, Position = UDim2.new(0,8,0,40), Size = UDim2.new(1,-16,1,-48), BackgroundTransparency=1})
local list = create("UIListLayout", {Parent = content, SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0,6)})
list.HorizontalAlignment = Enum.HorizontalAlignment.Left

-- small function to create toggle (used for Rollback & Cancel Rollback)
local function makeToggleRow(labelText, layoutOrder)
    local row = create("Frame", {Parent = content, Size = UDim2.new(1,0,0,24)}); row.LayoutOrder = layoutOrder
    create("TextLabel", {Parent = row, Position = UDim2.new(0,0,0,0), Size = UDim2.new(0.56,0,1,0), BackgroundTransparency=1, Text=labelText, Font=Enum.Font.Gotham, TextSize=13, TextColor3=Color3.fromRGB(220,220,225), TextXAlignment=Enum.TextXAlignment.Left})
    local sw = create("Frame", {Parent = row, Position = UDim2.new(1,-66,0, -2), Size = UDim2.new(0,60,0,20), BackgroundColor3=Color3.fromRGB(60,60,66)})
    create("UICorner",{CornerRadius=UDim.new(0,12), Parent = sw})
    local inner = create("Frame", {Parent = sw, Position = UDim2.new(0,2,0,2), Size = UDim2.new(0,16,0,16), BackgroundColor3=Color3.fromRGB(240,240,245)})
    create("UICorner",{CornerRadius=UDim.new(0,10), Parent = inner})
    local state = create("TextLabel", {Parent = sw, Position = UDim2.new(0,4,0,0), Size = UDim2.new(1,-8,1,0), BackgroundTransparency=1, Text="OFF", Font=Enum.Font.Gotham, TextSize=11, TextColor3=Color3.fromRGB(160,160,160), TextXAlignment=Enum.TextXAlignment.Right})
    return {Row=row, Switch=sw, Inner=inner, State=state, Enabled=false}
end

local rollbackToggle = makeToggleRow("Rollback", 1)
local cancelToggle = makeToggleRow("Cancel Rollback Data", 2)

-- wire toggles to call original payloads (safeFire via PACKET remote)
local function animateToggle(tog, enabled)
    local inner, state = tog.Inner, tog.State
    if enabled then
        TweenService:Create(inner, TweenInfo.new(0.18), {Position = UDim2.new(1,-18,0,2), BackgroundColor3 = Color3.fromRGB(90,200,170)}):Play()
        state.Text = "ON"; state.TextColor3 = Color3.fromRGB(100,220,150)
    else
        TweenService:Create(inner, TweenInfo.new(0.18), {Position = UDim2.new(0,2,0,2), BackgroundColor3 = Color3.fromRGB(240,240,245)}):Play()
        state.Text = "OFF"; state.TextColor3 = Color3.fromRGB(160,160,160)
    end
end

track(rollbackToggle.Switch.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        rollbackToggle.Enabled = not rollbackToggle.Enabled
        animateToggle(rollbackToggle, rollbackToggle.Enabled)
        -- preserved payload used previously
        local payload = ":\xF7"
        safeFire(REMOTE_ID, rollbackToggle.Enabled and payload or "")
    end
end))

track(cancelToggle.Switch.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        cancelToggle.Enabled = not cancelToggle.Enabled
        animateToggle(cancelToggle, cancelToggle.Enabled)
        local payload = ":\xF7"
        safeFire(REMOTE_ID, cancelToggle.Enabled and payload or "")
    end
end))

-- Seed selection row
local seedRow = create("Frame", {Parent = content, Size = UDim2.new(1,0,0,22)}); seedRow.LayoutOrder = 3
create("TextLabel", {Parent = seedRow, Position = UDim2.new(0,0,0,0), Size = UDim2.new(0.32,0,1,0), BackgroundTransparency=1, Text="Seed:", Font=Enum.Font.Gotham, TextSize=12, TextColor3=Color3.fromRGB(220,220,225)})
local seedBox = create("TextBox", {Parent = seedRow, Position = UDim2.new(0.34,0,0,0), Size = UDim2.new(0.64,0,1,0), Text = selectedSeed, BackgroundColor3 = Color3.fromRGB(30,30,34), ClearTextOnFocus=false, Font=Enum.Font.Gotham, TextSize=12}); create("UICorner",{CornerRadius=UDim.new(0,6), Parent = seedBox})
track(seedBox.MouseButton1Click:Connect(function() 
    -- popup
    local popupW, popupH = 160, math.min(180, 8 + #Seeds * 20)
    local popup = create("Frame", {Parent = gui, Size = UDim2.new(0, popupW, 0, popupH), Position = UDim2.new(0, frame.AbsolutePosition.X + 12, 0, frame.AbsolutePosition.Y + 60), BackgroundColor3 = Color3.fromRGB(28,28,30)})
    create("UICorner",{CornerRadius=UDim.new(0,6), Parent = popup})
    local scr = create("ScrollingFrame", {Parent = popup, Size = UDim2.new(1,-8,1,-8), Position = UDim2.new(0,4,0,4), BackgroundTransparency = 1, ScrollBarThickness = 6})
    local lst = create("UIListLayout", {Parent = scr, SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0,4)})
    for _,s in ipairs(Seeds) do
        local b = create("TextButton", {Parent = scr, Size = UDim2.new(1,0,0,18), BackgroundColor3 = Color3.fromRGB(36,36,40), Text = s, Font = Enum.Font.Gotham, TextSize = 12})
        create("UICorner",{CornerRadius=UDim.new(0,4), Parent = b})
        b.MouseButton1Click:Connect(function()
            seedBox.Text = s
            selectedSeed = s
            pcall(function() popup:Destroy() end)
        end)
    end
    task.defer(function() pcall(function() scr.CanvasSize = UDim2.new(0,0,0, lst.AbsoluteContentSize.Y + 8) end) end)
    local conn; conn = track(UserInputService.InputBegan:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1 then
            local m = inp.Position; local abs = popup.AbsolutePosition; local sz = popup.AbsoluteSize
            if not (m.X >= abs.X and m.X <= abs.X+sz.X and m.Y >= abs.Y and m.Y <= abs.Y+sz.Y) then
                pcall(function() popup:Destroy() end)
                if conn and conn.Connected then conn:Disconnect() end
            end
        end
    end))
end))
seedBox.Focused:Connect(function() seedBox:ReleaseFocus() end)

-- rows/cols
local rc = create("Frame", {Parent = content, Size = UDim2.new(1,0,0,22)}); rc.LayoutOrder = 4
create("TextLabel", {Parent = rc, Position = UDim2.new(0,0,0,0), Size = UDim2.new(0.32,0,1,0), BackgroundTransparency=1, Text="Rows:", Font=Enum.Font.Gotham, TextSize=12, TextColor3=Color3.fromRGB(210,210,210)})
local rowsBox = create("TextBox", {Parent = rc, Position = UDim2.new(0.34,0,0,0), Size = UDim2.new(0.12,0,1,0), Text="6", BackgroundColor3=Color3.fromRGB(30,30,34), Font=Enum.Font.Gotham, TextSize=12}); create("UICorner",{CornerRadius=UDim.new(0,6), Parent = rowsBox})
create("TextLabel", {Parent = rc, Position = UDim2.new(0.50,0,0,0), Size = UDim2.new(0.18,0,1,0), BackgroundTransparency=1, Text="Cols:", Font=Enum.Font.Gotham, TextSize=12, TextColor3=Color3.fromRGB(210,210,210)})
local colsBox = create("TextBox", {Parent = rc, Position = UDim2.new(0.70,0,0,0), Size = UDim2.new(0.12,0,1,0), Text="6", BackgroundColor3=Color3.fromRGB(30,30,34), Font=Enum.Font.Gotham, TextSize=12}); create("UICorner",{CornerRadius=UDim.new(0,6), Parent = colsBox})

-- Plant Grid Once
local plantBtn = create("TextButton", {Parent = content, Size = UDim2.new(1,0,0,26)}); plantBtn.LayoutOrder = 5
plantBtn.Text = "Plant Grid Once"; plantBtn.Font = Enum.Font.GothamBold; plantBtn.TextSize = 13; plantBtn.BackgroundColor3 = Color3.fromRGB(80,140,90)
create("UICorner",{CornerRadius=UDim.new(0,6), Parent = plantBtn})
track(plantBtn.MouseButton1Click:Connect(function()
    local seed = seedBox.Text or selectedSeed
    local rows = tonumber(rowsBox.Text) and math.max(1, math.floor(tonumber(rowsBox.Text))) or 6
    local cols = tonumber(colsBox.Text) and math.max(1, math.floor(tonumber(colsBox.Text))) or 6
    task.spawn(function()
        local ok, err = plantGrid(rows, cols, seed)
        notify("Plant Grid", ok and ("Planted "..rows.."x"..cols.." "..seed) or ("Failed: "..tostring(err)), ok and 1.6 or 3, ok)
    end)
end))

-- resize handle
local handle = create("Frame", {Parent = frame, Size = UDim2.new(0,10,0,10), Position = UDim2.new(1,-14,1,-14), BackgroundColor3 = Color3.fromRGB(60,60,64)})
create("UICorner",{CornerRadius=UDim.new(0,4), Parent = handle})
handle.Active = true
do
    local resizing = false; local moveConn, upConn
    handle.InputBegan:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1 then
            resizing = true
            local start = Vector2.new(inp.Position.X, inp.Position.Y)
            local startSize = Vector2.new(frame.AbsoluteSize.X, frame.AbsoluteSize.Y)
            moveConn = track(UserInputService.InputChanged:Connect(function(ch)
                if resizing and ch.UserInputType == Enum.UserInputType.MouseMovement then
                    local delta = ch.Position - start
                    local newW = math.clamp(startSize.X + delta.X, MIN_W, 1000)
                    local newH = math.clamp(startSize.Y + delta.Y, MIN_H, 1000)
                    frame.Size = UDim2.new(0, newW, 0, newH)
                end
            end))
            upConn = track(UserInputService.InputEnded:Connect(function(e)
                if e.UserInputType == Enum.UserInputType.MouseButton1 then
                    resizing = false
                    if moveConn and moveConn.Connected then moveConn:Disconnect() end
                    if upConn and upConn.Connected then upConn:Disconnect() end
                end
            end))
        end
    end)
end

-- drag by title
do
    local dragging=false; local dragInput, dragStart, startPos
    title.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true; dragInput = input; dragStart = input.Position; startPos = frame.Position
        end
    end)
    title.InputEnded:Connect(function(input) if input == dragInput then dragging=false end end)
    track(UserInputService.InputChanged:Connect(function(input)
        if dragging and input == dragInput and input.Position then
            local delta = input.Position - dragStart
            local cam = workspace.CurrentCamera; local vs = cam and cam.ViewportSize or Vector2.new(1024,768)
            local newX = math.clamp(startPos.X.Offset + delta.X, 0, vs.X - frame.AbsoluteSize.X)
            local newY = math.clamp(startPos.Y.Offset + delta.Y, 0, vs.Y - frame.AbsoluteSize.Y)
            frame.Position = UDim2.new(0, newX, 0, newY)
        end
    end))
end

-- cleanup on removal
track(gui.AncestryChanged:Connect(function()
    if not gui:IsDescendantOf(game) then cleanup() end
end))

notify("RollbackControls", "Compact UI ready — Rollback & Cancel preserved", 1.4, true)
