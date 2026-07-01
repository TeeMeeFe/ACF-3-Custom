local ACF = ACF

local ENTITY         = FindMetaTable("Entity")
local PHYSOBJ		 = FindMetaTable("PhysObj")

local IsEntityValid	 = ACF.Optimizations.IsEntityValid
local IsPhysObjValid = ACF.Optimizations.IsPhysObjValid

--===============================================================================================--
-- Local Funcs and Vars
--===============================================================================================--
local Clock          = ACF.Utilities.Clock
local Sounds         = ACF.Utilities.Sounds
local Contraption    = ACF.Contraption
local UnlinkRadSound = "physics/metal/crowbar_impact%s.wav"
local UnlinkGbxSound = "physics/metal/metal_box_impact_bullet%s.wav"
local IsValid        = IsValid
local Clamp          = math.Clamp
local Round          = math.Round
-- local Remap          = math.Remap
local max            = math.max
local min            = math.min
local TimerCreate    = timer.Create
local TimerRemove    = timer.Remove
local TickInterval   = engine.TickInterval
local MaxDistance    = ACF.MobilityLinkDistance * ACF.MobilityLinkDistance
local MaxRadDistance = ACF.RadiatorLinkDistance * ACF.RadiatorLinkDistance

-- Local function shit, unchanged from original engine code
local function GetNextFuelTank(Engine)
    local FuelTanks = Engine.FuelTanks
    if not next(FuelTanks) then return end

    local Select = next(FuelTanks, Engine.FuelTank) or next(FuelTanks)
    local Start = Select

    repeat
        if Select:CanConsume() then return Select end

        Select = next(FuelTanks, Select) or next(FuelTanks)
    until Select == Start

    return Select:CanConsume() and Select or nil
end

local function CheckDistantFuelTanks(Engine)
    local EnginePos = Engine:GetPos()

    for Tank in pairs(Engine.FuelTanks) do
        if EnginePos:DistToSqr(Tank:GetPos()) > MaxDistance then
            local Sound = UnlinkGbxSound:format(math.random(1, 3))

            Sounds.SendSound(Engine, Sound, 70, 100, 1)
            Sounds.SendSound(Tank, Sound, 70, 100, 1)

            Engine:Unlink(Tank)
        end
    end
end

local function CheckGearboxes(Engine)
    for Ent, Link in pairs(Engine.Gearboxes) do
        local OutPos = Engine:LocalToWorld(Engine.Out.Pos)
        local InPos = Ent:LocalToWorld(Ent.In.Pos)

        -- make sure it is not stretched too far
        if OutPos:Distance(InPos) > Link.RopeLen * 1.5 then
            Engine:Unlink(Ent)
            continue
        end

        if ACF.IsDriveshaftAngleExcessive(Ent, Ent.In, Engine, Engine.Out) then
            Engine:Unlink(Ent)
        end
    end
end

-- New in this iteration, its just like fueltanks except we have another constant for excess distance calc
local function CheckDistantRadiators(Engine)
   local EnginePos = Engine:GetPos()

    for Rad in pairs(Engine.Radiators) do
        if EnginePos:DistToSqr(Rad:GetPos()) > MaxRadDistance then
            local Sound = UnlinkRadSound:format(math.random(1, 2))

            Sounds.SendSound(Engine, Sound, 85, 100, 1)
            Sounds.SendSound(Rad, Sound, 85, 100, 1)

            Engine:Unlink(Rad)
        end
    end
end

local function SetActive(Entity, Value, EntTbl)
    EntTbl = EntTbl or Entity:GetTable()

    local ActBool = tobool(Value)
    local IsStalled = EntTbl.IsStalled

    if EntTbl.Active == ActBool then return end -- Already in the desired state
    if ActBool and EntTbl.Disabled then return end -- Can't activate a disabled engine

    if ActBool and not IsStalled then -- Was off, turn on, unless if it's stalled
        EntTbl.Active = true

        Entity:CalcMassRatio(EntTbl)

        EntTbl.State     = "Active"
        EntTbl.LastThink = Clock.CurTime
        EntTbl.Torque    = EntTbl.PeakTorque.InNm
        EntTbl.FlyRPM    = EntTbl.IdleRPM * 1.5

        Entity:UpdateSound(EntTbl)

        Entity:NextThink(Clock.CurTime + TickInterval())

        TimerCreate("ACF Engine Clock " .. Entity:EntIndex(), 3, 0, function()
            if not IsEntityValid(Entity) then return end

            CheckGearboxes(Entity)
            CheckDistantFuelTanks(Entity)
            CheckDistantRadiators(Entity)

            Entity:CalcMassRatio(EntTbl)
        end)
    else -- Was on, turn off
        EntTbl.Active = false
        if IsStalled then
            EntTbl.State = "Stalled"
        else
            EntTbl.State = "Idle"
        end
        EntTbl.FlyRPM = 0
        EntTbl.Torque = 0

        Entity:DestroySound()

        TimerRemove("ACF Engine Clock " .. Entity:EntIndex())
    end

    Entity:UpdateOverlay()
    Entity:UpdateOutputs(EntTbl)
end

--- Default BSFC fuel flow in L/s.
--- Off-peak throttle raises effective BSFC by up to 11%.
local function DefaultFuelFlow(Throttle, Power_KW, BSFC, FuelDensity)
    local EffectiveBSFC = BSFC * (1 + 0.11 * (1 - Throttle))
    local Flow = (Power_KW * EffectiveBSFC) / 3600 / FuelDensity -- Flow in Kg / Fuel density
    return Flow
end

do -- Random timer crew stuff
    function ENT:FindPropagator()
        local Temp = self:GetParent()
        if IsValid(Temp) and Temp:GetClass() == "acf_baseplate" then return Temp end
        return nil
    end

    function ENT:UpdateFuelMod(cfg)
        local Propagator = self:FindPropagator(cfg)
        local Val = Propagator and Propagator.FuelCrewMod or 0
        self.FuelCrewMod = math.Clamp(Val, ACF.CrewFallbackCoef, 1)
        return self.FuelCrewMod
    end
end
--===============================================================================================--

do -- Actual engine rpm and torque calculations
    function ENT:GetConsumption(Throttle, RPM, FuelTank, SelfTbl)
        SelfTbl = SelfTbl or ENTITY.GetTable(self)
        FuelTank = FuelTank or SelfTbl.FuelTank
        if not IsEntityValid(FuelTank) then return 0 end

        -- Otherwise check what type of fuel we're consuming and how much
        if SelfTbl.BlockType == "Electric" then
            return Throttle * SelfTbl.FuelUse * SelfTbl.Torque * RPM * 1.05e-4 / SelfTbl.FuelCrewMod
        else
            local Power = max(SelfTbl.Torque * RPM / 9548.8, 0.5) -- Minimum idle consumption
            local Flow  = DefaultFuelFlow(Throttle, Power, SelfTbl.BSFC, FuelTank.FuelDensity)

            return (SelfTbl.FuelUse * Flow) / SelfTbl.FuelCrewMod
        end
    end

    function ENT:Think()
        local SelfTbl = ENTITY.GetTable(self)

        if not SelfTbl.Active then return end
        if SelfTbl.Disabled then return end

        self:CalcRPM(SelfTbl)

        -- CalcRPM can turn the engine off or disable it (e.g. no fuel or legality issues)
        if not SelfTbl.Active or SelfTbl.Disabled then return end

        self:NextThink(CurTime() + TickInterval())

        return true
    end

    -- We're doing an experiment here. It seems that the entity table stores the functions for the entity
    -- class as well. So we don't need to do self:Function for every entity (which would invoke the __index function)
    -- If true then we should apply this in the rest of the hot paths.
    function ENT:CalcRPM(SelfTbl)
        -- Reusing these entity table pointers helps us cut down on __index calls
        -- This helps to massively improve performance throughout the entire drivetrain
        SelfTbl = SelfTbl or ENTITY.GetTable(self)

        local ClockTime  = Clock.CurTime
        local DeltaTime  = ClockTime - SelfTbl.LastThink
        -- Unused this iteration due to me working with a broken class-rewrite branch(awaiting on march to complete his work)
        local FuelTank   = GetNextFuelTank(SelfTbl)
        local IsElectric = SelfTbl.IsElectric
        local LimitRPM   = SelfTbl.RedlineRPM
        local FlyRPM     = SelfTbl.FlyRPM

        -- Determine if the rev limiter will engage or disengage
        local RevLimited = false
        if SelfTbl.revLimiterEnabled and not IsElectric then
            if FlyRPM > LimitRPM * 0.99 then
                RevLimited = true
            elseif FlyRPM < LimitRPM * 0.95 then
                RevLimited = false
            end

            SelfTbl.RevLimited = RevLimited
        end
        local Throttle = RevLimited and 0 or SelfTbl.Throttle

        -- Calculate fuel usage
        if IsEntityValid(FuelTank) then
            SelfTbl.FuelTank = FuelTank
            SelfTbl.FuelType = FuelTank.FuelType

            local Consumption = SelfTbl.GetConsumption(self, Throttle, FlyRPM, FuelTank, SelfTbl) * DeltaTime

            SelfTbl.FuelUsage = 60 * Consumption / DeltaTime
            ENTITY.GetTable(FuelTank).Consume(FuelTank, Consumption)
        elseif ACF.RequireFuel then -- Stay active if fuel consumption is disabled
            SetActive(self, false, SelfTbl)

            SelfTbl.FuelUsage = 0

            return 0
        end

        -- Calculate the current torque from flywheel RPM
        local IdleRPM    = SelfTbl.IdleRPM
        local PeakRPM    = IsElectric and SelfTbl.FlywheelOverride or SelfTbl.PowerBand.Max
        local Inertia    = SelfTbl.FlywheelInertia
        local PeakTorque = SelfTbl.PeakTorque.InNm
        local Drag       = PeakTorque * (max(FlyRPM - IdleRPM, 0) / PeakRPM) * (1 - Throttle) / Inertia

        local Torque = 0

        -- This is just to update the overlay
        -- Here ideally i'd also check if the starter is engaged and update that condition as well.
        -- This way of setting states is performance wasteful though...
        if FlyRPM < IdleRPM then
            SelfTbl.State = "Stalling"
        else
            SelfTbl.State = "Active"
        end

        if Throttle ~= 0 and FlyRPM < LimitRPM then
            -- local Percent = Remap(FlyRPM, IdleRPM, LimitRPM, 0, 1)
            Torque = Throttle * SelfTbl.Sample(FlyRPM) -- * (FlyRPM < LimitRPM and 1 or 0)
        end

        SelfTbl.Torque = Torque

        -- Let's accelerate the flywheel based on that torque
        FlyRPM = min(max(FlyRPM + Torque / Inertia - Drag, 0), LimitRPM)

        -- The gearboxes don't think on their own, it's the engine that calls them, to ensure consistent execution order
        local Boxes      = 0
        local TotalReqTq = 0
        local SlipDrain  = 0 -- RPM drain from clutch slip (per-gearbox, accumulated below)

        -- This is the presently available torque from the engine
        local TorqueDiff = max(FlyRPM - IdleRPM, 0) * Inertia

        -- The resulting torque output would be 0 when there's no throttle anyways, so we'll just skip the calculations entirely
        if Throttle ~= 0 then
            local BoxesTbl = SelfTbl.Gearboxes

            -- Get the requirements for torque for the gearboxes (Max clutch rating minus any wheels currently spinning faster than the Flywheel)
            for Ent, Link in pairs(BoxesTbl) do
                local EntTable = ENTITY.GetTable(Ent)
                if not EntTable.Disabled then
                    Boxes = Boxes + 1
                    Link.ReqTq = EntTable.Calc(Ent, FlyRPM, Inertia)
                    TotalReqTq = TotalReqTq + Link.ReqTq

                    -- Slip coupling: flywheel RPM vs load-side RPM at each gearbox input shaft.
                    -- When FlyRPM > LoadSideRPM the clutch drags the flywheel down toward the load.
                    -- When FlyRPM < LoadSideRPM (overrun) the load pushes the flywheel up.
                    -- Engagement strength is the average of left/right clutch values (0 = open, 1 = locked).
                    local SlipRPM = FlyRPM - (EntTable.LoadSideRPM or FlyRPM)
                    local Engage  = (EntTable.LClutch + EntTable.RClutch) * 0.5
                    SlipDrain = SlipDrain + SlipRPM * Engage * ACF.ClutchSlipCoef
                end
            end

            -- Clamp total slip so a single tick can't drain more than the available flywheel energy.
            SlipDrain = Clamp(SlipDrain, -TorqueDiff, TorqueDiff) / Inertia

            -- Calculate the ratio of total requested torque versus what's available
            local AvailRatio = min(TorqueDiff / TotalReqTq / Boxes, 1)

            local MassRatio = SelfTbl.MassRatio

            -- Split the torque fairly between the gearboxes who need it
            for Ent, Link in pairs(BoxesTbl) do
                Link:TransferGearbox(Ent, Link.ReqTq * AvailRatio * MassRatio, DeltaTime, MassRatio, FlyRPM)
                --Ent:Act(Link.ReqTq * AvailRatio * MassRatio, DeltaTime, MassRatio)
            end
        end

        SelfTbl.FlyRPM = FlyRPM - min(TorqueDiff, TotalReqTq) / Inertia - SlipDrain

        -- Stall detection: RPM collapsed below the stall threshold while the load exceeded output.
        -- SetActive handles the restart guard; CalcRPM just flags and shuts down.
        if SelfTbl.FlyRPM <= SelfTbl.IdleRPM * 0.1 and TotalReqTq > TorqueDiff then
            SelfTbl.IsStalled = true
            SetActive(self, false, SelfTbl)
        end
        SelfTbl.LastThink = ClockTime

        SelfTbl.UpdateSound(self, SelfTbl)
        SelfTbl.UpdateOutputs(self, SelfTbl)
    end
end

--===============================================================================================--
-- Meta Funcs (I probably should move this elsewhere...)
--===============================================================================================--
function ENT:Enable()
    local Active

    if self.Inputs.Active.Path then
        Active = tobool(self.Inputs.Active.Value)
    else
        Active = true
    end

    SetActive(self, Active, self:GetTable())

    self:UpdateOverlay()
    ACF.CheckLegal(self) -- MARCH: Check parent chain on enabled
end

function ENT:Disable()
    SetActive(self, false, self:GetTable()) -- Turn off the engine 

    self:UpdateOverlay()
end

-- Wiremod output updating
function ENT:UpdateOutputs(SelfTbl)
    SelfTbl = SelfTbl or ENTITY.GetTable(self)

    local FuelUsage = Round(SelfTbl.FuelUsage)
    local Torque    = SelfTbl.Torque
    local FlyRPM    = SelfTbl.FlyRPM
    local Power     = Round(Torque * FlyRPM / 9548.8)
    local State     = SelfTbl.State

    Torque = Round(Torque)
    FlyRPM = Round(FlyRPM)

    if SelfTbl.LastFuelUsage ~= FuelUsage then
        SelfTbl.LastFuelUsage = FuelUsage
        WireLib.TriggerOutput(self, "Fuel Use", FuelUsage)
    end
    if SelfTbl.LastTorque ~= Torque then
        SelfTbl.LastTorque = Torque
        WireLib.TriggerOutput(self, "Torque", Torque)
    end
    if SelfTbl.LastPower ~= Power then
        SelfTbl.LastPower = Power
        WireLib.TriggerOutput(self, "Power", Power)
    end
    if SelfTbl.LastRPM ~= FlyRPM then
        SelfTbl.LastRPM = FlyRPM
        WireLib.TriggerOutput(self, "RPM", FlyRPM)
    end
    if SelfTbl.State ~= State then
        SelfTbl.State = State
        WireLib.TriggerOutput(self, "State", State)
    end
end

-- Input actions
ACF.AddInputAction("acf_engine_custom", "Throttle", function(Entity, Value)
    Entity.Throttle = Clamp(Value, 0, 1) -- BREAKING CHANGE: Switched to use ratio, rather than percentages here
end)

ACF.AddInputAction("acf_engine_custom", "Active", function(Entity, Value)
    local Val = tobool(Value)
    SetActive(Entity, Val, Entity:GetTable())
    if not Val then Entity.IsStalled = false end -- In case the engine stalls, we have to turn off ignition then try again
end)

-- specialized calcmassratio for engines
function ENT:CalcMassRatio(SelfTbl)
    SelfTbl        = SelfTbl or ENTITY.GetTable(self)
    local Con      = ENTITY.CFW_GetContraption(self)
    local PhysMass = 0

    local Physical, _, Detached = Contraption.GetEnts(self)

    -- Duplex pairs iterates over Physical, then Detached - but we can make Detached nil
    -- if DetachedPhysmassRatio == false
    for K in ACF.DuplexPairs(Physical, ACF.DetachedPhysmassRatio and Detached or nil) do
        local Phys = ENTITY.GetPhysicsObject(K) -- Should always exist, but just in case

        if IsPhysObjValid(Phys) then
            local Mass = PHYSOBJ.GetMass(Phys)
            PhysMass   = PhysMass + Mass
        end
    end

    local TotalMass = Con and Con.totalMass or PhysMass

    SelfTbl.MassRatio = PhysMass / TotalMass
    TotalMass = Round(TotalMass, 2)
    PhysMass = Round(PhysMass, 2)

    if SelfTbl.LastTotalMass ~= TotalMass then
        SelfTbl.LastTotalMass = TotalMass
        WireLib.TriggerOutput(self, "Mass", Round(TotalMass, 2))
    end
    if SelfTbl.LastPhysMass ~= PhysMass then
        SelfTbl.LastPhysMass = PhysMass
        WireLib.TriggerOutput(self, "Physical Mass", Round(PhysMass, 2))
    end
end

