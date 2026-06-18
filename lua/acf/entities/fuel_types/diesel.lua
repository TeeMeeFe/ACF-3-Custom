local FuelTypes = ACF.Classes.FuelTypes

FuelTypes.Register("Diesel", {
    Name         = "Diesel",
    IgnitionType = "glow", -- compression ignition; glow plugs for cold start
    Efficiency   = 0.243,  -- kg/kWh (up to 0.274 at best efficiency)
    Stoich_AFR   = 14.5,   -- Stoichiometric Air Fuel Ratio
    --RequiresGlowPlugs = true,
    -- PistonSpeed  = 13,     -- m/s (diesel long-stroke limit)
})
