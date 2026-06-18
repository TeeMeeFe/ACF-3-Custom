local FuelTypes = ACF.Classes.FuelTypes

FuelTypes.Register("Petrol", {
    Name          = "Petrol",
    IgnitionType  = "spark", -- ignition through sparkplugs
    Efficiency    = 0.304,   -- kg/kWh BSFC
    Stoich_AFR    = 14.7,    -- Stoichiometric Air Fuel Ratio
    --P lugHeatRange = 6,       -- stock NGK heat range
    -- PistonSpeed   = 20,      -- m/s mean piston speed limit
})
