local ACF = ACF
local IsEntityValid = ACF.Optimizations.IsEntityValid

-- NET SURFER 2.0
util.AddNetworkString("ACF_RequestCustomEngineInfo")
util.AddNetworkString("ACF_InvalidateCustomEngineInfo")

function ENT:InvalidateClientInfo()
    net.Start("ACF_InvalidateCustomEngineInfo")
        net.WriteEntity(self)
    net.Broadcast()
end

net.Receive("ACF_RequestCustomEngineInfo", function(_, Ply)
    local Entity = net.ReadEntity()

    if IsEntityValid(Entity) then
        local Outputs    = {}
        local FuelTanks  = {}
        local Radiators  = {}
        local Driveshaft = Entity.Out.Pos

        if next(Entity.Gearboxes) then
            for E in pairs(Entity.Gearboxes) do
                Outputs[#Outputs + 1] = E:EntIndex()
            end
        end

        if next(Entity.FuelTanks) then
            for E in pairs(Entity.FuelTanks) do
                FuelTanks[#FuelTanks + 1] = E:EntIndex()
            end
        end

        if next(Entity.Radiators) then
            for E in pairs(Entity.Radiators) do
                Radiators[#Radiators + 1] = E:EntIndex()
            end
        end

        net.Start("ACF_RequestCustomEngineInfo")
            net.WriteEntity(Entity)
            net.WriteVector(Driveshaft)
            net.WriteUInt(#Outputs, 6)
            net.WriteUInt(#FuelTanks, 6)
            net.WriteUInt(#Radiators, 6)

            if next(Outputs) then
                for _, E in ipairs(Outputs) do
                    net.WriteUInt(E, MAX_EDICT_BITS)
                end
            end

            if next(FuelTanks) then
                for _, E in ipairs(FuelTanks) do
                    net.WriteUInt(E, MAX_EDICT_BITS)
                end
            end

            if next(Radiators) then
                for _, E in ipairs(Radiators) do
                    net.WriteUInt(E, MAX_EDICT_BITS)
                end
            end
        net.Send(Ply)
    end
end)
