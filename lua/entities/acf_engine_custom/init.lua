AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")

include("shared.lua")

local ACF = ACF
local Mobility = ACF.Mobility
local MobilityObj = Mobility.Objects
local MaxDistance = ACF.MobilityLinkDistance * ACF.MobilityLinkDistance

local ENTITY  = FindMetaTable("Entity")
local PHYSOBJ = FindMetaTable("PhysObj")

local IsEntityValid	 = ACF.Optimizations.IsEntityValid
local IsPhysObjValid = ACF.Optimizations.IsPhysObjValid

