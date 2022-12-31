export script_name = "Git Signs"
export script_description = "Displays git diffs in Aegisub"
export script_version = "0.2.3"
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
        feed: "https://raw.githubusercontent.com/TypesettingTools/arch1t3cht-Aegisub-Scripts/main/DependencyControl.json",
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
    lines_to_delete = {}

    for si, line in ipairs(subs)
        continue if line.class != "dialogue"
        if line.effect\match("%[Git %-%]")
            table.insert(lines_to_delete, si)
        line.effect = line.effect\gsub("%[Git [^%]]*%]", "")
        subs[si] = line

    subs.delete(lines_to_delete)


string2time = (timecode) ->
    timecode\gsub("(%d):(%d%d):(%d%d)%.(%d%d)", (a, b, c, d) -> d * 10 + c * 1000 + b * 60000 + a * 3600000)


parse_ass_line = (str) ->
    ltype, layer, s_time, e_time, style, actor, margin_l, margin_r, margin_t, effect, text = str\match(
        "(%a+): (%d+),([^,]-),([^,]-),([^,]-),([^,]-),([^,]-),([^,]-),([^,]-),([^,]-),(.*)"
    )
    return {
        class: "dialogue",
        comment: ltype == "Comment",
        start_time: string2time(s_time),
        end_time: string2time(e_time),
        :layer,
        :style,
        :margin_l,
        :margin_r,
        :margin_t,
        :actor,
        :effect,
        :text,
        extra: {},
    }


-- Returns a table (because I didn't want to figure out lua iterators)
-- of index-line pairs, where the indexing skips lines marked as removed
iterate_diff_section = (lines) ->
    reindexed = {}

    newindex = 1
    for gline in *lines
        table.insert(reindexed, {:newindex, :gline})
        newindex += 1 unless gline\match("^%-")

    return reindexed


show_diff_lines = (subs, diff, show_before) ->
    clear_markers(subs)
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
        for {:newindex, :gline} in *iterate_diff_section(section.lines)
            if newindex > 1 and gline\match("^%+?Dialogue: ") or gline\match("^%+?Comment: ")
                rl = gline\gsub("^%+", "")\gsub("\r$", "")

                aegisub.log(5, "Trying to find anchor line #{gl}\n")

                for si, s in ipairs(subs)
                    if s.raw == rl
                        offset = si - (section.newfrom + newindex - 1)
                        aegisub.log(5, "Found offset #{offset}")
                        break

                if offset == nil
                    aegisub.log("Diff didn't match the subtitles! Make sure to save your file.\n")
                    aegisub.cancel()

            break unless offset == nil
        break unless offset == nil

    if offset == nil
        aegisub.log("Either the diff didn't match the subtitles (save your file if so), or no dialogue lines were changed.\n")
        aegisub.cancel()

    lines_inserted = 0
    for i, section in ipairs(sections)
        for {:newindex, :gline} in *iterate_diff_section(section.lines)
            ind = section.newfrom + newindex - 1 + offset + lines_inserted

            if show_before and (gline\match("^%-Dialogue: ") or gline\match("^%-Comment: "))
                newline = parse_ass_line(gline\sub(1))
                newline.comment = true
                newline.effect = "[Git -]" .. newline.effect
                subs.insert(ind, newline)
                lines_inserted += 1

            if gline\match("^%+Dialogue: ") or gline\match("^%+Comment: ")
                line = subs[ind]
                line.effect = "[Git #{if show_before then '+' else '~'}]" .. line.effect
                subs[ind] = line


show_diff_diag = (subs, sel) ->
    config\load()
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
    },{
        class: "checkbox",
        label: "Show before and after",
        hint: "Add commented lines marked [Git -] showing how the line looked before the change.",
        name: "show_before",
        value: config.c.show_before
        x: 2, y: 1, width: 2, height: 2,
    }})

    return if not btn

    config.c.show_before = result.show_before if config.c.show_before != result.show_before
    config\write()

    ref = "#{result.ref}~#{result.before}"
    diff = get_git_diff(ref)

    current_diff = diff
    show_diff_lines(subs, diff, result.show_before)


configure = () ->
    config\load()

    if not haveDepCtrl
        aegisub.log("DependencyControl wasn't found! The config will not be persistent.\n")

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
