local ACF      		= ACF
local Classes       = ACF.Classes
local Contraption   = ACF.Contraption
local Notify        = ACF.Utilities.Notify

local DefaultModel = "ACF.Engines.PistonBlock.DefaultModel"

-- ClientData values may be an FQN string (menu) or a serialized {Type=...} table (dupe).
local function ResolveType(Value, Default)
	local Name = istable(Value) and Value.Type or Value
	return Classes.GetTypeByName(Name) or Classes.GetTypeByName(Default)
end

function ENT:ACF_OnVerifyClientData(ClientData) end
function ENT:ACF_PreSpawn(_, _, _, ClientData)
	local EngineClass = ResolveType(ClientData.EngineBlockModel, DefaultModel)

	PrintTable({Classes.GetTypeByName(ClientData.EngineBlockModel)})
	PrintTable({Classes.GetTypeByName(ClientData.OnInit)})
	self:SetScaledModel(EngineClass.Model or EngineClass.DefaultModel)
end

function ENT:ACF_OnSpawn(Owner, _, _, ClientData)
	local Entity = ents.Create("acf_engine_custom")
	if not IsValid(Entity) then return false end

	Entity:Spawn()

	Entity.Active        = false
	Entity.Gearboxes     = {}
	Entity.FuelTanks     = {}
	Entity.LastThink     = 0

	duplicator.ClearEntityModifier(self, "mass")
end

function ENT:ACF_PostSpawn(Owner, _, _, ClientData)
	--Contraption.SetModel(self, Model)
	Contraption.SetMass(self, 100) -- We later get the mass of the contraption

	duplicator.StoreEntityModifier(self, "mass", { Mass = 100 })
	Notify.NoticeToPlayer(Owner, "Attempt to create entity was successful!")

	--PrintTable(ACF.GetAllClientData(Owner))
	PrintTable(self.ACF_LiveData)
end

function ENT:ACF_OnUpdateEntityData()
	--PrintTable(self.ACF_LiveData)
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