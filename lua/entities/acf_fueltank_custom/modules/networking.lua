-- NET SURFER 2.0
util.AddNetworkString("ACF_RequestFuelTankInfo")
util.AddNetworkString("ACF_InvalidateFuelTankInfo")

function ENT:InvalidateClientInfo()
    net.Start("ACF_InvalidateFuelTankInfo")
        net.WriteEntity(self)
    net.Broadcast()
end

net.Receive("ACF_RequestFuelTankInfo", function(_, Ply)
    local Entity = net.ReadEntity()

    if IsValid(Entity) then
        local Engines = {}

        if Entity.Engines and next(Entity.Engines) then
            for E in pairs(Entity.Engines) do
                Engines[#Engines + 1] = E:EntIndex()
            end
        end

        net.Start("ACF_RequestFuelTankInfo")
            net.WriteEntity(Entity)
            net.WriteUInt(#Engines, 6)

            if next(Engines) then
                for _, E in ipairs(Engines) do
                    net.WriteUInt(E, MAX_EDICT_BITS)
                end
            end
        net.Send(Ply)
    end
end)
