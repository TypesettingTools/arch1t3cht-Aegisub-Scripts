export script_name = "Focus Lines"
export script_description = "Draws moving focus lines."
export script_version = "1.0.0"
export script_namespace = "arch.FocusLines"
export script_author = "arch1t3cht"

haveDepCtrl, DependencyControl = pcall(require, "l0.DependencyControl")
local AMath
local depctrl

if haveDepCtrl
    depctrl = DependencyControl({
        feed: "https://raw.githubusercontent.com/arch1t3cht/Aegisub-Scripts/main/DependencyControl.json",
        {
            {"arch.Math", version: "0.1.0", url: "https://github.com/arch1t3cht/Aegisub-Scripts",
            feed: "https://raw.githubusercontent.com/arch1t3cht/Aegisub-Scripts/main/DependencyControl.json"},
        }
    })
    AMath = depctrl\requireModules!
else
    AMath = require "arch.Math"

{:Point, :Matrix} = AMath

screenwidth = 0
screenheight = 0

round = (val, n=0) -> math.floor((val * 10^n) + 0.5) / (10^n)

randrange = (a, b) -> a + (b - a) * math.random()

format_drawing = (m) ->
    s = "m"
    for i, p in ipairs(m)
        if i == 2
            s ..= " l"
        s ..= " #{round(p[1], 2)} #{round(p[2], 2)}"
    return s


draw_focus_lines_at_frame = (orgline, i, results) ->
    orgline.start_time = aegisub.ms_from_frame(i)
    orgline.end_time = aegisub.ms_from_frame(i + 1)

    color = results.color\gsub("#(%x%x)(%x%x)(%x%x).*","&H%3%2%1&")

    outlines = {}

    extent = (screenwidth + screenheight) / 2 / math.min(results.width, results.height)

    for i=1,results.layers
        line = {k,v for k,v in pairs(orgline)}
        line.layer += i - 1

        t = (i - 1) / (results.layers - 1)
        blur = (1 - t) * results.minblur + t * results.maxblur

        text = "{\\an7\\p1\\1c#{color}\\bord0\\shad0\\blur#{round(blur, 2)}\\pos(#{screenwidth/2},#{screenheight/2})}"

        for j=1,results.numlines
            angle = math.random() * 2 * math.pi

            linewidth = randrange(results.minlinewidth, results.maxlinewidth) / 100

            shape = Matrix({
                {1 + randrange(-results.sizechange, results.sizechange)/100, 0},
                {1 + results.linepointiness/100 + randrange(-results.sizechange, results.sizechange)/100, linewidth},
                {extent, linewidth},
                {extent, -linewidth},
                {1 + results.linepointiness/100 + randrange(-results.sizechange, results.sizechange)/100, -linewidth},
            })

            shape = shape * Matrix.rot2d(angle)
            shape = shape * Matrix({
                {results.width / 2, 0},
                {0, results.height / 2},
            })

            if j != 1
                text ..= " "

            text ..= format_drawing(shape)

        line.text = text
        table.insert(outlines, line)

    return outlines
    

draw_focus_lines = (subs, sel, results) ->
    offset = 0
    newsel = {}

    for si, li in ipairs(sel)
        line = subs[li + offset]

        startframe = aegisub.frame_from_ms(line.start_time)
        endframe = aegisub.frame_from_ms(line.end_time) - 1

        for i=startframe,endframe
            for fline in *draw_focus_lines_at_frame(line, i, results)
                subs.insert(li + offset, fline)
                table.insert(newsel, li + offset)
                offset += 1

        subs.delete(li + offset)
        offset -= 1

    return newsel


focus_lines = (subs, sel) ->
    screenwidth, screenheight = aegisub.video_size()

    ok = "OK"
    cancel = "Cancel"
    help = "Help"

    while true
        button, results = aegisub.dialog.display({{
            class: "label",
            label: "           Lines per Layer: "
            x: 0, y: 0, width: 2, height: 1,
        }, {
            class: "intedit",
            name: "numlines",
            min: 0,
            max: 1000,
            value: 40,
            x: 2, y: 0, width: 1, height: 1,
        }, {
            class: "label",
            label: "Layers: "
            x: 3, y: 0, width: 1, height: 1,
        }, {
            class: "intedit",
            name: "layers",
            min: 0,
            max: 50,
            value: 5,
            x: 4, y: 0, width: 1, height: 1,
        }, {
            class: "label",
            label: "Color: "
            x: 5, y: 0, width: 1, height: 1,
        }, {
            class: "color",
            name: "color",
            x: 6, y: 0, width: 1, height: 1,
        }, {
            class: "label",
            label: "Ellipse: "
            x: 0, y: 1, width: 1, height: 1,
        }, {
            class: "label",
            label: "Width: "
            x: 1, y: 1, width: 1, height: 1,
        }, {
            class: "floatedit",
            name: "width",
            min: 0,
            max: 2 * screenwidth,
            value: round(0.8 * screenwidth, -2),
            x: 2, y: 1, width: 1, height: 1,
        }, {
            class: "label",
            label: "Height: "
            x: 3, y: 1, width: 1, height: 1,
        }, {
            class: "floatedit",
            name: "height",
            min: 0,
            max: 2 * screenheight,
            value: round(0.7 * screenheight, -2),
            x: 4, y: 1, width: 1, height: 1,
        }, {
            class: "label",
            label: "Size Change (%): "
            x: 5, y: 1, width: 1, height: 1,
        }, {
            class: "floatedit",
            name: "sizechange",
            min: 0,
            max: 100,
            value: 10,
            x: 6, y: 1, width: 1, height: 1,
        }, {
            class: "label",
            label: "Blur: "
            x: 0, y: 2, width: 1, height: 1,
        }, {
            class: "label",
            label: "Min: "
            x: 1, y: 2, width: 1, height: 1,
        }, {
            class: "floatedit",
            name: "minblur",
            min: 0,
            max: 10,
            value: 5,
            x: 2, y: 2, width: 1, height: 1,
        }, {
            class: "label",
            label: "Max: "
            x: 3, y: 2, width: 1, height: 1,
        }, {
            class: "floatedit",
            name: "maxblur",
            min: 0,
            max: 10,
            value: 10,
            x: 4, y: 2, width: 1, height: 1,
        }, {
            class: "label",
            label: "Line Width (%): "
            x: 0, y: 3, width: 1, height: 1,
        }, {
            class: "label",
            label: "Min: "
            x: 1, y: 3, width: 1, height: 1,
        }, {
            class: "floatedit",
            name: "minlinewidth",
            min: 0,
            max: 100,
            value: 1,
            x: 2, y: 3, width: 1, height: 1,
        }, {
            class: "label",
            label: "Max: "
            x: 3, y: 3, width: 1, height: 1,
        }, {
            class: "floatedit",
            name: "maxlinewidth",
            min: 0,
            max: 100,
            value: 1,
            x: 4, y: 3, width: 1, height: 1,
        }, {
            class: "label",
            label: "Line Pointiness (%): "
            x: 5, y: 3, width: 1, height: 1,
        }, {
            class: "floatedit",
            name: "linepointiness",
            min: 0,
            max: 2,
            value: 70,
            x: 6, y: 3, width: 1, height: 1,
        }}, {ok, help, cancel}, {ok: ok, cancel: cancel})

        return draw_focus_lines(subs, sel, results) if button == ok
        break if button == cancel or button == false

        if button == help
            aegisub.dialog.display({{
                class: "textbox",
                x: 0, y: 0, width: 50, height: 10,
                value: [[
This script replaces all selected subtitle lines with drawn frame-by-frame focus lines.
The focus lines are drawn using multiple layers of shapes, with different layers having different blur - scaling
linearly from the minimum blur to the maximum blur.
All other values are independent of the layer. The line width is chosen randomly in the given range for each individual line.
The ellipse's size change controls how much the focus lines randomly move inward and outward.
The "line pointiness" option is probably the least useful one, but it controls where the thickest point of each line lies.
]],
            }})


has_video = () -> aegisub.ms_from_frame(0) != nil

aegisub.register_macro(script_name, script_description, focus_lines, has_video)