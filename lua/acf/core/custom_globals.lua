local Sounds = ACF.Utilities.Sounds

do -- Globals
    ACF.SpeedOfSound          = 343    -- In Meters Per Second.
    ACF.AmbientTemperature    = 288.15 -- Override the previous one
    ACF.RoomTemperature       = 293.15 -- In Degrees Kelvin. This indicates the default temperature inside a safezone, if none defined.
    ACF.RadiatorLinkDistance  = 96     -- Distance in units at which linking radiators are possible.
    ACF.GeeDegreesPerGees     = 5.7    -- ° equivalent tilt per G of lateral/longitudinal force
    -- Heat split as fraction
    ACF.HeatFractionToCoolant = 0.70   -- Ratio of the heat generated that goes to coolant, rest goes to oil.
    -- Heat Generation scalars
    ACF.HeatFrozenConduction  = 0.015   -- Frozen fluid still conducts, just much slower.
    ACF.HeatGenerationAtIdle  = 0.15   -- Ratio as baseline heat/s when the engine is active and idling.
    ACF.HeatGenerationScalar  = 20     -- Scalar (aka multiplier) of heat generated over time. Higher is faster.
    -- Radiator constants 
    ACF.RadCoreHeatCapacity   = 4      -- bigger = more thermal lag.
    ACF.RadCoreContactCoeff   = 0.04   -- coolant<->core equilibration rate. Higher = thighter coupling of coolant-core temperatures. 
    ACF.RadUnpressTemperature = 70     -- Threshold fluid temperature at which any radiator can exist without any pressure buildup within them.
    -- Heat Damage scalars 
    ACF.HeatBoilLeakCoeff     = 0.05   -- Loss of L/s per °C over the fluid's Boiling Point.
    ACF.HeatBoilDamageRate    = 0.004  -- Loss of Health/s per °C over the fluid's Boiling Point.
    -- Unit conversion
    ACF.RPMToRads             = 0.10472 -- RPM to Radians.
    ACF.HUtoKPH               = 0.09144 -- Source units/s -> km/h.
    -- Miscelaneous
    ACF.FrictionalRPMExponent = 0.6     -- Reference exponent of total rotating assembly friction that increases with RPM. 
    ACF.RepairSoundPath       = "acf_custom/tools/tool_repair.wav" -- Reference sound when something gets fully repaired.
end

-- Handy little function since this can be used in many places at the same time
function ACF.DoRepairSound(Ent)
    Sounds.SendSound(Ent, ACF.RepairSoundPath, 100, 100, 1)
end

do -- Update checker
    hook.Add("ACF_OnLoadAddon", "ACF Custom Update Checker", function()
        ACF.AddRepository("TeeMeeFe", "ACF-3-Custom")

        hook.Remove("ACF_OnLoadAddon", "ACF Custom Update Checker")
    end)
end
