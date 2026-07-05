AddCSLuaFile("shared.lua")
AddCSLuaFile("cl_init.lua")

include("shared.lua")

-- Shamefully stolen from acf_baseplate
ENT.ACF_UserWeighable             = false
ENT.ACF_HealthUpdatesWireOverlay  = true

include("modules/linking.lua")
include("modules/spawning.lua")
include("modules/state.lua")
include("modules/thermals.lua")
include("modules/cfw.lua")
include("modules/sounds.lua")
include("modules/overlay.lua")
include("modules/networking.lua")