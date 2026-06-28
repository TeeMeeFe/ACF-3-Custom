local ACF         = ACF
local Classes     = ACF.Classes
local WireLib     = WireLib
local IsValid     = IsValid
local ActiveRadiators = ACF.FuelTanks

local RADIATORTYPE_BASE = "ACF.Radiators.RadiatorType"

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

ACF.RegisterLinkSource("acf_radiator", "Engine")

-- Remove-only teardown. Captured by AutoRegisterV2 as OrigOnRemove; the generated OnRemove still
-- runs ACF_OnEntityLast + WireLib cleanup around this.
function ENT:OnRemove(IsFullUpdate)
    if IsFullUpdate then return end

    if self.Engine then
        self:Unlink(Engine)
    end

    ActiveRadiators[self] = nil
end

-- Wire input handler for Active
ACF.AddInputAction("acf_radiator", "Active", function(Entity, Value)
    Entity.Active = tobool(Value)

    WireLib.TriggerOutput(Entity, "Activated", Entity.Active and 1 or 0)
end)

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