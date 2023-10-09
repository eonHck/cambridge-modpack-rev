require 'funcs'

local MarathonA1GameRev = require 'tetris.modes.marathon_a1_rev'
local Piece = require 'tetris.components.piece_rev'

local History4RollsRandomizer = require 'tetris.randomizers.history_4rolls'

local SurvivalA1GameRev = MarathonA1GameRev:extend()

SurvivalA1GameRev.name = "Survival A1 Rev"
SurvivalA1GameRev.hash = "SurvivalA1 Rev"
SurvivalA1GameRev.tagline = "A constant high-speed marathon!"

function SurvivalA1GameRev:getGravity()
	return 20
end

return SurvivalA1GameRev
