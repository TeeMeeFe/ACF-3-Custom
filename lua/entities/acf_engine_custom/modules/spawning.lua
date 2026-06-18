local ACF      		= ACF
local Notify        = ACF.Utilities.Notify
local Contraption   = ACF.Contraption

function ENT.ACF_OnVerifyClientData(ClientData)
    --ClientData.EnginePistons = Number(ClientData.EnginePistons)
end

function ENT:ACF_OnSpawn(Player, Pos, Angle, Data)
    local BaseClass = ACF.Classes.GetBaseClass(ENT)

    PrintTable({BaseClass})

    local Entity = ents.Create("acf_engine_custom")

    if not IsValid(Entity) then return false end

    --Entity:SetAngles(Angle)
    --Entity:SetPos(Pos)
    Entity:Spawn()

    --Player:AddCleanup("acf_engine", Entity)
    --Player:AddCount(Limit, Entity)
end

--[[ ACF Legality Check
	ALL SENTS MUST HAVE:
	ENT.ACF.PhysObj defined when spawned
	ENT.ACF.LegalMass defined when spawned
	ENT.ACF.Model defined when spawned

	ACF.CheckLegal(entity) called when finished spawning

	function ENT:Enable()
		<code>
	end

	function ENT:Disable()
		<code>
	end
]]--