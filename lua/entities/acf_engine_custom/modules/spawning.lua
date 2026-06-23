local ACF      		= ACF
local Classes       = ACF.Classes
local Contraption   = ACF.Contraption
local Notify        = ACF.Utilities.Notify

local ENTITY        = FindMetaTable("Entity")
local PHYSOBJ       = FindMetaTable("PhysObj")
local VECTOR        = FindMetaTable("Vector")

local DefaultModel = "ACF.Engines.PistonBlock.DefaultModel"

-- ClientData values may be an FQN string (menu) or a serialized {Type=...} table (dupe).
local function ResolveType(Value, Default)
	local Name = istable(Value) and Value.Type or Value
	return Classes.GetTypeByName(Name) or Classes.GetTypeByName(Default)
end

function ENT:ACF_OnVerifyClientData(ClientData) end
function ENT:ACF_PostUpdateEntityData(ClientData) end
function ENT:ACF_PreSpawn(_, _, _, ClientData)
	local EngineClass = ResolveType(ClientData.CustomEngineClass, DefaultModel)

	self:SetScaledModel(EngineClass.Model or DefaultModel)
end

function ENT:ACF_OnSpawn(Owner, _, _, ClientData)
	-- I dunno if its even correct to do this at this stage...
	local Pistons 	= ClientData.CustomEnginePistons or 0
	local Bore 		= ClientData.CustomEngineBore or 0
	local Stroke 	= ClientData.CustomEngineStroke or 0
	local Clearance = ClientData.CustomEngineClearance or 0

	self.Active        = false
	self.Gearboxes     = {}
	self.FuelTanks     = {}
	self.LastThink     = 0
	self.Pistons 	   = Pistons
	self.Bore          = Bore
	self.Stroke        = Stroke
	self.Clearance     = Clearance

	duplicator.ClearEntityModifier(self, "mass")
end

function ENT:ACF_PostSpawn(Owner, _, _, ClientData)
	Contraption.SetMass(self, 100) -- We later get the mass of the contraption
	duplicator.StoreEntityModifier(self, "mass", { Mass = 100 })

	local Params = {
		Pistons   = self.Pistons,
		Bore	  = self.Bore,
		Stroke 	  = self.Stroke,
		Clearance = self.Clearance
	}

	local Sel = ClientData.CustomEngineClass
	local Class = Classes.GetTypeByName(Sel)

	local LayoutFactors = Class.GetLayoutFactors(self.Pistons)
	local Compute = Class.Compute(Sel, LayoutFactors, Params)

	PrintTable(Compute)
	Notify.NoticeToPlayer(Owner, "Attempt to create entity was successful!")
end

function ENT:PostEntityPaste(_, _, CreatedEntities)
	print("Ran ENT:PostEntityPaste()")
end

function ENT:ACF_OnUpdateEntityData()
	PrintTable(self.ACF_LiveData)
	print("Ran ENT:ACF_OnUpdateEntityData()")
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