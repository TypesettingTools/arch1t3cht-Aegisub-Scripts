export script_name = "Split Tag Sections"
export script_description = "Split subtitle lines at tags, creating a separate event for each section"
export script_author = "arch1t3cht"
export script_namespace = "arch.SplitSections"
export script_version = "0.1.1"

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
    }
}
Line, LineCollection, ASS = dep\requireModules!

an_xshift = { 0, 0.5, 1, 0, 0.5, 1, 0, 0.5, 1 }
an_yshift = { 1, 1, 1, 0.5, 0.5, 0.5, 0, 0, 0 }

logger = dep\getLogger!

split = (subs, sel) ->
    lines = LineCollection subs, sel, () -> true

    toDelete = {}

    lines\runCallback (lines, line) ->
        data = ASS\parse line

        efftags = data\getEffectiveTags(-1, true, true, true).tags
        pos = data\getPosition()
        if pos.class == ASS.Tag.Move
            aegisub.log("Warning: Line #{line.humanizedNumber} has \\move. Skipping.")
            return

        table.insert toDelete, line

        an = efftags.align.value
        hasorg = #data\getTags({"origin"}) != 0

        x = 0
        y = 0

        lineheight = 0
        linedescent = 0

        splitLines = {}

        data\callback (section, _, i, j) ->
            return unless section.class == ASS.Section.Text or section.class == ASS.Section.Drawing

            -- TODO handle newlines

            splitLine = Line line, lines, {ASS: {}}
            splitSections = data\get ASS.Section.Tag, 1, i
            splitSections[#splitSections+1] = section
            splitLine.ASS = ASS.LineContents splitLine, splitSections

            lines\addLine splitLine
            table.insert splitLines, splitLine

            if section.class == ASS.Section.Text
                splitLine.width, splitLine.height, splitLine.descent = section\getTextExtents!
            else
                ext = section\getExtremePoints!
                splitLine.width, splitLine.height, splitLine.descent = ext.w, ext.h, 0

            splitLine.x = x

            x += splitLine.width
            lineheight = math.max(lineheight, splitLine.height)
            linedescent = math.max(linedescent, splitLine.descent)


        for splitLine in *splitLines
            xshift = splitLine.x + an_xshift[an] * (splitLine.width - x)
            yshift = (1 - an_yshift[an]) * (lineheight - splitLine.height) - (linedescent - splitLine.descent)

            -- We ensured above that this is not a move tag
            splitpos = splitLine.ASS\getPosition()
            splitpos.x += xshift
            splitpos.y += yshift

            if not hasorg
                splitLine.ASS\insertTags {
                    ASS\createTag "origin", pos.x, pos.y
                }

            splitLine.ASS\cleanTags 4
            splitLine.ASS\commit!

    lines\insertLines!
    lines\deleteLines toDelete

dep\registerMacro split
