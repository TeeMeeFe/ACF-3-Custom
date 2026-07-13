--local ACF = ACF
local Round = math.Round
local abs = math.abs

function ENT:ACF_UpdateOverlayState(State)
    if self.Active then
        State:AddSuccess("Active")
    else
        State:AddWarning("Idle")
    end

    if self.IsLeaking and self.Leaking > 0 then
        State:AddWarning("WARNING: Leaking!")
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
    if not self.IsBlock then
        State:AddKeyValue("Scale", self.ACF.Scale)
    end
    State:AddKeyValue("Fluid Type", MisteryText)

    local CoolantAmount   = Round(self.Amount, 2)
    local CoolantCapacity = Round(self.Capacity, 2)

    State:AddProgressBar("Coolant level", CoolantAmount, CoolantCapacity, " L")
end