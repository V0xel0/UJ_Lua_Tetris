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
	['.'] = {.1, .1, .1},
	[tetromino_type.i] = {.20, .95, .95},
	[tetromino_type.j] = {.10, .10, .95},
	[tetromino_type.l] = {.95, .65, .10},
	[tetromino_type.o] = {.95, .95, .20},
	[tetromino_type.s] = {.10, .95, .10},
	[tetromino_type.t] = {.60, .20, .95},
	[tetromino_type.z] = {.95, .10, .10}
}

local playfield = {} -- 0,0 cell is top left

local active_angle = 1
local active_tetro_type = tetromino_type.o
local active_tetro = { Vec2(0, 0), Vec2(0, 0), Vec2(0, 0), Vec2(0, 0) } -- every tetromino is four invidual pieces, the first one is the rotation origin
local spawn_offsets = { -- offsets from origin of every tetromino type piece, first is origin itself (its offset is from playfield) then rest of pieces from top-left to right bottom
	{ Vec2(4, 0), Vec2(-1,  0), Vec2( 1,  0), Vec2(2,  0) },
	{ Vec2(4, 1), Vec2(-1, -1), Vec2(-1,  0), Vec2(1,  0) },
	{ Vec2(4, 1), Vec2(-1,  0), Vec2( 1,  0), Vec2(1, -1) },
	{ Vec2(4, 1), Vec2( 0, -1), Vec2( 1, -1), Vec2(1,  0) },
	{ Vec2(4, 1), Vec2(-1,  0), Vec2( 0, -1), Vec2(1, -1) },
	{ Vec2(4, 1), Vec2(-1,  0), Vec2( 0, -1), Vec2(1,  0) },
	{ Vec2(4, 1), Vec2(-1, -1), Vec2( 0, -1), Vec2(1,  0) },
}
local kick_offsets = {
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

local function move_tetromino(tetromino, offset)
	local out = tetromino
	for i = 1, #tetromino, 1 do
		out[i] = out[i] + offset
	end
	return out
end

function love.load()
	love.window.setMode(screen_size_px, screen_size_px, {resizable=false, vsync=false, minwidth=screen_size_px, minheight=screen_size_px})
	love.window.setTitle("Tetris Kacper Łuczak")
	local target_fps = 60
	local dt = 1 / target_fps

	for i = 1, cell_count_h * cell_count_w, 1 do
		table.insert(playfield, '.')
	end
	-- spawn with offset from origin, transfer from local space to game(field) space
	active_tetro[1] = spawn_offsets[active_tetro_type][1]
	for i = 2, #active_tetro, 1 do
		active_tetro[i] = active_tetro[1] + spawn_offsets[active_tetro_type][i]
	end
end

function love.keypressed(key)
	if key == 'space' then
		local is_collision = false
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
			-- check_collision(newpos)
			if is_collision == false then
				active_tetro = kick_pos
				break;
			end
		end

		active_angle = next_angle

	end
	if key == 'up' then
		active_tetro_type = math.max(1, (active_tetro_type + 1) % 8)
	end
	if key == 'left' then
		move_tetromino(active_tetro, Vec2(-1, 0))
	end
	if key == 'right' then
		move_tetromino(active_tetro, Vec2(1, 0))
	end
end

function love.update(dt)
	
end

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
	-- Active tetromino draw
	for i = 1, #active_tetro, 1 do
		-- local rotate_it = angles_it[active_angle](x-1, y-1) + 1
		local playfield_x = active_tetro[i].x * cell_size_px
		local playfield_y = active_tetro[i].y * cell_size_px

		love.graphics.setColor(  cell_colors[active_tetro_type] )
		love.graphics.rectangle('fill', playfield_x, playfield_y,
							cell_draw_size_px, cell_draw_size_px )
	end

end
