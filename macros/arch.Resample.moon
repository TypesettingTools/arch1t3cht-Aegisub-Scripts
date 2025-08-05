export script_name = "Resample Perspective"
export script_description = "Apply after resampling a script in Aegisub to fix any lines with 3D rotations."
export script_author = "arch1t3cht"
export script_namespace = "arch.Resample"
export script_version = "2.1.1"

DependencyControl = require "l0.DependencyControl"
dep = DependencyControl{
    feed: "https://raw.githubusercontent.com/TypesettingTools/arch1t3cht-Aegisub-Scripts/main/DependencyControl.json",
    {
        {"a-mo.LineCollection", version: "1.3.0", url: "https://github.com/TypesettingTools/Aegisub-Motion",
         feed: "https://raw.githubusercontent.com/TypesettingTools/Aegisub-Motion/DepCtrl/DependencyControl.json"},
        {"l0.ASSFoundation", version: "0.5.0", url: "https://github.com/TypesettingTools/ASSFoundation",
         feed: "https://raw.githubusercontent.com/TypesettingTools/ASSFoundation/master/DependencyControl.json"},
        {"arch.Math", version: "0.1.8", url: "https://github.com/TypesettingTools/arch1t3cht-Aegisub-Scripts",
         feed: "https://raw.githubusercontent.com/TypesettingTools/arch1t3cht-Aegisub-Scripts/main/DependencyControl.json"},
        {"arch.Perspective", version: "1.2.1", url: "https://github.com/TypesettingTools/arch1t3cht-Aegisub-Scripts",
         feed: "https://raw.githubusercontent.com/TypesettingTools/arch1t3cht-Aegisub-Scripts/main/DependencyControl.json"},
    }
}
LineCollection, ASS, AMath, APersp = dep\requireModules!
{:Matrix} = AMath
{:relevantTags, :usedTags, :transformPoints, :tagsFromQuad, :prepareForPerspective} = APersp

logger = dep\getLogger!

resample = (ratiox, ratioy, orgmode, subs, sel) ->
    anamorphic = math.max(ratiox, ratioy) / math.min(ratiox, ratioy) > 1.01

    lines = LineCollection subs, sel, () -> true
    lines\runCallback (lines, line) ->
        data = ASS\parse line

        -- No perspective tags, we don't need to do anything
        return if not anamorphic and #data\getTags({"angle_x", "angle_y"}) == 0

        tagvals, width, height, warnings = prepareForPerspective(ASS, data)

        for warn in *warnings
            switch warn[1]
                when "multiple_tags"
                    aegisub.log("Warning: Line #{line.humanizedNumber} has more than one #{warn[2]} tag! This might break resampling.\n") if warn[2] == "\\frx" or warn[2] == "\\fry"
                when "transform"
                    aegisub.log("Warning: Line #{line.humanizedNumber} contains a #{warn[2]} tag in a transform tag! This might break resampling.\n") if warn[2] == "\\frx" or warn[2] == "\\fry"

        return if not anamorphic and tagvals.angle_x.value == 0 and tagvals.angle_y.value == 0

        for warn in *warnings
            switch warn[1]
                when "multiple_tags"
                    aegisub.log("Warning: Line #{line.humanizedNumber} has more than one #{warn[2]} tag! This might break resampling.\n")
                when "transform"
                    aegisub.log("Warning: Line #{line.humanizedNumber} contains a #{warn[2]} tag in a transform tag! This might break resampling.\n")
                when "zero_size"
                    aegisub.log("Warning: Line #{line.humanizedNumber} has zero width or height!\n")
                when "move"
                    aegisub.log("Line #{line.humanizedNumber} has \\move! Skipping.\n")
                    return
                when "text_and_drawings"
                    aegisub.log("Line #{line.humanizedNumber} has both text and drawings! Skipping.\n")
                    return
                else
                    aegisub.log("Unknown warning on line #{line.humanizedNumber}: #{warn[1]}\n")

        -- Set up the tags
        data\removeTags relevantTags
        data\insertTags [ tagvals[k] for k in *usedTags ]

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
        quad = transformPoints(tagvals, ratioy * width, ratioy * height)

        -- Transform it back to the new coordinates
        tagvals.origin.x /= ratiox
        tagvals.origin.y /= ratioy
        quad *= Matrix.diag(1 / ratiox, 1 / ratioy)
        tagsFromQuad(tagvals, quad, width, height, orgmode)

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

    orgmodes = {
        "Keep original \\org",
        "Force center \\org",
        "Try to force \\fax0",
    }
    orgmodes_flip = {v,k for k,v in pairs(orgmodes)}

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
    }, {
        class: "label",
        label: "\\org mode: ",
        x: 0, y: 2, width: 1, height: 1,
    }, {
        class: "dropdown",
        value: orgmodes[1],
        items: orgmodes,
        hint: "Controls how \\org will be handled when computing perspective tags, analogously to modes in Aegisub's perspective tool. This option should not change rendering except for rounding errors.",
        name: "orgmode",
        x: 1, y: 2, width: 2, height: 1,
    }})

    resample(results.srcresx / results.targetresx, results.srcresy / results.targetresy, orgmodes_flip[results.orgmode], subs, sel) if button

dep\registerMacro resample_ui
