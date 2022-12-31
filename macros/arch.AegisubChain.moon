export script_name = "AegisubChain"
export script_description = "Compose chains out of existing automation macros, and play them back as non-GUI macros, or using only one dialog."
export script_version = "0.4.1"
export script_namespace = "arch.AegisubChain"
export script_author = "arch1t3cht"


-- All global runtime variables are prefixed by _ac_ so that they won't be modified by third-party scripts called by us.

_ac_was_present = _ac_present
export _ac_present = true
export _ac_version = script_version
export _ac_f = {}  -- functions
export _ac_c = {}  -- constants
export _ac_i = {}  -- imports
export _ac_gs = {} -- global mutable variables
export _ac_default_config = {
    chain_menu: "AegisubChain Chains/"  -- Submenu to list all chains in. Can contain slashes.
    path: ""                            -- Path to search for macros in. Defaults to Aegisub's path if == true
    warning_shown: false                -- Whether the instability warning was shown
    chains: {}                          -- Defined chains
    blacklist: {}                       -- List of lua patterns to apply to paths of scripts being loaded. Scripts matching any of them will be skipped.
    show_in_menu: false                 -- Whether to show scripts to record directly in the automation menu
    num_chain_slots: 5                  -- Number of slots
    num_prev_chains: 2                  -- Number of macros of the form "repeat n-th last chains"
    chain_slots: {"", "", "", "", ""}   -- Configured slots
}

-- Aegisub gives us its api in the aegisub object. Even though debug prints didn't show any differences,
-- functions from a previous macro run are invalid in the next macro run.
-- Furthermore, the updated aegisub api object will only reach our script if, at the end of the last run,
-- the aegisub object is in the aegisub variable. Because of this, we need to juggle different aegisub instances
-- back and forth when running various scripts.
export _ac_aegisub = aegisub
export aegisub = {k, v for k, v in pairs(_ac_aegisub)}

-- IMPORTS

_ac_i.depctrl = require'l0.DependencyControl'
_ac_c.depctrl = _ac_i.depctrl {
    feed: "https://raw.githubusercontent.com/TypesettingTools/arch1t3cht-Aegisub-Scripts/main/DependencyControl.json",
    {
        {"l0.Functional", version: "0.6.0", url: "https://github.com/TypesettingTools/Functional",
          feed: "https://raw.githubusercontent.com/TypesettingTools/Functional/master/DependencyControl.json"},
        "lfs",
        "json",
        "moonscript.base",
    }
}

_ac_i.fun, _ac_i.lfs, _ac_i.json, _ac_i.moonbase = _ac_c.depctrl\requireModules!

-- COMPATIBILITY IMPORTS
-- This is ugly, but seems necessary: These imports aren't used by our script, but
-- they're modules that don't follow the modern pattern for lua patterns - instead of
-- returning a table with their functions, they just write into the global variable table.
-- Thus, a simple "require" won't return them after the first load.
-- We fix this by loading them here so that their functions won't get swapped out when switching scripts,
-- and by praying to Cthulhu that none of them will conflict.
require'karaskel'

-- CONSTANTS

-- Foolproof method to ensure that AegisubChain never loads itself. Should never be changed.
_ac_c.red_flag = "Hi, I'm AegisubChain, please don't load me! The following is a random red flag string: Jnd4nKxQWAMinndFqKFotlEJgaiRT0lepihiKGYaERA="
_ac_c.myname = "arch.AegisubChain.moon"

_ac_c.default_path = "?user/automation/autoload/|?data/automation/autoload/"    -- Will be read from aegisub config if it exists

_ac_c.init_dir = _ac_i.lfs.currentdir()    -- some script might change the working directory, so we reset it each time

_ac_c.debug = false      -- whether we're debugging right now. This turns off all pcalls so error messages can propagate fully.

_ac_c.select_mode_options = {
    "Macro's Selection": "macro",
    "Previous Selection": "keep",
    "All Changed Lines": "changed",
}

_ac_c.value_mode_options = {
    "Set in Dialog": "user",
    "Constant": "const",
    "Exclude": "exclude",
}

_ac_c.button_mode_options = _ac_i.fun.table.merge({
    "Raw Passthrough": "passthrough",
    "Passthrough with defaults": "passthrough_defaults",
}, _ac_c.value_mode_options)

_ac_c.default_diag_values = {
    "edit": "",
    "textbox": "",
    "dropdown": "",
    "color": "#000000",
    "coloralpha": "#00000000",
    "alpha": "",
    "intedit": 0,
    "floatedit": 0,
    "checkbox": false,
}

_ac_c.diag_default_names = {
    "edit": "text",
    "textbox": "text",
    "dropdown": "value",
    "color": "value",
    "coloralpha": "value",
    "alpha": "value",
    "intedit": "value",
    "floatedit": "value",
    "checkbox": "value",
}

_ac_c.default_value_modes = {
    "edit": "Set in Dialog",
    "textbox": "Set in Dialog",
    "dropdown": "Constant",
    "color": "Set in Dialog",
    "coloralpha": "Set in Dialog",
    "alpha": "Set in Dialog",
    "intedit": "Set in Dialog",
    "floatedit": "Set in Dialog",
    "checkbox": "Constant",
    "button": "Constant",
}

_ac_c.ourmacros = {}            -- macros to register with depctrl under a submenu

-- CONFIG
export _ac_config = _ac_c.depctrl\getConfigHandler(_ac_default_config, "config")

-- GLOBAL STATE
_ac_gs.initialized = false      -- whether the script has been initialized

_ac_gs.recording_chain = {}     -- list of steps in macro currently being recorded
_ac_gs.current_script = nil     -- script currently being loaded or run
_ac_gs.show_dummy_dialogs = false
_ac_gs.loaded_scripts = nil     -- table of scripts we have loaded
_ac_gs.captured_macros = nil    -- table of macros that have been "registered" with us

-- Yes, we do all this noise in global state, because it's just way less of a hassle to
-- juggle all of these variables through different environments.
_ac_gs.captured_dialogs = nil   -- list of dialogs that have been captured for the current step
_ac_gs.selected_macro = nil     -- macro that has been selected - if this isn't nil we shouldn't show a dialog

_ac_gs.current_chain = nil      -- chain currently being executed
_ac_gs.values_for_chain = nil   -- results of the dialog we showed the user before running the chain
_ac_gs.current_step_index = nil -- index of the current step in the chain being executed
_ac_gs.current_step_dialog_index = nil  -- index of the dialog for the current step of the chain being executed

_ac_gs.our_globals = {}

-- global state transcending script runs
_ac_gs.past_chains = {}         -- Previously executed chains

-- more juggling
export _ac_depctrl_aegisub = aegisub
export _ac_script_aegisub = {}
export aegisub = _ac_aegisub

_ac_c.initial_globals = {k,true for k, v in pairs(_G)}
_ac_c.initial_globals.script_name = nil
_ac_c.initial_globals.script_description = nil
_ac_c.initial_globals.script_version = nil
_ac_c.initial_globals.script_namespace = nil
_ac_c.initial_globals.script_author = nil


-- There is some other global state we need to keep track of:
--  - The working directory
--  - Loaded packages, and their captured variables

-- FUNCTION DEFINITIONS

_ac_f.log = (...) ->
    _ac_aegisub.log(...) if _ac_gs.initialized


_ac_f.pcall_wrap = (f, ...) ->
    if _ac_c.debug
        return true, f(...)
    return pcall(f, ...)


-- make sure the load doesn't capture any variables
_ac_f.load_wrap = (_ac_l_script, _ac_l_content) ->
    if _ac_l_script\match("%.moon$")
        return assert(_ac_i.moonbase.loadstring(_ac_l_content))
    else
        return assert(loadstring(_ac_l_content))


_ac_f.save_config = () ->
    _ac_config\write(true)


_ac_f.register_macro_hook = (name, desc, fun, testfun, actfun) ->
    _ac_f.log(5, "Registered #{name} as #{fun}!\n")
    _ac_gs.captured_macros[name] = {
        fun: fun,
        script: _ac_gs.current_script
    }


_ac_f.bounded_deep_copy = (x, bound) ->
    return x if bound == 0
    return x if type(x) != "table"
    return {k,_ac_f.bounded_deep_copy(v, bound - 1) for k,v in pairs(x)}


_ac_f.dialog_open_hook = (dialog, buttons, button_ids) ->
    if _ac_gs.captured_dialogs != nil
        -- we're currently recording a macro, so display the dialog normally for now
        btn, result = _ac_aegisub.dialog.display(dialog, buttons, button_ids)

        fields = {k,{value: v} for k,v in pairs(result)}

        for i, field in pairs(dialog)
            if field.name != nil and fields[field.name] != nil
                savefield = _ac_i.fun.table.copy field

                if savefield.value != nil and (savefield.class == "intedit" or savefield.class == "floatedit")
                    savefield.value = tonumber(savefield.value)

                fields[field.name].descriptor = savefield

        table.insert(_ac_gs.captured_dialogs, {
            buttons: buttons,
            button: btn,
            fields: fields,
        })

        if _ac_gs.show_dummy_dialogs
            -- show another dialog, and use its values
            return _ac_aegisub.dialog.display(dialog, buttons, button_ids)

        return btn, result

    elseif _ac_gs.current_step_index
        step = _ac_gs.current_chain[_ac_gs.current_step_index]
        if step.dialogs == nil
            _ac_f.log("Invalid chain config!\n")
            _ac_aegisub.cancel()

        diaginfo = step.dialogs[_ac_gs.current_step_dialog_index]
        if diaginfo == nil
            _ac_f.log("Unknown dialog shown!\n")

        if diaginfo.button.mode == "passthrough"
            newdiag = _ac_f.bounded_deep_copy(dialog, 3)

            -- set up the defaults if there are any
            if diaginfo.values != nil
                stepvalues = _ac_gs.values_for_chain[_ac_gs.current_step_index]
                local values
                if stepvalues != nil
                    values = stepvalues[_ac_gs.current_step_dialog_index]

                for fname,field in pairs(diaginfo.values)
                    for k,v in pairs(newdiag)
                        if v.name == fname
                            if field.mode == "const"
                                v[_ac_c.diag_default_names[v.class]] = field.value
                            elseif field.mode == "user"
                                v[_ac_c.diag_default_names[v.class]] = values.values[fname]

            -- pass the dialog on
            return _ac_aegisub.dialog.display(newdiag, buttons, button_ids)

        if diaginfo.values != nil
            result = {}

            -- first set up a result table containing the default answers
            for i, field in pairs(dialog)
                continue if field.name == nil
                if field.value != nil
                    result[field.name] = field.value
                else
                    result[field.name] = _ac_c.default_diag_values[field.class]

            -- next, override with the user configuration
            stepvalues = _ac_gs.values_for_chain[_ac_gs.current_step_index]
            local values
            if stepvalues != nil
                values = stepvalues[_ac_gs.current_step_dialog_index]

            for k, v in pairs(diaginfo.values)
                -- FEATURE: could add support for lua eval here... someday
                if v.mode == "const"
                    result[k] = v.value
                elseif v.mode == "user"
                    result[k] = values.values[k]

            local btn
            if diaginfo.button.mode == "const"
                btn = diaginfo.button.value
            elseif diaginfo.button.mode == "user" or true    -- let's not make button nil
                btn = values.button

            _ac_gs.current_step_dialog_index += 1

            return btn, result

    _ac_f.log("Unknown dialog shown!\n")
    -- same here
    btn, result = _ac_aegisub.dialog.display(dialog, buttons, button_ids)
    return btn, result


-- init function called on entry by all macro functions.
-- saves the list of currently defined global variables.
_ac_f.initialize = () ->
    -- I *think* it's possible to have an individual aegisub for every script, but with how
    -- hard it was to get the rest working, I'll stay with the simple, stupid method for now.
    export _ac_aegisub = aegisub

    for k, v in pairs(_ac_script_aegisub)
        _ac_script_aegisub[k] = nil

    for k, v in pairs(_ac_aegisub)
        _ac_script_aegisub[k] = v

    _ac_script_aegisub.register_macro = _ac_f.register_macro_hook

    if _ac_gs.initialized
        if _ac_aegisub.dialog == nil
            -- welp, aegisub is broken, so we can't really log anything. Let's hack our error message.
            I_LOST_MY_AEGISUB_INSTANCE_PLEASE_RELOAD_YOUR_AUTOMATION_SCRIPTS = (x) -> x()
            I_LOST_MY_AEGISUB_INSTANCE_PLEASE_RELOAD_YOUR_AUTOMATION_SCRIPTS()

        _ac_script_aegisub.dialog = _ac_i.fun.table.copy _ac_aegisub.dialog
        _ac_script_aegisub.dialog.display = _ac_f.dialog_open_hook

    export aegisub = _ac_script_aegisub


_ac_f.finalize = () ->
    export aegisub = _ac_aegisub
    _ac_i.lfs.chdir(_ac_c.init_dir)


_ac_f.scripts_in_path = () ->
    scripts = {}

    path = _ac_c.default_path
    if _ac_config.c.path != ""
        path = _ac_config.c.path

    ds, dn = _ac_i.fun.string.split path, "|"

    for i, dir in ipairs(ds)
        for file in _ac_i.lfs.dir(_ac_aegisub.decode_path(dir))
            continue if file == _ac_c.myname
            -- With all macros working, there's no real reason *not* to allow depctrl.
            -- If you find an actual application for this, I'd love to hear it.
            -- continue if file\match("^l0%.DependencyControl")   -- let's not
            if file\match("%.lua$") or file\match("%.moon$")
                fname = dir .. file
                match = false
                for i, p in ipairs(_ac_config.c.blacklist)
                    continue if p == ""
                    match = true if fname\match(p)

                table.insert(scripts, fname) unless match

    return scripts


-- The hardest part of all this is making sure that the scripts get all of the APIs and
-- global variables they need, while not interfering with other scripts, and while actually
-- receiving our modified aegisub object.
--
-- The obvious solution is using setfenv to give each script chunk their own environment.
-- But but this runs into issues when registering scripts, as the exports of script_name, etc
-- will only be in this sandbox environment and won't reach DependencyControl.
-- Thus, possible ideas are:
--  1. Changing package.loaded to make each script load their own depctrl from scratch:
--     Didn't work for reasons I have yet to understand.
--  2. Using metatables to pass only these values through to the global environment:
--     Doesn't work, since assignments to script_name, etc don't seem to be assignments to global variables.
--  3. Also giving the depctrl instance this environment
--     Didn't work.
--  4. Changing the environment of the entire thread, and swapping back and forth
--     Didn't work.
--  5. Not using environments after all, and simulating 4. by just manually juggling globals. AKA the stupid way
--     The only one that worked, and what I'm using right now.


_ac_f.move_globals = (from_globals, to_globals) ->
    for k,v in pairs(_G)
        continue if _ac_c.initial_globals[k]
        to_globals[k] = v
        _G[k] = nil

    for k,v in pairs(from_globals)
        _G[k] = v
        from_globals[k] = nil


_ac_f.run_script_initial = (script) ->
    scrpath = _ac_aegisub.decode_path(script)

    f = assert(io.open(scrpath))
    content = f\read("a")
    f\close()
    return if content\match(_ac_c.red_flag)

    _ac_gs.current_script = script
    _ac_i.lfs.chdir(_ac_c.init_dir)

    export script_name = nil
    export script_description = nil
    export script_version = nil
    export script_namespace = nil
    export script_author = nil

    env = {}
    _ac_f.move_globals(env, _ac_gs.our_globals)

    chunk = _ac_f.load_wrap(script, content)

    _ac_f.log(5, "Loading #{scrpath}...\n")
    status, errc = _ac_f.pcall_wrap(chunk)
    if status == false
        if _ac_c.debug
            _ac_f.log("Failed to load #{script} with the following error:\n")
            _ac_f.log("#{errc}\n")
            _ac_aegisub.cancel()
        else
            _ac_f.log("Failed to load #{script}! Skipping...\n")

    _ac_f.move_globals(_ac_gs.our_globals, env)

    _ac_gs.loaded_scripts[script] = {
        cwd: _ac_i.lfs.currentdir(),
        env: env
    }


-- When the first command is run that involves running other macros,
-- we load all automation scripts. Only loading those scripts involved in a
-- chain would require saving the file a macro belongs to in the chain's configuration file,
-- which I don't really want to do for portability reasons.
_ac_f.load_all_scripts = () ->
    if _ac_gs.loaded_scripts != nil
        return

    _ac_gs.loaded_scripts = {}
    _ac_gs.captured_macros = {}

    scripts = _ac_f.scripts_in_path()

    _ac_aegisub.progress.task("Loading macros...") if _ac_aegisub.progress != nil

    for i, script in ipairs(scripts)
        _ac_aegisub.progress.task("Loading macros... [#{script\match("[^/]+$")}]") if _ac_aegisub.progress != nil
        _ac_aegisub.progress.set(100 * (i - 1) / #scripts) if _ac_aegisub.progress != nil
        _ac_f.run_script_initial(script)

    for k, v in pairs(_ac_gs.captured_macros)
        _ac_f.log(4, "Found macro #{k} as #{v}\n")


-- takes the operations recorded, and the selection and the active line before the run.
-- returns the (sorted) list of changed lines, the moved selection, and the moved active line.
_ac_f.process_operations = (operations, prevlen, sel_, active_) ->
    active = {active_}
    sel = _ac_i.fun.table.copy sel_
    changed = {}
    len = prevlen

    filtered_op = {}

    shift_above = (i, tab, shift) ->
        for j, v in ipairs(tab)
            tab[j] = v + shift if v >= i

    -- simplify the operations, such that:
    -- - every operation only affects one line
    -- - newindex only entails assignments
    for i, op in ipairs(operations)
        if op.name == "newindex"
            if op.args[1] > 0
                table.insert(filtered_op, op)
            elseif op.args[1] == 0
                table.insert(filtered_op, {name: "append", args: {op.args[2]}})
            elseif op.args[1] < 0
                table.insert(filtered_op, {name: "insert", args: {-op.args[1], op.args[2]}})
            else
                _ac_f.log("Unknown operation argument: #{op.args[1]}\n")
                _ac_aegisub.cancel()

        -- -- subs.delete(i1, i2, ...) or
        -- -- subs.delete({i1, i2, ...})
        elseif op.name == "delete"
            args = op.args
            if type(args[1]) == "table"
                args = args[1]
            args = _ac_i.fun.list.uniq args

            for i, a in ipairs(args)
                table.insert(filtered_op, {name: op.name, args: {a}})

                for j, b in ipairs(args)
                    if j > i and b > a
                        args[j] = b - 1

        -- subs.insert(i, line1, line2, ...)
        elseif op.name == "insert"
            for i, a in ipairs(op.args)
                table.insert(filtered_op, {name: op.name, args: {op.args[1], a}}) unless i == 1
        -- subs.append(line1, line2, ...) or
        elseif op.name == "append"
            for i, a in ipairs(op.args)
                table.insert(filtered_op, {name: op.name, args: {a}})

        elseif op.name == "deleterange"
            for i in 1,(op.args[2] - op.args[1] + 1)
                table.insert(filtered_op, {name: op.name, args: {op.args[1]}})


    for i, op in ipairs(filtered_op)
        if op.name == "newindex"
            table.insert(changed, op.args[1]) if _ac_i.fun.list.indexOf(changed, op.args[1]) == nil
        elseif op.name == "append"
            table.insert(changed, len + 1)
            len += 1
        elseif op.name == "delete"
            i = op.args[1]
            if i == active[1]
                active = {}

            for k, v in ipairs(changed)
                changed[k] = nil if v == i
            for k, v in ipairs(sel)
                sel[k] = nil if v == i
            shift_above(i, changed, -1)
            shift_above(i, sel, -1)
            shift_above(i, active, -1)
            len -= 1
        elseif op.name == "insert"
            i = op.args[1]
            shift_above(i, changed, 1)
            shift_above(i, sel, 1)
            shift_above(i, active, 1)
            table.insert(changed, i)
            len += 1

    table.sort(changed)
    table.sort(sel)
    if #active == 0
        active = {sel[1]}

    return changed, sel, active[1]


-- pass a different subs object to the macros that tracks which lines were changed,
-- so that sel and active_line can be updated accordingly.
_ac_f.get_dummysubs = (operations, _ac_subs) ->
    -- instead of manually overriding all actions with hooks that track various changes,
    -- we'll just take the more organized route and log all relevant calls first, and go through them later.
    wrap_function = (fname) ->
        (...) ->
            table.insert(operations, {name: fname, args: {...}})
            return _ac_subs[fname](...)

    return setmetatable({}, {
        "__index": (tab, key) ->
            if type(key) == "string"
                if key == "n"
                    return _ac_subs.n
                return wrap_function(key)
            return _ac_subs[key]

        "__newindex": (tab, key, val) ->
            table.insert(operations, {name: "newindex", args: {key, val}})
            _ac_subs[key] = val

        "__len": (...) ->
            return #_ac_subs

        -- This isn't documented for lua 5.1, but the aegisub source sets __ipairs and this works,
        -- so let's just not question it
        "__ipairs": (...) ->
            return ipairs(_ac_subs)
    })


_ac_f.run_script_macro = (macroname, _ac_subs, _ac_sel, _ac_active) ->
    _ac_f.load_all_scripts()
    macro = _ac_gs.captured_macros[macroname]
    if macro == nil
        aegisub.log("Unknown macro: #{macroname}\n")
        aegisub.cancel()
    script = _ac_gs.loaded_scripts[macro.script]

    table.sort(_ac_sel)
    prevlen = #_ac_subs
    operations = {}
    dummysubs = _ac_f.get_dummysubs(operations, _ac_subs)

    _ac_i.lfs.chdir(script.cwd)
    _ac_f.move_globals(script.env, _ac_gs.our_globals)

    status, newsel, newactive = _ac_f.pcall_wrap(macro.fun, dummysubs, _ac_sel, _ac_active)
    if status == false
        errc = newsel
        if errc == nil
            errc = "#{errc} - Probably from aegisub.cancel()."
        _ac_f.log("Failed to run #{macroname} with the following error:\n")
        _ac_f.log("#{errc}\n")
        _ac_aegisub.cancel()

    script.cwd = _ac_i.lfs.currentdir()
    _ac_f.move_globals(_ac_gs.our_globals, script.env)

    changed, updatesel, updateactive = _ac_f.process_operations(operations, prevlen, _ac_sel, _ac_active)

    return newsel, newactive, changed, updatesel, updateactive


_ac_f.record_run_macro = (_ac_subs, _ac_sel, _ac_active) ->
    macroname, dummy = _ac_f.select_macro()
    if macroname == nil
        return

    _ac_gs.show_dummy_dialogs = dummy
    _ac_gs.captured_dialogs = {}
    newsel, newactive, changed, updatesel, updateactive = _ac_f.run_script_macro(macroname, _ac_subs, _ac_sel, _ac_active)

    _ac_gs.recording_chain or= {}
    table.insert(_ac_gs.recording_chain, {
            macro: macroname,
            captured_dialogs: _ac_gs.captured_dialogs
        })

    newsel = updatesel if newsel == nil
    newactive = updateactive if newactive == nil

    _ac_gs.captured_dialogs = nil
    _ac_gs.show_dummy_dialogs = nil

    return newsel, newactive


-- checks if a dialog field has a well-defined position and size
_ac_f.validate_field = (field) ->
    for i, v in ipairs({"x", "y", "width", "height"})
        return false if field[v] == nil
    return true


_ac_f.get_values_for_chain = (chain) ->
    user_diag = {}

    for stepi, step in ipairs(chain)
        for i, diag in ipairs(step.dialogs)
            for fname, field in pairs(diag.values or {})
                continue if field.mode != "user"

                -- we could place all of the invalid fields at the end, but that's way too
                -- much boilerplate code for way too little gain
                if not _ac_f.validate_field(field)
                    _ac_f.log("Invalid dialog config for user field!\n")
                    _ac_aegisub.cancel()

                table.insert(user_diag, {
                    class: "label",
                    label: field.flabel,
                    x: 2 * field.x, y: field.y, width: 1, height: field.height,
                })

                table.insert(user_diag, {
                    class: field.class,
                    value: field.value,
                    items: field.items,
                    text: field.text,
                    hint: field.hint,
                    min: field.min,
                    max: field.max,
                    step: field.step,
                    name: "s#{stepi}_d#{i}_f_#{fname}"
                    x: 2 * field.x + 1, y: field.y, width: 2 * field.width - 1, height: field.height,
                })

            if diag.button.mode == "user"
                field = diag.button

                if not _ac_f.validate_field(field)
                    _ac_f.log("Invalid dialog config for user field!\n")
                    _ac_aegisub.cancel()

                table.insert(user_diag, {
                    class: "label",
                    label: field.flabel,
                    x: 2 * field.x, y: field.y, width: 1, height: field.height,
                })

                table.insert(user_diag, {
                    class: "dropdown",
                    value: field.value,
                    name: "s#{stepi}_d#{i}_b",
                    items: field.items,
                    x: 2 * field.x + 1, y: field.y, width: 2 * field.width - 1, height: field.height,
                })

    if #user_diag == 0
        return {}

    btn, result = _ac_aegisub.dialog.display(user_diag)

    return if not btn

    user_values = {}

    for stepi, step in ipairs(chain)
        step_values = {}
        for i, diag in ipairs(step.dialogs)
            diag_values = {values: {}}
            for fname, field in pairs(diag.values or {})
                continue if field.mode != "user"
                diag_values.values[fname] = result["s#{stepi}_d#{i}_f_#{fname}"]

            if diag.button.mode == "user"
                diag_values.button = result["s#{stepi}_d#{i}_b"]

            table.insert(step_values, diag_values)
        table.insert(user_values, step_values)

    return user_values


_ac_f.run_chain = (chain, _ac_subs, _ac_sel, _ac_active) ->
    _ac_gs.current_chain = chain

    _ac_gs.values_for_chain = _ac_f.get_values_for_chain(chain) if _ac_gs.values_for_chain == nil
    return if _ac_gs.values_for_chain == nil

    for i, step in ipairs(chain)
        _ac_gs.current_step_index = i
        _ac_gs.current_step_dialog_index = 1

        prevlen = #_ac_subs
        newsel, newactive, changed, updatesel, updateactive = _ac_f.run_script_macro(step.macro, _ac_subs, _ac_sel, _ac_active)

        if step.select == "changed"
            _ac_sel = changed
            _ac_active = changed[1]
        elseif step.select == "keep"
            _ac_sel = updatesel
            _ac_active = updateactive
        elseif step.select == "macro" or true   -- default
            -- emulate the behavior of aegisub's automation engine, but assume that the script
            -- outputs correct values (i.e. that aegisub wouldn't throw errors)
            newactive or= updateactive

            if newsel != nil
                _ac_sel = newsel

                local future_active
                for s in *_ac_sel
                    future_active = s if active == nil or s == newactive

                if future_active != nil and (newactive > 0 or _ac_i.fun.list.indexOf(newsel, future_active) == nil)
                    _ac_active = future_active
                else
                    _ac_active = updateactive

                if #_ac_sel == 0
                    ac_sel = { _ac_active }
            else
                _ac_sel = updatesel
                _ac_active = updateactive
                _ac_active = _ac_sel[1] if _ac_i.fun.list.indexOf(_ac_sel, _ac_active) == nil

        _ac_gs.current_step_dialog_index = nil
        _ac_gs.current_step_index = nil

    table.insert(_ac_gs.past_chains, 1, {"chain": chain, "values": _ac_gs.values_for_chain})
    _ac_gs.past_chains[_ac_config.c.num_prev_chains + 1] = nil

    _ac_gs.current_chain = nil
    _ac_gs.values_for_chain = nil

    return _ac_sel, _ac_active


_ac_f.run_chain_slot = (slot, subs, sel, active) ->
    chainname = _ac_config.c.chain_slots[slot]
    if chainname == nil or chain == ""
        _ac_aegisub.log("No chain in slot #{slot}. Configure one in AegisubChain's settings.")
        return

    chain = _ac_config.c.chains[chainname]
    if chain == nil
        _ac_aegisub.log("Unkown chain #{chain} configured in slot #{slot}.")
        return

    return _ac_f.run_chain(chain, subs, sel, active)


_ac_f.repeat_last_chain = (index, samevals, subs, sel, active) ->
    lastchain = _ac_gs.past_chains[index]

    if lastchain == nil
        _ac_aegisub.log("No #{_ac_f.format_ordinal(index)} last chain exists yet!")
        return

    _ac_gs.values_for_chain = lastchain.values if samevals

    return _ac_f.run_chain(lastchain.chain, subs, sel, active)


-- This was the attempt to wrap a function in a try-finally block - If our script crashes we still try to restore the environment to something usable.
-- But usually, even when catching the crash and restoring the environment, the script is still broken afterwards.
-- It might be possible to auto-reload the script that crashed...
_ac_f.wrap = (f) ->
    (...) ->
        _ac_f.initialize()

        status, newsel, newactive = _ac_f.pcall_wrap(f, ...)
        if status == false
            errc = newsel
            _ac_f.log("Failed with the following error:\n")
            _ac_f.log("#{errc}\n")
            _ac_f.log("If you keep getting errors, try reloading your automation scripts.\n")

        _ac_f.finalize()

        return newsel, newactive


-- returns either nil (on cancel) or a selected macro, as well as whether a dummy dialog should be shown first
_ac_f.select_macro = () ->
    _ac_f.load_all_scripts()

    if _ac_gs.selected_macro != nil
        val = _ac_gs.selected_macro
        _ac_gs.selected_macro = nil
        return val, false

    macros = _ac_i.fun.table.keys(_ac_gs.captured_macros)
    table.sort(macros)

    btn, result = _ac_aegisub.dialog.display({
            {
                class: "label",
                label: "Macro name: ",
                x: 0, y: 0, width: 1, height: 1,
            },
            {
                class: "dropdown"
                name: "macro",
                items: macros,
                x: 1, y: 0, width: 1, height: 1,
            },
            {
                class: "checkbox",
                value: false
                name: "dummy",
                label: "Show dummy dialogs first",
                hint: [[
Whether, for each dialog the macro shows, a dummy dialog should be shown first.
The fields changed in this dialog will be the ones for which config options will be shown afterwards.
The inputs in the second dialog will be the ones actually passed to the script.
This option is useful whenever
a) you want to make a value configurable but don't want to change it this time
b) you want to make a value constant, which does not always have the same default value.
]],
                x: 1, y: 1, width: 1, height: 1,
            },
        })

    if btn
        return result.macro, result.dummy


_ac_f.record_chain = (_ac_subs, _ac_sel, _ac_active) ->
    if not _ac_config.c.warning_shown
        btn, result = _ac_aegisub.dialog.display({
                {
                    class: "label",
                    label: [[
AegisubChain is still experimental and relies on black magic to achieve its results.
Bugs in the script might very well crash Aegisub itself. Thus, please make sure to save
or back up your subtitle file before running any AegisubChain macros.]],
                    x: 0, y: 0, width: 1, height: 1
                }
            })

        return if not btn
        _ac_config.c.warning_shown = true
        _ac_f.save_config()

    _ac_gs.recording_chain = {}


_ac_f.comparable = (v1, v2) ->
    return v1 != nil and v2 != nil and (v1 < v2 or v1 > v2)


-- sorting function for dialog fields
_ac_f.compare_dialog_fields = (field1, field2) ->
    if _ac_f.comparable(field1.y, field2.y)
        return field1.y < field2.y
    if _ac_f.comparable(field1.x, field2.x)
        return field1.x < field2.x
    if _ac_f.comparable(field1.height, field2.height)
        return field1.height < field2.height
    if _ac_f.comparable(field1.width, field2.width)
        return field1.width < field2.width

    return _ac_f.comparable(field1.name, field2.name) and field1.name < field2.name


-- takes the index of the current step, and the y to insert the elements at.
-- also takes the index of the current step (or any value uniquely identifying it)
-- returns the ypos after this section
_ac_f.add_save_dialog_for_step = (diag, stepi, step, ypos) ->
    table.insert(diag, {
        class: "label",
        label: "[#{step.macro}]: ",
        x: 0, y: ypos, width: 1, height: 1,
    })
    table.insert(diag, {
        class: "label",
        label: "Selection mode: ",
        x: 1, y: ypos, width: 1, height: 1,
    })
    table.insert(diag, {
        class: "dropdown",
        name: "selectmode#{stepi}",
        hint: [[
What lines to select after finishing this step.
"Macro's Selection" defaults to the previous selection
if the macro returns no selection.]],
        items: _ac_i.fun.table.keys _ac_c.select_mode_options,
        value: "Macro's Selection",
        x: 2, y: ypos, width: 1, height: 1,
    })
    ypos += 1

    for i, capt_diag in ipairs(step.captured_dialogs)
        table.insert(diag, {
            class: "label",
            label: "Dialog #{i}:",
            x: 0, y: ypos, width: 1, height: 1,
        })
        -- Show form fields for those fields in the macro that were changed
        for fname, field in pairs(capt_diag.fields)
            continue if _ac_c.diag_default_names[field.descriptor.class] == nil
            continue if field.value == (field.descriptor[_ac_c.diag_default_names[field.descriptor.class]] or field.descriptor["value"] or _ac_c.default_diag_values[field.descriptor.class])

            table.insert(diag, {
                class: "label",
                label: "Field #{fname}:",
                x: 1, y: ypos, width: 1, height: 1,
            })
            patched_descriptor = _ac_i.fun.table.copy field.descriptor
            patched_descriptor.name = "s#{stepi}_d#{i}_f_#{fname}"
            patched_descriptor[_ac_c.diag_default_names[patched_descriptor.class]] = field.value
            patched_descriptor.x = 2
            patched_descriptor.y = ypos
            patched_descriptor.width = 1
            patched_descriptor.height = 1
            table.insert(diag, patched_descriptor)
            table.insert(diag, {
                class: "label",
                label: "Label: ",
                x: 3, y: ypos, width: 1, height: 1,
            })
            table.insert(diag, {
                class: "edit",
                name: "s#{stepi}_d#{i}_l_#{fname}",
                text: fname,
                hint: [[How to display this option in the chain dialog, if present]],
                x: 4, y: ypos, width: 1, height: 1,
            })
            table.insert(diag, {
                class: "label",
                label: "Value mode: ",
                x: 5, y: ypos, width: 1, height: 1,
            })
            table.insert(diag, {
                class: "dropdown",
                name: "s#{stepi}_d#{i}_m_#{fname}",
                hint: [[
Whether the chain user should enter this value in a dialog,
or whether it should stay constant for all runs.]],
                items: _ac_i.fun.table.keys _ac_c.value_mode_options,
                value: _ac_c.default_value_modes[field.descriptor.class],
                x: 6, y: ypos, width: 1, height: 1,
            })
            ypos += 1

        table.insert(diag, {
            class: "label",
            label: "Button: ",
            x: 1, y: ypos, width: 1, height: 1,
        })
        table.insert(diag, {
            class: "dropdown",
            name: "s#{stepi}_d#{i}_b",
            hint: [[The button to press for this dialog]],
            items: capt_diag.buttons,
            value: capt_diag.button,
            x: 2, y: ypos, width: 1, height: 1,
        })
        table.insert(diag, {
            class: "label",
            label: "Label: ",
            x: 3, y: ypos, width: 1, height: 1,
        })
        table.insert(diag, {
            class: "edit",
            name: "s#{stepi}_d#{i}_lb",
            text: "Dialog #{i} Button",
            hint: [[How to display this option in the chain dialog, if present]],
            x: 4, y: ypos, width: 1, height: 1,
        })
        table.insert(diag, {
            class: "label",
            label: "Value mode: ",
            x: 5, y: ypos, width: 1, height: 1,
        })
        table.insert(diag, {
            class: "dropdown",
            name: "s#{stepi}_d#{i}_mb",
            hint: [[
Whether the chain user should select the button
in a dialog (with the selected value as default),
or whether it should stay constant for all runs.
The "Pass through" options will show this dialog
to the user without any modifications or autofills.]],
            items: _ac_i.fun.table.keys _ac_c.button_mode_options,
            value: _ac_c.default_value_modes["button"],
            x: 6, y: ypos, width: 1, height: 1,
        })
        ypos += 1

    return ypos


_ac_f.process_save_dialog_for_step = (results, y, stepi, step) ->
    step.dialogs = {}
    excluded_dialogs = 0
    for i, capt_diag in ipairs(step.captured_dialogs)
        buttonmode = _ac_c.button_mode_options[results["s#{stepi}_d#{i}_mb"]]
        if buttonmode == "exclude"
            excluded_dialogs += 1
            continue
        if buttonmode == "passthrough"
            step.dialogs[i - excluded_dialogs] = {
                button: {mode: buttonmode}
            }
            continue

        buttonmode = "passthrough" if buttonmode == "passthrough_defaults"

        values = {}

        fnames = _ac_i.fun.table.keys(capt_diag.fields)
        fnames = [fname for fname in *fnames when results["s#{stepi}_d#{i}_f_#{fname}"] != nil]
        table.sort(fnames, (n1, n2) -> _ac_f.compare_dialog_fields(capt_diag.fields[n1].descriptor, capt_diag.fields[n2].descriptor))

        fieldx = 0
        for j, fname in ipairs(fnames)
            field = capt_diag.fields[fname]

            fieldinfo = {
                value: results["s#{stepi}_d#{i}_f_#{fname}"],
                mode: _ac_c.value_mode_options[results["s#{stepi}_d#{i}_m_#{fname}"]],
            }
            continue if fieldinfo.mode == "exclude"

            -- I should clean this up someday...
            if fieldinfo.mode == "user"
                fieldinfo.flabel = results["s#{stepi}_d#{i}_l_#{fname}"]
                fieldinfo.x = fieldx
                fieldinfo.y = y
                fieldinfo.width = 1
                fieldinfo.height = 1
                fieldinfo.class = field.descriptor.class
                fieldinfo.hint = field.descriptor.hint

                if fieldinfo.class == "edit" or fieldinfo.class == "textbox"
                    fieldinfo.text = fieldinfo.value
                    fieldinfo.value = nil

                if fieldinfo.class == "dropdown"
                    fieldinfo.items = field.descriptor.items

                if fieldinfo.class == "intedit" or field.class == "floatedit"
                    fieldinfo.min = field.descriptor.min
                    fieldinfo.max = field.descriptor.max
                    fieldinfo.step = field.descriptor.step if field.class == "floatedit"

                fieldx += 1

            values[fname] = fieldinfo

        button = {
            value: results["s#{stepi}_d#{i}_b"],
            mode: buttonmode,
        }
        if button.mode == "user"
            button.flabel = results["s#{stepi}_d#{i}_lb"]
            button.class = "dropdown"
            button.items = capt_diag.buttons
            button.x = fieldx
            button.y = y
            button.width = 1
            button.height = 1

            fieldx += 1

        step.dialogs[i - excluded_dialogs] = {
            button: button,
            values: values,
        }

        y += 1 unless fieldx == 0

    return y


_ac_f.save_chain = (_ac_subs, _ac_sel, _ac_active) ->
    chain = _ac_gs.recording_chain
    
    defname = "New Chain"
    if _ac_config.c.chains[defname] != nil
        i = 1
        while _ac_config.c.chains[defname] != nil
            defname = "New Chain (#{i})"
            i += 1

    yes = "Save"
    cancel = "Cancel"
    diag = {
        {
            class: "label",
            label: "Chain name: ",
            x: 0, y: 0, width: 1, height: 1,
        },
        {
            class: "edit",
            name: "chainname",
            text: defname,
            hint: [[The name for your chain as it will appear in the automation menu. Can contain slashes.]],
            x: 1, y: 0, width: 2, height: 1,
        }
    }
    y = 1

    for i, step in ipairs(chain)
        y = _ac_f.add_save_dialog_for_step(diag, i, step, y)

    btn, result = _ac_aegisub.dialog.display(diag,
        {yes, cancel},
        {"ok": yes, "cancel": cancel})

    if btn == yes
        if _ac_config.c.chains[result.chainname] != nil
            yes2 = "Yes"
            cancel2 = "Abort"
            btn2, result2 = _ac_aegisub.dialog.display({{
                class: "label",
                label: "This will replace an existing chain. Are you sure you want to continue?",
                x: 0, y: 0, width: 1, height: 1,
            }}, {yes2, cancel2}, {"ok": yes2, "cancel": cancel2})

            return if btn2 != yes2

        y = 0
        for i, step in ipairs(chain)
            step.select = _ac_c.select_mode_options[result["selectmode#{i}"]]

            y = _ac_f.process_save_dialog_for_step(result, y, i, step)
            step.captured_dialogs = nil

        _ac_config.c.chains[result.chainname] = chain
        _ac_f.save_config()

        _ac_gs.recording_chain = {}


_ac_f.erase_last_macro = (_ac_subs, _ac_sel, _ac_active) ->
    yes = "Yes"
    cancel = "Cancel"
    btn, result = _ac_aegisub.dialog.display({
            {
                class: "label",
                label: "Are you sure you want to erase the last recorded macro? (#{_ac_gs.recording_chain[#_ac_gs.recording_chain].macro})",
                x: 0, y: 0, width: 1, height: 1,
            }
        },
        {yes, cancel},
        {"ok": yes, "cancel": cancel})

    return if btn != yes

    _ac_gs.recording_chain[#_ac_gs.recording_chain] = nil


_ac_f.discard_chain = (_ac_subs, _ac_sel, _ac_active) ->
    yes = "Yes"
    cancel = "Cancel"
    btn, result = _ac_aegisub.dialog.display({
            {
                class: "label",
                label: "Are you sure you want to discard the current chain?",
                x: 0, y: 0, width: 1, height: 1,
            }
        },
        {yes, cancel},
        {"ok": yes, "cancel": cancel})

    return if btn != yes

    _ac_gs.recording_chain = {}


_ac_f.configure = (subs, sel, active_line) ->
    yes = "Save"
    cancel = "Cancel"
    setslots = "Configure Slots"

    _ac_config\load()

    blacklist_default = ""
    for i, bl in ipairs(_ac_config.c.blacklist)
        blacklist_default ..= bl .. "\n"
    blacklist_default = blacklist_default\sub(1, blacklist_default\len() - 1)

    btn, result = _ac_aegisub.dialog.display({
            {
                class: "label",
                label: "Prefix for Chains:",
                x: 0, y: 0, width: 1, height: 1,
            },
            {
                class: "edit",
                text: _ac_config.c.chain_menu
                name: "chain_menu",
                hint: "The prefix to register chains with. Can contain slashes or be empty.",
                x: 1, y: 0, width: 3, height: 1,
            },
            {
                class: "label",
                label: "Search Path:",
                x: 0, y: 1, width: 1, height: 1,
            },
            {
                class: "edit",
                text: _ac_config.c.path
                name: "path",
                hint: [[
The paths to search for scripts to load.
Can contain Aegisub path specifiers.
Defaults to Aegisub's path if empty.]],
                x: 1, y: 1, width: 3, height: 1,
            },
            {
                class: "checkbox",
                name: "show_in_menu",
                label: "Show macros directly in automation menu",
                value: _ac_config.c.show_in_menu,
                hint: [[
Whether macros to record should be shown directly in the automation menu.
Off by default, as it will slow down Aegisub's startup.]],
                x: 0, y: 2, width: 2, height: 1,
            },
            {
                class: "label",
                label: "Number of chain slots:",
                x: 0, y: 3, width: 1, height: 1,
            },
            {
                class: "intedit",
                name: "num_chain_slots",
                value: _ac_config.c.num_chain_slots,
                min: 0, max: 100,
                x: 1, y: 3, width: 1, height: 1,
            },
            {
                class: "label",
                label: "Number of \"previous chain\" actions:",
                x: 0, y: 4, width: 1, height: 1,
            },
            {
                class: "intedit",
                name: "num_prev_chains",
                value: _ac_config.c.num_prev_chains,
                min: 0, max: 100,
                x: 1, y: 4, width: 1, height: 1,
            },
            {
                class: "label",
                label: "Script Blacklist:",
                x: 0, y: 5, width: 4, height: 1,
            },
            {
                class: "textbox",
                text: blacklist_default,
                name: "blacklist",
                hint: [[
A list of lua patterns to be applied to paths of scripts
to load before expanding pathnames, separated by newlines.
Scripts matching one of the patterns will be skipped.
Example:
[/\]l0%.DependencyControl%.Toolbox%.moon$
]],
                x: 0, y: 6, width: 4, height: 5,
            },
        },
        {yes, cancel, setslots},
        {"ok": yes, "cancel": cancel})

    return if btn != yes and btn != setslots

    if result.num_chain_slots != _ac_config.c.num_chain_slots
        _ac_config.c.chain_slots = [(if i <= result.num_chain_slots then _ac_config.c.chain_slots[i] else "") for i=1,result.num_chain_slots]

    -- do checks for all of these so that config merging works better
    for i, f in ipairs({"chain_menu", "path", "show_in_menu", "num_chain_slots", "num_prev_chains"})
        _ac_config.c[f] = result[f] if _ac_config.c[f] != result[f]

    if result.blacklist != blacklist_default
       ds, dn  = _ac_i.fun.string.split result.blacklist, "\n"
       _ac_config.c.blacklist = [p for p in *ds when p != ""]

    _ac_f.save_config()

    _ac_f.configure_slots() if btn == setslots


_ac_f.configure_slots = () ->
    if _ac_config.c.num_chain_slots <= 0
        _ac_aegisub.log("No slots to configure! Increase the number of slots in the configuration.")
        _ac_aegisub.cancel()
    yes = "Save"
    cancel = "Cancel"

    allchains = _ac_i.fun.table.keys _ac_config.c.chains
    table.insert(allchains, 1, "")
    diag = {}
    for i=1,_ac_config.c.num_chain_slots
        table.insert(diag, {
            class: "label",
            label: "Slot #{i}:",
            x: 0, y: i - 1, width: 1, height: 1,
        })

        table.insert(diag, {
            class: "dropdown",
            name: "slot#{i}",
            value: _ac_config.c.chain_slots[i]
            items: allchains,
            x: 1, y: i - 1, width: 1, height: 1,
        })

    btn, result = _ac_aegisub.dialog.display(diag,
        {yes, cancel, setslots},
        {"ok": yes, "cancel": cancel})

    return if btn != yes

    for i=1,_ac_config.c.num_chain_slots
        _ac_config.c.chain_slots[i] = result["slot#{i}"]

    _ac_f.save_config()


_ac_f.manage_chains = (subs, sel, active) ->
    _ac_config\load()

    chainnames = _ac_i.fun.table.keys _ac_config.c.chains
    table.sort(chainnames)

    yes = "Save"
    cancel = "Cancel"
    del = "Delete Selected"
    exp = "Export Selected"
    imp = "Import Chains"

    diag = {{
        class: "label",
        label: "Chain name                          ",
        x: 1, y: 0, width: 1, height: 1,
    }, {
        class: "label",
        label: "Select",
        x: 3, y: 0, width: 1, height: 1,
    }}
    ypos = 1

    for i, chainname in ipairs(chainnames)
        chain = _ac_config.c.chains[chainname]
        table.insert(diag, {
            class: "label",
            label: "Chain",
            x: 0, y: ypos, width: 1, height: 1,
        })
        table.insert(diag, {
            class: "edit",
            text: chainname,
            name: "#{i}_name",
            x: 1, y: ypos, width: 1, height: 1,
        })
        table.insert(diag, {
            class: "label",
            label: ":   ",
            x: 2, y: ypos, width: 1, height: 1,
        })
        table.insert(diag, {
            class: "checkbox",
            name: "#{i}_selected",
            value: false,
            x: 3, y: ypos, width: 1, height: 1,
        })

        ypos += 1

    if ypos == 1
        table.insert(diag, {
            class: "label",
            label: "No chains found!",
            x: 0, y: ypos, width: 1, height: 1,
        })

    btn, results = _ac_aegisub.dialog.display(diag, {yes, del, exp, imp, cancel}, {"ok": yes, "cancel": cancel})
    return if btn == false

    if btn == yes
        any_changed = false
        -- rename chains
        for i, c in ipairs(chainnames)
            any_changed or= results["#{i}_name"] != c
            for j, cc in ipairs(chainnames)
                continue if j <= i
                if results["#{i}_name"] == results["#{j}_name"]
                    _ac_f.log("Conflicting chain names! If you want to replace one with the other, delete the old one first.\n")
                    _ac_aegisub.cancel()

        return if not any_changed

        for i, oldname in ipairs(chainnames)
            continue if results["#{i}_name"] == oldname
            _ac_config.c.chains[results["#{i}_name"]] = _ac_config.c.chains[oldname]
            _ac_config.c.chains[oldname] = nil

        _ac_f.save_config()
        _ac_f.log("Renamed chains. Please reload your automation scripts.")
        return

    selected_chains = [c for i, c in ipairs(chainnames) when results["#{i}_selected"]]
    if btn == del
        return if #selected_chains == 0
        yes2 = "Yes"
        return if _ac_aegisub.dialog.display({{class: "label", label: "Are you sure you want to delete #{#selected_chains} chain#{if #selected_chains != 1 then "s" else ""}?", x: 0, y: 0, width: 1, height: 1}}, {yes2, cancel}, {"ok": yes2, "cancel": cancel}) != yes2

        for i, k in ipairs(selected_chains)
            _ac_config.c.chains[k] = nil

        _ac_f.save_config()

    elseif btn == exp
        selected_chains = chainnames if #selected_chains == 0

        _ac_aegisub.dialog.display({{
            class: "label",
            label: "Exported #{#selected_chains} chain#{if #selected_chains != 1 then "s" else ""}:                                                                       ",
            x: 0, y: 0, width: 1, height: 1,
        }, {
            class: "textbox",
            text: _ac_i.json.encode({c,_ac_config.c.chains[c] for c in *selected_chains}),
            x: 0, y: 1, width: 1, height: 10,
        }})

    elseif btn == imp
        btn, result = _ac_aegisub.dialog.display({{
            class: "label",
            label: "Paste a table of chains to import here:                                                                                                         ",
            x: 0, y: 0, width: 1, height: 1,
        }, {
            class: "textbox",
            name: "chains",
            x: 0, y: 1, width: 1, height: 10,
        }})

        return if not btn

        newchains = _ac_i.json.decode(result.chains)
        if newchains == nil or type(newchains) != "table"
            _ac_f.log("Invalid chain format!")
            return

        will_replace = [k for k,v in pairs(newchains) when _ac_config.c.chains[k] != nil]

        if #will_replace > 0
            yes2 = "Yes"
            return if _ac_aegisub.dialog.display({{class: "label", label: "This will override #{#will_replace} chain#{if #will_replace != 1 then "s" else ""}. Are you sure?", x: 0, y: 0, width: 1, height: 1,}}, {yes2, cancel}, {"ok": yes2, "cancel": cancel}) != yes2

        for k,v in pairs(newchains)
            _ac_config.c.chains[k] = v

        _ac_f.save_config()


_ac_f.format_ordinal = (i) ->
    return "1st" if i == 1
    return "2nd" if i == 2
    return "3rd" if i == 3
    return "#{i}th"


_ac_f.read_aegisub_path = () ->
    f = io.open(_ac_aegisub.decode_path("?user/config.json"))
    return if f == nil
    content = f\read("a")
    f\close()
    config = _ac_i.json.decode(content)
    return if config == nil
    return if config["Path"] == nil
    return if config["Path"]["Automation"] == nil
    return if config["Path"]["Automation"]["Autoload"] == nil
    _ac_c.default_path = config["Path"]["Automation"]["Autoload"]


_ac_f.wrap_register_group_macro = (...) ->
    table.insert(_ac_c.ourmacros, {...})


_ac_f.wrap_register_macro = (...) ->
    _ac_c.depctrl\registerMacro(...)


if not _ac_was_present
    _ac_f.read_aegisub_path()

    _ac_f.wrap_register_group_macro("Record next Macro in Chain", "Run an automation script as the next step in the chain being recorded.", _ac_f.wrap(_ac_f.record_run_macro))
    _ac_f.wrap_register_group_macro("Erase last Macro in Chain", "Erase the last macro you have recorded in the current chain", _ac_f.erase_last_macro, () -> _ac_gs.recording_chain != nil and #_ac_gs.recording_chain > 0)
    _ac_f.wrap_register_group_macro("Save Chain", "Finalize and save the current chain", _ac_f.save_chain, () -> _ac_gs.recording_chain != nil and #_ac_gs.recording_chain > 0)
    _ac_f.wrap_register_group_macro("Discard Chain", "Discard the current chain without saving", _ac_f.discard_chain, () -> _ac_gs.recording_chain != nil and #_ac_gs.recording_chain > 0)
    _ac_f.wrap_register_group_macro("Configure", "Configure #{script_name}", _ac_f.configure)
    _ac_f.wrap_register_group_macro("Manage Chains", "Manage your recorded chains", _ac_f.manage_chains)

    for i=1,_ac_config.c.num_chain_slots
        _ac_f.wrap_register_group_macro("Actions/Chain Slot #{i}", "The #{_ac_f.format_ordinal(i)} configurable chain slot.", _ac_f.wrap((...) -> _ac_f.run_chain_slot(i, ...)))

    for i=1,_ac_config.c.num_prev_chains
        _ac_f.wrap_register_group_macro("Actions/Repeat #{_ac_f.format_ordinal(i)} Last Chain", "Repeat a previously executed chain", _ac_f.wrap((...) -> _ac_f.repeat_last_chain(i, false, ...)))
        _ac_f.wrap_register_group_macro("Actions/Repeat #{_ac_f.format_ordinal(i)} Last Chain with Same Settings", "Repeat a previously executed chain with the same values set", _ac_f.wrap((...) -> _ac_f.repeat_last_chain(i, true, ...)))

    for k, v in pairs(_ac_config.c.chains)
        _ac_f.wrap_register_macro("#{_ac_config.c.chain_menu}#{k}", "A chain recorded by #{script_name}", _ac_f.wrap((...) -> _ac_f.run_chain(v, ...)))

    if _ac_config.c.show_in_menu
        _ac_f.wrap(_ac_f.load_all_scripts)()
        for k, v in pairs(_ac_gs.captured_macros)
            runner = (...) ->
                _ac_gs.selected_macro = k
                _ac_f.record_run_macro(...)

            _ac_f.wrap_register_group_macro("Record next Macro/#{k}", "Run #{k} as the next step in the chain being recorded.", _ac_f.wrap(runner))

    _ac_c.depctrl\registerMacros(_ac_c.ourmacros)

_ac_gs.initialized = true
