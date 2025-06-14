export script_name = "Fix KFX Boilerplate"
export script_description = "Fix certain errors in boilerplate lines in old KFX templates on new Aegisub versions"
export script_author = "arch1t3cht"
export script_namespace = "arch.FixKFXBoilerplate"
export script_version = "1.0.0"

haveDepCtrl, DependencyControl = pcall(require, "l0.DependencyControl")
local depctrl
if haveDepCtrl
    depctrl = DependencyControl{
        feed: "https://raw.githubusercontent.com/TypesettingTools/arch1t3cht-Aegisub-Scripts/main/DependencyControl.json",
    }

-- For now we just apply the least invasive fix of replacing _G.unicode.len(foo) with _G.unicode.len((foo)).
-- If this turns out to miss too many files we can do something simpler like just patch _G.unicode.len with a wrapper function.

find_matching_paren = (str, n) ->
    return nil if str\sub(n, n) ~= "("

    depth = 1

    while n <= #str
        n += 1
        c = str\sub(n, n)

        depth += 1 if c == "("
        depth -= 1 if c == ")"

        return n if depth == 0
    return nil


fix_boilerplate = (subs, sel) ->
    patched = 0
    for li, line in ipairs(subs)
        continue unless line.class == "dialogue"
        continue unless line.comment
        continue unless line.effect\match("template") or line.effect\match("code")

        while true
            i = 1
            newtext = line.text
            while true
                _, i = line.text\find("unicode.len(", i, true)
                break if i == nil
                matching = find_matching_paren(line.text, i)
                matching2 = find_matching_paren(line.text, i + 1)

                continue if matching == nil
                continue if matching2 == matching - 1

                newtext = line.text\sub(1, i) .. "(" .. line.text\sub(i + 1, matching) .. ")" .. line.text\sub(matching + 1)
                patched += 1

            break if newtext == line.text
            line.text = newtext

        subs[li] = line
    
    aegisub.log("Patched #{patched} instances of _G.unicode.len.")


if haveDepCtrl
    depctrl\registerMacro fix_boilerplate
else
    aegisub.register_macro(script_name, script_description, fix_boilerplate)
