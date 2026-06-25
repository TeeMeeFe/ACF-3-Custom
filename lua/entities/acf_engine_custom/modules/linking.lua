local ACF      		= ACF
local Mobility      = ACF.Mobility
local MobilityObj   = Mobility.Objects
local MaxDistance   = ACF.MobilityLinkDistance * ACF.MobilityLinkDistance

ACF.RegisterClassLink("acf_engine_custom", "acf_fueltank", function(Engine, Target)
    if Engine.FuelTanks[Target] then return false, "This engine is already linked to this fuel tank!" end
    if Target.Engines[Engine] then return false, "This engine is already linked to this fuel tank!" end
    if not Engine.FuelTypes[Target.FuelType] then return false, "Cannot link because fuel type is incompatible." end
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