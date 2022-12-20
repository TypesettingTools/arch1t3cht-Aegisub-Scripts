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
        {"arch.Math", version: "0.1.6", url: "https://github.com/arch1t3cht/Aegisub-Scripts",
         feed: "https://raw.githubusercontent.com/arch1t3cht/Aegisub-Scripts/main/DependencyControl.json"},
        {"arch.Perspective", version: "0.1.0", url: "https://github.com/arch1t3cht/Aegisub-Scripts",
         feed: "https://raw.githubusercontent.com/arch1t3cht/Aegisub-Scripts/main/DependencyControl.json"},
    }
}
LineCollection, ASS, AMath, APersp = dep\requireModules!
{:Matrix} = AMath
{:transformPoints, :tagsFromQuad} = APersp

logger = dep\getLogger!

alltags = {"shear_x", "shear_y", "scale_x", "scale_y", "angle", "angle_x", "angle_y", "origin", "position", "outline", "outline_x", "outline_y", "shadow", "shadow_x", "shadow_y"}
usedtags = {"shear_x", "shear_y", "scale_x", "scale_y", "angle", "angle_x", "angle_y", "origin", "position", "outline_x", "outline_y", "shadow_x", "shadow_y"}


resample = (ratiox, ratioy, centerorg, subs, sel) ->
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
        quad = transformPoints(tagvals, ratioy * width, ratioy * height)

        -- Transform it back to the new coordinates
        tagvals.origin.x /= ratiox
        tagvals.origin.y /= ratioy
        quad *= Matrix.diag(1 / ratiox, 1 / ratioy)
        tagsFromQuad(tagvals, quad, width, height, centerorg)

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
    }, {
        class: "checkbox",
        label: "Force center \\org",
        hint: "If on, all lines will use the center of their quad as the \\org point. If off, the \\org of the lines will be preserved. This option should not change rendering except for rounding errors."
        name: "centerorg"
        x: 0, y: 2, width: 2, height: 1,
    }})

    resample(results.srcresx / results.targetresx, results.srcresy / results.targetresy, results.centerorg, subs, sel) if button

dep\registerMacro resample_ui
