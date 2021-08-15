local Knit = require(game:GetService("ReplicatedStorage").Knit)
local SoundService = Knit.GetService("SoundService")

local ParentClass = require(script.Parent)
local HearingClass = {}
HearingClass.__index = HearingClass
setmetatable(HearingClass, ParentClass)

HearingClass.Tag = "Monster:HearingClass"


function HearingClass.new(monster)
    local self = setmetatable(ParentClass.new(monster), HearingClass)
    self.eventList = {"Aggro", "Chase", "Wander", "Nothing"}
    self.chaseList = {"Heard", "Nothing"}
    self.currentChase = "Nothing"
    self.chaseValue = 0
    self.heardTarget = nil

    return self
end


function HearingClass:Chase(target)
    local goal = target.Position
    print(goal)
    self:ChangeSpeed("ChaseSpeed")
    self:StartMovement(goal)
end

function HearingClass:Heard(loudness, source)
    local distance = math.abs((self.root.Position - source.Position).Magnitude)
    local hearingMultiplier = self.attributes.HearingMultiplier
    if not hearingMultiplier then hearingMultiplier = 1 -- Base Value of HearingMultiplier
    end

    local finalLoudness = (loudness * hearingMultiplier) - distance
    local eventChange = self:EventChange("Chase", "Heard", finalLoudness)
    if eventChange then
        self.chaseValue = finalLoudness

        self.heardTarget = source
        self:Chase(self.heardTarget)
    end
end

function HearingClass:Init()
    self:BaseInit()
    -- Events
    self._janitor:Add(self.IdleEvent:Connect(function()
        self.chaseValue = 0
        self.heardTarget = nil
    end))
    self._janitor:Add(SoundService.Heard:Connect(function(loudness, source) self:Heard(loudness, source)
    end))
end

function HearingClass:Destroy()
    self._janitor:Destroy()
end


return HearingClass