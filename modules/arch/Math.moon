haveDepCtrl, DependencyControl, depctrl = pcall require, 'l0.DependencyControl'

if haveDepCtrl
    depctrl = DependencyControl {
        name: "ArchMath",
        version: "0.1.10",
        description: [[General-purpose linear algebra functions, approximately matching the patterns of Matlab or numpy]],
        author: "arch1t3cht",
        url: "https://github.com/TypesettingTools/arch1t3cht-Aegisub-Scripts",
        moduleName: 'arch.Math',
        {}
    }

-- This is a collection of functions I needed for Perspective.moon, and some infrastructure around them:
-- - Vectors in n-dimensional space
-- - Matrices
-- - Some linear algebra, in particular LU decomposition
-- In no way do I claim that this is feature-complete (in fact this is already overengineered to oblivion),
-- but PR's are very welcome.


-- By making all my classes inherit from this, I can make metatables entries to be inherited by child classes.
-- See https://github.com/leafo/moonscript/issues/51#issuecomment-36732147 .
class ClassFix
    __inherited: (C) =>
        for i,v in next,@__base
            C.__base[i] or= v


id = (...) -> ...

local Matrix
local Point


-- Lua is dynamically typed, so there's no point in distinguishing between different dimensions in these.
--
-- I am aware that a "point" is also just a matrix with one column (or row), and that this could make some of
-- this code more compact. But I'll leave it this way for a bit more clarity.

-- Point in n-dimensional space. Doubles as a generic array type with some higher level functions.
-- Methods don't modify the objects.
--
-- Example:
-- p = Point(1, -2, 3)
-- print(p[1])
-- print(p.size)
-- print(3 * p)
class Point extends ClassFix
    -- Possible arguments for constructor:
    -- - A collection of numbers:
    --      Point(1, 2, 3, 4)
    -- - A table
    --      Point({1, 2, 3})
    -- - A 1xn or nx1 matrix
    --      Point(Matrix({{1, 2, 3, 4}}))
    new: (a, ...) =>
        local coords
        if type(a) == "table"
            if a.__class == Matrix
                if a.width == 1
                    coords = [r[1] for r in *a]
                elseif a.height == 1
                    coords = a[1]
            else
                coords = a
        else
            coords = {a, ...}

        for i, v in ipairs(coords)
            @[i] = v
        @size = #coords

    x: => @[1]
    y: => @[2]
    z: => @[3]

    aslist: () => [v for v in *@]

    project: (fr, to) =>
        if to == nil
            to = fr
            fr = 1

        return Point([@[i] for i=fr,to])

    map: (f) =>
        return @@ [f(v) for v in *@]

    fold: (f, initial) =>
        val = initial
        for c in *@
            val = f(val, c)
        return val

    zipWith: (f, p) =>
        assert(@size == p.size)
        return @@ [f(@[i], p[i]) for i=1,@size]

    copy: () => @map(id)

    sum: => @fold(((a, b) -> a + b), 0)

    __eq: (p) => @size == p.size and @dist(p) == 0

    __len: () => @size

    __add: (p, q) ->
        if type(p) == "number"
            return q\map((a) -> p + a)
        elseif type(q) == "number"
            return p\map((a) -> a + q)

        if not q.size
            return getmetatable(q).__add(p, q)

        return p\zipWith(((a, b) -> a + b), q)

    __unm: => @map((a) -> -a)

    __sub: (p) => @ + (-p)

    __mul: (p, q) ->
        if type(p) == "number"
            return q\map((a) -> p * a)
        elseif type(q) == "number"
            return p\map((a) -> a * q)
        return p\dot(q)

    __div: (p, q) ->
        if type(p) == "number"
            return q\map((a) -> p / a)
        elseif type(q) == "number"
            return p\map((a) -> a / q)
        return p\zipWith(((a, b) -> a / b), q)

    __concat: (q) =>
        p = @
        if type(p) == "number"
            p = @@ p
        elseif type(q) == "number"
            q = @@ q

        if not q.size
            return getmetatable(q).__concat(p, q)

        return @@ [(if i <= p.size then p[i] else q[i-p.size]) for i=1,(p.size+q.size)]

    __tostring: =>
        s = "#{@@__name}("
        for i, c in ipairs(@)
            if i > 1
                s ..= ", "
            s ..= tostring(c)
        return s .. ")"

    to: (p) => p - @

    hadamard_prod: (p) => @zipWith(((a, b) -> a * b), p)

    dot: (p) => @hadamard_prod(p)\sum!

    length: => math.sqrt(@map((a) -> a^2)\sum!)

    dist: (p) => @to(p)\length!

    min: => @fold(math.min, math.huge)

    max: => -((-@)\min!)

    cross: (p) =>
        assert(@size == 3 and p.size == 3)
        return @@(@y! * p\z! - @z! * p\y!, @z! * p\x! - @x! * p\z!, @x! * p\y! - @y! * p\x!)

    -- k-th unit basis vector in n-dimensional space
    @unit: (n, k) -> @ [(if i == k then 1 else 0) for i=1,n]


-- nxm matrix. Represented as an "array" of rows, represented by Points
class Matrix extends ClassFix
    -- Possible arguments for constructor:
    -- - A two-dimensional table (table of rows)
    --      Matrix({{1, 2}, {3, 4}})
    -- - A point (to turn into an 1xn matrix)
    --      Matrix(Point({1, 2, 3}))
    -- - A table of points
    --      Matrix([Point({1, 2}), Point({3, 4})])
    -- - A collection of points
    --      Matrix(Point({1, 2}), Point({3, 4}))
    -- Points will be copied first.
    new: (entries, ...) =>
        local rows
        if type(entries[1]) == "number"
            rows = [Point(e) for e in *{entries, ...}]
        elseif entries.__class == Point
            rows = {entries, ...}
        elseif entries[1].__class == Point
            rows = entries
        else
            rows = [Point(r) for r in *entries]

        for i, v in ipairs(rows)
            @[i] = v

        @height = #rows
        @width = #rows[1]

    aslist: () => [ r\aslist! for r in *@]

    project: (...) => [ r\project(...) for r in *@ ]

    square: () => @width == @height

    map: (f) =>
        return @@ [ r\map(f) for r in *@]

    zipWith: (f, p) =>
        assert(@height == p.height and @width == p.width)
        return @@ [ @[i]\zipWith(f, p[i]) for i=1,@height]

    prod: (m) =>
        assert(@width == m.height)
        return @@ [ [Point([@[i][k] * m[k][j] for k=1,@width])\sum! for j=1,m.width] for i=1,@height]

    copy: () => @map(id)

    __eq: (p) =>
        return false unless @width == p.width and @height == p.height
        for i=1,@width
            for j=1,@height
                return false unless @[i][j] == p[i][j]
        return true

    __len: () => @height

    __add: (q) =>
        p = @
        if type(p) == "number"
            return q\map((a) -> p + a)
        if type(q) == "number"
            return p\map((a) -> a + q)
        if p.__class == Point
            p = q.__class ([p for i=1,q.height])
        if q.__class == Point
            q = p.__class ([q for i=1,p.height])
        return p\zipWith(((a, b) -> a + b), q)

    __unm: => @map((a) -> -a)

    __sub: (p) => @ + (-p)

    __mul: (p, q) ->
        if type(p) == "number"
            return q\map((a) -> p * a)
        elseif type(q) == "number"
            return p\map((a) -> a * q)
        elseif q.__class == Point
            q = (Matrix q)\transpose!
        return p\prod(q)

    __div: (p, q) ->
        if type(p) == "number"
            return q\map((a) -> p / a)
        elseif type(q) == "number"
            return p\map((a) -> a / q)
        return p\zipWith(((a, b) -> a / b), q)

    __concat: (q) =>
        p = @
        if type(p) == "number"
            p = Point(p)
        if type(q) == "number"
            q = Point(q)

        if p.__class == Point
            p = q.__class [p for i=1,q.height]
        if q.__class == Point
            q = p.__class [q for i=1,p.height]

        return q.__class [p[i] .. q[i] for i=1,p.height]

    __tostring: =>
        s = "#{@@__name}(\n"
        for r in *@
            s ..= "[ "
            for j, c in ipairs(r)
                if j > 1
                    s ..= " "
                s ..= tostring(c)
            s ..= " ]\n"
        return s .. ")"

    transpose: () =>
        @@ [ [@[i][j] for i=1,@height] for j=1,@width]

    -- shorthand for transpose
    t: () => @transpose!

    -- For an nxn matrix, returns the (n+1)x(n+1) matrix that leaves the k-th canonical basis vector invariant
    -- and acts like the given matrix on the quotient space.
    -- Can also take multiple values to do this iteratively.
    onSubspace: (k, ...) =>
        return @copy! if k == nil
        coordfun = (i, j) ->
            if i == k and j == k
                return 1
            elseif i == k or j == k
                return 0
            return @[if i > k then i - 1 else i][if j > k then j - 1 else j]

        return (@@ [ [coordfun(i, j) for j=1,@height+1] for i=1,@width+1])\onSubspace(...)


    -- Returns the LU decomposition with pivoting, combined in one matrix, together with the permutation
    -- The permutation p is given as a permutation dict to be used when computing the preimage. That is, we decompose
    --      M = P L U
    -- where
    --    P[i][j] = 1 iff p[j] = i
    lu: =>
        assert(@square!)
        n = @width
        m = @aslist!

        p = [i for i=1,n]

        for i=1,n
            -- pivoting
            maxv = -1
            local k
            for j=i,n
                if math.abs(m[j][i]) > maxv
                    k = j
                    maxv = math.abs(m[j][i])

            m[i], m[k] = m[k], m[i]
            p[i], p[k] = p[k], p[i]

            -- LU step
            for j=i,n 		-- R
                for k=1,(i-1)
                    m[i][j] -= m[i][k] * m[k][j]
            for j=(i+1),n 	-- L
                for k=1,(i-1)
                    m[j][i] -= m[j][k] * m[k][i]
                m[j][i] /= m[i][i]

        return @@(m), p

    -- Returns the LU decomposition M = P L U with pivoting by returning the three matrices P, L, U.
    lu_matrices: =>
        lu, pt = @lu!
        n = @width

        l = @@ [ [(if j < i then lu[i][j] else (if j == i then 1 else 0)) for j=1,n] for i=1,n]
        u = @@ [ [(if j >= i then lu[i][j] else 0) for j=1,n] for i=1,n]
        p = @@ [ [(if pt[j] == i then 1 else 0) for j=1,n] for i=1,n]
        
        return p, l, u

    -- If the matrix is an LU decomposition, computes the preimage of y
    luPreim: (b, p) =>
        assert(@square! and @width == #b)
        n = @width
        b = [b[p[i]] for i=1,#b] unless p == nil
        -- forward substitution
        z = {}
        for i=1,n
            z[i] = b[i]
            for j=1,(i-1)
                z[i] -= @[i][j] * z[j]

        -- backward substitution
        x = {}
        for ii=1,n
            i = n + 1 - ii
            x[i] = z[i]
            for j=(i+1),n
                x[i] -= @[i][j] * x[j]
            x[i] /= @[i][i]

        return Point(x)

    preim: (b) =>
        lu, p = @lu!
        return lu\luPreim(b, p)

    det: =>
        lu = @lu!
        return Point([lu[i][i] for i=1,@width])\fold(((a, b) -> a * b), 1)

    inverse: =>
        lu, p = @lu!
        return (@@ [lu\luPreim(Point.unit(@width, k), p) for k=1,@width])\transpose!


    @diag = (...) ->
        diagonal = {...}
        diagonal = diagonal[1] if type(diagonal[1]) == "table"
        return @@ [ [(if i == j then diagonal[i] else 0) for j=1,#diagonal] for i=1,#diagonal]

    @id = (n) ->
        return Matrix [ [(if i == j then 1 else 0) for j=1,n] for i=1,n]

    @rot2d = (phi) ->
        return Matrix {
            {math.cos(phi), -math.sin(phi)},
            {math.sin(phi), math.cos(phi)},
        }


-- transforms each point in the given shape string. The transform argument can either be
-- - a function that takes a 2d Point and returns a 2d Point, or
-- - a 2x2 or 3x3 Matrix. In the case of a 3x3 Matrix, points will be transformed projectively.
--   That is, they'll be given a z coordinate of 1, multiplied by the matrix, and projected back
--   to the z=1 plane.
transformShape = (shape, transform) ->
    if type(transform) == "table" and transform.__class == Matrix
        if #transform == 2
            transform = transform\onSubspace(3)

        mat = transform
        transform = (pt) ->
            pt = Point(mat * (pt .. 1))
            return (pt / pt\z!)\project(2)

    return shape\gsub("([+-%d.eE]+)%s+([+-%d.eE]+)", (x, y) ->
        pt = transform(Point(x, y))
        "#{pt\x!} #{pt\y!}")


lib = {
    :Point,
    :Matrix,
    :transformShape,
}

if haveDepCtrl
    lib.version = depctrl
    return depctrl\register lib
else
    return lib
