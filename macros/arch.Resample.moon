export script_name = "Resample Perspective"
export script_description = "Apply after resampling a script in Aegisub to fix any lines with 3D rotations."
export script_author = "arch1t3cht"
export script_namespace = "arch.Resample"
export script_version = "1.2.0"

DependencyControl = require "l0.DependencyControl"
dep = DependencyControl{
    feed: "https://raw.githubusercontent.com/arch1t3cht/Aegisub-Scripts/main/DependencyControl.json",
    {
        {"a-mo.LineCollection", version: "1.3.0", url: "https://github.com/TypesettingTools/Aegisub-Motion",
         feed: "https://raw.githubusercontent.com/TypesettingTools/Aegisub-Motion/DepCtrl/DependencyControl.json"},
        {"l0.ASSFoundation", version: "0.5.0", url: "https://github.com/TypesettingTools/ASSFoundation",
         feed: "https://raw.githubusercontent.com/TypesettingTools/ASSFoundation/master/DependencyControl.json"},
        {"arch.Math", version: "0.1.4", url: "https://github.com/arch1t3cht/Aegisub-Scripts",
         feed: "https://raw.githubusercontent.com/arch1t3cht/Aegisub-Scripts/main/DependencyControl.json"},
    }
}
LineCollection, ASS, AMath = dep\requireModules!
{:Point, :Matrix} = AMath

logger = dep\getLogger!

screen_z = 312.5

alltags = {"shear_x", "shear_y", "scale_x", "scale_y", "angle", "angle_x", "angle_y", "origin", "position", "outline", "outline_x", "outline_y", "shadow", "shadow_x", "shadow_y"}
usedtags = {"shear_x", "shear_y", "scale_x", "scale_y", "angle", "angle_x", "angle_y", "origin", "position", "outline_x", "outline_y", "shadow_x", "shadow_y"}

an_xshift = { 0, 0.5, 1, 0, 0.5, 1, 0, 0.5, 1 }
an_yshift = { 1, 1, 1, 0.5, 0.5, 0.5, 0, 0, 0 }

transformQuad = (t, width, height) ->
    quad = Matrix {
        {0, 0},
        {width, 0},
        {width, height},
        {0, height},
    }
    pos = Point(t.position.x, t.position.y)
    org = Point(t.origin.x, t.origin.y)

    -- Shearing
    quad *= Matrix({
        {1, t.shear_x.value},
        {t.shear_y.value, 1},
    })\transpose!

    -- Translate to alignment point
    an = t.align.value
    quad -= Point(width * an_xshift[an], height * an_yshift[an])

    -- Apply scaling
    quad = quad\zipWith(((a, b) -> a * b), Matrix([Point(t.scale_x.value / 100, t.scale_y.value / 100) for i=1,4]))

    -- Translate relative to origin
    quad += pos - org

    -- Rotate ZXY
    quad = quad .. 0
    quad *= Matrix.rot2d(math.rad(-t.angle.value))\onSubspace(3)\transpose!
    quad *= Matrix.rot2d(math.rad(-t.angle_x.value))\onSubspace(1)\transpose!
    quad *= Matrix.rot2d(math.rad(t.angle_y.value))\onSubspace(2)\transpose!

    -- Project
    quad = Matrix [ (screen_z / (p\z! + screen_z)) * Point(p\x!, p\y!) for p in *quad ]

    -- Move to origin
    quad += org

    return quad


tagsFromQuad = (t, quad, width, height, center=false) ->
    if center
        diag1 = quad[3] - quad[1]
        diag2 = quad[2] - quad[4]
        b = quad[4] - quad[1]
        center_la = Matrix(diag1, diag2)\transpose!\preim b
        center = quad[1] + center_la[1] * diag1
        t.origin.x = center\x!
        t.origin.y = center\y!

    -- Normalize to center
    quad -= Point(t.origin.x, t.origin.y)

    -- Find a paralellogram projecting to the quad
    z24 = Matrix({ quad[2] - quad[3], quad[4] - quad[3] })\transpose!\preim(quad[1] - quad[3])
    zs = Point(1, z24[1], z24\sum!, z24[2]) * 2 / z24\sum!
    quad ..= screen_z
    quad = Matrix[quad[i] * zs[i] for i=1,4]

    -- Find the rotations
    n = (quad[2] - quad[1])\cross(quad[4] - quad[1])
    roty = math.atan2(n\x!, n\z!)
    ry = Matrix.rot2d(roty)\onSubspace(2)
    n = Point(ry * n)
    rotx = math.atan2(n\y!, n\z!)
    rx = Matrix.rot2d(rotx)\onSubspace(1)

    ab = Point(rx * ry * (quad[2] - quad[1]))
    rotz = math.atan2(ab\y!, ab\x!)
    rz = Matrix.rot2d(-rotz)\onSubspace(3)

    -- We now have a horizontal parallelogram in the 2D plane, so find the shear and the dimensions
    ad = Point(rz * rx * ry * (quad[4] - quad[1]))
    rawfax = ad\x! / ad\y!
    
    scalex = ab\length! / width
    scaley = math.abs(ad\y!) / height

    -- TODO: Figure out what happens here when center = false. Need to transform the entire quad back and find the positioning
    an = t.align.value
    shift = Point(an_xshift[an], an_yshift[an]) - 0.5

    -- Set all the new tags
    pos = Point(t.origin.x, t.origin.y) - Point(height / 2 * rawfax * scaley, 0) + Point(width, height)\hadamard_prod(shift)\hadamard_prod(Point(scalex, scaley))
    t.position.x = pos\x!
    t.position.y = pos\y!
    t.angle.value = math.deg(-rotz)
    t.angle_x.value = math.deg(rotx)
    t.angle_y.value = math.deg(-roty)
    t.scale_x.value = 100 * scalex
    t.scale_y.value = 100 * scaley
    t.shear_x.value = rawfax * scaley / scalex
    t.shear_y.value = 0


resample = (ratiox, ratioy, subs, sel) ->
    anamorphic = math.max(ratiox, ratioy) / math.min(ratiox, ratioy) > 1.01

    lines = LineCollection subs, sel, () -> true
    lines\runCallback (lines, line) ->
        data = ASS\parse line

        -- No perspective tags, we don't need to do anything
        return if not anamorphic and #data\getTags({"angle_x", "angle_y"}) == 0

        tagvals = data\getEffectiveTags(-1, true, true, true).tags
        return if not anamorphic and tagvals.angle_x.value == 0 and tagvals.angle_y.value == 0
        width, height = data\getTextExtents!
        width /= (tagvals.scale_x.value / 100)
        height /= (tagvals.scale_y.value / 100)
        if data\getPosition().class == ASS.Tag.Move
            aegisub.log("Line has \\move! Skipping.")
            return

        -- Manually enforce the relations between tags
        if #data\getTags({"origin"}) == 0
            tagvals.origin.x = tagvals.position.x
            tagvals.origin.y = tagvals.position.y
        for name in *{"outline", "shadow"}
            for coord in *{"x", "y"}
                cname = "#{name}_#{coord}"
                if #data\getTags({cname}) == 0
                    tagvals[cname].value = tagvals[name].value

        -- Set up the tags
        data\removeTags alltags
        data\insertTags [ tagvals[k] for k in *usedtags ]

        -- Revert Aegisub's resampling.
        for tag in *{"position", "origin"}
            tagvals[tag].x *= ratiox
            tagvals[tag].y *= ratioy

        tagvals.scale_x.value *= (ratiox / ratioy)      -- Aspect ratio resampling

        -- Store the previous \fscx\fscy
        oldscale = { k,tagvals[k].value for k in *{"scale_x", "scale_y"} }

        -- Get the original rendered quad
        -- Note that we use ratioy in both dimensions here, since font sizes in .ass rendering
        -- only scale with the height.
        quad = transformQuad(tagvals, ratioy * width, ratioy * height)

        -- Transform it back to the new coordinates
        tagvals.origin.x /= ratiox
        tagvals.origin.y /= ratioy
        quad /= Matrix([ {ratiox, ratioy} for i=1,4 ])
        tagsFromQuad(tagvals, quad, width, height, true)    -- TODO get center=false working

        -- Correct \bord and \shad for the \fscx\fscy change
        for name in *{"outline", "shadow"}
            for coord in *{"x", "y"}
                tagvals["#{name}_#{coord}"].value *= tagvals["scale_#{coord}"].value / oldscale["scale_#{coord}"]

        -- Rejoice
        data\cleanTags 4
        data\commit!
    lines\replaceLines!


resample_ui = (subs, sel) ->
    video_width, video_height = aegisub.video_size!

    button, results = aegisub.dialog.display({{
        class: "label",
        label: "Source Resolution: ",
        x: 0, y: 0, width: 1, height: 1,
    }, {
        class: "intedit",
        name: "srcresx",
        value: 1280,
        x: 1, y: 0, width: 1, height: 1,
    }, {
        class: "label",
        label: "x",
        x: 2, y: 0, width: 1, height: 1,
    }, {
        class: "intedit",
        name: "srcresy",
        value: 720,
        x: 3, y: 0, width: 1, height: 1,
    }, {
        class: "label",
        label: "Target Resolution: ",
        x: 0, y: 1, width: 1, height: 1,
    }, {
        class: "intedit",
        name: "targetresx",
        value: video_width or 1920,
        x: 1, y: 1, width: 1, height: 1,
    }, {
        class: "label",
        label: "x",
        x: 2, y: 1, width: 1, height: 1,
    }, {
        class: "intedit",
        name: "targetresy",
        value: video_height or 1080,
        x: 3, y: 1, width: 1, height: 1,
    }})

    resample(results.srcresx / results.targetresx, results.srcresy / results.targetresy, subs, sel) if button

dep\registerMacro resample_ui
