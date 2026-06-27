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

ACF.Classes.DefineClass("ACF.Engines.BlockType", function()
    CLASS.Name          = "Block Type Class"
    CLASS.Description   = "The base class for any and all types of engine blocks."

    FIELD("ACF.Engines.BlockType", "BlockType", {"PistonBlock", "ElectricBlock", "TurbineBlock"})
end)