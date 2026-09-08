local ACF = ACF
local Clock          = ACF.Utilities.Clock
local Contraption    = ACF.Contraption

local ENTITY         = FindMetaTable("Entity")
local PHYSOBJ        = FindMetaTable("PhysObj")

local IsEntityValid	 = ACF.Optimizations.IsEntityValid
local IsPhysObjValid = ACF.Optimizations.IsPhysObjValid

--===============================================================================================--
-- Constants 
--===============================================================================================--

-- Water pump: Q (L/s) = K_PUMP_FLOW × RPM
-- 0.667 L/s at 3 000 RPM (≈ 40 L/min automotive spec)
local K_PUMP_FLOW       = 0.667 / 3000

-- Oil passive cooling
-- K_OIL_AMB × (90 - 20) = HEAT_IDLE_GAIN × HEAT_FRAC_OIL = 0.045
local K_OIL_AMB         = 0.045 / 70  -- 6.43e-4

--===============================================================================================--
-- Local Funcs and Vars
--===============================================================================================--
local PI = math.pi
local max = math.max

do -- State Handling
    function ENT:CalcTemp(SelfTbl)
        SelfTbl = SelfTbl or ENTITY.GetTable(self)
        if SelfTbl.Disabled then return end

        local ClockTime = Clock.CurTime
        local DeltaTime = ClockTime - SelfTbl.LastThink
        local Throttle  = max(SelfTbl.Throttle, 0.01)
        local RPM       = SelfTbl.FlyRPM or 0
        local Power     = max(SelfTbl.Torque * RPM / 9548.8, 0)
        local IdleRPM   = SelfTbl.IdleRPM
        local AmbTemp   = SelfTbl.AmbientTemp
        local IsPrimed  = SelfTbl.FuelPrimed
        local HeatCoeff = SelfTbl.HeatCoefficient or 0.012
        local AsmFric   = SelfTbl.Friction or 1

        -- Assembly friction adds heat to the oil circuit
        local Omega     = (RPM * 2 * PI) * 0.0166667
        local PowerFriction = (AsmFric * Omega) * 0.001

        local IdleHeat  = ACF.HeatGenerationAtIdle * ACF.HeatGenerationScalar * DeltaTime
        local LoadHeat  = HeatCoeff * Power * Throttle * ACF.HeatGenerationScalar * DeltaTime

        local TotalHeat = IsPrimed and SelfTbl.Active and IdleHeat + LoadHeat or 0

        -- Actual Thermal Calcs
        local CT = SelfTbl.Temperature.Coolant
        local OT = SelfTbl.Temperature.Oil

        -- Get the vehicle speed for the radiator ram-air effect
        local Ancestor = Contraption.GetAncestor(self)
        local AncestorPhys = IsEntityValid(Ancestor) and ENTITY.GetPhysicsObject(Ancestor)
        local Velocity = (AncestorPhys and IsPhysObjValid(AncestorPhys)) and PHYSOBJ.GetVelocity(AncestorPhys):Length() or 0

        local TotalHOCool = 0 -- Total Heat Out to Coolant
        SelfTbl.WaterPumpFlow = 0 -- We start at 0, cause we haven't calculated this yet or because there's no radiators

        local Rads = SelfTbl.Radiators
        for Ent, Link in pairs(Rads) do
            if IsEntityValid(Ent) then
                local EntTable = ENTITY.GetTable(Ent)

                if not EntTable.Disabled and EntTable.Active then
                    local Amount          = EntTable.Amount
                    local Capacity        = EntTable.Capacity

                    local CoolantLevel    = Amount / Capacity
                    local CoolantLevelMin = 0.15 -- Coolant level threshold

                    -- Water pump flow. Cavitates if coolant level is critically low
                    local Q = CoolantLevel >= CoolantLevelMin and K_PUMP_FLOW * RPM or 0
                    SelfTbl.WaterPumpFlow = SelfTbl.WaterPumpFlow + Q

                    TotalHOCool = TotalHOCool + Ent:CalcTemp(CT, TotalHeat, Q, DeltaTime, Velocity)
                else
                    TotalHOCool = TotalHOCool + Ent:CalcTemp(CT, 0, 0, DeltaTime, Velocity)
                end
            end
        end

        -- Oil<->coolant heat exchange (bidirectional, scales with RPM)
        local K_OC = 0.001 * (RPM / IdleRPM) * ACF.HeatGenerationScalar
        local ExchangedHeat = K_OC * (OT - CT) * DeltaTime

        -- Total heat generated, distributed to coolant and oil.
        local HeatToCool = ACF.HeatFractionToCoolant * TotalHeat
        local HeatToOil  = ACF.HeatFractionToOil * TotalHeat + (PowerFriction * 0.001) * DeltaTime

        -- Sump passive cooling + assembly friction heat added to oil
        local HOCool = K_OIL_AMB * (CT - AmbTemp) * DeltaTime -- Passive Heat out 
        local HOOil = K_OIL_AMB * (OT - AmbTemp) * DeltaTime

        -- Total calculation assignments 
        SelfTbl.Temperature.Coolant = max(AmbTemp, CT + HeatToCool - TotalHOCool - HOCool + ExchangedHeat)
        SelfTbl.Temperature.Oil     = max(AmbTemp, OT + HeatToOil - HOOil - ExchangedHeat)

        SelfTbl.WasTimed = false -- Reset our timer just in case 
        return true
    end
end