local ACF     		= ACF
local Classes 		= ACF.Classes
local Round   		= math.Round
local TimerRemove   = timer.Remove
local Contraption   = ACF.Contraption
local IsEntityValid = ACF.Optimizations.IsEntityValid

local function UpdateEngine(Entity, Class)
	Entity.ACF = Entity.ACF or {}

	local Model = Entity.Model or Class.CustomEngineModel
	Entity:SetScaledModel(Model)

	local Params = {
		Pistons   = Entity.Pistons or Class.CustomEnginePistons,
		Bore	  = Entity.Bore or Class.CustomEngineBore,
		Stroke 	  = Entity.Stroke or Class.CustomEngineStroke,
		Clearance = Entity.Clearance or Class.CustomEngineClearance
	}

	local EngineClass = Entity.Engine.Class
	local FuelTypes = {}
	local ExtraEngineFields = {}
	-- Shitty hack to get the type of fuel used for these engine Classes
	-- This is the same hack used for the menu creation in piston_block/inline.lua
	if EngineClass == "ACF.EngineTypes.GenericPetrol" then
		FuelTypes = {["ACF.FuelTypes.Petrol"] = true}
		ExtraEngineFields = {
			PistonSpeed  = 20, -- m/s
			Efficiency   = 0.304, -- TypeFields.Efficiency
			TorqueScale  = 0.25, -- TypeFields.TorqueScale
			IgnitionType = "spark"
		}
	elseif EngineClass == "ACF.EngineTypes.GenericDiesel" then
		FuelTypes = {["ACF.FuelTypes.Diesel"] = true}
		ExtraEngineFields = {
			PistonSpeed  = 13, -- m/s
			Efficiency   = 0.243, -- TypeFields.Efficiency
			TorqueScale  = 0.25, -- TypeFields.TorqueScale
			IgnitionType = "glow"
		}
	end

	local LayoutFactors = Class.GetLayoutFactors(Params.Pistons)
	local Compute = Class.Compute(_, LayoutFactors, Params, ExtraEngineFields)

	local Displacement = Compute.Displacement
	local Sign = Compute.Sign
	local Name = ("%sL %s - %scc"):format(Round(Displacement.InLiters, 1), Sign, Round(Displacement.InCubicCentimeters))

	-- Class compute table assignments
	Entity.ACF.Model 		    = Model
	Entity.Name      			= Name
	Entity.ShortName 			= Name
	Entity.BalanceFactor  		= Compute.BalanceFactor
	Entity.BigEndDiam     		= Compute.BigEndDiam_cm
	Entity.BlockType	 		= Compute.IsPiston and "Piston" or Compute.IsTurbine and "Turbine" or Compute.IsElectric and "Electric"
	Entity.Bore	        		= Compute.BoreCm
	Entity.BSFC 				= Compute.BSFC
	Entity.CompressionRatio 	= Compute.CompressionRatio
	Entity.Clearance      		= Compute.ClearanceCm
	Entity.CoolantLevel         = 0
	Entity.DefaultSound       	= Entity.SoundPath
	Entity.Displacement 		= Displacement
	Entity.FiringIrregularity 	= Compute.FiringIrregularity
	Entity.FlywheelInertia 		= Compute.FlywheelInertia
	Entity.FlyRPM				= 0
	Entity.FuelTypes          	= FuelTypes or { ["ACF.FuelTypes.Petrol"] = true }
	Entity.FuelType           	= next(FuelTypes)
	Entity.HeatCoefficient		= Compute.HeatCoeff
	Entity.HealthMult			= 0.3
	Entity.IdleRPM				= Compute.IdleRPM
	Entity.IsStalled			= false
	Entity.Layout				= Compute.Layout
	Entity.Mass                 = Compute.ScaledMass
	Entity.LimitRPM   		    = Compute.LimitRPM
	Entity.OilSumpTilt  		= Compute.OilSumpTilt
	Entity.PeakTorque			= Compute.PeakTorque
	Entity.PeakPower			= Compute.PeakPower
	Entity.PowerBand			= Compute.PowerBand
	Entity.Pistons 				= Compute.Pistons
	Entity.RodRatio				= Compute.RodRatio
	Entity.RedlineRPM           = Compute.RedlineRPM
	Entity.RevLimited			= false
	Entity.SoundPitch         	= Entity.Pitch or 1
	Entity.SoundVolume        	= Entity.SoundVolume or 1
	Entity.Sign 				= Sign
	Entity.Sample				= Compute.Sample
	Entity.Scale                = Compute.ModelScale
	Entity.SparksPerRev			= Compute.SparksPerRev
	Entity.Stroke				= Compute.StrokeCm
	Entity.SweptVolPerCyl		= Compute.SweptVolPerCyl
	Entity.TorqueSmoothness		= Compute.TorqueSmoothness
	Entity.TorqueCurve			= Compute.Curve
	Entity.Torque           	= 0
	Entity.VECurve		    	= Compute.VECurve
	Entity.HitBoxes         	= ACF.GetHitboxes(Entity:GetModel())
	Entity.Out              	= ACF.LocalPlane(Entity:WorldToLocal(Entity:GetAttachment(Entity:LookupAttachment("driveshaft")).Pos), Vector(1, 0, 0))
	Entity.WasTimed             = false -- Temperature timer shit

	Entity:SetScale(Entity.Scale)

	Contraption.SetMass(Entity, Entity.Mass)

	-- PrintTable({Compute})
	-- Calculate base fuel usage
	--if Type.CalculateFuelUsage then
	---	Entity.FuelUse = Type.CalculateFuelUsage(Entity)
	--else
		Entity.FuelUse = ACF.FuelRate * Entity.BSFC -- * 3e-8 -- This forces any engine to consume literal nanoliters lol.
	--end

	WireLib.TriggerOutput(Entity, "State", "Idle")

end

function ENT:ACF_OnVerifyClientData(ClientData) end
function ENT:ACF_PreSpawn(_, _, _, ClientData)
	-- These shouldn't exist here, but the class menu stuff isn't finished yet, so we cope with this instead.
	local Engine = ClientData.EngineType
	local EngineClass = ClientData.EngineClass
	local AmbientTemperature = ACF.AmbientTemperature - 273.15 -- In Degrees Celcius

	Engine.Class = EngineClass -- Doesn't save for duplicator

	self.ACF 				= {}
	self.Active        		= false
	self.AmbientTemp        = AmbientTemperature
	self.Engine          	= Engine
	self.EngineFieldData   	= Classes.GetTypeByName(EngineType)
	self.ExhaustEntity 		= nil
	self.FuelTypes			= {}
	self.FuelTanks     		= {}
	self.Gearboxes     		= {}
	self.Radiators     		= {}
	self.Friction           = 0
	self.MassRatio     		= 1
	self.LastThink     		= 0
	self.LastTorque    		= 0
	self.LastFuelUsage 		= 0
	self.LastPower     		= 0
	self.LastRPM       		= 0
	self.LastTotalMass 		= 0
	self.LastPhysMass  		= 0
	self.LastState 			= ""
	self.LastPitch     		= 0
	self.SoundPath     		= "vehicles/junker/jnk_fourth_cruise_loop2.wav" -- Placeholder for now
	self.FuelUsage     		= 0
	self.Layout 	   		= ""
	self.Throttle 	   		= 0
	self.IsStalled		    = false
	self.State         		= "Idle"
	self.SoundBanks    		= {}
	self.RevLimiterEnabled 	= true
	self.LastCoolantTemp    = AmbientTemperature
	self.LastOilTemp        = AmbientTemperature
	self.Temperature   		= {Coolant = AmbientTemperature, Oil = AmbientTemperature}
	self.WaterPumpFlow		= 0
	-- Cope, cry and seethe 
	self.Model              = ClientData.CustomEngineModel
	self.Pistons 	   		= ClientData.CustomEnginePistons
	self.Bore          		= ClientData.CustomEngineBore
	self.Stroke        		= ClientData.CustomEngineStroke
	self.Clearance     		= ClientData.CustomEngineClearance

	duplicator.ClearEntityModifier(self, "mass")
end

function ENT.ACF_CheckSpawnLimit(Player)
	return Player:CheckLimit("_acf_engine_custom")
end

function ENT:ACF_PostSpawn()
	ACF.AugmentedTimer(function(cfg) self:UpdateFuelMod(cfg) end, function() return IsEntityValid(self) end, nil, {MinTime = 0.1, MaxTime = 0.25})
end

function ENT:ACF_PreUpdateEntityData()
	-- Don't reconfigure a running engine; shut it down first (no-op on a fresh spawn).
	if self.Active then self:Disable() end
end

function ENT:ACF_OnUpdateEntityData()
	--PrintTable(self.ACF_LiveData)
	print("Ran ENT:ACF_OnUpdateEntityData()")
end

function ENT:ACF_PostUpdateEntityData()
	UpdateEngine(self, self:GetEngineType())

	-- A reconfigure can invalidate existing links (no-op on a fresh spawn).
	if next(self.Gearboxes) then
		for Gearbox in pairs(self.Gearboxes) do
			self:Unlink(Gearbox)
			self:Link(Gearbox)
		end
	end

	if next(self.FuelTanks) then
		for Tank in pairs(self.FuelTanks) do
			if not self.FuelTypes[Tank.FuelType] then
				self:Unlink(Tank)
			end
		end
	end

	-- TODO: Handle radiator validation here
end

ACF.RegisterLinkSource("acf_engine_custom", "Gearboxes")
ACF.RegisterLinkSource("acf_engine_custom", "FuelTanks")
ACF.RegisterLinkSource("acf_engine_custom", "Radiators")

function ENT:PreEntityCopy()
	if next(self.Gearboxes) then
		local Gearboxes = {}

		for Gearbox in pairs(self.Gearboxes) do
			Gearboxes[#Gearboxes + 1] = Gearbox:EntIndex()
		end

		duplicator.StoreEntityModifier(self, "ACFGearboxes", Gearboxes)
	end

	if next(self.FuelTanks) then
		local Tanks = {}

		for Tank in pairs(self.FuelTanks) do
			Tanks[#Tanks + 1] = Tank:EntIndex()
		end

		duplicator.StoreEntityModifier(self, "ACFFuelTanks", Tanks)
	end

	if next(self.Radiators) then
		local Radiators = {}

		for Rad in pairs(self.Radiators) do
			Radiators[#Radiators + 1] = Rad:EntIndex()
		end

		duplicator.StoreEntityModifier(self, "ACFRadiators", Radiators)
	end

	-- AutoRegisterV2 wraps this as the original PreEntityCopy and handles the wire/base dupe info.
end

function ENT:PostEntityPaste(_, Ent, CreatedEntities)
	local EntMods = Ent.EntityMods

	-- Backwards compatibility
	if EntMods.GearLink then
		local Entities = EntMods.GearLink.entities

		for _, EntID in ipairs(Entities) do
			self:Link(CreatedEntities[EntID])
		end

		EntMods.GearLink = nil
	end

	-- Backwards compatibility
	if EntMods.FuelLink then
		local Entities = EntMods.FuelLink.entities

		for _, EntID in ipairs(Entities) do
			self:Link(CreatedEntities[EntID])
		end

		EntMods.FuelLink = nil
	end

	if EntMods.ACFGearboxes then
		for _, EntID in ipairs(EntMods.ACFGearboxes) do
			self:Link(CreatedEntities[EntID])
		end

		EntMods.ACFGearboxes = nil
	end

	if EntMods.ACFFuelTanks then
		for _, EntID in ipairs(EntMods.ACFFuelTanks) do
			self:Link(CreatedEntities[EntID])
		end

		EntMods.ACFFuelTanks = nil
	end

	-- AutoRegisterV2 wraps this as the original PostEntityPaste and handles the wire/base dupe info.
end

-- Cope for now, in the future we should consider adding the cost of any other attachments to this engine...
function ENT:GetCost()
	local selftbl = self:GetTable()

	return math.max(5, (selftbl.PeakTorque / 160) + (selftbl.PeakPower / 80))
end

-- Remove-only teardown. Captured by AutoRegisterV2 as OrigOnRemove; the generated OnRemove still
-- runs ACF_OnEntityLast + WireLib cleanup around this.
function ENT:OnRemove(IsFullUpdate)
	if IsFullUpdate then return end

	local Class = self.ClassData

	if Class and Class.OnLast then
		Class.OnLast(self, Class)
	end

	self:DestroySound()

	for Gearbox in pairs(self.Gearboxes) do
		self:Unlink(Gearbox)
	end

	for Tank in pairs(self.FuelTanks) do
		self:Unlink(Tank)
	end

	for Radiator in pairs(self.Radiators) do
		self:Unlink(Radiator)
	end

	TimerRemove("ACF Engine Clock " .. self:EntIndex())
	TimerRemove("ACF Temperature Clock " .. self:EntIndex())
end
