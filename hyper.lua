--[[
    HYPER'S HUB V9.9 – RAKNET REAL DESYNC (INTEGRADO)
    Base V9 + todas as técnicas funcionais do diálogo
    RakNet: mantido
    Funcionalidades adicionais:
      - Hitbox invisível + Ghost visual seguido pela câmera
      - Spoofing de remotes (hookfunction)
      - Lag switching (firewall)
      - Physics lock moderno
--]]

-- ============================================================
-- 0. OFUSCAÇÃO E CONFIGURAÇÃO INICIAL (NOVO)
-- ============================================================
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local lp = Players.LocalPlayer

math.randomseed(tick() + os.time())
local function randStr(len)
    len = len or math.random(6,12)
    local chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_"
    local out = ""
    for _ = 1, len do out = out .. chars:sub(math.random(1,#chars), math.random(1,#chars)) end
    return out
end

-- ============================================================
-- 1. CONFIGURAÇÕES VISUAIS (ORIGINAIS, SEM ALTERAÇÃO)
-- ============================================================
local PI2 = math.pi * 2
local OUTER_RADIUS, INNER_RADIUS = 3.2, 1.8
local OUTER_SPEED, INNER_SPEED = 2.5, -3.5
local GROUND_OFFSET = 3.1

-- ============================================================
-- 2. ESTADO GLOBAL (ORIGINAL + NOVOS CAMPOS)
-- ============================================================
local HyperState = {
    Active = false,
    GhostModel = nil,
    GroundParts = {},      -- instâncias dos anéis
    Attachments = {},      -- original (não usado, mas mantido)
    VfxConn = nil,
    Hooked = false,
    -- NOVOS CAMPOS (adicionados sem conflito)
    RingData = {},         -- metadados dos anéis
    Constraints = {},
    OriginalChar = nil,
    OriginalHRP = nil,
    RemoteSpoofActive = false,
    LagSwitchActive = false,
    LagSwitchRuleName = nil,
    ThreadId = nil,
}

-- ============================================================
-- 3. FUNÇÕES AUXILIARES (CLEANUP ORIGINAL + EXTENSÃO)
-- ============================================================
local function cleanup()
    -- Parte original
    if HyperState.VfxConn then HyperState.VfxConn:Disconnect(); HyperState.VfxConn = nil end
    if HyperState.Hooked and raknet then raknet.remove_send_hook() end
    for _, p in ipairs(HyperState.GroundParts) do if p.dot then p.dot:Destroy() end end
    if HyperState.GhostModel then HyperState.GhostModel:Destroy(); HyperState.GhostModel = nil end
    HyperState.GroundParts = {}
    HyperState.Attachments = {}
    HyperState.Hooked = false

    -- Extensão (novo)
    for _, p in ipairs(HyperState.RingData) do
        if p.obj then pcall(function() p.obj:Destroy() end) end
    end
    HyperState.RingData = {}
    for _, c in ipairs(HyperState.Constraints) do
        pcall(function() c:Destroy() end)
    end
    HyperState.Constraints = {}

    if HyperState.OriginalChar then
        for _, part in ipairs(HyperState.OriginalChar:GetDescendants()) do
            if part:IsA("BasePart") then
                part.Transparency = 0
                part.Material = Enum.Material.Plastic
            end
        end
        local hum = HyperState.OriginalChar:FindFirstChildOfClass("Humanoid")
        if hum then
            hum.AutoRotate = true
            hum.PlatformStand = false
        end
        if HyperState.OriginalHRP then
            Workspace.CurrentCamera.CameraSubject = HyperState.OriginalHRP
        end
    end

    if HyperState.LagSwitchActive then
        pcall(function()
            os.execute('netsh advfirewall firewall delete rule name="' .. HyperState.LagSwitchRuleName .. '"')
        end)
        HyperState.LagSwitchActive = false
    end

    HyperState.Active = false
    HyperState.ThreadId = nil
    HyperState.OriginalChar = nil
    HyperState.OriginalHRP = nil
end

-- ============================================================
-- 4. RAKNET HOOK (ORIGINAL – NÃO ALTERADO)
-- ============================================================
local function rakhook(packet)
    if packet.PacketId == 0x1B and HyperState.Active then
        local buf = packet.AsBuffer
        buffer.writeu32(buf, 1, 0xFFFFFFFF)
        packet:SetData(buf)
    end
end

-- ============================================================
-- 5. FUNÇÕES DE VFX (ORIGINAIS, MAS ADAPTADAS PARA ANIMAÇÃO DINÂMICA)
-- ============================================================
local function makeRingDot(pos, radius, angle, col)
    local dot = Instance.new("Part")
    dot.Anchored, dot.CanCollide = true, false
    dot.Size = Vector3.new(0.2, 0.2, 0.2)
    dot.Material = Enum.Material.Neon
    dot.Color = col
    dot.Parent = workspace
    return dot
end

-- ============================================================
-- 6. NOVAS FUNÇÕES: PHYSICS LOCK, GHOST, REMOTE SPOOF, LAG SWITCH
-- ============================================================

-- Physics lock moderno (substitui a necessidade do RakNet, mas não o remove)
local function applyPhysicsLock()
    local char = lp.Character
    if not char then return end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if hum then hum.AutoRotate = false end

    local rootAtt = Instance.new("Attachment")
    rootAtt.Parent = hrp
    local worldAtt = Instance.new("Attachment")
    worldAtt.Parent = Workspace
    worldAtt.Position = hrp.Position

    local vVel = Instance.new("VectorVelocity")
    vVel.Attachment0 = rootAtt
    vVel.RelativeTo = Enum.ActuatorRelativeTo.World
    vVel.VectorVelocity = Vector3.zero
    vVel.MaxForce = 5e5
    vVel.Parent = hrp

    local aVel = Instance.new("AngularVelocity")
    aVel.Attachment0 = rootAtt
    aVel.RelativeTo = Enum.ActuatorRelativeTo.World
    aVel.AngularVelocity = Vector3.zero
    aVel.MaxTorque = 5e5
    aVel.Parent = hrp

    local align = Instance.new("AlignPosition")
    align.Attachment0 = rootAtt
    align.Attachment1 = worldAtt
    align.MaxForce = 5e5
    align.Responsiveness = 80
    align.ReactionForceEnabled = false
    align.Parent = hrp

    table.insert(HyperState.Constraints, rootAtt)
    table.insert(HyperState.Constraints, worldAtt)
    table.insert(HyperState.Constraints, vVel)
    table.insert(HyperState.Constraints, aVel)
    table.insert(HyperState.Constraints, align)

    task.delay(0.5, function()
        if not HyperState.Active then
            for _, c in ipairs({vVel, aVel, align, rootAtt, worldAtt}) do
                pcall(c.Destroy, c)
            end
        end
    end)
end

-- Separação hitbox/visual + ghost + câmera
local function createGhostAndHideOriginal()
    local char = lp.Character
    if not char then return end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end

    HyperState.OriginalChar = char
    HyperState.OriginalHRP = hrp

    -- Tornar original invisível (hitbox)
    for _, part in ipairs(char:GetDescendants()) do
        if part:IsA("BasePart") then
            part.Transparency = 1
            part.Material = Enum.Material.ForceField
        end
    end

    -- Criar ghost (visual)
    char.Archivable = true
    local ghost = char:Clone()
    char.Archivable = false
    ghost.Name = randStr()
    for _, v in ipairs(ghost:GetDescendants()) do
        if v:IsA("BasePart") then
            v.Transparency = 0.3
            v.Color = Color3.fromRGB(0, 120, 255)
            v.Material = Enum.Material.Neon
            v.CanCollide = false
        elseif v:IsA("Humanoid") then
            v.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
        elseif v:IsA("Script") or v:IsA("LocalScript") then
            v:Destroy()
        end
    end
    local hl = Instance.new("Highlight", ghost)
    hl.FillColor = Color3.fromRGB(0, 100, 220)
    hl.FillTransparency = 0.5
    hl.OutlineColor = Color3.white
    ghost:SetPrimaryPartCFrame(hrp.CFrame)
    ghost.Parent = Workspace
    HyperState.GhostModel = ghost

    -- Câmera segue o ghost
    Workspace.CurrentCamera.CameraSubject = ghost:FindFirstChild("HumanoidRootPart") or ghost
end

-- Anéis (usando a estrutura original, mas com posição dinâmica)
local function createRings(startPos)
    for i = 1, 24 do
        local angle = (i / 24) * PI2
        local dot = makeRingDot(startPos, OUTER_RADIUS, angle, Color3.fromRGB(0, 150, 255))
        table.insert(HyperState.GroundParts, { dot = dot, angle = angle, isOuter = true })
        -- Também criamos anel interno (antes não tinha, mas vamos adicionar para melhor efeito)
        local innerDot = makeRingDot(startPos, INNER_RADIUS, angle, Color3.fromRGB(0, 200, 255))
        table.insert(HyperState.GroundParts, { dot = innerDot, angle = angle, isOuter = false })
    end
end

-- Atualização dos anéis (agora dinâmica, com a posição atual do personagem)
local function updateRings(dt, currentPos)
    local t = tick()
    for _, p in ipairs(HyperState.GroundParts) do
        local rad = p.isOuter and OUTER_RADIUS or INNER_RADIUS
        local speed = p.isOuter and OUTER_SPEED or INNER_SPEED
        local curA = p.angle + t * speed
        p.dot.CFrame = CFrame.new(
            currentPos.X + math.cos(curA) * rad,
            currentPos.Y - GROUND_OFFSET,
            currentPos.Z + math.sin(curA) * rad
        )
    end
end

-- Remote spoofing (hookfunction)
local function setupRemoteSpoofing()
    if not hookfunction then return end
    local spoofedRemotes = {}
    local function scan(container)
        for _, obj in ipairs(container:GetChildren()) do
            if obj:IsA("RemoteEvent") and (obj.Name:lower():find("move") or obj.Name:lower():find("pos")) then
                table.insert(spoofedRemotes, obj)
                local originalFire = obj.FireServer
                obj.FireServer = function(self, ...)
                    if HyperState.Active and HyperState.RemoteSpoofActive then
                        local fakePos = Vector3.new(math.random(-50,50), math.random(0,10), math.random(-50,50))
                        return originalFire(self, fakePos)
                    else
                        return originalFire(self, ...)
                    end
                end
            end
            scan(obj)
        end
    end
    scan(game:GetService("ReplicatedStorage"))
end

-- Lag switch via firewall
local function toggleLagSwitch(state)
    if not state then
        if HyperState.LagSwitchActive then
            pcall(function()
                os.execute('netsh advfirewall firewall delete rule name="' .. HyperState.LagSwitchRuleName .. '"')
            end)
            HyperState.LagSwitchActive = false
        end
        return
    end
    local exePath = game:GetService("Process"):GetCurrentProcess().FilePath
    if not exePath or exePath == "" then return end
    HyperState.LagSwitchRuleName = "HyperHub_Lag_" .. randStr(6)
    local result = os.execute('netsh advfirewall firewall add rule name="' .. HyperState.LagSwitchRuleName ..
                              '" dir=out program="' .. exePath .. '" action=block')
    if result then HyperState.LagSwitchActive = true end
end

-- Maintenance loop
local function startMaintenance(threadId)
    task.spawn(function()
        while HyperState.Active and HyperState.ThreadId == threadId do
            task.wait(0.4)
            local hasLock = false
            for _, c in ipairs(HyperState.Constraints) do
                if c:IsA("VectorVelocity") then hasLock = true; break end
            end
            if not hasLock then applyPhysicsLock() end
            if HyperState.OriginalChar then
                for _, part in ipairs(HyperState.OriginalChar:GetDescendants()) do
                    if part:IsA("BasePart") then part.Transparency = 1 end
                end
            end
            if HyperState.GhostModel and HyperState.OriginalHRP then
                HyperState.GhostModel:SetPrimaryPartCFrame(HyperState.OriginalHRP.CFrame)
            end
        end
    end)
end

-- ============================================================
-- 7. FUNÇÃO PRINCIPAL startDesync (ORIGINAL + EXTENSÕES)
-- ============================================================
local function startDesync()
    cleanup()
    local char = lp.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end

    local startPos = hrp.Position
    HyperState.Active = true
    HyperState.ThreadId = HttpService:GenerateGUID(false)

    -- PARTE ORIGINAL: Criação do Ghost (simples, mas agora usaremos o avançado)
    -- Para não perder a referência, mantemos a lógica original de clonagem,
    -- mas substituímos pela função que também esconde o original.
    -- A função original fazia:
    -- char.Archivable = true
    -- local ghost = char:Clone()
    -- char.Archivable = false
    -- ...
    -- Vamos chamar a nova função que faz isso e mais.
    createGhostAndHideOriginal()  -- substitui o bloco original

    -- Criação dos anéis (original era 24 anéis apenas externos; adicionamos internos)
    createRings(startPos)

    -- Loop de animação VFX (original usava Heartbeat e startPos fixo; agora usa posição dinâmica)
    HyperState.VfxConn = RunService.Heartbeat:Connect(function()
        if not HyperState.Active then return end
        local currentPos = hrp and hrp.Parent and hrp.Position or hrp.Position
        updateRings(0, currentPos)  -- dt não é usado, usamos tick() dentro
    end)

    -- RakNet hook (original)
    if raknet then 
        raknet.add_send_hook(rakhook)
        HyperState.Hooked = true
    end

    -- NOVAS EXTENSÕES
    applyPhysicsLock()
    if hookfunction then
        setupRemoteSpoofing()
        HyperState.RemoteSpoofActive = true
    end
    startMaintenance(HyperState.ThreadId)
end

-- ============================================================
-- 8. INTERFACE ORIGINAL (COM BOTÃO LAG SWITCH ADICIONADO)
-- ============================================================
local GuiParent = (gethui and gethui()) or game:GetService("CoreGui")
if GuiParent:FindFirstChild("HypersHubV9") then GuiParent.HypersHubV9:Destroy() end

local ScreenGui = Instance.new("ScreenGui", GuiParent)
ScreenGui.Name = "HypersHubV9"

local Main = Instance.new("Frame", ScreenGui)
Main.Size = UDim2.new(0, 260, 0, 180)
Main.Position = UDim2.new(0.5, -130, 0.8, 0)
Main.BackgroundColor3 = Color3.fromRGB(8,8,12)
Main.BackgroundTransparency = 0.15
Main.Draggable = true
Main.Active = true
Instance.new("UICorner", Main).CornerRadius = UDim.new(0, 10)
local stroke = Instance.new("UIStroke", Main)
stroke.Color = Color3.fromRGB(0, 150, 255)
stroke.Thickness = 1.5

local Title = Instance.new("TextLabel", Main)
Title.Size = UDim2.new(1, 0, 0, 45)
Title.Text = "HYPER'S HUB V9.9"
Title.TextColor3 = Color3.fromRGB(0, 200, 255)
Title.Font = Enum.Font.GothamBold
Title.TextSize = 18
Title.BackgroundTransparency = 1

local Subtitle = Instance.new("TextLabel", Main)
Subtitle.Size = UDim2.new(1, 0, 0, 25)
Subtitle.Position = UDim2.new(0, 0, 0, 40)
Subtitle.Text = "RAKNET REAL DESYNC"
Subtitle.TextColor3 = Color3.fromRGB(150,150,150)
Subtitle.Font = Enum.Font.Gotham
Subtitle.TextSize = 11
Subtitle.BackgroundTransparency = 1

local Status = Instance.new("TextLabel", Main)
Status.Size = UDim2.new(1, 0, 0, 20)
Status.Position = UDim2.new(0, 0, 0.55, 0)
Status.Text = "STATUS: ○ INACTIVE"
Status.TextColor3 = Color3.fromRGB(255, 100, 100)
Status.Font = Enum.Font.GothamBold
Status.TextSize = 12
Status.BackgroundTransparency = 1

local OnBtn = Instance.new("TextButton", Main)
OnBtn.Size = UDim2.new(0.3, 0, 0, 35)
OnBtn.Position = UDim2.new(0.05, 0, 0.68, 0)
OnBtn.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
OnBtn.Text = "ON"
OnBtn.TextColor3 = Color3.fromRGB(0, 200, 255)
OnBtn.Font = Enum.Font.GothamBold
OnBtn.TextSize = 14
Instance.new("UICorner", OnBtn).CornerRadius = UDim.new(0, 6)

local OffBtn = Instance.new("TextButton", Main)
OffBtn.Size = UDim2.new(0.3, 0, 0, 35)
OffBtn.Position = UDim2.new(0.38, 0, 0.68, 0)
OffBtn.BackgroundColor3 = Color3.fromRGB(40, 20, 20)
OffBtn.Text = "OFF"
OffBtn.TextColor3 = Color3.fromRGB(255, 100, 100)
OffBtn.Font = Enum.Font.GothamBold
OffBtn.TextSize = 14
Instance.new("UICorner", OffBtn).CornerRadius = UDim.new(0, 6)

local LagBtn = Instance.new("TextButton", Main)
LagBtn.Size = UDim2.new(0.25, 0, 0, 35)
LagBtn.Position = UDim2.new(0.72, 0, 0.68, 0)
LagBtn.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
LagBtn.Text = "LAG: OFF"
LagBtn.TextColor3 = Color3.fromRGB(200, 200, 200)
LagBtn.Font = Enum.Font.GothamBold
LagBtn.TextSize = 12
Instance.new("UICorner", LagBtn).CornerRadius = UDim.new(0, 6)

local CloseBtn = Instance.new("TextButton", Main)
CloseBtn.Size = UDim2.new(0, 28, 0, 28)
CloseBtn.Position = UDim2.new(1, -35, 0, 5)
CloseBtn.BackgroundColor3 = Color3.fromRGB(40, 20, 20)
CloseBtn.Text = "✕"
CloseBtn.TextColor3 = Color3.fromRGB(255, 100, 100)
CloseBtn.Font = Enum.Font.GothamBold
CloseBtn.TextSize = 16
Instance.new("UICorner", CloseBtn).CornerRadius = UDim.new(0, 6)

OnBtn.MouseButton1Click:Connect(function()
    if not HyperState.Active then
        startDesync()
        HyperState.Active = true
        OnBtn.BackgroundColor3 = Color3.fromRGB(0, 100, 80)
        OffBtn.BackgroundColor3 = Color3.fromRGB(40, 20, 20)
        Status.Text = "STATUS: ● ACTIVE – DESYNC ON"
        Status.TextColor3 = Color3.fromRGB(0, 255, 150)
    end
end)

OffBtn.MouseButton1Click:Connect(function()
    if HyperState.Active then
        HyperState.Active = false
        cleanup()
        OnBtn.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
        OffBtn.BackgroundColor3 = Color3.fromRGB(100, 30, 30)
        Status.Text = "STATUS: ○ INACTIVE"
        Status.TextColor3 = Color3.fromRGB(255, 100, 100)
        LagBtn.Text = "LAG: OFF"
        LagBtn.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
    end
end)

LagBtn.MouseButton1Click:Connect(function()
    if not HyperState.Active then
        Status.Text = "STATUS: Ative o desync primeiro"
        Status.TextColor3 = Color3.fromRGB(255, 200, 0)
        task.delay(2, function()
            if not HyperState.Active then
                Status.Text = "STATUS: ○ INACTIVE"
                Status.TextColor3 = Color3.fromRGB(255, 100, 100)
            end
        end)
        return
    end
    if HyperState.LagSwitchActive then
        toggleLagSwitch(false)
        LagBtn.Text = "LAG: OFF"
        LagBtn.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
    else
        toggleLagSwitch(true)
        if HyperState.LagSwitchActive then
            LagBtn.Text = "LAG: ON"
            LagBtn.BackgroundColor3 = Color3.fromRGB(0, 80, 80)
        else
            Status.Text = "STATUS: Lag switch falhou (admin?)"
            task.delay(2, function()
                if HyperState.Active then
                    Status.Text = "STATUS: ● ACTIVE – DESYNC ON"
                else
                    Status.Text = "STATUS: ○ INACTIVE"
                end
            end)
        end
    end
end)

CloseBtn.MouseButton1Click:Connect(function()
    if HyperState.Active then
        HyperState.Active = false
        cleanup()
    end
    ScreenGui:Destroy()
end)

lp.OnTeleport:Connect(cleanup)
Players.PlayerRemoving:Connect(cleanup)

-- ============================================================
-- FIM – SCRIPT PRONTO (RAKNET ORIGINAL PRESERVADO)
-- ============================================================
