local ACF     = ACF
local Classes = ACF.Classes
local Round   = math.Round

local TimerRemove  = timer.Remove

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

	self.Active        		= false
	self.ExhaustEntity 		= nil
	self.Gearboxes     		= {}
	self.FuelTanks     		= {}
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
	self.Pistons 	   		= Pistons
	self.Bore          		= Bore
	self.Stroke        		= Stroke
	self.Clearance     		= Clearance

	duplicator.ClearEntityModifier(self, "mass")
end

function ENT:ACF_PostSpawn(Owner, _, _, ClientData)
	--Contraption.SetMass(self, self.ACF.Mass) -- We later get the mass of the contraption
	--duplicator.StoreEntityModifier(self, "mass", { Mass = 100 })

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
	self.DefaultSound       = self.SoundPath
	self.Displacement 		= Displacement
	self.FiringIrregularity = Compute.FiringIrregularity
	self.FlywheelInertia 	= Compute.FlywheelInertia
	self.FlyRPM				= 0
	self.HeatCoefficient	= Compute.HeatCoeff
	self.HealthMult			= 0.3 -- Insane coping because march did something with the class registration 
	self.IdleRPM			= Compute.IdleRPM
	self.IsStalled			= false
	self.Layout				= Compute.Layout
	self.RedlineRPM   		= Compute.RedlineRPM
	self.OilSumpTilt  		= Compute.OilSumpTilt
	self.PeakTorque			= Compute.PeakTorque
	self.PeakPower			= Compute.PeakPower
	self.PowerBand			= Compute.PowerBand
	self.Pistons 			= Compute.Pistons
	self.RodRatio			= Compute.RodRatio
	self.RevLimited			= false
	self.SoundPitch         = self.Pitch or 1
	self.SoundVolume        = self.SoundVolume or 1
	self.Sign 				= Sign
	self.Sample				= Compute.Sample
	self.SparksPerRev		= Compute.SparksPerRev
	self.Stroke				= Compute.StrokeCm
	self.SweptVolPerCyl		= Compute.SweptVolPerCyl
	self.TorqueSmoothness	= Compute.TorqueSmoothness
	self.TorqueCurve		= Compute.TorqueCurve
	self.Torque             = 0
	self.VECurve		    = Compute.VECurve
	self.HitBoxes         	= ACF.GetHitboxes(self:GetModel())
	self.Out              	= ACF.LocalPlane(self:WorldToLocal(self:GetAttachment(self:LookupAttachment("driveshaft")).Pos), Vector(1, 0, 0))

	PrintTable(Compute)
	WireLib.TriggerOutput(self, "State", "Idle")
end

function ENT:ACF_OnUpdateEntityData()
	--PrintTable(self.ACF_LiveData)
	print("Ran ENT:ACF_OnUpdateEntityData()")
end

function ENT:ACF_PostUpdateEntityData(ClientData)
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

ACF.RegisterLinkSource("acf_engine_custom", "Gearboxes")
ACF.RegisterLinkSource("acf_engine_custom", "FuelTanks")
ACF.RegisterLinkSource("acf_engine_custom", "Radiators")

-- Remove-only teardown. Captured by AutoRegisterV2 as OrigOnRemove; the generated OnRemove still
-- runs ACF_OnEntityLast + WireLib cleanup around this.
function ENT:OnRemove(IsFullUpdate)
	if IsFullUpdate then return end

	self:DestroySound() -- Don't have this yet

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

-- Cope for now
function ENT:ACF_Activate()
end
--[[]
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
end]]--

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