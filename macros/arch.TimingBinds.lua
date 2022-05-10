script_name = "Timing Shortcuts"
script_author = "arch1t3cht"
script_version = "1.0.0"
script_namespace = "arch.timingbinds"
script_description = "Some shorthands for timing"


function do_snap(subs, sel, active_line, to_end)
    frame = aegisub.project_properties().video_position
    if to_end then
        time = aegisub.ms_from_frame(frame + 1)
    else
        time = aegisub.ms_from_frame(frame)
    end

    otherindex = active_line - 1
    if to_end then otherindex = active_line + 1 end

    line = subs[active_line]
    otherline = subs[otherindex]
    if otherline == nil or otherline.class ~= "dialogue" then
        otherline = nil
    end

    if otherline ~= nil and (not to_end and otherline.end_time == line.start_time or to_end and otherline.start_time == line.end_time) then
        if to_end then
            otherline.start_time = time
        else
            otherline.end_time = time
        end
        subs[otherindex] = otherline
    end

    if to_end then
        line.end_time = time
    else
        line.start_time = time
    end

    subs[active_line] = line

    return true
end

function snap_beginning_to_video(subs, sel, active_line)
    return do_snap(subs, sel, active_line, false)
end

function snap_end_to_video(subs, sel, active_line)
    return do_snap(subs, sel, active_line, true)
end

function has_video(subs, sel)
    if aegisub.frame_from_ms(0) == nil then
        return false, "No video opened!"
    end
    return true
end

function shift_frames_to_video(subs, sel, active_line)
    active_line_frame = aegisub.frame_from_ms(subs[active_line].start_time)
    video_frame = aegisub.project_properties().video_position
    if video_frame == nil then
        return false, "No video opened!"
    end

    frame_diff = video_frame - active_line_frame

    for i, s in ipairs(sel) do
        line = subs[s]

        line.start_time = aegisub.ms_from_frame(aegisub.frame_from_ms(line.start_time) + frame_diff)
        line.end_time = aegisub.ms_from_frame(aegisub.frame_from_ms(line.end_time) + frame_diff)

        subs[s] = line
    end
end

function join_previous(subs, sel, active_line)
    sstart, send = aegisub.get_audio_selection()
    line = subs[active_line]
    line.start_time = sstart
    line.end_time = send
    subs[active_line] = line

    prevline = subs[active_line - 1]
    if prevline == nil or prevline.class ~= "dialogue" then
        return
    end
    prevline.end_time = sstart
    subs[active_line - 1] = prevline
end

aegisub.register_macro("Timing Binds/Snap Beginning to Frame","Snap the current line's beginning to the current frame, but also snap the previous line's end, if the lines were joined.",snap_beginning_to_video, has_video)
aegisub.register_macro("Timing Binds/Snap End to Frame","Snap the current line's end to the current frame, but also snap the following line's end, if the lines were joined.",snap_end_to_video, has_video)
aegisub.register_macro("Timing Binds/Join Previous Line","Joins the previous line's end to the current line's beginning.", join_previous)
aegisub.register_macro("Timing Binds/Shift by Frames to Video Position","Shifts the selection such that the active line starts at the video position, but shifts by frames instead of by milliseconds.", shift_frames_to_video)
