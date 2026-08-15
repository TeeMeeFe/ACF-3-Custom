local ACF = ACF
local Classes = ACF.Classes

-- ============================================================
--  This file is the base class from which the rest of the engines will
--  inherit from. It is required by other modules which will 
--  eventually be created. All downstream modules read from a data bus
--  without knowing which layout produced it.
--
--  ── Class hierarchy ───────────────────────────────────────────
--
--     BlockType           (abstract base — defines interface contract)
--     ├── PistonBlock     (all reciprocating engines, shared physics)
--     │    ├── InlineEngine        layout="inline"
--     │    ├── BoxerEngine         layout="boxer"
--     │    ├── V-TypeEngine        layout="v"         BankAngle required
--     │    ├── WR-TypeEngine       layout="wr"        BankAngle + BankCount
--     │    ├── RotaryEngine        layout="wankel"    Rotary geometry
--     |    ├── RadialEngine        layout="radial"    Radial engines
--     |    ├── SingleMonoEngine    layout="single"    Requires Balance shafts
--     |    └── ParallelTwinEngine  layout="twin"      Requires Balance shafts 
--     ├── TurbineBlock    (layout="turbine")    non-piston superclass
--     └── ElectricBlock   (layout="electric")   non-piston superclass
-- ============================================================

Classes.DefineClass("ACF.CustomEngines.BaseEngineBlock", function() end)

--- INSANE coping this is because i must really define what type of engines are we instancing, just for two fields
-- Define the base engine type (petrol, diesel or electric) cause we need to.
Classes.DefineClass("ACF.CustomEngineTypes.BaseEngineType", function() end)

-- Electric engines(copied and pasted here just for reference, this can go away in an eventual merge to the main addon)
Classes.DefineClass("ACF.CustomEngineTypes.Electric", "ACF.CustomEngineTypes.BaseEngineType", function()
    CLASS.Name        = "Generic Electric Engine"
    CLASS.ShortName   = "Electric"
    CLASS.Efficiency  = 0.85 --percent efficiency converting chemical kw into mechanical kw
    CLASS.TorqueScale = 0.5
    CLASS.TorqueCurve = { 1, 0.5, 0 }
    CLASS.HealthMult  = 0.75
    CLASS.IsElectric  = true
    CLASS.Fuel		  = { ["ACF.CustomFuelTypes.Lithium"] = true }

    FIELD("ACF.CustomFuelTypes.FuelType", "FuelType", {"ACF.CustomFuelTypes.Lithium"})

    function CLASS.CalculateFuelUsage(Entity)
        -- Electric engines use current power output, not max
        return ACF.FuelRate * Entity.Efficiency / 3600
    end
end)

-- Diesel engines
-- Efficiency and torqueCurve are defined by the fuel type classes
Classes.DefineClass("ACF.CustomEngineTypes.GenericDiesel", "ACF.CustomEngineTypes.BaseEngineType", function()
    CLASS.Name         = "Generic Diesel Engine"
    CLASS.ShortName    = "Diesel"
    CLASS.TorqueScale  = 0.25
    CLASS.HealthMult   = 0.5
    CLASS.PistonSpeed  = 13 -- m/s
    CLASS.Efficiency   = 0.243
    CLASS.IgnitionType = "glow"
    CLASS.Fuel		   = { ["ACF.CustomFuelTypes.Diesel"] = true }

    FIELD("ACF.CustomFuelTypes.FuelType", "FuelType", {"ACF.CustomFuelTypes.Diesel"})
end)

-- Any Petrol engines
Classes.DefineClass("ACF.CustomEngineTypes.GenericPetrol", "ACF.CustomEngineTypes.BaseEngineType", function()
    CLASS.Name         = "Generic Petrol Engine"
    CLASS.ShortName    = "Petrol"
    CLASS.TorqueScale  = 0.25
    CLASS.HealthMult   = 0.2
    CLASS.PistonSpeed  = 20 -- m/s
    CLASS.Efficiency   = 0.304
    CLASS.IgnitionType = "spark"
    CLASS.Fuel		   = {
        ["ACF.CustomFuelTypes.Petrol"] = true,
        ["ACF.CustomFuelTypes.E85"] = true,
        ["ACF.CustomFuelTypes.Methanol"] = true
    }

    FIELD("ACF.CustomFuelTypes.FuelType", "FuelType", {
        "ACF.CustomFuelTypes.Petrol",
        "ACF.CustomFuelTypes.E85",
        "ACF.CustomFuelTypes.Methanol"
    })
end)

-- Any turbines
Classes.DefineClass("ACF.CustomEngineTypes.Turbine", "ACF.CustomEngineTypes.BaseEngineType", function()
    CLASS.Name         = "Generic Turbine"
    CLASS.ShortName    = "Turbine"
    CLASS.Efficiency   = 0.375 -- previously 0.231
    CLASS.IgnitionType = "both" -- Technically can use both sparkplugs and glowplugs, as well as being multifuel
    CLASS.TorqueScale  = 0.2
    CLASS.TorqueCurve  = { 1, 0.9, 0.8, 0.7, 0.6, 0.5, 0.4, 0.3, 0.2, 0.1 }
    CLASS.IsTurbine    = true
    CLASS.HealthMult   = 0.125
    -- Turbines are okay with anything that can burn 
    CLASS.Fuel		   = {
        ["ACF.CustomFuelTypes.Diesel"] = true,
        ["ACF.CustomFuelTypes.Petrol"] = true,
        ["ACF.CustomFuelTypes.E85"] = true,
        ["ACF.CustomFuelTypes.Methanol"] = true,
        ["ACF.CustomFuelTypes.JetFuel"] = true
    }

    FIELD("ACF.CustomFuelTypes.FuelType", "FuelType", {
        "ACF.CustomFuelTypes.Diesel",
        "ACF.CustomFuelTypes.Petrol",
        "ACF.CustomFuelTypes.E85",
        "ACF.CustomFuelTypes.Methanol",
        "ACF.CustomFuelTypes.JetFuel"
    })
end)
