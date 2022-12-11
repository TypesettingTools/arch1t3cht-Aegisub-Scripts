export script_name = "Convert Folds"
export script_description = "Convert folds stored in the project properties to extradata folds."
export script_author = "arch1t3cht"
export script_namespace = "arch.LoadFolds"
export script_version = "1.0.0"

haveDepCtrl, DependencyControl = pcall(require, "l0.DependencyControl")

local depctrl

if haveDepCtrl
    depctrl = DependencyControl({
        feed: "https://raw.githubusercontent.com/arch1t3cht/Aegisub-Scripts/main/DependencyControl.json",
        {},
    })
    config = depctrl\getConfigHandler(default_config, "config", false)


folds_key = "_aegi_folddata"


parse_line_fold = (line) ->
    return if not line.extra
    
    info = line.extra[folds_key]
    return if not info

    side, collapsed, id = info\match("^(%d+);(%d+);(%d+)$")
    return {:side, :collapsed, :id}


load_folds = (subs, sel) ->
    button, results = aegisub.dialog.display({{
        class: "label",
        label: "Paste the \"Line Folds\" line from the Project Properties:",
        x: 0, y: 0, width: 1, height: 1,
    },{
        class: "edit",
        name: "foldinfo"
        x: 0, y: 1, width: 1, height: 1,
    }})

    return if not button

    maxid = 0
    local dialoguestart
    for i, line in ipairs(subs)
        fold = parse_line_fold(line)
        maxid = math.max(maxid, fold.id or 0) if fold

        if dialoguestart == nil and line.class == "dialogue"
            dialoguestart = i

    foldinfo = results.foldinfo
    foldinfo = foldinfo\gsub("^Line Folds:", "")\gsub("^ *", "")\gsub(" *$", "")

    for foldrange in foldinfo\gmatch("[^,]+")
        maxid += 1

        fr, to, collapsed = foldrange\match("^(%d+):(%d+):(%d+)$")
        fr += dialoguestart
        to += dialoguestart

        line1 = subs[fr]
        line1.extra or= {}
        line1.extra[folds_key] = "0;#{collapsed};#{maxid}"
        subs[fr] = line1

        line2 = subs[to]
        line2.extra or= {}
        line2.extra[folds_key] = "1;#{collapsed};#{maxid}"
        subs[to] = line2


wrap_register_macro = (...) ->
    if haveDepCtrl
        depctrl\registerMacro(...)
    else
        aegisub.register_macro(script_name, script_description)

wrap_register_macro(load_folds)
