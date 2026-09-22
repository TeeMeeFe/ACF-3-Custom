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
local PI             = math.pi
local abs            = math.abs
local random         = math.random
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

-- Get the volume of the fuel pipeline
local function GetPipelineVolume(PipeLength, PipeSize)
    return (PI / 4) * PipeSize * PipeSize * PipeLength / 1000 -- in mL
end

-- Calculates fuel tank distance based on the furthest one, to calculate pipeline pressure build/decay.
local function CalcFuelTankDistance(Engine)
    local Length = 0
    for _, Dist in pairs(Engine.FuelLinkDistances) do
        if Dist > Length then
            Length = Dist
        end
    end
    return Length
end

local function CheckDistantFuelTanks(Engine)
    local EnginePos = Engine:GetPos()

    for Tank in pairs(Engine.FuelTanks) do
        local Distance = EnginePos:DistToSqr(Tank:GetPos())

        Engine.FuelLinkDistances[Tank] = Distance
        if Distance > MaxDistance then
            local Sound = UnlinkGbxSound:format(random(1, 3))

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
            local Sound = UnlinkRadSound:format(random(1, 2))

            Sounds.SendSound(Engine, Sound, 85, 100, 1)
            Sounds.SendSound(Rad, Sound, 85, 100, 1)

            Engine:Unlink(Rad)
        end
    end
end

local function SetStarterActive(EntTbl, Active)
    local Starter = EntTbl.Starter
    if not IsEntityValid(Starter) then return end

    local SrtTable = Starter:GetTable()
    if SrtTable.IsCranking == Active then return end

    SrtTable.SetActive(Starter, Active)
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

        EntTbl.LastThink = Clock.CurTime

        Entity:UpdateSound(EntTbl)

        Entity:NextThink(Clock.CurTime + TickInterval())

        -- Fuel rail pressure calc.
        local FuelLength = CalcFuelTankDistance(Entity)
        local PipelineVol = GetPipelineVolume(Clamp(FuelLength, 1, MaxDistance), EntTbl.PipeRefSize)
        local PressureBuildRate = EntTbl.PumpFlow / PipelineVol
        local PressureDecayRate = PipelineVol * EntTbl.PipeLeakRate

        EntTbl.RailBuildRate = PressureBuildRate
        EntTbl.RailDecayRate = PressureDecayRate

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
        SetStarterActive(EntTbl, false)

        TimerRemove("ACF Engine Clock " .. Entity:EntIndex())
    end

    -- Set the radiator to whatever state this entity is in
    for Ent, Link in pairs(EntTbl.Radiators) do
        if not Ent.Disabled and IsEntityValid(Ent) then
            Ent:SetActive(EntTbl.Active)
        elseif not IsEntityValid(Ent) then
            EntTbl.Radiators[Ent] = nil -- I shouldn't be doing this but sometimes it gets left lingering like this.
        end
    end

    Entity:UpdateOverlay()
    Entity:UpdateOutputs(EntTbl)
end

--- Default BSFC fuel flow in L/s.
--- Off-peak throttle raises effective BSFC by up to 11%.
local function DefaultFuelFlow(Throttle, Power, BSFC, FuelDensity)
    local EffectiveBSFC = BSFC * (1 + 0.11 * (1 - Throttle))
    local Flow = (Power * EffectiveBSFC) / 3600 / FuelDensity -- Flow in Kg / Fuel density
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
        self.FuelCrewMod = Clamp(Val, ACF.CrewFallbackCoef, 1)
        return self.FuelCrewMod
    end
end
--===============================================================================================--

do -- Actual engine rpm and torque calculations
    function ENT:GetTorqueMult() return ACF.GetServerData("TorqueMult") or 1 end

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
        if SelfTbl.Disabled then return end

        -- Keep updating temps and pressure even if the radiator is off
        if not SelfTbl.Active then
            if not SelfTbl.WasTimed then
                TimerCreate("ACF Temperature Clock " .. self:EntIndex(), 1, 0, function()
                    if not SelfTbl.Active then
                        self:CalcTemp(SelfTbl)
                        SelfTbl.RailPressure = max(SelfTbl.RailPressure - ((Clock.CurTime - SelfTbl.LastThink) * SelfTbl.RailDecayRate), 0) -- Update rail pressure too
                        SelfTbl.LastThink = Clock.CurTime
                        SelfTbl.UpdateOutputs(self, SelfTbl)
                    end
                end)
                SelfTbl.WasTimed = true
            end
            return
        -- Else start cranking the engine
        elseif SelfTbl.Active and not SelfTbl.IsStalled and SelfTbl.HasStarter and SelfTbl.FlyRPM < SelfTbl.IdleRPM * 0.5 then
            SetStarterActive(SelfTbl, SelfTbl.Active)
        end

        -- Got destroyed, only keep updating thermals 
        if SelfTbl.IsDestroyed then return end

        self:CalcRPM(SelfTbl)
        self:CalcTemp(SelfTbl)

        SelfTbl.LastThink = Clock.CurTime
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

        local ClockTime = Clock.CurTime
        local DeltaTime = ClockTime - SelfTbl.LastThink

        -- Due to the temperature clock, every one second it'll synchronize the DeltaTime to our ClockTime,
        -- so we have to return early to avoid some issues downstream. This doesn't mean this tick will be wasted,
        -- since DeltaTime is already returning 0 at this state, so nothing of significance could happen anyway. 
        if DeltaTime == 0 then return end

        local FuelTank   = GetNextFuelTank(SelfTbl)
        local TorqueMult = SelfTbl.GetTorqueMult() -- Idk if this will work given the tight perf budget we have to work with here...
        local DamageMult = SelfTbl.TorqueDamageMult
        local IsElectric = SelfTbl.IsElectric
        local IdleRPM    = SelfTbl.IdleRPM
        local LimitRPM   = SelfTbl.LimitRPM
        local RedlineRPM = SelfTbl.RedlineRPM
        local FlyRPM     = SelfTbl.FlyRPM

        local Starter    = SelfTbl.Starter
        local SrtTable   = ENTITY.GetTable(Starter)

        local StrTorque  = SrtTable.Torque

        -- Determine if the rev limiter will engage or disengage
        local RevLimited = false
        if SelfTbl.RevLimiterEnabled and not IsElectric then
            if FlyRPM > RedlineRPM * 0.99 then
                RevLimited = true
            elseif FlyRPM < RedlineRPM * 0.95 then
                RevLimited = false
            end

            SelfTbl.RevLimited = RevLimited
        end

        -- Throttle Idler code shamefully stolen from Tyunge's engine rework.
        local IdleRatio = (IdleRPM - FlyRPM) / IdleRPM
        SelfTbl.IdleThrottle = Clamp(SelfTbl.IdleThrottle + (IdleRatio * 0.25), 0, 1)

        local SmoothedIdle = SelfTbl.IdleThrottle - SelfTbl.LastIdleThrottle
        SelfTbl.LastIdleThrottle = SelfTbl.IdleThrottle

        local Throttle = RevLimited and 0 or Clamp(SelfTbl.Throttle + (SelfTbl.IdleThrottle + SmoothedIdle * 5), 0, 1)

        -- Turn off the starter if we have reached enough velocity
        if SrtTable.IsCranking and FlyRPM >= IdleRPM * 0.9 then
            SetStarterActive(SelfTbl, false)
        end

        -- Calculate fuel usage
        if IsEntityValid(FuelTank) then
            SelfTbl.FuelTank = FuelTank
            SelfTbl.FuelType = FuelTank.FuelType

            local Consumption = SelfTbl.GetConsumption(self, Throttle, FlyRPM, FuelTank, SelfTbl) * DeltaTime

            SelfTbl.FuelUsage = SelfTbl.Active and 60 * Consumption / max(DeltaTime, 0.001) or 0 -- Clamp this bitch so it doesn't NaN out
            ENTITY.GetTable(FuelTank).Consume(FuelTank, Consumption)
        elseif ACF.RequireFuel then -- Stay active if fuel consumption is disabled
            SetActive(self, false, SelfTbl)

            SelfTbl.FuelUsage = 0

            return 0
        end

        -- Update rail pressure
        SelfTbl.RailPressure = min(SelfTbl.RailPressure + SelfTbl.RailBuildRate * DeltaTime, 1)
        SelfTbl.FuelPrimed   = SelfTbl.RailPressure >= 0.70  -- Fraction of full pressure considered "primed"

        -- Calculate the current torque from flywheel RPM
        local Torque, Friction = 0, SelfTbl.Friction or 0
        local FlyInertia = SelfTbl.FlywheelInertia

        if FlyRPM < LimitRPM then
            local Sample = SelfTbl.Sample(FlyRPM)
            Torque = SelfTbl.FuelPrimed and Throttle * Sample[1] * TorqueMult * DamageMult or 0
            Friction = Sample[2] * (SelfTbl.OilViscosity or 1.0)
        end

        -- The gearboxes don't think on their own, it's the engine that calls them, to ensure consistent execution order
        local GearboxCount      = 0
        local GearboxLoad       = 0
        local GearboxRPM        = 0
        local GearboxInertia    = 0
        local GearboxTotalRatio = 0

        local BoxesTbl = SelfTbl.Gearboxes
        local TotalReqTq = 0
        -- Get the requirements for torque for the gearboxes (Max clutch rating minus any wheels currently spinning faster than the Flywheel)
        for Ent, Link in pairs(BoxesTbl) do
            local EntTbl = ENTITY.GetTable(Ent)

            if not EntTbl.Disabled then
                Link.ReqTq = EntTbl.Calc(Ent, FlyRPM, FlyInertia)
                TotalReqTq = TotalReqTq + Link.ReqTq

                GearboxCount      = GearboxCount + 1
                GearboxLoad       = GearboxLoad + (EntTbl.Load or 0)
                GearboxTotalRatio = GearboxTotalRatio + (EntTbl.TotalRatio or 0)
                GearboxRPM        = GearboxRPM + (EntTbl.MeasuredRPM or FlyRPM)
                GearboxInertia    = GearboxInertia + (EntTbl.DownstreamInertia or 0)
            end
        end

        if GearboxCount > 0 then
            GearboxRPM = GearboxRPM / GearboxCount
            GearboxTotalRatio = GearboxTotalRatio / GearboxCount
        end

        -- Pumping/compression braking
        local PMEP = 25 -- bar; Tune this bitch 
        local CompressionBrakeTorque = -(PMEP * SelfTbl.Displacement.InLiters / (4 * PI)) * SelfTbl.CompressionRatio * (1 - Throttle)

        SelfTbl.CompressionBrakeTorque = CompressionBrakeTorque

        local SlipDifference = GearboxRPM - FlyRPM
        local MaxTq = (abs(SlipDifference) * GearboxInertia) / max(GearboxTotalRatio, 0.001)
        local FeedbackTq = Clamp((SlipDifference * GearboxInertia * GearboxLoad) * 0.5, -MaxTq, MaxTq)
        local IncomingInertia = max(FlyInertia, GearboxInertia * GearboxLoad)

        local EngineTorque = (Torque + StrTorque + (FeedbackTq * GearboxLoad) + (CompressionBrakeTorque * max(1 - GearboxLoad, 0.5))) - Friction -- Limited compression brake slip

        -- Let's accelerate the flywheel based on that torque
        FlyRPM = max(FlyRPM + EngineTorque / IncomingInertia, 0)

        -- This is just to update the overlay
        -- Here ideally i'd also check if the starter is engaged and update that condition as well.
        if FlyRPM <= IdleRPM * 0.9 and SrtTable.IsCranking then
            SelfTbl.State = "Cranking"
        elseif FlyRPM <= IdleRPM * 0.9 and not SrtTable.IsCranking then
            SelfTbl.State = "Stalling"
        else
            SelfTbl.State = "Active"
        end
        SelfTbl.Torque = Torque
        SelfTbl.Friction = Friction -- Assembly Friction

        -- This is the presently available torque from the engine
        local TorqueDiff = Clamp(FlyRPM - IdleRPM, -TotalReqTq, TotalReqTq) * IncomingInertia

        -- Calculate the ratio of total requested torque versus what's available
        local AvailRatio = min(abs(TorqueDiff) / max(abs(TotalReqTq), 1e-6), 1)

        local MassRatio = SelfTbl.MassRatio

        -- Split the torque fairly between the gearboxes who need it
        for Ent, Link in pairs(BoxesTbl) do
            Link:TransferGearbox(Ent, Link.ReqTq * AvailRatio * MassRatio, DeltaTime, MassRatio, FlyRPM)
        end

        SelfTbl.FlyRPM = FlyRPM

        -- Stall detection: RPM collapsed below the stall threshold while the load exceeded output.
        -- SetActive handles the restart guard; CalcRPM just flags and shuts down.
        if FlyRPM <= IdleRPM * 0.33 and (GearboxTotalRatio == 0 and not SrtTable.IsCranking) or (FlyRPM <= IdleRPM * 0.33 and TotalReqTq > TorqueDiff) then
            SelfTbl.IsStalled = true
            SetActive(self, false, SelfTbl)
        end

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
    local Temps     = SelfTbl.Temperature

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
    if SelfTbl.LastState ~= State then
        SelfTbl.LastState = State
        WireLib.TriggerOutput(self, "State", State)
    end
    if SelfTbl.LastCoolantTemp ~= Temps.Coolant then
        SelfTbl.LastCoolantTemp = Temps.Coolant
        WireLib.TriggerOutput(self, "Coolant Temp", Temps.Coolant)
    end
    if SelfTbl.LastOilTemp ~= Temps.Oil then
        SelfTbl.LastOilTemp = Temps.Oil
        WireLib.TriggerOutput(self, "Oil Temp", Temps.Oil)
    end
    if SelfTbl.LastOilPressure ~= Round(SelfTbl.OilPressureBar, 1) then
        SelfTbl.LastOilPressure = Round(SelfTbl.OilPressureBar, 1)
        WireLib.TriggerOutput(self, "Oil Pressure", SelfTbl.LastOilPressure)
    end
    if SelfTbl.LastOilWarning ~= (not SelfTbl.OilPressureOK) then
        SelfTbl.LastOilWarning = not SelfTbl.OilPressureOK
        WireLib.TriggerOutput(self, "Oil Warning", SelfTbl.LastOilWarning and 1 or 0)
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

function ENT:ACF_Activate(Recalc)
    local PhysObj = self.ACF.PhysObj
    local Mass    = PhysObj:GetMass()
    local Area    = PhysObj:GetSurfaceArea() * ACF.InchToCmSq
    -- Fucking ArmoUr :face_vomiting: :face_vomiting: :face_vomiting: :face_vomiting: :face_vomiting:
    -- Britons gave us americans the english language so we can sanitize it and have it sound more or less understandable and be more legible!
    -- TODO: Replace this variable name and all instances of it with the correct word and fix the comment since its wrong lol
    local Armour  = Mass * 1000 / Area / 0.78 * ACF.ArmorMod -- Density of steel = 7.8g cm3 so 7.8kg for a 1mx1m plate 1m thick
    local Health  = Area / ACF.Threshold
    local Percent = 1

    if Recalc and self.ACF.Health and self.ACF.MaxHealth then
        Percent = self.ACF.Health / self.ACF.MaxHealth
    end

    self.ACF.Area      = Area
    self.ACF.Health    = Health * Percent * self.HealthMult
    self.ACF.MaxHealth = Health * self.HealthMult
    self.ACF.Armour    = Armour * (0.5 + Percent * 0.5)
    self.ACF.MaxArmour = Armour
    self.ACF.Type      = "Prop"
end