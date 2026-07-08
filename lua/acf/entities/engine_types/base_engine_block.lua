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

ACF.Classes.DefineClass("ACF.Engines.BaseEngineBlock", function()
    CLASS.Name          = "Base Engine Block Class"
    CLASS.Description   = "The base class for any and all types of engine blocks."

    MENU_FIELD("ACF.Engines.BaseEngineBlock", "BlockType", {"ACF.Engines.PistonBlock", "ACF.Engines.ElectricBlock", "ACF.Engines.TurbineBlock"})
end)

--- INSANE coping this is because i must really define what type of engines are we instancing, just for two fields
-- Define the base engine type (petrol, diesel or electric) cause we need to.
ACF.Classes.DefineClass("ACF.CustomEngineTypes.BaseEngineType", function() end)

-- Electric engines(copied and pasted here just for reference, this can go away in an eventual merge to the main addon)
ACF.Classes.DefineClass("ACF.CustomEngineTypes.Electric", "ACF.CustomEngineTypes.BaseEngineType", function()
    CLASS.Name        = "Generic Electric Engine"
    CLASS.Efficiency  = 0.85 --percent efficiency converting chemical kw into mechanical kw
    CLASS.TorqueScale = 0.5
    CLASS.TorqueCurve = { 1, 0.5, 0 }
    CLASS.HealthMult  = 0.75

    function CLASS.CalculateFuelUsage(Entity)
        -- Electric engines use current power output, not max
        return ACF.FuelRate * Entity.Efficiency / 3600
    end
end)

-- Diesel engines
-- Efficiency and torqueCurve are defined by the fuel type classes
ACF.Classes.DefineClass("ACF.CustomEngineTypes.GenericDiesel", "ACF.CustomEngineTypes.BaseEngineType", function()
    CLASS.Name        = "Generic Diesel Engine"
    CLASS.TorqueScale = 0.35
    CLASS.HealthMult  = 0.5
    CLASS.Fuel		 = { ["ACF.CustomFuelTypes.Diesel"] = true }

    FIELD("ACF.FuelTypes.FuelType", "FuelType", {"ACF.CustomFuelTypes.Diesel"})
end)

-- Any Petrol engines
ACF.Classes.DefineClass("ACF.CustomEngineTypes.GenericPetrol", "ACF.CustomEngineTypes.BaseEngineType", function()
    CLASS.Name        = "Generic Petrol Engine"
    CLASS.TorqueScale = 0.25
    CLASS.HealthMult  = 0.2
    CLASS.Fuel		  = {
        ["ACF.CustomFuelTypes.Petrol"] = true,
        ["ACF.CustomFuelTypes.E85"] = true,
        ["ACF.CustomFuelTypes.Methanol"] = true
    }

    FIELD("ACF.FuelTypes.FuelType", "FuelType", {"ACF.CustomFuelTypes.Petrol", "ACF.CustomFuelTypes.E85", "ACF.CustomFuelTypes.Methanol"})
end)
