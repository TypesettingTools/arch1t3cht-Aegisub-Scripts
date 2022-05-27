export script_name = "Git Signs"
export script_description = "Displays git diffs in Aegisub"
export script_version = "0.1.0"
export script_namespace = "arch.GitSigns"
export script_author = "arch1t3cht"

haveDepCtrl, DependencyControl = pcall(require, "l0.DependencyControl")
local config
local fun
local depctrl

default_config = {
    git_path: "",
}

if haveDepCtrl
    depctrl = DependencyControl({
        feed: "https://raw.githubusercontent.com/arch1t3cht/Aegisub-Scripts/main/DependencyControl.json",
        {
            {"l0.Functional", version: "0.6.0", url: "https://github.com/TypesettingTools/Functional",
              feed: "https://raw.githubusercontent.com/TypesettingTools/Functional/master/DependencyControl.json"},
        }
    })
    config = depctrl\getConfigHandler(default_config, "config", false)
    fun = depctrl\requireModules!
else
    id = () -> nil
    config = {c: default_config, load: id, write: id}
    fun = require "l0.Functional"

local has_git
local current_diff

get_git = () ->
    if config.c.git_path != "" then config.c.git_path else "git"

check_has_git = () ->
    return has_git if has_git != nil

    handle = io.popen("#{get_git()} --help", "r")
    content = handle\read("*a")
    has_git = content != ""
    return has_git


get_git_diff = (ref) ->
    dir = aegisub.decode_path("?script")
    if dir == "?script"
        aegisub.log("File isn't saved! Aborting.")
        aegisub.cancel()

    handle = io.popen("#{get_git()} -C \"#{dir}\" diff --raw -p \"#{ref}\" \"#{aegisub.file_name()}\"")
    return handle\read("*a")


clear_markers = (subs) ->
    for si, line in ipairs(subs)
        continue if line.class != "dialogue"
        line.effect = line.effect\gsub("%[Git [^%]]*%]", "")
        subs[si] = line


show_diff_lines = (subs, diff) ->
    parts = fun.string.split diff, "@@"
    sections = {}

    i = 2
    while i + 1 <= #parts
        oldfrom, oldto, newfrom, newto = parts[i]\match("%-([%d]+),([%d]+) %+([%d]+),([%d]+)")
        lines = fun.string.split parts[i+1]\sub(2), "\n"

        if oldfrom == nil or oldto == nil or newfrom == nil or newto == nil or lines == nil
            aegisub.log("Invalid diff output!\n")
            aegisub.cancel()

        table.insert(sections, {:oldfrom, :oldto, :newfrom, :newto, :lines})
        i += 2
    
    local offset

    for i, section in ipairs(sections)
        newindex = 1
        for j, gline in ipairs(section.lines)
            if offset == nil and j > 1 and gline\match("^%+?Dialogue: ") or gline\match("^%+?Comment: ")
                gl = gline\gsub("^%+", "")\gsub("\r$", "")

                aegisub.log(5, "Trying to find anchor line #{gl}\n")

                for si, s in ipairs(subs)
                    if s.raw == gl
                        offset = si - (section.newfrom + newindex - 1)
                        aegisub.log(5, "Found offset #{offset}")
                        break
                
                if offset == nil
                    aegisub.log("Diff didn't match the subtitles! Make sure to save your file.\n")
                    aegisub.cancel()

            if gline\match("^%+Dialogue: ") or gline\match("^%+Comment: ")
                ind = section.newfrom + newindex - 1 + offset
                line = subs[ind]
                line.effect = "[Git ~]" .. line.effect
                subs[ind] = line

            newindex += 1 unless gline\match("^%-")


show_diff_diag = (subs, sel) ->
    if not check_has_git()
        aegisub.log("Git executable not found!")
        aegisub.cancel()

    btn, result = aegisub.dialog.display({{
        class: "label",
        label: "Target ref: ",
        x: 0, y: 0, width: 1, height: 1,
    },{
        class: "edit",
        text: "HEAD",
        name: "ref",
        hint: [[The ref to diff with]],
        x: 1, y: 0, width: 1, height: 1,
    },{
        class: "intedit",
        value: 0,
        min: 0,
        max: math.huge,
        name: "before",
        hint: [[How many commits to rewind from the ref. Added with a tilde after the ref.]],
        x: 2, y: 0, width: 1, height: 1,
    },{
        class: "label",
        label: "Commits prior",
        x: 3, y: 0, width: 1, height: 1,
    }})

    return if not btn

    ref = "#{result.ref}~#{result.before}"
    diff = get_git_diff(ref)

    current_diff = diff
    show_diff_lines(subs, diff)


configure = () ->
    config\load()

    ok = "Save"
    cancel = "Cancel"
    btn, result = aegisub.dialog.display({{
        class: "label",
        label: "Git path: ",
        x: 0, y: 0, width: 1, height: 1,
    },{
        class: "edit",
        name: "git_path",
        hint: "Path to git executable",
        value: config.c.git_path,
        x: 1, y: 0, width: 1, height: 1,
    }}, {ok, cancel}, {ok: ok, cancel: cancel})

    return if not btn

    config.c.git_path = result.git_path if result.git_path != config.c.git_path
    config\write()


mymacros = {}
wrap_register_macro = (name, ...) ->
    if haveDepCtrl
        table.insert(mymacros, {name, ...})
    else
        aegisub.register_macro("#{script_name}/#{name}", ...)

wrap_register_macro("Show Diff", "Highlight the diff relative to a certain ref", show_diff_diag)
wrap_register_macro("Configure", "Configure GitSigns", configure)
wrap_register_macro("Clear Markers", "Clear GitSigns Markers", clear_markers)

if haveDepCtrl
    depctrl\registerMacros(mymacros)
