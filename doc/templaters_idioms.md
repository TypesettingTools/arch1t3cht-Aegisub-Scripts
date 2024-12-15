# Karaoke Templater Idioms, Snippets, and Tricks
This page collects some common templating tricks and idioms.
You can use it to learn new tricks, or as a kind of "cheat sheet".
Of course, you should also refer to the respective templater's documentation (see [my general templater guide](templaters.md) for links).

Everything listed here uses The0x539's templater.

### Setting a Random Seed
If your template uses randomness, it may be helpful to set a constant seed at the top of your template by adding a `code once` with `math.randomseed(1337)` (or some other seed).
That way, rerunning your template won't regenerate all random effects, which makes it easier to compare outputs.
Once your template and lyrics are final, you can try different seeds if some randomly generated values look weird, but note that any change to your template or lyrics will probably shuffle all values around again.
If you find yourself repeatedly needing to shuffle around the seed to get random values to look good, you may want to tweak your random distributions.
For example, picking out five random angles on a circle rarely looks good and you usually want to start out with splitting a circle into five uniform pieces and then shuffling things around slightly.

### A Simple Random Range Function
Put `function random(a, b) return a + (b - a) * math.random()` in a `code once`  to get a function that gives you a random float in the given range (as opposed to Lua's built-in `math.random(a, b)` which only returns integers).

### A Dummy Function to Eat Values
Put `function d() return "" end` into a `code once` to get a function `d` that can be used to eat any value.
This can be useful when some `!!` expression (e.g. something involving `or` or `and`) evaluates to a boolean or some other string, which then ends up being written into your generated line without you wanting to.
By just wrapping that expression in a `d()`, you can discard the value.

This is also useful if you want to write comments inside of `template` or `mixin` lines, since you can just do `!d("This is a comment")!`.

### `set` is cool
`set` is a very helpful function and you should use it.
As a reminder, it can be used inside of `template` or `mixin` lines to remember values.
So, instead of `{\fscx!100 + 2*t!\fscy!100 + 2*t!}` you can write `!set("scale", 100 + 2 * t)!{\fscx!scale!\fscy!scale!}`.
In general, it is good practice to never have to write any constant (at least any constant you may want to modify later) or any formula multiple times.
Using `set` can help you with that.

You can also sometimes use a `code line/syl/word/char` instead of `set`, but, as a reminder, these only run *once* for every line/syl/word/char in the input lyrics, while `set` runs for every *generated* line (i.e. also for every loop iteration).
Hence, if you need to set a value depending on the loop iteration (or your fbf frame), you need to use `set` rather than some `code` line.

### Inline If-and-Else
In Lua, you can write an inline if-and-else expression (i.e. a ternary operator) using `and` and `or`, for example: `!orgline.actor == "big" and 150 or 100!` evaluates to `150` if `orgline.actor` is `"big"` and to `100` otherwise.

If you want to use this to conditionally call a function (e.g. `!line.end_time < line.start_time and skip()!`), note that this expression can evaluate to `false` and end up writing `"false"` into your generated line.
Hence, you may want to wrap such expressions in a `d()` (see [above](#a-dummy-function-to-eat-values)).

### Immediately-Invoked Function Expressions (IIFE)
If you really need to run complex code (e.g. including loops) inside of a `template` or `mixin` and can't/don't want to use a `code` line or a helper function, you can use an IIFE with `!(function () <code here> end)()!`.

### Easy `\pos`
If you have KaraOK installed (but note that you'll still run this template using The0x's templater), you can use `!ln.tag.pos()!` as a shorthand for quickly setting your syllable's position (i.e. for something like `\an5\pos(!orgline.left + syl.center!,!orgline.middle!)`).
You can customize the alignment or add a shift using parameters to this function, refer to the [KaraOK documentation](https://github.com/logarrhythmic/karaOK?tab=readme-ov-file#pos) for more information.

### Getting the Relative Time with FBF
When you use `util.fbf` to get a frame-by-frame loop, you can use `!set("t", line.start_time - orgline.start_time)!` to then find the relative time from the current frame slice to the start of the line.

If you additionally want to retime everything to the syllable/char or add lead-in, you can e.g. use the following pattern:

`!retime(<your values>)!!set("starttime", line.start_time)!!util.fbf()!set("t", line.start_time - starttime)!`.

Using this, you can then use transforms in your line by just subtracting `t` from all values: A `\t(0,150,\frz30)` on a non-fbf'd line can turn into a `\t(!-t!,!150 - t!,\frz30)` on an fbf'd line.
This saves you the trouble of writing your own interpolation functions and baking in the values (though you could do this too, e.g. using `util.lerp`).

### ASS Gotcha: `\move` with Relative Times
If you do the above with `\move` rather than with `\t` you should be aware that a `\move` whose start and end timestamps are negative (or zero) results in a move over the entire line's duration.
Hence, for `\move` you may need to add some additional logic or to use `util.lerp` with a `\pos` instead.

### Easy Alternating Values with `(-1)^i`
If you want a value to flip between positive and negative every syl/char/line/etc, you can multiply it with `(-1)^syl.i`.
This is much more compact than manual code or something like `syl.i % 2 == 0 and value or -value`.

### Text to Shape
Use [ILL](https://github.com/TypesettingTools/ILL-Aegisub-Scripts/) to convert text to shapes and modify those shapes:
- Make sure you have the `ILL` module installed via DependencyControl
- Add a `code once` with `ill = require("ILL.ILL")`
- Use `ill.Line.toPath({data=orgline.styleref,text_stripped=syl.text_stripped})` to obtain a path object for your text. For example, you could assign this to a variable `path` in a `code syl`, or use `set` (or use the result directly). You can `syl.text_stripped` with `orgline.text_stripped` or any other text you want.
- To turn the path object into an actual shape, use `path:export()`. For example, you could use `{!ln.tag.pos(7)!\p1}!path:export()!`.
- You can use various functions to modify the path, e.g. `path:move(10, 20)` to move the path around, `path:rotatefrz(90)` to rotate, etc. Refer to [the ILL source code](https://github.com/TypesettingTools/ILL-Aegisub-Scripts/blob/main/modules/ILL/ILL/Ass/Shape/Path.moon) for a list of functions. Note that functions like `move` and `rotatefrz` both return the modified path *and* modify the path they were called on. Hence, if you need to output multiple copies of the path that are modified in different ways, you may need to use `path:clone()` to clone your paths.

### Using Dummy `kara` Lines as Input
Sometimes, you may want to hardcode some drawings or clips in your template.
To make adding and modifying drawings as easy as possible, I like to edit these drawings as clips using Aegisub's built-in clipping tool.
You can use the following system to directly read in these values:

- Make a new style called `Dummy`.
- Make sure you have imported ILL (see above).
- Add a couple of lines with the style `Dummy` and the actor `kara` and give them clips using Aegisub's clip tool. Then, comment out the lines. If you want to edit them, you can uncomment them again, edit the clips, and comment them again.

  Make sure that these lines are *above* your normal `kara` lines.
- Then, add a `code once` with the style `Dummy` and the code `shapes = {}`.
- Also, add a `code line` with the style `Dummy` and the code `table.insert(shapes, ill.Path(orgline.text:match("%\\clip%(.-)%)")))`.
- Then, you can access the list `shapes` of all the shapes in your remaining template's code (and e.g. export it using `shapes[0].export()`).

If you want, you can also modify these shapes somehow (e.g. center them) or add extra metadata (e.g. the line's start and end times).
If you only need the shape text (e.g. for a clip) and don't need to modify it in any way, you also don't need to go through `ill.Path()`.

### Importing DependencyControl-only Modules
If, for some reason, you need to import some module that unconditionally calls DependencyControl (the most likely one being `Functional`), you need to set a `script_namespace` first: `_G.script_namespace = "mykaratemplate"; functional = require"l0.Functional";`

## Crimes
Finally, here are some reasons why I shouldn't be allowed near a templater.

### Moonscript
If you're too lazy to write a for loop or want to use moonscript's string interpolation, you can use the following snippet:

- Add `code once` with `moon = require("moonscript.base"); function moony(s) return _G.setfenv(moon.loadstring(s), tenv)() end`
- Then, you can define functions in moonscript like this: `double = moony("l -> [ a * 2 for a in *l ]")`.

Of course, with moonscript using whitespace for indentation you can't easily write more complex logic in moonscript, but this *can* be useful for a quick list comprehension.

### Multiline Functions
*This is mostly a meme. I haven't (yet) used this in a template myself. If you get to the point where you need to do this you should probably just write a separate file with utility functions or use something like [aegsc](https://github.com/butterfansubs/aegsc).*

If you're sick of huge unreadable one-line Lua functions, you can do the following:

- Add a `code once` with `multiline = {}; local last_actor = ""; for i,line in _G.ipairs(subs) do if line.effect == "multiline" then local actor = line.actor ~= "" and line.actor or multiline_last_actor;  multiline_last_actor = actor; multiline[actor] = multiline[actor] and (multiline[actor] .. "\n" .. line.text) or line.text; end end` (yes, the irony of this being a huge unreadable one-line Lua function is not lost on me).
- Write some multiline Lua code by adding multiple comments with the effect `multiline`. Give the first of these lines some name in the `actor`.
  ```lua
  Comment: [...],mycode,0,0,0,multiline,function myfun()
  Comment:    [...]   ,,0,0,0,multiline,  -- Your code here
  Comment:    [...]   ,,0,0,0,multiline,end
- Call that multiline code using `_G.setfenv(_G.loadstring(multiline.mycode), tenv)()`.
  For example, to define the function in the above example, add a `code once` with `_G.setfenv(_G.loadstring(multiline.mycode), tenv)()`.
