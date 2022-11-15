# Miscellaneous Tricks with Karaoke Templaters
- [Miscellaneous Tricks with Karaoke Templaters](#miscellaneous-tricks-with-karaoke-templaters)
  - [Text Moving Along a Path](#text-moving-along-a-path)
    - [Breakdown](#breakdown)
    - [Result](#result)
  - [Text Wobbling Along with a Wave](#text-wobbling-along-with-a-wave)
    - [Breakdown](#breakdown-1)
  - [Clip Matching Various Transform Tags](#clip-matching-various-transform-tags)
  - [Text Breaking Effect](#text-breaking-effect)
    - [Breakdown](#breakdown-2)

This page collects various templates I wrote for purposes other than song styling to illustrate how karaoke templaters can also be useful for typesetting and other automation related to .ass subtitles.
Hopefully, they will be instructive to other people looking to learn how to use templaters for more advanced typesetting.
Note that most of these templates started out as rather proof-of-concept, and are thus not as nicely structured as they could be.
Of course, many of these templates could also be full-fledged automation scripts, but writing them as templates makes it a lot simpler to tweak them to look exactly how you want them to.

All templates in this document use [The0x539's Templater](https://github.com/The0x539/Aegisub-Scripts/blob/trunk/src/0x.KaraTemplater.moon).
Check out [my templater guide](templaters.md) if you haven't already.

## Text Moving Along a Path
This is one of the simplest but still powerful cases where templaters can already come in handy. An example is the following sign from Episode 9 of the third season of Kaguya-Sama:

https://user-images.githubusercontent.com/99741385/201791297-ab93d268-f1d8-4c05-880e-267e7c3cefd4.mp4

Here, the text moves vertically along a wave, while the camera is also slowly panning upwards. (Notice that the "bumps" in the wave form of the text move downwards as the clip progresses.)
The letters also rotate according to the direction they're currently moving towards.
We'd like to format the English translation in a similar way.
Signs like these, where we want to transform subtitles in some complex but predictable manner, are perfect for karaoke templaters.
Using some math, this case can be solved by a comparatively simple template like the following one:

```
[Script Info]
ScriptType: v4.00+
WrapStyle: 0
ScaledBorderAndShadow: yes
YCbCr Matrix: TV.709
PlayResX: 1920
PlayResY: 1080

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Default,Arial,120,&H00C96DFE,&H000000FF,&H00FFFFFF,&H00000000,0,0,0,0,100,100,0,0,1,4,0,2,10,10,10,1

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
Comment: 0,0:00:00.00,0:00:00.00,Default,,0,0,0,code once,startx = 1200; starty = 120;lheight=100;yspeed=-550;phase=3.5;ypan=190;freq=0.0075;amp=80;
Comment: 0,0:00:00.00,0:00:00.00,Default,,0,0,0,template char,!util.fbf("line", 0, 0, 1, "fbf")!
Comment: 0,0:00:00.00,0:00:00.00,Default,,0,0,0,mixin char,!set("t", (line.start_time - orgline.start_time) / 1000)!
Comment: 0,0:00:00.00,0:00:00.00,Default,,0,0,0,mixin char,!set("y", starty + t * yspeed + lheight * char.ci)!
Comment: 0,0:00:00.00,0:00:00.00,Default,,0,0,0,mixin char,!set("x", startx + amp * math.sin(phase + freq * y))!
Comment: 0,0:00:00.00,0:00:00.00,Default,,0,0,0,mixin char,!set("deriv", amp * freq * math.cos(phase + freq * y))!
Comment: 0,0:00:00.00,0:00:00.00,Default,,0,0,0,mixin char,{\b1}
Comment: 0,0:00:00.00,0:00:00.00,Default,,0,0,0,mixin char,{\an5\pos(!x!, !y + ypan * t!)}
Comment: 0,0:00:00.00,0:00:00.00,Default,,0,0,0,mixin char,{\frz!math.deg(math.atan(deriv))!}
Comment: 0,0:00:00.00,0:00:03.69,Default,,0,0,0,kara,Kara templates are OP
```

### Breakdown
We can break down the sign as follows:
- The line is written vertically, character by character.
  - Thus, we want to use a `template char`.
  - We'll start by vertically positioning each character according to its index in the line (so `char.ci`).
- The characters also move upwards linearly.
  - Thus, we use a frame-by-frame move. This is what happens in the main `template char` line.
    The first mixin following this computes the time offset of the current frame to the beginning.
  - Then, the second mixin computes the y position of each character as a constant `starty` plus a multiple of the character index `char.ci` plus a term linearly depending on the time `t`.
- The characters are positioned along a wave-like path.
  - We model this path by a sine wave.
- The characters also move along this path.
  - Thus, we want to make the $x$ position of the characters be a sine wave depending on the y position.
    This happens in the third mixin, which computes `x` as a simple general sine wave consisting of a constant summand `startx`,
    the amplitude `amp` corresponding to the horizontal extent of the wave,
    the frequency `freq` corresponding (inversely) to the vertical distance between bumps,
    and the `phase`, which controls in what part of the wave the text starts.
  - We set all these parameters (and all other ones) in the first `code once` line, and tweak them to fit the scene.
- The characters are rotated along the path.
  - We need to rotate each character so that its vertical axis points in the direction tangent to the wave.
    This calls for some calculus:
    In the fourth mixin, we compute the derivative of the wave function defined above.
    This is the inverse slope of the required tangent line (inverse because $y$ and $x$ are switched here, since the wave runs vertically).
    This is exactly the $\tan$ of the required rotation angle (since `\frz0` corresponds to the text's vertical axis being, well, vertical).
    Hence, we set the `\frz` to the $arctan$ of this derivative, converted to degrees, in the last mixin.
- The camera also slowly pans upwards (or the wave as a whole moves downwards).
  - Thus, after doing all the wave calculations, we add another summand to the y position which is linearly dependent on the time `t`.
    This happens in the sixth mixin where `\pos` is being set.
- The remaining parts are just some formatting.

### Result

https://user-images.githubusercontent.com/99741385/201794661-7794b179-24e8-482c-b462-14c3bbd9cb0b.mp4

Of course, the template could now be extended to add more formatting (a better font, blur, splitting border and fill, etc.) and/or to give different characters different colors to match the Japanese sign.

## Text Wobbling Along with a Wave
After sharing the clip above, I was challenged to write a template for the following sign in Mobile Suit Gundam- The Witch From Mercury:

https://user-images.githubusercontent.com/99741385/201795178-ff37a7c3-2192-4656-a39e-95e134c169da.mp4

The English episode title at the bottom was already in the raw video, but a translation "Episode 1" of 第1話 was missing.
With the Japanese text wobbling back and forth, signs like these seem very intimidating at first glance, but it's actually simpler to make than you'd think.
Again, what's key is that the effect is actually pretty simple to describe mathematically, so the only hard part is explaining it to the templater.

Here's the final result:

https://user-images.githubusercontent.com/99741385/201795735-b0a1fd46-a638-4c8e-8e2f-b0323a436ad2.mp4

and here's the template for it:
```
[Script Info]
ScriptType: v4.00+
WrapStyle: 0
ScaledBorderAndShadow: yes
YCbCr Matrix: TV.709
PlayResX: 1920
PlayResY: 1080

[V4+ Styles]
Style: TS,Gandhi Sans,75,&H00FFFFFF,&H000000FF,&H00000000,&H00000000,-1,0,0,0,100,100,0,0,1,0,0,5,10,10,10,1

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
Comment: 0,0:04:41.01,0:04:45.01,TS,,0,0,0,code once,yutils = require("Yutils");
Comment: 0,0:04:41.01,0:04:45.01,TS,,0,0,0,code once,fname = "A-OTF Shuei KakuGo Kin Std B"; fsize = 50; font = yutils.decode.create_font(fname, false, false, false, false, fsize, 1, 1, 0)
Comment: 0,0:04:41.01,0:04:45.01,TS,,0,0,0,code once,px=965; py=66;swidth, sheight = aegisub.video_size(); centerx = swidth / 2; centery = sheight / 2; radspeed = 200; waves = {{width=30, strength=10, delay=-2.2}, {width=30, strength = 10, delay=-1.95}, {width=40, strength=1, delay=-1.4}};fadetime=450;
Comment: 0,0:04:41.01,0:04:45.01,TS,,0,0,0,code once,function sease(val, range) return (1 - math.cos(math.pi * math.min(val / range, 1))) / 2 end
Comment: 0,0:04:41.01,0:04:45.01,TS,,0,0,0,code once,function wave(x, y, t) dist = math.sqrt((x - centerx) ^ 2 + (y - centery) ^ 2); w = 0; for i, wave in _G.ipairs(waves) do w = w + wave.strength * (1 - sease(math.abs(radspeed * (t - wave.delay) - dist), wave.width)) end return w; end
Comment: 0,0:04:41.01,0:04:45.01,TS,,0,0,0,code once,function transform(x, y, t) dist = math.sqrt((x - centerx)^2 + (y - centery)^2); w = wave(x, y, t); return (x + w * (x - centerx) / dist), (y + w * (y - centery) / dist); end
Comment: 0,0:04:41.01,0:04:45.01,TS,,0,0,0,code line,local s = orgline.styleref; lineshape = font.text_to_shape(orgline.text_stripped);
Comment: 0,0:04:41.01,0:04:45.01,TS,,0,0,0,code line,linestyle = {}; for k, v in _G.pairs(orgline.styleref) do linestyle[k] = v; end linestyle.fontname = fname; linestyle.fontsize = fsize; linestyle.bold = false;
Comment: 0,0:04:41.01,0:04:45.01,TS,,0,0,0,template line notext,!util.fbf("line", 0, 0, 1, "fbf")!
Comment: 0,0:04:41.01,0:04:45.01,TS,,0,0,0,mixin line,!set("t", (line.start_time - orgline.start_time) / 1000)!
Comment: 0,0:04:41.01,0:04:45.01,TS,,0,0,0,mixin line,!(function() w, h = aegisub.text_extents(linestyle, orgline.text_stripped); lx = px - w / 2; ly = py - h / 2 + orgline.actor; end)()!
Comment: 0,0:04:41.01,0:04:45.01,TS,,0,0,0,mixin line,{\an7\pos(!lx!,!ly!)}!relayer(orgline.layer)!
Comment: 0,0:04:41.01,0:04:45.01,TS,,0,0,0,mixin line,{\fad(255, 0, 0, !-t * 1000!, !fadetime - t * 1000!, !fadetime!, !fadetime!)!orgline.text:match("{(.-)}")!}
Comment: 0,0:04:41.01,0:04:45.01,TS,,0,0,0,mixin line,{\p1}!lineshape:gsub("([-%d.]+) +([-%d.]+)", function(x, y)  tx, ty = transform(x + lx, y + ly, t); return (tx - lx) .. " " .. (ty - ly) end)!
Comment: 2,0:04:43.30,0:04:45.01,TS,0,0,0,0,kara,{\blur0.7\c&H353430&}Episode 1
Comment: 0,0:04:43.30,0:04:45.01,TS,4,0,0,0,kara,{\blur4\c&H7D7D7D&\1a&H3A&}Episode 1
Comment: 1,0:04:43.30,0:04:45.01,TS,-2.2,0,0,0,kara,{\blur1.7\c&H339200&\1a&H50&}Episode 1
Comment: 1,0:04:43.30,0:04:45.01,TS,2,0,0,0,kara,{\blur1.7\c&H8300FF&\1a&H88&}Episode 1
```
The template is timed to episode 01 of the GJM release. Their Episode 04 also actually contains this sign.

### Breakdown

So, let's break down this effect:
- We want the text to wobble back and forth.
  This is hopeless with ordinary text rendering, so let's convert the text to a shape and work with that instead.
  This happens in the first two `code` lines, as well as the second to last one.
- The Japanese sign looks as if the text was at the bottom of a pool of water, in which a series of waves is expanding from the center, which warps the text through refraction.
  A physically accurate recreation would therefore use Snell's law to compute how the similarly refracted English text would look on the screen.
  However, this is way too complex and we can get away with a much simpler pattern:
  We simply warp the text by moving each point slightly towards or away from the center of the screen, by a distance that's controlled by circular waves that move outward over time.
  In fact, we make our lives even simpler by simply transforming each corner or control point of the text's shape this way.
  This already looks good enough in this case. If it didn't (say, if the text was much larger, and thus the control points were further apart), we could first subdivide the shape into a finer one.
- If you look very closely, you'll see that the Japanese text is actually visible at multiple different locations in some frames, just like it would be with real refraction.
  Our warped text doesn't have this property, but luckily it's not too noticable here.
- With our effect explained, let's break down the template:
  We want to match the wobbling of the Japanese text, which happens along multiple waves radially expanding outward with similar speeds.
  So, in the third `code` line, we define a list of such waves (or maybe I should call them pulses), each of which has a strength (how strongly the text is warped with this wave), a width (how long the wave takes to pass through the text) and a delay (when the wave starts to expand from the center, essentially controlling the time when it warps the text).
  We also define the speed `radspeed` with which the waves move away from the center.
- In the fifth code line, we then define this `wave`function, which given a point on the screen and a timestamp, returns how much the given point should be displaced away from the screen's center at the given point in time.
  As the waves expand outward radially, this only depends on the point's distance from the center of the screen.
  We start with a strength of 0, and, for each of the defined pulses, add on a pulse with the given width at the given point in time.
  The pulses are given by a simple sinusoidal easing function `sease`.
- The `transform` function in the last code line then performs exactly this transform with a point by computing the `wave` function at the given point and time, and returning the point displaced from the center by the corresponding amount.
- Now, we have the actual template: We start by splitting into frame-by-frame events and computing the time offset as in the last example.
- Then, since we turned this into a shape, we need to do some math with the text extents to position the text correctly and center-aligned, and to convert shape coordinates into on-screen coordinates.
  Specifically, we compute the width and height (`w` and `h`) of the text and compute `lx`, `ly` as the position the shape should have with `\an7` to be positioned at the desired position `\pos(px,py)`.
- In order to match the vertical chromatic abberation of the Japanese text, we also add add the content of the `kara` line's Actor field to the $y$ position, so that the Actor field of the different layers can be used to control the vertical offset.
- In the second to last mixin, we add a fade (time-shifted to match the frame-by-frame split) and also insert all formatting tags of the original `kara` line, so that those can be adjusted for different colors and blur.
- The last mixin line is where the magic happens. We turn on drawing mode, and run a `gsub` on the text-to-shape output (computed in the first `code line` line) that takes every pair of numbers in the shape string, converts to screen coordinates, applies the `transform` function, and converts back to shape coordinates.
  This shape is then added to the line's text. Note that the actual `template` line has the `notext` modifier, as the `Episode 1` text shouldn't be appended.

## Clip Matching Various Transform Tags
I originally wrote this template to experiment with various rotation tag resampling scripts.
It takes a rectangle and rotation tags, and computes a clip that exactly matches the resulting rotations.

![image](https://user-images.githubusercontent.com/99741385/201800548-26d0c209-508c-4f63-b74f-2983dfd842ae.png)

This isn't too impressive on its own, but I wanted to preserve it for posterity, and I did use a reduced form of it for another effect (see below).

Here's the template:
```
[Script Info]
Title: Default Aegisub file
ScriptType: v4.00+
WrapStyle: 0
ScaledBorderAndShadow: yes
YCbCr Matrix: TV.709
PlayResX: 1280
PlayResY: 720

[Aegisub Project Garbage]
Video File: ?dummy:23.976000:400:1280:720:47:163:254:

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Default,Arial,20,&H00FFFFFF,&H000000FF,&H00000000,&H00000000,0,0,0,0,100,100,0,0,1,2,2,2,10,10,10,1

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
Comment: 0,0:00:00.00,0:00:00.00,Default,,0,0,0,code once,pos = {x=720,y=360};frz=50;frx=30;fry=20;width=300;height=100
Comment: 0,0:00:10.11,0:00:10.11,Default,,0,0,0,code once,function translate_clip(clip_arr, t) newclip = {}; for i,pt in _G.ipairs(clip_arr) do newclip[i] = {x=pt.x + t.x, y=pt.y + t.y} end return newclip; end;
Comment: 0,0:00:10.11,0:00:10.11,Default,,0,0,0,code once,function write_clip(clip_arr) cliptext = ""; for i,pt in _G.ipairs(clip_arr) do if i == 1 then cliptext = cliptext .. "m" elseif i == 2 then cliptext = cliptext .. " l" end cliptext = cliptext .. " " .. pt.x .. " " .. pt.y; end return cliptext; end
Comment: 0,0:00:10.11,0:00:10.11,Default,,0,0,0,code once,function transform_clip(clip_arr, o, frz, frx, fry) fl = 312.5; newclip = {}; for i,pt in _G.ipairs(clip_arr) do t = {x=pt.x - o.x; y = pt.y - o.y}; t = {x=t.x*math.cos(-frz)-t.y*math.sin(-frz), y=t.x*math.sin(-frz)+t.y*math.cos(-frz), z=0}; t = {x=t.x, y=t.y*math.cos(-frx)-t.z*math.sin(-frx), z=t.y*math.sin(-frx)+t.z*math.cos(-frx)}; t = {x=t.x*math.cos(fry)-t.z*math.sin(fry), y=t.y, z=t.x*math.sin(fry)+t.z*math.cos(fry)};; newclip[i] = {x=o.x + fl * t.x/(t.z + fl), y=o.y + fl * t.y/(t.z+fl)} end return newclip; end;
Comment: 0,0:00:10.11,0:00:10.11,Default,,0,0,0,code once,shape = {{x=0,y=0}, {x=width,y=0}, {x=width,y=height}, {x=0,y=height}}
Comment: 0,0:00:00.00,0:00:00.00,Default,,0,0,0,template line,{\an7\pos(!pos.x!,!pos.y!)\bord0\shad0\frz!frz!\frx!frx!\fry!fry!\clip(!write_clip(transform_clip(translate_clip(shape, pos), pos, math.rad(frz), math.rad(frx), math.rad(fry)))!)\p1}!write_clip(shape)!
Comment: 0,0:00:00.00,0:00:05.00,Default,,0,0,0,kara,
```
The template is pretty self-explanatory:
We make a rectangular shape in the last `code once` line, where we represent a shape as an array of tables containing an $x$ and a $y$ coordinate each.
We have a function `write_clip` turning this into a shape string that connects all the given points by lines, and two functions `translate_clip` and `transform_clip` that apply transforms to each of the points in the array.
The real magic happens in `transform_clip`, where the three rotations given by `frz`, `frx`, and `fry` are applied (in that order, matching .ass rendering).
This is done by applying the corresponding rotation matrices, followed by projecting back to the $z=312.5$ plane.

## Text Breaking Effect
This final effect is one that can actually be used for song styling, but it's also the promised application of the template above. (Though I should say that I actually wrote this one first. Which you can as it's formatted in a pretty messy way.)
It's an effect that breaks each syllable of the text into pieces, which then fall down the screen.

https://user-images.githubusercontent.com/99741385/201801435-8623c753-21e9-447a-a6d1-d5ed96fa5058.mp4

This is the template:
```
[Script Info]
ScriptType: v4.00+
PlayResX: 1920
PlayResY: 1080
ScaledBorderAndShadow: yes
WrapStyle: 0
YCbCr Matrix: TV.709

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Karaoke,Cactus,70,&H002B0578,&H000000FF,&H0052C9DB,&H00000000,0,0,0,0,100,100,0,0,1,2.5,0,8,10,10,20,1

[Events]
Comment: 0,0:00:10.11,0:00:10.11,Karaoke,,0,0,0,code once,function random(a, b) return a + (b - a) * math.random() end
Comment: 0,0:00:10.11,0:00:10.11,Karaoke,,0,0,0,code once,function write_clip(clip_arr) cliptext = ""; for i,pt in _G.ipairs(clip_arr) do if i == 1 then cliptext = cliptext .. "m" elseif i == 2 then cliptext = cliptext .. " l" end cliptext = cliptext .. " " .. pt.x .. " " .. pt.y; end return cliptext; end
Comment: 0,0:00:10.11,0:00:10.11,Karaoke,,0,0,0,code once,function translate_clip(clip_arr, tx, ty) newclip = {}; for i,pt in _G.ipairs(clip_arr) do newclip[i] = {x=pt.x + tx, y=pt.y + ty} end return newclip; end;
Comment: 0,0:00:10.11,0:00:10.11,Karaoke,,0,0,0,code once,function rotate_clip(clip_arr, o, frz) rad = -frz * math.pi / 180; newclip = {}; for i,pt in _G.ipairs(clip_arr) do tx = pt.x - o.x; ty = pt.y - o.y; newclip[i] = {x=o.x + math.cos(rad) * tx - math.sin(rad) * ty, y=o.y + math.sin(rad) * tx + math.cos(rad) * ty} end return newclip; end;
Comment: 0,0:00:10.11,0:00:10.11,Karaoke,,0,0,0,code once,function rayxrect(o, t, topleft, botright) lx = t.x < o.x and topleft.x or botright.x; ly = t.y < o.y and topleft.y or botright.y; xinty = o.y + (t.y - o.y) / (t.x - o.x) * (lx - o.x); yintx = o.x + (t.x - o.x) / (t.y - o.y) * (ly - o.y); return ((o.y <= xinty and xinty <= ly) or (o.y >= xinty and xinty >= ly)) and {x=lx, y=xinty} or {x=yintx, y=ly}; end
Comment: 0,0:00:00.00,0:00:05.00,Karaoke,,0,0,0,code syl,break_len = 1000; break_speed = 20; break_rotspeed = (-1)^syl.i * random(3, 20); break_gravity = 2; break_o_variance = 5; break_px = orgline.left + syl.center; break_py = orgline.middle; break_o = {x=break_px + random(-break_o_variance, break_o_variance), y = break_py + random(-break_o_variance, break_o_variance)}; break_n = util.rand.item({3, 4, 5,6,7}); break_a_abs = random(0, 360); break_a_variance = 10; break_info = {}; for i=1,break_n do a = (i*(360/break_n) + random(-break_a_variance, break_a_variance) + break_a_abs) * math.pi/180; rp = {x=break_o.x+break_len*math.cos(a), y=break_o.y+break_len*math.sin(a)}; int = rayxrect(break_o, rp, {x=orgline.left+syl.left, y=orgline.top}, {x=orgline.left+syl.right, y=orgline.bottom}); break_info[i] = {angle = a, rp = rp, rectint = int, rotspeed = break_rotspeed * random(0.7, 1.2)}; end for i=1,break_n do break_info[i].clip = {break_o, break_info[i].rp, break_info[i%break_n + 1].rp}; break_info[i].centroid = {x=(break_o.x + break_info[i].rectint.x + break_info[i%break_n + 1].rectint.x)/3, y=(break_o.y + break_info[i].rectint.y + break_info[i%break_n + 1].rectint.y)/3}; end
Comment: 0,0:00:00.00,0:00:05.00,Karaoke,,0,0,0,template syl noblank,{!retime("start2syl")!\an5\pos(!break_px!,!break_py!)}
Comment: 0,0:00:00.00,0:00:05.00,Karaoke,,0,0,0,template syl noblank loop piece 1,{!util.fbf("presyl", 0, 2000, 1, "fbf")!!retime("abs", line.start_time, math.min(line.end_time, orgline.end_time))!!maxloop("piece", break_n)!!set("t", loopctx.state.fbf)!!set("info", break_info[loopctx.state.piece])!!set("tx", break_speed * t * math.cos(info.angle))!!set("ty", break_speed * t * math.sin(info.angle)+break_gravity*t^2)!!set("frz", info.rotspeed*t)!\an5\org(!info.centroid.x+tx!, !info.centroid.y+ty!)\pos(!break_px+tx!, !break_py+ty!)\clip(!write_clip(rotate_clip(translate_clip(info.clip, tx, ty), {x=info.centroid.x + tx, y=info.centroid.y + ty}, frz))!)\frz!frz!\alpha!colorlib.fmt_alpha(12*t)!}
Comment: 0,0:00:00.00,0:00:05.00,Karaoke,,0,0,0,kara,{\k37}Ka{\k39}ra{\k21}o{\k48}ke {\k120}Line
```

### Breakdown
You'll notice some familiar functions in here:
We have the same functions `write_clip` and `translate_clip` as before, and we have `rotate_clip`, which rotates the points of the shape with a given org.
We need these since we use clips to cut our syllable into pieces, and need to transform the clips accordingly once we start moving and rotating them.
So, here's a breakdown of the rest of the template:

- This is a classic karaoke effect, so we use `template syl`.
  We have one `template syl` retimed to `start2syl` for the static text before it starts to break - nothing too mind-blowing there.
- What's more interesting is the second `template syl`, as well as the `code syl` before it. Let's start with the `code syl`:
- We begin by defining some constants. Most imporatntly, we randomly pick a number `break_n` of pieces to break the syllable into.
  We then loop over that number of iterations, and build a table `break_info` containing all the information on how we broke our syllable apart:
- We pick a center `break_o` to start cutting from once and for all for the given syllable.
  This is just the syllable's center plus a random offset.
  Then, we randomly pick angles to cut along (we start by cutting into equally-sized angles and randomly perturb them).
- We draw the rays from `break_o` with those angles and intersect them with the bounding box of the syllable.
  We need to do this, since we need to compute the (approximate) center of mass of the broken piece, since this will need to be the origin of the rotation of the pieces.
  Otherwise the rotation won't look right.
- We also build the clip for the given piece and randomly pick a rotation speed for the piece.
  We let the pieces of successive syllables alternatingly rotate left and right.
- In the second `template syl` line, we now draw all of this.
  On top of the typical frame-by-frame loop, we loop over the number of pieces.
  We also use `retime` to make sure that the pieces will only be visible for as long as the `kara` line is active.
  (This is a dumb hack and should just use `skip()` or a parameter for `util.fbf` instead... I did say that these weren't yet polished.)
  We compute how much the piece has moved in `tx` and `ty` - this is just the linear movement in the direction of the break, together with gravitational acceleration.
  We also compute the rotation according to the picked rotation speed, while setting the origin to the `centroid` of the piece (adjusted by `tx` and `ty`).
  Finally, we transform the clip we picked accordingly and apply it. We fade the piece out using `colorlib.fmt_alpha`.
  
  
