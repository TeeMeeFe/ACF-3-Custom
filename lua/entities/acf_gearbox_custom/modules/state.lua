local ACF = ACF

local Utilities   	 = ACF.Utilities
local Clock       	 = Utilities.Clock
local TickInterval   = engine.TickInterval

local Clamp       	 = math.Clamp
local floor          = math.floor
local abs         	 = math.abs
local min         	 = math.min
local max         	 = math.max
local deg            = math.deg

local ENTITY         = FindMetaTable("Entity")
local VECTOR         = FindMetaTable("Vector")
local PHYSOBJ        = FindMetaTable("PhysObj")

local IsEntityValid  = ACF.Optimizations.IsEntityValid
local IsPhysObjValid = ACF.Optimizations.IsPhysObjValid

local function GetChassisAngleVelocity(Entity)
    local Parent = ENTITY.GetParent(Entity)
    local Phys   = IsEntityValid(Parent) and ENTITY.GetPhysicsObject(Parent)

    -- Returns the chassis' angular velocity in world space (deg/s).
    if IsPhysObjValid(Phys) then return PHYSOBJ.GetAngleVelocity(Phys) end

    -- In case our gearbox is not parented, we return the gearbox's angular velocity instead.
    Phys = ENTITY.GetPhysicsObject(Entity)
    if IsPhysObjValid(Phys) then return PHYSOBJ.GetAngleVelocity(Phys) end

    -- Fallback to 0, although i think this should error, but ehh whatever you say my GTA III character... :3
    return vector_origin
end

local function CalcWheel(Entity, Link, Wheel, ChassisAngVel)
    local EntityTable = ENTITY.GetTable(Entity)

    local GearRatio = EntityTable.GearRatio

    local WheelPhys    = ENTITY.GetPhysicsObject(Wheel)
    local WheelAngVel  = PHYSOBJ.GetAngleVelocity(WheelPhys)
    local WheelVelDiff = PHYSOBJ.LocalToWorldVector(WheelPhys, WheelAngVel)
    VECTOR.Sub(WheelVelDiff, ChassisAngVel)

    local AxisW = PHYSOBJ.LocalToWorldVector(WheelPhys, Link.Axis)

    -- Angular velocity of the wheel relative to the chassis on the drive axis
    local RelAngVel = VECTOR.Dot(WheelVelDiff, AxisW)
    Link.Vel        = RelAngVel

    if GearRatio == 0 then return 0 end

    -- We get degrees per second and is also inverted, so we have to convert to RPM (deg/s → RPM (1 RPM = 6 deg/s))
    return RelAngVel * GearRatio / -6
end

local function BrakeWheel(Link, Wheel, Brake, MaxBrakeTq, DeltaTime, ChassisAngVel, Loss)
    if Brake <= 0 then Link.IsBraking = false ; return end

    local WheelPhys = ENTITY.GetPhysicsObject(Wheel)
    if not PHYSOBJ.IsMotionEnabled(WheelPhys) then return end -- skipping entirely if its frozen

    local WheelAngVel  = PHYSOBJ.GetAngleVelocity(WheelPhys)
    local WheelVelDiff = PHYSOBJ.LocalToWorldVector(WheelPhys, WheelAngVel)
    VECTOR.Sub(WheelVelDiff, ChassisAngVel)

    local AxisW    = PHYSOBJ.LocalToWorldVector(WheelPhys, Link.Axis)
    local RelOmega = VECTOR.Dot(WheelVelDiff, AxisW)

    Link.LastVel = Link.Vel

    -- Dead zone: stop braking when essentially stationary to prevent oscillation
    local BRAKE_DEADZONE = 0.015 -- RPM equivalent (× 6 = deg/s)

    if abs(RelOmega) < BRAKE_DEADZONE * 6 then
        Link.IsBraking = false
        return
    end

    -- TODO: Some low-pass filter here to dampen braketorque when fully stopped, relative to chassis velocity. 

    -- Coulomb friction: constant magnitude opposing rotation
    local BrakeTorque = -Link.Axis
    VECTOR.Mul(BrakeTorque, Brake)
    VECTOR.Mul(BrakeTorque, Clamp(Link.Vel, -MaxBrakeTq, MaxBrakeTq))
    VECTOR.Mul(BrakeTorque, Loss or 1)

    PHYSOBJ.AddAngleVelocity(WheelPhys, BrakeTorque)

    Link.IsBraking = true
end

do -- Gear Shifting ------------------------------------
    local Sounds = Utilities.Sounds

    -- Handles gearing for automatic gearboxes. 0 = Neutral, 1 = Drive, 2 = Reverse
    function ENT:ChangeDrive(Value)
        Value = Clamp(floor(Value), 0, 2)

        if self.Drive == Value then return end

        self.Drive = Value

        self:ChangeGear(Value == 2 and self.GearCount or Value)
    end

    function ENT:ChangeGear(Value)
        Value = Clamp(floor(Value), self.MinGear, self.GearCount)

        if self.Gear == Value then return end

        self.Gear           = Value
        self.InGear         = false
        self.GearRatio      = self.Gears[Value] * self.FinalDrive
        self.ChangeFinished = Clock.CurTime + self.SwitchTime

        local SoundPath  = self.SoundPath

        if SoundPath ~= "" then
            local Pitch = self.SoundPitch and Clamp(self.SoundPitch * 100, 0, 255) or 100
            local Volume = self.SoundVolume or 0.5

            Sounds.SendSound(self, SoundPath, 70, Pitch, Volume)
        end

        WireLib.TriggerOutput(self, "Current Gear", Value)

        local Ratio = ACF.ConvertGearRatio(self.GearRatio, self.GearboxLegacyRatio)
        WireLib.TriggerOutput(self, "Ratio", Ratio)
    end
end ----------------------------------------------------

do -- Movement -----------------------------------------
    local Tick = TickInterval()

    local function GetRotationalInertia(Link, Wheel)
        local Phys = ENTITY.GetPhysicsObject(Wheel)
        if not Phys then return end

        local Inertia = PHYSOBJ.GetInertia(Phys)
        VECTOR.Mul(Inertia, Link.Axis)
        return VECTOR.Length(Inertia)
    end

    function ENT:Calc(InputRPM, InputInertia)
        local SelfTbl = ENTITY.GetTable(self)
        if SelfTbl.Disabled then return 0 end

        local Now = Clock.CurTime

        if SelfTbl.LastActive == Now then return SelfTbl.TorqueOutput end

        if SelfTbl.ChangeFinished < Now then
            SelfTbl.InGear = true
        end

        if SelfTbl.CalcTick == Now then
            -- Inertia-weighted average of RPM from all engines this tick
            local TotalInertia = SelfTbl.CalcInertia + InputInertia

            if TotalInertia > 0 then
                SelfTbl.CalcRPM = (SelfTbl.CalcRPM * SelfTbl.CalcInertia + InputRPM * InputInertia) / TotalInertia
            end

            SelfTbl.CalcInertia = TotalInertia
            return SelfTbl.TorqueOutput
        end

        -- First Calc call this tick: seed the averager and compute fresh
        SelfTbl.CalcTick    = Now
        SelfTbl.CalcRPM     = InputRPM
        SelfTbl.CalcInertia = InputInertia

        local BoxPhys = ENTITY.GetPhysicsObject(ENTITY.GetAncestor(self))
        local Gear = SelfTbl.Gear

        -- Shift-completion gate (Automatic only)
        if SelfTbl.ChangeFinished > 0 and SelfTbl.ChangeFinished <= Now then
            SelfTbl.InGear         = true
            SelfTbl.ChangeFinished = 0
        end

        if SelfTbl.CVT and Gear == 1 then
            local Gears = SelfTbl.Gears

            if SelfTbl.CVTRatio > 0 then
                Gears[1] = SelfTbl.CVTRatio
            else
                local MinRPM  = SelfTbl.MinRPM
                Gears[1] = 1 / Clamp((InputRPM - MinRPM) / (SelfTbl.MaxRPM - MinRPM), 0.05, 1)
            end

            local GearRatio = Gears[1] * SelfTbl.FinalDrive
            SelfTbl.GearRatio = GearRatio

            if SelfTbl.LastRatio ~= GearRatio then
                SelfTbl.LastRatio = GearRatio
                local Ratio = ACF.ConvertGearRatio(GearRatio, SelfTbl.GearboxLegacyRatio)
                WireLib.TriggerOutput(self, "Ratio", Ratio)
            end
        end

        if SelfTbl.Automatic and SelfTbl.Drive == 1 and SelfTbl.InGear then
            local PhysVel = BoxPhys:GetVelocity():Length()

            if not SelfTbl.Hold and Gear ~= SelfTbl.MaxGear and PhysVel > (SelfTbl.ShiftPoints[Gear] * SelfTbl.ShiftScale) then
                self:ChangeGear(Gear + 1)
            elseif PhysVel < (SelfTbl.ShiftPoints[Gear - 1] * SelfTbl.ShiftScale) then
                self:ChangeGear(Gear - 1)
            end
        end

        local TorqueOutput = 0
        local TotalReqTq = 0

        local LClutch = SelfTbl.LClutch
        local RClutch = SelfTbl.RClutch
        local ChassisAV = GetChassisAngleVelocity(self)
        local GearRatio = SelfTbl.GearRatio
        local LMult, RMult = 1, 1

        if GearRatio == 0 then
            SelfTbl.TotalReqTq   = 0
            SelfTbl.TorqueOutput = 0
            SelfTbl.TotalRatio   = 0
            SelfTbl.DownstreamInertia = 0
            SelfTbl.Load         = 0
            return 0
        end

        -- Inputs scaled for downstream (divide RPM, multiply inertia)
        local ScaledRPM     = InputRPM / GearRatio
        local ScaledInertia = InputInertia * GearRatio

        local DoubleDiff = SelfTbl.DoubleDiff
        local SteerRate  = SelfTbl.SteerRate

         -- DoubleDiff steer low-pass filter
        if DoubleDiff then
            local SteerRateFiltered = SelfTbl.SteerRateFiltered or 0

            -- First order low-pass
            SteerRateFiltered = SteerRateFiltered + (SteerRate - SteerRateFiltered) * Tick / (0.04 + Tick)
            SelfTbl.SteerRateFiltered = SteerRateFiltered

            local Rate = SteerRateFiltered * 2
            LMult = min(0, Rate) + 1
            RMult = -max(0, Rate) + 1
        end

        local MeasuredRPMSum = 0
        local MeasuredCount = 0
        local DownstreamInertia = 0
        local TotalRatioSum = 0

        -- Downstream gearboxes
        for Ent, Link in pairs(SelfTbl.GearboxOut) do
            local EntTbl = ENTITY.GetTable(Ent)
            local Clutch = Link.Side == 0 and LClutch or RClutch

            if not Ent.Disabled and Clutch > 0 then
                local SubRPM = Ent:Calc(ScaledRPM, ScaledInertia)
                local Req  = (SubRPM / GearRatio) * Clutch
                Link.ReqTq = Req
                TotalReqTq = TotalReqTq + Req
            else
                Link.ReqTq = 0
            end

            MeasuredRPMSum    = MeasuredRPMSum + (EntTbl.MeasuredRPM or ScaledRPM) * GearRatio
            MeasuredCount     = MeasuredCount + 1
            DownstreamInertia = DownstreamInertia + (EntTbl.DownstreamInertia or 0)
            TotalRatioSum     = TotalRatioSum + abs(GearRatio) * (EntTbl.TotalRatio or 1)
        end

        -- Wheels
        for Wheel, Link in pairs(SelfTbl.Wheels) do
            Link.ReqTq = 0

            if GearRatio ~= 0 then
                local WheelRPM = CalcWheel(self, Link, Wheel, ChassisAV)
                local Clutch = Link.Side == 0 and LClutch or RClutch

                if SelfTbl.InGear and Clutch > 0 then
                    local Multiplier = 1

                    if DoubleDiff and SteerRate ~= 0 then
                        -- This actually controls the RPM of the wheels, so the steering rate is correct
                        -- I have to do it this way so the linter wont complain about any scope pyramids (very conservative value given to them)
                        Multiplier = Link.Side == 0 and LMult or RMult
                    end

                    local Target = InputRPM * Multiplier
                    local ReqTq = (Target - WheelRPM) * InputInertia * Clutch

                    -- TODO: Real compression brake torque would go here instead.
                    Link.ReqTq = max(ReqTq, -abs(ReqTq) * 0.05) -- Boomer, 0.05 is a magic number
                    TotalReqTq = TotalReqTq + Link.ReqTq
                end

                MeasuredRPMSum = MeasuredRPMSum + WheelRPM
                MeasuredCount  = MeasuredCount + 1
                DownstreamInertia = DownstreamInertia + GetRotationalInertia(Link, Wheel)
            else
                MeasuredRPMSum = 0
                MeasuredCount = 0
                DownstreamInertia = 0
            end
        end

        -- Effectors
        for Effector, Link in pairs(SelfTbl.Effectors) do
            local Clutch = Link.Side == 0 and LClutch or RClutch

            Link.ReqTq = 0

            if not Effector.Disabled then
                local Req  = abs(Effector:Calc(ScaledRPM, ScaledInertia) / GearRatio) * Clutch
                Link.ReqTq = Req
                TotalReqTq = TotalReqTq + Req
            end
        end

        SelfTbl.MeasuredRPM = MeasuredCount > 0 and (MeasuredRPMSum / MeasuredCount) or InputRPM
        SelfTbl.DownstreamInertia = DownstreamInertia
        SelfTbl.TotalRatio = GearRatio ~= 0 and (abs(GearRatio) * max(TotalRatioSum, 1)) or 0
        SelfTbl.Load = GearRatio == 0 and 0 or ((LClutch + RClutch) * 0.5)

        SelfTbl.TotalReqTq = TotalReqTq
        TorqueOutput = Clamp(TotalReqTq, -SelfTbl.MaxTorque, SelfTbl.MaxTorque)
        SelfTbl.TorqueOutput = TorqueOutput

        self:UpdateOverlay()

        WireLib.TriggerOutput(self, "Output Torque", TorqueOutput)

        return TorqueOutput
    end

    function ENT:DistributeTorque(Torque, DeltaTime, MassRatio, FlyRPM)
        local SelfTbl = ENTITY.GetTable(self)
        if SelfTbl.Disabled or Torque == 0 then return end

        local GearRatio  = SelfTbl.GearRatio
        local TotalReqTq = SelfTbl.TotalReqTq

        if GearRatio == 0 then return end

        -- Internal torque loss from damage
        local Health = SelfTbl.ACF.Health
        local MaxHP  = SelfTbl.ACF.MaxHealth
        local Loss   = Clamp(Health / MaxHP, 0.4, 1)

        SelfTbl.Loss = Loss

        -- Automatic torque-converter slip penalty
        local Slop = SelfTbl.Automatic and 0.9 or 1.0
        local Sign = Torque > 0 and 1 or -1

        local ReactTq = 0
        -- AvailTq: per-unit factor; ReqTq × AvailTq = actual torque applied
        -- local AvailTq = min(abs(Torque) / TotalReqTq, 1) * GearRatio * Sign * Loss * Slop
        local AvailTq = min(abs(Torque) / max(abs(TotalReqTq), 1e-6), 1) * GearRatio * Sign * Loss * Slop

        -- Direction forwarded to effectors so reversible props work
        local Direction = SelfTbl.Drive == 2 and -1 or 1

        -- Transfer torque to our entities
        -- Downstream gearboxes
        for Ent, Link in pairs(SelfTbl.GearboxOut) do
            Link:TransferGearbox(Ent, Link.ReqTq * AvailTq, DeltaTime, MassRatio, FlyRPM)
        end

        -- Effectors
        for Effector, Link in pairs(SelfTbl.Effectors) do
            Link:TransferEffector(Effector, Link.ReqTq * AvailTq, DeltaTime, MassRatio, FlyRPM, Direction)
        end

        -- Apply torque to them wheels 
        for Wheel, Link in pairs(SelfTbl.Wheels) do
            local WheelTorque = Link.ReqTq * AvailTq

            Link:TransferWheel(Wheel, WheelTorque, DeltaTime)
            ReactTq = ReactTq + WheelTorque
        end

        -- Chassis reaction torque: Newton's third law makes the body twist opposite to the drive direction when power is applied
        if ReactTq ~= 0 then
            local BoxPhys = ENTITY.GetPhysicsObject(ENTITY.GetAncestor(self))

            if IsPhysObjValid(BoxPhys) then
                local RightDir = ENTITY.GetRight(self)

                VECTOR.Mul(RightDir, Clamp(2 * deg(ReactTq * MassRatio) * DeltaTime, -500000, 500000))
                PHYSOBJ.ApplyTorqueCenter(BoxPhys, RightDir)
            end
        end

        SelfTbl.BrakeTick = Clock.CurTime
        self:ApplyBrakes()
    end

    function ENT:Act(Torque, DeltaTime, MassRatio, FlyRPM)
        local SelfTbl = ENTITY.GetTable(self)
        if SelfTbl.Disabled then return end

        if Torque == 0 then
            SelfTbl.LastActive = Clock.CurTime
            return
        end

        local EngineCount = table.Count(SelfTbl.Engines)
        local GearboxCount = table.Count(SelfTbl.GearboxIn)

        -- Single-engine fast path: distribute immediately, no deferred timer
        if EngineCount + GearboxCount <= 1 then
            self:DistributeTorque(Torque, DeltaTime, MassRatio, FlyRPM)
            return
        end

        -- Multiple engines: Accumulates their torque and then distribute
        local Now = Clock.CurTime

        if SelfTbl.ActTick ~= Now then
            SelfTbl.ActTick        = Now
            SelfTbl.AccumTorque    = 0
            SelfTbl.ActDt          = DeltaTime
            SelfTbl.ActMassRatio   = MassRatio
            SelfTbl.ActFlyRPM      = FlyRPM
            SelfTbl.ActDistributed = false
        end

        SelfTbl.AccumTorque = SelfTbl.AccumTorque + Torque

        if not SelfTbl.ActDistributed then
            SelfTbl.ActDistributed = true
            -- Deferred so all engines complete their Act calls before distribution
            timer.Simple(0, function()
                if IsEntityValid(self) then
                    self:DistributeTorque(SelfTbl.AccumTorque, SelfTbl.ActDt, SelfTbl.ActMassRatio, SelfTbl.ActFlyRPM)
                end
            end)
        end

        SelfTbl.LastActive = Clock.CurTime
    end
end ----------------------------------------------------

do -- Braking ------------------------------------------
    function ENT:ApplyBrakes()
        local SelfTbl = ENTITY.GetTable(self)

        if SelfTbl.Disabled then return end -- Illegal brakes man
        if not SelfTbl.Braking then return end -- Kills the whole thing if its not supposed to be running
        if not next(SelfTbl.Wheels) then return end -- No brakes for the non-wheel users
        if SelfTbl.LastBrake == Clock.CurTime then return end -- Don't run this twice in a tick

        local BoxPhys = ENTITY.GetPhysicsObject(ENTITY.GetAncestor(self))
        if not IsPhysObjValid(BoxPhys) then return end -- Fixes an issue I had where deleting a contraption while driving it threw an error

        local DeltaTime  = Clock.DeltaTime
        local Loss       = SelfTbl.Loss
        local LBrake     = SelfTbl.LBrake
        local RBrake     = SelfTbl.RBrake
        local MaxBrakeTq = SelfTbl.MaxTorque * 2
        local ChassisAV  = GetChassisAngleVelocity(self)
        SelfTbl.Braking  = false

        -- Calculate brake power for every wheel linked to our gearbox
        for Wheel, Link in pairs(SelfTbl.Wheels) do
            if not Link.IsBraking then
                local Brake = Link.Side == 0 and LBrake or RBrake

                CalcWheel(self, Link, Wheel, ChassisAV)  -- Updating the link velocity
                BrakeWheel(Link, Wheel, Brake, MaxBrakeTq, DeltaTime, ChassisAV, Loss)

                if Link.IsBraking then SelfTbl.Braking = true end
            end
            -- Reset per-tick IsBraking flag so it's fresh for the next Calc pass
            Link.IsBraking = false
        end

        SelfTbl.LastBrake = Clock.CurTime

        -- Rinse and repeat as long as we're still pressing to brake
        timer.Simple(DeltaTime, function()
            if not IsEntityValid(self) then return end

            self:ApplyBrakes()
        end)
    end
end ----------------------------------------------------

do -- Inputs -------------------------------------------
    local function SetCanApplyBrakes(Gearbox)
        local CanApply = Gearbox.LBrake ~= 0 or Gearbox.RBrake ~= 0

        if CanApply ~= Gearbox.Braking then
            Gearbox.Braking = CanApply

            Gearbox:ApplyBrakes()
        end
    end

    ACF.AddInputAction("acf_gearbox_custom", "Gear", function(Entity, Value)
        if Entity.Automatic then
            Entity:ChangeDrive(Value)
        else
            Entity:ChangeGear(Value)
        end
    end)

    ACF.AddInputAction("acf_gearbox_custom", "Gear Up", function(Entity, Value)
        if not tobool(Value) then return end

        if Entity.Automatic then
            Entity:ChangeDrive(Entity.Drive + 1)
        else
            Entity:ChangeGear(Entity.Gear + 1)
        end
    end)

    ACF.AddInputAction("acf_gearbox_custom", "Gear Down", function(Entity, Value)
        if not tobool(Value) then return end

        if Entity.Automatic then
            Entity:ChangeDrive(Entity.Drive - 1)
        else
            Entity:ChangeGear(Entity.Gear - 1)
        end
    end)

    ACF.AddInputAction("acf_gearbox_custom", "Clutch", function(Entity, Value)
        Entity.LClutch = Clamp(1 - Value, 0, 1)
        Entity.RClutch = Clamp(1 - Value, 0, 1)
    end)

    ACF.AddInputAction("acf_gearbox_custom", "Left Clutch", function(Entity, Value)
        if not Entity.DualClutch then return end

        Entity.LClutch = Clamp(1 - Value, 0, 1)
    end)

    ACF.AddInputAction("acf_gearbox_custom", "Right Clutch", function(Entity, Value)
        if not Entity.DualClutch then return end

        Entity.RClutch = Clamp(1 - Value, 0, 1)
    end)

    ACF.AddInputAction("acf_gearbox_custom", "Brake", function(Entity, Value)
        Entity.LBrake = Clamp(Value, 0, 1)
        Entity.RBrake = Clamp(Value, 0, 1)

        SetCanApplyBrakes(Entity)
    end)

    ACF.AddInputAction("acf_gearbox_custom", "Left Brake", function(Entity, Value)
        if not Entity.DualClutch then return end

        Entity.LBrake = Clamp(Value, 0, 1)

        SetCanApplyBrakes(Entity)
    end)

    ACF.AddInputAction("acf_gearbox_custom", "Right Brake", function(Entity, Value)
        if not Entity.DualClutch then return end

        Entity.RBrake = Clamp(Value, 0, 1)

        SetCanApplyBrakes(Entity)
    end)

    ACF.AddInputAction("acf_gearbox_custom", "CVT Ratio", function(Entity, Value)
        if not Entity.CVT then return end

        if Entity.GearboxLegacyRatio and Value ~= 0 then Value = 1 / Value end
        Entity.CVTRatio = Value ~= 0 and Clamp(Value, ACF.MinCVTRatio, ACF.MaxCVTRatio) or Value
    end)

    ACF.AddInputAction("acf_gearbox_custom", "Steer Rate", function(Entity, Value)
        if not Entity.DoubleDiff then return end

        Entity.SteerRate = Clamp(Value, -1, 1)
    end)

    ACF.AddInputAction("acf_gearbox_custom", "Hold Gear", function(Entity, Value)
        if not Entity.Automatic then return end

        Entity.Hold = tobool(Value)
    end)

    ACF.AddInputAction("acf_gearbox_custom", "Shift Speed Scale", function(Entity, Value)
        if not Entity.Automatic then return end

        Entity.ShiftScale = Clamp(Value, 0.1, 1.5)
    end)
end ----------------------------------------------------

--===============================================================================================--
-- Meta Funcs (I probably should move this elsewhere...)
--===============================================================================================--
do -- Miscellaneous ------------------------------------
    function ENT:Enable()
        if self.Automatic then
            self:ChangeDrive(self.OldGear)
        else
            self:ChangeGear(self.OldGear)
        end

        self.OldGear = nil

        self:UpdateOverlay()
    end

    function ENT:Disable()
        self.OldGear = self.Automatic and self.Drive or self.Gear

        if self.Automatic then
            self:ChangeDrive(0)
        else
            self:ChangeGear(0)
        end

        self:UpdateOverlay()
    end

    -- Prevent people from changing bodygroup
    function ENT:CanProperty(_, Property)
        return Property ~= "bodygroups"
    end

    -- Remove-only teardown. Captured by AutoRegisterV2 as OrigOnRemove; the generated OnRemove runs
    -- ACF_OnEntityLast (which fires the gearbox class' OnLast) + WireLib cleanup around this.
    function ENT:OnRemove(IsFullUpdate)
        if IsFullUpdate then return end

        for Engine in pairs(self.Engines) do
            self:Unlink(Engine)
        end

        for Wheel in pairs(self.Wheels) do
            self:Unlink(Wheel)
        end

        for Gearbox in pairs(self.GearboxIn) do
            Gearbox:Unlink(self)
        end

        for Gearbox in pairs(self.GearboxOut) do
            self:Unlink(Gearbox)
        end

        for Effector in pairs(self.Effectors) do
            self:Unlink(Effector)
        end

        timer.Remove("ACF Gearbox Clock " .. self:EntIndex())
    end
end ----------------------------------------------------
