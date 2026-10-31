local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local LocalPlayer = Players.LocalPlayer
local StarterGui = game:GetService("StarterGui")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")

local Env = (getgenv and getgenv()) or _G
if type(Env.Fyrex_zCleanup) == "function" then pcall(Env.Fyrex_zCleanup) end
Env.Fyrex_zCleanup = nil

local ScriptConnections = {}
local SettingsStore = {Data = {Toggles = {}, Values = {}}, Entries = {}, Paused = false, Queued = false, File = "Fyrex_z_Settings.json"}
pcall(function()
    if typeof(isfile) == "function" and typeof(readfile) == "function" and isfile(SettingsStore.File) then
        local Decoded = HttpService:JSONDecode(readfile(SettingsStore.File))
        if type(Decoded) == "table" then
            if type(Decoded.Toggles) == "table" then SettingsStore.Data.Toggles = Decoded.Toggles end
            if type(Decoded.Values) == "table" then SettingsStore.Data.Values = Decoded.Values end
        end
    end
end)
function SettingsStore.Save()
    if SettingsStore.Paused or SettingsStore.Queued or typeof(writefile) ~= "function" then return end
    SettingsStore.Queued = true
    task.delay(1, function()
        SettingsStore.Queued = false
        pcall(function() writefile(SettingsStore.File, HttpService:JSONEncode(SettingsStore.Data)) end)
    end)
end
function SettingsStore.TurnOff(Title)
    for _, Entry in ipairs(SettingsStore.Entries) do
        if Entry.Title == Title and Entry.Element then
            pcall(function() Entry.Element:Set(false) end)
        end
    end
end
function SettingsStore.SetValue(Key, Value)
    if SettingsStore.Paused then return end
    SettingsStore.Data.Values[Key] = Value
    SettingsStore.Save()
end
local NotificationsEnabled = SettingsStore.Data.Values.Notifications ~= false

local function Notify(Title, Message, Duration)
    if not NotificationsEnabled then return end
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = tostring(Title or "Fyrex_z"),
            Text = tostring(Message or ""),
            Duration = Duration or 4
        })
    end)
end

local WindUI = loadstring(game:HttpGet("https://raw.githubusercontent.com/Footagesus/WindUI/main/dist/main.lua"))()
local Window = WindUI:CreateWindow({Title = "🎃 Slap Battles But I Made it", Folder = "Fyrex_z", NewElements = true, HideSearchBar = true})
local VisualsTab = Window:Tab({Title = "Visuals", Icon = "eye"})
local FarmTab = Window:Tab({Title = "Farm", Icon = "zap"})
local BadgesTab = Window:Tab({Title = "Badges", Icon = "award"})
local MapTab = Window:Tab({Title = "Map", Icon = "map"})
local PlayerTab = Window:Tab({Title = "Players", Icon = "users"})

local AllToggles = {}
for _, Tab in ipairs({VisualsTab, FarmTab, BadgesTab, MapTab, PlayerTab}) do
    pcall(function()
        local OriginalToggle = Tab.Toggle
        Tab.Toggle = function(self, Config)
            local Entry = {Title = Config.Title, Original = Config.Callback, Fired = false}
            Config.Callback = function(Value)
                Entry.Fired = true
                if not SettingsStore.Paused and Entry.Title then
                    SettingsStore.Data.Toggles[Entry.Title] = Value and true or false
                    SettingsStore.Save()
                end
                if Entry.Original then return Entry.Original(Value) end
            end
            Entry.Element = OriginalToggle(self, Config)
            if Entry.Element then table.insert(AllToggles, Entry.Element) end
            table.insert(SettingsStore.Entries, Entry)
            return Entry.Element
        end
    end)
end

local function SafeSpawn(Name, Fn, Retries)
    task.spawn(function()
        local Attempt = 0
        while true do
            local Success, Err = pcall(Fn)
            if Success then return end
            Attempt += 1
            Notify(Name, "Error: " .. string.sub(tostring(Err), 1, 100), 5)
            if Attempt > (Retries or 0) then return end
            task.wait(1)
        end
    end)
end

local function GetSlaps()
    local Stats = LocalPlayer:FindFirstChild("leaderstats")
    if not Stats then return nil end
    local Stat = Stats:FindFirstChild("Slaps")
    if not Stat then
        for _, Child in ipairs(Stats:GetChildren()) do
            if Child:IsA("ValueBase") and string.find(string.lower(Child.Name), "slap", 1, true) then
                Stat = Child
                break
            end
        end
    end
    return Stat and tonumber(Stat.Value) or nil
end

local function RequireSlaps(Title, Amount, GloveName)
    local Slaps = GetSlaps()
    if Slaps and Slaps < Amount then
        Notify(GloveName, "Not enough Slaps. Need " .. Amount .. ", you have " .. Slaps .. ".", 5)
        task.defer(function()
            for _, Entry in ipairs(SettingsStore.Entries) do
                if Entry.Title == Title and Entry.Element then
                    pcall(function() Entry.Element:Set(false) end)
                end
            end
        end)
        return false
    end
    return true
end

local State = {Fly = false, Noclip = false, NoclipManual = false, Farm = false, ESP = false, Badge = false, InfiniteJump = false, AntiRagdoll = false, AntiFreeze = false, AntiVoid = false, AntiCubeOfDeath = false, AntiAFK = false}
local WalkSpeedValue, JumpPowerValue, FlySpeedValue, FarmHoldValue = 16, 50, 60, 0.3
do
    local Saved = SettingsStore.Data.Values
    if type(Saved.WalkSpeed) == "number" then WalkSpeedValue = math.clamp(Saved.WalkSpeed, 0, 200) end
    if type(Saved.JumpPower) == "number" then JumpPowerValue = math.clamp(Saved.JumpPower, 0, 200) end
    if type(Saved.FlySpeed) == "number" then FlySpeedValue = math.clamp(Saved.FlySpeed, 10, 200) end
end
local SelectedPlayer
local FlyConnection, NoclipConnection, ESPConnection, InfiniteJumpConnection, AntiRagdollConnection, AntiFreezeConnection, AntiVoidConnection, AntiAFKConnection
local FlyGyro, FlyBodyVelocity
local FlyCollision = {}
local NoclipCollision, ESPObjects, PlayerConnections = {}, {}, {}
local FarmGeneration, BadgeGeneration, TNTGeneration = 0, 0, 0

local ELUDE_PLACE_ID = 113725055511492
local EludeShared = (getgenv and getgenv().Fyrex_zEludeState) or nil
if not EludeShared then
    EludeShared = {Running = false, Completed = false, Started = false}
    if getgenv then pcall(function() getgenv().Fyrex_zEludeState = EludeShared end) end
end
EludeShared.Started = EludeShared.Started or EludeShared.Running or EludeShared.Completed
local EludeTargetRun = false
local EludeTargetsCompleted = EludeShared.Completed

local function FindEludeTargets()
    local TargetNames = {"Bob plush", "Handle", "Jerma amogus sus smile meme funni", " "}
    local FoundTargets = {}

    for _, Name in ipairs(TargetNames) do
        local Target = workspace:FindFirstChild(Name, true)
        if not Target then return nil end

        local TargetCFrame
        if Target:IsA("BasePart") then
            TargetCFrame = Target.CFrame
        elseif Target:IsA("Model") then
            local Part = Target.PrimaryPart or Target:FindFirstChildWhichIsA("BasePart", true)
            TargetCFrame = Part and (Target.PrimaryPart and Target:GetPivot() or Part.CFrame) or nil
        else
            local Part = Target:FindFirstChildWhichIsA("BasePart", true)
            TargetCFrame = Part and Part.CFrame or nil
        end

        if not TargetCFrame then return nil end
        local Duplicate = false
        for _, Existing in ipairs(FoundTargets) do
            if (Existing.CFrame.Position - TargetCFrame.Position).Magnitude < 2 then
                Duplicate = true
                break
            end
        end
        if not Duplicate then
            table.insert(FoundTargets, {CFrame = TargetCFrame, Name = Name})
        end
    end

    return FoundTargets
end

local function TeleportToEludeTarget(AllowFallback)
    if EludeTargetRun or EludeTargetsCompleted or EludeShared.Started or EludeShared.Running or EludeShared.Completed then return end
    EludeTargetRun = true
    EludeShared.Started = true
    EludeShared.Running = true

    task.spawn(function()
        local Started = os.clock()
        local Targets
        repeat
            Targets = FindEludeTargets()
            if not Targets then task.wait(0.2) end
        until Targets or os.clock() - Started >= 20

        if not Targets then
            EludeTargetRun = false
            EludeShared.Running = false
            EludeShared.Started = false
            return
        end

        local MaxTargets = math.min(#Targets, 4)
        for i = 1, MaxTargets do
            local Target = Targets[i]
            local Character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
            local Root = Character:FindFirstChild("HumanoidRootPart") or Character:WaitForChild("HumanoidRootPart", 5)
            local Humanoid = Character:FindFirstChildOfClass("Humanoid")

            if Root and Humanoid and Humanoid.Health > 0 then
                local Destination = Target.CFrame + Vector3.new(0, 3, 0)
                pcall(function()
                    Root.AssemblyLinearVelocity = Vector3.zero
                    Root.AssemblyAngularVelocity = Vector3.zero
                    Root.CFrame = Destination
                end)
                task.wait(0.5)
            end
            task.wait(0.25)
        end

        EludeTargetsCompleted = true
        EludeShared.Completed = true
        EludeTargetRun = false
        EludeShared.Running = false
    end)
end

local function GetCharacter() return LocalPlayer.Character end
local function GetHumanoid()
    local Character = GetCharacter()
    return Character and Character:FindFirstChildOfClass("Humanoid")
end
local function GetRoot(Character) return Character and Character:FindFirstChild("HumanoidRootPart") end
local function GetPlayerNames()
    local Names = {}
    for _, Player in ipairs(Players:GetPlayers()) do
        if Player ~= LocalPlayer then table.insert(Names, Player.Name) end
    end
    table.sort(Names)
    return Names
end
local function ApplyMovement()
    local Humanoid = GetHumanoid()
    if Humanoid then
        Humanoid.WalkSpeed = WalkSpeedValue
        Humanoid.UseJumpPower = true
        Humanoid.JumpPower = JumpPowerValue
    end
end
local function SaveAndDisableCollision(Character, Saved)
    if not Character then return end
    for _, Part in ipairs(Character:GetDescendants()) do
        if Part:IsA("BasePart") then
            if Saved[Part] == nil then Saved[Part] = Part.CanCollide end
            Part.CanCollide = false
        end
    end
end
local function RestoreCollision(Saved)
    for Part, Value in pairs(Saved) do
        pcall(function() if Part.Parent then Part.CanCollide = Value end end)
        Saved[Part] = nil
    end
end
local function DestroyFlyObjects()
    if FlyGyro then FlyGyro:Destroy(); FlyGyro = nil end
    if FlyBodyVelocity then FlyBodyVelocity:Destroy(); FlyBodyVelocity = nil end
end
local function StopFly()
    State.Fly = false
    if FlyConnection then FlyConnection:Disconnect(); FlyConnection = nil end
    RestoreCollision(FlyCollision)
    DestroyFlyObjects()
    local Humanoid = GetHumanoid()
    if Humanoid then Humanoid.PlatformStand = false end
    local Root = GetRoot(GetCharacter())
    if Root then Root.AssemblyLinearVelocity = Vector3.zero end
end
local function CreateFlyObjects(Root)
    DestroyFlyObjects()
    FlyGyro = Instance.new("BodyGyro")
    FlyGyro.P = 9e4
    FlyGyro.MaxTorque = Vector3.new(9e9, 9e9, 9e9)
    FlyGyro.CFrame = Root.CFrame
    FlyGyro.Parent = Root
    FlyBodyVelocity = Instance.new("BodyVelocity")
    FlyBodyVelocity.Velocity = Vector3.zero
    FlyBodyVelocity.MaxForce = Vector3.new(9e9, 9e9, 9e9)
    FlyBodyVelocity.Parent = Root
end
local function StartFly()
    StopFly()
    local Root = GetRoot(GetCharacter())
    if not Root then return end
    State.Fly = true
    CreateFlyObjects(Root)

    local CachedCharacter, CachedParts, CachedAt = nil, {}, 0
    FlyConnection = RunService.RenderStepped:Connect(function()
        local Character, Camera = GetCharacter(), workspace.CurrentCamera
        local Root, Humanoid = GetRoot(Character), GetHumanoid()
        if not State.Fly or not Root or not Humanoid or not Camera or Humanoid.Health <= 0 then return end
        if not FlyGyro or not FlyBodyVelocity or FlyGyro.Parent ~= Root or FlyBodyVelocity.Parent ~= Root then
            CreateFlyObjects(Root)
        end
        Humanoid.PlatformStand = true
        if State.FlyNoclip then
            if Character ~= CachedCharacter or os.clock() - CachedAt > 0.75 then
                CachedCharacter, CachedAt = Character, os.clock()
                table.clear(CachedParts)
                for _, Part in ipairs(Character:GetDescendants()) do
                    if Part:IsA("BasePart") then CachedParts[#CachedParts + 1] = Part end
                end
            end
            for _, Part in ipairs(CachedParts) do
                if Part.Parent then
                    if FlyCollision[Part] == nil then FlyCollision[Part] = Part.CanCollide end
                    Part.CanCollide = false
                end
            end
        elseif next(FlyCollision) then
            RestoreCollision(FlyCollision)
        end

        local CameraCFrame = Camera.CFrame
        FlyGyro.CFrame = CameraCFrame

        local MoveDirection = Humanoid.MoveDirection
        local Speed = FlySpeedValue
        local Velocity = Vector3.zero

        if MoveDirection.Magnitude > 0.05 then
            local LookVector = Vector3.new(CameraCFrame.LookVector.X, 0, CameraCFrame.LookVector.Z)
            if LookVector.Magnitude > 0.001 then
                LookVector = LookVector.Unit
                local RightVector = Vector3.new(CameraCFrame.RightVector.X, 0, CameraCFrame.RightVector.Z).Unit
                local Forward = MoveDirection:Dot(LookVector)
                local Side = MoveDirection:Dot(RightVector)
                local Direction = CameraCFrame.LookVector * Forward + CameraCFrame.RightVector * Side
                if Direction.Magnitude > 0.01 then
                    Velocity = Direction.Unit * Speed
                else
                    Velocity = MoveDirection * Speed
                end
            else
                Velocity = CameraCFrame.LookVector * Speed
            end
        end

        if UserInputService:IsKeyDown(Enum.KeyCode.Space) then
            Velocity = Velocity + CameraCFrame.UpVector * Speed
        elseif UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then
            Velocity = Velocity - CameraCFrame.UpVector * Speed
        end

        FlyBodyVelocity.Velocity = Velocity
    end)
end
local function StopInfiniteJump()
    State.InfiniteJump = false
    if InfiniteJumpConnection then InfiniteJumpConnection:Disconnect(); InfiniteJumpConnection = nil end
end
local function StartInfiniteJump()
    StopInfiniteJump()
    State.InfiniteJump = true
    InfiniteJumpConnection = UserInputService.JumpRequest:Connect(function()
        local Humanoid = GetHumanoid()
        if State.InfiniteJump and Humanoid and Humanoid.Health > 0 then Humanoid:ChangeState(Enum.HumanoidStateType.Jumping) end
    end)
end
local function StopAntiRagdoll()
    State.AntiRagdoll = false
    if AntiRagdollConnection then
        AntiRagdollConnection:Disconnect()
        AntiRagdollConnection = nil
    end
end

local function StartAntiRagdoll()
    StopAntiRagdoll()
    State.AntiRagdoll = true
    local Character = GetCharacter()
    local Humanoid = GetHumanoid()
    if not Character or not Humanoid then return end
    AntiRagdollConnection = Humanoid.StateChanged:Connect(function(_, NewState)
        if not State.AntiRagdoll or not Humanoid.Parent or Humanoid.Health <= 0 then return end
        if NewState == Enum.HumanoidStateType.Ragdoll or NewState == Enum.HumanoidStateType.FallingDown then
            task.defer(function()
                if State.AntiRagdoll and Humanoid.Parent and Humanoid.Health > 0 then
                    pcall(function()
                        Humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
                    end)
                end
            end)
        end
    end)
end
local function StopAntiFreeze()
    State.AntiFreeze = false
    if AntiFreezeConnection then AntiFreezeConnection:Disconnect(); AntiFreezeConnection = nil end
end

local function StopAntiAFK()
    State.AntiAFK = false
    if AntiAFKConnection then
        AntiAFKConnection:Disconnect()
        AntiAFKConnection = nil
    end
end

local function StartAntiAFK()
    StopAntiAFK()
    State.AntiAFK = true
    AntiAFKConnection = LocalPlayer.Idled:Connect(function()
        if not State.AntiAFK then return end
        pcall(function()
            local VirtualUser = game:GetService("VirtualUser")
            VirtualUser:CaptureController()
            VirtualUser:ClickButton2(Vector2.new(0, 0))
        end)
    end)
end

local function StartAntiFreeze()
    StopAntiFreeze()
    State.AntiFreeze = true
    AntiFreezeConnection = RunService.Heartbeat:Connect(function()
        if not State.AntiFreeze then return end
        local Character, Humanoid = GetCharacter(), GetHumanoid()
        local Root = GetRoot(Character)
        if not Character or not Humanoid or not Root or Humanoid.Health <= 0 then return end
        pcall(function()
            if not State.Fly then Humanoid.PlatformStand = false end
            Humanoid.Sit = false
            Humanoid.WalkSpeed = WalkSpeedValue
            Humanoid.UseJumpPower = true
            Humanoid.JumpPower = JumpPowerValue
            for _, Part in ipairs(Character:GetChildren()) do
                if Part:IsA("BasePart") and Part.Anchored then Part.Anchored = false end
            end
            local CurrentState = Humanoid:GetState()
            if not State.Fly and (CurrentState == Enum.HumanoidStateType.PlatformStanding or CurrentState == Enum.HumanoidStateType.FallingDown) then
                Humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
            end
        end)
    end)
end

local AntiVoidLastRecovery = 0
local AntiVoidRecoveryCooldown = 0.3
local AntiVoidPlatform
local AntiVoidPlatformSize = Vector3.new(120, 2, 120)
local AntiVoidCheckDistance = 2500
local AntiVoidFallSpeed = 20
local AntiVoidHistory = {}
local AntiVoidParams = RaycastParams.new()
AntiVoidParams.FilterType = Enum.RaycastFilterType.Exclude
AntiVoidParams.RespectCanCollide = true

local function RemoveAntiVoidPlatform()
    if AntiVoidPlatform then
        AntiVoidPlatform:Destroy()
        AntiVoidPlatform = nil
    end
end

local function StopAntiVoid()
    State.AntiVoid = false
    table.clear(AntiVoidHistory)
    RemoveAntiVoidPlatform()
    if AntiVoidConnection then AntiVoidConnection:Disconnect(); AntiVoidConnection = nil end
end

local function CreateAntiVoidPlatform()
    if AntiVoidPlatform and AntiVoidPlatform.Parent then return AntiVoidPlatform end
    local Part = Instance.new("Part")
    Part.Name = "Fyrex_z_AntiVoidPlatform"
    Part.Size = AntiVoidPlatformSize
    Part.Anchored = true
    Part.CanCollide = true
    Part.CanTouch = false
    Part.CanQuery = true
    Part.Transparency = 0.25
    Part.Material = Enum.Material.SmoothPlastic
    Part.TopSurface = Enum.SurfaceType.Smooth
    Part.BottomSurface = Enum.SurfaceType.Smooth
    Part.Color = Color3.fromRGB(70, 140, 90)
    Part.Parent = workspace
    AntiVoidPlatform = Part
    return Part
end

local function IsOnAntiVoidPlatform(Root)
    local Platform = AntiVoidPlatform
    if not Platform or not Platform.Parent then return false end
    local Offset = Root.Position - Platform.Position
    return math.abs(Offset.X) < Platform.Size.X / 2 and math.abs(Offset.Z) < Platform.Size.Z / 2
        and Offset.Y > -3 and Offset.Y < 10
end

local function PickAntiVoidSafe(Now)
    local Chosen
    for Index = #AntiVoidHistory, 1, -1 do
        Chosen = AntiVoidHistory[Index]
        if Now - Chosen.Time >= 0.8 then break end
    end
    return Chosen and Chosen.CFrame
end

local function StartAntiVoid()
    StopAntiVoid()
    State.AntiVoid = true
    AntiVoidLastRecovery = 0
    local LastCharacter
    local LastRecord = 0
    local Accumulator = 0
    AntiVoidConnection = RunService.Heartbeat:Connect(function(Delta)
        if not State.AntiVoid then return end
        Accumulator += Delta
        if Accumulator < 0.03 then return end
        Accumulator = 0

        local Character, Humanoid = GetCharacter(), GetHumanoid()
        local Root = GetRoot(Character)
        if not Character or not Humanoid or not Root or Humanoid.Health <= 0 then return end

        if Character ~= LastCharacter then
            LastCharacter = Character
            table.clear(AntiVoidHistory)
            RemoveAntiVoidPlatform()
            AntiVoidParams.FilterDescendantsInstances = {Character}
        end
        if State.Fly then return end

        local Now = os.clock()
        local Velocity = Root.AssemblyLinearVelocity

        if Humanoid.FloorMaterial ~= Enum.Material.Air and Velocity.Magnitude < 60 and not IsOnAntiVoidPlatform(Root) then
            if Now - LastRecord >= 0.2 then
                LastRecord = Now
                table.insert(AntiVoidHistory, {CFrame = Root.CFrame, Time = Now})
                if #AntiVoidHistory > 15 then table.remove(AntiVoidHistory, 1) end
            end
            if AntiVoidPlatform then RemoveAntiVoidPlatform() end
            return
        end

        local BelowLimit = Root.Position.Y < workspace.FallenPartsDestroyHeight + 150
        local FastDrop = Velocity.Y < -120
        if not BelowLimit and not FastDrop and Velocity.Y > -AntiVoidFallSpeed then return end
        if Now - AntiVoidLastRecovery < AntiVoidRecoveryCooldown then return end

        if not BelowLimit and not FastDrop then
            local Hit = workspace:Raycast(Root.Position, Vector3.new(0, -AntiVoidCheckDistance, 0), AntiVoidParams)
            if Hit then return end
        elseif not BelowLimit then
            local Hit = workspace:Raycast(Root.Position, Vector3.new(0, -300, 0), AntiVoidParams)
            if Hit then return end
        end

        AntiVoidLastRecovery = Now
        local Target = PickAntiVoidSafe(Now)
        Root.AssemblyLinearVelocity = Vector3.zero
        Root.AssemblyAngularVelocity = Vector3.zero
        if Target then
            Root.CFrame = Target + Vector3.new(0, 3, 0)
        else
            local Platform = CreateAntiVoidPlatform()
            Platform.CFrame = CFrame.new(Root.Position.X, Root.Position.Y - 6, Root.Position.Z)
            Root.CFrame = CFrame.new(Root.Position.X, Platform.Position.Y + Platform.Size.Y / 2 + 4, Root.Position.Z)
        end
        pcall(function() Humanoid:ChangeState(Enum.HumanoidStateType.GettingUp) end)
    end)
end

local CubeShield
local CubeWatchConnection
local CubeCache = {Target = nil, SearchedAt = 0}
local function StopAntiCubeOfDeath()
    State.AntiCubeOfDeath = false
    if CubeWatchConnection then CubeWatchConnection:Disconnect(); CubeWatchConnection = nil end
    CubeCache.Target = nil
    CubeCache.SearchedAt = 0
    if CubeShield then CubeShield:Destroy(); CubeShield = nil end
end

local function StartAntiCubeOfDeath()
    StopAntiCubeOfDeath()
    State.AntiCubeOfDeath = true
    local function UpdateShield()
        local Target = CubeCache.Target
        if not Target or not Target:IsDescendantOf(workspace) then
            Target = nil
            if os.clock() - CubeCache.SearchedAt >= 1 then
                CubeCache.SearchedAt = os.clock()
                Target = workspace:FindFirstChild("Racundeadblock", true)
                CubeCache.Target = Target
            end
        end
        if not Target then
            if CubeShield then CubeShield:Destroy(); CubeShield = nil end
            return
        end
        local TargetCFrame, TargetSize
        if Target:IsA("BasePart") then
            TargetCFrame, TargetSize = Target.CFrame, Target.Size
        elseif Target:IsA("Model") then
            TargetCFrame, TargetSize = Target:GetBoundingBox()
        else
            return
        end
        if not CubeShield then
            CubeShield = Instance.new("Part")
            CubeShield.Name = "Fyrex_zAntiCubeOfDeathShield"
            CubeShield.Anchored = true
            CubeShield.CanCollide = true
            CubeShield.CanTouch = false
            CubeShield.CanQuery = false
            CubeShield.Transparency = 0.8
            CubeShield.Material = Enum.Material.ForceField
            CubeShield.Color = Color3.fromRGB(80, 180, 255)
            CubeShield.Parent = workspace
        end
        CubeShield.CFrame = TargetCFrame
        CubeShield.Size = TargetSize + Vector3.new(8, 8, 8)
    end
    UpdateShield()
    local CubeAccumulator = 0
    CubeWatchConnection = RunService.Heartbeat:Connect(function(Delta)
        CubeAccumulator += Delta
        if CubeAccumulator >= 0.1 then
            CubeAccumulator = 0
            UpdateShield()
        end
    end)
end

local function StopNoclip()
    State.Noclip = false
    if NoclipConnection then NoclipConnection:Disconnect(); NoclipConnection = nil end
    RestoreCollision(NoclipCollision)
end
local function StartNoclip()
    if NoclipConnection then NoclipConnection:Disconnect(); NoclipConnection = nil end
    State.Noclip = true
    local CachedCharacter, CachedParts, CachedAt = nil, {}, 0
    NoclipConnection = RunService.Stepped:Connect(function()
        if not State.Noclip then return end
        local Character = GetCharacter()
        if not Character then return end
        if Character ~= CachedCharacter or os.clock() - CachedAt > 0.75 then
            CachedCharacter, CachedAt = Character, os.clock()
            table.clear(CachedParts)
            for _, Part in ipairs(Character:GetDescendants()) do
                if Part:IsA("BasePart") then CachedParts[#CachedParts + 1] = Part end
            end
        end
        for _, Part in ipairs(CachedParts) do
            if Part.Parent then
                if NoclipCollision[Part] == nil then NoclipCollision[Part] = Part.CanCollide end
                Part.CanCollide = false
            end
        end
    end)
end
local function RemoveESP(Player)
    local Data = ESPObjects[Player]
    if not Data then return end
    for _, Object in ipairs(Data.Objects) do pcall(function() Object:Destroy() end) end
    ESPObjects[Player] = nil
end
local function CreateESP(Player)
    if Player == LocalPlayer or not State.ESP then return end
    RemoveESP(Player)
    local Character = Player.Character
    local Root, Head = GetRoot(Character), Character and Character:FindFirstChild("Head")
    local LocalRoot = GetRoot(GetCharacter())
    if not Root or not Head or not LocalRoot then return end
    local Data = {Objects = {}, Root = Root, LocalRoot = LocalRoot}
    ESPObjects[Player] = Data
    local HighlightObject = Instance.new("Highlight")
    HighlightObject.Name = "Fyrex_zESPHighlight"
    HighlightObject.Adornee = Character
    HighlightObject.FillColor = Color3.fromRGB(255, 255, 255)
    HighlightObject.OutlineColor = Color3.fromRGB(255, 255, 255)
    HighlightObject.FillTransparency = 0.85
    HighlightObject.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    HighlightObject.Parent = Character
    table.insert(Data.Objects, HighlightObject)
    local StartAttachment = Instance.new("Attachment")
    StartAttachment.Name = "Fyrex_zESPStart"
    StartAttachment.Parent = LocalRoot
    table.insert(Data.Objects, StartAttachment)
    local EndAttachment = Instance.new("Attachment")
    EndAttachment.Name = "Fyrex_zESPEnd"
    EndAttachment.Parent = Root
    table.insert(Data.Objects, EndAttachment)
    local BeamObject = Instance.new("Beam")
    BeamObject.Name = "Fyrex_zESPTracer"
    BeamObject.Attachment0 = StartAttachment
    BeamObject.Attachment1 = EndAttachment
    BeamObject.FaceCamera = true
    BeamObject.Width0 = 0.045
    BeamObject.Width1 = 0.045
    BeamObject.Color = ColorSequence.new(Color3.new(1, 1, 1))
    BeamObject.Parent = LocalRoot
    table.insert(Data.Objects, BeamObject)
end
local function RefreshESP()
    if not State.ESP then return end
    local LocalRoot = GetRoot(GetCharacter())
    if not LocalRoot then return end
    for _, Player in ipairs(Players:GetPlayers()) do
        if Player ~= LocalPlayer then
            local Data = ESPObjects[Player]
            local Root = GetRoot(Player.Character)
            local Head = Player.Character and Player.Character:FindFirstChild("Head")
            if Root and Head and (not Data or Data.Root ~= Root or Data.LocalRoot ~= LocalRoot) then
                CreateESP(Player)
            elseif Data and (not Root or not Head) then
                RemoveESP(Player)
            end
        end
    end
end
local function SetESP(Enabled)
    State.ESP = Enabled
    if ESPConnection then ESPConnection:Disconnect(); ESPConnection = nil end
    if not Enabled then
        for Player in pairs(ESPObjects) do RemoveESP(Player) end
        return
    end
    RefreshESP()
    local Accumulator = 0
    ESPConnection = RunService.Heartbeat:Connect(function(Delta)
        Accumulator += Delta
        if Accumulator >= 0.25 then
            Accumulator = 0
            RefreshESP()
        end
    end)
end

local function GetSlappleModels()
    local Island = workspace:FindFirstChild("Slapple island")
    local Slapples = Island and Island:FindFirstChild("Slapples")
    local Items = {}
    if not Slapples then return Items end
    for _, Slapple in ipairs(Slapples:GetChildren()) do
        if (Slapple.Name == "Slapple" and (Slapple:IsA("Model") or Slapple:IsA("BasePart")))
            or (Slapple.Name == "Golden Slapple" and Slapple:IsA("BasePart")) then
            table.insert(Items, Slapple)
        end
    end
    table.sort(Items, function(A, B)
        if A.Name == "Golden Slapple" then return true end
        if B.Name == "Golden Slapple" then return false end
        return A.Name < B.Name
    end)
    return Items
end
local function GetSlapplePart(SlApple)
    if not SlApple or not SlApple.Parent then
        return nil
    end

    if SlApple:IsA("BasePart") then
        return SlApple
    end

    if SlApple:IsA("Model") then
        local Glove = SlApple:FindFirstChild("Glove", true)
        if Glove and Glove:IsA("BasePart") then
            return Glove
        end

        return SlApple.PrimaryPart or SlApple:FindFirstChildWhichIsA("BasePart", true)
    end

    return nil
end

local function GetSlappleTarget(SlApple)
    local TouchPart = GetSlapplePart(SlApple)
    if not TouchPart then
        return nil, nil
    end

    local TargetPosition = TouchPart.Position + Vector3.new(0, math.max(1.5, TouchPart.Size.Y * 0.5 + 0.75), 0)
    return CFrame.new(TargetPosition), TouchPart
end

local function TouchSlapple(Character, SlApple)
    if not Character or not SlApple or not SlApple.Parent then
        return false
    end

    local Root = GetRoot(Character)
    local Humanoid = Character:FindFirstChildOfClass("Humanoid")
    local TargetCFrame, TouchPart = GetSlappleTarget(SlApple)

    if not Root or not Humanoid or Humanoid.Health <= 0 or not TargetCFrame or not TouchPart then
        return false
    end

    Root.AssemblyLinearVelocity = Vector3.zero
    Root.AssemblyAngularVelocity = Vector3.zero
    Root.CFrame = TargetCFrame

    if typeof(firetouchinterest) == "function" then
        pcall(function()
            firetouchinterest(Root, TouchPart, 0)
            task.wait(0.1)
            firetouchinterest(Root, TouchPart, 1)
        end)
    end

    return true
end

local function StopFarm()
    State.Farm = false
    FarmGeneration += 1

    if State.NoclipManual then
        StartNoclip()
    else
        StopNoclip()
    end
end

local function StartFarm()
    StopFarm()
    State.Farm = true
    FarmGeneration += 1
    StartNoclip()

    local Generation = FarmGeneration

    SafeSpawn("Farm", function()
        while State.Farm and Generation == FarmGeneration do
            local Character = GetCharacter()
            local Humanoid = GetHumanoid()
            local Root = GetRoot(Character)

            if not Character or not Root or not Humanoid or Humanoid.Health <= 0 then
                task.wait(0.5)
            else
                local Items = GetSlappleModels()

                if #Items == 0 then
                    task.wait(1)
                else
                    for _, SlApple in ipairs(Items) do
                        if not State.Farm or Generation ~= FarmGeneration then
                            break
                        end

                        if not Character.Parent or not Humanoid.Parent or Humanoid.Health <= 0 then
                            break
                        end

                        if SlApple.Parent then
                            pcall(function()
                                TouchSlapple(Character, SlApple)
                            end)
                            task.wait(FarmHoldValue)
                        end
                    end
                end
            end

            task.wait(0.2)
        end
    end, 5)
end
local function GetReplicaEvent()
    local Holder = workspace:FindFirstChild(LocalPlayer.Name)
    local Replica = Holder and Holder:FindFirstChild("Replica")
    local Event = Replica and Replica:FindFirstChild("Event")
    if Event then return Event end
    Replica = LocalPlayer:FindFirstChild("Replica")
    return Replica and Replica:FindFirstChild("Event")
end
local function GetDoorCFrame()
    local Lobby = workspace:FindFirstChild("Lobby")
    local Portal = Lobby and Lobby:FindFirstChild("PORTAL1")
    local Door = Portal and Portal:FindFirstChild("DOOR")
    if not Door then return nil end
    if Door:IsA("BasePart") then return Door.CFrame end
    if Door:IsA("Model") then return Door:GetPivot() end
    return nil
end
local function StopBadge()
    State.Badge = false
    BadgeGeneration += 1
end
local function StartBadge()
    StopBadge()
    State.Badge = true
    BadgeGeneration += 1
    local Generation = BadgeGeneration
    SafeSpawn("Bob Glove", function()
        local ClickedReplica = false
        local ClickDeadline = os.clock() + 10
        while State.Badge and Generation == BadgeGeneration and not ClickedReplica and os.clock() < ClickDeadline do
            local Stands = workspace:FindFirstChild("Stands")
            local ReplicaStand = Stands and Stands:FindFirstChild("Replica")
            local Glove = ReplicaStand and ReplicaStand:FindFirstChild("Glove")
            local Detector = Glove and Glove:FindFirstChild("ClickDetector")
            if Detector and Detector:IsA("ClickDetector") and typeof(fireclickdetector) == "function" then
                local Success = pcall(function() fireclickdetector(Detector) end)
                if Success then ClickedReplica = true end
            end
            if not ClickedReplica then task.wait(0.25) end
        end
        while State.Badge and Generation == BadgeGeneration do
            pcall(function()
                local Character, Humanoid = GetCharacter(), GetHumanoid()
                local Root = GetRoot(Character)
                if not Character or not Root or not Humanoid or Humanoid.Health <= 0 then return end
                local DoorCFrame = GetDoorCFrame()
                if DoorCFrame then Root.AssemblyLinearVelocity = Vector3.zero; Root.CFrame = DoorCFrame end
                task.wait(1.2)
                if not State.Badge or Generation ~= BadgeGeneration then return end
                local Event = GetReplicaEvent()
                if Event then Event:FireServer("glove") end
                task.wait(1.5)
                if not State.Badge or Generation ~= BadgeGeneration then return end
                Humanoid.Health = 0
                local OldCharacter, Timeout = Character, os.clock() + 10
                repeat task.wait(0.2) until not State.Badge or Generation ~= BadgeGeneration or (LocalPlayer.Character and LocalPlayer.Character ~= OldCharacter and GetRoot(LocalPlayer.Character)) or os.clock() > Timeout
            end)
            task.wait(0.1)
        end
    end)
end

PlayerTab:Section({Title = "Player Select", Text = "Choose a player to target"})
local PlayerDropdown = PlayerTab:Dropdown({Title = "Select Player", Desc = "Pick who to target", Values = GetPlayerNames(), AllowNone = true, Callback = function(Value) SelectedPlayer = Players:FindFirstChild(Value) end})
PlayerTab:Toggle({Title = "ESP Players", Desc = "Highlights other players", Callback = SetESP})
PlayerTab:Section({Title = "Player Actions", Text = "Act on the selected player"})
PlayerTab:Button({Title = "Teleport to Player", Desc = "Select a player first", Callback = function()
    if not SelectedPlayer or not SelectedPlayer.Parent then return end
    local Root, TargetRoot = GetRoot(GetCharacter()), GetRoot(SelectedPlayer.Character)
    if Root and TargetRoot then Root.CFrame = TargetRoot.CFrame * CFrame.new(0, 0, 3) end
end})
local function UpdatePlayerDropdown()
    if PlayerDropdown then pcall(function() PlayerDropdown:Refresh(GetPlayerNames()) end) end
    if SelectedPlayer and not SelectedPlayer.Parent then SelectedPlayer = nil end
end
local function TrackPlayer(Player)
    if Player == LocalPlayer then return end
    if PlayerConnections[Player] then PlayerConnections[Player]:Disconnect() end
    PlayerConnections[Player] = Player.CharacterAdded:Connect(function()
        task.wait(1)
        if State.ESP then CreateESP(Player) end
    end)
end
for _, Player in ipairs(Players:GetPlayers()) do TrackPlayer(Player) end
table.insert(ScriptConnections, Players.PlayerAdded:Connect(function(Player)
    TrackPlayer(Player)
    UpdatePlayerDropdown()
    task.delay(1, function() if State.ESP then CreateESP(Player) end end)
end))
table.insert(ScriptConnections, Players.PlayerRemoving:Connect(function(Player)
    RemoveESP(Player)
    if PlayerConnections[Player] then PlayerConnections[Player]:Disconnect(); PlayerConnections[Player] = nil end
    UpdatePlayerDropdown()
end))

VisualsTab:Section({Title = "Movement Toggles", Text = "Enable or disable movement abilities"})
VisualsTab:Toggle({Title = "Fly", Desc = "Space up, Ctrl down to move vertically", Callback = function(Value) if Value then StartFly() else StopFly() end end})
VisualsTab:Toggle({Title = "Fly Noclip", Desc = "Pass through walls while flying", Callback = function(Value) State.FlyNoclip = Value end})
VisualsTab:Toggle({Title = "Infinite Jump", Desc = "Jump again in mid-air", Callback = function(Value) if Value then StartInfiniteJump() else StopInfiniteJump() end end})
VisualsTab:Toggle({Title = "Noclip", Desc = "Walk through walls", Callback = function(Value)
    State.NoclipManual = Value
    if Value then StartNoclip() elseif not State.Farm then StopNoclip() end
end})
VisualsTab:Section({Title = "Movement Settings", Text = "Adjust movement speeds and jump height"})
VisualsTab:Slider({Title = "Fly Speed", Value = {Min = 10, Max = 200, Default = math.clamp(FlySpeedValue, 10, 200)}, Callback = function(Value) FlySpeedValue = Value; SettingsStore.SetValue("FlySpeed", Value) end})
VisualsTab:Slider({Title = "WalkSpeed", Value = {Min = 16, Max = 200, Default = math.clamp(WalkSpeedValue, 16, 200)}, Callback = function(Value) WalkSpeedValue = Value; SettingsStore.SetValue("WalkSpeed", Value); ApplyMovement() end})
VisualsTab:Input({Title = "WalkSpeed Value", Placeholder = "Enter speed", Callback = function(Value) local Number = tonumber(Value); if Number then WalkSpeedValue = math.clamp(Number, 0, 200); SettingsStore.SetValue("WalkSpeed", WalkSpeedValue); ApplyMovement() end end})
VisualsTab:Slider({Title = "JumpPower", Value = {Min = 50, Max = 200, Default = math.clamp(JumpPowerValue, 50, 200)}, Callback = function(Value) JumpPowerValue = Value; SettingsStore.SetValue("JumpPower", Value); ApplyMovement() end})
VisualsTab:Input({Title = "JumpPower Value", Placeholder = "Enter power", Callback = function(Value) local Number = tonumber(Value); if Number then JumpPowerValue = math.clamp(Number, 0, 200); SettingsStore.SetValue("JumpPower", JumpPowerValue); ApplyMovement() end end})
local AntiDisarmConnection
local AntiDisarmGeneration = 0

local function StopAntiDisarm()
    AntiDisarmGeneration += 1
    if AntiDisarmConnection then
        AntiDisarmConnection:Disconnect()
        AntiDisarmConnection = nil
    end
end

local function StartAntiDisarm()
    StopAntiDisarm()
    local RemoteEvents = game:GetService("ReplicatedStorage"):FindFirstChild("RemoteEvents")
    local DisarmEvent = RemoteEvents and RemoteEvents:FindFirstChild("DisarmCallEvent")
    if not DisarmEvent or not DisarmEvent:IsA("RemoteEvent") then
        Notify("Fyrex_z", "DisarmCallEvent was not found.", 4)
        return
    end
    local Generation = AntiDisarmGeneration
    AntiDisarmConnection = DisarmEvent.OnClientEvent:Connect(function()
        task.spawn(function()
            local StartTime = os.clock()
            while Generation == AntiDisarmGeneration and os.clock() - StartTime < 7.5 do
                pcall(function()
                    StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, true)
                end)
                task.wait(0.05)
            end
        end)
    end)
    Notify("Fyrex_z", "Anti-Disarm UI protection enabled.", 3)
end

VisualsTab:Section({Title = "Protections", Text = "Toggle character and idle protections"})
VisualsTab:Toggle({Title = "Anti-Ragdoll", Desc = "Stops you from ragdolling", Callback = function(Value) if Value then StartAntiRagdoll() else StopAntiRagdoll() end end})
VisualsTab:Toggle({Title = "Anti-Disarm", Desc = "Keeps your backpack visible when disarmed", Callback = function(Value) if Value then StartAntiDisarm() else StopAntiDisarm() end end})
VisualsTab:Toggle({Title = "Anti-Freeze", Desc = "Unfreezes you if you get frozen", Callback = function(Value) if Value then StartAntiFreeze() else StopAntiFreeze() end end})
VisualsTab:Toggle({Title = "Anti-AFK", Desc = "Prevents the idle kick", Callback = function(Value)
    if Value then
        StartAntiAFK()
        Notify("Fyrex_z", "Turned On Anti-AFK", 3)
    else
        StopAntiAFK()
    end
end})
VisualsTab:Toggle({Title = "Anti-Void", Desc = "Catches you when falling into the void", Callback = function(Value) if Value then StartAntiVoid() else StopAntiVoid() end end})
VisualsTab:Toggle({Title = "Anti-CubeOfDeath", Desc = "Protects you from the Cube of Death", Callback = function(Value) if Value then StartAntiCubeOfDeath() else StopAntiCubeOfDeath() end end})
VisualsTab:Section({Title = "Player ESP", Text = "Toggle player highlighting"})
FarmTab:Section({Title = "Farm", Text = "Farming options"})
FarmTab:Toggle({Title = "Glove Slaps Farm", Desc = "You need to be in the Arena", Callback = function(Value) if Value then StartFarm() else StopFarm() end end})
FarmTab:Input({Title = "Farm Hold Time", Placeholder = "2", Callback = function(Value) local Number = tonumber(Value); if Number then FarmHoldValue = math.clamp(Number, 1, 5) end end})
BadgesTab:Section({Title = "Bob Glove", Text = "Automatically complete the Bob badge unlock"})
BadgesTab:Toggle({Title = "Auto Get Bob Glove", Desc = "Requires 605 Slaps", Callback = function(Value) if Value then if RequireSlaps("Auto Get Bob Glove", 605, "Replica Glove") then StartBadge() end else StopBadge() end end})

local SafeBoxModel
local RemoveSafeBox
local CreateSafeBox
local RattleBoneActive = false
local RattleBoneGeneration = 0

local function StopRattleBone()
    RattleBoneActive = false
    RattleBoneGeneration += 1
end

local function FindCandycorns()
    local Candies = workspace:FindFirstChild("Candies")
    if not Candies then return {} end

    local Found = {}
    for _, Object in ipairs(Candies:GetDescendants()) do
        local Name = string.lower(Object.Name)
        if string.find(Name, "candycorn", 1, true) then
            if Object:IsA("BasePart") then
                table.insert(Found, Object)
            elseif Object:IsA("Model") then
                local Part = Object.PrimaryPart or Object:FindFirstChildWhichIsA("BasePart", true)
                if Part then table.insert(Found, Part) end
            end
        end
    end

    return Found
end

local function GetObjectCFrame(Object)
    if not Object then return nil end
    if Object:IsA("BasePart") then return Object.CFrame end
    if Object:IsA("Model") then return Object:GetPivot() end
    local Part = Object:FindFirstChildWhichIsA("BasePart", true)
    return Part and Part.CFrame or nil
end

local function StartRattleBone()
    StopRattleBone()
    RattleBoneActive = true
    RattleBoneGeneration += 1
    local Generation = RattleBoneGeneration

    SafeSpawn("CandyCorn", function()
        if not RattleBoneActive or Generation ~= RattleBoneGeneration then return end

        local DeadlineForDoor = os.clock() + 20
        local DoorCFrame
        repeat
            if not RattleBoneActive or Generation ~= RattleBoneGeneration then return end
            DoorCFrame = GetDoorCFrame()
            if not DoorCFrame then task.wait(0.25) end
        until DoorCFrame or os.clock() >= DeadlineForDoor

        if not DoorCFrame or not RattleBoneActive or Generation ~= RattleBoneGeneration then
            RattleBoneActive = false
            return
        end

        local Character = GetCharacter()
        local Root = GetRoot(Character)
        local Humanoid = GetHumanoid()
        if not Root or not Humanoid or Humanoid.Health <= 0 then
            RattleBoneActive = false
            return
        end

        Root.AssemblyLinearVelocity = Vector3.zero
        Root.AssemblyAngularVelocity = Vector3.zero
        Root.CFrame = DoorCFrame + Vector3.new(0, 3, 0)
        task.wait(0.5)

        while RattleBoneActive and Generation == RattleBoneGeneration do
            local Candies = FindCandycorns()
            if #Candies == 0 then
                local Door = GetDoorCFrame()
                Character = GetCharacter()
                Root = GetRoot(Character)
                Humanoid = GetHumanoid()
                if Door and Root and Humanoid and Humanoid.Health > 0 then
                    local SafeCFrame = Door * CFrame.new(500, 60, 0)
                    CreateSafeBox(SafeCFrame)
                    Root.AssemblyLinearVelocity = Vector3.zero
                    Root.AssemblyAngularVelocity = Vector3.zero
                    Root.CFrame = SafeCFrame + Vector3.new(0, 3, 0)
                    Notify("RattleBone", "CandyCorn not found. SafeBox created and you were teleported there.", 5)
                else
                    Notify("RattleBone", "CandyCorn not found and Portal1 destination is unavailable.", 5)
                end
                RattleBoneActive = false
                break
            else
                for _, Candy in ipairs(Candies) do
                    if not RattleBoneActive or Generation ~= RattleBoneGeneration then return end
                    if Candy and Candy.Parent then
                        local CandyCFrame = GetObjectCFrame(Candy)
                        Character = GetCharacter()
                        Root = GetRoot(Character)
                        Humanoid = GetHumanoid()
                        if CandyCFrame and Root and Humanoid and Humanoid.Health > 0 then
                            Root.AssemblyLinearVelocity = Vector3.zero
                            Root.AssemblyAngularVelocity = Vector3.zero
                            Root.CFrame = CandyCFrame + Vector3.new(0, 3, 0)
                            task.wait(0.35)
                        end
                    end
                end
                task.wait(0.25)
            end
        end
    end, 5)
end

BadgesTab:Section({Title = "CandyCorn Farm", Text = "Teleport to Portal1, then cycle through CandyCorns in workspace.Candies"})
BadgesTab:Toggle({Title = "Auto Farm CandyCorns", Desc = "You need to be in the Lobby", Callback = function(Value)
    if Value then
        StartRattleBone()
    else
        StopRattleBone()
    end
end})

local PumpkinActive = false
local PumpkinGeneration = 0
local PumpkinConnection
local PumpkinPending = {}

local function StopPumpkin()
    PumpkinActive = false
    PumpkinGeneration += 1
    if PumpkinConnection then
        PumpkinConnection:Disconnect()
        PumpkinConnection = nil
    end
    table.clear(PumpkinPending)
end

local function IsInsideCharacter(Object)
    local Parent = Object.Parent
    while Parent and Parent ~= workspace do
        if Players:GetPlayerFromCharacter(Parent) then return true end
        Parent = Parent.Parent
    end
    return false
end

local function IsPumpkinCandidate(Object)
    if Object:IsA("Tool") then
        local Name = string.lower(Object.Name):gsub("%s+", "")
        return string.find(Name, "pumpkin", 1, true) ~= nil
    end
    return Object.Name == "Pumpkin ( Item )"
end

local function GetPumpkinPart(Object)
    if Object:IsA("BasePart") then return Object end
    return Object:FindFirstChild("Handle") or Object:FindFirstChildWhichIsA("BasePart", true)
end

local function QueuePumpkin(Object)
    if PumpkinPending[Object] == nil and not IsInsideCharacter(Object) then
        PumpkinPending[Object] = 0
    end
end

local function FirePumpkinMachine()
    local Machine = workspace:FindFirstChild("PumpkinsMachine")
    local Part = Machine and Machine:FindFirstChild("Pumpkin")
    local Prompt = Part and Part:FindFirstChildWhichIsA("ProximityPrompt", true)
    if not Part or not Prompt then return end
    if not Part:IsA("BasePart") then
        Part = Part:FindFirstChildWhichIsA("BasePart", true)
        if not Part then return end
    end

    pcall(function()
        Prompt.RequiresLineOfSight = false
        Prompt.Enabled = true
    end)

    local NearCFrame = CFrame.new(Part.Position + Vector3.new(0, 2, 0))
    local Deadline = os.clock() + 2.5
    local Fired = 0

    while os.clock() < Deadline and Fired < 3 do
        local Root = GetRoot(GetCharacter())
        local Humanoid = GetHumanoid()
        if not Root or not Humanoid or Humanoid.Health <= 0 then return end

        Root.AssemblyLinearVelocity = Vector3.zero
        Root.AssemblyAngularVelocity = Vector3.zero
        Root.CFrame = NearCFrame
        task.wait(0.3)

        if (Root.Position - Part.Position).Magnitude <= math.max(Prompt.MaxActivationDistance, 8) then
            if typeof(fireproximityprompt) == "function" then
                pcall(function() fireproximityprompt(Prompt) end)
            end
            if Prompt.HoldDuration > 0 then
                pcall(function()
                    Prompt:InputHoldBegin()
                    task.wait(Prompt.HoldDuration + 0.1)
                    Prompt:InputHoldEnd()
                end)
            end
            Fired += 1
        end
        task.wait(0.4)
    end
end

local function StartPumpkin()
    StopPumpkin()
    PumpkinActive = true
    PumpkinGeneration += 1
    local Generation = PumpkinGeneration

    PumpkinConnection = workspace.DescendantAdded:Connect(function(Object)
        if not PumpkinActive or Generation ~= PumpkinGeneration then return end
        if Object:IsA("Tool") or Object:IsA("Model") or Object:IsA("BasePart") then
            task.defer(function()
                if PumpkinActive and Generation == PumpkinGeneration and Object.Parent and IsPumpkinCandidate(Object) then
                    QueuePumpkin(Object)
                end
            end)
        end
    end)

    SafeSpawn("Pumpkin", function()
        local Descendants = workspace:GetDescendants()
        for Index, Object in ipairs(Descendants) do
            if not PumpkinActive or Generation ~= PumpkinGeneration then return end
            if (Object:IsA("Tool") or Object:IsA("Model") or Object:IsA("BasePart")) and IsPumpkinCandidate(Object) then
                QueuePumpkin(Object)
            end
            if Index % 400 == 0 then task.wait() end
        end

        while PumpkinActive and Generation == PumpkinGeneration do
            local Object = next(PumpkinPending)
            if not Object then
                task.wait(0.5)
                continue
            end

            local Attempts = PumpkinPending[Object]
            local Part = Object.Parent and GetPumpkinPart(Object)
            local Root = GetRoot(GetCharacter())
            local Humanoid = GetHumanoid()

            if not Part or Attempts >= 4 or IsInsideCharacter(Object) then
                PumpkinPending[Object] = nil
            elseif Root and Humanoid and Humanoid.Health > 0 then
                PumpkinPending[Object] = Attempts + 1
                local OriginalCFrame = Root.CFrame
                Root.AssemblyLinearVelocity = Vector3.zero
                Root.AssemblyAngularVelocity = Vector3.zero
                Root.CFrame = Part.CFrame + Vector3.new(0, 3, 0)
                task.wait(0.15)
                if typeof(firetouchinterest) == "function" then
                    pcall(function()
                        firetouchinterest(Root, Part, 0)
                        task.wait(0.1)
                        firetouchinterest(Root, Part, 1)
                    end)
                end
                task.wait(0.3)
                if not Object.Parent or not Object:IsDescendantOf(workspace) then
                    PumpkinPending[Object] = nil
                    Notify("Pumpkin", "Pumpkin picked up.", 3)
                    FirePumpkinMachine()
                end
                local ReturnRoot = GetRoot(GetCharacter())
                if ReturnRoot and PumpkinActive and Generation == PumpkinGeneration then
                    ReturnRoot.AssemblyLinearVelocity = Vector3.zero
                    ReturnRoot.CFrame = OriginalCFrame
                end
            else
                task.wait(0.5)
            end
            task.wait(0.2)
        end
    end, 5)
end

BadgesTab:Section({Title = "Pumpkin Item", Text = "Scans for Pumpkin tools and touches them as they appear"})
BadgesTab:Toggle({Title = "Auto Get Pumpkin", Desc = "You need to be in the Arena", Callback = function(Value)
    if Value then
        StartPumpkin()
    else
        StopPumpkin()
    end
end})

BadgesTab:Section({Title = "Moon Glove", Text = "Click the epic duck to get Moon Glove"})
BadgesTab:Button({Title = "Get Moon Glove", Desc = "You need to be in the Lobby", Callback = function()
    local Duck = workspace:FindFirstChild("epic duck")
    if not Duck then return end
    local Detector
    if Duck:IsA("ClickDetector") then
        Detector = Duck
    else
        Detector = Duck:FindFirstChildWhichIsA("ClickDetector", true)
    end
    if Detector and typeof(fireclickdetector) == "function" then
        pcall(function()
            fireclickdetector(Detector)
        end)
    end
end})

local ChairGloveActive = false
local ChairGloveGeneration = 0
local function StopChairGlove()
    ChairGloveActive = false
    ChairGloveGeneration += 1
    local Humanoid = GetHumanoid()
    if Humanoid and Humanoid.Health > 0 then
        Humanoid.Jump = true
        pcall(function()
            Humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
        end)
    end
end
local function StartChairGlove()
    ChairGloveActive = false
    ChairGloveGeneration += 1
    ChairGloveActive = true
    ChairGloveGeneration += 1
    local Generation = ChairGloveGeneration
    SafeSpawn("Chair Glove", function()
        local Lobby = workspace:FindFirstChild("Lobby")
        local Decoration = Lobby and Lobby:FindFirstChild("Decoration")
        local Chair = Decoration and Decoration:FindFirstChild("Chair")
        local Seat = Chair and Chair:FindFirstChild("Seat")
        if not Seat or not Seat:IsA("BasePart") then
            ChairGloveActive = false
            return
        end
        local Character = GetCharacter()
        local Root = GetRoot(Character)
        local Humanoid = GetHumanoid()
        if not Root or not Humanoid or Humanoid.Health <= 0 then
            ChairGloveActive = false
            return
        end
        Root.AssemblyLinearVelocity = Vector3.zero
        Root.AssemblyAngularVelocity = Vector3.zero
        Root.CFrame = Seat.CFrame * CFrame.new(0, 3, 0)
        local Deadline = os.clock() + 1800
        while ChairGloveActive and Generation == ChairGloveGeneration and os.clock() < Deadline do
            task.wait(0.5)
        end
        if Generation == ChairGloveGeneration then ChairGloveActive = false end
    end)
end
BadgesTab:Section({Title = "Chair Glove", Text = "Automatically visit the chair and wait for the unlock"})
BadgesTab:Toggle({Title = "Auto Get Chair Glove", Desc = "You need to be in the Lobby", Callback = function(Value)
    if Value then
        StartChairGlove()
    else
        StopChairGlove()
    end
end})
local TNTActive = false
local function StopTNT()
    TNTActive = false
    TNTGeneration += 1
end

local function GetPromptPosition(Prompt)
    local Parent = Prompt.Parent
    if Parent and Parent:IsA("BasePart") then
        return Parent.Position
    end
    if Parent and Parent:IsA("Attachment") then
        local Part = Parent.Parent
        if Part and Part:IsA("BasePart") then
            return Parent.WorldPosition
        end
    end
    return nil
end

local function GetNearbyPrompt(Root, Prompts)
    if not Root then return nil end
    local BestPrompt
    local BestDistance = math.huge
    for _, Prompt in ipairs(Prompts) do
        if Prompt.Parent and Prompt.Enabled then
            local Position = GetPromptPosition(Prompt)
            if Position then
                local Distance = (Root.Position - Position).Magnitude
                local AllowedDistance = math.max(Prompt.MaxActivationDistance + 5, 12)
                if Distance <= AllowedDistance and Distance < BestDistance then
                    BestPrompt = Prompt
                    BestDistance = Distance
                end
            end
        end
    end
    return BestPrompt
end

local function ClickScreen()
    local Camera = workspace.CurrentCamera
    if not Camera then return false end
    local Viewport = Camera.ViewportSize
    local X = math.floor(Viewport.X / 2)
    local Y = math.floor(Viewport.Y / 2)

    if typeof(tap) == "function" then
        return pcall(function() tap(X, Y) end)
    end

    local Success = pcall(function()
        local VirtualInput = game:GetService("VirtualInputManager")
        VirtualInput:SendMouseButtonEvent(X, Y, 0, true, game, 0)
        task.wait(0.08)
        VirtualInput:SendMouseButtonEvent(X, Y, 0, false, game, 0)
    end)
    return Success
end

local function StartTNT()
    StopTNT()
    TNTActive = true
    TNTGeneration += 1
    local Generation = TNTGeneration

    SafeSpawn("TNT Glove", function()
        local function IsCurrent()
            return TNTActive and Generation == TNTGeneration
        end
        local function NotifyTNT(Message)
        end

        local DoorCFrame = GetDoorCFrame()
        if not DoorCFrame then
            NotifyTNT("Could not find workspace.Lobby.PORTAL1.DOOR")
            if Generation == TNTGeneration then TNTActive = false end
            return
        end

        local Character = GetCharacter()
        local Root = GetRoot(Character)
        local Humanoid = GetHumanoid()
        if not Root or not Humanoid or Humanoid.Health <= 0 then
            if Generation == TNTGeneration then TNTActive = false end
            return
        end

        Root.AssemblyLinearVelocity = Vector3.zero
        Root.AssemblyAngularVelocity = Vector3.zero
        Root.CFrame = DoorCFrame
        task.wait(1.2)
        if not IsCurrent() then return end

        Root = GetRoot(GetCharacter())
        Humanoid = GetHumanoid()
        if not Root or not Humanoid or Humanoid.Health <= 0 then
            if Generation == TNTGeneration then TNTActive = false end
            return
        end

        Root.AssemblyLinearVelocity = Vector3.zero
        Root.AssemblyAngularVelocity = Vector3.zero
        Root.CFrame = CFrame.new(-381, 45247, 107)
        task.wait(0.6)
        if not IsCurrent() then return end

        local Prompts = {}
        for Index, Object in ipairs(workspace:GetDescendants()) do
            if Object:IsA("ProximityPrompt") then
                table.insert(Prompts, Object)
            end
            if Index % 600 == 0 then
                task.wait()
                if not IsCurrent() then return end
            end
        end

        local Deadline = os.clock() + 20
        local Triggered = false
        local AttemptedPrompt = nil

        while IsCurrent() and os.clock() < Deadline do
            Root = GetRoot(GetCharacter())
            Humanoid = GetHumanoid()
            if not Root or not Humanoid or Humanoid.Health <= 0 then
                task.wait(0.3)
                continue
            end

            local Prompt = GetNearbyPrompt(Root, Prompts)
            if Prompt and Prompt ~= AttemptedPrompt and typeof(fireproximityprompt) == "function" then
                AttemptedPrompt = Prompt
                local Success = pcall(function()
                    fireproximityprompt(Prompt)
                end)
                if Success then
                    Triggered = true
                    break
                end
            end
            task.wait(0.35)
        end

        if not IsCurrent() then return end
        if not Triggered then
            NotifyTNT("No nearby prompt was activated. Check the TNT coordinates and executor support.")
            TNTActive = false
            return
        end

        task.wait(0.5)
        if not IsCurrent() then return end
        local ClickWorked = ClickScreen()
        if not ClickWorked then
            NotifyTNT("The screen click could not be simulated by this executor. Tap the screen manually if needed.")
        end

        local WaitStarted = os.clock()
        while IsCurrent() and os.clock() - WaitStarted < 4 do
            task.wait(0.2)
        end
        if Generation == TNTGeneration then TNTActive = false end
    end)
end

BadgesTab:Section({Title = "TNT Glove", Text = "Search nearby prompts after teleporting to the TNT area"})
BadgesTab:Button({
    Title = "Auto Get TNT Glove",
    Desc = "You need to be in the Lobby",
    Callback = function()
        StartTNT()
    end
})

local TrapGloveActive = false
local TrapGloveGeneration = 0
RemoveSafeBox = function()
    if SafeBoxModel then
        SafeBoxModel:Destroy()
        SafeBoxModel = nil
    end
    local Existing = workspace:FindFirstChild("SafeBox")
    if Existing then Existing:Destroy() end
end

local function StopTrapGlove()
    TrapGloveActive = false
    TrapGloveGeneration += 1
    RemoveSafeBox()
end

local function GetDoor1CFrame()
    local Lobby = workspace:FindFirstChild("Lobby")
    local Portal = Lobby and Lobby:FindFirstChild("PORTAL1")
    local Door = Portal and Portal:FindFirstChild("DOOR")
    if not Door then return nil end
    if Door:IsA("BasePart") then return Door.CFrame end
    if Door:IsA("Model") then return Door:GetPivot() end
    local Part = Door:FindFirstChildWhichIsA("BasePart", true)
    return Part and Part.CFrame or nil
end

CreateSafeBox = function(Center)
    RemoveSafeBox()
    local Model = Instance.new("Model")
    Model.Name = "SafeBox"
    Model.Parent = workspace

    local function MakePart(Name, Size, Offset)
        local Part = Instance.new("Part")
        Part.Name = Name
        Part.Size = Size
        Part.CFrame = Center * CFrame.new(Offset)
        Part.Anchored = true
        Part.CanCollide = true
        Part.CanTouch = false
        Part.CanQuery = false
        Part.Material = Enum.Material.Plastic
        Part.TopSurface = Enum.SurfaceType.Studs
        Part.BottomSurface = Enum.SurfaceType.Inlet
        Part.Color = Color3.fromRGB(100, 100, 100)
        Part.Transparency = 0.12
        Part.Parent = Model
        return Part
    end

    MakePart("SafeBoxFloor", Vector3.new(80, 1, 80), Vector3.new(0, -4.5, 0))
    MakePart("SafeBoxWall", Vector3.new(1, 40, 80), Vector3.new(-39.5, 15.5, 0))
    MakePart("SafeBoxWall", Vector3.new(1, 40, 80), Vector3.new(39.5, 15.5, 0))
    MakePart("SafeBoxWall", Vector3.new(78, 40, 1), Vector3.new(0, 15.5, -39.5))
    MakePart("SafeBoxWall", Vector3.new(78, 40, 1), Vector3.new(0, 15.5, 39.5))
    MakePart("SafeBoxRoof", Vector3.new(80, 1, 80), Vector3.new(0, 35.5, 0))
    SafeBoxModel = Model
    return Model
end

local FishGloveActive = false
local FishGloveGeneration = 0
local function StopFishGlove()
    FishGloveActive = false
    FishGloveGeneration += 1
    RemoveSafeBox()
end
local function StartFishGlove()
    StopFishGlove()
    FishGloveActive = true
    FishGloveGeneration += 1
    local Generation = FishGloveGeneration
    SafeSpawn("Fish Glove", function()
        local function IsCurrent()
            return FishGloveActive and Generation == FishGloveGeneration
        end
        local function WaitWhileActive(Duration)
            local Deadline = os.clock() + Duration
            while IsCurrent() and os.clock() < Deadline do task.wait(0.25) end
            return IsCurrent()
        end
        local Stands = workspace:FindFirstChild("Stands")
        local Stand = Stands and Stands:FindFirstChild("ZZZZZZZ")
        local Glove = Stand and Stand:FindFirstChild("Glove")
        if not Glove or not Glove:IsA("MeshPart") then
            FishGloveActive = false
            return
        end
        local Character = GetCharacter()
        local Root = GetRoot(Character)
        local Humanoid = GetHumanoid()
        if not Root or not Humanoid or Humanoid.Health <= 0 then FishGloveActive = false return end
        Root.AssemblyLinearVelocity = Vector3.zero
        Root.AssemblyAngularVelocity = Vector3.zero
        Root.CFrame = Glove.CFrame * CFrame.new(0, 2.5, 0)
        if typeof(firetouchinterest) == "function" then
            pcall(function()
                firetouchinterest(Root, Glove, 0)
                task.wait(0.15)
                firetouchinterest(Root, Glove, 1)
            end)
        end
        local Detector = Glove:FindFirstChildWhichIsA("ClickDetector", true)
        if Detector and typeof(fireclickdetector) == "function" then
            pcall(function() fireclickdetector(Detector) end)
        end
        if not WaitWhileActive(0.8) then return end
        local DoorCFrame = GetDoorCFrame()
        Character = GetCharacter()
        Root = GetRoot(Character)
        Humanoid = GetHumanoid()
        if not DoorCFrame or not Root or not Humanoid or Humanoid.Health <= 0 then
            FishGloveActive = false
            return
        end
        Root.AssemblyLinearVelocity = Vector3.zero
        Root.AssemblyAngularVelocity = Vector3.zero
        Root.CFrame = DoorCFrame * CFrame.new(0, 4, 0)
        if not WaitWhileActive(1.2) then return end
        Character = GetCharacter()
        Root = GetRoot(Character)
        Humanoid = GetHumanoid()
        if not Root or not Humanoid or Humanoid.Health <= 0 then FishGloveActive = false return end
        Root.AssemblyLinearVelocity = Vector3.zero
        Root.AssemblyAngularVelocity = Vector3.zero
        Root.CFrame = DoorCFrame * CFrame.new(500, 60, 0)
        if not WaitWhileActive(0.3) then return end
        Character = GetCharacter()
        Root = GetRoot(Character)
        Humanoid = GetHumanoid()
        if not Root or not Humanoid or Humanoid.Health <= 0 then FishGloveActive = false return end
        CreateSafeBox(Root.CFrame)
        local EventHolder = Character:FindFirstChild("ZZZZZZZ")
        local Event = EventHolder and EventHolder:FindFirstChild("Event")
        if Event and Event:IsA("RemoteEvent") then
            pcall(function() Event:FireServer("stone", false) end)
        end
        WaitWhileActive(600)
        if Generation == FishGloveGeneration then FishGloveActive = false end
        RemoveSafeBox()
    end)
end

local function StartTrapGlove()
    StopTrapGlove()
    TrapGloveActive = true
    TrapGloveGeneration += 1
    local Generation = TrapGloveGeneration

    SafeSpawn("Trap Glove", function()
        local function IsCurrent()
            return TrapGloveActive and Generation == TrapGloveGeneration
        end

        local Clicked = false
        while IsCurrent() and not Clicked do
            local Stands = workspace:FindFirstChild("Stands")
            local Brick = Stands and Stands:FindFirstChild("Brick")
            local Glove = Brick and Brick:FindFirstChild("Glove")
            local Detector = Glove and Glove:FindFirstChild("ClickDetector")

            if Detector and Detector:IsA("ClickDetector") and typeof(fireclickdetector) == "function" then
                local Success = pcall(function()
                    fireclickdetector(Detector)
                end)
                if Success then Clicked = true end
            end

            if not Clicked then task.wait(0.5) end
        end
        if not IsCurrent() then return end

        task.wait(0.25)
        local DoorCFrame = GetDoor1CFrame()
        local Character = GetCharacter()
        local Root = GetRoot(Character)
        local Humanoid = GetHumanoid()

        if not DoorCFrame or not Root or not Humanoid or Humanoid.Health <= 0 then
            pcall(function()
            end)
            while IsCurrent() do task.wait(0.5) end
            return
        end

        Root.AssemblyLinearVelocity = Vector3.zero
        Root.AssemblyAngularVelocity = Vector3.zero
        Root.CFrame = DoorCFrame * CFrame.new(0, 4, 0)
        task.wait(1.5)
        if not IsCurrent() then return end

        Character = GetCharacter()
        Root = GetRoot(Character)
        Humanoid = GetHumanoid()
        if not Root or not Humanoid or Humanoid.Health <= 0 then
            while IsCurrent() do task.wait(0.5) end
            return
        end

        Root.AssemblyLinearVelocity = Vector3.zero
        Root.AssemblyAngularVelocity = Vector3.zero
        Root.CFrame = DoorCFrame * CFrame.new(500, 60, 0)
        task.wait(0.15)
        if not IsCurrent() then return end

        Character = GetCharacter()
        Root = GetRoot(Character)
        Humanoid = GetHumanoid()
        if not Root or not Humanoid or Humanoid.Health <= 0 then
            while IsCurrent() do task.wait(0.5) end
            return
        end

        local Float = Instance.new("BodyPosition")
        Float.Name = "SafeBoxCreateFloat"
        Float.MaxForce = Vector3.new(0, 1e9, 0)
        Float.P = 1e5
        Float.D = 1e4
        Float.Position = Root.Position + Vector3.new(0, 8, 0)
        Float.Parent = Root
        task.wait(0.45)
        if not IsCurrent() then
            if Float and Float.Parent then Float:Destroy() end
            return
        end

        Character = GetCharacter()
        Root = GetRoot(Character)
        Humanoid = GetHumanoid()
        if not Root or not Humanoid or Humanoid.Health <= 0 then
            if Float and Float.Parent then Float:Destroy() end
            while IsCurrent() do task.wait(0.5) end
            return
        end

        local BoxCenter = Root.CFrame
        CreateSafeBox(BoxCenter)
        if Float and Float.Parent then Float:Destroy() end
        Root.AssemblyLinearVelocity = Vector3.zero
        Root.AssemblyAngularVelocity = Vector3.zero

        while IsCurrent() do
            local Holder = workspace:FindFirstChild(LocalPlayer.Name)
            local BrickFolder = Holder and Holder:FindFirstChild("Brick")
            local Event = BrickFolder and BrickFolder:FindFirstChild("Event")
            if Event and Event:IsA("RemoteEvent") then
                pcall(function() Event:FireServer("lego") end)
            end

            task.wait(1)
        end
    end)
end

local EludeActive = false
local EludeGeneration = 0

local function StopElude()
    EludeActive = false
    EludeGeneration += 1
end

local function StartElude()
    if game.PlaceId == ELUDE_PLACE_ID then
        TeleportToEludeTarget(true)
        return
    end

    StopElude()
    EludeActive = true
    EludeGeneration += 1
    local Generation = EludeGeneration

    SafeSpawn("Elude Glove", function()
        local Map = workspace:FindFirstChild("Slap Battles Map")
        local MoaiIsland = Map and Map:FindFirstChild("MoaiIsland")
        local Island = MoaiIsland and MoaiIsland:FindFirstChild("Island")
        local Keypad = Island and Island:FindFirstChild("Keypad")
        local Buttons = Keypad and Keypad:FindFirstChild("Buttons")
        if not Buttons then
            EludeActive = false
            TeleportToEludeTarget(false)
            return
        end

        local function ClickButton(Name)
            if not EludeActive or Generation ~= EludeGeneration then return false end
            local Button = Buttons:FindFirstChild(Name)
            local Detector = Button and Button:FindFirstChildWhichIsA("ClickDetector", true)
            if not Button or not Button:IsA("BasePart") or not Detector or typeof(fireclickdetector) ~= "function" then
                EludeActive = false
                return false
            end
            local ok = pcall(function() fireclickdetector(Detector) end)
            if not ok then
                EludeActive = false
                return false
            end
            task.wait(0.35)
            return EludeActive and Generation == EludeGeneration
        end

        for _, Name in ipairs({"B6", "B9", "B6", "B9", "Enter"}) do
            if not ClickButton(Name) then return end
        end

        if Generation == EludeGeneration then
            EludeActive = false
        end
    end)
end

BadgesTab:Section({Title = "Elude Glove", Text = "Complete the Elude unlock sequence"})
BadgesTab:Toggle({Title = "Auto Get Elude Glove", Desc = "You need to be in the Arena", Callback = function(Value) if Value then StartElude() else StopElude() end end})

task.defer(function()
    if game.PlaceId == ELUDE_PLACE_ID then
        TeleportToEludeTarget(true)
    end
end)

BadgesTab:Section({Title = "Fish Glove", Text = "Automatically perform the Fish Glove unlock"})
BadgesTab:Toggle({Title = "Auto Get Fish Glove", Desc = "Requires 20 Slaps", Callback = function(Value)
    if Value then
        if RequireSlaps("Auto Get Fish Glove", 20, "ZZZ Glove") then StartFishGlove() end
    else
        StopFishGlove()
    end
end})

local BombGloveActive = false
local BombGloveGeneration = 0

local function StopBombGlove()
    BombGloveActive = false
    BombGloveGeneration += 1
    RemoveSafeBox()
end

local function StartBombGlove()
    StopBombGlove()
    BombGloveActive = true
    BombGloveGeneration += 1
    local Generation = BombGloveGeneration

    SafeSpawn("Bomb Glove", function()
        local function IsCurrent()
            return BombGloveActive and Generation == BombGloveGeneration
        end

        local Clicked = false
        local ClickDeadline = os.clock() + 15

        while IsCurrent() and not Clicked and os.clock() < ClickDeadline do
            local Stands = workspace:FindFirstChild("Stands")
            local CreeperStand = Stands and Stands:FindFirstChild("Creeper")
            local Glove = CreeperStand and CreeperStand:FindFirstChild("Glove")
            local Detector = Glove and Glove:FindFirstChild("ClickDetector")

            if Detector and Detector:IsA("ClickDetector") and typeof(fireclickdetector) == "function" then
                local Success = pcall(function()
                    fireclickdetector(Detector)
                end)
                if Success then Clicked = true end
            end

            if not Clicked then task.wait(0.25) end
        end

        if not IsCurrent() then return end

        task.wait(0.25)
        if not IsCurrent() then return end

        local DoorCFrame = GetDoor1CFrame()
        local Character = GetCharacter()
        local Root = GetRoot(Character)
        local Humanoid = GetHumanoid()

        if not DoorCFrame or not Root or not Humanoid or Humanoid.Health <= 0 then
            pcall(function()
            end)
            while IsCurrent() do task.wait(0.5) end
            return
        end

        Root.AssemblyLinearVelocity = Vector3.zero
        Root.AssemblyAngularVelocity = Vector3.zero
        Root.CFrame = DoorCFrame * CFrame.new(0, 4, 0)

        task.wait(1.5)
        if not IsCurrent() then return end

        Character = GetCharacter()
        Root = GetRoot(Character)
        Humanoid = GetHumanoid()

        if not Root or not Humanoid or Humanoid.Health <= 0 then
            while IsCurrent() do task.wait(0.5) end
            return
        end

        Root.AssemblyLinearVelocity = Vector3.zero
        Root.AssemblyAngularVelocity = Vector3.zero
        Root.CFrame = DoorCFrame * CFrame.new(500, 60, 0)

        task.wait(0.15)
        if not IsCurrent() then return end

        Character = GetCharacter()
        Root = GetRoot(Character)
        Humanoid = GetHumanoid()

        if not Root or not Humanoid or Humanoid.Health <= 0 then
            while IsCurrent() do task.wait(0.5) end
            return
        end

        local Float = Instance.new("BodyPosition")
        Float.Name = "BombSafeBoxCreateFloat"
        Float.MaxForce = Vector3.new(0, 1e9, 0)
        Float.P = 1e5
        Float.D = 1e4
        Float.Position = Root.Position + Vector3.new(0, 8, 0)
        Float.Parent = Root

        task.wait(0.45)
        if not IsCurrent() then
            if Float and Float.Parent then Float:Destroy() end
            return
        end

        Character = GetCharacter()
        Root = GetRoot(Character)
        Humanoid = GetHumanoid()

        if not Root or not Humanoid or Humanoid.Health <= 0 then
            if Float and Float.Parent then Float:Destroy() end
            while IsCurrent() do task.wait(0.5) end
            return
        end

        CreateSafeBox(Root.CFrame)
        if Float and Float.Parent then Float:Destroy() end
        Root.AssemblyLinearVelocity = Vector3.zero
        Root.AssemblyAngularVelocity = Vector3.zero

        while IsCurrent() do
            local Backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
            local CharacterNow = LocalPlayer.Character
            local Creeper = (Backpack and Backpack:FindFirstChild("Creeper"))
                or (CharacterNow and CharacterNow:FindFirstChild("Creeper"))
            local Event = Creeper and Creeper:FindFirstChild("Event", true)

            if Event and Event:IsA("RemoteEvent") then
                pcall(function()
                    Event:FireServer("glove")
                end)
            end

            task.wait(3)
        end
    end)
end

BadgesTab:Section({Title = "Bomb Glove", Text = "Run the Bomb Glove unlock sequence"})
BadgesTab:Toggle({Title = "Auto Get Bomb Glove", Desc = "Requires Creeper Glove", Callback = function(Value) if Value then StartBombGlove() else StopBombGlove() end end})

BadgesTab:Section({Title = "Trap Glove", Text = "Automatically perform the Trap Glove unlock"})
BadgesTab:Toggle({
    Title = "Auto Get Trap Glove",
    Desc = "Requires 50 Slaps",
    Callback = function(Value)
        if Value then
            if RequireSlaps("Auto Get Trap Glove", 50, "Brick Glove") then StartTrapGlove() end
        else
            StopTrapGlove()
        end
    end
})

local PhaseOrbActive = false
local PhaseOrbGeneration = 0
local function GetPhaseOrbCFrame(Orb)
    if not Orb then return nil end
    if Orb:IsA("BasePart") then return Orb.CFrame end
    if Orb:IsA("Model") then return Orb:GetPivot() end
    local Part = Orb:FindFirstChildWhichIsA("BasePart", true)
    return Part and Part.CFrame or nil
end
local function StopPhaseOrb()
    PhaseOrbActive = false
    PhaseOrbGeneration += 1
end
local function StartPhaseOrb()
    StopPhaseOrb()
    PhaseOrbActive = true
    PhaseOrbGeneration += 1
    local Generation = PhaseOrbGeneration
    SafeSpawn("Phase Orb", function()
        local LastOrb = nil
        while PhaseOrbActive and Generation == PhaseOrbGeneration do
            local Orb = workspace:FindFirstChild("PhaseOrb")
            if not Orb then
                LastOrb = nil
                task.wait(0.25)
                continue
            end
            if Orb ~= LastOrb then
                LastOrb = Orb
                local OriginalCharacter = GetCharacter()
                local OriginalRoot = GetRoot(OriginalCharacter)
                local OriginalCFrame = OriginalRoot and OriginalRoot.CFrame
                local OrbCFrame = GetPhaseOrbCFrame(Orb)
                if OriginalRoot and OriginalCFrame and OrbCFrame then
                    OriginalRoot.AssemblyLinearVelocity = Vector3.zero
                    OriginalRoot.AssemblyAngularVelocity = Vector3.zero
                    OriginalRoot.CFrame = OrbCFrame + Vector3.new(0, 3, 0)
                    task.wait(0.15)
                    local CurrentRoot = GetRoot(GetCharacter())
                    local OrbPart = Orb:IsA("BasePart") and Orb or Orb:FindFirstChildWhichIsA("BasePart", true)
                    if CurrentRoot and OrbPart and typeof(firetouchinterest) == "function" then
                        pcall(function()
                            firetouchinterest(CurrentRoot, OrbPart, 0)
                            task.wait(0.1)
                            firetouchinterest(CurrentRoot, OrbPart, 1)
                        end)
                    end
                    local WaitStarted = os.clock()
                    while PhaseOrbActive and Generation == PhaseOrbGeneration and os.clock() - WaitStarted < 5 do
                        task.wait(0.1)
                    end
                    if PhaseOrbActive and Generation == PhaseOrbGeneration then
                        local ReturnRoot = GetRoot(GetCharacter())
                        if ReturnRoot and GetHumanoid() and GetHumanoid().Health > 0 then
                            ReturnRoot.AssemblyLinearVelocity = Vector3.zero
                            ReturnRoot.AssemblyAngularVelocity = Vector3.zero
                            ReturnRoot.CFrame = OriginalCFrame
                        end
                    end
                end
            end
            task.wait(0.25)
        end
    end, 5)
end
BadgesTab:Section({Title = "Phase Orb", Text = "Automatically visit PhaseOrb when it appears"})
BadgesTab:Toggle({Title = "Auto Touch Phase Orb", Desc = "You need to be in the Arena", Callback = function(Value) if Value then StartPhaseOrb() else StopPhaseOrb() end end})

MapTab:Section({Title = "Teleport Tool", Text = "A tool that teleports you to wherever you click"})
MapTab:Button({Title = "Get Teleport Tool", Desc = "Click anywhere with it equipped to teleport", Callback = function()
    local Backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
    if Backpack and Backpack:FindFirstChild("Teleport Tool") then
        Notify("Teleport Tool", "You already have it.", 3)
        return
    end
    local ToolInstance = Instance.new("Tool")
    ToolInstance.Name = "Teleport Tool"
    ToolInstance.RequiresHandle = false
    ToolInstance.CanBeDropped = false
    ToolInstance.ToolTip = "Click anywhere to teleport"
    ToolInstance.Activated:Connect(function()
        local Root = GetRoot(GetCharacter())
        if not Root then return end
        local Mouse = LocalPlayer:GetMouse()
        local Target = Mouse.Hit and Mouse.Hit.Position
        if not Target then return end
        Root.CFrame = CFrame.new(Target + Vector3.new(0, 3, 0))
    end)
    ToolInstance.Parent = Backpack
    Notify("Teleport Tool", "Added to your backpack.", 3)
end})

MapTab:Section({Title = "Island Teleport", Text = "Select an island and teleport to its coordinates"})
local IslandLocations = {
    ["Kabo's Basement"] = Vector3.new(-171, 158, -199),
    ["Moai Island"] = Vector3.new(226, 45227, 119),
    ["Lolipop Island"] = Vector3.new(-162, 45228, 104),
    ["Slapple Island"] = Vector3.new(-358, 45283, 106),
    ["Desert Island"] = Vector3.new(29, 45228, -76),
    ["Snow Island"] = Vector3.new(39, 45228, 333)
}
local SelectedIsland
MapTab:Dropdown({Title = "Select Island", Desc = "Pick an island to teleport to", Values = {"Kabo's Basement", "Moai Island", "Lolipop Island", "Slapple Island", "Desert Island", "Snow Island"}, AllowNone = true, Callback = function(Value)
    if typeof(Value) == "string" and IslandLocations[Value] then
        SelectedIsland = Value
    else
        SelectedIsland = nil
    end
end})
MapTab:Button({Title = "Teleport to Island", Desc = "Select an island first", Callback = function()
    local Position = SelectedIsland and IslandLocations[SelectedIsland]
    local Character = GetCharacter()
    local Root = GetRoot(Character)
    local Humanoid = GetHumanoid()
    if not Position or not Root or not Humanoid or Humanoid.Health <= 0 then
        return
    end
    Root.AssemblyLinearVelocity = Vector3.zero
    Root.AssemblyAngularVelocity = Vector3.zero
    Root.CFrame = CFrame.new(Position + Vector3.new(0, 5, 0))
end})

table.insert(ScriptConnections, LocalPlayer.CharacterAdded:Connect(function()
    task.wait(1)
    ApplyMovement()
    if State.Noclip then StartNoclip() end
    if State.Fly then StartFly() end
    if State.AntiRagdoll then StartAntiRagdoll() end
    if State.AntiFreeze then StartAntiFreeze() end
    if State.AntiVoid then StartAntiVoid() end
    if State.AntiCubeOfDeath then StartAntiCubeOfDeath() end
    if State.ESP then RefreshESP() end
end))

do
    local SettingsTab = Window:Tab({Title = "Settings", Icon = "settings"})

    local function StopAllFeatures()
        SettingsStore.Paused = true
        task.delay(1.5, function() SettingsStore.Paused = false end)
        for _, Element in ipairs(AllToggles) do
            pcall(function() Element:Set(false) end)
        end
        for _, Stopper in ipairs({StopFly, StopInfiniteJump, StopAntiRagdoll, StopAntiFreeze, StopAntiAFK, StopAntiVoid, StopAntiCubeOfDeath, StopNoclip, StopFarm, StopBadge, StopAntiDisarm, StopRattleBone, StopPumpkin, StopChairGlove, StopTNT, StopTrapGlove, StopFishGlove, StopElude, StopBombGlove, StopPhaseOrb}) do
            pcall(Stopper)
        end
        pcall(SetESP, false)
    end

    local function Unload(SkipDestroy)
        StopAllFeatures()
        for _, Connection in ipairs(ScriptConnections) do
            pcall(function() Connection:Disconnect() end)
        end
        table.clear(ScriptConnections)
        for Player, Connection in pairs(PlayerConnections) do
            pcall(function() Connection:Disconnect() end)
            PlayerConnections[Player] = nil
        end
        if not SkipDestroy then pcall(function() Window:Destroy() end) end
        Env.Fyrex_zCleanup = nil
    end
    Env.Fyrex_zCleanup = Unload
    pcall(function() Window:OnDestroy(function() Unload(true) end) end)

    pcall(function()
        local SavedKey = SettingsStore.Data.Values.UIKey
        Window:SetToggleKey((SavedKey and Enum.KeyCode[SavedKey]) or Enum.KeyCode.RightShift)
    end)

    SettingsTab:Section({Title = "Interface", Text = "Window and notification options"})
    SettingsTab:Input({Title = "Toggle UI Key", Desc = "Type a key name like RightShift or K", Placeholder = "RightShift", Callback = function(Value)
        local Success, Code = pcall(function() return Enum.KeyCode[tostring(Value)] end)
        if Success and Code then
            pcall(function() Window:SetToggleKey(Code) end)
            SettingsStore.SetValue("UIKey", Code.Name)
            Notify("Settings", "UI key set to " .. Code.Name, 3)
        else
            Notify("Settings", "That key name was not found.", 3)
        end
    end})
    local NotificationsToggle = SettingsTab:Toggle({Title = "Notifications", Desc = "Show script notifications", Value = NotificationsEnabled, Default = NotificationsEnabled, Callback = function(Value)
        NotificationsEnabled = Value and true or false
        SettingsStore.SetValue("Notifications", NotificationsEnabled)
    end})
    if NotificationsToggle and NotificationsEnabled then
        task.defer(function() pcall(function() NotificationsToggle:Set(true) end) end)
    end

    SettingsTab:Button({Title = "Clear Saved Settings", Desc = "Forget saved toggles, sliders and keys", Callback = function()
        SettingsStore.Data = {Toggles = {}, Values = {}}
        if typeof(writefile) == "function" then
            pcall(function() writefile(SettingsStore.File, HttpService:JSONEncode(SettingsStore.Data)) end)
        end
        Notify("Settings", "Saved settings cleared.", 3)
    end})

    SettingsTab:Section({Title = "Server", Text = "Rejoin or switch servers"})
    SettingsTab:Button({Title = "Rejoin Server", Desc = "Rejoin the same server", Callback = function()
        pcall(function()
            if #Players:GetPlayers() <= 1 then
                TeleportService:Teleport(game.PlaceId, LocalPlayer)
            else
                TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer)
            end
        end)
    end})
    SettingsTab:Button({Title = "Server Hop", Desc = "Join a different public server", Callback = function()
        task.spawn(function()
            local Success, Result = pcall(function()
                local Url = "https://games.roblox.com/v1/games/" .. game.PlaceId .. "/servers/Public?sortOrder=Asc&limit=100"
                return HttpService:JSONDecode(game:HttpGet(Url))
            end)
            local Servers = Success and type(Result) == "table" and Result.data
            if type(Servers) ~= "table" then
                Notify("Server Hop", "Could not get the server list.", 4)
                return
            end
            local Options = {}
            for _, Server in ipairs(Servers) do
                if Server.id ~= game.JobId and Server.playing and Server.maxPlayers and Server.playing < Server.maxPlayers then
                    table.insert(Options, Server.id)
                end
            end
            if #Options == 0 then
                Notify("Server Hop", "No other server found.", 4)
                return
            end
            pcall(function() TeleportService:TeleportToPlaceInstance(game.PlaceId, Options[math.random(#Options)], LocalPlayer) end)
        end)
    end})
    SettingsTab:Button({Title = "Copy Server ID", Desc = "Copies the current server ID", Callback = function()
        if typeof(setclipboard) == "function" then
            pcall(function() setclipboard(game.JobId) end)
            Notify("Settings", "Server ID copied.", 3)
        else
            Notify("Settings", "Your executor cannot copy to clipboard.", 3)
        end
    end})

end

task.spawn(function()
    task.wait(0.5)
    local Restorable = {["Infinite Jump"] = true, ["Noclip"] = true, ["Fly Noclip"] = true, ["Anti-Ragdoll"] = true, ["Anti-Disarm"] = true, ["Anti-Freeze"] = true, ["Anti-AFK"] = true, ["Anti-Void"] = true, ["Anti-CubeOfDeath"] = true, ["ESP Players"] = true}
    for _, Entry in ipairs(SettingsStore.Entries) do
        if Restorable[Entry.Title] and SettingsStore.Data.Toggles[Entry.Title] == true then
            Entry.Fired = false
            if Entry.Element then pcall(function() Entry.Element:Set(true) end) end
            task.wait(0.1)
            if not Entry.Fired and Entry.Original then pcall(Entry.Original, true) end
            task.wait(0.1)
        end
    end
    local Saved = SettingsStore.Data.Values
    if Saved.WalkSpeed or Saved.JumpPower then pcall(ApplyMovement) end
end)

pcall(function() Notify("Fyrex_z", "Credits to: @Fyrex_z on YouTube", 5) end)
