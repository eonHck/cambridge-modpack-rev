local Object = require 'libs.classic'
require 'funcs'

local playedReadySE = false
local playedGoSE = false

local Grid = require 'tetris.components.grid_rev'
local Randomizer = require 'tetris.randomizers.randomizer'
local BagRandomizer = require 'tetris.randomizers.bag'
local binser = require 'libs.binser'

local GameModeRev = Object:extend()

GameModeRev.name = ""
GameModeRev.hash = ""
GameModeRev.tagline = ""
GameModeRev.rollOpacityFunction = function(age) return 0 end

function GameModeRev:new()
	self.replay_inputs = {}
	self.random_low, self.random_high = love.math.getRandomSeed()
	self.random_state = love.math.getRandomState()
	self.save_replay = config.gamesettings.save_replay == 1
	
	self.grid = Grid(10, 24)
	self.randomizer = Randomizer()
	self.piece = nil
	self.ready_frames = 100
	self.frames = 0
	self.game_over_frames = 0
	self.score = 0
	self.level = 0
	self.lines = 0
	self.squares = 0
	self.drop_bonus = 0
	self.are = 0
	self.lcd = 0
	self.das = { direction = "none", frames = -1 }
	self.move = "none"
	self.prev_inputs = {}
	self.next_queue = {}
	self.game_over = false
	self.clear = false
	self.completed = false
	-- configurable parameters
	self.lock_drop = false
	self.lock_hard_drop = false
	self.instant_hard_drop = false
	self.instant_soft_drop = true
	self.enable_hold = false
	self.enable_hard_drop = true
	self.next_queue_length = 1
	self.additive_gravity = true
	self.classic_lock = false
	self.draw_section_times = false
	self.draw_secondary_section_times = false
	self.big_mode = false
	self.irs = true
	self.ihs = true
	self.square_mode = false
	self.immobile_spin_bonus = false
	self.rpc_details = "In game"
	self.SGnames = {
		"9", "8", "7", "6", "5", "4", "3", "2", "1",
		"S1", "S2", "S3", "S4", "S5", "S6", "S7", "S8", "S9",
		"GM"
	}
	-- variables related to configurable parameters
	self.drop_locked = false
	self.hard_drop_locked = false
	self.lock_on_soft_drop = false
	self.lock_on_hard_drop = false
	self.cleared_block_table = {}
	self.last_lcd = 0
	self.used_randomizer = nil
	self.hold_queue = nil
	self.held = false
	self.section_start_time = 0
	self.section_times = { [0] = 0 }
	self.secondary_section_times = { [0] = 0 }
end

function GameModeRev:getARR() return 1 end
function GameModeRev:getDropSpeed() return 1 end
function GameModeRev:getARE() return 25 end
function GameModeRev:getLineARE() return 25 end
function GameModeRev:getLockDelay() return 30 end
function GameModeRev:getLineClearDelay() return 40 end
function GameModeRev:getDasLimit() return 15 end
function GameModeRev:getDasCutDelay() return 0 end
function GameModeRev:getGravity() return 1/64 end

function GameModeRev:getNextPiece(ruleset)
	local shape = self.used_randomizer:nextPiece()
	return {
		skin = self:getSkin(),
		shape = shape,
		orientation = ruleset:getDefaultOrientation(shape),
	}
end

function GameModeRev:getSkin()
	return "2tie"
end

function GameModeRev:initialize(ruleset)
	-- generate next queue
	self.used_randomizer = (
		table.equalvalues(
			table.keys(ruleset.colourscheme),
			self.randomizer.possible_pieces
		) and
		self.randomizer or BagRandomizer(table.keys(ruleset.colourscheme))
	)
	self.ruleset = ruleset
	for i = 1, math.max(self.next_queue_length, 1) do
		table.insert(self.next_queue, self:getNextPiece(ruleset))
	end
	self.lock_on_soft_drop = ({ruleset.softdrop_lock, self.instant_soft_drop, false, true })[config.gamesettings.manlock]
	self.lock_on_hard_drop = ({ruleset.harddrop_lock, self.instant_hard_drop, true,  false})[config.gamesettings.manlock]
end

function GameModeRev:saveReplay()
	-- Save replay.
	local replay = {}
	replay["inputs"] = self.replay_inputs
	replay["random_low"] = self.random_low
	replay["random_high"] = self.random_high
	replay["random_state"] = self.random_state
	replay["mode"] = self.name
	replay["ruleset"] = self.ruleset.name
	replay["timer"] = self.frames
	replay["score"] = self.score
	replay["level"] = self.level
	replay["lines"] = self.lines
	replay["gamesettings"] = config.gamesettings
	replay["secret_inputs"] = self.secret_inputs
	replay["delayed_auto_shift"] = config.das
	replay["auto_repeat_rate"] = config.arr
	replay["das_cut_delay"] = config.dcd
	replay["timestamp"] = os.time()
	replay["pause_count"] = self.pause_count
	replay["pause_time"] = self.pause_time
	if love.filesystem.getInfo("replays") == nil then
		love.filesystem.createDirectory("replays")
	end
	local init_name = string.format("replays/%s.crp", os.date("%Y-%m-%d_%H-%M-%S"))
	local replay_name = init_name
	local replay_number = 0
	while true do
		if love.filesystem.getInfo(replay_name, "file") then
			replay_number = replay_number + 1
			replay_name = string.format("%s (%d)", init_name, replay_number)
		else
			break
		end
	end
	love.filesystem.write(replay_name, binser.serialize(replay))
end

function GameModeRev:addReplayInput(inputs)
	-- check if inputs have changed since last frame
	if not equals(self.prev_inputs, inputs) then
		-- insert new inputs into replay inputs table
		local new_inputs = {}
		new_inputs["inputs"] = {}
		new_inputs["frames"] = 1
		for key, value in pairs(inputs) do
			new_inputs["inputs"][key] = value
		end
		self.replay_inputs[#self.replay_inputs + 1] = new_inputs
	else
		-- add 1 to input frame counter
		self.replay_inputs[#self.replay_inputs]["frames"] = self.replay_inputs[#self.replay_inputs]["frames"] + 1
	end
end

function GameModeRev:update(inputs, ruleset)
	if self.game_over or self.completed then
		if self.save_replay and self.game_over_frames == 0 then
			self:saveReplay()

			-- ensure replays are only saved once per game, incase self.game_over_frames == 0 for longer than one frame
			self.save_replay = false
		end
		self.game_over_frames = self.game_over_frames + 1
		return
	end

	if config.gamesettings.diagonal_input == 2 then
		if inputs["left"] or inputs["right"] then
			inputs["up"] = false
			inputs["down"] = false
		elseif inputs["down"] then
			inputs["up"] = false
		end
	end

	if self.save_replay then self:addReplayInput(inputs) end

	-- advance one frame
	if self:advanceOneFrame(inputs, ruleset) == false then return end

	self:chargeDAS(inputs, self:getDasLimit(), self:getARR())

	-- set attempt flags
	if inputs["left"] or inputs["right"] then self:onAttemptPieceMove(self.piece, self.grid) end
	if (
		inputs["rotate_left"] or inputs["rotate_right"] or
		inputs["rotate_left2"] or inputs["rotate_right2"] or
		inputs["rotate_180"]
	) then
		self:onAttemptPieceRotate(self.piece, self.grid)
	end
	
	if self.piece == nil then
		self:processDelays(inputs, ruleset)
	else
		-- perform active frame actions such as fading out the next queue
		self:whilePieceActive()

		if self.enable_hold and inputs["hold"] == true and self.held == false and self.prev_inputs["hold"] == false then
			self:hold(inputs, ruleset)
			self.prev_inputs = inputs
			return
		end

		if (self.lock_drop or (
			not ruleset.are or self:getARE() == 0
		)) and inputs["up"] ~= true then
			self.drop_locked = false
		end

		if (self.lock_hard_drop or (
			not ruleset.are or self:getARE() == 0
		)) and inputs["down"] ~= true then
			self.hard_drop_locked = false
		end

		-- diff vars to use in checks
		local piece_y = self.piece.position.y
		local piece_x = self.piece.position.x
		local piece_rot = self.piece.rotation

		ruleset:processPiece(
			inputs, self.piece, self.grid, self:getGravity(), self.prev_inputs,
			(
				inputs.up and self.lock_on_hard_drop and not self.hard_drop_locked
			) and "none" or self.move,
			self:getLockDelay(), self:getDropSpeed(),
			self.drop_locked, self.hard_drop_locked,
			self.enable_hard_drop, self.additive_gravity, self.classic_lock
		)

		local piece_dy = self.piece.position.y - piece_y
		local piece_dx = self.piece.position.x - piece_x
		local piece_drot = self.piece.rotation - piece_rot

		-- das cut
		if (
			(piece_dy ~= 0 and (inputs.up or inputs.down)) or
			(piece_drot ~= 0 and (
				inputs.rotate_left or inputs.rotate_right or
				inputs.rotate_left2 or inputs.rotate_right2 or
				inputs.rotate_180
			))
		) then
			self:dasCut()
		end

		if (piece_dx ~= 0) then
			self.piece.last_rotated = false
			self:onPieceMove(self.piece, self.grid, piece_dx)
		end
		if (piece_dy ~= 0) then
			self.piece.last_rotated = false
			self:onPieceDrop(self.piece, self.grid, piece_dy)
		end
		if (piece_drot ~= 0) then
			self.piece.last_rotated = true
			self:onPieceRotate(self.piece, self.grid, piece_drot)
		end

		if inputs["down"] == true and
			self.piece:isDropBlocked(self.grid) and
			not self.hard_drop_locked then
			self:onHardDrop(piece_dy)
			if self.lock_on_hard_drop then
				self.piece_hard_dropped = true
				self.piece.locked = true
			end
		end

		if inputs["up"] == true then
			if not (
				self.piece:isDropBlocked(self.grid) and
				piece_drot ~= 0
			) then
				self:onSoftDrop(piece_dy)
			end
			if self.piece:isDropBlocked(self.grid) and
				not self.drop_locked and
				self.lock_on_soft_drop
			then
				self.piece.locked = true
				self.piece_soft_locked = true
			end
		end

		if self.piece.locked == true then
			-- spin detection, immobile only for now
			if self.immobile_spin_bonus and
			   self.piece.last_rotated and (
				self.piece:isDropBlocked(self.grid) and
				self.piece:isMoveBlocked(self.grid, { x=-1, y=0 }) and 
				self.piece:isMoveBlocked(self.grid, { x=1, y=0 }) and
				self.piece:isMoveBlocked(self.grid, { x=0, y=-1 })
			) then
				self.piece.spin = true
			end

			self.grid:applyPiece(self.piece)
			
			-- mark squares (can be overridden)
			if self.square_mode then
				self.squares = self.squares + self.grid:markSquares()
			end

			local cleared_row_count = self.grid:getClearedRowCount()
			self:onPieceLock(self.piece, cleared_row_count)
			self:updateScore(self.level, self.drop_bonus, cleared_row_count)

			self.cleared_block_table = self.grid:markClearedRows()
			self.piece = nil
			if self.enable_hold then
				self.held = false
			end

			if cleared_row_count > 0 then
				local row_count_names = {"single","double","triple","quad"}
				playSE("erase",row_count_names[cleared_row_count] or "quad")
				self.lcd = self:getLineClearDelay()
				self.last_lcd = self.lcd
				self.are = (
					ruleset.are and self:getLineARE() or 0
				)
				if self.lcd == 0 then
					self.grid:clearClearedRows()
					self:afterLineClear(cleared_row_count)
					if self.are == 0 then
						self:initializeOrHold(inputs, ruleset)
					end
				end
				self:onLineClear(cleared_row_count)
			else
				if self:getARE() == 0 or not ruleset.are then
					self:initializeOrHold(inputs, ruleset)
				else
					self.are = self:getARE()
				end
			end
		end
	end
	self.prev_inputs = inputs
end

function GameModeRev:updateScore() end

function GameModeRev:advanceOneFrame()
	if self.clear then
		self.completed = true
	elseif self.ready_frames == 0 then
		self.frames = self.frames + 1
	end
end

-- event functions
function GameModeRev:whilePieceActive() end
function GameModeRev:onAttemptPieceMove(piece, grid) end
function GameModeRev:onAttemptPieceRotate(piece, grid) end
function GameModeRev:onPieceMove(piece, grid, dx) end
function GameModeRev:onPieceRotate(piece, grid, drot) end
function GameModeRev:onPieceDrop(piece, grid, dy) end
function GameModeRev:onPieceLock(piece, cleared_row_count) 
	playSE("lock")
end

function GameModeRev:onLineClear(cleared_row_count) end
function GameModeRev:afterLineClear(cleared_row_count) end

function GameModeRev:onPieceEnter() end
function GameModeRev:onHold() end

function GameModeRev:onSoftDrop(dropped_row_count)
	self.drop_bonus = self.drop_bonus + (
		(self.piece.big and 2 or 1) * dropped_row_count
	)
end

function GameModeRev:onHardDrop(dropped_row_count)
	self:onSoftDrop(dropped_row_count * 2)
end

function GameModeRev:onGameOver()
	switchBGM(nil)
	-- pitchBGM(1)
	local alpha = 0
	local animation_length = 120
	if self.game_over_frames < animation_length then
		-- Show field for a bit, then fade out.
		alpha = math.pow(2048, self.game_over_frames/animation_length - 1)
	elseif self.game_over_frames < 2 * animation_length then
		-- Keep field hidden for a short time, then pop it back in (for screenshots).
		alpha = 1
	end
	love.graphics.setColor(0, 0, 0, alpha)
	love.graphics.rectangle(
		"fill", 64, 80,
		16 * self.grid.width, 16 * (self.grid.height - 4)
	)
end

function GameModeRev:onGameComplete()
	self:onGameOver()
end

function GameModeRev:onExit() end

-- DAS functions

function GameModeRev:startRightDAS()
	self.move = "right"
	self.das = { direction = "right", frames = 0 }
	if self:getDasLimit() == 0 then
		self:continueDAS()
	end
end

function GameModeRev:startLeftDAS()
	self.move = "left"
	self.das = { direction = "left", frames = 0 }
	if self:getDasLimit() == 0 then
		self:continueDAS()
	end
end

function GameModeRev:continueDAS()
	local das_frames = self.das.frames + 1
	if das_frames >= self:getDasLimit() then
		if self.das.direction == "left" then
			self.move = (self:getARR() == 0 and "speed" or "") .. "left"
			self.das.frames = self:getDasLimit() - self:getARR()
		elseif self.das.direction == "right" then
			self.move = (self:getARR() == 0 and "speed" or "") .. "right"
			self.das.frames = self:getDasLimit() - self:getARR()
		end
	else
		self.move = "none"
		self.das.frames = das_frames
	end
end

function GameModeRev:stopDAS()
	self.move = "none"
	self.das = { direction = "none", frames = -1 }
end

function GameModeRev:chargeDAS(inputs)
	if config.gamesettings.das_last_key == 2 then
		if inputs["right"] == true and self.das.direction ~= "right" and not self.prev_inputs["right"] then
			self:startRightDAS()
		elseif inputs["left"] == true and self.das.direction ~= "left" and not self.prev_inputs["left"] then
			self:startLeftDAS()
		elseif inputs[self.das.direction] == true then
			self:continueDAS()
		else
			self:stopDAS()
		end
	else  -- default behaviour, das first key pressed
		if inputs[self.das.direction] == true then
			self:continueDAS()
		elseif inputs["right"] == true then
			self:startRightDAS()
		elseif inputs["left"] == true then
			self:startLeftDAS()
		else
			self:stopDAS()
		end
	end
end

function GameModeRev:dasCut()
	self.das.frames = math.max(
		self.das.frames - self:getDasCutDelay(),
		-(self:getDasCutDelay() + 1)
	)
end

function GameModeRev:areCancel(inputs, ruleset)
	if ruleset.are_cancel and strTrueValues(inputs) ~= "" and
	not self.prev_inputs.up and
	(self.piece_hard_dropped or
	(self.piece_soft_locked and not self.prev_inputs.down)) then
		self.lcd = 0
		self.are = 0
	end
end

function GameModeRev:checkBufferedInputs(inputs)
	if (
		config.gamesettings.buffer_lock ~= 1 and
		not self.prev_inputs["up"] and inputs["up"] and
		self.enable_hard_drop
	) then
		self.buffer_hard_drop = true
	end
	if (
		config.gamesettings.buffer_lock ~= 1 and
		not self.prev_inputs["down"] and inputs["down"]
	) then
		self.buffer_soft_drop = true
	end
end

function GameModeRev:processDelays(inputs, ruleset, drop_speed)
	if self.ready_frames == 100 then
		playedReadySE = false
		playedGoSE = false
	end
	if self.ready_frames > 0 then
		self:checkBufferedInputs(inputs)
		if not playedReadySE then
			playedReadySE = true
			playSEOnce("ready")
		end
		self.ready_frames = self.ready_frames - 1
		if self.ready_frames == 50 and not playedGoSE then
			playedGoSE = true
			playSEOnce("go")
		end
		if self.ready_frames == 0 then
			self:initializeOrHold(inputs, ruleset)
		end
	elseif self.lcd > 0 then
		self:checkBufferedInputs(inputs)
		self.lcd = self.lcd - 1
		self:areCancel(inputs, ruleset)
		if self.lcd == 0 then
			local cleared_row_count = self.grid:getClearedRowCount()
			self.grid:clearClearedRows()
			self:afterLineClear(cleared_row_count)
			playSE("fall")
			if self.are == 0 then
				self:initializeOrHold(inputs, ruleset)
			end
		end
	elseif self.are > 0 then
		self:checkBufferedInputs(inputs)
		self.are = self.are - 1
		self:areCancel(inputs, ruleset)
		if self.are == 0 then
			self:initializeOrHold(inputs, ruleset)
		end
	end
end

function GameModeRev:initializeOrHold(inputs, ruleset)
	if (
		(self.frames == 0 or (ruleset.are and self:getARE() ~= 0))
		and self.ihs or false
	) and self.enable_hold and inputs["hold"] == true then
		self:hold(inputs, ruleset, true)
	else
		self:initializeNextPiece(inputs, ruleset, self.next_queue[1])
	end
	self:onPieceEnter()
	self:onEnterOrHold(inputs, ruleset)
end

function GameModeRev:hold(inputs, ruleset, ihs)
	local data = copy(self.hold_queue)
	if self.piece == nil then
		self.hold_queue = self.next_queue[1]
		table.remove(self.next_queue, 1)
		table.insert(self.next_queue, self:getNextPiece(ruleset))
	else
		self.hold_queue = {
			skin = self.piece.skin,
			shape = self.piece.shape,
			orientation = ruleset:getDefaultOrientation(self.piece.shape),
		}
	end
	if data == nil then
		self:initializeNextPiece(inputs, ruleset, self.next_queue[1])
	else
		self:initializeNextPiece(inputs, ruleset, data, false)
	end
	self.held = true
	self:onHold()
	if ihs then
		playSE("ihs")
	else
		playSE("hold")
		self:onEnterOrHold(inputs, ruleset)
	end
end

function GameModeRev:onEnterOrHold(inputs, ruleset)
	if not self.grid:canPlacePiece(self.piece) then
		self.game_over = true
		return
	elseif self.piece:isDropBlocked(self.grid) then
		playSE("bottom")
	end
	ruleset:dropPiece(
		inputs, self.piece, self.grid, self:getGravity(),
		self:getDropSpeed(), self.drop_locked, self.hard_drop_locked
	)
end

function GameModeRev:initializeNextPiece(
	inputs, ruleset, piece_data, generate_next_piece
)
	if not self.buffer_soft_drop and self.lock_drop or (
		not ruleset.are or self:getARE() == 0
	) then
		self.drop_locked = true
	end
	if not self.buffer_hard_drop and self.lock_hard_drop or (
		not ruleset.are or self:getARE() == 0
	) then
		self.hard_drop_locked = true
	end
	self.piece = ruleset:initializePiece(
		inputs, piece_data, self.grid, self:getGravity(),
		self.prev_inputs, self.move,
		self:getLockDelay(), self:getDropSpeed(),
		self.drop_locked, self.hard_drop_locked, self.big_mode,
		(
			self.frames == 0 or (ruleset.are and self:getARE() ~= 0)
		) and self.irs or false
	)
	if config.gamesettings.buffer_lock == 3 then
		if self.buffer_hard_drop then
			local prev_y = self.piece.position.y
			self.piece:dropToBottom(self.grid)
			self.piece.locked = self.lock_on_hard_drop
			self:onHardDrop(self.piece.position.y - prev_y)
		end
		if (
			self.buffer_soft_drop and
			self.lock_on_soft_drop and
			self:getGravity() >= self.grid.height - 4
		) then
			self.piece.locked = true
		end
	end
	self.piece_hard_dropped = false
	self.piece_soft_locked = false
	self.buffer_hard_drop = false
	self.buffer_soft_drop = false
	if generate_next_piece == nil then
		table.remove(self.next_queue, 1)
		table.insert(self.next_queue, self:getNextPiece(ruleset))
	end
	self:playNextSound(ruleset)
end

function GameModeRev:playNextSound(ruleset)
	playSE("blocks", ruleset.next_sounds[self.next_queue[1].shape])
end

function GameModeRev:getHighScoreData()
	return {
		score = self.score
	}
end

function GameModeRev:animation(x, y, skin, colour)
	-- Animation progress where 0 = start and 1 = end
	local progress = 1
	if self.last_lcd ~= 0 then
		progress = (self.last_lcd - self.lcd) / self.last_lcd
	end
	-- Convert progress through the animation into an alpha value, with easing
	local alpha = 1 - progress ^ 2
	return {
			1, 1, 1,
			alpha,
			skin, colour,
			48 + x * 16, y * 16
	}
end

function GameModeRev:canDrawLCA()
	return self.lcd > 0
end

function GameModeRev:drawLineClearAnimation()
	for y, row in pairs(self.cleared_block_table) do
		for x, block in pairs(row) do
			local rev_x = self.grid.width - x + 1
            local rev_y = self.grid.height - y + 5
			local animation_table = self:animation(rev_x, rev_y, block.skin, block.colour)
			love.graphics.setColor(
				animation_table[1], animation_table[2],
				animation_table[3], animation_table[4]
			)
			love.graphics.draw(
				blocks[animation_table[5]][animation_table[6]],
				animation_table[7], animation_table[8]
			)
		end
	end
end

function GameModeRev:drawPiece()
	if self.piece ~= nil then
		local b = (
			self.classic_lock and
			(
				self.piece:isDropBlocked(self.grid) and
				1 - self.piece.gravity or 1
			) or
			1 - (self.piece.lock_delay / self:getLockDelay())
		)
		self.piece:draw(1, 0.25 + 0.75 * b, self.grid)
	end
end

function GameModeRev:drawGhostPiece(ruleset)
	if self.piece == nil or not self.grid:canPlacePiece(self.piece) then
		return
	end
	local ghost_piece = self.piece:withOffset({x=0, y=0})
	ghost_piece.ghost = true
	ghost_piece:dropToBottom(self.grid)
	ghost_piece:draw(0.5)
end

function GameModeRev:drawNextQueue(ruleset)
	local colourscheme
	if table.equalvalues(
		self.used_randomizer.possible_pieces,
		{"I", "J", "L", "O", "S", "T", "Z"}
	) then
		colourscheme = ({ruleset.colourscheme, ColourSchemes.Arika, ColourSchemes.TTC})[config.gamesettings.piece_colour]
	else
		colourscheme = ruleset.colourscheme
	end
	function drawPiece(piece, skin, offsets, pos_x, pos_y)
		for index, offset in pairs(offsets) do
			local x = self.grid.width - (offset.x + ruleset:getDrawOffset(piece, rotation).x + ruleset.spawn_positions[piece].x) - 1
			local y = self.grid.height - (offset.y + ruleset:getDrawOffset(piece, rotation).y + 4.7) + 9
			love.graphics.draw(blocks[skin][colourscheme[piece]], pos_x+x*16, pos_y+y*16)
		end
	end
	for i = 1, self.next_queue_length do
		self:setNextOpacity(i)
		local next_piece = self.next_queue[i].shape
		local skin = self.next_queue[i].skin
		local rotation = self.next_queue[i].orientation
		if config.side_next then -- next at side
			drawPiece(next_piece, skin, ruleset.block_offsets[next_piece][rotation], 192, -16+i*48)
		else -- next at top
			drawPiece(next_piece, skin, ruleset.block_offsets[next_piece][rotation], -16+i*80, -32)
		end
	end
	if self.hold_queue ~= nil and self.enable_hold then
		self:setHoldOpacity()
		drawPiece(
			self.hold_queue.shape, 
			self.hold_queue.skin, 
			ruleset.block_offsets[self.hold_queue.shape][self.hold_queue.orientation],
			-16, -32
		)
	end
	return false
end

function GameModeRev:setNextOpacity(i)
	love.graphics.setColor(1, 1, 1, 1)
end

function GameModeRev:setHoldOpacity()
	local colour = self.held and 0.6 or 1
	love.graphics.setColor(colour, colour, colour, 1)
end

function GameModeRev:getBackground()
	return 0
end

function GameModeRev:getHighscoreData()
	return {}
end

function GameModeRev:drawGrid()
	self.grid:draw()
end

function GameModeRev:drawScoringInfo()
	love.graphics.setColor(1, 1, 1, 1)
	love.graphics.setFont(font_3x5_2)

	if config["side_next"] then
		love.graphics.printf("NEXT", 240, 72, 40, "left")
	else
		love.graphics.printf("NEXT", 64, 420, 40, "left")
	end

	love.graphics.print(
		self.das.direction .. " " ..
		self.das.frames .. " " ..
		strTrueValues(self.prev_inputs) ..
		self.drop_bonus
	)

	love.graphics.setFont(font_8x11)
	love.graphics.printf(formatTime(self.frames), 64, 40, 160, "center")
end

function GameModeRev:drawSectionTimes(current_section)
	local section_x = 530

	for section, time in pairs(self.section_times) do
		if section > 0 then
			love.graphics.printf(formatTime(time), section_x, 40 + 20 * section, 90, "left")
		end
	end

	love.graphics.printf(formatTime(self.frames - self.section_start_time), section_x, 40 + 20 * current_section, 90, "left")
end

function GameModeRev:sectionColourFunction(section)
	return { 1, 1, 1, 1 }
end

function GameModeRev:drawSectionTimesWithSecondary(current_section, section_limit)
	section_limit = section_limit or math.huge
	local section_x = 530
	local section_secondary_x = 440

	for section, time in pairs(self.section_times) do
		if section > 0 then
			love.graphics.printf(formatTime(time), section_x, 40 + 20 * section, 90, "left")
		end
	end

	for section, time in pairs(self.secondary_section_times) do
		love.graphics.setColor(self:sectionColourFunction(section))
		if section > 0 then
			love.graphics.printf(formatTime(time), section_secondary_x, 40 + 20 * section, 90, "left")
		end
		love.graphics.setColor(1, 1, 1, 1)
	end

	local current_x
	if table.getn(self.section_times) < table.getn(self.secondary_section_times) then
		current_x = section_x
	else
		current_x = section_secondary_x
	end

	if current_section <= section_limit then
		love.graphics.printf(formatTime(self.frames - self.section_start_time), current_x, 40 + 20 * current_section, 90, "left")
	end
end

function GameModeRev:drawSectionTimesWithSplits(current_section, section_limit)
	section_limit = section_limit or math.huge
	
	local section_x = 440
	local split_x = 530

	local split_time = 0

	for section, time in pairs(self.section_times) do
		if section > 0 then
			love.graphics.setColor(self:sectionColourFunction(section))
			love.graphics.printf(formatTime(time), section_x, 40 + 20 * section, 90, "left")
			love.graphics.setColor(1, 1, 1, 1)
			split_time = split_time + time
			love.graphics.printf(formatTime(split_time), split_x, 40 + 20 * section, 90, "left")
		end
	end
	
	if (current_section <= section_limit) then
		love.graphics.printf(formatTime(self.frames - self.section_start_time), section_x, 40 + 20 * current_section, 90, "left")
		love.graphics.printf(formatTime(self.frames), split_x, 40 + 20 * current_section, 90, "left")
	end
end

function GameModeRev:drawBackground()
	local id = self:getBackground()
	if type(id) == "number" then id = clamp(id, 0, #backgrounds) end
	love.graphics.setColor(1, 1, 1, 1)
	drawBackground(id)
end

function GameModeRev:drawFrame()
	-- game frame
	if self.grid.width == 10 and self.grid.height == 24 then
		love.graphics.draw(misc_graphics["frame"], 48, 64)
	else
		love.graphics.setColor(174/255, 83/255, 76/255, 1)
		love.graphics.setLineWidth(8)
		love.graphics.line(
			60,76,
			68+16*self.grid.width,76,
			68+16*self.grid.width,84+16*(self.grid.height-4),
			60,84+16*(self.grid.height-4),
			60,76
		)
		love.graphics.setColor(203/255, 137/255, 111/255, 1)
		love.graphics.setLineWidth(4)
		love.graphics.line(
			60,76,
			68+16*self.grid.width,76,
			68+16*self.grid.width,84+16*(self.grid.height-4),
			60,84+16*(self.grid.height-4),
			60,76
		)
		love.graphics.setLineWidth(1)
		love.graphics.setColor(0, 0, 0, 200)
		love.graphics.rectangle(
			"fill", 64, 80,
			16 * self.grid.width, 16 * (self.grid.height - 4)
		)
	end
end

function GameModeRev:drawReadyGo()
	-- ready/go graphics
	love.graphics.setColor(1, 1, 1, 1)

	if self.ready_frames <= 100 and self.ready_frames > 52 then
		love.graphics.draw(misc_graphics["ready"], 144 - 50, 240 - 14)
	elseif self.ready_frames <= 50 and self.ready_frames > 2 then
		love.graphics.draw(misc_graphics["go"], 144 - 27, 240 - 14)
	end
end

function GameModeRev:drawCustom() end

function GameModeRev:drawIfPaused()
	love.graphics.setFont(font_3x5_3)
	love.graphics.printf("PAUSED!", 64, 160, 160, "center")
end

-- transforms specified in here will transform the whole screen
-- if you want a transform for a particular component, push the
-- default transform by using love.graphics.push(), do your
-- transform, and then love.graphics.pop() at the end of that
-- component's draw call!
function GameModeRev:transformScreen() end

function GameModeRev:draw(paused)
	self:transformScreen()
	self:drawBackground()
	self:drawFrame()
	self:drawGrid()
	self:drawPiece()
	if self:canDrawLCA() then
		self:drawLineClearAnimation()
	end
	self:drawNextQueue(self.ruleset)
	self:drawScoringInfo()
	self:drawReadyGo()
	self:drawCustom()

	love.graphics.setColor(1, 1, 1, 1)
	love.graphics.setFont(font_3x5_2)
	if config.gamesettings.display_gamemode == 1 then
		love.graphics.printf(
			self.name .. " - " .. self.ruleset.name,
			0, 460, 640, "left"
		)
	end

	if paused then
		self:drawIfPaused()
	end

	if self.completed then
		self:onGameComplete()
	elseif self.game_over then
		self:onGameOver()
	end
end

return GameModeRev
