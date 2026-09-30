local ACF = ACF
local Sounds = ACF.SoundToolSupport

print("bitch")
PrintTable({Sounds})
Sounds.acf_engine_custom = {
	GetSound = function(Ent)
		return {
			Sound  = Ent.SoundPath,
			Pitch  = Ent.SoundPitch,
			Volume = Ent.SoundVolume
		}
	end,
	SetSound = function(Ent, SoundData)
		local Sound = SoundData.Sound:Trim():lower()

		Ent.SoundPath   = Sound
		Ent.SoundPitch  = SoundData.Pitch
		Ent.SoundVolume = SoundData.Volume

		Ent:UpdateSound()
	end,
	ResetSound = function(Ent)
		Ent.SoundPath   = Ent.DefaultSound
		Ent.SoundPitch  = 1
		Ent.SoundVolume = 1

		Ent:UpdateSound()
	end
}

Sounds.acf_gearbox_custom = {
	GetSound = function(Ent)
		return {
			Sound  = Ent.SoundPath,
			Pitch  = Ent.SoundPitch,
			Volume = Ent.SoundVolume,
		}
	end,
	SetSound = function(Ent, SoundData)
		Ent.SoundPath   = SoundData.Sound
		Ent.SoundPitch  = SoundData.Pitch
		Ent.SoundVolume = SoundData.Volume
	end,
	ResetSound = function(Ent)
		Ent.SoundPath   = Ent.DefaultSound
		Ent.SoundPitch  = nil
		Ent.SoundVolume = nil
	end
}