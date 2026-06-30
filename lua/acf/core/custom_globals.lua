do -- Globals
    ACF.SpeedOfSound         = 343     -- In Meters Per Second
    ACF.RoomTemperature      = 293.15  -- In Degrees Kelvin. This indicates the default temperature inside a safezone, if none defined.
    ACF.RadiatorLinkDistance = 96      -- Distance in inches at which linking radiators are possible.
    ACF.ClutchSlipCoef       = 0.003   -- Tune: higher = stronger coupling, more pronounced stall under load
    -- Unit conversion
    ACF.RPMToRads            = 0.10472 -- RPM to Radians
end

do -- Update checker
    hook.Add("ACF_OnLoadAddon", "ACF Custom Update Checker", function()
        ACF.AddRepository("TeeMeeFe", "ACF-3-Custom")

        hook.Remove("ACF_OnLoadAddon", "ACF Custom Update Checker")
    end)
end
