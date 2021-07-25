local Knit = require(game:GetService("ReplicatedStorage").Knit)
local Signal = require(Knit.Util.Signal)
local PathfindingService = game:GetService("PathfindingService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local MonsterService = Knit.GetService("MonsterService")

local BaseClass = {}
BaseClass.__index = BaseClass


function BaseClass.new(monster)
    local self = setmetatable({
    -- Properties
        attributes = monster:GetAttributes();
        currentEvent = "Nothing";
        eventList = {"Aggro", "Wander", "Nothing"};
        monsterCharacter = monster;
        root = monster.HumanoidRootPart;
        humanoid = monster.Humanoid;
    -- Variables
        raiders = workspace.Dungeon.Raiders;
        target = nil;
        targetDistance = nil;
        targetCharacter = nil;
        path = nil;
        pathObject = nil;
        currentWaypointIndex = 0;
    }, BaseClass)

    -- Setting Class Attributes
    if self.attributes.Class then
        local class = MonsterService.GetClass(self.attributes.Class)
        for i,v in pairs(class) do
            monster:SetAttribute(i,v)
        end
        self.attributes = monster:GetAttributes()
    end

    -- Events
    self.IdleEvent = Signal.new()
    self.MoveToFinished = Signal.new()
    -- Maid
    self._maid = require(Knit.Util.Maid).new()
    self.MoveCleanup = nil
    self.BlockedCleanup = nil
    -- Event Connections
    self._maid:GiveTask(self.IdleEvent:Connect(function() self:Idle()
    end)) -- Makes the Monster wander when Idle
    self._maid:GiveTask(RunService.Heartbeat:Connect(function() self:LogicLoop() -- Runs the LogicLoop for each Heartbeat
    end))

    return self
end

function BaseClass:EventChange(newEvent) -- A function to prioritize certain Events over the other, and changing the current Event to the higher priority Event.
    local currentPriority = table.find(self.eventList, self.currentEvent)
    local newPriority = table.find(self.eventList, newEvent)

    if newPriority < currentPriority then
        self.currentEvent = newEvent
        return true
    elseif newEvent == "Nothing" then
        self.currentEvent = newEvent
        self.IdleEvent:Fire()
    else
        return false
    end
end

-- Pathfinding and Movement

function BaseClass:Pathfind(target) -- Pathfinding
    local path
    if self.attributes.Radius and self.attributes.Height then
        local agentParameters = {
            AgentRadius = self.attributes.Radius;
            AgentHeight = self.attributes.Height;
            AgentCanJump = true;
        }
        if self.attributes.CanJump then agentParameters.AgentCanJump = self.attributes.CanJump
        end
        path = PathfindingService:CreatePath(agentParameters)
    else
        path = PathfindingService:CreatePath()
    end
    path:ComputeAsync(self.root.position, target)

    if path.Status == Enum.PathStatus.Success then
        return path:GetWaypoints(), path
    else
        return false
    end
end

function BaseClass:MoveTo(reached) -- Move to current waypoint in the path
    self.currentWaypointIndex += 1
    if reached and self.currentWaypointIndex < #self.path then
        -- Moving to Waypoint
        local waypoint = self.path[self.currentWaypointIndex]
        if waypoint.Action == Enum.PathWaypointAction.Jump then
            self.humanoid.Jump = true
        end
        self.humanoid:MoveTo(waypoint.Position)
        -- Firing another :MoveTo()
        local distance = math.abs((self.root.Position - waypoint.Position).Magnitude)
        --print(distance / self.humanoid.WalkSpeed)
        wait(distance / self.humanoid.WalkSpeed - 0.15)
        self.MoveToFinished:Fire(true)
    else
        self:AbortMovement()
    end
end

function BaseClass:PathBlocked(blockedWaypointIndex) -- Runs when the Path from the Pathfinding gets blocked
    if blockedWaypointIndex >= self.currentWaypointIndex then
        self:AbortMovement()
    end
end

function BaseClass:StartMovement(target) -- Start Pathfinded Movement to specified Target
    -- Pathfinding
    self.path, self.pathObject = self:Pathfind(target)
    -- Starting Movement
    if self.path then
        -- Events
        local MoveCleanup = self.MoveToFinished:Connect(function(reached) self:MoveTo(reached)
        end)
        local BlockCleanup = self.pathObject.Blocked:Connect(function(blockedWaypointIndex) self:PathBlocked(blockedWaypointIndex)
        end)
        self.MoveCleanup = self._maid:GiveTask(MoveCleanup)
        self.BlockCleanup = self._maid:GiveTask(BlockCleanup)
        -- MoveTo 1st Waypoint
        self:MoveTo(true)
    else
       self:EventChange("Nothing")
    end
end

function BaseClass:AbortMovement() -- Aborts Current Pathfinded Movement
    self.path = nil
    self.pathObject = nil
    self.currentWaypointIndex = 0
    self._maid[self.MoveCleanup] = nil
    self._maid[self.BlockCleanup] = nil

    self:EventChange("Nothing")
end

function BaseClass:ChangeSpeed(speedMod) -- Changes the Monster's Humanoid Walkspeed if the Monster has Speed Modifiers
    local speedModAttr = self.attributes[speedMod]
    if speedModAttr then
        self.humanoid.WalkSpeed = (self.attributes.BaseSpeed * speedModAttr)
    end
end

-- Monster Actions

function BaseClass:Attack()
    -- Face the Monster towards the Target
    local rotation = CFrame.lookAt(self.root.Position, self.target.Position)
    local tweenInfo = TweenInfo.new(1, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
    local goal = {}
    goal.CFrame = rotation
    self.root.Position = self.root.Position
    local tween = TweenService:Create(self.root, tweenInfo, goal)
    tween:Play()
    tween.Completed:Wait()
    -- Attacking the Target
    local debounce = true
    local face = self.root.CFrame.LookVector
    local thickness = 0
    if self.attributes.Thickness then thickness = self.attributes.Thickness
    end
    -- HitBox
    local hitBoxSpawn = self.root.CFrame + ((face * (self.attributes.AttackRange / 2)) + (face * (thickness / 2)))
    local hitBox = MonsterService.GetHitBox(self.attributes.HitBox):Clone()
    hitBox.Parent = workspace
    hitBox.CFrame = hitBoxSpawn

    hitBox.Touched:Connect(function(hit)
        if debounce and hit.Parent == self.targetCharacter then
            debounce = false
            self.targetCharacter.Humanoid:TakeDamage(self.attributes.Damage)
        end
    end)

    wait(1)
    hitBox:Destroy()
end

function BaseClass:Wander()
    if self:EventChange("Wander") then
        if self.attributes.WanderSpeed then -- Changes the Monster's Humanoid WalkSpeed to the Monster's WanderSpeed if Monster has WanderSpeed
            self:ChangeSpeed(self.attributes.WanderSpeed)
        end
        -- Randomizing Coordinate
        local xRand = math.random(-50,50)
        local zRand = math.random(-50,50)
        local target = self.root.Position + Vector3.new(xRand,0,zRand)

        self:StartMovement(target)
    end
end

function BaseClass:Aggro() -- Aggroes the Monster's Target. Aggro is the highest priority Event, which is why it uses a while loop instead of an event loop.
    if self:EventChange("Aggro") then
        local oldTarget = self.targetCharacter
        self:ChangeSpeed("AggroSpeed")
        while self.targetDistance <= self.attributes.AggroRange do
            RunService.Heartbeat:Wait()
            print(self.target)
            if not self.target then break
            end
            self.humanoid:MoveTo(self.target.Position)
            if self.targetDistance <= self.attributes.AttackRange then self:Attack()
            end
        end
        self:EventChange("Nothing")
    end
end

-- Monster Logic Loop

function BaseClass:TargetPriority()
    local raiders = self.raiders:GetChildren()
    local currentDistance = math.huge
    local newTarget
    local targetCharacter
    if #raiders > 0 then
        for _,v in pairs(raiders) do
            local targetRoot = v.HumanoidRootPart
            local newDistance = (self.root.Position - targetRoot.Position).magnitude
            if newDistance < currentDistance then
                currentDistance = newDistance
                newTarget = targetRoot
                targetCharacter = v
            end
        end
    end

    return newTarget, currentDistance, targetCharacter
end

function BaseClass:LogicLoop()
    self.target, self.targetDistance, self.targetCharacter = self:TargetPriority()
    if self.targetDistance <= self.attributes.AggroRange and self.currentEvent ~= "Aggro"  then
        if not self.currentEvent == "Nothing" then
            self:AbortMovement()
        end
        self:Aggro()
    end
end

function BaseClass:Idle()
    RunService.Heartbeat:Wait()
    if self.attributes.IdleTime then wait(self.attributes.IdleTime)
    else wait(1)
    end
    self:Wander()
end

function BaseClass:Destroy()
    self._maid:Destroy()
end

return BaseClass