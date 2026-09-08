local ENTITY = FindMetaTable("Entity")
local max    = math.max
local exp    = math.exp

-- Coolant radiator normalisation constant.
-- Calibrated: 1.0 L 4-cyl NA at idle / 88 °C in thermal equilibrium
-- with ACF.HeatFractionToCoolant = 0.70 applied to total heat.
-- K_COOL = ACF.HeatGenerationAtIdle × ACF.HeatFractionToCoolant /
--          (Q_idle × rho_cool × Cp_cool × (88 - 20))
-- = 0.105 / (0.18898 × 1.075 × 3600 × 68)  ≈  2.368e-6 / 0.70
local K_COOL = 7.4358e-6 / ACF.HeatFractionToCoolant

-- Ram air: SATURATING approach to full effect vs vehicle speed
local RAM_AIR_REF_KPH = 100   -- kph at ~63% of max ram-air effect — TUNE

-- Fan: flat contribution, covering exactly the case ram air can't
-- (stationary/idling). Real fans don't match highway ram air — kept
-- deliberately below 1 for that reason.
local FAN_EFFECTIVENESS = 0.45  -- TUNE

-- Auto-thermostatic fan engagement 
local FAN_AUTO_ON_TEMP  = 95   -- °C — TUNE
local FAN_AUTO_OFF_TEMP = 88   -- °C — hysteresis band, TUNE

-- Coolant flow saturation: heat-transfer effectiveness rises with flow
-- but SATURATES — past a point coolant moves through the core too fast
-- to fully equilibrate with the air side, so more flow stops helping.
local FLOW_SATURATION_REF = 0.5 -- L/s at ~63% of max transfer — TUNE

-- Core thermal mass: the radiator's own metal core/tank has real heat
-- capacity, buffering heat between "arrives from coolant" and "actually
-- leaves to the air". Without this the whole system responded
-- instantaneously, which is unrealistically fast.
local CORE_HEAT_CAPACITY = 4.0   -- bigger = more thermal lag — TUNE
local CORE_CONTACT_COEF  = 0.08  -- coolant<->core equilibration rate — TUNE

function ENT:SetActive(Active)
    self.Active = Active
    self:UpdateOverlay()
    self:UpdateOutputs()
end

function ENT:CalcTemp(InputTemp, InputHeat, InputFlow, DeltaTime, Velocity)
    local SelfTbl = ENTITY.GetTable(self)
    if SelfTbl.Disabled then return end

    local Amount       = SelfTbl.Amount       -- In Liters
    local Capacity     = SelfTbl.Capacity
    local Density      = SelfTbl.Density      -- In Grams per Cubic Centimeter or Kilograms per Liter
    local SpecificHeat = SelfTbl.SpecificHeat -- In Kilojoules per Kilogram

    local CoreEff      = SelfTbl.CoreEff or 1.0

    local AmbTemp      = SelfTbl.AmbTemp
    local Temperature  = SelfTbl.Temperature

    -- Separate core thermal-mass state, distinct from coolant.
    local CoreTemp     = SelfTbl.CoreTemp or AmbTemp
    local Percentage   = max(Amount / Capacity, 0)

    local ThermFrac

    -- Thermostat variables/constants
    local ThermOpenTemp   = SelfTbl.ThermOpenAtTemp -- Temperature at which the thermostat will begin to open
    local ThermThreshold  = 2    -- Multiply this by 2 to get the temperature range at which the thermostat remains partly open 
    local ThermFracToCool = 0.10 -- Fraction of heat taken when the thermostat is fully closed

    if SelfTbl.ThermEnabled then
        -- Thermostat: smooth ThermThreshold*2 °C blend around ThermOpenTemp
        if Temperature < ThermOpenTemp - ThermThreshold then
            ThermFrac = ThermFracToCool
        elseif Temperature > ThermOpenTemp + ThermThreshold then
            ThermFrac = 1.0
        else
            local Blend = (Temperature - (ThermOpenTemp - ThermThreshold)) / (2 * ThermThreshold)
            ThermFrac = ThermFracToCool + (1.0 - ThermFracToCool) * Blend
        end
        -- Auto-thermostatic fan
        if CoreTemp >= FAN_AUTO_ON_TEMP then
            SelfTbl.FanActive = true
        elseif CoreTemp <= FAN_AUTO_OFF_TEMP then
            SelfTbl.FanActive = false
        end
    else
        ThermFrac = ThermFracToCool
        SelfTbl.FanActive = false
    end

    -- Airflow: ram air (saturating vs speed) + fan
    Velocity = Velocity or 0
    local SpeedKPH     = Velocity * ACF.HUtoKPH
    local RamAirFactor = 1 - exp(-SpeedKPH / RAM_AIR_REF_KPH)
    local FanFactor    = SelfTbl.FanActive and FAN_EFFECTIVENESS or 0
    local AirFactor    = max(RamAirFactor, FanFactor)

    -- Coolant flow saturation 
    local FlowFactor = 1 - exp(-InputFlow / FLOW_SATURATION_REF)

    -- Stage 1: coolant -> core
    local CoolantToCore = CORE_CONTACT_COEF * FlowFactor * (Temperature - CoreTemp) * DeltaTime

    -- Stage 2: core -> air (rate-limited by airflow + core design)
    local IdleHO = K_COOL * DeltaTime * Capacity * 100 * ACF.HeatGenerationScalar
    local CoreToAir = max(IdleHO, K_COOL * CoreEff * Amount * (InputHeat * FlowFactor) * Density * SpecificHeat *
        (CoreTemp - AmbTemp) * Percentage * ThermFrac * AirFactor * DeltaTime)

    CoreTemp = CoreTemp + (CoolantToCore - CoreToAir) / CORE_HEAT_CAPACITY
    SelfTbl.CoreTemp = max(AmbTemp, CoreTemp)

    SelfTbl.Temperature = max(AmbTemp, InputTemp - CoolantToCore)
    SelfTbl.UpdateOutputs(self, SelfTbl)

    return CoolantToCore
end

-- Wiremod output updating
function ENT:UpdateOutputs(SelfTbl)
    SelfTbl = SelfTbl or ENTITY.GetTable(self)

    local CoreTemp = SelfTbl.CoreTemp
    local Temperature = SelfTbl.Temperature
    local Active = SelfTbl.Active
    local FanActive = SelfTbl.FanActive
    local Thermostat = SelfTbl.ThermEnabled

    if SelfTbl.LastActive ~= Active then
        SelfTbl.LastActive = Active
        WireLib.TriggerOutput(self, "Activated", Active)
    end
    if SelfTbl.ThermEnabled ~= Thermostat then
        SelfTbl.ThermEnabled = Thermostat
        WireLib.TriggerOutput(self, "Thermostat Active", Thermostat)
    end
    if SelfTbl.LastFanActive ~= FanActive then
        SelfTbl.LastFanActive = FanActive
        WireLib.TriggerOutput(self, "Fan Active", FanActive and 1 or 0)
    end
    if SelfTbl.LastCoreTemp ~= CoreTemp then
        SelfTbl.LastCoreTemp = CoreTemp
        WireLib.TriggerOutput(self, "Core Temperature", CoreTemp)
    end
    if SelfTbl.LastTemperature ~= Temperature then
        SelfTbl.LastTemperature = Temperature
        WireLib.TriggerOutput(self, "Temperature", Temperature)
    end

end
