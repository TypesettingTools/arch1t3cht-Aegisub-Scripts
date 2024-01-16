# Aegisub-Scripts
My automation scripts for Aegisub. In my opinion, the coolest thing here is AegisubChain, but I also have some other useful scripts for editing and timing.

- [Aegisub-Scripts](#aegisub-scripts)
  - [Installation](#installation)
  - [Guides](#guides)
  - [AegisubChain](#aegisubchain)
  - [Scripts for Typesetting](#scripts-for-typesetting)
    - [Focus Lines](#focus-lines)
    - [PerspectiveMotion](#perspectivemotion)
    - [Derive Perspective Track](#derive-perspective-track)
    - [Resample Perspective](#resample-perspective)
    - [Perspective](#perspective)
  - [Scripts for Editing and QC](#scripts-for-editing-and-qc)
    - [Rewriting Tools](#rewriting-tools)
    - [Note Browser](#note-browser)
    - [Git Signs](#git-signs)
  - [Scripts for Timing](#scripts-for-timing)
    - [Timing Binds](#timing-binds)
    - [Center Times](#center-times)
  - [Other Scripts](#other-scripts)
    - [Convert Folds](#convert-folds)
    - [Blender Export Scripts for After Effects Tracking Data](#blender-export-scripts-for-after-effects-tracking-data)
  - [See also](#see-also)

## Installation
Most scripts I make use [DependencyControl](https://github.com/TypesettingTools/DependencyControl) for versioning and dependency management, and can be installed from within Aegisub using DependencyControl's Install Script function.
Some of them strictly require it to be installed.

## Guides
I wrote a [guide](doc/templaters.md) or primer on karaoke templates that aims to get people far enough to start reading documentation without too much pain. It also contains a few tables for converting templates between the three major templaters.

I also wrote up the mathematics involved in the various perspective scripts [here](doc/perspective_math.md).

## AegisubChain
My biggest project. From a technical standpoint, [AegisubChain](macros/arch.AegisubChain.moon) is comparable to a virtual machine that can run (multiple) other automation scripts, while hooking into their API calls. In particular, it can intercept dialogs and prefill them with certain values, or suppress them entirely by immediately returning whatever results it wants.

From an end-user standpoint, AegisubChain allows you to record and play back "pipelines" of macros (called *chains*), and only showing one dialog collecting all required values on playback. It can also create wrappers around macros that skip some dialogs or prefill some values, or turn virtually any macro action into a non-GUI macro.

Consider the following example, which records a 4-step process to make text incrementally fade from top to bottom, and later plays it back using just one script and one dialog:

https://user-images.githubusercontent.com/99741385/202811305-41d3557c-952b-408e-9a5d-113b66efccc7.mp4

Here's a second, simpler example which adds colors to text and runs "Blur & Glow".

https://user-images.githubusercontent.com/99741385/168145566-4ef2dbbd-8afe-4e6c-8055-ae0beb0c69b4.mp4

Other, simpler uses include turning simple actions like "Open a script; Click a button" into a non-GUI macro. For example, it could allow one to have (instant) key bindings for NecrosCopy's Copy Text or Copy Tags.

Detailed documentation is [here](doc/aegisubchain.md).

## Scripts for Typesetting

### Focus Lines
A script that generates moving focus lines, tweakable with a few parameters.

**WARNING**: This script is dumb and horribly inefficient. I made it when I didn't know what I was doing. You can still use it, but make sure to clip the generated shapes to the frame area (plus some padding to account for the blur) and apply a Shape Clipper. Also be careful not to use too many layers.

https://user-images.githubusercontent.com/99741385/180628464-2f970f02-b134-474b-b4b6-a998c22fcf75.mp4

### PerspectiveMotion
An analogue to [Aegisub-Motion](https://github.com/TypesettingTools/Aegisub-Motion) that can handle perspective motion. Unlike the "After Effects Transform Data" that Aegisub-Motion needs, this tool requires an "After Effects Power Pin" track, which you can export directly from Mocha, or using [Akatsumekusa's plugin](https://github.com/Akatmks/Akatsumekusa-Aegisub-Scripts) for Blender.

### Derive Perspective Track
More or less an analogue to [The0x539's DeriveTrack](https://github.com/The0x539/Aegisub-Scripts/blob/trunk/doc/0x.DeriveTrack.md) for perspective tracks. It turns the outer quads of a set of lines (as set using the perspective tool in [my Aegisub fork](https://github.com/arch1t3cht/Aegisub)) into a PowerPin track that can be used with [Aegisub Perspective-Motion](#perspective-motion). Alternatively, it can derive a track directly from the override tags. This way, manual perspective tracks can be made and applied to multiple different lines directly in Aegisub, without having to go through Mocha or Blender.

### Resample Perspective
Run this [script](macros/arch.Resample.moon) after Aegisub's "Resample Resolution" to fix perspective rotations in the selected lines that were broken by resampling. If you're resampling to a different aspect ratio, select "Stretch" in Aegisub's resampler.

There exist [multiple](https://github.com/TypesettingTools/CoffeeFlux-Aegisub-Scripts#scale-rotation-tags) [scripts](https://github.com/petzku/Aegisub-Scripts#resample) like this already, but this script uses a different approach to ensure exact accuracy. However, it still has a few limitations:
- It still requires all individual events to have one consistent perspective and will not work if perspective tags change mid-line. In these cases you'll need to split the lines manually first.
- It does not take position shifts due to large `\shad` values into account. If these become significant, you need to split the text from the shadow, adjust the positions, and resample them separately.
- Shapes might need to be `\an7` to be positioned properly.

### Perspective
I have a library [`arch.Perspective.moon`](modules/arch/Perspective.moon) that allows applying perspective transformations to subtitle lines. It abstracts away almost all of the tag wrangling and allows you to just work in terms of the quads you want to transform things from or to. All my perspective-related scripts use this library.

Ordinary single-line perspective handling has been added directly to [my Aegisub fork](https://github.com/arch1t3cht/Aegisub). One day I might still write a script to cover some more advanced usage (e.g. a "perspective Recalculator"), but this is very low priority.

For the math involved in these functions, see either the comments in the source code [this write-up](doc/perspective_math.md).

## Scripts for Editing and QC
These scripts try to provide shortcuts for actions in editing or in applying QC notes. They're tailored to the processes and conventions in the group I'm working in, but maybe they'll also be useful for other people.

### Rewriting Tools
This script is for whenever you're editing subtitles but want to also preserve the original line in the same subtitle line. It wraps the previous line in braces, but also escapes any styling tags it contains. Conversely, it can revert to any of the deactivated lines with one hotkey.

https://user-images.githubusercontent.com/99741385/168145699-4076a81f-81f7-4ce7-baf5-6ac06f4a6cdb.mp4

[The script](macros/arch.RWTools.lua) contains more detailed documentation.

### Note Browser
Takes a list of subtitle QC notes (or really any collection of timestamped notes), each starting with a timestamp, and provides shortcuts for jumping to lines with notes, as well as a way to mark lines containing notes. If configured to, it will also show the notes themselves in Aegisub.

https://user-images.githubusercontent.com/99741385/168145809-91e5f1ba-2a12-4003-8366-1bf8def09ab3.mp4

Documentation is included in [the script](macros/arch.NoteBrowser.moon). Note, however, that this script is intended to be used more as a companion for working with the note file, instead of to replace it. Any text not matching the format of a timestamped note is skipped, so users should always double-check with the original note document.

### Git Signs
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

### Convert Folds
This script converts the line folds added in [my Aegisub fork](https://arch1t3cht/Aegisub) from the old storage format that used the Project Properties to the new extradata-based format.
To use it, either
- copy the "Line Folds:" line in your `.ass` file, open this file in Aegisub, and paste this into the dialog of the "Convert Folds" script, or
- click the "From File" button to automatically read this line from the subtitle file. This only works if the file is saved on your disk.
This will work on any version of Aegisub (i.e. an Aegisub version using extradata folds will be able to load folds from the resulting file), but in order for the folds to be displayed inside of Aegisub, you obviously need a build that supports extradata folds.

### Blender Export Scripts for After Effects Tracking Data
You might be looking for my patched version of the After Effects Blender export script that adds the ability to export Power Pin data. This script has been superseded by Akatsumekusa's version, which is an almost complete rewrite with more features and a more user-friendly GUI. Go [here](https://github.com/Akatmks/Akatsumekusa-Aegisub-Scripts) to download this version.

## See also
Or "Other Stuff I Worked on that Might be Interesting".
- [ass.nvim](https://github.com/arch1t3cht/ass.nvim): A neovim 5.0 plugin for `.ass` subtitles. Its most important feature is a split window editing mode to efficiently copy new dialog (say, a translation) to a timed subtitle file.
- My [Aegisub fork](https://github.com/arch1t3cht/Aegisub) with some new features like folding and other audio/video sources.

---
Thanks to [PhosCity](https://github.com/PhosCity) for testing many of my early scripts.
