ACF.Classes.DefineClass("ACF.FuelTypes.Methanol", "ACF.FuelTypes.FuelType", function()
    CLASS.Name         = "Methanol Fuel"
    CLASS.ShortName    = "Methanol"
    CLASS.Density      = 0.792    -- kg/L, slightly denser than e85 and petrol
    CLASS.IgnitionType = "spark"  -- Ignition through sparkplugs
    CLASS.Efficiency   = 0.904    -- kg/kWh BSFC, about 3 times higher than petrol, but energy density is half as much
    CLASS.Stoich_AFR   = 6.4      -- Stoichiometric Air Fuel Ratio, runs much richer than diesel or e85
end)