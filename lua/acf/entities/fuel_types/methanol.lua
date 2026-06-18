local FuelTypes = ACF.Classes.FuelTypes

FuelTypes.Register("Methanol", {
    Name          = "Methanol",
    IgnitionType  = "spark", -- ignition through sparkplugs
    Efficiency    = 0.45,    -- kg/kWh BSFC, way less than diesel so requires more units of fuel 
    Stoich_AFR    = 6.4,     -- Stoichiometric Air Fuel Ratio, runs much richer than diesel or e85
    -- PlugHeatRange = 6,       -- stock NGK heat range
    -- PistonSpeed   = 20,      -- m/s mean piston speed limit
})
