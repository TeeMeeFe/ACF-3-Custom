local ACF    = ACF
local Damage = ACF.Damage
local Clamp  = math.Clamp

-- This function needs to return HitRes
function ENT:ACF_OnDamage(DmgResult, DmgInfo)
	local HitRes = Damage.doPropDamage(self, DmgResult, DmgInfo)

	-- Adjusting performance based on damage
	local TorqueMult = Clamp(((1 - self.TorqueScale) / 0.5) * ((self.ACF.Health / self.ACF.MaxHealth) - 1) + 1, self.TorqueScale, 1)

	self.PeakTorque = self.PeakTorqueHeld * TorqueMult

	return HitRes
end
