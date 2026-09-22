local ACF = ACF
local Damage = ACF.Damage

local ENTITY = FindMetaTable("Entity")
local max    = math.max
-- local Clamp  = math.Clamp

-- -- Constants, these are all assumed, and will need to fuck off if a rewrite is tried(or maybe not, who knows)
local RAD_HEALTH_BASE       = 150  -- HP at HealthMult=1
-- local LEAK_SEVERITY_THRESH  = 0.10
-- local CATASTROPHIC_THRESH   = 0.40
-- local LEAK_SOC_COEF         = 0.15 -- coolant fraction lost per unit

function ENT:ACF_Activate(recalc)
    local SelfTbl = ENTITY.GetTable(self)
    SelfTbl.ACF = SelfTbl.ACF or {}

    if not recalc then
        local HealthMult = SelfTbl.HealthMult or 1.0
        SelfTbl.ACF.MaxHealth = RAD_HEALTH_BASE * HealthMult
        SelfTbl.ACF.Health    = SelfTbl.ACF.MaxHealth
    end
end

function ENT:ACF_OnDamage(DmgResult, DmgInfo)
    local HitRes    = Damage.doPropDamage(self, DmgResult, DmgInfo)
    local SelfTbl   = ENTITY.GetTable(self)

--     local MaxHP     = SelfTbl.ACF.MaxHealth or 1
--     local Severity  = Clamp(DmgInfo:GetDamage() / MaxHP, 0, 1)

--     if Severity > CATASTROPHIC_THRESH then
--         SelfTbl.Amount = 0
--         SelfTbl.IsLeaking = true
--     elseif Severity > LEAK_SEVERITY_THRESH then
--         SelfTbl.Amount = max(0, SelfTbl.Amount - SelfTbl.Capacity * Severity * LEAK_SOC_COEF)
--         SelfTbl.IsLeaking = true
--     end

    -- Damaged core rejects heat less effectively.
    local HealthFrac = 1 - (SelfTbl.ACF.Health / SelfTbl.ACF.MaxHealth)
    SelfTbl.CoreEff = max(0.2, 1.0 - 0.5 * HealthFrac)

    if SelfTbl.ACF.Health == 0 then
        SelfTbl.Amount      = 0 -- All fluid contents were lost 
        SelfTbl.IsLeaking   = true
        SelfTbl.IsDestroyed = true
    end

    return HitRes
end

function ENT:ACF_OnRepaired()
    local SelfTbl = ENTITY.GetTable(self)

    -- If fully repaired do the sound
    if SelfTbl.ACF.Health == SelfTbl.ACF.MaxHealth and SelfTbl.IsDestroyed then
        SelfTbl.IsLeaking   = false
        SelfTbl.IsDestroyed = false
        ACF.DoRepairSound(self)
    end

    -- Always refill the radiator
    SelfTbl.Amount = SelfTbl.Capacity
    self:UpdateOverlay()
end