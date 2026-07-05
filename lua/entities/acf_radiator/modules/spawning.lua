local ACF         = ACF
local Classes     = ACF.Classes
local WireLib     = WireLib
local IsValid     = IsValid
local ActiveRadiators = ACF.FuelTanks

local RADIATORTYPE_BASE = "ACF.Radiators.RadiatorType"

do -- Spawning
    -- Resolves a FuelType client-data value (legacy short id, class FQN string, or {Type=} table)
    -- to a ContainerShapes-style class FQN. Falls back to Standard radiator.
    local function ResolveType(Value)
        if istable(Value) and Value.Type then Value = Value.Type end
        if Classes.GetTypeByName(Value) then return Value end -- Already a FQN

        for _, Class in ipairs(Classes.GetSubtypes(RADIATORTYPE_BASE)) do
            if Class.ID == Value then return Classes.GetTypeName(Class) end
        end

        return "ACF.Radiators.Standard"
    end

    function ENT:ACF_OnVerifyClientData(ClientData) end
    function ENT:ACF_PreSpawn(_, _, _, ClientData)
        self.ACF = {}

        local ShapeClass = ResolveType(ClientData.RadiatorType)
        ShapeClass = Classes.GetTypeByName(ShapeClass)
        local Model = ShapeClass.Model

        self.ACF.Model = Model
        self:SetScaledModel(self.ACF.Model)
    end

    function ENT:ACF_OnSpawn()
        self.Active          = false
        self.Engine          = nil
        self.Mixture         = 0
        self.MisteryText     = ""
        self.IsLeaking       = false
        self.LeakingRate     = 0
        self.LastThink       = 0
        self.LastTemperature = 0
        self.LastAmount      = 0
        self.LastActivated   = 0

        duplicator.ClearEntityModifier(self, "mass")

        ActiveRadiators[self] = true
    end

    function ENT:ACF_PostSpawn(_, _, _, ClientData)
        self.Temperature = ACF.AmbientTemperature -- In Degrees Kelvin.

        self:SetScale(self.ACF.Scale)
        -- Radiators should be active by default.
        self:TriggerInput("Active", 1)
        self.Active = true
        WireLib.TriggerOutput(self, "Entity", self)
        WireLib.TriggerOutput(self, "Temperature", self.Temperature)
    end
end
ACF.RegisterLinkSource("acf_radiator", "Engine")

do -- Updating
    function ENT:ACF_PostUpdateEntityData()
        self.ACF = self.ACF or {}

        local RadType = self:GetRadiator()
        local Scale   = self:ACF_GetUserVar("RadiatorScale")
        local Size    = Vector(
            self:ACF_GetUserVar("RadiatorSizeX"),
            self:ACF_GetUserVar("RadiatorSizeY"),
            self:ACF_GetUserVar("RadiatorSizeZ")
        )
        local Mixture = self:ACF_GetUserVar("CoolantMix")
        local Model   = (RadType and RadType.Model) or "models/radiators/Radiator_small.mdl"

        -- Keep the current fuel level proportionally when reconfiguring an existing tank.
        local Percentage = (self.Capacity and self.Amount) and (self.Amount / self.Capacity) or 1

        self.ACF.Model = Model
        self:SetScaledModel(Model)

        self.Mixture = Mixture
        self.Density = RadType.Density
        self.EntType = "Radiator"
        self.Name    = RadType.Name
        self.IsBlock = RadType.IsBlock

        PrintTable({RadType.Density, Mixture, self.Name, Scale})
        if RadType.IsBlock then
            self:SetSize(Size)
            local _, Capacity, EmptyMass = self:CalcVolumeAndCapacity(Size)

            self.Capacity = Capacity
            self.EmptyMass = EmptyMass
        else
            self:SetScale(Scale)
            self.ACF.Scale = Scale
            self.BaseCapacity = RadType.BaseCapacity
            self.BaseEmptyMass = RadType.BaseEmptyMass

            local Capacity, EmptyMass = self:CalcEmptyMassAndCapacity(Scale)
            self.Capacity = Capacity
            self.EmptyMass = EmptyMass
        end

        self.UnitMass = RadType.Density
        self.Amount = Percentage * self.Capacity

        self:UpdateMass(true)
    end
end

-- Wire input handler for Active
ACF.AddInputAction("acf_radiator", "Active", function(Entity, Value)
    Entity.Active = tobool(Value)

    WireLib.TriggerOutput(Entity, "Activated", Entity.Active and 1 or 0)
end)

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
function ENT:CalcEmptyMassAndCapacity(Scale)
    local Capacity = self.BaseCapacity * Scale ^ 2.15
    local BaseMass = self.BaseEmptyMass + (Capacity * 1)
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