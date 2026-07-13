local ACF = ACF
local Clock         = ACF.Utilities.Clock

local ENTITY        = FindMetaTable("Entity")
local IsEntityValid	= ACF.Optimizations.IsEntityValid

--===============================================================================================--
-- Constants 
--===============================================================================================--

-- Coolant thresholds (°C)
-- local COOL_OPTIMAL    = 88
-- local COOL_WARN       = 105
-- local COOL_MAX        = 120

-- -- Oil thresholds (°C)
-- local OIL_OPTIMAL     = 90
-- local OIL_WARN        = 130
-- local OIL_MAX         = 160

-- Water pump: Q (L/s) = K_PUMP_FLOW × RPM
-- 0.667 L/s at 3 000 RPM (≈ 40 L/min automotive spec)
local K_PUMP_FLOW       = 0.667 / 3000

-- Oil passive cooling
-- K_OIL_AMB × (90 - 20) = HEAT_IDLE_GAIN × HEAT_FRAC_OIL = 0.045
local K_OIL_AMB         = 0.045 / 70  -- 6.43e-4

-- Oil↔coolant exchange (scales with RPM)
local K_OC_BASE         = 0.001 -- game-units/(s·K) when active and at idle

--===============================================================================================--
-- Local Funcs and Vars
--===============================================================================================--
local PI = math.pi
local max = math.max

do -- State Handling
    function ENT:CalcTemp(SelfTbl)
        SelfTbl = SelfTbl or ENTITY.GetTable(self)

        local ClockTime = Clock.CurTime
        local DeltaTime = ClockTime - SelfTbl.LastThink
        local Torque    = SelfTbl.Torque
        local RPM       = SelfTbl.FlyRPM or 0
        local IdleRPM   = SelfTbl.IdleRPM
        local AmbTemp   = SelfTbl.AmbientTemp
        local HeatCoeff = SelfTbl.HeatCoefficient or 0.012
        local AsmFric   = SelfTbl.Friction or 1

        -- Assembly friction adds heat to the oil circuit
        local Omega     = (RPM * 2 * PI) * 0.0166667
        local P_fric_kW = (AsmFric * Omega) * 0.001

        local TotalHeat = (ACF.HeatGenerationAtIdle + HeatCoeff) * Torque * DeltaTime * ACF.HeatGenerationScalar

        -- Actual Thermal Calcs
        local CT = SelfTbl.Temperature.Coolant
        local OT = SelfTbl.Temperature.Oil

        local HOCool = 0

        SelfTbl.WaterPumpFlow = 0 -- We start at 0, cause we haven't calculated this yet or because there's no radiators

        local Rads = SelfTbl.Radiators
        for Ent, Link in pairs(Rads) do
            if IsEntityValid(Ent) then
                local EntTable = ENTITY.GetTable(Ent)

                if not EntTable.Disabled then
                    local Amount          = EntTable.Amount
                    local Capacity        = EntTable.Capacity

                    local CoolantLevel    = (Capacity and Amount) and (Amount / Capacity) or 1
                    local CoolantLevelMin = 0.15 -- Coolant level threshold

                    -- Water pump flow. Cavitates if coolant level is critically low
                    local Q = CoolantLevel >= CoolantLevelMin and K_PUMP_FLOW * RPM or 0
                    SelfTbl.WaterPumpFlow = Q

                    HOCool = Ent:CalcTemp(CT, TotalHeat, Q, DeltaTime)
                end
            end
        end

        -- Oil↔coolant heat exchange (bidirectional, scales with RPM)
        local K_OC = K_OC_BASE * (RPM / IdleRPM) * ACF.HeatGenerationScalar
        local ExchangedHeat = K_OC * (OT - CT) * DeltaTime

        -- Total heat generated, distributed to coolant and oil.
        local HeatToCool = ACF.HeatFractionToCoolant * TotalHeat
        local HeatToOil  = ACF.HeatFractionToOil * (TotalHeat + P_fric_kW * 0.001) * DeltaTime

        -- Sump passive cooling + assembly friction heat added to oil
        local HOOil = K_OIL_AMB * (OT - AmbTemp) * DeltaTime

        -- Total calculation assignments 
        SelfTbl.Temperature.Coolant = max(AmbTemp, CT + HeatToCool - HOCool + ExchangedHeat)
        SelfTbl.Temperature.Oil     = max(AmbTemp, OT + HeatToOil - HOOil - ExchangedHeat)

        SelfTbl.WasTimed = false -- Reset our timer just in case 
        return true
    end
end