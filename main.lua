if os.getenv("LOCAL_LUA_DEBUGGER_VSCODE") == "1" then
    require("lldebugger").start()
end
local Vec2 = require 'Vec2'

local function enum(tbl)
    local length = #tbl
    for i = 1, length do
        local v = tbl[i]
        tbl[v] = i
    end

    return tbl
end

local screen_size_px = 1080  -- square window

local play_size_width_px = screen_size_px * 0.5
local play_size_height_px = screen_size_px

local cell_count_w = 10
local cell_count_h = 20
local cell_size_px = play_size_height_px / cell_count_h
local playfield = {} -- 0,0 cell is top left

local time_interval = 0.4
local time_acc = 0
local lines_count = 0

local animation_acc = 0
local lines_delay = 0.3
local resumed_from_animation = true

local score = 0
local lines_rows = {}

local tetromino_type = enum {
	"i",
	"j",
	"l",
	"o",
	"s",
	"t",
	"z",
}

local cell_colors = {
	['.'] = { .1, .1, .1},
	['x'] = { .95, .95, .95},
	[tetromino_type.i] = {.20, .95, .95},
	[tetromino_type.j] = {.10, .10, .95},
	[tetromino_type.l] = {.95, .65, .10},
	[tetromino_type.o] = {.95, .95, .20},
	[tetromino_type.s] = {.10, .95, .10},
	[tetromino_type.t] = {.60, .20, .95},
	[tetromino_type.z] = {.95, .10, .10}
}

local active_angle = 1
local active_tetro_type = tetromino_type.t
local active_tetro = { Vec2(0, 0), Vec2(0, 0), Vec2(0, 0), Vec2(0, 0) } -- every tetromino is four invidual pieces, the first one is the rotation origin

local spawn_offsets = { -- offsets from origin of every tetromino type piece, first is origin itself (its offset is from playfield) then rest of pieces from top-left to right bottom
	[tetromino_type.i] = { Vec2(4, 0), Vec2(-1,  0), Vec2( 1,  0), Vec2(2,  0) },
	[tetromino_type.j] = { Vec2(4, 0), Vec2(-1, -1), Vec2(-1,  0), Vec2(1,  0) },
	[tetromino_type.l] = { Vec2(4, 0), Vec2(-1,  0), Vec2( 1,  0), Vec2(1, -1) },
	[tetromino_type.o] = { Vec2(4, 0), Vec2( 0, -1), Vec2( 1, -1), Vec2(1,  0) },
	[tetromino_type.s] = { Vec2(4, 0), Vec2(-1,  0), Vec2( 0, -1), Vec2(1, -1) },
	[tetromino_type.t] = { Vec2(4, 0), Vec2(-1,  0), Vec2( 0, -1), Vec2(1,  0) },
	[tetromino_type.z] = { Vec2(4, 0), Vec2(-1, -1), Vec2( 0, -1), Vec2(1,  0) },
}

local kick_offsets = { -- SRS offsets for each rotation state, ex: to get kick offset when coming from state 1 to 2, subtract nth kick of 1 from nth kick of 2
	-- j,l,s,t,z
	{
		{ Vec2(0, 0), Vec2( 0, 0), Vec2( 0, 0), Vec2(0,  0), Vec2( 0,  0) },
		{ Vec2(0, 0), Vec2( 1, 0), Vec2( 1, 1), Vec2(0, -2), Vec2( 1, -2) },
		{ Vec2(0, 0), Vec2( 0, 0), Vec2( 0, 0), Vec2(0,  0), Vec2( 0,  0) },
		{ Vec2(0, 0), Vec2(-1, 0), Vec2(-1, 1), Vec2(0, -2), Vec2(-1, -2) }
	},
	-- i
	{
		{ Vec2( 0,  0), Vec2(-1,  0), Vec2( 2,  0), Vec2(-1,  0), Vec2( 2,  0) },
		{ Vec2(-1,  0), Vec2( 0,  0), Vec2( 0,  0), Vec2( 0, -1), Vec2( 0,  2) },
		{ Vec2(-1, -1), Vec2( 1, -1), Vec2(-2, -1), Vec2( 1,  0), Vec2(-2,  0) },
		{ Vec2( 0, -1), Vec2( 0, -1), Vec2( 0, -1), Vec2( 0,  1), Vec2( 0, -2) }
	},
	-- o
	{
		{ Vec2( 0, 0)},
		{ Vec2( 0, 1)},
		{ Vec2(-1, 1)},
		{ Vec2(-1, 0)}
	}
}

-- TODO: pack tetromino data to one table
local function spawn_new_tetromino(tetro)
	active_tetro_type = love.math.random(7)
	--active_tetro_type = tetromino_type.o
	tetro[1] = spawn_offsets[active_tetro_type][1]
	active_angle = 1

	-- spawn with offset from origin, transfer from local space to game(field) space
	for i = 2, #active_tetro, 1 do
		tetro[i] = tetro[1] + spawn_offsets[active_tetro_type][i]
	end
end

local function copy_positions(from, to)
	for i = 1, #from, 1 do
		to[i] = from[i]
	end
end

-- TODO: pack cell_count with field, cleanup bandaid
local function check_collision(tetromino, field)
	local has_collided = false

	for i = 1, #tetromino, 1 do
		local t_x, t_y = tetromino[i].x, tetromino[i].y
		local field_block = field[(t_x+1) + t_y * cell_count_w]

		if t_x >= cell_count_w or t_x < 0 or 
		   t_y >= cell_count_h or field_block ~= '.' then
			if t_y >= 0 then -- bandaid for spawn
				has_collided = true
			end
		end
	end

	return has_collided
end

local function move_pos(tetromino, offset)
	local new_pos = {}

	for i = 1, #tetromino, 1 do
		new_pos[i] = tetromino[i] + offset
	end

	local has_collided = check_collision(new_pos, playfield)
	if has_collided == false then
		copy_positions(new_pos, tetromino)
	end

	return has_collided
end

function love.load()
	love.window.setMode(screen_size_px, screen_size_px, { resizable=false, vsync=false, minwidth=screen_size_px, minheight=screen_size_px })
	love.window.setTitle("Tetris Kacper Łuczak")

	for i = 1, cell_count_h * cell_count_w, 1 do
		table.insert(playfield, '.')
	end
	spawn_new_tetromino(active_tetro)
end

function love.keypressed(key)
	if key == 'space' then
		local has_collided = false
		local tetro_kicks = 0
		local next_angle = math.max(1, (active_angle + 1) % 5)

		if active_tetro_type == tetromino_type.i then
			tetro_kicks = 2
		elseif active_tetro_type == tetromino_type.o then
			tetro_kicks = 3
		else
			tetro_kicks = 1
		end

		local rot_pos = {}
		for i = 1, #active_tetro, 1 do
			rot_pos[i] = active_tetro[i]
			local relative = active_tetro[i] - active_tetro[1] -- from world(game) space to local space
			rot_pos[i] = Vec2(-relative.y, relative.x)
			rot_pos[i] = rot_pos[i] + active_tetro[1] -- back to world(game) space
		end

		-- rotation, kicks, collision
		for ik = 1, #kick_offsets[tetro_kicks][active_angle], 1 do
			local kick_pos = {}
			for i = 1, #active_tetro, 1 do
				kick_pos[i] = rot_pos[i] + (kick_offsets[tetro_kicks][active_angle][ik] - kick_offsets[tetro_kicks][next_angle][ik])
			end
			has_collided = check_collision(kick_pos, playfield)
			if has_collided == false then
				copy_positions(kick_pos, active_tetro)
				break;
			end
		end

		active_angle = next_angle
		time_acc = time_interval - 0.3 -- TODO: make rotation move period dynamic based on time_speed
	end

	if key == 'left' then
		move_pos(active_tetro, Vec2(-1, 0))
	end
	if key == 'right' then
		move_pos(active_tetro, Vec2(1, 0))
	end
	if key == 'down' then
		local has_collided = false
		while has_collided == false do
			has_collided = move_pos(active_tetro, Vec2(0, 1))
		end
		time_acc = time_interval
	end
end

function love.update(dt)
	time_acc = time_acc + dt
	local has_collided = false

	-- move active tetromino down every time_speed interval
    while time_acc >= time_interval do
		time_acc = time_acc - time_interval
		has_collided = move_pos(active_tetro, Vec2(0, 1))
    end

	-- Lines removal
	if not not next(lines_rows) and resumed_from_animation == false then
		animation_acc = animation_acc + dt

		if animation_acc >= lines_delay then
			for i = 1, #lines_rows, 1 do
				for l_y = lines_rows[i], 0, -1 do
					for f_x = 1, cell_count_w do
						playfield[(f_x) + l_y * cell_count_w] = playfield[(f_x) + (l_y-1) * cell_count_w]
						playfield[f_x] = '.'
					end
				end
			end
			for i = 1, #lines_rows, 1 do
				table.remove(lines_rows)
			end

			animation_acc = 0
			resumed_from_animation = true
		end
	end

	if has_collided == true then
		-- save active tetromino to playfield
		for i = 1, #active_tetro, 1 do
			local t_x, t_y = active_tetro[i].x, active_tetro[i].y
			playfield[(t_x+1) + t_y * cell_count_w] = active_tetro_type
		end

		-- full rows check, only need to check from active
		if resumed_from_animation == true then
			local y_set = {} -- bandaid to not duplicate rows that have already been checked
			for i = 1, #active_tetro, 1 do
				local t_y = active_tetro[i].y

				if y_set[t_y] == nil then
					local is_line = true
					y_set[t_y] = true

					for f_x = 1, cell_count_w, 1 do
						local field_block = playfield[(f_x) + t_y * cell_count_w]
						is_line = (is_line and (field_block ~= '.'))
					end

					if is_line == true then
						lines_count = lines_count + 1
						score = score + 1
						for l_x = 1, cell_count_w, 1 do
							playfield[(l_x) + t_y * cell_count_w] = 'x'
						end
						table.insert(lines_rows, t_y)
						resumed_from_animation = false
					end
				end
			end
			-- needed cause rows can be in any order and they need to be sorted for lines removal logic to work
			table.sort(lines_rows)
		end

		spawn_new_tetromino(active_tetro)

		-- check for defeat
		if check_collision(active_tetro, playfield) == true then
			love.event.quit()
		end
	end

end

-- TODO: Cleanup
function love.draw()

	local cell_gap_size_px = 4
	local cell_draw_size_px = cell_size_px - cell_gap_size_px

	-- Back grid draw
	for y = 1, cell_count_h, 1 do
		for x = 1, cell_count_w, 1 do
			love.graphics.setColor( cell_colors[playfield[x + (y-1) * cell_count_w]] )
			love.graphics.rectangle('fill', (x-1) * cell_size_px, (y-1) * cell_size_px,
									cell_draw_size_px, cell_draw_size_px )
		end
	end

	-- Draw ghost
	local has_collided = false
	local ghost_pos = {}
	copy_positions(active_tetro, ghost_pos)
	while has_collided == false do
		has_collided = move_pos(ghost_pos, Vec2(0, 1))
	end
	for i = 1, #ghost_pos, 1 do
		local playfield_x = ghost_pos[i].x * cell_size_px
		local playfield_y = ghost_pos[i].y * cell_size_px
		local color = {}
		for ic = 1, 3, 1 do
			color[ic] = cell_colors[active_tetro_type][ic] * 0.3
		end
		love.graphics.setColor( color )
		love.graphics.rectangle('fill', playfield_x, playfield_y,
							cell_draw_size_px, cell_draw_size_px )
	end

	-- Active tetromino draw
	for i = 1, #active_tetro, 1 do
		local playfield_x = active_tetro[i].x * cell_size_px
		local playfield_y = active_tetro[i].y * cell_size_px

		love.graphics.setColor(  cell_colors[active_tetro_type] )
		love.graphics.rectangle('fill', playfield_x, playfield_y,
							cell_draw_size_px, cell_draw_size_px )
	end

end
