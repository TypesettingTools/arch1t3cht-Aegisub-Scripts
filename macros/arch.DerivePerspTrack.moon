export script_name = "Derive Perspective Track"
export script_description = "Create a power-pin track file from the outer perspective quads of a set of lines."
export script_author = "arch1t3cht"
export script_namespace = "arch.DerivePerspTrack"
export script_version = "1.0.0"

haveDepCtrl, DependencyControl = pcall(require, "l0.DependencyControl")
local depctrl
if haveDepCtrl
    depctrl = DependencyControl{
        feed: "https://raw.githubusercontent.com/TypesettingTools/arch1t3cht-Aegisub-Scripts/main/DependencyControl.json",
    }

require "karaskel"

outer_quad_key = "_aegi_perspective_ambient_plane"
translate_outer_powerpin = {1, 2, 4, 3}

-- Reinvent a wheel or two here... this script is really simple so it's worth doing this to avoid having external dependencies
min = (l) ->
    result = math.huge
    for v in *l
        result = math.min(result, v)
    return result

max = (l) -> -min([-v for v in *l])

keys = (l) -> [k for k,v in pairs(l)]

get_outer_quad = (line) ->
    quadinfo = line.extra[outer_quad_key]
    return nil if quadinfo == nil

    x1, y1, x2, y2, x3, y3, x4, y4 = quadinfo\match("^([%d-.]+);([%d-.]+)|([%d-.]+);([%d-.]+)|([%d-.]+);([%d-.]+)|([%d-.]+);([%d-.]+)$")
    return nil if x1 == nil

    return {{x1, x2, x3, x4}, {y1, y2, y3, y4}}


derive_persp_track = (subs, sel) ->
    meta = karaskel.collect_head subs, false
    quads = {}

    for li in *sel
        line = subs[li]
        q = get_outer_quad(line)
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

    minf = min(keys(quads))
    maxf = max(keys(quads))

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
            append "\t#{f - minf}\t#{q[1][j]}\t#{q[2][j]}"

        append ""
    
    append "End of Keyframe Data"

    aegisub.log(table.concat powerpin, "\n")


if haveDepCtrl
    depctrl\registerMacro derive_persp_track
else
    aegisub.register_macro(script_name, script_description, derive_persp_track)