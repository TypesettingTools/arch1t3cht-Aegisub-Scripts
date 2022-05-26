script_name = "Rewriting Tools"
script_author = "arch1t3cht"
script_version = "1.0.0"
script_namespace = "arch.RWTools"
script_description = "Deactivating the current line and escaping styling tags"

switch_name = "Switch Active Lines"
switch_description = "Deactivates the active line and activates any inactive lines marked with !- ."

rewrite_name = "Prepare Rewrite"
rewrite_description = "Deactivates the active line and copies it to a new line for rewriting."

clean_name = "Clean Up Styling Tag Escapes"
clean_description = "Removes all pipe ('|') characters from the end of styling blocks."

CONFIG_PATH = aegisub.decode_path('?user/arch_scripts.conf')

haveDepCtrl, DependencyControl = pcall(require, "l0.DependencyControl")

default_config = {
    default_signature = "OG",
    personal_signature = "",
    auto_fixes = true,
    forbid_nested = true,
}

if haveDepCtrl then
    depctrl = DependencyControl({})
    config = depctrl:getConfigHandler(default_config, "config")
else
    id = function() return nil end
    config = {c = default_config, load = id, write = id}
end

-- This script automates the process of commenting and uncommenting subitle lines during rewrites,
-- using conventions used in some of the groups I'm working in.
--
-- Line format (formal-ish specification - scroll down for the functions and explicit examples):
-- Every line of a subtitle file is a sequence of sections of one of the following forms:
-- - Global styling tags: A brace block whose content starts with a backslash and ends with a pipe ('|').
--      These are styling overrides which should globally apply to any rewrite (e.g. position, alignment, font size, etc)
--      as opposed to local styling tags like those italicizing certain words.
--
--      Each (contiguous set) of global styling tags starts a new text section, each of which will have its self-contained set of rewrites.
--      To start such a section without changing styles, simply use an empty tag of this format like {\|}.
--
-- - Text sections: The text before, after, or in between two global styling tags.
--      Each of these sections reprents one bit of text, which is open for rewrites.
--      Such a section should be a sequence of blocks of one of the following forms:
--          - Inactive line: A brace block not started by a backslash or asterisk (Asterisks are allowed for compatibility with Dialog Swapper).
--              This can be any brace block matching this format (so also miscellaneous comments that aren't actual lines),
--              But in order for the script to interact with them, they should have the format
--                  {<proposed line> - <author>}    ,
--              where the <author> signature could potentially also contain other comments.
--              In the <proposed line>, should be escaped by replacing their braces with square brackets,
--              and the backslashes by harmless forward slashes.
--
--          - Active line: A block of the form
--                  <proposed line>[{<author>}]   ,
--            where the <proposed line> is allowed to contain (local) styling tags, and the <author> signature
--            must not begin with a backslash or asterisk and is only allowed to be omitted when this block is the last
--            in its section (since otherwise the following inactive line would be incorrectly recognized as the signature)
--
--      Only one of the blocks in a section should be an active line at any time.
--
-- In most cases, there will be only one non-empty text section.
--
-- The script's main function "Switch Active Lines" will, for each section:
-- - Deactivate any active lines, signing them with the default signature (defaults to "OG") if no signature is present.
-- - Activate any inactive lines where the " - " separating the line from the signature has been marked by replacing it with " !- ".
--   Thus, there should ideally be just one line per section marked this way.
-- - If there is a block that has been deactivated, but no block has been activated (suggesting that the user wants to write a new suggested line),
--   it will add a new signature at the end of the section, providing that one is specified in the configuration.
--
-- The function "Prepare Rewrite" will do all of the above, but also
-- - Copy the line that was just deactivated to the end of the section, before the added signature
--   That way, the user can quickly propose a small change in the line.
-- - Always add a signature, as long as one is configured.
--
-- The function "Clean Up Styling Tag Escapes" will simply remove all the pipe ('|') characters from global styling tags.
--
-- Examples:
-- - Deactivating the line
--      {\i1}Hello{\i0}, world!{author}
--   Will turn it into
--      {[/i1]Hello[/i0], world! - author}
--   If a personal signature like "me" is set in the configuration, it will automatically be added:
--      {[/i1]Hello[/i0], world! - author}{me}
--
-- - Deactivating the line
--      {\an8|}Hello, {\i1}world{\i0}!
--   Will turn it into
--      {\an8|}{Hello,[/i1]world[/i0]! - OG}
--   where the default signature "OG" can be set to a different on in the configuration.
--
-- - Applying "Switch Lines" to the line
--      {Hello, [/i1]world[/i0]! !- OG}{foo - bar}  .
--   Will turn it into
--      Hello, {\i1}world{\i0}!{OG}{foo - bar}  .
--   Applying "Switch Lines" again will turn this line into
--      {Hello, [/i1]world[/i0]! - OG}{foo - bar}  ,
--   which is just the beginning line without the marker.
--   On the other hand, applying "Prepare Rewrite" to this second line will turn it into
--      {Hello, [/i1]world[/i0]! - OG}{foo - bar}Hello, {\i1}world{\i0}!{me}  ,
--   where "me" is the personal signature set in the configuration.
--
-- - A more complex example containing multiple sections: Consider a line where two people speak simultaneously,
--   which is represented using en dashes (represented as hyphens here):
--              - foo!\N- bar!
--   To make a rewrite for only one of these lines, add a separator after \N:
--              - foo!\N{\|}- bar!
--   Now these can be both be rewritten with "Prepare Rewrite":
--      {- foo!\N - OG}- foo!\N{me}{\|}{- bar! - OG}- bar!{me}
--   Say we want to rewrite the first line to "- foo2!\N", and don't rewrite the second line:
--      {- foo!\N - OG}- foo2!\N{me}{\|}{- bar! - OG}
--   Apply "Switch Lines" again:
--      {- foo!\N - OG}{- foo2!\N - me}{me}{\|}{- bar! - OG}
--   This will cause a duplicate signature, but preventing this would require a lot more macro options. Remove this duplicate, and mark both lines:
--      {- foo!\N - OG}{- foo2!\N !- me}{\|}{- bar! !- OG}
--   Finally, apply "Switch Lines":
--      {- foo!\N - OG}- foo2!{me}\N{\|}- bar!{OG}
--   This specific application is very tedious for small rewrites, but can still greatly speed up the process for longer sections with formatting.
--
-- It is strongly recommended to bind both of the rewriting macros to keybinds (e.g. Ctrl+K and Ctrl+Shift+K respectively).
--
-- Acknowledgements:
-- - Config code was blatantly stolen from Clipper.

-------------------
-- GENERAL UTILS (from Clipper) --
-------------------


function unreachable()
    if not val then
        aegisub.log("Incorrect line format! Aborting.")
        aegisub.cancel()
    end
end


-- These two functions are split up because signed deactivated lines like
-- {Upper line\N - author} would be broken by simply stripping spaces
-- surrounding \N tags everywhere.
-- An unintended but welcome side effect is that only those lines which the
-- user touches will have text fixes applied - this ensures a basic level
-- of reversibility.
function fix_text(line)
    -- Applies some basic formatting fixes:
    -- Removes spaces surrounding \N tags
    while true do
        local newline = line
            :gsub(" *\\N *([^!])", "\\N%1")
            :gsub(" *\\n *", "\\n")

        if newline == line then
            return line
        end
        line = newline
    end
end

function fix_line_format(line)
    -- Applies some basic formatting fixes:
    -- Removes spaces surrounding or padding {} blocks
    while true do
        local newline = line
            :gsub("{ *", "{")
            :gsub("({[^}]-) *}", "%1}")  -- make sure '}' is closing a tag here (still breaks if there's nested tags, but this is the best lua patterns can do.)

        if newline == line then
            return line
        end
        line = newline
    end
end

function fix_text_checked(line)
    if config.c.auto_fixes then
        return fix_text(line)
    else
        return line
    end
end

function fix_line_format_checked(line)
    if config.c.auto_fixes then
        return fix_line_format(line)
    else
        return line
    end
end

function stripstart(intext, out)
    local ws = intext:match("^ *")
    intext = intext:sub(#ws + 1)
    if not config.c.auto_fixes then
        out = out .. ws
    end
    return intext, out
end

function appendstripend(text, out)
    if config.c.auto_fixes then
        local ws = text:match(" *$")
        text = text:sub(1, #text - #ws)
    end
    return out .. text
end

function get_signature(sign)
    if sign ~= "" then
        return "{" .. sign .. "}"
    end
    return ""
end

function switch_lines_proper(subs, sel, rewrite)
    for _, i in ipairs(sel) do
        local line = subs[i]

        if config.c.forbid_nested then
            if line.text:match("{[^}]+{") then
                aegisub.log("Nested braces detected! Please fix them before running the script. Aborting...")
                return
            end
        end

        -- local intext = fix_line_format_checked(line.text)
        local intext = line.text
        local out = ""

        local deactivated = false
        local reactivated = false
        local newline = ""

        while true do   -- parse components of the line
            intext, out = stripstart(intext, out)
            local escaped_braceblock = intext:match("^{\\[^}]-|}")
            local deactive_line = intext:match("^{[^\\*][^}]-}")
            -- and some edge cases:
            local empty_block = intext:match("^{}")
            local unterminated_brace = intext:match("^{[^}]*$")

            if escaped_braceblock ~= nil or intext == "" then
                if rewrite then
                    newline, out = stripstart(newline, out)
                    newline = fix_text_checked(newline)
                    out = appendstripend(newline, out)
                end
                if (deactivated and not reactivated) or (rewrite and newline ~= "") then
                    out = out .. get_signature(config.c.personal_signature)
                end
                if intext == "" then
                    break
                end
                out = out .. escaped_braceblock 
                intext = intext:sub(#escaped_braceblock + 1)

                deactivated = false
                reactivated = false
                newline = ""
            elseif deactive_line ~= nil then
                if deactive_line:match(" !%- ") == nil then
                    out = out .. deactive_line
                else
                    local reactivate_line = deactive_line
                    -- evil capture hacks to replace only those forward slashes
                    -- by backslashes, that are contained in square brackets.
                    while true do
                        local r = reactivate_line:gsub("(%[[^%]]-)/([^%]]-%])", "%1%\\%2")
                        if r == reactivate_line then
                            break
                        end
                        reactivate_line = r
                    end
                    if config.c.auto_fixes then
                        reactivate_line = reactivate_line:gsub(" * !%- ", " !- ")
                    end

                    out = out .. fix_text_checked(reactivate_line:gsub("^{", ""):gsub("%[", "{"):gsub("%]", "}"):gsub(" !%- ", "{"))
                    reactivated = true
                end

                intext = intext:sub(#deactive_line + 1)
            elseif empty_block ~= nil then
                -- just ignore it
                out = out .. empty_block
                intext = intext:sub(#empty_block + 1)
            elseif unterminated_brace ~= nil then
                -- terminate it and (effectively) abort
                out = out .. unterminated_brace
                intext = intext:sub(#unterminated_brace + 1)
            else    -- beginning of an active line
                local linetext = ""
                local linesignature = config.c.default_signature
                -- this could be done with a bigger regex and some gsubs,
                -- but in edge cases with broken nested braces this might hold up better
                while intext ~= "" do
                    local escaped_braceblock = intext:match("^{[\\*][^}]-|}")
                    local styling_braceblock = intext:match("^{[\\*][^}]-}")
                    local cleartext = intext:match("^[^{]+")
                    local signature = intext:match("^{[^}]-}")

                    if escaped_braceblock ~= nil then
                        break
                    elseif styling_braceblock ~= nil then
                        newline = newline .. styling_braceblock
                        linetext = linetext .. styling_braceblock:gsub("{", "["):gsub("}", "]"):gsub("\\", "/")
                        intext = intext:sub(#styling_braceblock + 1)
                    elseif cleartext ~= nil then
                        newline = newline .. cleartext
                        linetext = linetext .. cleartext
                        intext = intext:sub(#cleartext + 1)
                    elseif signature ~= nil then
                        if #signature >= 2 then
                            assert(signature[2] ~= "|" and signature[2] ~= "\\")
                        end

                        linesignature = signature:gsub("[{}]", "")
                        intext = intext:sub(#signature + 1)
                        break
                    else
                        assert(false)
                    end
                end

                out = out .. "{" .. fix_text_checked(linetext)
                if linesignature ~= "" then
                    out = out .. " - " .. linesignature
                end
                out = out .. "}"

                deactivated = true
            end 
        end

        line.text = fix_line_format_checked(out)
        subs[i] = line
    end
end

function clean_lines(subs, sel)
    load_config()
    for _, i in ipairs(sel) do
        local line = subs[i]

        while true do
            local newtext = line.text:gsub("({\\[^}]-)|}", "%1}")

            if newtext == line.text then
                break
            end

            line.text = newtext
        end

        subs[i] = line
    end
end

function switch_lines(subs, sel)
    switch_lines_proper(subs, sel, false)
end

function rewrite_line(subs, sel)
    switch_lines_proper(subs, sel, true)
end

function can_run(subs, sel)
    return #sel == 1
end

function configure()
    config:load()
    local diag = {
        {class = 'label', label = 'Default signature', x = 0, y = 0, width = 1, height = 1},
        {
            class = 'edit',
            name = 'default_signature',
            hint = "Signature to sign unsigned active lines with. Leave blank to deactivate.",
            value = config.c.default_signature,
            x = 1, y = 0, width = 1, height = 1,
        },
        {class = 'label', label = 'Your signature', x = 0, y = 1, width = 1, height = 1},
        {
            class = 'edit',
            name = 'personal_signature',
            hint = "Signature to automatically insert when deactivating a line. Leave blank to deactivate.",
            value = config.c.personal_signature,
            x = 1, y = 1, width = 1, height = 1,
        },
        {class = 'label', label = 'Apply auto fixes', x = 0, y = 2, width = 1, height = 1},
        {
            class = 'checkbox',
            name = 'auto_fixes',
            hint = "Whether to automatically remove unnecessary spaces. Deactivate if you know what you're doing (e.g. for special typesetting).",
            value = config.c.auto_fixes,
            x = 1, y = 2, width = 1, height = 1,
        },
        {class = 'label', label = 'Check for nested braces', x = 0, y = 3, width = 1, height = 1},
        {
            class = 'checkbox',
            name = 'forbid_nested',
            hint = "Whether to abort if nested braces are found. Deactivate if you know what you're doing.",
            value = config.c.forbid_nested,
            x = 1, y = 3, width = 1, height = 1,
        },
    }
    local buttons = {'OK', 'Cancel'}
    local button_ids = {ok = 'OK', cancel = 'Cancel'}
    local button, results = aegisub.dialog.display(diag, buttons, button_ids)
    if button == false then aegisub.cancel() end

    for i,v in ipairs({"personal_signature", "default_signature", "auto_fixes", "forbid_nested"}) do
        if results[v] ~= config.c[v] then
            config.c[v] = results[v]
        end
    end

    config:write()

    return results
end

aegisub.register_macro(script_name .. "/" .. switch_name,switch_description,switch_lines,can_run)
aegisub.register_macro(script_name .. "/" .. rewrite_name,rewrite_description,rewrite_line,can_run)
aegisub.register_macro(script_name .. "/" .. clean_name,clean_description,clean_lines)
aegisub.register_macro(script_name .. "/" .. "Configure","Configure Rewriting Tools",configure)