AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")

include("shared.lua")

-- Shamefully stolen from acf_baseplate
ENT.ACF_UserWeighable             = false
ENT.ACF_HealthUpdatesWireOverlay  = true

include("modules/spawning.lua")
include("modules/overlay.lua")