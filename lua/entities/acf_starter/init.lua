include("shared.lua")

ENT.DoNotDuplicate = true
CFW.addParentDetour("acf_engine_custom", "Engine")

local Sounds = ACF.Utilities.Sounds
local Clamp  = math.Clamp
local abs    = math.abs

local ENTITY = FindMetaTable("Entity")

function ENT:ACF_PostSpawn()
    self.State        = "Idle"
    self.IsCranking   = false
    self.NominalRPM   = 350 -- RPM at which our starter normally runs at 
    self.LimitRPM     = 700
    self.Torque       = 0
    self.LastTorque   = 0
    self.InputVoltage = 12 -- TODO: This would read from a battery instead of being constant
    self.LastVoltage  = 0
    self.SoundPitch   = 1
    self.LastPitch    = 0
    self.SoundVolume  = 1
    self.RemoveParent = true -- If false, it just removes this entity.
end

function ENT:SetActive(Active)
    if Active then
        self.State      = "Cranking"
        self.IsCranking = true
    else
        self.State      = "Idle"
        self.IsCranking = false
        self:DestroySound()
    end
end

local function GetPitchVolume(Starter, RPM)
    local Pitch = Clamp(20 + (RPM * Starter.SoundPitch * 1.5), 1, 100)
    -- Rev limiter code disabled because it has issues with the volume delta time, but it's still here if we need it
    local Volume = 0.25 + (0.1 + 0.9 * ((RPM / Starter.LimitRPM) ^ 1.5)) * 0.666

    return Pitch, Volume
end

function ENT:UpdateSound(SelfTbl, RPM)
    SelfTbl = SelfTbl or ENTITY.GetTable(self)

    if not SelfTbl.IsCranking then return end

    local Path = SelfTbl.SoundPath
    if Path == "" then return end
    local Pitch, Volume = GetPitchVolume(SelfTbl, RPM)

    if abs(Pitch - SelfTbl.LastPitch) < 1 then return end -- Don't bother updating if the pitch difference is too small to notice
    SelfTbl.LastPitch = Pitch

    if SelfTbl.Sound then
        Sounds.SendAdjustableSound(self, false, Pitch, Volume)
    else
        Sounds.CreateAdjustableSound(self, Path, Pitch, Volume)
        SelfTbl.Sound = true
    end
end

function ENT:DestroySound()
    Sounds.SendAdjustableSound(self, true)

    self.LastPitch  = 0
    self.Sound      = nil
end

function ENT:Think()
    local SelfTbl = ENTITY.GetTable(self)
    if SelfTbl.Disabled then return end

    local Engine = (SelfTbl.Engine):GetTable()
    local FlyRPM = Engine.FlyRPM

    if SelfTbl.IsCranking then
        -- This roughly creates the electric motor torque-curve, full torque at 0 RPM, and linearly dropping to 0 at LimitRPM.
        local SpeedFrac = Clamp(FlyRPM / SelfTbl.LimitRPM, 0, 1)
        SelfTbl.Torque = SelfTbl.TorqueStall * SelfTbl.InputVoltage * (1 - SpeedFrac)
        SelfTbl.LastTorque = SelfTbl.Torque
    elseif SelfTbl.Torque ~= 0 then
        SelfTbl.Torque = 0
        SelfTbl.LastTorque = 0
    end

    if SelfTbl.IsCranking then
        SelfTbl.UpdateSound(self, SelfTbl, FlyRPM)
    end
end

function ENT:RemoveSafely()
    local Parent = self.Engine:GetTable()

    Parent.Starter = nil
    self.RemoveParent = false
    self:Remove()
end

-- One can't exist without the other
function ENT:OnRemove()
    if IsValid(self.Engine) and self.RemoveParent then
        self.Engine:Remove()
    end
end

-- This shouldn't be called usually due to parent detouring.
function ENT:CFW_OnParented(Entity, Connected)
    if not IsValid(Entity) then return end

    if Connected == false and (Entity == self.Engine and self.RemoveParent) then self:Remove() end
end

function ENT:UpdateTransmitState()
    return TRANSMIT_PVS
end
