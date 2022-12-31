export script_name = "Convert Folds"
export script_description = "Convert folds stored in the project properties to extradata folds."
export script_author = "arch1t3cht"
export script_namespace = "arch.ConvertFolds"
export script_version = "1.1.2"

haveDepCtrl, DependencyControl = pcall(require, "l0.DependencyControl")

local depctrl

if haveDepCtrl
    depctrl = DependencyControl({
        feed: "https://raw.githubusercontent.com/TypesettingTools/arch1t3cht-Aegisub-Scripts/main/DependencyControl.json",
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
    apply = "Apply"
    fromfile = "From File"
    cancel = "Cancel"

    button, results = aegisub.dialog.display({{
        class: "label",
        label: "Paste the \"Line Folds\" line from the Project Properties:",
        x: 0, y: 0, width: 1, height: 1,
    },{
        class: "edit",
        name: "foldinfo"
        x: 0, y: 1, width: 1, height: 1,
    }}, {apply, fromfile, cancel}, {"ok": apply, "cancel": cancel})

    return if not button

    foldinfo = results.foldinfo

    if button == fromfile
        f = io.open(aegisub.decode_path("?script/#{aegisub.file_name()}"))
        if f == nil
            aegisub.log("Couldn't open subtitle file.\n")
            aegisub.cancel()

        content = f\read("a")\gsub("\r\n", "\n")
        f\close()
        infoline = content\match("\n(Line Folds: *[0-9:,]* *\n)")
        if infoline == nil
            aegisub.log("Couldn't find fold info in subtitle file.\n")
            aegisub.cancel()

        foldinfo = infoline\gsub("^\n*", "")\gsub("\n*$", "")


    maxid = 0
    local dialoguestart
    for i, line in ipairs(subs)
        fold = parse_line_fold(line)
        maxid = math.max(maxid, fold.id or 0) if fold

        if dialoguestart == nil and line.class == "dialogue"
            dialoguestart = i

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
