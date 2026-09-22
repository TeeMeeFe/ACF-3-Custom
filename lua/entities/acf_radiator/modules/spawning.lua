local ACF         = ACF
local WireLib     = WireLib
local IsValid     = IsValid
local Contraption = ACF.Contraption
local ActiveRadiators = ACF.FuelTanks

do -- Spawning
    function ENT:ACF_PreSpawn()
        self.ACF              = {}
        self.AmbTemp          = ACF.AmbientTemperature - 273.15 -- In Degrees Kelvin to Degrees Celcius.
        self.Active           = false
        self.FanActive        = false
        self.CoreEff          = 1.0
        self.CoreTemperature  = self.AmbTemp
        self.InputTemperature = self.AmbTemp
        self.Engine           = nil
        self.IsDestroyed      = false
        self.IsLeaking        = false
        self.IsFrozen         = false
        self.LastActive       = 0
        self.LastFanActive    = 0
        self.LastThermEnabled = 0
        self.LastThink        = 0
        self.LastTemperature  = 0
        self.LastCoreTemp     = 0
        self.LastActivated    = 0
        self.LastAmount       = 0
        self.LastPressure     = 0
        self.LeakingRate      = 0
        self.MisteryText      = ""
        self.Mixture          = 0
        self.ThermEnabled     = true
        self.MaxPressure      = 1.2 -- bar, relief valve setting 
        self.UnpressTemp      = ACF.RadUnpressTemperature -- °C, below this value the system runs unpressurized
        self.Pressure         = 0

        duplicator.ClearEntityModifier(self, "mass")

        ActiveRadiators[self] = true
    end
end
ACF.RegisterLinkSource("acf_radiator", "Engine")

do -- Updating
    function ENT:ACF_PostUpdateEntityData()
        self.ACF = self.ACF or {}

        local RadType = self:GetRadiator()
        local Scale   = self:ACF_GetUserVar("RadiatorScale")
        local Mixture = self:ACF_GetUserVar("CoolantMix")
        local Density = self:ACF_GetUserVar("Density")
        local SpecificHeat = self:ACF_GetUserVar("SpecificHeat")
        local ThermostatTemp = self:ACF_GetUserVar("ThermostatTemp")
        local Model   = (RadType and RadType.Model) or "models/radiators/Radiator_small.mdl"

        -- Keep the current fuel level proportionally when reconfiguring an existing radiator.
        local Percentage = (self.Capacity and self.Amount) and (self.Amount / self.Capacity) or 1

        self.ACF.Model = Model
        self:SetScaledModel(Model)

        self.Mixture = Mixture
        self.Density = Density
        self.SpecificHeat = SpecificHeat
        self.EntType = "Radiator"
        self.Name    = RadType.Name

        self:SetScale(Scale)
        self.ACF.Scale = Scale
        self.HealthMult = RadType.HealthMult
        self.BaseCapacity = RadType.BaseCapacity
        self.EmptyMass = RadType.BaseEmptyMass
        self.ThermOpenAtTemp = ThermostatTemp

        local Capacity, Mass = self:CalcMassAndCapacity(Scale)
        self.Mass = Mass
        self.Capacity = Capacity

        self.UnitMass = RadType.Density
        self.Amount = Percentage * self.Capacity

        local FreezePoint = self:ACF_GetUserVar("FreezingPoint")
        local BoilingPoint = self:ACF_GetUserVar("BoilingPoint")
        self.BoilingPoint = BoilingPoint
        self.FreezePoint  = FreezePoint
        self.IsFrozen     = self.CoreTemperature <= FreezePoint

        WireLib.TriggerOutput(self, "Temperature", self.CoreTemperature)
        WireLib.TriggerOutput(self, "Amount", self.Amount)
        WireLib.TriggerOutput(self, "Capacity", self.Capacity)
        WireLib.TriggerOutput(self, "Thermostat Active", self.ThermEnabled and 1 or 0)

        Contraption.SetMass(self, self.Mass)
        self:UpdateMass(true)
    end
end

do -- Wiremod input handlers
    -- Active
    ACF.AddInputAction("acf_radiator", "Active", function(Entity, Value)
        Entity.Active = tobool(Value)

        Entity:SetActive(Value)
    end)
    -- Thermostat, allows the fan to engage if active
    ACF.AddInputAction("acf_radiator", "Thermostat", function(Entity, Value)
        Entity.ThermEnabled = tobool(Value)

        WireLib.TriggerOutput(Entity, "Thermostat Active", Entity.ThermEnabled and 1 or 0)
    end)
end

-- Remove-only teardown. Captured by AutoRegisterV2 as OrigOnRemove; the generated OnRemove still
-- runs ACF_OnEntityLast + WireLib cleanup around this.
function ENT:OnRemove(IsFullUpdate)
    if IsFullUpdate then return end

    if self.Engine then
        self:Unlink(Engine)
    end

    ActiveRadiators[self] = nil
end

-- The function to calculate empty mass and the capacity of a radiator.
-- Given that we only scale a model instead of sizing it, it has to be simpler.
function ENT:CalcMassAndCapacity(Scale)
    local Density  = self.Density
    local Capacity = self.BaseCapacity * Scale ^ 2.15
    local BaseMass = self.EmptyMass + (Capacity * Density)
    return Capacity, BaseMass
end

do	-- NET SURFER 2.0
    util.AddNetworkString("ACF_RequestRadiatorInfo")
    util.AddNetworkString("ACF_InvalidateRadiatorInfo")

    function ENT:InvalidateClientInfo()
        net.Start("ACF_InvalidateRadiatorInfo")
            net.WriteEntity(self)
        net.Broadcast()
    end

    net.Receive("ACF_RequestRadiatorInfo", function(_, Ply)
        local Entity = net.ReadEntity()
        local EngineEntity = nil

        if IsValid(Entity) then
            if IsValid(Entity.Engine) then
                EngineEntity = Entity.Engine
            end

            net.Start("ACF_RequestRadiatorInfo")
                net.WriteEntity(Entity)
                net.WriteEntity(EngineEntity)
            net.Send(Ply)
        end
    end)
end