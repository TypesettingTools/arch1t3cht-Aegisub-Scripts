# Aegisub-Scripts
My automation scripts for Aegisub. You're probably here for AegisubChain, but there are also some other useful scripts for editing and timing in here.

- [Aegisub-Scripts](#aegisub-scripts)
  - [AegisubChain](#aegisubchain)
    - [Basic usage](#basic-usage)
    - [Detailed Documentation](#detailed-documentation)
      - [Script Registration and Execution](#script-registration-and-execution)
      - [Recording Process](#recording-process)
      - [Chain config format](#chain-config-format)
    - [Limitations and Workarounds](#limitations-and-workarounds)
    - [Compatibility](#compatibility)
      - [API](#api)
    - [Possible future features](#possible-future-features)
  - [Scripts for Editing and QC](#scripts-for-editing-and-qc)
    - [Rewriting Tools](#rewriting-tools)
    - [Note Browser](#note-browser)
    - [Git Signs](#git-signs)
  - [Scripts for Timing](#scripts-for-timing)
    - [Timing Binds](#timing-binds)
    - [Center Times](#center-times)
  - [Other Scripts](#other-scripts)
    - [Blender Export Script for After Effects Power Pin Data](#blender-export-script-for-after-effects-power-pin-data)
  - [See also](#see-also)


## AegisubChain
My biggest project. From a technical standpoint, [AegisubChain](macros/arch.AegisubChain.moon) is comparable to a virtual machine that can run (multiple) other automation scripts, while hooking into their API calls. In particular, it can intercept dialogs and prefill them with certain values, or suppress them entirely by immediately returning whaterver results it wants (which I'll call autofilling).

From an end-user standpoint, AegisubChain allows you to record and play back "pipelines" of macros (called *chains*), and only showing one dialog collecting all required values on playback. It can also create wrappers around macros that skip some dialogs or prefill some values, or turn virtually any macro action into a non-GUI macro.

Consider the following example, which records a 4-step process to make text incrementally fade from top to bottom, and later plays it back using just one script and one dialog:

https://user-images.githubusercontent.com/99741385/168145342-8e1daad6-8559-459c-9f0f-69e23e3541a1.mp4

Here's a second, simpler example which adds colors to text and runs "Blur & Glow".

https://user-images.githubusercontent.com/99741385/168145566-4ef2dbbd-8afe-4e6c-8055-ae0beb0c69b4.mp4

Other, simpler uses include turning simple actions like "Open a script; Click a button" into a non-GUI macro. For example, it could allow one to have (instant) key bindings for NecrosCopy's Copy Text or Copy Tags.

### Basic usage
- Use "Record Next Macro in Chain" to begin recording a chain, and select what macro you'd like to run.
- Use the macro's dialogs as you normally would, but pay attention to only change values in fields that are actually relevant
- Continue by recording the next macro in your chain, but don't change the selection or any other settings like video position between finishing the last macro and recording the next. (More precisely, you can of course change them, but know that AegisubChain won't notice the changes. So changing the video position is fine if none of the scripts from that point on use the video position. Changing the selection is only a good idea if you know exactly what you're doing - see below for more details)
- When you're done, run "Save Chain". In the dialog, you'll see a list of all dialogs that have been opened throughout, and, for each of them, a list of all fields that were changed in this dialog. For each field, you can choose if you want the field to always be filled with this value when running the chain (i.e. "Constant"), or if you want to type in its value when running the chain (i.e. "Set by User"). You can also set the default (or constant, if you chose "Constant") value for this field, as well as the field's label in the dialog shown when running the chain.
- You can do the same for buttons: "Constant" will always use the chosen button to close the respective dialog. "Set by User" will offer a drop-down menu when running the chain.
- Finally, set the name for your chain in the top left and save it.
- Then, reload your automation scripts. Your chain will appear under "AegisubChain Chains" (unless configured otherwise).

### Detailed Documentation
The above should work for most simple purposes. The following will be helpful to understand more exactly what AegisubChain can and can't do, and how to make it work in more tricky cases.

#### Script Registration and Execution
When it first needs them, AegisubChain will scan for lua or moonscript files in its path (which is configurable, but defaults to Aegisub's auto-load path), and run them while intercepting calls to `aegisub.register_macro`. Just as happens internally in Aegisub, each script will be loaded once, and its captured variables and global variables will persist throughout - until automation scripts are reloaded. Thus, each script will have a global state that transcends chains, but is entirely separate from the state of the script that was loaded directly by Aegisub.

AegisubChain tries its best to separate the environments of the scripts it loads from each other. It does so by keeping track of which global variables were created by which scripts, and swapping them back and forth when switching between scripts. See the comments in [the script](macros/arch.AegisubChain.moon) for more detailed information.

#### Recording Process
When recording a macro, AegisubChain will intercept each call to `aegisub.dialog.display` and show the same dialog itself. It will then record all the fields (where "fields" means any editable part of a dialog, including dropdowns and checkboxes) whose values have been changed (i.e. whose values differ from whatever their values where when the dialog was first shown). It will also record which button was pressed.

If the option "Show dummy dialogs first" is enabled when recording a macro, then each dialog that that macro shows will be shown twice. The first dialog is used only by AegisubChain, and it's where it will detect what fields have been changed. The second dialog's values are passed on to the macro without any sort of recording. This is useful when the user wants to mark certain values as "changed", but doesn't actually want to change them in this specific iteration of running the macro.

Apart from the macro names themselves, this is also the only thing that AegisubChain will record. It will not record any changes in selection, video position, or any changes you make to the subtitles in between recording steps.

A dialog field is described by its internal `name` field in the dialog definition table (and not by any other value like its position in the window).

AegisubChain will record the dialogs that appear by their order of appearance (as opposed to any intrinsic feature of the dialog). Whatever dialog appeared first when running a macro will be assumed to always be the first dialog to be shown when running this macro.

When saving a chain, it will allow you to, for each changed field and each button, configure how AegisubChain should handle it. The defining setting is the "Value Mode" dropdown to the very right:
- If a field's mode is set to "Exclude", it will be ignored when saving the chain (i.e. it will be treated as if it had never been changed by the user). If a button's mode is set to "Exclude", its respective dialog will be skipped by the chain, *as if it had never appeared*. (Which for example means that, if this is applied to the first dialog in a macro, from now on the second dialog will be treated as if it was the first.)
- If a field's mode is set to "Constant", it will be autofilled with whatever value is entered in its corresponding field in the save dialog (which in turn defaults to what the user entered when recording). If a button's mode is set to "Constant", the dialog will always be closed by pressing the button selected in the respective dropdown.
- If a field's mode is set to "Set by User", the user will be prompted to enter that field's value at the beginning of the chain's playback, with the default value of that field being whatever is entered in the corresponding field in the save dialog. The user can also set a label for this field, which will appear in front of said field in the playback dialog. If a button's mode is set to "Set by User", the user will be offered a drop-down menu in a similar manner to select what button to close the dialog with.

Furthermore, there are two additional modes for buttons (which actually affect their entire respective dialogs).
- The option "Raw Passthrough" will *not* autofill any values in said dialog, and instead show this dialog to the user without any modifications when running the chain. For example, this can be useful for info dialogs like "XYZ lines changed".
- The option "Passthrough with defaults" will also *not* autofill any values in said dialog, and show the dialog to the user, however it will *prefill* some fields with whatever values have been chosen for them - either in "Constant" mode or in "Set by User" mode. (The usefulness of the latter mode is debatable, as the same field would be shown at two occasions now, but it is allowed.)

These two options both translate to the same underlying mode `passthrough`. "Raw Passthrough" simply applies "Passthrough with defaults", but sets all fields to "Exclude" first.

When saving a chain, AegisubChain will automatically compute the layout for the dialog that will be shown on chain playback: There's one row for each dialog (which has the mode "Set by User" set somewhere), and the fields are sorted in their respective rows by where they appeared in the dialog they correspond to. This dialog layout can be changed by editing the chain (either in the config file or by exporting and importing): It essentially follows the format of a dialog control table, although it will be stretched horizontally by AegisubChain to also add in the labels.

Finally, the save dialog also offers to choose a "Selection mode" for each script. This setting controls what lines will be selected (and what will be the active line) after running a step in the chain (and thus which selection and active line will be fed to the next chain):
- The default option "Macro's Selection" will select whatever selection the macro returned. If none is returned, it will apply "Previous Selection" as a fallback.
- "Previous Selection" will select whatever lines were selected before running the step. (More precisely, it will take the previous selection and shift indices to account for lines being inserted or deleted).
- "Changed lines" will select all lines which the script changed or inserted.

When playing back a chain, AegisubChain will first show a dialog prompting for the fields it has been configured to ask the user for. The dialog control tables are read from the config. If no fields or buttons have been set to "Set by User", no dialog will be shown.

AegisubChain will proceed to run each of the macros in the chain. In each step, for the i-th dialog that opens, it will fill its fields (again going by the `name` field) with the values obtained for the i-th dialog (including constant values) in the chain definition. If the button's mode is `passthrough`, it will proceed to show it to the user - otherwise it will automatically "close" the dialog using the specified button. Once the script finishes, it will track how the selection changed (this is done by passing a dummy `subtitles` object to the script, which has a metatable set that logs all relevant actions and forwards them to the actual `subtitles` object), and compute the selection that should be returned or passed on to the next step's macro.

#### Chain config format
AegisubChain used DependencyControl's ConfigHandler to store its configuration and its chains in json format. Refer to the script and its configuration dialog for documentation of the global configuration options. The following explains the chain format:
- A chain is an array of steps

A step is a table containing one of the following fields:
- It **must** contain a field `script`, which is the name of the script as registered in Aegisub.
- It **should** contain a field `select`, whose value is one of `macro`, `changed`, or `keep`, and which controls what lines will be selected after running this step. The default value is `macro`.
- It **must** contain a field `dialogs`, which is an array of dialog info tables.

A dialog info table is a table that can contain the following fields:
- It **can** contain a field `fields`, which is a table containing field info tables for various field names. A field info table is a table that can contain the following fields:
    - It **should** contain a field `mode`, which controls how this field is autofilled or prefilled in dialogs. Possible values are `const` and `user` (the default).
    - If the mode is `const` **should** contain a field `value`, which sets the value the field should be autofilled with.
    - If the mode is `user`, it **must** contain fields `class`, `x`, `y`, `width`, `height`, `items` and **should** contain fields `label`, `hint`, `text`, `value`, `min`, `max`, `step` whenever applicable (refer to the documentation of Aegisub's dialog control tables). These values control how the respective field is shown in the chain playback dialog.
    - If the mode is `user`, it **must** contain a field `flabel` determining the label for that field in the chain playback dialog.
- It **must** contain a field `button`, which contains a button info table which specifies how this dialog should be handled. This table has the same format as a field info table, but without a `class` field, and with the additional allowed value `passthrough` for the mode.

### Limitations and Workarounds
This section lists some consequences of what has been described above, and how to possibly work around them. Some of these are obvious, but could still be interesting.
- It bears repeating that **AegisubChain will not pick up on any changes made to subtitles or the selection between recording steps**. Every single step of the chain needs to be run as a macro, with the exception of the user being able to choose between selection modes. Macros like Selectricks or Selegator can be used for more control over selection.
- AegisubChain recognizes dialog fields by their internal `name` fields, and recognized dialogs by the number of dialogs that appeared before them. Thus, it will not work well with scripts which only sometimes show dialogs, or with scripts which generate them dynamically.
- AegisubChain does not attempt to find out *how* a dialog field was changed. For example, when running HYDRA in full mode on the text `Test`, and entering `Tes*t` in "Tag position" to apply tags to the last character, AegisubChain will just interpret this as setting this field to `Tes*t`, and will thus always prefill or autofill that exact value, no matter what the line's text is. Settings like the "Presets" next to "Text position" should be used instead.
- AegisubChain will fill a field that is not recorded in the chain's config with its default value. This can become problematic when default values are not constant, such as when they're set to the value entered during the last run. For example, Hyperdimensional Relocator's default repositioning mode on its first run is `clip2frz`. On subsequent runs, its default mode is whatever mode was last used. Thus, recording a chain with `clip2frz` would by default always use the mode that was last selected, instead of using `clip2frz`.

    To avoid this issue, the option "Show dummy dialogs first" can be used when recording the chain: By changing the mode to *anything* for the first dialog, and then running Relocator with `clip2frz` for the second dialog, the intended effect is achieved and AegisubChain will pick up the field as changed. Then, in the save dialog, the constant value for the mode can be set back to `clip2frz`.
- As of now, AegisubChain does not treat DependencyControl any different than any other module. Thus, instead of intercepting the macro registrations with DependencyControl, it intercepts the actual call to `aegisub.register_macro` which DependencyControl performs after that. This means that macros will be listed in AegisubChain with the same name they're registered with in Aegisub, which will include any custom folders made by DependencyControl's Macro Configuration.

    This makes chains less portable, as they'll depend on the macro configuration of the user playing them. However, preventing this would mean intercepting calls to DependencyControl, which loses some of the script's universality. So, for now, editing the macro names in the chain's definition is the only way to fix this.

    A possible alternative solution would be making a third-party tool that can adjust a chain to any user's Macro Configuration (or include an option for such a filter when importing and exporting macros).

- As of now, chains cannot be edited after saving them, and chain playback dialogs can't be customized when saving chains. For now, editing the chain's config (either by editing the config file or by exporting and importing) is the only way to customize them.

### Compatibility
This could be interesting for people trying to write Aegisub scripts that work well with AegisubChain. In order of importance:
- Modules need to use the modern lua convention for modules (i.e. returning a table containing all its function, instead of just exporting them) to work well. Any modules that don't follow this need to be treated individually by AegisubChain.
- Don't change global variables that are present by default, and don't change the entries of any imported modules
- Make your dialogs and their field names as predictable as possible
- Don't do any other forbidden things like
    - Changing the `aegisub` variable
    - Doing type checks on the subtitles object obtained from Aegisub, or touching its metatables.

  I'm the only one allowed to do those.

#### API
In case you need to know if your script is being run by AegisubChain, here's a list of global variables which exist in this case:
- `_ac_present`: True if your script was loaded by AegisubChain.
- `_ac_version`: AegisubChain's version
- `_ac_config`: AegisubChain's config handler. `_ac_config.c` is its configuration table. Please be nice and don't break it.
- `_ac_aegisub`: The real aegisub object.

Any other global variables are unstable and could change at any point in time.

### Possible future features
Some things I might implement in the future, if I have the time and am sufficiently satisfied with the design:
- Paging for the "Save Chain" and "Manage Chains" dialogs. This will definitely be necessary for more complex chains, but it's a pain to build, which is why I haven't done it yet.
- Some form of Lua eval in fields. This would remove most of the inflexibility the script has right now. Simple applications would be converting values before entering them in dialogs, or entering the same value in two different fields. More complex applications could be something like making dialog frontends for LuaInterpret scripts by filling some of the constant definitions with values that were picked in a dialog (e.g. by evaluation expressions surrounded by `!` as in karaoke templates.).

    The most difficult part here is finding an API which is both flexible  and does not involve too much boilerplate code in these expressions. (Ideally they could not only access the results of the playback dialog, but also the current dialog's info, as well as subtitles both before running the chain and at the current point in time.) This is why I've been holding off on this feature for now.
- Adding more options to edit chains via dialogs. I'm also a bit hesitant here, since making every single aspect editable will make editing them very tedious. Drawing the line at what should be changeable in dialogs and what shouldn't has been hard. A standalone application to edit chains could be a good idea, but it would involve a lot more work.
- To help with the fact that every step of the chain has to happen in a macro, it could be helpful to make a script containing a collection of "companion" macros for AegisubChain that allow things like managing the selection, video and audio position (this would be simulated instead) or the current subtitle line. All of these are actions which would often just be done manually, so there aren't too many scripts for them.
- Some online place to find or share recorded chains.

## Scripts for Editing and QC
These scripts try to provide shortcuts for actions in editing or in applying QC notes. They're tailored to the processes and conventions in the group I'm working in, but maybe they'll also be useful for other people.

### Rewriting Tools
This script is for whenever you're editing subtitles but want to also preserve the original line in the same subtitle line. It wraps the previous line in braces, but also escapes any styling tags it contains. Conversely, it can revert to any of the deactivated lines with one hotkey.

https://user-images.githubusercontent.com/99741385/168145699-4076a81f-81f7-4ce7-baf5-6ac06f4a6cdb.mp4

[The script](macros/arch.RWTools.lua) contains more detailed documentation. Note, however, that this script is intended to be used more as a companion for working with the note file, instead of to replace it. Any text not matching the format of a timestamped note is skipped, so users should always double-check with the original note document.

### Note Browser
Takes a list of subtitle QC notes (or really any collection of timestamped notes), each starting with a timestamp, and provides shortcuts for jumping to lines with notes, as well as a way to mark lines containing notes. If configured to, it will also show the notes themselves in Aegisub.

https://user-images.githubusercontent.com/99741385/168145809-91e5f1ba-2a12-4003-8366-1bf8def09ab3.mp4

Documentation is included in [the script](macros/arch.NoteBrowser.moon).

### Git Signs
**This script is still work in progress. It's stable, but there are still some features to be added.**

If the subtitle file is part of a git repository, this script can parse the git diff relative to some other commit (or any ref, really) and highlight the lines which were marked as changed. This can be useful when reviewing edits made by another member, or when proofreading one's edits before pushing.

## Scripts for Timing
These scripts aren't in DependencyControl, since I can imagine that they'll mostly be useful to me.

### Timing Binds
A couple of shortcuts I use for more efficient timing, especially when timing to video. None of this is groundbreaking, but most of these were things I didn't find elsewhere, at least in this exact form.
- Snapping start or end to video **while keeping lines joined**
- A version of [The0x539's JoinPrevious](https://github.com/The0x539/Aegisub-Scripts) that uses the current audio selection instead of the line's time
- A version of Aegisub's "Shift selection so that the active line starts at the video frame" that shifts by frames instead of by milliseconds.

For reference, I usually time without TPP and without autocommit, but with "Go to next line on commit" on. I use this script together with [PhosCity's](https://github.com/PhosCity) Bidirectional Snapping

### Center Times
Chooses the centisecond timings for subtitle lines in their frames in a way that prevents or minimizes frame timing errors (whenever possible) when shifting subtitles by time (e.g. when syncing files with [SubKt](https://github.com/Myaamori/SubKt)). The [script file](macros/arch.CenterTimes.lua) has a very detailed explanation.

## Other Scripts

### Blender Export Script for After Effects Power Pin Data
This script (download it [here](https://raw.githubusercontent.com/arch1t3cht/Aegisub-Scripts/main/scripts/powerpin_export.py)) exports Blender plane tracks in After Effects Power Pin format, in the same way as Mocha does for its perspective tracks. This allows using Blender plane tracks with [Aegisub-Perspective-Motion](https://github.com/Zahuczky/Zahuczkys-Aegisub-Scripts/tree/main). Exporting individual tracking markers in Power Pin format (this can be useful when using Perspective-Motion for ordinary position tracking) might be added at some point in the future.

For a guide on how to use this script and planar tracking in Blender, see
- [The tutorial for ordinary tracking in Blender](https://subarashii-no-fansub.github.io/Subbing-Tutorial/Tracking-Motion/). This script is installed and used in exactly the same way.
- [This video tutorial explaining plane tracking](https://www.youtube.com/watch?v=Z8SwnRN701w)
- [Blender's documentation on plane tracks](https://docs.blender.org/manual/en/latest/movie_clip/tracking/clip/editing/track.html#create-plane-track)

Note in particular that the individual markers don't need to be set to "Perspective". They can be set to just "Location" or whatever else works best for tracking. The script will instead export the parameters of the plane track generated by blender afterwards.

## See also
Or "Other Stuff I Worked on that Might be Interesting".
- Zahuczky's [Aegisub-Perspective-Motion](https://github.com/Zahuczky/Zahuczkys-Aegisub-Scripts/tree/main) (worked on some of the math in this)
- [ass.nvim](https://github.com/arch1t3cht/ass.nvim): A neovim 5.0 plugin for `.ass` subtitles. Its most important feature is a split window editing mode to efficiently copy new dialog (say, a translation) to a timed subtitle file.

---
Thanks to [PhosCity](https://github.com/PhosCity) for testing almost all of these scripts.
