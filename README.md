# Aegisub-Scripts
My automation scripts for Aegisub. You're probably here for AegisubChain, but there are also some other useful scripts for editing and timing in here.

- [Aegisub-Scripts](#aegisub-scripts)
  - [Guides](#guides)
  - [AegisubChain](#aegisubchain)
  - [Scripts for Typesetting](#scripts-for-typesetting)
    - [Focus Lines](#focus-lines)
    - [Perspective (WIP)](#perspective-wip)
  - [Scripts for Editing and QC](#scripts-for-editing-and-qc)
    - [Rewriting Tools](#rewriting-tools)
    - [Note Browser](#note-browser)
    - [Git Signs](#git-signs)
  - [Scripts for Timing](#scripts-for-timing)
    - [Timing Binds](#timing-binds)
    - [Center Times](#center-times)
  - [Other Scripts](#other-scripts)
    - [Blender Export Script for After Effects Power Pin Data](#blender-export-script-for-after-effects-power-pin-data)
    - [Modified Export Script for After Effects Transform Data](#modified-export-script-for-after-effects-transform-data)
  - [See also](#see-also)

## Guides
I wrote a [guide](doc/templaters.md) or primer on karaoke templates that aims to get people far enough to start reading documentation without too much pain. It also contains a few tables for converting templates between the three major templaters.

## AegisubChain
My biggest project. From a technical standpoint, [AegisubChain](macros/arch.AegisubChain.moon) is comparable to a virtual machine that can run (multiple) other automation scripts, while hooking into their API calls. In particular, it can intercept dialogs and prefill them with certain values, or suppress them entirely by immediately returning whaterver results it wants (which I'll call autofilling).

From an end-user standpoint, AegisubChain allows you to record and play back "pipelines" of macros (called *chains*), and only showing one dialog collecting all required values on playback. It can also create wrappers around macros that skip some dialogs or prefill some values, or turn virtually any macro action into a non-GUI macro.

Consider the following example, which records a 4-step process to make text incrementally fade from top to bottom, and later plays it back using just one script and one dialog:

https://user-images.githubusercontent.com/99741385/168145342-8e1daad6-8559-459c-9f0f-69e23e3541a1.mp4

Here's a second, simpler example which adds colors to text and runs "Blur & Glow".

https://user-images.githubusercontent.com/99741385/168145566-4ef2dbbd-8afe-4e6c-8055-ae0beb0c69b4.mp4

Other, simpler uses include turning simple actions like "Open a script; Click a button" into a non-GUI macro. For example, it could allow one to have (instant) key bindings for NecrosCopy's Copy Text or Copy Tags.

Detailed documentation is [here](doc/aegisubchain.md).

## Scripts for Typesetting

### Focus Lines
A script that generates moving focus lines, tweakable with a few parameters.

### Perspective (WIP)
This is still very work in progress, but I started working on extracting the math I used in [Aegisub-Perspective-Motion](https://github.com/Zahuczky/Zahuczkys-Aegisub-Scripts/tree/main) into Lua libraries and an improved perspective script. The core functions are implemented [here](modules/arch/Perspective.moon) already, together with some general-purpose [linear algebra functions](modules/arch/Math.moon).

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
- Snapping start or end to video **while keeping lines joined**.
- A version of [The0x539's JoinPrevious](https://github.com/The0x539/Aegisub-Scripts) that uses the current audio selection instead of the line's commited time. That is, it works without needing to commit the change if autocommit is disabled.
- A version of Aegisub's "Shift selection so that the active line starts at the video frame" that shifts by frames instead of by milliseconds.
- A version of the above macro that shifts all lines whose starting time is larger than or equal to the current line together with the selection. This is useful when retiming subtitles after scenes have been cut out of or added to the video.

For reference, I usually time without TPP and without autocommit, but with "Go to next line on commit" on. I use this script together with [PhosCity's](https://github.com/PhosCity) Bidirectional Snapping

### Center Times
Chooses the centisecond timings for subtitle lines in their frames in a way that prevents or minimizes frame timing errors (whenever possible) when shifting subtitles by time (e.g. when syncing files with [SubKt](https://github.com/Myaamori/SubKt)). The [script file](macros/arch.CenterTimes.lua) has a very detailed explanation.

## Other Scripts

### Blender Export Script for After Effects Power Pin Data
This script (download it [here](https://raw.githubusercontent.com/arch1t3cht/Aegisub-Scripts/main/scripts/powerpin-export.py), see the first guide linked below for how to install and use it) exports Blender plane tracks or sample tracks in After Effects Power Pin format, in the same way as Mocha does for its perspective tracks. This allows using Blender tracks with [Aegisub-Perspective-Motion](https://github.com/Zahuczky/Zahuczkys-Aegisub-Scripts/tree/main).

For a guide on how to use this script and planar tracking in Blender, see
- [The tutorial for ordinary tracking in Blender](https://subarashii-no-fansub.github.io/Subbing-Tutorial/Tracking-Motion/). This script is installed and used in exactly the same way.
- [This video tutorial explaining plane tracking](https://www.youtube.com/watch?v=Z8SwnRN701w)
- [Blender's documentation on plane tracks](https://docs.blender.org/manual/en/latest/movie_clip/tracking/clip/editing/track.html#create-plane-track)

Note in particular that for exporting plane tracks, the individual markers don't need to be set to "Perspective". They can be set to just "Location" or whatever else works best for tracking. The script will instead export the parameters of the plane track generated by blender afterwards.

Exporting individual sample tracks is also possible, but far less accurate due to the nature of the track.

### Modified Export Script for After Effects Transform Data
The [scripts](scripts/) folder also contains a [modified version](https://raw.githubusercontent.com/arch1t3cht/Aegisub-Scripts/main/scripts/aae-export.py) of the existing script [aae-export.py](https://raw.githubusercontent.com/Subarashii-no-Fansub/AAE-Export/master/aae-export.py) that also exports plane tracks to transform data.

## See also
Or "Other Stuff I Worked on that Might be Interesting".
- Zahuczky's [Aegisub-Perspective-Motion](https://github.com/Zahuczky/Zahuczkys-Aegisub-Scripts/tree/main) (worked on the tracking math in this)
- [ass.nvim](https://github.com/arch1t3cht/ass.nvim): A neovim 5.0 plugin for `.ass` subtitles. Its most important feature is a split window editing mode to efficiently copy new dialog (say, a translation) to a timed subtitle file.

---
Thanks to [PhosCity](https://github.com/PhosCity) for testing almost all of these scripts.
