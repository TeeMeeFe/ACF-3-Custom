local ACF       = ACF
local Damage    = ACF.Damage
local Clamp     = math.Clamp

-- Single source of truth for the health->performance curve. 
function ENT:UpdateTorqueDamageMult()
	local TorqueMult = Clamp(((1 - self.TorqueScale) / 0.5) * ((self.ACF.Health / self.ACF.MaxHealth) - 1) + 1, self.TorqueScale, 1)
	self.TorqueDamageMult = TorqueMult

	return TorqueMult
end

function ENT:ACF_OnDamage(DmgResult, DmgInfo)
	local HitRes = Damage.doPropDamage(self, DmgResult, DmgInfo)

	self:UpdateTorqueDamageMult()

	if self.ACF.Health == 0 then
		self.IsDestroyed = true
		self:Disable()
	end

	return HitRes
end

function ENT:ACF_OnRepaired()
	self:UpdateTorqueDamageMult()

	if self.ACF.Health == self.ACF.MaxHealth and self.IsDestroyed then
		self.IsDestroyed = false
		self:UpdateOverlay()
		ACF.DoRepairSound(self)
	end
end
