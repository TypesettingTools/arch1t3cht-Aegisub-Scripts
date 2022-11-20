# Function AAEExportExportAll._generate() at or about line 144,
# excluding inner function generate_power_pin() at or about line 252,
# is copied from the original `aae-export.py` by Martin Herkt.

# Other part of this script, including the aforementioned inner
# function generate_power_pin(), is written by arch1t3cht,
# Akatsumekusa and contributors.

# Copyright (c) 2013, Martin Herkt
#
# Permission to use, copy, modify, and/or distribute this software for
# any purpose with or without fee is hereby granted, provided that the
# above copyright notice and this permission notice appear in all
# copies.
#
# THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL
# WARRANTIES WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED
# WARRANTIES OF MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE
# AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL
# DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR
# PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER
# TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR
# PERFORMANCE OF THIS SOFTWARE.

# Copyright (c) 2022 arch1t3cht and contributors
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
# 
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
# BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
# ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
# CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

bl_info = {
    "name": "Adobe After Effects 6.0 Keyframe Data Export",
    "description": "Export motion tracking data as Aegisub-Motion compatible AAE file",
    "author": "Martin Herkt, arch1t3cht, Akatsumekusa",
    "version": (0, 1, 6),
    "support": "COMMUNITY",
    "category": "Video Tools",
    "blender": (2, 80, 0),
    "location": "Clip Editor > Tools > Solve > AAE Export",
    "warning": "",
    "doc_url": "https://github.com/arch1t3cht/Aegisub-Scripts#other-scripts",
    "tracker_url": "https://github.com/arch1t3cht/Aegisub-Scripts/issues"
}

import bpy
import bpy_extras.io_utils
from datetime import datetime
import math
from pathlib import Path

class AAEExportSettings(bpy.types.PropertyGroup):
    bl_label = "AAEExportSettings"
    bl_idname = "AAEExportSettings"
    
    do_also_export: bpy.props.BoolProperty(name="Auto export",
                                           description="Automatically export the selected track to file while copying",
                                           default=True)
    do_includes_power_pin: bpy.props.BoolProperty(name="Includes Power Pin",
                                           description="Includes Power Pin data in plane track export.\nAs of Nov 2022, Aegisub-Perspective-Motion doesn't accept Power Pin data mixed with regular tracking data likely due to a bug. Please use the separate powerpin-export.py until this Aegisub-Perspective-Motion bug is fixed",
                                           default=True)
    do_do_not_overwrite: bpy.props.BoolProperty(name="Do not overwrite",
                                                description="Generate unique files every time",
                                                default=False)

class AAEExportExportAll(bpy.types.Operator):
    bl_label = "Export"
    bl_description = "Export all tracking markers and plane tracks to AAE files next to the original movie clip"
    bl_idname = "movieclip.aae_export_export_all"

    @staticmethod
    def _plane_track_center(l, m, n, o):
        """
        Parameters
        ----------
        l : list[float]
        m : list[float]
        n : list[float]
        o : list[float]
            The four points of a plane track in either clockwise or
            counterwise order before multiplying with clip.size.

        Returns
        -------
        i : list[float]
            The centre of plane track. NEVER None. NEVER None.

        """
        # https://stackoverflow.com/questions/563198
        px = l[0]
        py = l[1]
        rx = n[0] - l[0]
        ry = n[1] - l[1]
        qx = m[0]
        qy = m[1]
        sx = o[0] - m[0]
        sy = o[1] - m[1]

        j = rx * sy - ry * sx
        k = (qx - px) * ry - (qy - py) * rx

        if j == 0 and k == 0:
            # The points are collinear
            return [(px * 2 + rx + qx * 2 + sx) / 4, (py * 2 + ry + qy * 2 + sy) / 4]
        elif j == 0 and k != 0:
            # The two lines are parallel
            # It could return AAEExportExportAll._plane_track_center(l, n, m, o)
            # but that will give a false sense of security as if this
            # function can deal with hourglass-shaped input.
            return [(px * 2 + rx + qx * 2 + sx) / 4, (py * 2 + ry + qy * 2 + sy) / 4]
        else: # j != 0
            # The two lines intersects
            t = k / j
            return [px + t * rx, py + t * ry]

    def execute(self, context):
        clip = context.edit_movieclip
        settings = context.screen.AAEExportSettings

        for track in clip.tracking.tracks:
            AAEExportExportAll._export_to_file(clip, track, AAEExportExportAll._generate(clip, track, settings.do_includes_power_pin), None, settings.do_do_not_overwrite)

        for plane_track in clip.tracking.plane_tracks:
            AAEExportExportAll._export_to_file(clip, plane_track, AAEExportExportAll._generate(clip, plane_track, settings.do_includes_power_pin), None, settings.do_do_not_overwrite)
        
        return {"FINISHED"}

    @staticmethod
    def _generate(clip, track, do_includes_power_pin):
        """
        Parameters
        ----------
        clip : bpy.types.MovieClip
        track : bpy.types.MovieTrackingTrack or MovieTrackingPlaneTrack
        do_includes_power_pin : bool
            AAEExportSettings.do_includes_power_pin.

        Returns
        -------
        aae : str

        """
        startarea = None
        startwidth = None
        startheight = None
        startrot = None

        data = []

        aae = "Adobe After Effects 6.0 Keyframe Data\n\n"
        aae += "\tUnits Per Second\t{0:.3f}\n".format(clip.fps)
        aae += "\tSource Width\t{0}\n".format(clip.size[0])
        aae += "\tSource Height\t{0}\n".format(clip.size[1])
        aae += "\tSource Pixel Aspect Ratio\t1\n"
        aae += "\tComp Pixel Aspect Ratio\t1\n\n"

        for marker in (track.markers[1:] if not track.markers[0].is_keyed else track.markers) if track.markers[0].__class__.__name__ == "MovieTrackingMarker" else track.markers[1:-1]:
            if not 0 < marker.frame <= clip.frame_duration:
                continue
            if marker.mute:
                continue

            if marker.__class__.__name__ == "MovieTrackingMarker":
                coords = marker.co
                corners = marker.pattern_corners
            else: # "MovieTrackingPlaneMarker"
                coords = AAEExportExportAll._plane_track_center(marker.corners[0], marker.corners[1], marker.corners[2], marker.corners[3])
                corners = [[p[0] - coords[0], p[1] - coords[1]] for p in marker.corners]
            
            area = 0
            width = math.sqrt((corners[1][0] - corners[0][0]) * (corners[1][0] - corners[0][0]) + (corners[1][1] - corners[0][1]) * (corners[1][1] - corners[0][1]))
            height = math.sqrt((corners[3][0] - corners[0][0]) * (corners[3][0] - corners[0][0]) + (corners[3][1] - corners[0][1]) * (corners[3][1] - corners[0][1]))
            for i in range(1,3):
                x1 = corners[i][0] - corners[0][0]
                y1 = corners[i][1] - corners[0][1]
                x2 = corners[i+1][0] - corners[0][0]
                y2 = corners[i+1][1] - corners[0][1]
                area += x1 * y2 - x2 * y1
            
            area = abs(area / 2)

            if startarea == None:
                startarea = area

            if startwidth == None:
                startwidth = width
            if startheight == None:
                startheight = height

            zoom = math.sqrt(area / startarea) * 100

            xscale = width / startwidth * 100
            yscale = height / startheight * 100

            diff = [(corners[0][0] + corners[1][0]) / 2, (corners[0][1] + corners[1][1]) / 2]

            rotation = math.atan2(diff[0], diff[1]) * 180 / math.pi

            if startrot == None:
                startrot = rotation
                rotation = 0
            else:
                rotation -= startrot - 360

            x = coords[0] * clip.size[0]
            y = (1 - coords[1]) * clip.size[1]

            data.append([marker.frame, x, y, xscale, yscale, rotation])

        posline = "\t{0}\t{1:.3f}\t{2:.3f}\t0"
        scaleline = "\t{0}\t{1:.3f}\t{2:.3f}\t100"
        rotline = "\t{0}\t{1:.3f}"

        positions = "\n".join([posline.format(d[0], d[1], d[2]) for d in data])
        scales = "\n".join([scaleline.format(d[0], d[3], d[4]) for d in data])
        rotations = "\n".join([rotline.format(d[0], d[5]) for d in data])

        aae += "Anchor Point\n"
        aae += "\tFrame\tX pixels\tY pixels\tZ pixels\n"
        aae += positions

        aae += "\n\n"
        aae += "Position\n"
        aae += "\tFrame\tX pixels\tY pixels\tZ pixels\n"
        aae += positions

        aae += "\n\n"
        aae += "Scale\n"
        aae += "\tFrame\tX percent\tY percent\tZ percent\n"
        aae += scales

        aae += "\n\n"
        aae += "Rotation\n"
        aae += "\tFrame Degrees\n"
        aae += rotations

        def generate_power_pin(clip, track):
            power_pin = ""

            frames = []
            corners = []
            for marker in track.markers[1:-1]:
                if not 0 < marker.frame <= clip.frame_duration:
                    continue
                if marker.mute:
                    continue

                frames.append(marker.frame)
                corners.append([list(c) for c in marker.corners])
            
            for pini, corneri in [(2, 3), (3, 2), (4, 0), (5, 1)]:
                power_pin += f"\n\nEffects\tCC Power Pin #1\tCC Power Pin-000{pini}"
                power_pin += "\n\tFrame\tX pixels\tY pixels"

                for i, plane in enumerate(corners):
                    corner = plane[corneri]
                    x = corner[0] * clip.size[0]
                    y = (1 - corner[1]) * clip.size[1]
                    power_pin += f"\n\t{frames[i]}\t{x:.3f}\t{y:.3f}"

            return power_pin
    
        if do_includes_power_pin and track.markers[0].__class__.__name__ == "MovieTrackingPlaneMarker":
            aae += generate_power_pin(clip, track)

        aae += "\n\nEnd of Keyframe Data\n"

        return aae

    @staticmethod
    def _export_to_file(clip, track, aae, prefix, do_do_not_overwrite):
        """
        Parameters
        ----------
        clip : bpy.types.MovieClip
        track : bpy.types.MovieTrackingTrack or MovieTrackingPlaneTrack
        aae : str
            Likely coming from _generated().
        prefix : None or str
        do_do_not_overwrite : bool
            AAEExportSettings.do_do_not_overwrite.

        """
        coords = None
        if track.markers[0].__class__.__name__ == "MovieTrackingMarker":
            for marker in track.markers:
                if not marker.mute:
                    coords = (marker.co[0] * clip.size[0], (1 - marker.co[1]) * clip.size[1])
                    break
        else: # "MovieTrackingPlaneMarker"
            for marker in track.markers:
                if not marker.mute:
                    coords = AAEExportExportAll._plane_track_center(marker.corners[0], marker.corners[1], marker.corners[2], marker.corners[3])
                    coords = (coords[0] * clip.size[0], (1 - coords[1]) * clip.size[1])
                    break

        if coords != None:
            p = Path(clip.filepath if not prefix else prefix)
            p = p.with_stem(p.stem + \
                            "[" + ("Track" if track.markers[0].__class__.__name__ == "MovieTrackingMarker" else "Plane Track") + "]" + \
                            f"[({coords[0]:.0f}, {coords[1]:.0f})]" + \
                            (datetime.now().strftime("[%H%M%S %b %d]") if do_do_not_overwrite else "")) \
                 .with_suffix(".txt")
            with p.open(mode="w", encoding="utf-8", newline="\r\n") as f:
                f.write(aae)

    @staticmethod
    def _copy_to_clipboard(context, aae):
        """
        Parameters
        ----------
        context : bpy.context
        aae : str
            Likely coming from _generated().
            
        """
        context.window_manager.clipboard = aae

class AAEExportCopySingleTrack(bpy.types.Operator):
    bl_label = "Copy"
    bl_description = "Copy selected marker as AAE data to clipboard"
    bl_idname = "movieclip.aae_export_copy_single_track"

    def execute(self, context):
        clip = context.edit_movieclip
        settings = context.screen.AAEExportSettings

        aae = AAEExportExportAll._generate(clip, context.selected_movieclip_tracks[0], settings.do_includes_power_pin)
        
        AAEExportExportAll._copy_to_clipboard(context, aae)
        if settings.do_also_export:
            AAEExportExportAll._export_to_file(clip, context.selected_movieclip_tracks[0], aae, None, settings.do_do_not_overwrite)
        
        return {"FINISHED"}

class AAEExportCopyPlaneTrack(bpy.types.Operator):
    bl_label = "Copy"
    bl_description = "Copy selected plane track as AAE data to clipboard"
    bl_idname = "movieclip.aae_export_copy_plane_track"

    def execute(self, context):
        clip = context.edit_movieclip
        settings = context.screen.AAEExportSettings

        aae = None
        for plane_track in context.edit_movieclip.tracking.plane_tracks:
            if plane_track.select == True:
                aae = AAEExportExportAll._generate(clip, plane_track, settings.do_includes_power_pin)
                break

        AAEExportExportAll._copy_to_clipboard(context, aae)
        if settings.do_also_export:
            AAEExportExportAll._export_to_file(clip, clip.tracking.plane_tracks[0], aae, None, settings.do_do_not_overwrite)
        
        return {"FINISHED"}
    
class AAEExport(bpy.types.Panel):
    bl_label = "AAE Export"
    bl_idname = "SOLVE_PT_aae_export"
    bl_space_type = "CLIP_EDITOR"
    bl_region_type = "TOOLS"
    bl_category = "Solve"

    def draw(self, context):
        pass

    @classmethod
    def poll(cls, context):
        return context.edit_movieclip is not None

class AAEExportSelectedTrack(bpy.types.Panel):
    bl_label = "Selected track"
    bl_idname = "SOLVE_PT_aae_export_selected"
    bl_space_type = "CLIP_EDITOR"
    bl_region_type = "TOOLS"
    bl_category = "Solve"
    bl_parent_id = "SOLVE_PT_aae_export"

    def draw(self, context):
        layout = self.layout
        layout.use_property_split = True
        layout.use_property_decorate = False
        
        settings = context.screen.AAEExportSettings
        
        column = layout.column()
        column.label(text="Selected track")

        row = layout.row()
        row.scale_y = 2
        row.enabled = len(context.selected_movieclip_tracks) == 1
        row.operator("movieclip.aae_export_copy_single_track")
        
        column = layout.column()
        column.label(text="Selected plane track")
        
        selected_plane_tracks = 0
        for plane_track in context.edit_movieclip.tracking.plane_tracks:
            if plane_track.select == True:
                selected_plane_tracks += 1

        row = layout.row()
        row.scale_y = 2
        row.enabled = selected_plane_tracks == 1
        row.operator("movieclip.aae_export_copy_plane_track")

    @classmethod
    def poll(cls, context):
        return context.edit_movieclip is not None

class AAEExportAllTracks(bpy.types.Panel):
    bl_label = "All tracks"
    bl_idname = "SOLVE_PT_aae_export_all"
    bl_space_type = "CLIP_EDITOR"
    bl_region_type = "TOOLS"
    bl_category = "Solve"
    bl_parent_id = "SOLVE_PT_aae_export"

    def draw(self, context):
        layout = self.layout
        layout.use_property_split = True
        layout.use_property_decorate = False
        
        settings = context.screen.AAEExportSettings
        
        column = layout.column()
        column.label(text="Plane tracks")
        column.prop(settings, "do_includes_power_pin")
        
        column = layout.column()
        column.label(text="All tracks")
        column.prop(settings, "do_also_export")
        column.prop(settings, "do_do_not_overwrite")
        
        row = layout.row()
        row.scale_y = 2
        row.enabled = len(context.edit_movieclip.tracking.tracks) >= 1 or \
                      len(context.edit_movieclip.tracking.plane_tracks) >= 1
        row.operator("movieclip.aae_export_export_all")

    @classmethod
    def poll(cls, context):
        return context.edit_movieclip is not None

class AAEExportLegacy(bpy.types.Operator, bpy_extras.io_utils.ExportHelper):
    """Export motion tracking markers to Adobe After Effects 6.0 compatible files"""
    bl_label = "Export to Adobe After Effects 6.0 Keyframe Data"
    bl_idname = "export.aae_export_legacy"
    filename_ext = ""
    filter_glob = bpy.props.StringProperty(default="*", options={"HIDDEN"})

    def execute(self, context):
        # This is broken but I don't want to fix...
        if len(bpy.data.movieclips) != 1:
            raise ValueError("The legacy export method only allows one clip to be loaded into Blender at a time. You can either try the new export interface at „Clip Editor > Tools > Solve > AAE Export“ or use „File > New“ to create a new Blender file.")
        clip = bpy.data.movieclips[0]
        settings = context.screen.AAEExportSettings

        for track in clip.tracking.tracks:
            AAEExportExportAll._export_to_file(clip, track, AAEExportExportAll._generate(clip, track, False), self.filepath, True)

        for plane_track in clip.tracking.plane_tracks:
            AAEExportExportAll._export_to_file(clip, track, AAEExportExportAll._generate(clip, plane_track, False), self.filepath, True)

classes = (AAEExportSettings,
           AAEExportExportAll,
           AAEExportCopySingleTrack,
           AAEExportCopyPlaneTrack,
           AAEExport,
           AAEExportSelectedTrack,
           AAEExportAllTracks,
           AAEExportLegacy)
           
def register_export_legacy(self, context):
    self.layout.operator(AAEExportLegacy.bl_idname, text="Adobe After Effects 6.0 Keyframe Data")

def register():
    for class_ in classes:
        bpy.utils.register_class(class_)
        
    bpy.types.Screen.AAEExportSettings = bpy.props.PointerProperty(type=AAEExportSettings)
        
    bpy.types.TOPBAR_MT_file_export.append(register_export_legacy)

def unregister():
    bpy.types.TOPBAR_MT_file_export.remove(register_export_legacy)
    
    del bpy.types.Screen.AAEExportSettings
    
    for class_ in classes:
        bpy.utils.unregister_class(class_)

if __name__ == "__main__":
    register()
#    unregister() 
