# PerspectiveMotion
- [PerspectiveMotion](#perspectivemotion)
  - [Introduction](#introduction)
  - [Basic usage](#basic-usage)
  - [Options](#options)

## Introduction

An analogue to [Aegisub-Motion](https://github.com/TypesettingTools/Aegisub-Motion)
able to handle perspective motion. Unlike the "After Effects Transform Data" needed by Aegisub-Motion,
this tool requires an "After Effects Power Pin" track, which you can export directly from Mocha,
or with the help of [Akatsumekusa's plugin](https://github.com/Akatmks/Akatsumekusa-Aegisub-Scripts) from Blender.

## Basic usage

First you’ll need to motion track your object to obtain the Power Pin data.
The details of how to perform motion tracking are out of scope here,
but when using Blender you might want to take a look at the examples from
[Akatsumekusa’s plugin docs](https://github.com/Akatmks/Akatsumekusa-Aegisub-Scripts/blob/master/docs/aae-export-tutorial.md#tutorial-4-tracking-perspective).
While currently not part of those examples, you might also find plane tracks
useful for more complex scenarios; check Blender documentation for details.

The most important part of the exported data are the positions of each of the four quad corners per frame.
Per corner there’s one section in the exported data, each section starting with a line like:
```
Effects CC Power Pin #1 CC Power Pin-0002
```

With `0002` denoting the upper left, `0003` the upper right, `0004` the lower left and `0005` the lower right corner.
You might need to fix up the orientation after exporting to ensure the above mapping holds.
Crucially up/down, left/right here is considered from the point of view
of the tracked object itself **not** in regular screen space!
Put another way, while mapping corner ids, assume the scene is rotated such that the tracked object face
directly points at the camera, its text baseline is horizontal and glyphs upright.

Here are some examples

![perspectivemotion_pinorder_example01.png](https://github.com/user-attachments/assets/5c341658-7709-45fc-ad84-f02cbee382c1)
![perspectivemotion_pinorder_example02.png](https://github.com/user-attachments/assets/fa741f35-0dd7-4d57-8347-f6ac97363a27)
![perspectivemotion_pinorder_example03.png](https://github.com/user-attachments/assets/895fbedd-0961-450e-9aca-a601390eddda)

If reordering is needed it suffices to just change the number in the opening line of each segment, the order of sections inside the exported data stream does not matter.

Now just select the template line which you want to transform, make sure its start and end time match the motion-tracked frames, copy Power Pin data into the clipboard and run the script.

## Options

- `Apply perspective`: if checked it’s assumed the line this is being applied to does not yet have any
   perspective transformations and an appropriate transformation is automatically derived from the ingested
   Power Pin data at the given frame. Note this automatically generated transform may not be scaled
   exactly as a tight fit of the Power Pin quad.  
   If unchecked it’s assumed the line already is transformed and scaled appropriately for its frame
   and all transformations are applied relative to the existing line.  
   Usually this will be (un)checked automatically when opening the dialogue depending on whether
   there already are any perspective transformation tags.

- `Relative to frame`: specifies which motion tracking frame the reference line corresponds to.
   Always numbered starting from one and counting each successive motion tracking frame regardless
   of which frame number are listed in motion tracking data.

- `\org mode`: the same as for the built-in perspective tool
