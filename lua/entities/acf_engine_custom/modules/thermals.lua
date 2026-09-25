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
local COOL_WARN     = 105 -- Past this, the engine will begin getting little damage over time.
local COOL_MAX      = 120 -- Same as above, but lots of damage over time.
-- Oil system constants 
local OIL_OPTIMAL_T = 90  -- °C  reference viscosity temperature
local OIL_WARN      = 130 -- At this point the oil too hot, and the engine begins to lose power.
local OIL_MAX       = 160 -- At this point the oil is too liquid and does not lubricate properly. Increased engine damage.

-- Oil passive cooling
-- K_OIL_AMB × (90 - 20) = HEAT_IDLE_GAIN × HEAT_FRAC_OIL = 0.045
local K_OIL_AMB     = 0.045 / 70  -- 6.43e-4
-- Relative viscosity vs 90°C optimum: 20°C -> 6.25x, 160°C -> 0.17x
local LN_VISC_COLD_HOT = math.log(6.25) / (OIL_OPTIMAL_T - 20)

local OIL_PRESSURE_TAU      = 1.3  -- s, response lag
local OIL_STARV_TAU_STARVE  = 5.0  -- s, time to fully starve at OilEffPress=0
local OIL_STARV_TAU_RECOVER = 2.0  -- s, recovery time once pressure restored
local OIL_STARV_WARN        = 0.10 -- accumulator fraction that triggers warning

-- Two-tier drain rate per fluid, same shape as the radiator's
-- relief-vs-boil distinction: WARN = slow structural stress (head
-- gasket / thinning oil film), MAX = fast (active warping/seizure risk).
local COOL_WARN_DRAIN = 0.005   -- HP/s per °C over COOL_WARN 
local COOL_MAX_DRAIN  = 0.015   -- HP/s per °C over COOL_MAX 
local OIL_WARN_DRAIN  = 0.003   -- HP/s per °C over OIL_WARN
local OIL_MAX_DRAIN   = 0.025   -- HP/s per °C over OIL_MAX 
-- Oil damage constants 
local OIL_SEIZE_WEAR_RATE = 0.2 -- TorqueDamageMult lost per second at full starvation
local OIL_DAMAGE_FLOOR    = 0.5

-- Water pump: Q (L/s) = K_PUMP_FLOW × RPM
-- 0.667 L/s at 3 000 RPM (≈ 40 L/min automotive spec)
local K_PUMP_FLOW     = 0.667 / 3000

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
    local function CalcWear(Ent, SelfTbl, DeltaTime)
        SelfTbl = SelfTbl or ENTITY.GetTable(Ent)

        local FinalCT = SelfTbl.Temperature.Coolant
        local FinalOT = SelfTbl.Temperature.Oil

        local ThermalDrain = 0

        if FinalCT > COOL_MAX then
            ThermalDrain = ThermalDrain + (FinalCT - COOL_MAX) * COOL_MAX_DRAIN
        elseif FinalCT > COOL_WARN then
            ThermalDrain = ThermalDrain + (FinalCT - COOL_WARN) * COOL_WARN_DRAIN
        end

        if FinalOT > OIL_MAX then
            ThermalDrain = ThermalDrain + (FinalOT - OIL_MAX) * OIL_MAX_DRAIN
        elseif FinalOT > OIL_WARN then
            ThermalDrain = ThermalDrain + (FinalOT - OIL_WARN) * OIL_WARN_DRAIN
        end

        -- Soft wear consequence, only at FULL starvation. Adds on top of ThermalDrain variable 
        if SelfTbl.OilStarvation >= 1.0 and SelfTbl.Active then
            ThermalDrain = ThermalDrain + max(OIL_DAMAGE_FLOOR, abs(ThermalDrain - OIL_SEIZE_WEAR_RATE) * DeltaTime)
        end

        if ThermalDrain > 0 then
            SelfTbl.ACF.Health = max(0, SelfTbl.ACF.Health - ThermalDrain * DeltaTime)

            -- Update torque based on our damage 
            Ent:UpdateTorqueDamageMult()

            if SelfTbl.ACF.Health == 0 and not SelfTbl.IsDestroyed then
                SelfTbl.IsDestroyed = true
                Ent:Disable()
            end
        end
        return true
    end

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
        local EffPitch = Pitch + abs(G_lon) * ACF.GeeDegreesPerGees
        local EffRoll  = Roll  + abs(G_lat) * ACF.GeeDegreesPerGees
        local Theta = min(sqrt(EffPitch * EffPitch + EffRoll * EffRoll), 180)

        local FTilt

        if Theta <= TiltWarn then FTilt = 1.0
        elseif Theta >= TiltStarve then FTilt = 0.0
        else FTilt = 1.0 - (Theta - TiltWarn) / (TiltStarve - TiltWarn) end

        -- OilKPump precomputed once at configure time
        local OilTgtPress = min((SelfTbl.OilKPump or 0) * RPM, SelfTbl.OilPRelief) * FTilt
        local OilEffPress  = SelfTbl.OilPressure or OilTgtPress
        OilEffPress = OilEffPress + (OilTgtPress - OilEffPress) * min(DeltaTime / OIL_PRESSURE_TAU, 1)
        SelfTbl.OilPressure = OilEffPress

        local OilStarvation  = SelfTbl.Active and SelfTbl.OilStarvation or 0
        local OilPressMinRun = SelfTbl.OilPressMinRun
        if OilEffPress < OilPressMinRun then
            OilStarvation = min(1, OilStarvation + (1 - OilEffPress / OilPressMinRun) * DeltaTime / OIL_STARV_TAU_STARVE)
        else
            OilStarvation = max(0, OilStarvation - DeltaTime / OIL_STARV_TAU_RECOVER)
        end
        SelfTbl.OilStarvation = OilStarvation
        SelfTbl.OilPressureOK = SelfTbl.Active and OilStarvation < OIL_STARV_WARN or true

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

        CalcWear(self, SelfTbl, DeltaTime)
    end
end