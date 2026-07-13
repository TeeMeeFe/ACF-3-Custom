local ENTITY = FindMetaTable("Entity")
local max    = math.max

-- Coolant radiator normalisation constant.
-- Calibrated: 1.0 L 4-cyl NA at idle / 88 °C in thermal equilibrium
-- with ACF.HeatFractionToCoolant = 0.70 applied to total heat.
-- K_COOL = ACF.HeatGenerationAtIdle × ACF.HeatFractionToCoolant /
--          (Q_idle × rho_cool × Cp_cool × (88 - 20))
-- = 0.105 / (0.18898 × 1.075 × 3600 × 68)  ≈  2.368e-6 / 0.70
local K_COOL = 7.4358e-6 / ACF.HeatFractionToCoolant
-- Thermostat constants
local COOL_THERM_OPEN   = 85   -- Temperature at which the thermostat will begin to open
local COOL_THERM_THRESH = 2    -- Multiply this by 2 to get the temperature range at which the thermostat remains partly open 
local COOL_CLOSED_FRAC  = 0.10 -- Fraction of heat taken when the thermostat is fully closed

function ENT:CalcTemp(InputTemp, InputHeat, InputFlow, DeltaTime)
    local SelfTbl = ENTITY.GetTable(self)
    if SelfTbl.Disabled then return end

    local Amount       = SelfTbl.Amount       -- In Liters
    local Capacity     = SelfTbl.Capacity
    local Density      = SelfTbl.Density      -- In Grams per Cubic Centimeter or Kilograms per Liter
    local SpecificHeat = SelfTbl.SpecificHeat -- In Kilojoules per Kilogram

    local AmbTemp      = SelfTbl.AmbTemp
    local Temperature  = SelfTbl.Temperature

    local Percentage   = max(Amount / Capacity, 0)

    local ThermFrac

    -- Thermostat: smooth 4 °C blend around COOL_THERM_OPEN
    if Temperature < COOL_THERM_OPEN - COOL_THERM_THRESH then
        ThermFrac = COOL_CLOSED_FRAC
    elseif Temperature > COOL_THERM_OPEN + COOL_THERM_THRESH then
        ThermFrac = 1.0
    else
        ThermFrac = COOL_CLOSED_FRAC + (1.0 - COOL_CLOSED_FRAC) * ((Temperature - (COOL_THERM_OPEN - COOL_THERM_THRESH)) * 0.25)
    end

    local OutputHeat = K_COOL * Amount * (InputHeat * InputFlow) * Density * SpecificHeat * (Temperature - AmbTemp) * Percentage * ThermFrac * DeltaTime
    SelfTbl.Temperature = max(AmbTemp, InputTemp - OutputHeat)

    PrintTable({AmbTemp, SelfTbl.Temperature, InputTemp, InputHeat, InputFlow, OutputHeat})
    SelfTbl.UpdateOutputs(self, SelfTbl)

    return OutputHeat
end

-- Wiremod output updating
function ENT:UpdateOutputs(SelfTbl)
    SelfTbl = SelfTbl or ENTITY.GetTable(self)
    local Temperature = SelfTbl.Temperature

    if SelfTbl.LastTemperature ~= Temperature then
        SelfTbl.LastTemperature = Temperature
        WireLib.TriggerOutput(self, "Temperature", Temperature)
    end
end
