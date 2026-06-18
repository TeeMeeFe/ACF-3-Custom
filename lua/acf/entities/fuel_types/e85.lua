local FuelTypes = ACF.Classes.FuelTypes

FuelTypes.Register("E85", {
    Name          = "Ethanol 85",
    IgnitionType  = "spark", -- ignition through sparkplugs
    Efficiency    = 0.7,     -- kg/kWh BSFC, much lower density than petrol, so roughly 30% more fuel by mass is needed
    Stoich_AFR    = 9.7,     -- Stoichiometric Air Fuel Ratio
    -- PlugHeatRange = 8,       -- stock NGK heat range
    -- PistonSpeed   = 20,      -- m/s mean piston speed limit
})
