export script_name = "FBF-ifier"    -- thank Light for the name, I needed something that doesn't clash with Zeref's "Line To FBF"
export script_description = "Convert lines into frame-by-frame chunks"
export script_author = "arch1t3cht"
export script_namespace = "arch.Line2Fbf"
export script_version = "0.1.1"

DependencyControl = require "l0.DependencyControl"
dep = DependencyControl{
    feed: "https://raw.githubusercontent.com/TypesettingTools/arch1t3cht-Aegisub-Scripts/main/DependencyControl.json",
    {
        {"a-mo.LineCollection", version: "1.3.0", url: "https://github.com/TypesettingTools/Aegisub-Motion",
         feed: "https://raw.githubusercontent.com/TypesettingTools/Aegisub-Motion/DepCtrl/DependencyControl.json"},
        {"l0.ASSFoundation", version: "0.5.0", url: "https://github.com/TypesettingTools/ASSFoundation",
         feed: "https://raw.githubusercontent.com/TypesettingTools/ASSFoundation/master/DependencyControl.json"},
        {"arch.Util", version: "0.1.0", url: "https://github.com/TypesettingTools/arch1t3cht-Aegisub-Scripts",
         feed: "https://raw.githubusercontent.com/TypesettingTools/arch1t3cht-Aegisub-Scripts/main/DependencyControl.json"},
    }
}
LineCollection, ASS, Util = dep\requireModules!

logger = dep\getLogger!

fbfify = (subs, sel, active) ->
    lines = LineCollection subs, sel, () -> true

    to_delete = {}
    preFbfCount = #lines
    lines\runCallback ((lines, line) ->
        data = ASS\parse line

        table.insert to_delete, line

        fbf = Util.line2fbf data
        for fbfline in *fbf
            lines\addLine fbfline
    ), true

    lines\insertLines!
    lines\deleteLines to_delete

    return [i - preFbfCount for i in *lines\getSelection!]

dep\registerMacro fbfify

