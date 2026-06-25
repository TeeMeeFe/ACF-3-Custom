local ACF      		= ACF
local Classes       = ACF.Classes
local Contraption   = ACF.Contraption
local Notify        = ACF.Utilities.Notify

local ENTITY        = FindMetaTable("Entity")
local PHYSOBJ       = FindMetaTable("PhysObj")
local VECTOR        = FindMetaTable("Vector")

-- Math Constants
local Round = math.Round
local Floor = math.floor
local Abs   = math.abs

local DefaultModel = "ACF.Engines.PistonBlock.DefaultModel"

-- Engines should have these states: IDLE, STARTING, ACTIVE, STALLING
-- Old engines had ACTIVE, IDLE. 

-- ClientData values may be an FQN string (menu) or a serialized {Type=...} table (dupe).
local function ResolveType(Value, Default)
	local Name = istable(Value) and Value.Type or Value
	return Classes.GetTypeByName(Name) or Classes.GetTypeByName(Default)
end

function ENT:ACF_OnVerifyClientData(ClientData) end
function ENT:ACF_PostUpdateEntityData(ClientData) end
function ENT:ACF_PreSpawn(_, _, _, ClientData)
	local EngineClass = ResolveType(ClientData.CustomEngineClass, DefaultModel)

	self.ACF = {}
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
	self.Layout 	   = ""
	self.Throttle 	   = 0
	self.State         = "idle"
	self.SoundBanks    = {}
	self.Temperature   = {Water = ACF.AmbientTemperature, Oil = ACF.AmbientTemperature}
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

	local Displacement = Compute.Displacement
	local Sign    = Compute.Sign
	local Name 	  = ("%sL %s - %scc"):format(Round(Displacement.InLiters, 1), Sign, Round(Displacement.InCubicCentimeters))

	-- Class compute table assignments
	self.Name      			= Name
	self.ShortName 			= Name
	self.BalanceFactor  	= Compute.BalanceFactor
	self.BigEndDiam     	= Compute.BigEndDiam_cm
	self.BlockType	 		= Compute.IsPiston and "Piston" or Compute.IsTurbine and "Turbine" or Compute.IsElectric and "Electrical"
	self.Bore	        	= Compute.BoreCm
	self.BSFC 				= Compute.BSFC
	self.CompressionRatio 	= Compute.CompressionRatio
	self.Clearance      	= Compute.ClearanceCm
	self.Displacement 		= Displacement
	self.FiringIrregularity = Compute.FiringIrregularity
	self.FlywheelInertia 	= Compute.FlywheelInertia
	self.HeatCoefficient	= Compute.HeatCoeff
	self.IdleRPM			= Compute.IdleRPM
	self.Layout				= Compute.Layout
	self.MaxRPM 	 		= Compute.maxRPM
	self.MaxTorque			= Compute.maxTorque
	self.OilSumpTiltStarve  = Compute.OilSumpTiltStarve
	self.OilSumpTiltWarn    = Compute.OilSumpTiltWarn
	self.PeakTorque			= Compute.PeakTorque
	self.PeakPower			= self.PeakTorque * self.MaxRPM  / 9548.8
	self.Pistons 			= Compute.Pistons
	self.RedlineRPM   		= Compute.RedlineRPM
	self.RodRatio			= Compute.RodRatio
	self.State              = self.State
	self.Sign 				= Sign
	self.Sample				= Compute.Sample
	self.SparksPerRev		= Compute.SparksPerRev
	self.Stroke				= Compute.StrokeCm
	self.SweptVolPerCyl		= Compute.SweptVolPerCyl
	self.TorqueSmoothness	= Compute.TorqueSmoothness
	self.TorqueCurve		= Compute.curve
	self.TorqueCurve.Steps  = Compute.steps
	self.HitBoxes         	= ACF.GetHitboxes(self:GetModel())
	self.Out              	= ACF.LocalPlane(self:WorldToLocal(self:GetAttachment(self:LookupAttachment("driveshaft")).Pos))

	WireLib.TriggerOutput(self, "State", "idle")

	--PrintTable(Compute)
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