local ACF     		= ACF
local Classes 		= ACF.Classes
local Messages      = ACF.Utilities.Messages

local GetType 		= Classes.GetTypeByName
local Round   		= math.Round
local max           = math.max
local TimerRemove   = timer.Remove
local Contraption   = ACF.Contraption
local IsEntityValid = ACF.Optimizations.IsEntityValid

local function UpdateEngine(Entity, ClassData)
	Entity.ACF = Entity.ACF or {}

	local Model = Entity:ACF_GetUserVar("CustomEngineModel") or ClassData.CustomEngineModel
	Entity:SetScaledModel(Model)

	local Params = {
		Pistons    = Entity:ACF_GetUserVar("CustomEnginePistons") or ClassData.CustomEnginePistons,
		Bore	   = Entity:ACF_GetUserVar("CustomEngineBore") or ClassData.CustomEngineBore,
		Stroke 	   = Entity:ACF_GetUserVar("CustomEngineStroke") or ClassData.CustomEngineStroke,
		Clearance  = Entity:ACF_GetUserVar("CustomEngineClearance") or ClassData.CustomEngineClearance,
		BankAngle  = Entity:ACF_GetUserVar("CustomEngineBankAngle") or ClassData.CustomEngineBankAngle,
		BankAmount = Entity:ACF_GetUserVar("CustomEngineBankAmount") or ClassData.CustomEngineBankAmount,
	}

	local EngineClass = Entity.EngineFuelType
	local TypeDef     = GetType(EngineClass)
	local FuelTypes   = GetType(EngineClass).Fuel

	local ExtraEngineFields = {
		PistonSpeed  = TypeDef.PistonSpeed,
		Efficiency   = TypeDef.Efficiency,
		TorqueScale  = TypeDef.TorqueScale,
		TorqueCurve  = TypeDef.TorqueCurve,
		IgnitionType = TypeDef.IgnitionType
	}

	local LayoutFactors = ClassData.GetLayoutFactors(Params.Pistons, Params.BankAngle)
	local Compute = ClassData.Compute(_, LayoutFactors, Params, ExtraEngineFields)

	local Displacement = Compute.Displacement
	local Sign = Compute.Sign
	local Type = TypeDef.ShortName
	local Name
	if Displacement.InLiters <= 1 then
		Name = ("%scc %s - %s"):format(Round(Displacement.InCubicCentimeters, 0), Sign, Type)
	else
		Name = ("%sL %s - %s"):format(Round(Displacement.InLiters, 1), Sign, Type)
	end

	-- Class compute table assignments
	Entity.ACF.Model 		    = Model
	Entity.Name      			= Name
	Entity.ShortName 			= Type
	Entity.BalanceFactor  		= Compute.BalanceFactor
	Entity.BigEndDiam     		= Compute.BigEndDiam
	Entity.BlockType	 		= Compute.IsPiston and "Piston" or Compute.IsTurbine and "Turbine" or Compute.IsElectric and "Electric"
	Entity.Bore	        		= Compute.Bore
	Entity.BSFC 				= Compute.BSFC
	Entity.CompressionRatio 	= Compute.CompressionRatio
	Entity.Clearance      		= Compute.Clearance
	Entity.CoolantLevel         = 0
	Entity.DefaultSound       	= Entity.SoundPath
	Entity.Displacement 		= Displacement
	Entity.FiringIrregularity 	= Compute.FiringIrregularity
	Entity.FlywheelInertia 		= Compute.FlywheelInertia
	Entity.FlyRPM				= 0
	Entity.FuelTypes          	= FuelTypes or { ["ACF.CustomFuelTypes.Petrol"] = true }
	Entity.FuelType           	= next(FuelTypes)
	Entity.HeatCoefficient		= Compute.HeatCoeff
	Entity.HealthMult			= TypeDef.HealthMult
	Entity.ID                   = Name
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
	Entity.Stroke				= Compute.Stroke
	Entity.SweptVolPerCyl		= Compute.SweptVolPerCyl
	Entity.Type                 = TypeDef.Name
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

function ENT:ACF_PreSpawn(_, _, _, ClientData)
	-- TODO: This should be either Ambient or Room Temp, depending on where you're spawning this engine.
	local AmbientTemperature = ACF.AmbientTemperature - 273.15 -- In Degrees Celcius
	-- Ugly hack just to get duplicator support in a working state :((((
	local EngineBlockType = istable(ClientData.BlockType) and ClientData.BlockType.Type or ClientData.BlockType
	local EngineFuelType  = istable(ClientData.EngineType) and ClientData.EngineType.Type or ClientData.EngineType

	self.ACF 				= {}
	self.Active        		= false
	self.AmbientTemp        = AmbientTemperature
	self.EngineBlockType    = EngineBlockType
	self.EngineFuelType     = EngineFuelType
	self.ExhaustEntity 		= nil
	self.FuelTypes			= {}
	self.FuelTanks     		= {}
	self.Gearboxes     		= {}
	self.Radiators     		= {}
	self.HasStarter         = true -- TODO: true for now, it should be a uservar
	self.Starter            = nil
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
	self.IdleThrottle	    = 0
	self.LastIdleThrottle   = 0
	self.IsStalled		    = false
	self.State         		= "Idle"
	self.SoundBanks    		= {}
	self.RevLimiterEnabled 	= true
	self.LastCoolantTemp    = AmbientTemperature
	self.LastOilTemp        = AmbientTemperature
	self.Temperature   		= {Coolant = AmbientTemperature, Oil = AmbientTemperature}
	self.WaterPumpFlow		= 0

	duplicator.ClearEntityModifier(self, "mass")
	CFW.addTransformProxy("acf_engine_custom", "Starter", "acf_starter", "Engine")
end

function ENT.ACF_CheckSpawnLimit(Player)
	return Player:CheckLimit("_acf_engine_custom")
end

local function OnUpdateEntity(Entity)
	local SelfTbl = Entity:GetTable()
	if not SelfTbl.HasStarter then return end

	-- Rebuild the starter.
	if not IsValid(SelfTbl.Starter) then
		local Starter = ents.Create("acf_starter")

		if not IsValid(Starter) then
			error(tostring(Entity) .. " did not have a valid starter spawn with it!")
			Entity:Remove()

			return
		-- Setup custom attachments if none was found.
		elseif Entity:LookupAttachment("starter") == 0 then
			GetType(SelfTbl.EngineBlockType).AddCustomAttachments() -- Call to set the attachment points.

			-- Fucking bitchass function didn't work? Print error in chat and gtfo here.
			if Entity:LookupAttachment("starter") == 0 then
				local Owner = Entity:GetOwner()

				Messages.SendChat(Owner, "Error", tostring(Entity) .. " did not have a valid attachment point for \"starter\"!")
				Starter:Remove()
				return
			end
		end

		local StarterPos = Entity:GetAttachment(Entity:LookupAttachment("starter")).Pos
		local StarterAng = Entity:GetAttachment(Entity:LookupAttachment("starter")).Ang

		Starter:SetScaledModel("models/engines/emotor-standalone-tiny.mdl")
		Starter:SetLocalPos(StarterPos)
		Starter:SetAngles(StarterAng)
		Starter:SetScale(0.5 * SelfTbl.Scale)
		Starter:SetParent(Entity)
		Starter:Spawn()
		Starter:SetCollisionGroup(COLLISION_GROUP_WORLD)
		Starter:DrawShadow(false)

		Entity:SetNWEntity("ACF.Starter", Starter)

		local Mass = 5 * SelfTbl.Scale[1]
		Contraption.SetMass(Starter, Mass)

		SelfTbl.StarterPos = Entity:WorldToLocal(StarterPos)
		SelfTbl.Starter = Starter
		Starter.Engine  = Entity
		Starter.Owner   = Entity
	end
end

function ENT:ACF_PostSpawn()
	ACF.AugmentedTimer(function(cfg) self:UpdateFuelMod(cfg) end, function() return IsEntityValid(self) end, nil, {MinTime = 0.1, MaxTime = 0.25})
end

function ENT:ACF_PreUpdateEntityData()
	-- Don't reconfigure a running engine; shut it down first (no-op on a fresh spawn).
	if self.Active then self:Disable() end
end

function ENT:ACF_PostUpdateEntityData(ClientData)
	UpdateEngine(self, self:GetBlockType())
	OnUpdateEntity(self)

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

	if EntMods.ACFRadiators then
		for _, EntID in ipairs(EntMods.ACFRadiators) do
			self:Link(CreatedEntities[EntID])
		end

		EntMods.ACFRadiators = nil
	end

	-- AutoRegisterV2 wraps this as the original PostEntityPaste and handles the wire/base dupe info.
end

-- Cope for now, in the future we should consider adding the cost of any other attachments to this engine...
function ENT:GetCost()
	local selftbl = self:GetTable()

	return max(5, (selftbl.PeakTorque.InNm / 160) + (selftbl.PeakPower.InKW / 80))
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
