local ACF      		= ACF
local Mobility      = ACF.Mobility
local MobilityObj   = Mobility.Objects
local MaxDistance   = ACF.MobilityLinkDistance * ACF.MobilityLinkDistance

local Classes       = ACF.Classes
local Contraption   = ACF.Contraption
--local Notify        = ACF.Utilities.Notify

local ENTITY        = FindMetaTable("Entity")
local PHYSOBJ       = FindMetaTable("PhysObj")
local VECTOR        = FindMetaTable("Vector")

-- Math Constants
local Round = math.Round
local Floor = math.floor
local Abs   = math.abs

local DefaultModel = ("ACF.Engines.PistonBlock").DefaultModel

-- Engines should have these states: IDLE, STARTING, ACTIVE, STALLING
-- Old engines had ACTIVE, IDLE. 

-- ClientData values may be an FQN string (menu) or a serialized {Type=...} table (dupe).
local function ResolveType(Value, Default)
	local Name = istable(Value) and Value.Type or Value
	return Classes.GetTypeByName(Name) or Classes.GetTypeByName(Default)
end

--function ENT:ACF_OnVerifyClientData(ClientData) end
function ENT:ACF_PreSpawn(_, _, _, ClientData)
	self.ACF = {}

	--PrintTable({ClientData})
	local EngineType = ResolveType(ClientData.EngineType, DefaultModel)
	local Model = EngineType.Model

	self.EngineType = EngineType
	self.ACF.Model = Model
	self:SetScaledModel(Model or DefaultModel)
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
	self.Radiators     = {}
	self.MassRatio     = 1
	self.LastThink     = 0
	self.LastPitch     = 0
	self.LastTorque    = 0
	self.LastFuelUsage = 0
	self.LastPower     = 0
	self.LastRPM       = 0
	self.LastTotalMass = 0
	self.LastPhysMass  = 0
	self.FuelUsage     = 0
	self.Layout 	   = ""
	self.Throttle 	   = 0
	self.State         = "Idle"
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

	local Sel = ClientData.EngineType
	local Class = Classes.GetTypeByName(Sel)

	--PrintTable({Sel, Class, ClientData})
	local LayoutFactors = Class.GetLayoutFactors(self.Pistons)
	local Compute = Class.Compute(Sel, LayoutFactors, Params)

	local Displacement = Compute.Displacement
	local Sign = Compute.Sign
	local Name = ("%sL %s - %scc"):format(Round(Displacement.InLiters, 1), Sign, Round(Displacement.InCubicCentimeters))

	-- Class compute table assignments
	self.Name      			= Name
	self.ShortName 			= Name
	self.BalanceFactor  	= Compute.BalanceFactor
	self.BigEndDiam     	= Compute.BigEndDiam_cm
	self.BlockType	 		= Compute.IsPiston and "Piston" or Compute.IsTurbine and "Turbine" or Compute.IsElectric and "Electric"
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
	self.RedlineRPM   		= Compute.RedlineRPM
	self.OilSumpTilt  		= Compute.OilSumpTilt
	self.PeakTorque			= Compute.PeakTorque
	self.PeakPower			= Compute.PeakPower
	self.PowerBand			= Compute.PowerBand
	self.Pistons 			= Compute.Pistons
	self.RodRatio			= Compute.RodRatio
	self.Sign 				= Sign
	self.Sample				= Compute.Sample
	self.SparksPerRev		= Compute.SparksPerRev
	self.Stroke				= Compute.StrokeCm
	self.SweptVolPerCyl		= Compute.SweptVolPerCyl
	self.TorqueSmoothness	= Compute.TorqueSmoothness
	self.TorqueCurve		= Compute.TorqueCurve
	self.VECurve		    = Compute.VECurve
	self.HitBoxes         	= ACF.GetHitboxes(self:GetModel())
	self.Out              	= ACF.LocalPlane(self:WorldToLocal(self:GetAttachment(self:LookupAttachment("driveshaft")).Pos), Vector(1, 0, 0))

	--PrintTable(Compute)
	WireLib.TriggerOutput(self, "State", "Idle")
end

function ENT:ACF_OnUpdateEntityData()
	--PrintTable(self.ACF_LiveData)
	print("Ran ENT:ACF_OnUpdateEntityData()")
end

function ENT:ACF_PostUpdateEntityData(ClientData)
	--PrintTable(self.ACF_LiveData)
	if self.Active then return false, "Turn off the engine before updating it!" end -- TODO: Localize me!
	local Feedback = ""

	-- These are just placeholders for now as this code below is straight up stripped from the old engine Update function
	if next(self.Gearboxes) then
		local Count, Total = 0, 0

		for Gearbox in pairs(self.Gearboxes) do
			self:Unlink(Gearbox)

			local Result = self:Link(Gearbox)

			if not Result then Count = Count + 1 end

			Total = Total + 1
		end

		if Count == Total then
			Feedback = Feedback .. "\nUnlinked all gearboxes due to excessive driveshaft angle." -- TODO: Localize me!
		elseif Count > 0 then
			local Text = Feedback .. "\nUnlinked %s out of %s gearboxes due to excessive driveshaft angle." -- TODO: Localize me!

			Feedback = Text:format(Count, Total)
		end
	end

	if next(self.FuelTanks) then
		local Count, Total = 0, 0

		for Tank in pairs(self.FuelTanks) do
			if not self.FuelTypes[Tank.FuelType] then
				self:Unlink(Tank)

				Count = Count + 1
			end

			Total = Total + 1
		end

		if Count == Total then
			Feedback = Feedback .. "\nUnlinked all fuel tanks due to fuel type change." -- TODO: Localize me!
		elseif Count > 0 then
			local Text = Feedback .. "\nUnlinked %s out of %s fuel tanks due to fuel type change." -- TODO: Localize me!

			Feedback = Text:format(Count, Total)
		end
	end

	return true, "Engine updated successfully!" .. Feedback
end

function ENT:PostEntityPaste(_, _, CreatedEntities)
	print("Ran ENT:PostEntityPaste()")
end

ACF.RegisterLinkSource("acf_engine_custom", "Gearboxes")
ACF.RegisterLinkSource("acf_engine_custom", "FuelTanks")
ACF.RegisterLinkSource("acf_engine_custom", "Radiators")

-- Remove-only teardown. Captured by AutoRegisterV2 as OrigOnRemove; the generated OnRemove still
-- runs ACF_OnEntityLast + WireLib cleanup around this.
function ENT:OnRemove(IsFullUpdate)
	if IsFullUpdate then return end

	--hook.Run("ACF_OnEntityLast", "acf_engine", self, Class) -- Maybe its not needed anymore?

	-- self:DestroySound() -- Don't have this yet

	for Gearbox in pairs(self.Gearboxes) do
		self:Unlink(Gearbox)
	end

	for Tank in pairs(self.FuelTanks) do
		self:Unlink(Tank)
	end

	for Radiator in pairs(self.Radiators) do
		self:Unlink(Radiator)
	end

	--TimerRemove("ACF Engine Clock " .. self:EntIndex()) -- Not yet...
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