local ACF      		 = ACF
local Classes        = ACF.Classes
local IsEntityValid  = ACF.Optimizations.IsEntityValid
local Mobility       = ACF.Mobility
local MobilityObj    = Mobility.Objects
local MaxDistance    = ACF.MobilityLinkDistance * ACF.MobilityLinkDistance
local MaxRadDistance = ACF.RadiatorLinkDistance * ACF.RadiatorLinkDistance

ACF.RegisterClassLink("acf_engine_custom", "acf_fueltank", function(Engine, Target)
    local TargetFuelType = Classes.GetTypeName(Target:ACF_GetUserVar("FuelType"):GetType())

    if Engine.FuelTanks[Target] then return false, "This engine is already linked to this fuel tank!" end
    if Target.Engines[Engine] then return false, "This engine is already linked to this fuel tank!" end
    if not Engine.FuelTypes[TargetFuelType] then return false, "Cannot link because fuel type is incompatible." end
    if Target.NoLinks then return false, "This fuel tank doesn't allow linking." end
    if Engine:GetPos():DistToSqr(Target:GetPos()) > MaxDistance then return false, "This fuel tank is too far away from this engine." end

    Engine.FuelTanks[Target] = true
    Target.Engines[Engine] = true

    Engine:UpdateOverlay()
    Target:UpdateOverlay()

    Target:InvalidateClientInfo()

    return true, "Engine linked successfully!"
end)

ACF.RegisterClassUnlink("acf_engine_custom", "acf_fueltank", function(Engine, Target)
    if Engine.FuelTanks[Target] or Target.Engines[Engine] then
        if Engine.FuelTank == Target then
            Engine.FuelTank = next(Engine.FuelTanks, Target)
        end

        Engine.FuelTanks[Target] = nil
        Target.Engines[Engine]	 = nil

        Engine:UpdateOverlay()
        Target:UpdateOverlay()

        Target:InvalidateClientInfo()

        return true, "Engine unlinked successfully!"
    end

    return false, "This engine is not linked to this fuel tank."
end)

ACF.RegisterClassLink("acf_engine_custom", "acf_gearbox", function(Engine, Target)
    if Engine.Gearboxes[Target] then return false, "This engine is already linked to this gearbox." end
    if Engine:GetPos():DistToSqr(Target:GetPos()) > MaxDistance then return false, "This gearbox is too far away from this engine!" end

    -- make sure the angle is not excessive
    local InPos = Target:LocalToWorld(Target.In.Pos)
    local OutPos = Engine:LocalToWorld(Engine.Out.Pos)

    if ACF.IsDriveshaftAngleExcessive(Target, Target.In, Engine, Engine.Out) then
        return false, "Cannot link due to excessive driveshaft angle!"
    end

    local Link = MobilityObj.Link(Engine, Target)

    Link:SetOrigin(Engine.Out)
    Link:SetTargetPos(Target.In)
    Link:SetAxis(Direction)

    Link.RopeLen = (OutPos - InPos):Length()

    Engine.Gearboxes[Target] = Link
    Target.Engines[Engine]   = true

    Engine:UpdateOverlay()
    Target:UpdateOverlay()

    Engine:InvalidateClientInfo()

    return true, "Engine linked successfully!"
end)

ACF.RegisterClassUnlink("acf_engine_custom", "acf_gearbox", function(Engine, Target)
    if not Engine.Gearboxes[Target] then
        return false, "This engine is not linked to this gearbox."
    end

    local Rope = Engine.Gearboxes[Target].Rope

    if IsValid(Rope) then Rope:Remove() end

    Engine.Gearboxes[Target] = nil
    Target.Engines[Engine]	 = nil

    Engine:UpdateOverlay()
    Target:UpdateOverlay()

    Engine:InvalidateClientInfo()

    return true, "Engine unlinked successfully!"
end)

ACF.RegisterClassLink("acf_engine_custom", "acf_radiator", function(Engine, Target)
    if Engine.Radiators[Target] then return false, "This engine is already linked to this radiator!" end
    if Target.Engine == Engine then return false, "This engine is already linked to this radiator!" end
    if Engine:GetPos():DistToSqr(Target:GetPos()) > MaxRadDistance then return false, "The radiator is too far away from this engine!" end
    -- Radiators can only link to 1 engine but engines can link to N radiators(1:N cardinality)
    if IsEntityValid(Target.Engine) and Target.Engine ~= Engine then return false, "The radiator is already linked to another engine!" end

    -- TODO: Set any other custom linking restrictions here

    Engine.Radiators[Target] = true
    Target.Engine = Engine

    Engine:UpdateOverlay()
    Target:UpdateOverlay()

    Target:InvalidateClientInfo()

    return true, "Engine linked successfully!"
end)

ACF.RegisterClassUnlink("acf_engine_custom", "acf_radiator", function(Engine, Target)
    if not Engine.Radiators[Target] then
        return false, "This engine is not linked to this radiator."
    end

    Engine.Radiators[Target] = nil
    Target.Engine = nil

    Engine:UpdateOverlay()
    Target:UpdateOverlay()

    Engine:InvalidateClientInfo()

    return true, "Engine unlinked successfully!"
end)
