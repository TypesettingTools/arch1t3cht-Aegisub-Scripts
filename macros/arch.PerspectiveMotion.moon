export script_name = "Aegisub Perspective-Motion"
export script_description = "Apply perspective motion tracking data"
export script_author = "arch1t3cht"
export script_namespace = "arch.PerspectiveMotion"
export script_version = "0.3.1"

DependencyControl = require "l0.DependencyControl"
dep = DependencyControl{
    feed: "https://raw.githubusercontent.com/TypesettingTools/arch1t3cht-Aegisub-Scripts/main/DependencyControl.json",
    {
        {"a-mo.LineCollection", version: "1.3.0", url: "https://github.com/TypesettingTools/Aegisub-Motion",
         feed: "https://raw.githubusercontent.com/TypesettingTools/Aegisub-Motion/DepCtrl/DependencyControl.json"},
        {"l0.ASSFoundation", version: "0.5.0", url: "https://github.com/TypesettingTools/ASSFoundation",
         feed: "https://raw.githubusercontent.com/TypesettingTools/ASSFoundation/master/DependencyControl.json"},
        {"arch.Math", version: "0.1.10", url: "https://github.com/TypesettingTools/arch1t3cht-Aegisub-Scripts",
         feed: "https://raw.githubusercontent.com/TypesettingTools/arch1t3cht-Aegisub-Scripts/main/DependencyControl.json"},
        {"arch.Perspective", version: "1.2.1", url: "https://github.com/TypesettingTools/arch1t3cht-Aegisub-Scripts",
         feed: "https://raw.githubusercontent.com/TypesettingTools/arch1t3cht-Aegisub-Scripts/main/DependencyControl.json"},
        {"arch.Util", version: "0.1.0", url: "https://github.com/TypesettingTools/arch1t3cht-Aegisub-Scripts",
         feed: "https://raw.githubusercontent.com/TypesettingTools/arch1t3cht-Aegisub-Scripts/main/DependencyControl.json"},
        "aegisub.clipboard",
    }
}
LineCollection, ASS, AMath, APersp, Util, clipboard = dep\requireModules!
{:Point, :Matrix} = AMath
{:Quad, :an_xshift, :an_yshift, :relevantTags, :usedTags, :transformPoints, :tagsFromQuad, :prepareForPerspective} = APersp

complained_about_layout_res = {}

logger = dep\getLogger!

die = (errmsg) ->
    aegisub.log(errmsg .. "\n")
    aegisub.cancel!


track = (quads, options, subs, sel, active) ->
    lines = LineCollection subs, sel, () -> true
    videoW, videoH = aegisub.video_size!
    layoutScale = lines.meta.PlayResY / (lines.meta.LayoutResY or videoH)

    if layoutScale != 1 and not complained_about_layout_res[aegisub.file_name! or ""]
        complained_about_layout_res[aegisub.file_name! or ""] = true
        if lines.meta.LayoutResY
            aegisub.log("Your file's LayoutResY (#{lines.meta.LayoutResY}) does not match its PlayResY (#{lines.meta.PlayResY}). Unless you know what you're doing you should probably resample to make them match.")
        else
            aegisub.log("Your file's LPlayResY (#{lines.meta.PlayResY}) does not match your video's height (#{videoH}). You may want to set a LayoutResY for your file.")

    die("Invalid relative frame") if options.relframe < 1 or options.relframe > #quads

    abs_relframe = options.selection_start_frame + options.relframe - 1

    -- First, find out what lines should be transformed relative to which other lines
    frame2line = {}
    lines_intersect = false
    all_contain_relframe = true
    lines\runCallback (lines, line) ->
        all_contain_relframe and= (line.startFrame <= abs_relframe and abs_relframe < line.endFrame)
        for frame=line.startFrame,(line.endFrame - 1)
            lines_intersect = true if frame2line[frame]
            frame2line[frame] = line

    if lines_intersect and not all_contain_relframe
        die("Times of selected lines intersect but not all lines contain the reference frame. I don't know what to do with this. If you think of a way to make this script read the user's mind, let me know.")

    die("No line at reference frame!") if not frame2line[abs_relframe]

    rel_lines = {}
    local single_rel_line

    -- Then, FBF everything and find the lines we work relative to
    to_delete = {}
    lines\runCallback ((lines, line) ->
        data = ASS\parse line

        table.insert to_delete, line
        line.willdelete = true

        fbf = Util.line2fbf data
        for fbfline in *fbf
            lines\addLine fbfline

            if all_contain_relframe
                fbfline.rel_line = fbf[abs_relframe - line.startFrame + 1]
                rel_lines[fbfline.rel_line] = 1
            elseif fbfline.startFrame == abs_relframe
                single_rel_line = fbfline
                rel_lines[fbfline] = 1
    ), true

    rel_quad = quads[options.relframe]

    -- If we're supposed to apply the perspective, apply it to the relative lines
    if options.applyperspective
        for rel_line,_ in pairs(rel_lines)
            data = ASS\parse rel_line

            tagvals, width, height, warnings = prepareForPerspective(ASS, data)
            -- ignore the warnings because I'm lazy and this script isn't usually run unsupervised

            pos = Point(tagvals.position.x, tagvals.position.y)

            oldscale = { k,tagvals[k].value for k in *{"scale_x", "scale_y"} }

            -- Really, blindly applying perspective to some quad isn't a good idea (and not really necessary
            -- either now that there's a perspective tool), but some people want it.
            -- The problem is that it's not really clear what \fscx and \fscy should be, but I guess the
            -- most natural choice is just picking a perspective that does not change \fscx and \fscy
            -- (i.e. that keeps them at 100 if they weren't explicitly specified before).
            -- So the plan is to transform the line to the entire quad, see what \fscx and \fscy end up at,
            -- and use the inverses of those values to find the actual quad we want to transform to.

            data\removeTags relevantTags
            data\insertTags [ tagvals[k] for k in *usedTags ]

            rect_at_pos = (width, height) ->
                result = Quad.rect 1, 1
                result -= Point(an_xshift[tagvals.align.value], an_yshift[tagvals.align.value])
                result *= (Matrix.diag(width, height))
                result += rel_quad\xy_to_uv(pos)   -- This breaks if the line already has some perspective but honestly if you run the script like that then that's on you
                result = Quad [ rel_quad\uv_to_xy(p) for p in *result ]
                return result

            tagsFromQuad(tagvals, rect_at_pos(1, 1), width, height, options.orgmode, layoutScale)

            tagsFromQuad(tagvals, rect_at_pos(oldscale.scale_x / tagvals.scale_x.value, oldscale.scale_y / tagvals.scale_y.value), width, height, options.orgmode, layoutScale)

            -- we don't need to adjust bord/shad since we're going for no change in scale

            data\cleanTags 4
            data\commit!

    -- Find some more data for the relative lines
    for rel_line,_ in pairs(rel_lines)
        data = ASS\parse rel_line
        rel_line_tags, width, height, warnings = prepareForPerspective(ASS, data)     -- ignore warnings
        rel_line_quad = transformPoints(rel_line_tags, width, height, nil, layoutScale)

        rel_line.tags = rel_line_tags
        rel_line.quad = rel_line_quad

    -- Then, do the actual tracking
    lines\runCallback (lines, line) ->
        return if line.willdelete
        line.rel_line or= single_rel_line

        data = ASS\parse line
        frame_quad = quads[line.startFrame - lines.startFrame + 1]

        tagvals, width, height, warnings = prepareForPerspective(ASS, data)     -- ignore warnings
        oldscale = { k,tagvals[k].value for k in *{"scale_x", "scale_y"} }

        uv_quad = Quad [ rel_quad\xy_to_uv(p) for p in *line.rel_line.quad ]
        if not options.trackpos
            -- Is this mode even useful in practice? Who knows!
            uv_quad += frame_quad\xy_to_uv(Point(tagvals.position.x, tagvals.position.y)) - rel_quad\xy_to_uv(Point(line.rel_line.tags.position.x, line.rel_line.tags.position.y))
            -- This breaks if the lines have different alignments or if the relative line has its position shifted by something like \fax. If you have a better idea to find positions (and an actual use case for all this) I'd love to hear it.

        target_quad = Quad [ frame_quad\uv_to_xy(p) for p in *uv_quad ]

        -- Set up the tags
        data\removeTags relevantTags
        data\insertTags [ tagvals[k] for k in *usedTags ]

        tagsFromQuad(tagvals, target_quad, width, height, options.orgmode, layoutScale)

        -- -- Correct \bord and \shad for the \fscx\fscy change
        if options.trackbordshad
            for name in *{"outline", "shadow"}
                for coord in *{"x", "y"}
                    tagvals["#{name}_#{coord}"].value *= tagvals["scale_#{coord}"].value / oldscale["scale_#{coord}"]

        if options.trackclip
            clip = (data\getTags {"clip_vect", "iclip_vect"})[1]
            if clip == nil
                rect = (data\removeTags {"clip_rect", "iclip_rect"})[1]
                if rect != nil
                    clip = rect\getVect!
                    clip\setInverse rect.__tag.inverse  -- Because apparently assf sometimes decides to invert the clip?
                    data\insertTags clip

            if clip != nil
                -- I'm sure there's a better way to do this but oh well...
                for cont in *clip.contours
                    for cmd in *cont.commands
                        for pt in *cmd\getPoints(true)
                            -- We cannot exactly transform clips that contain cubic curves or splines,
                            -- the best we can do is map all coordinates. For polygons this is accurate.
                            -- If users need full accuracy, they can flatten their clip first.
                            p = Point(pt.x, pt.y)
                            uv = rel_quad\xy_to_uv p
                            q = frame_quad\uv_to_xy uv
                            pt.x = q\x!
                            pt.y = q\y!

        -- Rejoice
        data\cleanTags 4
        data\commit!

        if options.includeextra
            line.extra["_aegi_perspective_ambient_plane"] = table.concat(["#{frame_quad[i]\x!};#{frame_quad[i]\y!}" for i=1,4], "|")

    lines\insertLines!
    lines\deleteLines to_delete


parse_single_pin = (lines, marker) ->
    pin_pos = [ k for k, line in ipairs(lines) when line\match("^Effects[\t ]+CC Power Pin #1[\t ]+CC Power Pin%-#{marker}$") ]

    if #pin_pos != 1
        return nil

    i = pin_pos[1] + 2

    x = {}
    y = {}
    while lines[i]\match("^[\t ]+[0-9]")
        values = [ t for t in string.gmatch(lines[i], "%S+") ]
        table.insert(x, values[2])
        table.insert(y, values[3])
        i += 1

    return x, y

-- function that contains everything that happens before the transforms
parse_powerpin_data = (powerpin) ->
    -- Putting the user input into a table
    lines = [ line for line in string.gmatch(powerpin, "([^\n]*)\n?") ]

    return nil unless #([l for l in *lines when l\match"Effects[\t ]+CC Power Pin #1[\t ]+CC Power Pin%-0002"]) != 0

    -- FIXME sanity check more things here like the resolution and frame rate matching

    -- Filtering out everything other than the data, and putting them into their own tables.
    -- Power Pin data goes like this: TopLeft=0002, TopRight=0003, BottomRight=0005,  BottomLeft=0004
    x1, y1 = parse_single_pin(lines, "0002")
    x2, y2 = parse_single_pin(lines, "0003")
    x3, y3 = parse_single_pin(lines, "0005")
    x4, y4 = parse_single_pin(lines, "0004")

    return nil if #x1 != #x2
    return nil if #x1 != #x3
    return nil if #x1 != #x4

    return [Quad {{x1[i], y1[i]}, {x2[i], y2[i]}, {x3[i], y3[i]}, {x4[i], y4[i]}} for i=1,#x1]


main_dialog = (subs, sel, active) ->
    die("You need to have a video loaded for frame-by-frame tracking.") if aegisub.frame_from_ms(0) == nil

    active_line = subs[active]

    selection_start_frame = Point([ aegisub.frame_from_ms(subs[si].start_time) for si in *sel ])\min!
    selection_end_frame = Point([ aegisub.frame_from_ms(subs[si].end_time) for si in *sel ])\max!
    selection_frames = selection_end_frame - selection_start_frame

    clipboard_input = clipboard.get() or ""
    clipboard_data = parse_powerpin_data(clipboard_input)
    prefilled_data = if clipboard_data != nil and #clipboard_data == selection_frames then clipboard_input else ""

    lazy_heuristic = tonumber(active_line.text\match("\\fr[xy]([-.%deE]+)"))
    has_perspective = lazy_heuristic != nil and lazy_heuristic != 0

    video_frame = aegisub.project_properties().video_position
    rel_frame = if video_frame >= selection_start_frame and video_frame < selection_end_frame then 1 + video_frame - selection_start_frame else 1

    orgmodes = {
        "Keep original \\org",
        "Force center \\org",
        "Try to force \\fax0",
    }
    orgmodes_flip = {v,k for k,v in pairs(orgmodes)}

    button, results = aegisub.dialog.display({{
        class: "label",
        label: "Paste your Power-Pin data here:               ",
        x: 0, y: 0, width: 1, height: 1,
    }, {
        class: "textbox",
        name: "data",
        value: prefilled_data,
        x: 0, y: 1, width: 1, height: 7,
    }, {
        class: "label",
        label: "Relative to frame ",
        x: 1, y: 1, width: 1, height: 1,
    }, {
        class: "intedit",
        value: rel_frame,
        name: "relframe",
        min: 1, max: selection_frames,
        x: 2, y: 1, width: 1, height: 1,
    }, {
        class: "label",
        label: "\\org mode: ",
        x: 1, y: 2, width: 1, height: 1,
    }, {
        class: "dropdown",
        value: orgmodes[1],
        items: orgmodes,
        hint: "Controls how \\org will be handled when computing perspective tags, analogously to modes in Aegisub's perspective tool. This option should not change rendering except for rounding errors.",
        name: "orgmode",
        x: 2, y: 2, width: 1, height: 1,
    }, {
        class: "checkbox",
        name: "applyperspective",
        label: "Apply perspective",
        value: not has_perspective,
        x: 1, y: 3, width: 2, height: 1,
    }, {
        class: "checkbox",
        name: "includeextra",
        label: "Add quad to extradata",
        value: true,
        x: 1, y: 4, width: 2, height: 1,
    }, {
        class: "checkbox",
        name: "trackpos",
        label: "Track position",
        value: true,
        x: 0, y: 8, width: 1, height: 1,
    }, {
        class: "checkbox",
        name: "trackclip",
        label: "Track clips",
        value: true,
        x: 0, y: 9, width: 1, height: 1,
    }, {
        class: "checkbox",
        name: "trackbordshad",
        label: "Scale \\bord and \\shad",
        value: true,
        x: 0, y: 10, width: 1, height: 1,
    }})

    return if not button

    die("No tracking data provided!") if results.data == ""

    quads = parse_powerpin_data results.data

    die("Invalid tracking data!") if quads == nil
    die("The length of the tracking data (#{#quads}) does not match the selected lines (#{selection_frames}).") if #quads != selection_frames

    results.selection_start_frame = selection_start_frame

    track(quads, results, subs, sel, active)

dep\registerMacro main_dialog

