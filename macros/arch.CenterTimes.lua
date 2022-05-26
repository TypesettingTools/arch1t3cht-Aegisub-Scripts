script_name = "Center Times"
script_author = "arch1t3cht"
script_version = "1.1"
script_namespace = "arch.CenterTimes"
script_description = "Centering times of lines in frame ranges"

---------- Rationale behind this script: ----------
-- ** Motivation
-- Some third-party tools like SubKt or various automation scripts can only
-- shift subtitle lines by times, and not by frames.
-- More specifically, some of them provide features for syncing two files
-- with respect to two sync points by adding the time difference of these two
-- sync points to every line in one of the files.
--
-- .ass files specify times with centisecond accuracy, and one video frame
-- usually spans more than one centisecond step. If the times of the sync
-- points are aligned inside their frame range in an unfortunate manner,
-- i.e. if one sync point has a time very early in its frame, while the
-- other lies very late in its frame, the time difference will not come
-- out to be a clean multiple of a frame's duration. If this is then added
-- to the time of another line, the resulting number of frames this line
-- is shifted by will depend on the alignment of the line's time in its frame.
-- Thus, not all lines might be shifted by the same number of frames, which
-- can cause 1-frame (or potentially worse) flashes.
--
-- ** Possible remedies
-- Of course, this can be solved by instead configuring such tools to shift
-- by frames. However, this requires knowing the frame rate, which is not
-- always nontrivial to code (as is the case with SubKt).
-- In some cases, this issue can also be prevented by making sure that
-- the times of all lines are aligned in a way that makes these frame-jumps
-- mathematically impossible. Whether this is possible depends on the video's
-- frame rate, but for common frame rates like 23.976 fps, this can be done:
--
-- ** Computations
-- - Without any rounding, for a frame rate of 23.976 fps,
--   two frames are just over 41ms apart
-- - .ass subtitles allow specifying times up to timesteps of 10ms
-- - We can model this as if any line had an "ideal time" where it should
--   actually be, which we always choose to be the exact midpoint of the time
--   span of a frame,
--   and the "approximated time", which is its time in any .ass file, and which
--   is thus rounded to 10ms steps
-- 
-- -> thus, when reading a line's time from a .ass file, ideally the absolute
--    error for any given line is <= 5ms 
-- - When SubKt syncs a .ass line into another file, it
--     - reads the sync target time a (error <= 5ms)
--     - reads the sync source time b (error <= 5ms)
--     - reads the actual line's time t (error <= 5ms)
-- - and then times the line to t + (a - b).
-- - Hence the maximum absolute error for the synced line is
--                  5ms + 5ms + 5ms = 15ms.
--   But this is smaller than 41ms / 2, so as long as these three times are
--   close enough to their respective ideal times, the synced time will still
--   be inside the 41ms range.
--
-- ** Conclusion
-- By timing each involved line to the centisecond step closest to the ideal
-- time of the respective frame, one can ensure that every line stays inside
-- its frame throughout such a syncing process for such a frame rate (and in
-- fact for any constant frame rate below 33 fps). However, this will of
-- course only work for one iteration of such a process, unless the times are
-- recentered again after the first iteration.
-- 
-- Aegisub does not time lines optimally, even when using functions that time
-- lines to video frames. This script optimally centers the times of all
-- selected lines with respect to (a very close approximation of) the currently
-- loaded video's frame rate. It contains a built-in guarantee that no line
-- will be moved to different frames (as reported by Aegisub) - if the computed
-- time for any line lies in a different frame, the script will abort.
-- Note, however, that this will (obviously) not apply for lines containing
-- transform or \move tags.
--
-- Floating point rounding errors are a theoretical concern, but (as long as
-- floating point precision of 32 bit or more are used) will not be anywhere
-- close to relevant for video lengths anywhere under 5 hours. 
--
-- ** Important Caveats
-- This script (and, in fact, this whole argument) will NOT work whenever lines
-- timed to the 0-th frame are involved, as 00:00:00.00 is the only centisecond
-- step contained in this frame.
--
-- It will also (obviously) not work for variable frame rates. Finally, the
-- script assumes that the first frame starts right after 00:00:00.00, so
-- it will not work for videos that don't conform to this.
--
-- Finally, this script only changes the beginning and end times of subtitle lines,
-- so the rendering of any lines containing \move or \t tags *will* be affected.


function centertime(time, framerate)
    -- time: in milliseconds
    local frame = aegisub.frame_from_ms(time)
    local center = math.floor((frame - 0.5) / (framerate * 10) + 0.5) * 10

    if center < 0 then center = 0 end

    if aegisub.frame_from_ms(center) ~= frame then
        show_dialog("Assertion failed!")
        return nil
    end

    return center
end

function centertimes(subs, sel)
    -- use evil hacks to get the framerate
    local ref_ms = 100000000     -- 10^8 ms ~~ 27.7h
    local ref_frame = aegisub.frame_from_ms(ref_ms)

    if ref_frame == nil then
        aegisub.log("No video opened / no framerate available!")
        return
    end

    local framerate = ref_frame / ref_ms    -- in frames/ms

    for x, i in ipairs(sel) do
        local line = subs[i]
        line.start_time = centertime(line.start_time, framerate)
        line.end_time = centertime(line.end_time, framerate)
        if line.start_time == nil or line.end_time == nil then
            -- assertion failed: error
            return
        end
        subs[i] = line
    end
end

function has_video(subs, sel)
    if aegisub.frame_from_ms(0) == nil then
        return false, "No video opened / no framerate available!"
    end
    return true
end

aegisub.register_macro(script_name,script_description,centertimes,has_video)