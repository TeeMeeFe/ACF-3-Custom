--local ACF = ACF
local Round = math.Round
local abs   = math.abs

local LowColor  = Color(66, 96, 116)
local HighColor = Color(255, 128, 30)

ENT.OverlayDelay = 1

function ENT:ACF_UpdateOverlayState(State)
    -- Actual state
    if self.ACF.Health == 0 then
        State:AddError("Destroyed")
    elseif self.ACF.Health ~= 0 and self.Amount == 0 then
        State:AddError("No coolant left!")
    elseif self.ACF.Health ~= 0 and self.Active then
        State:AddSuccess("Active")
    elseif self.ACF.Health ~= 0 and not self.Active and not IsValid(self.Engine) then
        State:AddWarning("Idle, and not linked to an engine!")
    else
        State:AddWarning("Idle")
    end
    -- Warnings
    if self.IsLeaking and self.LeakingRate > 0 then
        State:AddWarning("WARNING: Leaking!")
    end
    if self.IsFrozen then
        State:AddWarning("WARNING: Frozen!")
    end

    local CMix = self.Mixture
    local MisteryText
    if CMix <= 0 then
        MisteryText = "Pure 100% Water"
    elseif CMix < 1 then
        MisteryText = ("Water: %s%s, Glycol: %s%s"):format(Round(abs(1 - CMix) * 100), "%", Round(CMix * 100), "%")
    else
        MisteryText = "Pure 100% Glycol"
    end

    State:AddKeyValue("Type", self.Name)
    State:AddKeyValue("Scale", self.ACF.Scale)
    State:AddKeyValue("Fluid Type", MisteryText)

    local CoolantAmount   = Round(self.Amount, 2)
    local CoolantCapacity = Round(self.Capacity, 2)

    State:AddProgressBar("Coolant level", CoolantAmount, CoolantCapacity, " L")

    local Pressure = self.Pressure
    local MaxPress = self.MaxPressure

    State:AddProgressBar("Pressure", Pressure, MaxPress, " Bar", 0, LowColor, HighColor)

    local Temperature = self.CoreTemperature or self.AmbTemp
    local FreezingPoint = self.FreezePoint
    local BoilingPoint = self.BoilingPoint

    State:AddCustomProgressBar("Temperature", Temperature, FreezingPoint, BoilingPoint, " °C", 0, LowColor, HighColor)
end