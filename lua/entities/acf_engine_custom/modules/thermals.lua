local ACF = ACF
local Clock         = ACF.Utilities.Clock

local ENTITY        = FindMetaTable("Entity")
local IsEntityValid	= ACF.Optimizations.IsEntityValid
--===============================================================================================--
--  Constants
--===============================================================================================--
-- Heat split
local HEAT_FRAC_COOL  = 0.70
local HEAT_FRAC_OIL   = 0.30
local HEAT_IDLE_GAIN  = 0.15    -- baseline heat/s at idle

-- Coolant thresholds (°C)
local COOL_THERM_OPEN = 85
local COOL_OPTIMAL    = 88
local COOL_WARN       = 105
local COOL_MAX        = 120

-- Oil thresholds (°C)
local OIL_OPTIMAL     = 90
local OIL_WARN        = 130
local OIL_MAX         = 160

-- Water pump: Q (L/s) = K_PUMP_FLOW × RPM
-- 0.667 L/s at 3 000 RPM (≈ 40 L/min automotive spec)
local K_PUMP_FLOW     = 0.667 / 3000

-- Coolant radiator normalisation constant.
-- Calibrated: 1.0 L 4-cyl NA at idle / 88 °C in thermal equilibrium
-- with HEAT_FRAC_COOL = 0.70 applied to total heat.
-- K_COOL = HEAT_IDLE_GAIN × HEAT_FRAC_COOL /
--          (Q_idle × rho_cool × Cp_cool × (88 - 20))
-- = 0.105 / (0.18898 × 1.075 × 3600 × 68)  ≈  2.368e-6 / 0.70
local K_COOL          = 7.4358e-6 / HEAT_FRAC_COOL

-- Thermostat
local COOL_CLOSED_FRAC = 0.10

-- Coolant especific constants, these should be coming from the acf_radiator entity instead
local CP_COOLANT       = 3600    -- J/(kg·K)  50/50 water-glycol
local RHO_COOLANT      = 1.075   -- kg/L

-- Oil passive cooling
-- K_OIL_AMB × (90 - 20) = HEAT_IDLE_GAIN × HEAT_FRAC_OIL = 0.045
local K_OIL_AMB       = 0.045 / 70    -- 6.43e-4

-- Oil↔coolant exchange (scales with RPM)
local K_OC_BASE       = 0.001   -- game-units/(s·K) when active and at idle

-- Coolant level
local COOL_TOTAL_VOL  = 6.5     -- L
local COOL_LEVEL_WARN = 0.50
local COOL_LEVEL_MIN  = 0.15
local COOL_LEAK_DECAY = 0.05    -- /s exponential decay

-- Oil pressure
local OIL_P_MIN_RUN    = 1.0
local OIL_P_RELIEF     = 5.0
local OIL_TILT_WARN    = 50     -- ° default; overridden by Geo layout
local OIL_TILT_STARVE  = 90
local OIL_TAU_STARVE   = 5.0
local OIL_TAU_RECOVER  = 2.0
local OIL_STARV_WARN   = 0.10
local OIL_STARV_SEIZE  = 1.0

--===============================================================================================--
-- Local Funcs and Vars
--===============================================================================================--
local PI = math.pi
local max = math.max

local function GetNextRadiator(Engine)
    local Radiators = Engine.Radiators
    if not next(Radiators) then return end

    local Select = next(Radiators, Engine.Radiator) or next(Radiators)
    local Start = Select

    repeat
        if Select:CanConsume() then return Select end

        Select = next(Radiators, Select) or next(Radiators)
    until Select == Start

    return (Select:CanConsume()) and Select or nil
end

do -- State Handling
    function ENT:CalcTemp(SelfTbl)
        SelfTbl = SelfTbl or ENTITY.GetTable(self)

        local ClockTime = Clock.CurTime
        local DeltaTime = ClockTime - SelfTbl.LastThink
        local Radiator  = GetNextRadiator(SelfTbl)
        local Torque    = SelfTbl.Torque
        local RPM       = SelfTbl.FlyRPM
        local IdleRPM   = SelfTbl.IdleRPM
        local AmbTemp   = SelfTbl.AmbientTemp - 273.15 -- In degrees Celcius
        local HeatCoeff = SelfTbl.HeatCoefficient or 0.012

        -- Assembly friction adds heat to the oil circuit
        local AsmFric   = 7 --SelfTbl.AssemblyFriction_Nm or 0
        local Omega     = (RPM * 2 * PI) * 0.0166667
        local P_fric_kW = (AsmFric * Omega) * 0.001

        local TotalHeat = (HEAT_IDLE_GAIN + HeatCoeff * Torque) * DeltaTime

        if IsEntityValid(Radiator) then
            SelfTbl.Radiator = Radiator
        end

        -- Coolant Calcs
        local CT = SelfTbl.Temperature.Coolant

        -- Water pump flow — cavitates if coolant level is critically low
        local Q = K_PUMP_FLOW * RPM
        if (SelfTbl.CoolantLevel or 1) < COOL_LEVEL_MIN then Q = 0 end
        SelfTbl.WaterPumpFlow = Q

        local ThermFrac
        -- Thermostat: smooth 4 °C blend around COOL_THERM_OPEN
        if CT < COOL_THERM_OPEN - 2 then
            ThermFrac = COOL_CLOSED_FRAC
        elseif CT > COOL_THERM_OPEN + 2 then
            ThermFrac = 1.0
        else
            ThermFrac = COOL_CLOSED_FRAC
                + (1.0 - COOL_CLOSED_FRAC)
                * ((CT - (COOL_THERM_OPEN - 2)) * 0.25)
        end
        -- RadiatorCapacity (acf_radiator, default 1.0 if none linked) multiplies heat rejection:
        -- < 1.0 = undersized/damaged core,
        -- > 1.0 = performance/heavy-duty radiator with more rejection margin.
        local RadCap = 1 --SelfTbl.RadiatorCapacity or 1.0

        -- Heat Out Coolant
        local HOCool = K_COOL * RadCap * Q * RHO_COOLANT * CP_COOLANT * (CT - AmbTemp) * ThermFrac * DeltaTime
        HOCool = HOCool * max(SelfTbl.CoolantLevel or 1, 0)

        -- Oil↔coolant heat exchange (bidirectional, scales with RPM)
        local K_OC = K_OC_BASE * (RPM / IdleRPM)
        local ExchangedHeat = K_OC * (SelfTbl.Temperature.Oil - CT) * DeltaTime

        local HeatToCool = HEAT_FRAC_COOL * TotalHeat

        -- Oil Calcs
        local OT = SelfTbl.Temperature.Oil

        -- Sump passive cooling + assembly friction heat added to oil
        -- Heat Out Oil
        local HOOil     = K_OIL_AMB * (OT - AmbTemp) * DeltaTime
        local HeatToOil = HEAT_FRAC_OIL * TotalHeat + P_fric_kW * 0.001 * DeltaTime

        -- Total calculation assignments 
        SelfTbl.Temperature.Coolant = max(AmbTemp, CT + HeatToCool - HOCool + ExchangedHeat)
        SelfTbl.Temperature.Oil     = max(AmbTemp, OT + HeatToOil - HOOil - ExchangedHeat)

        --SelfTbl.LastThink = ClockTime
        PrintTable({RPM, TotalHeat, CT, OT, Q, HeatToCool, HeatToOil, ExchangedHeat})

        return true
    end
end