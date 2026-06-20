local ACF      		= ACF
local Notify        = ACF.Utilities.Notify
local Contraption   = ACF.Contraption

local DefaultModel = "models/holograms/cube.mdl"

local function ResolveType(Value, Default)
	local Name = istable(Value) and Value.Type or Value
	return Classes.GetTypeByName(Name) or Classes.GetTypeByName(Default)
end

function ENT.ACF_OnVerifyClientData(ClientData) end
function ENT:ACF_PreSpawn(Player, _, _, ClientData)
	local Model = ClientData.EngineBlockModel

	if not Model then
		Model = DefaultModel
		Notify.WarningToPlayer(Player, "Failed to fetch class model!", "Fallback to default cube model.")
	end
	self:SetScaledModel(Model)
end

local function UpdateEngine(Entity, Data, Class, Engine, Type)

end

function ENT:ACF_OnSpawn(Player, _, _, ClientData)
	local Entity = ents.Create("acf_engine_custom")
	if not IsValid(Entity) then return false end


	Entity:Spawn()

	Notify.NoticeToPlayer(Player, "Attempt to create entity was successful!")
	duplicator.ClearEntityModifier(self, "mass")
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