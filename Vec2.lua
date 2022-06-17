-- based on https://codereview.stackexchange.com/a/107237
local Vec2 = {}
do
    local meta = {
        _metatable = "Private metatable",
        _DESCRIPTION = "Vectors in 2D"
    }

    meta.__index = meta

    function meta:__add( v )
        return Vec2(self.x + v.x, self.y + v.y)
    end

	function meta:__sub( v )
        return Vec2(self.x - v.x, self.y - v.y)
    end

    function meta:__mul( v )
        return self.x * v.x + self.y * v.y
    end

    function meta:__eq( v )
        return self.x == v.x and self.y == v.y
    end

    function meta:__tostring()
        return ("<%g, %g>"):format(self.x, self.y)
    end

    function meta:magnitude()
        return math.sqrt( self * self )
    end

    setmetatable( Vec2, {
        __call = function( V, x ,y ) return setmetatable( {x = x, y = y}, meta ) end
    } )
end

Vec2.__index = Vec2

return Vec2