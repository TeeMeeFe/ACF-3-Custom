local ACF       = ACF
local Damage    = ACF.Damage
local Clamp     = math.Clamp

-- This function needs to return HitRes
function ENT:ACF_OnDamage(DmgResult, DmgInfo)
	local HitRes = Damage.doPropDamage(self, DmgResult, DmgInfo)

	-- Adjusting performance based on damage
	local TorqueMult = Clamp(((1 - self.TorqueScale) / 0.5) * ((self.ACF.Health / self.ACF.MaxHealth) - 1) + 1, self.TorqueScale, 1)

	self.TorqueDamageMult = TorqueMult

	if self.ACF.Health == 0 then
		self.IsDestroyed = true
		self:Disable()
	end

	return HitRes
end

function ENT:ACF_OnRepaired() -- OldArmor, OldHealth, Armor, Health
	-- Adjusting performance based on damage
	local TorqueMult = Clamp(((1 - self.TorqueScale) / 0.5) * ((self.ACF.Health / self.ACF.MaxHealth) - 1) + 1, self.TorqueScale, 1)
	self.TorqueDamageMult = TorqueMult

	if self.ACF.Health == self.ACF.MaxHealth and self.IsDestroyed then
		self.IsDestroyed = false
		self:UpdateOverlay()
		ACF.DoRepairSound(self)
	end
end

