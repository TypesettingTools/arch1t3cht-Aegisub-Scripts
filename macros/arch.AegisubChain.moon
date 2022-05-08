export script_name = "AegisubChain"
export script_description = "Compose macros out of existing automation scripts."
export script_version = "0.1.0"
export script_namespace = "arch.#{script_name}"
export script_author = "arch1t3cht"


-- All global runtime variables are prefixed by _ac_ so that they won't be modified by third-party scripts called by us.
-- With environments this shouldn't actually be necessary, but let's just take the safe route.
-- TODO do the same for local variables (which actually is necessary, as we can't change the environment before defining the function)

_ac_was_present = _ac_present
export _ac_present = true
export _ac_version = script_version
export _ac_f = {}  -- functions
export _ac_c = {}  -- constants
export _ac_i = {}  -- imports
export _ac_gs = {} -- global mutable variables
export _ac_default_config = {
    chain_menu: "AegisubChain Chains/"  -- Submenu to list all chains in. Can contain slashes.
    path: true                          -- Path to search for macros in. Defaults to Aegisub's path if == true
    warning_shown: false                -- Whether the instability warning was shown
    chains: {}                          -- Defined chains
}

-- Aegisub gives us its api in the aegisub object. Even though debug prints didn't show it for me,
-- functions from a previous macro run are invalid in the next macro run.
-- Furthermore, the updated aegisub api object will only reach our script if, at the end of the last run,
-- the aegisub object is in the aegisub variable. Because of this, we need to juggle different aegisub instances
-- back and forth when running various scripts.
export _ac_aegisub = aegisub
export aegisub = {k, v for k, v in pairs(_ac_aegisub)}

-- IMPORTS
_ac_i.depctrl = require'l0.DependencyControl'
_ac_i.config = require'l0.DependencyControl.ConfigHandler'
_ac_i.fun = require'l0.Functional'
_ac_i.lfs = require'lfs'
_ac_i.json = require'json'
_ac_i.moonbase = require'moonscript.base'

-- CONSTANTS

-- Foolproof method to ensure that AegisubChain never loads itself. Should never be changed.
_ac_c.red_flag = "Hi, I'm AegisubChain, please don't load me! The following is a random red flag string: Jnd4nKxQWAMinndFqKFotlEJgaiRT0lepihiKGYaERA="
_ac_c.myname = "arch.AegisubChain.moon"

_ac_c.default_path = "?user/automation/autoload/|?data/automation/autoload/"    -- Will be read from aegisub config if it exists

_ac_c.init_dir = _ac_i.lfs.currentdir()    -- some script might change the working directory, so we reset it each time

_ac_c.depctrl = _ac_i.depctrl {}
_ac_c.config_file = _ac_c.depctrl\getConfigFileName()

_ac_c.debug = false      -- whether we're debugging right now. This turns off all pcalls so error messages can propagate fully.

_ac_c.select_mode_options = {
    "Macro's Selection": "macro",
    "Previous Selection": "keep",
    "All Changed Lines": "changed",
}

_ac_c.value_mode_options = {
    "Set in Dialog": "user",
    "Constant": "const",
}

_ac_c.default_diag_values = {
    "edit": "",
    "string": "",
    "dropdown": "",
    "color": "#000000",
    "coloralpha": "#00000000",
    "alpha": "",
    "intedit": 0,
    "floatedit": 0,
    "checkbox": false,
}

_ac_c.default_value_modes = {
    "edit": "Set in Dialog",
    "string": "Set in Dialog",
    "dropdown": "Constant",
    "color": "Set in Dialog",
    "coloralpha": "Set in Dialog",
    "alpha": "Set in Dialog",
    "intedit": "Set in Dialog",
    "floatedit": "Set in Dialog",
    "checkbox": "Constant",
    "button": "Constant",
}

-- CONFIG
export _ac_config = _ac_i.config(_ac_c.config_file, _ac_default_config, "config")

-- GLOBAL STATE
_ac_gs.recording = false
_ac_gs.recording_chain = {}     -- list of steps in macro currently being recorded
_ac_gs.current_script = nil     -- script currently being loaded or run
_ac_gs.show_dummy_dialogs = false
_ac_gs.loaded_scripts = nil     -- table of scripts we have loaded
_ac_gs.captured_macros = nil    -- table of macros that have been "registered" with us

-- Yes, we do all this noise in global state, because it's just way less of a hassle to
-- juggle all of these variables through different environments.
_ac_gs.captured_dialogs = nil   -- list of dialogs that have been captured for the current step

_ac_gs.current_chain = nil      -- chain currently being executed
_ac_gs.values_for_chain = nil   -- results of the dialog we showed the user before running the chain
_ac_gs.current_step_index = nil -- index of the current step in the chain being executed
_ac_gs.current_step_dialog_index = nil  -- index of the dialog for the current step of the chain being executed

_ac_gs.our_globals = {}

-- more juggling
export _ac_depctrl_aegisub = aegisub
export _ac_script_aegisub = {}
export aegisub = _ac_aegisub

_ac_c.initial_globals = {k,true for k, v in pairs(_G)}


-- There is some other global state we need to keep track of:
--  - The working directory
--  - Loaded packages, and their captured variables

-- FUNCTION DEFINITIONS

_ac_f.pcall_wrap = (f, ...) ->
    if _ac_c.debug
        return true, f(...)
    return pcall(f, ...)


_ac_f.save_config = () ->
    _ac_config\write(true)


_ac_f.register_macro_hook = (name, desc, fun, testfun, actfun) ->
    _ac_aegisub.log(5, "Registered #{name} as #{fun}!\n")
    _ac_gs.captured_macros[name] = {
        fun: fun,
        script: _ac_gs.current_script
    }


_ac_f.dialog_open_hook = (dialog, buttons, button_ids) ->
    if _ac_gs.captured_dialogs != nil
        -- we're currently recording a macro, so display the dialog normally for now
        btn, result = _ac_aegisub.dialog.display(dialog, buttons, button_ids)

        fields = {k,{value: v} for k,v in pairs(result)}

        -- TODO add an option for showing a dummy dialog first
        -- again we just record everything for now and filter it later.
        for i, field in pairs(dialog)
            if field.name != nil and fields[field.name] != nil
                fields[field.name].descriptor = field

        table.insert(_ac_gs.captured_dialogs, {
            buttons: buttons,
            button: btn,
            fields: fields,
        })

        if _ac_gs.show_dummy_dialogs
            -- show another dialog, and use its values
            btn, result = _ac_aegisub.dialog.display(dialog, buttons, button_ids)
            return btn, result

        return btn, result

    elseif _ac_gs.current_step_index
        step = _ac_gs.current_chain[_ac_gs.current_step_index]
        if step.dialogs == nil
            _ac_aegisub.log("Invalid chain config!\n")
            _ac_aegisub.cancel()

        diaginfo = step.dialogs[_ac_gs.current_step_dialog_index]
        if diaginfo == nil
            _ac_aegisub.log("Unknown dialog shown!\n")

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
        else
            -- either an unknown dialog or a dialog we should show
            -- in any case, just show it
            btn, result = _ac_aegisub.dialog.display(dialog, buttons, button_ids)
            return btn, result
    else
        _ac_aegisub.log("Unknown dialog shown!\n")
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
    if _ac_config.c.path ~= true
        path = _ac_config.c.path

    ds, dn = _ac_i.fun.string.split path, "|"

    for i, dir in ipairs(ds)
        for file in _ac_i.lfs.dir(_ac_aegisub.decode_path(dir))
            continue if file == _ac_c.myname
            continue if file\match("^l0%.DependencyControl")   -- let's not
            if file\match("%.lua$") or file\match("%.moon$")
                table.insert(scripts, dir .. file)

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

    _ac_l_env = {}
    _ac_f.move_globals(_ac_l_env, _ac_gs.our_globals)

    local chunk
    if script\match("%.moon$")
        chunk = assert(_ac_i.moonbase.loadstring(content))
    else
        chunk = assert(loadstring(content))

    _ac_aegisub.log(5, "Loading #{scrpath}...\n")
    status, errc = _ac_f.pcall_wrap(chunk)
    if status == false
        if _ac_c.debug
            _ac_aegisub.log("Failed to load #{script} with the following error:\n")
            _ac_aegisub.log("#{errc}\n")
            _ac_aegisub.cancel()
        else
            _ac_aegisub.log("Failed to load #{script}! Skipping...\n")

    _ac_f.move_globals(_ac_gs.our_globals, _ac_l_env)

    _ac_gs.loaded_scripts[script] = {
        cwd: _ac_i.lfs.currentdir(),
        env: _ac_l_env
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

    _ac_aegisub.progress.task("Loading macros...")

    for i, script in ipairs(scripts)
        _ac_aegisub.progress.task("Loading macros... [#{script\match("[^/]+$")}]")
        _ac_aegisub.progress.set(100 * (i - 1) / #scripts)
        _ac_f.run_script_initial(script)

    for k, v in pairs(_ac_gs.captured_macros)
        _ac_aegisub.log(4, "Found macro #{k} as #{v}\n")


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
                _ac_aegisub.log("Unknown operation argument: #{op.args[1]}\n")
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
        _ac_aegisub.log("Failed to run #{macroname} with the following error:\n")
        _ac_aegisub.log("#{errc}\n")
        _ac_aegisub.cancel()

    script.cwd = _ac_i.lfs.currentdir()
    _ac_f.move_globals(_ac_gs.our_globals, script.env)

    changed, updatesel, updateactive = _ac_f.process_operations(operations, prevlen, _ac_sel, _ac_active)

    return newsel, newactive, changed, updatesel, updateactive


_ac_f.record_run_macro = (_ac_subs, _ac_sel, _ac_active) ->
    if not _ac_gs.recording
        return

    macroname, dummy = _ac_f.select_macro()
    if macroname == nil
        return

    _ac_gs.show_dummy_dialogs = dummy
    _ac_gs.captured_dialogs = {}
    newsel, newactive, changed, updatesel, updateactive = _ac_f.run_script_macro(macroname, _ac_subs, _ac_sel, _ac_active)

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
            for fname, field in pairs(diag.values)
                continue if field.mode != "user"

                -- we could place all of the invalid fields at the end, but that's way too
                -- much boilerplate code for way too little gain
                if not _ac_f.validate_field(field)
                    _ac_aegisub.log("Invalid dialog config for user field!\n")
                    _ac_aegisub.cancel()

                table.insert(user_diag, {
                    class: "label",
                    label: field.label,
                    x: 2 * field.x, y: field.y, width: 1, height: field.height,
                })

                table.insert(user_diag, {
                    class: field.class,
                    value: field.value,
                    items: field.items,
                    text: field.text
                    name: "s#{stepi}_d#{i}_f_#{fname}"
                    x: 2 * field.x + 1, y: field.y, width: 2 * field.width - 1, height: field.height,
                })

            if diag.button.mode == "user"
                field = diag.button

                if not _ac_f.validate_field(field)
                    _ac_aegisub.log("Invalid dialog config for user field!\n")
                    _ac_aegisub.cancel()

                table.insert(user_diag, {
                    class: "label",
                    label: field.label,
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
            for fname, field in pairs(diag.values)
                continue if field.mode != "user"
                diag_values.values[fname] = result["s#{stepi}_d#{i}_f_#{fname}"]

            if diag.button.mode == "user"
                diag_values.button = result["s#{stepi}_d#{i}_b"]

            table.insert(step_values, diag_values)
        table.insert(user_values, step_values)

    return user_values


_ac_f.run_chain = (chain, _ac_subs, _ac_sel, _ac_active) ->
    _ac_gs.current_chain = chain

    _ac_gs.values_for_chain = _ac_f.get_values_for_chain(chain)
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
            _ac_sel = newsel
            _ac_active = newactive
            _ac_sel = updatesel if _ac_sel == nil
            _ac_active = updateactive if _ac_active == nil

        _ac_gs.current_step_dialog_index = nil
        _ac_gs.current_step_index = nil

    _ac_gs.current_chain = nil
    _ac_gs.values_for_chain = nil

    return _ac_sel, _ac_active


-- Wraps a function in a try-finally block - If our script crashes we still try to restore the environment to something usable.
_ac_f.wrap = (f) ->
    (...) ->
        _ac_f.initialize()

        -- newsel, newactive = f(...)
        -- TODO uncomment
        status, newsel, newactive = _ac_f.pcall_wrap(f, ...)
        if status == false
            errc = newsel
            _ac_aegisub.log("Failed with the following error:\n")
            _ac_aegisub.log("#{errc}\n")
            _ac_aegisub.cancel()

        _ac_f.finalize()

        return newsel, newactive


-- returns either nil (on cancel) or a selected macro, as well as whether a dummy dialog should be shown first
_ac_f.select_macro = () ->
    _ac_f.load_all_scripts()

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
    _ac_aegisub.log(_ac_c.default_path .. "\n")
    _ac_aegisub.cancel()
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

    _ac_gs.recording = true
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
        name: "selectmode#{i}",
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
            continue if field.class == "label"
            continue if field.value == (field.descriptor.value or _ac_c.default_diag_values[field.descriptor.class])

            table.insert(diag, {
                class: "label",
                label: "Field #{fname}:",
                x: 1, y: ypos, width: 1, height: 1,
            })
            patched_descriptor = _ac_i.fun.table.copy field.descriptor
            patched_descriptor.name = "s#{stepi}_d#{i}_f_#{fname}"
            patched_descriptor.value = field.value
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
or whether it should stay constant for all runs.]],
            items: _ac_i.fun.table.keys _ac_c.value_mode_options,
            value: _ac_c.default_value_modes["button"],
            x: 6, y: ypos, width: 1, height: 1,
        })
        ypos += 1

    return ypos


_ac_f.process_save_dialog_for_step = (results, y, stepi, step) ->
    step.dialogs = {}
    for i, capt_diag in ipairs(step.captured_dialogs)
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

            if fieldinfo.mode == "user"
                fieldinfo.label = results["s#{stepi}_d#{i}_l_#{fname}"]
                fieldinfo.x = fieldx
                fieldinfo.y = y
                fieldinfo.width = 1
                fieldinfo.height = 1
                fieldinfo.class = field.descriptor.class

                if fieldinfo.class == "edit" or fieldinfo.class == "textbox"
                    fieldinfo.text = fieldinfo.value
                    fieldinfo.value = nil

                if fieldinfo.class == "dropdown"
                    fieldinfo.items == field.descriptor.items

                fieldx += 1

            values[fname] = fieldinfo

        button = {
            value: results["s#{stepi}_d#{i}_b"],
            mode: _ac_c.value_mode_options[results["s#{stepi}_d#{i}_mb"]],
        }
        if button.mode == "user"
            button.label = results["s#{stepi}_d#{i}_lb"]
            button.class = "dropdown"
            button.items = capt_diag.buttons
            button.x = fieldx
            button.y = y
            button.width = 1
            button.height = 1

            fieldx += 1

        step.dialogs[i] = {
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
            btn2, result2 = _ac_aegisub.dialog.display({
                class: "label",
                label: "This will replace an existing chain. Are you sure you want to continue?",
                x: 0, y: 0, width: 1, height: 1,
            }, {yes2, cancel2}, {"ok": yes2, "cancel": cancel2})

            return if btn2 != yes2

        y = 0
        for i, step in ipairs(chain)
            step.select = _ac_c.select_mode_options[result["selectmode#{i}"]]

            y = _ac_f.process_save_dialog_for_step(result, y, i, step)
            step.captured_dialogs = nil

        _ac_config.c.chains[result.chainname] = chain
        _ac_f.save_config()

        _ac_gs.recording = false
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

    if btn != yes
        return

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

    if btn != yes
        return

    _ac_gs.recording = false
    _ac_gs.recording_chain = nil


_ac_f.read_aegisub_path = () ->
    f = io.open(_ac_aegisub.decode_path("?user/config.json"))
    return if f == nil
    content = f\read("a")
    config = _ac_i.json.decode(content)
    return if config == nil
    return if config["Path"] == nil
    return if config["Path"]["Automation"] == nil
    return if config["Path"]["Automation"]["Autoload"] == nil
    _ac_c.default_path = config["Path"]["Automation"]["Autoload"]


if not _ac_was_present
    _ac_f.read_aegisub_path()

    aegisub.register_macro("#{script_name}/Record Chain", "Begin recording a chain", _ac_f.record_chain, () -> not _ac_gs.recording)
    aegisub.register_macro("#{script_name}/Record next Macro in Chain", "Run an automation script as the next step in the chain being recorded.", _ac_f.wrap(_ac_f.record_run_macro), () -> _ac_gs.recording)
    aegisub.register_macro("#{script_name}/Erase last Macro in Chain", "Erase the last macro you have recorded in the current chain", _ac_f.erase_last_macro, () -> _ac_gs.recording and #_ac_gs.recording_chain > 0)
    aegisub.register_macro("#{script_name}/Save Chain", "Finalize and save the current chain", _ac_f.save_chain, () -> _ac_gs.recording)
    aegisub.register_macro("#{script_name}/Discard Chain", "Discard the current chain without saving", _ac_f.discard_chain, () -> _ac_gs.recording)

    for k, v in pairs(_ac_config.c.chains)
        aegisub.register_macro("#{_ac_config.c.chain_menu}#{k}", "A chain recorded by #{script_name}", _ac_f.wrap((...) -> _ac_f.run_chain(v, ...)))
