local ACF     = ACF
local Classes = ACF.Classes
local Round   = math.Round

local TimerRemove  = timer.Remove

local IsEntityValid = ACF.Optimizations.IsEntityValid

-- Engines should have these states: IDLE, STARTING, ACTIVE, STALLING
-- Old engines had ACTIVE, IDLE. 

local function UpdateEngine(Entity, Class)
	Entity.ACF = Entity.ACF or {}
	Entity:SetScaledModel(Class.Model)

	local Params = {
		Pistons   = Entity.Pistons,
		Bore	  = Entity.Bore,
		Stroke 	  = Entity.Stroke,
		Clearance = Entity.Clearance
	}

	local TypeFields = Classes.GetTypeByName(Entity.EngineClass)
	local FuelTypes = TypeFields.Fuel

	local LayoutFactors = Class.GetLayoutFactors(Entity.Pistons)
	local Compute = Class.Compute(Sel, LayoutFactors, Params)

	local Displacement = Compute.Displacement
	local Sign = Compute.Sign
	local Name = ("%sL %s - %scc"):format(Round(Displacement.InLiters, 1), Sign, Round(Displacement.InCubicCentimeters))

	-- Class compute table assignments
	Entity.Name      			= Name
	Entity.ShortName 			= Name
	Entity.BalanceFactor  		= Compute.BalanceFactor
	Entity.BigEndDiam     		= Compute.BigEndDiam_cm
	Entity.BlockType	 		= Compute.IsPiston and "Piston" or Compute.IsTurbine and "Turbine" or Compute.IsElectric and "Electric"
	Entity.Bore	        		= Compute.BoreCm
	Entity.BSFC 				= Compute.BSFC
	Entity.CompressionRatio 	= Compute.CompressionRatio
	Entity.Clearance      		= Compute.ClearanceCm
	Entity.DefaultSound       	= Entity.SoundPath
	Entity.Displacement 		= Displacement
	Entity.FiringIrregularity 	= Compute.FiringIrregularity
	Entity.FlywheelInertia 		= Compute.FlywheelInertia
	Entity.FlyRPM				= 0
	Entity.FuelTypes          	= FuelTypes or { ["ACF.CustomFuelTypes.Petrol"] = true }
	Entity.FuelType           	= next(FuelTypes)
	Entity.HeatCoefficient		= Compute.HeatCoeff
	Entity.HealthMult			= TypeFields.HealthMult
	Entity.IdleRPM				= Compute.IdleRPM
	Entity.IsStalled			= false
	Entity.Layout				= Compute.Layout
	Entity.RedlineRPM   		= Compute.RedlineRPM
	Entity.OilSumpTilt  		= Compute.OilSumpTilt
	Entity.PeakTorque			= Compute.PeakTorque
	Entity.PeakPower			= Compute.PeakPower
	Entity.PowerBand			= Compute.PowerBand
	Entity.Pistons 				= Compute.Pistons
	Entity.RodRatio				= Compute.RodRatio
	Entity.RevLimited			= false
	Entity.SoundPitch         	= Entity.Pitch or 1
	Entity.SoundVolume        	= Entity.SoundVolume or 1
	Entity.Sign 				= Sign
	Entity.Sample				= Compute.Sample
	Entity.SparksPerRev			= Compute.SparksPerRev
	Entity.Stroke				= Compute.StrokeCm
	Entity.SweptVolPerCyl		= Compute.SweptVolPerCyl
	Entity.TorqueSmoothness		= Compute.TorqueSmoothness
	Entity.TorqueCurve			= Compute.TorqueCurve
	Entity.Torque           	= 0
	Entity.VECurve		    	= Compute.VECurve
	Entity.HitBoxes         	= ACF.GetHitboxes(Entity:GetModel())
	Entity.Out              	= ACF.LocalPlane(Entity:WorldToLocal(Entity:GetAttachment(Entity:LookupAttachment("driveshaft")).Pos), Vector(1, 0, 0))

	--PrintTable(Compute)
	WireLib.TriggerOutput(Entity, "State", "Idle")

end

function ENT:ACF_OnVerifyClientData(ClientData) end
function ENT:ACF_PreSpawn(_, _, _, ClientData)
	local Engine = Classes.GetTypeByName(ClientData.EngineType)
	--PrintTable({Classes.GetTypeByName(ClientData.EngineClass)})

	self.ACF 				= {}
	self.ACF.Model 		    = Model
	self.Active        		= false
	self.Engine             = Engine
	self.EngineType 		= Classes.GetTypeName(Engine)
	self.EngineClass   		= ClientData.EngineClass
	self.ExhaustEntity 		= nil
	self.FuelTypes			= {}
	self.FuelTanks     		= {}
	self.Gearboxes     		= {}
	self.Radiators     		= {}
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
	self.Temperature   		= {Water = ACF.AmbientTemperature, Oil = ACF.AmbientTemperature}
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
	UpdateEngine(self, self.Engine) -- ENT:GetBlockType doesn't work

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

function ENT:PostEntityPaste(Player, Ent, CreatedEntities)
	--[[local EntMods = Ent.EntityMods

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

	--Wire dupe info
	self.BaseClass.PostEntityPaste(self, Player, Ent, CreatedEntities)]]--
end

-- Remove-only teardown. Captured by AutoRegisterV2 as OrigOnRemove; the generated OnRemove still
-- runs ACF_OnEntityLast + WireLib cleanup around this.
function ENT:OnRemove(IsFullUpdate)
	if IsFullUpdate then return end

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
end

-- Cope for now, this doesn't work apparently for scalables 
function ENT:ACF_Activate(Recalc)
	local PhysObj = self.ACF.PhysObj
	local Mass    = PhysObj:GetMass()
	local Area    = PhysObj:GetSurfaceArea() * ACF.InchToCmSq
	-- Fucking ArmoUr :face_vomiting: :face_vomiting: :face_vomiting: :face_vomiting: :face_vomiting:
	-- Britons gave us americans the english language so we can sanitize it and have it sound more or less understandable and be more legible!
	-- TODO: Replace this variable name and all instances of it with the correct word and fix the comment since its wrong lol
	local Armour  = Mass * 1000 / Area / 0.78 * ACF.ArmorMod -- Density of steel = 7.8g cm3 so 7.8kg for a 1mx1m plate 1m thick
	local Health  = Area / ACF.Threshold
	local Percent = 1

	if Recalc and self.ACF.Health and self.ACF.MaxHealth then
		Percent = self.ACF.Health / self.ACF.MaxHealth
	end

	self.ACF.Area      = Area
	self.ACF.Health    = Health * Percent * self.HealthMult
	self.ACF.MaxHealth = Health * self.HealthMult
	self.ACF.Armour    = Armour * (0.5 + Percent * 0.5)
	self.ACF.MaxArmour = Armour
	self.ACF.Type      = "Prop"
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