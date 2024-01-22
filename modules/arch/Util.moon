DependencyControl = require 'l0.DependencyControl'

depctrl = DependencyControl {
    name: "Util",
    version: "0.1.0",
    description: [[Utility functions used in some of my scripts]],
    author: "arch1t3cht",
    url: "https://github.com/TypesettingTools/arch1t3cht-Aegisub-Scripts",
    moduleName: 'arch.Util',
    {
        {"a-mo.Line", version: "1.5.3", url: "https://github.com/TypesettingTools/Aegisub-Motion",
          feed: "https://raw.githubusercontent.com/TypesettingTools/Aegisub-Motion/DepCtrl/DependencyControl.json"},
        {"l0.ASSFoundation", version: "0.5.0", url: "https://github.com/TypesettingTools/ASSFoundation",
         feed: "https://raw.githubusercontent.com/TypesettingTools/ASSFoundation/master/DependencyControl.json"},
    }
}

Line, ASS = depctrl\requireModules!


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
    tagSections = {}
    sectionEffTags = {}
    sourceData\callback ((section, _, i, j) ->
        tagSections[i] = j
        sectionEffTags[i] = (section\getEffectiveTags true).tags
    ), ASS.Section.Tag

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
                sectionIndex = tr.parent.index
                tagIndex = tagSections[sectionIndex]

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
                    -- FIXME this still breaks in a case like \t(\frx10)\frx20\t(\frx30)
                    -- but that's extremely niche so I'm not fixing it now
                    tagname = tag.__tag.name
                    currValue[tagIndex] or= {}
                    currValue[tagIndex][tagname] or= sectionEffTags[sectionIndex][tagname]
                    local finalValue

                    if tag.class == ASS.Tag.Color
                        finalValue = currValue[tagIndex][tagname]\copy!
                        for channel in *{"r", "g", "b"}
                            finalValue[channel] = finalValue[channel]\lerp tag[channel], k
                    elseif tag.class == ASS.Tag.ClipRect
                        -- ClipRect\lerp exists but does not return the resulting clip. If and when this gets fixed, this can be removed
                        finalValue = currValue[tagIndex][tagname]\copy!
                        for pt in *{"topLeft", "bottomRight"}
                            finalValue[pt] = finalValue[pt]\lerp tag[pt], k
                    else
                        finalValue = currValue[tagIndex][tagname]\lerp tag, k

                    data\replaceTags finalValue, tagIndex, tagIndex, true
                    currValue[tagIndex][tagname] = finalValue

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

            -- Insert all alpha tags so we can modify them later
            -- Don't bother with checking if they exist already, cleanTags will do that for us later
            alphaTags = data\getDefaultTags!\filterTags [ "alpha#{k}" for k=1,4 ]
            if alphaTags.tags.alpha1.value == alphaTags.tags.alpha2.value and alphaTags.tags.alpha1.value == alphaTags.tags.alpha3.value and alphaTags.tags.alpha1.value == alphaTags.tags.alpha4.value
                alphaTags = {ASS\createTag "alpha", alphaTags.tags.alpha1.value}

            data\insertTags alphaTags, 1, 1

            data\modTags {"alpha", "alpha1", "alpha2", "alpha3", "alpha4"}, ((tag) ->
                tag.value = tag.value - (tag.value * fadeVal - 0x7F) / 0xFF + fadeVal
                tag.value = math.max(0, math.min(255, tag.value))
            ) if fadeVal > 0

        data\cleanTags cleanLevel
        data\commit!
        table.insert fbfLines, newLine

    return fbfLines


lib = {
    :round_to_cs,
    :exact_ms_from_frame,
    :line2fbf,
}

lib.version = depctrl
return depctrl\register lib
