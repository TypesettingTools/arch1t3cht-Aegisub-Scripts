haveDepCtrl, DependencyControl, depctrl = pcall require, 'l0.DependencyControl'

local amath

if haveDepCtrl
    depctrl = DependencyControl {
        name: 'Perspective',
        version: '0.1.0',
        description: [[Math functions for dealing with perspective transformations.]],
        author: "arch1t3cht",
        url: "https://github.com/arch1t3cht/Aegisub-Scripts",
        moduleName: 'arch.Perspective',
        {
            { "arch.Math", version: "0.1.0" },
        }
    }

    amath = depctrl\requireModules!
else
    amath = require"arch.Math"

{:Point, :Matrix} = amath

-- compatibility with Lua >= 5.2
unpack = unpack or table.unpack


local Quad

-- Quadrilateral (usually in 2D space) described by its four corners, in clockwise or counter-clockwise direction.
-- Internally, we always use numbering that's counter-clockwise in the cartesian plane, which is clockwise on a 2D screen.
class Quad extends Matrix
    new: (...) =>
        super(...)
        assert(@height == 4)

    -- Computes the intersection point of the diagonals.
    -- Doubles as a generic function to intersect to lines in 2D space.
    midpoint: =>
        la = Matrix(@[3] - @[1], @[4] - @[2])\transpose!\preim(@[4] - @[1])
        return @[1] + la[1] * (@[3] - @[1])


    --------------------
    -- Collection of functions describing the perspective transformation between this quad and a 1x1 square.
    -- These were originally computed from cross-ratios and run through Mathematica to combine all the fractions,
    -- which makes it work in such "edge" cases as two sides of the quad being parallel.
    -- They were then dumped from Mathematica in InputForm and inserted here without much postprocessing,
    -- except for sometimes putting common denominators in an extra variable
    --------------------

    -- Helper functions to wrap code dumped from Mathematica
    -- returns x1, x2, x3, x4, y1, y2, y3, y4
    unwrap: => @[1][1], @[2][1], @[3][1], @[4][1], @[1][2], @[2][2], @[3][2], @[4][2]

    -- translates x1, y1 to 0, 0 and returns x2, x3, x4, y2, y3, y4
    unwrap_rel: =>
        @ = @ - @[1]
        return @[2][1], @[3][1], @[4][1], @[2][2], @[3][2], @[4][2]


    -- Perspective transform mapping the quad to a unit square
    xy_to_uv: (xy) =>
        assert(@width == 2)
        x2, x3, x4, y2, y3, y4 = @unwrap_rel!
        x, y = unpack(xy - @[1])

        u = -(((x3*y2 - x2*y3)*(x4*y - x*y4)*(x4*(-y2 + y3) + x3*(y2 - y4) + x2*(-y3 + y4)))/(x3^2*(x4*y2^2*(-y + y4) + y4*(x*y2*(y2 - y4) + x2*(y - y2)*y4)) + x3*(x4^2*y2^2*(y - y3) + 2*x4*(x2*y*y3*(y2 - y4) + x*y2*(-y2 + y3)*y4) + x2*y4*(x2*(-y + y3)*y4 + 2*x*y2*(-y3 + y4))) + y3*(x*x4^2*y2*(y2 - y3) + x2*x4^2*(y2*y3 + y*(-2*y2 + y3)) - x2^2*(x4*y*(y3 - 2*y4) + x4*y3*y4 + x*y4*(-y3 + y4)))))
        v = ((x2*y - x*y2)*(x4*y3 - x3*y4)*(x4*(y2 - y3) + x2*(y3 - y4) + x3*(-y2 + y4)))/(x3*(x4^2*y2^2*(-y + y3) + x2*y4*(2*x*y2*(y3 - y4) + x2*(y - y3)*y4) - 2*x4*(x2*y*y3*(y2 - y4) + x*y2*(-y2 + y3)*y4)) + x3^2*(x4*y2^2*(y - y4) + y4*(x2*(-y + y2)*y4 + x*y2*(-y2 + y4))) + y3*(x*x4^2*y2*(-y2 + y3) + x2*x4^2*(2*y*y2 - y*y3 - y2*y3) + x2^2*(x4*y*(y3 - 2*y4) + x4*y3*y4 + x*y4*(-y3 + y4))))

        return Point(u, v)

    -- Perspective transform mapping a unit square to the quad
    uv_to_xy: (uv) =>
        assert(@width == 2)
        x2, x3, x4, y2, y3, y4 = @unwrap_rel!
        u, v = unpack(uv)

        d = (x4*((-1 + u + v)*y2 + y3 - v*y3) + x3*(y2 - u*y2 + (-1 + v)*y4) + x2*((-1 + u)*y3 - (-1 + u + v)*y4))
        x = (v*x4*(x3*y2 - x2*y3) + u*x2*(x4*y3 - x3*y4)) / d
        y = (v*y4*(x3*y2 - x2*y3) + u*y2*(x4*y3 - x3*y4)) / d

        return Point(x, y) + @[1]

    -- Derivative (i.e. Jacobian) of uv_to_xy at the given point
    d_uv_to_xy: (uv) =>
        assert(@width == 2)
        x2, x3, x4, y2, y3, y4 = @unwrap_rel!
        u, v = unpack(uv)

        d = (x4*((-1 + u + v)*y2 + y3 - v*y3) + x3*(y2 - u*y2 + (-1 + v)*y4) + x2*((-1 + u)*y3 - (-1 + u + v)*y4))^2

        dxdu = (x2*(x4*y3 - x3*y4)*(x4*((-1 + u + v)*y2 + y3 - v*y3) + x3*(y2 - u*y2 + (-1 + v)*y4) + x2*((-1 + u)*y3 - (-1 + u + v)*y4)) + (x3*y2 - x4*y2 + x2*(-y3 + y4))*(v*x4*(x3*y2 - x2*y3) + u*x2*(x4*y3 - x3*y4))) / d
        dxdv = (x4*(x3*y2 - x2*y3)*(x4*((-1 + u + v)*y2 + y3 - v*y3) + x3*(y2 - u*y2 + (-1 + v)*y4) + x2*((-1 + u)*y3 - (-1 + u + v)*y4)) - (x4*(y2 - y3) + (-x2 + x3)*y4)*(v*x4*(x3*y2 - x2*y3) + u*x2*(x4*y3 - x3*y4))) / d
        dydu = ((-1 + v)*x3^2*y2*(y2 - y4)*y4 + y3*((-1 + v)*x4^2*y2*(y2 - y3) + v*x2^2*(y3 - y4)*y4 + x2*x4*y2*(-y3 + y4)) + x3*y2*(2*(-1 + v)*x4*y3*y4 - (-1 + 2*v)*x2*(y3 - y4)*y4 + x4*y2*(y3 + y4 - 2*v*y4))) / d
        dydv = ((x3*y2 - x2*y3)*y4*(-(x4*y2) - x2*y3 + x4*y3 + x3*(y2 - y4) + x2*y4) + u*(x4^2*y2*y3*(-y2 + y3) + 2*x3*x4*y2*(y2 - y3)*y4 + y4*(2*x2*x3*y2*(y3 - y4) + x3^2*y2*(-y2 + y4) + x2^2*y3*(-y3 + y4)))) / d

        return Matrix({{dxdu, dxdv}, {dydu, dydv}})

    -- Derivative (i.e. Jacobian) of xy_to_uv at the given point
    d_xy_to_uv: (xy) =>
        assert(@width == 2)
        x2, x3, x4, y2, y3, y4 = @unwrap_rel!
        x, y = unpack(xy)

        d = (x3*(x4^2*y2^2*(-y + y3) + x2*y4*(2*x*y2*(y3 - y4) + x2*(y - y3)*y4) - 2*x4*(x2*y*y3*(y2 - y4) + x*y2*(-y2 + y3)*y4)) + x3^2*(x4*y2^2*(y - y4) + y4*(x2*(-y + y2)*y4 + x*y2*(-y2 + y4))) + y3*(x*x4^2*y2*(-y2 + y3) + x2*x4^2*(2*y*y2 - y*y3 - y2*y3) + x2^2*(x4*y*(y3 - 2*y4) + x4*y3*y4 + x*y4*(-y3 + y4))))^2

        dudx = ((x3*y2 - x2*y3)*(x4*y2 - x2*y4)*(x4*y3 - x3*y4)*(x4*y*(y2 - y3) + x3*(y - y2)*y4 + x2*(-y + y3)*y4)*(x4*(-y2 + y3) + x3*(y2 - y4) + x2*(-y3 + y4))) / d
        dvdx = -((x3*y2 - x2*y3)*(x4*y2 - x2*y4)*(x4*y3 - x3*y4)*(-(x3*x4*y2) + x*x4*(y2 - y3) + x2*x4*y3 + x*(-x2 + x3)*y4)*(x4*(-y2 + y3) + x3*(y2 - y4) + x2*(-y3 + y4))) / d
        dudy = ((x3*y2 - x2*y3)*(x4*y2 - x2*y4)*(x4*y3 - x3*y4)*(x4*y2*(y - y3) + x2*y*(y3 - y4) + x3*y2*(-y + y4))*(x4*(y2 - y3) + x2*(y3 - y4) + x3*(-y2 + y4))) / d
        dvdy = ((x3*y2 - x2*y3)*(x4*y2 - x2*y4)*(-(x4*y3) + x3*y4)*(x4*(-y2 + y3) + x3*(y2 - y4) + x2*(-y3 + y4))*(x*(x3*y2 - x4*y2 - x2*y3 + x2*y4) + x2*(x4*y3 - x3*y4))) / d

        return Matrix({{dudx, dudy}, {dvdx, dvdy}})


return {
    :Quad,
}
