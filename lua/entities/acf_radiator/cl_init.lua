local ACF		= ACF
local Clock		= ACF.Utilities.Clock
local IsValid   = IsValid
local Queued	= {}

include("shared.lua")

do	-- NET SURFER 2.0
    net.Receive("ACF_InvalidateRadiatorInfo", function()
        local Radiator = net.ReadEntity()
        if not IsValid(Radiator) then return end

        Radiator.HasData = false
    end)

    net.Receive("ACF_RequestRadiatorInfo", function()
        local Radiator   = net.ReadEntity()
        local Engine	 = net.ReadEntity()

        if not IsValid(Radiator) then return end
        if not IsValid(Engine) then return end

        Radiator.Engine  = Engine
        Radiator.HasData = true
        Radiator.Age	 = Clock.CurTime + 5
    end)

    function ENT:RequestRadiatorInfo()
        if Queued[self] then return end

        Queued[self] = true

        timer.Simple(5, function() Queued[self] = nil end)

        net.Start("ACF_RequestRadiatorInfo")
            net.WriteEntity(self)
        net.SendToServer()
    end
end

do	-- Overlay
    local EngineColor = Color(255, 255, 0, 25)

    function ENT:DrawOverlay()
        local SelfTbl = self:GetTable()

        if not SelfTbl.HasData then
            self:RequestRadiatorInfo()
            return
        elseif Clock.CurTime > SelfTbl.Age then
            self:RequestRadiatorInfo()
        end

        render.SetColorMaterial()

        if IsValid(SelfTbl.Engine) then
            local Pos, Ang, Mins, Maxs = E:GetPos(), E:GetAngles(), E:OBBMins(), E:OBBMaxs()

            render.DrawWireframeBox(Pos, Ang, Mins, Maxs, EngineColor, true)
            render.DrawBox(Pos, Ang, Mins, Maxs, EngineColor)
        end
    end
end