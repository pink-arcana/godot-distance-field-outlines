class_name DefaultSettings
extends Object

const EffectDefaults := {
	DFOutlineSettings.EffectID.RAW_DISTANCE_FIELD :  {
			"outline_width" : 2048,
			"outline_color": Color.WHITE,
			"background_color": Color.BLACK,
		},
	DFOutlineSettings.EffectID.STEPPED_DISTANCE_FIELD :  {
			"outline_width" : 2048,
			"outline_color": Color.ORANGE,
			"background_color": Color.BLACK,
			"depth_fade_mode": DFOutlineSettings.DepthFadeMode.NONE,
		},
	DFOutlineSettings.EffectID.PADDING :  {
			"outline_width" : 10,
		},
	DFOutlineSettings.EffectID.INVERTED :  {
			"outline_width" : 10,
			"outline_color": Color.BLACK,
			"use_background_color" : false,
		},
	DFOutlineSettings.EffectID.SKETCH :  {
			"outline_width" : 32,
			"depth_fade_mode": DFOutlineSettings.DepthFadeMode.NONE,
		},
	DFOutlineSettings.EffectID.NEON_GLOW :  {
			"outline_width" : 32,
			"use_background_color" : true,
			"outline_color": Color.HOT_PINK,
			"background_color": Color.BLACK,
			"depth_fade_mode": DFOutlineSettings.DepthFadeMode.NONE,
		},
	DFOutlineSettings.EffectID.RAINBOW_ANIMATION :  {
			"outline_width" : 512,
			"use_background_color" : true,
			"background_color": Color.BLACK,
			"depth_fade_mode": DFOutlineSettings.DepthFadeMode.NONE,
		},
}
