local ACF         = ACF
local Classes     = ACF.Classes
local WireLib     = WireLib
local ActiveTanks = ACF.FuelTanks

local TANK_MATERIAL = "models/props_canal/metalcrate001d"

do -- Spawning
	function ENT:ACF_PreSpawn(_, _, _, ClientData)
		self.ACF = {}

		local ShapeClass = Classes.GetTypeByName(ClientData.Shape) or Classes.GetTypeByName("ACF.ContainerShapes.Box")
		local Model      = ShapeClass.Model

		self.ACF.Model = Model

		self:SetMaterial(TANK_MATERIAL)
		self:SetScaledModel(Model)
	end

	function ENT:ACF_OnSpawn()
		self.Engines       = {}
		self.Leaking       = 0
		self.LastThink     = 0
		self.LastAmount    = 0
		self.LastActivated = 0

		duplicator.ClearEntityModifier(self, "mass")

		ActiveTanks[self] = true
	end

	function ENT:ACF_PostSpawn()
		self:TriggerInput("Active", 1)
		WireLib.TriggerOutput(self, "Entity", self)
	end
end

do -- Updating
	function ENT:ACF_PostUpdateEntityData()
		self.ACF = self.ACF or {}

		local FuelType = self:ACF_GetUserVar("FuelType")
		local Shape    = self:ACF_GetUserVar("Shape")
		local Size     = Vector(
			self:ACF_GetUserVar("FuelSizeX"),
			self:ACF_GetUserVar("FuelSizeY"),
			self:ACF_GetUserVar("FuelSizeZ")
		)
		local Model    = (Shape and Shape.Model) or "models/acf/core/s_fuel.mdl"

		-- Keep the current fuel level proportionally when reconfiguring an existing tank.
		local Percentage = (self.Capacity and self.Amount) and (self.Amount / self.Capacity) or 1

		self.ACF.Model = Model
		self:SetScaledModel(Model)
		self:SetSize(Size)
		self:SetMaterial(TANK_MATERIAL)

		local FuelID = FuelType.ID
		-- Publish the fuel type FQN so engine links (keyed by FQN, see acf_engine) resolve.
		self.FuelType    = Classes.GetTypeName(FuelType:GetType())
		self.FuelDensity = FuelType.Density
		self.IsExplosive = FuelType.IsExplosive
		self.IsElectric  = FuelType.IsElectric
		self.NoLinks     = false
		self.EntType     = "Fuel Tank"
		self.Name        = FuelID .. " Tank"
		self.ShortName   = FuelID
		self.WireAmountName = "Fuel"

		local _, Capacity, EmptyMass = self:CalcVolumeAndCapacity(Size)

		self.Capacity  = Capacity -- Internal volume available for fuel in liters
		self.EmptyMass = EmptyMass

		if FuelType.IsElectric then
			self.Name     = "Electric Battery"
			self.Liters   = Capacity -- Batteries' capacity is different from internal volume
			self.Capacity = Capacity * ACF.LiIonED
			self.UnitMass = FuelType.Density / ACF.LiIonED -- kg per kWh
		else
			self.UnitMass = FuelType.Density -- kg per liter
		end

		self:SetNWString("WireName", "ACF " .. self.Name)

		self.Amount = Percentage * self.Capacity

		self:UpdateMass(true)

		WireLib.TriggerOutput(self, "Fuel", self.Amount)
		WireLib.TriggerOutput(self, "Capacity", self.Capacity)

		-- Unlink engines that can no longer use this fuel type / model.
		if self.Engines and next(self.Engines) then
			for Engine in pairs(self.Engines) do
				if self.NoLinks or not Engine.FuelTypes[self.FuelType] then
					self:Unlink(Engine)
				end
			end
		end
	end
end

ACF.RegisterLinkSource("acf_fueltank_custom", "Engines")

-- Wire input handler for Active
ACF.AddInputAction("acf_fueltank_custom", "Active", function(Entity, Value)
	Entity.Active = tobool(Value)

	WireLib.TriggerOutput(Entity, "Activated", Entity.Active and 1 or 0)
end)

-- Remove-only teardown. Captured by AutoRegisterV2 as OrigOnRemove; the generated OnRemove still
-- runs ACF_OnEntityLast + WireLib cleanup around this.
function ENT:OnRemove(IsFullUpdate)
	if IsFullUpdate then return end

	if self.Engines then
		for Engine in pairs(self.Engines) do
			self:Unlink(Engine)
		end
	end

	ActiveTanks[self] = nil
end
