export script_name = "Aegisub Perspective-Motion"
export script_description = "Apply perspective motion tracking data"
export script_author = "arch1t3cht"
export script_namespace = "arch.PerspectiveMotion"
export script_version = "0.1.3"

DependencyControl = require "l0.DependencyControl"
dep = DependencyControl{
    feed: "https://raw.githubusercontent.com/TypesettingTools/arch1t3cht-Aegisub-Scripts/main/DependencyControl.json",
    {
        {"a-mo.Line", version: "1.5.3", url: "https://github.com/TypesettingTools/Aegisub-Motion",
          feed: "https://raw.githubusercontent.com/TypesettingTools/Aegisub-Motion/DepCtrl/DependencyControl.json"},
        {"a-mo.LineCollection", version: "1.3.0", url: "https://github.com/TypesettingTools/Aegisub-Motion",
         feed: "https://raw.githubusercontent.com/TypesettingTools/Aegisub-Motion/DepCtrl/DependencyControl.json"},
        {"l0.ASSFoundation", version: "0.5.0", url: "https://github.com/TypesettingTools/ASSFoundation",
         feed: "https://raw.githubusercontent.com/TypesettingTools/ASSFoundation/master/DependencyControl.json"},
        {"arch.Math", version: "0.1.10", url: "https://github.com/TypesettingTools/arch1t3cht-Aegisub-Scripts",
         feed: "https://raw.githubusercontent.com/TypesettingTools/arch1t3cht-Aegisub-Scripts/main/DependencyControl.json"},
        {"arch.Perspective", version: "1.1.0", url: "https://github.com/TypesettingTools/arch1t3cht-Aegisub-Scripts",
         feed: "https://raw.githubusercontent.com/TypesettingTools/arch1t3cht-Aegisub-Scripts/main/DependencyControl.json"},
        "aegisub.clipboard",
    }
}
Line, LineCollection, ASS, AMath, APersp, clipboard = dep\requireModules!
{:Point, :Matrix} = AMath
{:Quad, :an_xshift, :an_yshift, :relevantTags, :usedTags, :transformPoints, :tagsFromQuad, :prepareForPerspective} = APersp

logger = dep\getLogger!

die = (errmsg) ->
    aegisub.log(errmsg .. "\n")
    aegisub.cancel!

-- rounds a ms timestamp to cs just like Aegisub does
round_to_cs = (time) ->
    (time + 5) - (time + 5) % 10

-- gets the exact starting timestamp of a given frame,
-- unlike aegisub.frame_from_ms, which returns a timestamp in the
-- middle of the frame suitable for a line's start time.
exact_ms_from_frame = (frame) ->
    frame += 1

    ms = aegisub.ms_from_frame(frame)
    while true
        new_ms = ms - 1
        if new_ms < 0 or aegisub.frame_from_ms(new_ms) != frame
            break

        ms = new_ms

    return ms - 1

-- line2fbf function, modified from a function by PhosCity
line2fbf = (sourceData, cleanLevel = 3) ->
    line, effTags = sourceData.line, (sourceData\getEffectiveTags -1, true, true, false).tags
    -- Aegisub will never give us timestamps that aren't rounded to centiseconds, but lua code might.
    -- Explicitly round to centiseconds just to be sure.
    startTime = round_to_cs line.start_time
    startFrame = line.startFrame
    endFrame = line.endFrame

    -- Tag Collection
    local fade
    -- Fade
    for tag in *{"fade_simple", "fade"}
        fade = sourceData\getTags(tag, 1)[1]
        break if fade
    -- Transform
    transforms = sourceData\getTags "transform"

    -- Fbfing
    fbfLines = {}
    for frame = startFrame, endFrame-1
        newLine = Line sourceData.line, sourceData.line.parentCollection
        newLine.start_time = aegisub.ms_from_frame(frame)
        newLine.end_time = aegisub.ms_from_frame(frame + 1)
        data = ASS\parse newLine
        now = exact_ms_from_frame(frame) - startTime

        -- Move
        move = effTags.move
        if move and not move.startPos\equal move.endPos
            t1, t2 = move.startTime.value, move.endTime.value

            -- Does assf handle this for us already? Who knows, certainly not me!
            t1 or= 0
            t2 or= 0

            t1, t2 = t2, t1 if t1 > t2

            if t1 <= 0 and t2 <= 0
                t1 = 0
                t2 = line.duration

            local k
            if now <= t1
                k = 0
            elseif now >= t2
                k = 1
            else
                k = (now - t1) / (t2 - t1)

            finalPos = move.startPos\lerp(move.endPos, k)
            data\removeTags "move"
            data\replaceTags {ASS\createTag "position", finalPos}

        -- Transform
        if #transforms > 0
            currValue = {}
            data\removeTags "transform"
            for tr in *transforms
                t1 = tr.startTime\get!
                t2 = tr.endTime\get!

                t2 = line.duration if t2 == 0

                accel = tr.accel\get! or 1

                local k
                if now < t1
                    k = 0
                elseif now >= t2
                    k = 1
                else
                    k = ((now - t1) / (t2 - t1))^accel

                for tag in *tr.tags\getTags!
                    tagname = tag.__tag.name
                    -- FIXME this can break when there's more than one section
                    -- or for certain orders of tags
                    currValue[tagname] or= effTags[tagname]
                    local finalValue
                    if tag.class == ASS.Tag.Color
                        finalValue = currValue[tagname]\lerpRGB tag, fac
                    else
                        finalValue = currValue[tagname]\lerp tag, fac
                    data\replaceTags finalValue
                    currValue[tagname] = finalValue

        -- Fade
        if fade
            local a1, a2, a3, t1, t2, t3, t4
            if fade.__tag.name == "fade_simple"
                a1, a2, a3  = 255, 0, 255
                t1, t4 = -1, -1
                t2, t3 = fade.inDuration\getTagParams!, fade.outDuration\getTagParams!
            else
                a1, a2, a3, t1, t2, t3, t4 = fade\getTagParams!

            if t1 == -1 and t4 == -1
                t1 = 0
                t4 = line.duration
                t3 = t4 - t3

            local fadeVal
            if now < t1
                fadeVal = a1
            elseif now < t2
                k = (now - t1)/(t2 - t1)
                fadeVal = a1 * (1 - k) + a2 * k
            elseif now < t3
                fadeVal = a2
            elseif now < t4
                k = (now - t3)/(t4 - t3)
                fadeVal = a2 * (1 - k) + a3 * k
            else
                fadeVal = a3

            data\removeTags {"fade", "fade_simple"}

            data\modTags {"alpha", "alpha1", "alpha2", "alpha3", "alpha4"}, ((tag) ->
                tag.value = tag.value - (tag.value * fadeVal - 0x7F) / 0xFF + fadeVal
                tag.value = math.max(0, math.min(255, tag.value))
            ) if fadeVal > 0

        data\cleanTags cleanLevel
        data\commit!
        table.insert fbfLines, newLine

    return fbfLines


track = (quads, options, subs, sel, active) ->
    lines = LineCollection subs, sel, () -> true

    die("Invalid relative frame") if options.relframe < 1 or options.relframe > #quads

    -- First, FBF everything
    to_delete = {}
    lines\runCallback ((lines, line) ->
        data = ASS\parse line

        table.insert to_delete, line

        fbf = line2fbf data
        for fbfline in *fbf
            lines\addLine fbfline
    ), true

    -- Then, find the line we do everything relative to

    -- FIXME This gets weird when there's more than one line visible at the relative frame.
    --     The script can't really read the user's mind here but in theory there could be a system
    --     that allows for tracking multiple sets of lines at once like the old persp-mo had
    --     (although that was only really necessary back when that wasn't able to fbf).
    --     I won't bother with doing this until anyone actually needs this, though

    rel_quad = quads[options.relframe]

    local rel_line
    lines\runCallback (lines, line) ->
        rel_line = line if line.startFrame == lines.startFrame + options.relframe - 1

    die("No line at relative frame!") if rel_line == nil

    -- If we're supposed to apply the perspective, apply it to the relative line
    if options.applyperspective
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

        tagsFromQuad(tagvals, rect_at_pos(1, 1), width, height, options.orgmode)

        tagsFromQuad(tagvals, rect_at_pos(oldscale.scale_x / tagvals.scale_x.value, oldscale.scale_y / tagvals.scale_y.value), width, height, options.orgmode)

        -- we don't need to adjust bord/shad since we're going for no change in scale

        data\cleanTags 4
        data\commit!

    -- Find some more data for the relative line
    local rel_line_tags
    local rel_line_quad
    do
        data = ASS\parse rel_line
        rel_line_tags, width, height, warnings = prepareForPerspective(ASS, data)     -- ignore warnings
        rel_line_quad = transformPoints(rel_line_tags, width, height)

    -- Then, do the actual tracking
    lines\runCallback (lines, line) ->
        data = ASS\parse line
        frame_quad = quads[line.startFrame - lines.startFrame + 1]

        tagvals, width, height, warnings = prepareForPerspective(ASS, data)     -- ignore warnings
        oldscale = { k,tagvals[k].value for k in *{"scale_x", "scale_y"} }

        uv_quad = Quad [ rel_quad\xy_to_uv(p) for p in *rel_line_quad ]
        if not options.trackpos
            -- Is this mode even useful in practice? Who knows!
            uv_quad += frame_quad\xy_to_uv(Point(tagvals.position.x, tagvals.position.y)) - rel_quad\xy_to_uv(Point(rel_line_tags.position.x, rel_line_tags.position.y))
            -- This breaks if the lines have different alignments or if the relative line has its position shifted by something like \fax. If you have a better idea to find positions (and an actual use case for all this) I'd love to hear it.

        target_quad = Quad [ frame_quad\uv_to_xy(p) for p in *uv_quad ]

        -- Set up the tags
        data\removeTags relevantTags
        data\insertTags [ tagvals[k] for k in *usedTags ]

        tagsFromQuad(tagvals, target_quad, width, height, options.orgmode)

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
    die("The length of the tracking data does not match the selected lines.") if #quads != selection_frames

    track(quads, results, subs, sel, active)

dep\registerMacro main_dialog

