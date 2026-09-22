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
local FAN_EFFECTIVENESS = 0.05  -- TUNE

-- Auto-thermostatic fan engagement 
local FAN_AUTO_ON_TEMP  = 95   -- °C — TUNE
local FAN_AUTO_OFF_TEMP = 88   -- °C — hysteresis band, TUNE

-- Coolant flow saturation: heat-transfer effectiveness rises with flow
-- but SATURATES — past a point coolant moves through the core too fast
-- to fully equilibrate with the air side, so more flow stops helping.
local FLOW_SATURATION_REF = 0.5 -- L/s at ~63% of max transfer — TUNE

-- Coolant lost venting at the relief cap (normal operation — real
-- systems do lose a little through the overflow when running hot).
local RELIEF_LEAK_COEF = 0.002  -- L per (bar-overpressure × second) — TUNE

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
    local Temperature  = SelfTbl.InputTemperature

    -- Separate core thermal-mass state, distinct from coolant.
    local CoreTemp     = SelfTbl.CoreTemperature or AmbTemp
    local Percentage   = max(Amount / Capacity, 0)

    local FreezePoint  = SelfTbl.FreezePoint
    local WasFrozen    = SelfTbl.IsFrozen

    local FREEZE_HYSTERESIS = 2 -- °C margin before re-freezing/thawing to prevent chatter

    if WasFrozen and CoreTemp > FreezePoint + FREEZE_HYSTERESIS then
        SelfTbl.IsFrozen = false
    elseif not WasFrozen and CoreTemp < FreezePoint - FREEZE_HYSTERESIS then
        SelfTbl.IsFrozen = true
    end

    -- Frozen fluid can't circulate at all regardless of pump demand 
    if SelfTbl.IsFrozen then
        InputFlow = InputFlow * ACF.HeatFrozenConduction
    end

    local ThermFrac

    -- Thermostat variables/constants
    local ThermOpenTemp   = SelfTbl.ThermOpenAtTemp -- Temperature at which the thermostat will begin to open
    local ThermThreshold  = 2    -- Multiply this by 2 to get the temperature range at which the thermostat remains partly open 
    local ThermFracToCool = 0.10 -- Fraction of heat taken when the thermostat is fully closed

    if SelfTbl.ThermEnabled then
        -- Thermostat: smooth ThermThreshold*2 °C blend around ThermOpenTemp
        if CoreTemp < ThermOpenTemp - ThermThreshold then
            ThermFrac = ThermFracToCool
        elseif CoreTemp > ThermOpenTemp + ThermThreshold then
            ThermFrac = 1.0
        else
            local Blend = (CoreTemp - (ThermOpenTemp - ThermThreshold)) / (2 * ThermThreshold)
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
    local CoolantToCore = ACF.RadCoreContactCoeff * FlowFactor * (Temperature - CoreTemp) * DeltaTime * ACF.HeatGenerationScalar

    -- Stage 2: core -> air (rate-limited by airflow + core design)
    local IdleHO = K_COOL * DeltaTime * Capacity * 100 * ACF.HeatGenerationScalar
    local CoreToAir = max(IdleHO, K_COOL * CoreEff * Amount * (InputHeat * FlowFactor * ACF.HeatGenerationScalar) * Density * SpecificHeat *
        (CoreTemp - AmbTemp) * Percentage * ThermFrac * AirFactor * DeltaTime)

    -- Frozen conduction penalty applies regardless of pressure state.
    local ConductionMult = SelfTbl.IsFrozen and ACF.HeatFrozenConduction or 1.0
    CoreToAir = CoreToAir * ConductionMult

    CoreTemp = CoreTemp + (CoolantToCore - CoreToAir) / ACF.RadCoreHeatCapacity
    SelfTbl.CoreTemperature = max(AmbTemp, CoreTemp)

    -- Pressure / relief valve / boil-over
    local BoilingPoint      = SelfTbl.BoilingPoint
    local MaxPressure       = SelfTbl.MaxPressure
    local UnpressurizedTemp = SelfTbl.UnpressTemp
    local PressureTempCoeff = MaxPressure / (BoilingPoint - UnpressurizedTemp)

    local Pressure = SelfTbl.IsFrozen and 0 or max(0, (Temperature - UnpressurizedTemp) * PressureTempCoeff) * (Amount / Capacity)
    local AmountLost = 0

    if Pressure > MaxPressure then
        -- Relief valve venting, aka. normal, bounded coolant loss.
        local Overpressure = Pressure - MaxPressure
        AmountLost = AmountLost + Overpressure * RELIEF_LEAK_COEF * DeltaTime
        Pressure = MaxPressure
    end

    if Temperature > BoilingPoint then
        -- Genuine boil-over. At this stage pressure is already pinned at cap and can no longer keep suppressing it.
        -- Much faster coolant loss AND real structural damage (steam damage to hoses/seals)
        local OverBoil = Temperature - BoilingPoint
        AmountLost = AmountLost + OverBoil * ACF.HeatBoilLeakCoeff * DeltaTime

        if SelfTbl.ACF then
            SelfTbl.ACF.Health = max(0, SelfTbl.ACF.Health - OverBoil * ACF.HeatBoilDamageRate * DeltaTime)
        end
    end

    SelfTbl.Pressure = Amount ~= 0 and Pressure or 0
    -- Do the actual leak 
    if AmountLost > 0 then
        SelfTbl.Amount      = max(0, Amount - AmountLost)
        SelfTbl.LeakingRate = AmountLost
        SelfTbl.IsLeaking   = true
    -- Stopped leaking 
    elseif AmountLost == 0 and SelfTbl.IsLeaking then
        SelfTbl.LeakingRate = 0
        SelfTbl.IsLeaking   = false
    end

    SelfTbl.InputTemperature = max(AmbTemp, InputTemp - CoolantToCore)
    SelfTbl.UpdateOverlay(self)
    SelfTbl.UpdateOutputs(self, SelfTbl)

    return CoolantToCore
end

-- Wiremod output updating
function ENT:UpdateOutputs(SelfTbl)
    SelfTbl = SelfTbl or ENTITY.GetTable(self)

    local CoreTemp    = SelfTbl.CoreTemperature
    local Active      = SelfTbl.Active
    local FanActive   = SelfTbl.FanActive
    local Thermostat  = SelfTbl.ThermEnabled
    local Pressure    = SelfTbl.Pressure

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
        WireLib.TriggerOutput(self, "Temperature", CoreTemp)
    end
    if SelfTbl.LastPressure ~= Pressure then
        SelfTbl.LastPressure = Pressure
        WireLib.TriggerOutput(self, "Pressure", Pressure)
    end
end
