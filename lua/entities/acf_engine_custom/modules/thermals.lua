local ACF = ACF
local Clock          = ACF.Utilities.Clock
local Contraption    = ACF.Contraption

local ENTITY         = FindMetaTable("Entity")
local PHYSOBJ        = FindMetaTable("PhysObj")

local IsEntityValid	 = ACF.Optimizations.IsEntityValid
local IsPhysObjValid = ACF.Optimizations.IsPhysObjValid

--===============================================================================================--
-- Constants (Slop swamp warning [Sorryyyy >.<])
--===============================================================================================--

-- Water pump: Q (L/s) = K_PUMP_FLOW × RPM
-- 0.667 L/s at 3 000 RPM (≈ 40 L/min automotive spec)
local K_PUMP_FLOW  = 0.667 / 3000
-- Oil passive cooling
-- K_OIL_AMB × (90 - 20) = HEAT_IDLE_GAIN × HEAT_FRAC_OIL = 0.045
local K_OIL_AMB  = 0.045 / 70  -- 6.43e-4
-- Oil system constants 
local OIL_OPTIMAL_T   = 90     -- °C  reference viscosity temperature
-- Relative viscosity vs 90°C optimum: 20°C -> 6.25x, 160°C -> 0.17x
local LN_VISC_COLD_HOT = math.log(6.25) / (OIL_OPTIMAL_T - 20)

local OIL_PRESSURE_TAU      = 0.3  -- s, response lag — TUNE
local OIL_STARV_TAU_STARVE  = 5.0  -- s, time to fully starve at OilEffPress=0
local OIL_STARV_TAU_RECOVER = 2.0  -- s, recovery time once pressure restored
local OIL_STARV_WARN        = 0.10 -- accumulator fraction that triggers warning

local G_DEG_PER_G = 5.7  -- ° equivalent tilt per G of lateral/longitudinal force

--===============================================================================================--
-- Local Funcs and Vars
--===============================================================================================--
local PI   = math.pi
local abs  = math.abs
local max  = math.max
local min  = math.min
local sqrt = math.sqrt
local exp  = math.exp

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

        -- Get the vehicle speed for the radiator ram-air effect as well as for the engine g-forces
        -- Have to do this here so we don't do it again twice for the g-force calcs. 
        local Ancestor     = Contraption.GetAncestor(self)
        local AncestorEnt  = IsEntityValid(Ancestor) and Ancestor
        local AncestorPhys = AncestorEnt and ENTITY.GetPhysicsObject(AncestorEnt)
        local PhysValid    = AncestorPhys and IsPhysObjValid(AncestorPhys)

        local VehicleSpeed = PhysValid and PHYSOBJ.GetVelocity(AncestorPhys):Length() or 0

        -- Oil calcs
        -- G-force (finite difference of chassis velocity) 
        local G_lat, G_lon = 0, 0
        if PhysValid and DeltaTime ~= 0 then
            local VelNow  = PHYSOBJ.GetVelocity(AncestorPhys) * ACF.InchToMeter
            local PrevVel = SelfTbl.PrevVelocity or VelNow
            local Accel   = (VelNow - PrevVel) / DeltaTime
            SelfTbl.PrevVelocity = VelNow

            local Ang = ENTITY.GetAngles(AncestorEnt)
            G_lat = Accel:Dot(Ang:Right())   / 9.81
            G_lon = Accel:Dot(Ang:Forward()) / 9.81
        end

        -- Oil pressure / sump tilt / starvation 
        local TiltWarn   = SelfTbl.OilSumpTilt.Warn
        local TiltStarve = SelfTbl.OilSumpTilt.Starve

        local Pitch = AncestorEnt and abs(ENTITY.GetAngles(AncestorEnt).p) or 0
        local Roll  = AncestorEnt and abs(ENTITY.GetAngles(AncestorEnt).r) or 0
        local EffPitch = Pitch + abs(G_lon) * G_DEG_PER_G
        local EffRoll  = Roll  + abs(G_lat) * G_DEG_PER_G
        local Theta = min(sqrt(EffPitch * EffPitch + EffRoll * EffRoll), 180)

        local FTilt

        if Theta <= TiltWarn then FTilt = 1.0
        elseif Theta >= TiltStarve then FTilt = 0.0
        else FTilt = 1.0 - (Theta - TiltWarn) / (TiltStarve - TiltWarn) end

        -- OilKPump precomputed once at configure time
        local OilTgtPress = min((SelfTbl.OilKPump or 0) * RPM, SelfTbl.OilPRelief) * FTilt
        local OilEffPress  = SelfTbl.OilPressureBar or OilTgtPress
        OilEffPress = OilEffPress + (OilTgtPress - OilEffPress) * min(DeltaTime / OIL_PRESSURE_TAU, 1)
        SelfTbl.OilPressureBar = OilEffPress

        local OilStarvation = SelfTbl.OilStarvation or 0
        local OilPMinRun = SelfTbl.OilPMinRun
        if OilEffPress < OilPMinRun then
            OilStarvation = min(1, OilStarvation + (1 - OilEffPress / OilPMinRun) * DeltaTime / OIL_STARV_TAU_STARVE)
        else
            OilStarvation = max(0, OilStarvation - DeltaTime / OIL_STARV_TAU_RECOVER)
        end
        SelfTbl.OilStarvation = OilStarvation
        SelfTbl.OilPressureOK = OilStarvation < OIL_STARV_WARN

        -- Soft wear consequence, only at FULL starvation, floored, not a hard kill
        -- if OilStarvation >= 1.0 then
        --     SelfTbl.TorqueDamageMult = max(OIL_DAMAGE_FLOOR, (SelfTbl.TorqueDamageMult or 1) - OIL_SEIZE_WEAR_RATE * DeltaTime)
        -- end

        -- Live viscosity from ACTUAL current oil temperature
        SelfTbl.OilViscosity = exp(-LN_VISC_COLD_HOT * (OT - OIL_OPTIMAL_T))

        -- Coolant/Oil temperature calcs
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

                    TotalHOCool = TotalHOCool + Ent:CalcTemp(CT, TotalHeat, Q, DeltaTime, VehicleSpeed)
                else
                    TotalHOCool = TotalHOCool + Ent:CalcTemp(CT, 0, 0, DeltaTime, VehicleSpeed)
                end
            end
        end

        -- Oil<->coolant heat exchange (bidirectional, scales with RPM)
        local K_OC = 0.001 * (RPM / IdleRPM) * ACF.HeatGenerationScalar
        local ExchangedHeat = K_OC * (OT - CT) * DeltaTime

        -- Total heat generated, distributed to coolant and oil.
        local HeatToCool = ACF.HeatFractionToCoolant * TotalHeat
        local HeatToOil  = (1 - ACF.HeatFractionToCoolant) * TotalHeat + (PowerFriction * 0.001) * DeltaTime

        -- Sump passive cooling + assembly friction heat added to oil
        local HOCool = K_OIL_AMB * (CT - AmbTemp) * DeltaTime * ACF.HeatGenerationScalar -- Passive Heat out 
        local HOOil = K_OIL_AMB * (OT - AmbTemp) * DeltaTime * ACF.HeatGenerationScalar

        -- Total calculation assignments 
        SelfTbl.Temperature.Coolant = max(AmbTemp, CT + HeatToCool - TotalHOCool - HOCool + ExchangedHeat)
        SelfTbl.Temperature.Oil     = max(AmbTemp, OT + HeatToOil - HOOil - ExchangedHeat)

        SelfTbl.WasTimed = false -- Reset our timer just in case 
        return true
    end
end