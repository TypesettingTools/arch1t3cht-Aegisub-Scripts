export script_name = "Derive Perspective Track"
export script_description = "Create a power-pin track file from the outer perspective quads of a set of lines."
export script_author = "arch1t3cht"
export script_namespace = "arch.DerivePerspTrack"
export script_version = "1.1.2"

DependencyControl = require("l0.DependencyControl")
dep = DependencyControl{
    feed: "https://raw.githubusercontent.com/TypesettingTools/arch1t3cht-Aegisub-Scripts/main/DependencyControl.json",
    {
        {"l0.Functional", version: "0.6.0", url: "https://github.com/TypesettingTools/Functional",
          feed: "https://raw.githubusercontent.com/TypesettingTools/Functional/master/DependencyControl.json"},
        {"a-mo.LineCollection", version: "1.3.0", url: "https://github.com/TypesettingTools/Aegisub-Motion",
         feed: "https://raw.githubusercontent.com/TypesettingTools/Aegisub-Motion/DepCtrl/DependencyControl.json"},
        {"l0.ASSFoundation", version: "0.5.0", url: "https://github.com/TypesettingTools/ASSFoundation",
         feed: "https://raw.githubusercontent.com/TypesettingTools/ASSFoundation/master/DependencyControl.json"},
        {"arch.Math", version: "0.1.10", url: "https://github.com/TypesettingTools/arch1t3cht-Aegisub-Scripts",
         feed: "https://raw.githubusercontent.com/TypesettingTools/arch1t3cht-Aegisub-Scripts/main/DependencyControl.json"},
        {"arch.Perspective", version: "0.2.3", url: "https://github.com/TypesettingTools/arch1t3cht-Aegisub-Scripts",
         feed: "https://raw.githubusercontent.com/TypesettingTools/arch1t3cht-Aegisub-Scripts/main/DependencyControl.json"},
        "karaskel",
    }
}

Functional, LineCollection, ASS, AMath, APersp = dep\requireModules!
{:Point} = AMath
{:prepareForPerspective, :transformPoints, :Quad} = APersp


outer_quad_key = "_aegi_perspective_ambient_plane"
translate_outer_powerpin = {1, 2, 4, 3}


get_outer_quad = (subs, i) ->
    quadinfo = subs[i].extra[outer_quad_key]
    return nil if quadinfo == nil

    x1, y1, x2, y2, x3, y3, x4, y4 = quadinfo\match("^([%d-.]+);([%d-.]+)|([%d-.]+);([%d-.]+)|([%d-.]+);([%d-.]+)|([%d-.]+);([%d-.]+)$")
    return nil if x1 == nil

    return Quad({{x1, y1}, {x2, y2}, {x3, y3}, {x4, y4}})


get_quad_from_tags = (subs, i) ->
    -- We need to go through LineCollection here to get the styleRef
    lines = LineCollection subs, {i}

    data = ASS\parse(lines.lines[1])
    tags, width, height, warnings = prepareForPerspective(ASS, data)

    for warn in *warnings
        if warn[1] == "move"
            aegisub.log("Failed to derive: line has \\move!")
            aegisub.cancel()
        -- ignore the other ones for now

    return transformPoints(tags, width, height)


derive_persp_track = (derive_fun) -> (subs, sel) ->
    meta = karaskel.collect_head subs, false
    quads = {}

    for li in *sel
        line = subs[li]
        q = derive_fun(subs, li)
        if q == nil
            aegisub.log("Selected line has no outer quad set!")
            aegisub.cancel()

        sf = aegisub.frame_from_ms(line.start_time)
        ef = aegisub.frame_from_ms(line.end_time) - 1

        for f=sf,ef
            if quads[f] != nil
                aegisub.log("Selected lines have overlapping times!")
                aegisub.cancel()
            
            quads[f] = q

    minf = Point(Functional.table.keys(quads))\min()
    maxf = Point(Functional.table.keys(quads))\max()

    powerpin = {}
    append = (s) -> table.insert powerpin, s

    append "Adobe After Effects 6.0 Keyframe Data"
    append ""
    append "\tUnits Per Second\t23.976"
    append "\tSource Width\t#{meta.res_x}"
    append "\tSource Height\t#{meta.res_y}"
    append "\tSource Pixel Aspect Ratio\t1"
    append "\tComp Pixel Aspect Ratio\t1"
    append ""

    for i=1,4
        append "Effects\tCC Power Pin #1\tCC Power Pin-000#{i+1}"
        append "\tFrame\tX pixels\tY pixels"
        j = translate_outer_powerpin[i]

        q = quads[minf]
        for f=minf,maxf
            q = quads[f] unless quads[f] == nil
            append "\t#{f - minf}\t#{q[j][1]}\t#{q[j][2]}"

        append ""
    
    append "End of Keyframe Data"

    aegisub.log(table.concat powerpin, "\n")


dep\registerMacros {
    {"From Outer Quad", "Derive a Power-Pin track from the outer quad set using the perspective tool", derive_persp_track get_outer_quad}
    {"From Tags", "Derive a Power-Pin track from the override tags of the selected lines", derive_persp_track get_quad_from_tags}
}
