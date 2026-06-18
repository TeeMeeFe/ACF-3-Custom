AddCSLuaFile("shared.lua")
AddCSLuaFile("cl_init.lua")

include("shared.lua")

-- Shamefully stolen from acf_baseplate
ENT.ACF_UserWeighable             = false
--ENT.ACF_KillableButIndestructible = false
ENT.ACF_HealthUpdatesWireOverlay  = true

include("modules/spawning.lua")