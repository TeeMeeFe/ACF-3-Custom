local ACF  = ACF
local deg  = math.deg
local acos = math.acos
local max  = math.max

-- Because of the fact that one line below checks for an specific class, it means that it wont work for our custom
-- gearboxes, so we simply strip that function from util_sh.lua and push our own changes instead

--- Determines the combined deviations of the driveshaft between two entities
--- A return value of zero means that both entities are facing each other perfectly.
local function ACF_DetermineDriveshaftAngle(InputEntity, Input, OutputEntity, Output)
    -- Gearbox -> gearbox connections use Link objects; which contain Source, Origin, and Axis.
    -- Beyond that, everything works like normal; so we can just populate Output/OutputEntity
    -- from the Link object.
    -- TODO: Link object maybe should use LocalPlane instead of creating it each time? This isn't
    -- that hot of a function given it runs infrequently (i think), but it's still a bit of a waste
    if Output == nil then
        local Link = OutputEntity

        Output = ACF.LocalPlane(Link.Origin, Link.OutDirection)
        OutputEntity = Link.Source
    end

    -- For the entity sending power, this is the direction of a "straight" shaft
    local OP, OutputWorldDir = Output:ApplyTo(OutputEntity)
    debugoverlay.Line(OP, OP + (OutputWorldDir * 200), 5, Color(20, 255, 20))

    -- Gearbox -> prop connections mean that Input will be nil, because props don't have a power input
    -- like gearboxes do. So this just switches back to the old way of checking in one direction.
    if Input == nil then
        if InputEntity:GetClass() ~= "acf_gearbox_custom" then
            local Degrees = deg(acos((InputEntity:GetPos() - OP):GetNormalized():Dot(OutputWorldDir)))
            return Degrees
        else
            error("Input == nil AND InputEntity != prop_physics!")
        end
    end

    -- This handles either gearbox -> gearbox or engine -> gearbox, depending on if Output == nil
    -- This will check both directions.

    -- For the entity receiving power, this is the direction of a "straight" shaft
    local IP, InputWorldDir = Input:ApplyTo(InputEntity)
    debugoverlay.Line(IP, IP + (InputWorldDir * 200), 5, Color(255, 20, 20))

    -- For the entity sending power, the deviation between the shaft and what it considers "straight"
    local OutToIn = deg(acos((OP - IP):GetNormalized():Dot(InputWorldDir)))

    -- For the entity receiving power, the deviation between the shaft and what it considers "straight"
    local InToOut = deg(acos((IP - OP):GetNormalized():Dot(OutputWorldDir)))

    -- The max of the deviations
    return max(OutToIn, InToOut)
end

function ACF.IsCustomDriveshaftAngleExcessive(InputEntity, Input, OutputEntity, Output)
    local Determined = ACF_DetermineDriveshaftAngle(InputEntity, Input, OutputEntity, Output)
    return Determined > ACF.MaxDriveshaftAngle, Determined
end