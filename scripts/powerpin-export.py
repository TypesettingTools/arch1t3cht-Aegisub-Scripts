# Copyright (c) 2022 arch1t3cht

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
    "name": "Adobe After Effects 6.0 Keyframe Data Export (Power Pin)",
    "description": "Export plane track to Aegisub-Motion compatible AAE file",
    "author": "arch1t3cht, Akatsumekusa",
    "version": (0, 1, 1),
    "support": "COMMUNITY",
    "category": "Video Tools",
    "blender": (3, 2, 0),
    "location": "Clip Editor > Tools > Solve > AAE Export (Power Pin)",
    "warning": "",
    "doc_url": "https://github.com/arch1t3cht/Aegisub-Scripts#other-scripts",
    "tracker_url": "https://github.com/arch1t3cht/Aegisub-Scripts/issues"
}

import itertools
import bpy
import bpy_extras.io_utils
from datetime import datetime
import mathutils.geometry
from pathlib import Path

class PowerPinExportSettings(bpy.types.PropertyGroup):
    bl_label = "PowerPinExportSettings"
    bl_idname = "PowerPinExportSettings"
    
    do_do_not_overwrite: bpy.props.BoolProperty(name="Do not overwrite",
                                                description="Generate unique files every time",
                                                default=False)
    do_copy_to_clipboard: bpy.props.BoolProperty(name="Copy to clipboard",
                                                 description="Copy the Power Pin data to clipboard.\nThis option will only work either when there is only one plane track on the clip, or there is only one plane track selected",
                                                 default=True)

class PowerPinExportExport(bpy.types.Operator):
    bl_label = "Export"
    bl_description = "Export plane track to Power Pin AAE files next to the original movie clip"
    bl_idname = "movieclip.power_pin_export_export"

    def execute(self, context):
        clip = context.edit_movieclip
        settings = context.screen.PowerPinExportSettings

        plane_tracks = 0 # Please enjoy the confusion
        selected_plane_tracks = []
        for plane_track in context.edit_movieclip.tracking.plane_tracks:
            plane_tracks += 1
            if plane_track.select == True:
                selected_plane_tracks.append(plane_track)

        if plane_tracks > 1 and len(selected_plane_tracks) != 1:
            do_copy_to_clipboard = False
        else:
            do_copy_to_clipboard = settings.do_copy_to_clipboard

        if plane_tracks > 1 and len(selected_plane_tracks) != plane_tracks and len(selected_plane_tracks) != 0:
            plane_tracks = selected_plane_tracks # Same as above
        else:
            plane_tracks = clip.tracking.plane_tracks # Same ww

        for plane_track in plane_tracks:
            power_pin = PowerPinExportExport._generate(clip, plane_track)

            if do_copy_to_clipboard:
                PowerPinExportExport._copy_to_clipboard(context, power_pin)
            PowerPinExportExport._export_to_file(clip, plane_track, power_pin, None, settings.do_do_not_overwrite)
        
        return {'FINISHED'}

    @staticmethod
    def _generate(clip, track):
        """
        Parameters
        ----------
        clip : bpy.types.MovieClip
        track : bpy.types.MovieTrackingTrack or MovieTrackingPlaneTrack

        Returns
        -------
        power_pin : str
        """
        power_pin = "Adobe After Effects 6.0 Keyframe Data\n\n"
        power_pin += "\tUnits Per Second\t{0:.3f}\n".format(clip.fps)
        power_pin += "\tSource Width\t{0}\n".format(clip.size[0])
        power_pin += "\tSource Height\t{0}\n".format(clip.size[1])
        power_pin += "\tSource Pixel Aspect Ratio\t1\n"
        power_pin += "\tComp Pixel Aspect Ratio\t1\n"

        frames = []
        corners = []
        for marker in track.markers:
            if not 0 < marker.frame <= clip.frame_duration:
                continue
            if marker.mute:
                continue

            frames.append(marker.frame)
            corners.append([list(c) for c in marker.corners])
        
        for pini, corneri in [(2, 3), (3, 2), (4, 0), (5, 1)]:
            power_pin += f"\nEffects\tCC Power Pin #1\tCC Power Pin-000{pini}\n"
            power_pin += "\tFrame\tX pixels\tY pixels\n"

            for i, plane in enumerate(corners):
                corner = plane[corneri]
                x = corner[0] * clip.size[0]
                y = (1 - corner[1]) * clip.size[1]
                power_pin += f"\t{frames[i]}\t{x:.3f}\t{y:.3f}\n"

        power_pin += "\nEnd of Keyframe Data\n"

        return power_pin

    @staticmethod
    def _export_to_file(clip, track, power_pin, prefix, do_do_not_overwrite):
        """
        Parameters
        ----------
        clip : bpy.types.MovieClip
        track : bpy.types.MovieTrackingTrack or MovieTrackingPlaneTrack
        power_pin : str
            Likely coming from _generated().
        prefix : None or str
        do_do_not_overwrite : bool
            PowerPinExportSettings.do_do_not_overwrite.

        """
        coords = None
        for marker in track.markers:
            if not marker.mute:
                coords = mathutils.geometry.intersect_line_line_2d(marker.corners[0], marker.corners[2], marker.corners[1], marker.corners[3])
                coords = (coords[0] * clip.size[0], (1 - coords[1]) * clip.size[1])
                break

        if coords != None:
            p = Path(clip.filepath if not prefix else prefix)
            p = p.with_stem(p.stem + \
                            "[Plane Track][Power Pin]" + \
                            f"[({coords[0]:.0f}, {coords[1]:.0f})]" + \
                            (datetime.now().strftime("[%H%M%S %b %d]") if do_do_not_overwrite else "")) \
                 .with_suffix(".txt")
            with p.open(mode="w", encoding="utf-8", newline="\r\n") as f:
                f.write(power_pin)
                
    @staticmethod
    def _copy_to_clipboard(context, power_pin):
        """
        Parameters
        ----------
        context : bpy.context
        power_pin : str
            Likely coming from _generated().
            
        """
        context.window_manager.clipboard = power_pin

class PowerPinExport(bpy.types.Panel):
    bl_label = "AAE Export (PowerPin)"
    bl_idname = "SOLVE_PT_power_pin_export"
    bl_space_type = "CLIP_EDITOR"
    bl_region_type = "TOOLS"
    bl_category = "Solve"

    def draw(self, context):
        layout = self.layout
        layout.use_property_split = True
        layout.use_property_decorate = False
        
        settings = context.screen.PowerPinExportSettings

        plane_tracks = 0
        selected_plane_tracks = 0
        for plane_track in context.edit_movieclip.tracking.plane_tracks:
            plane_tracks += 1
            if plane_track.select == True:
                selected_plane_tracks += 1

        column = layout.column()
        if plane_tracks <= 1:
            column.label(text="Plane track")
        else:
            if selected_plane_tracks == 0:
                column.label(text="Plane track")
            else:
                column.label(text="Selected plane track")
        column.prop(settings, "do_do_not_overwrite")
        row = column.row()
        if plane_tracks <= 1:
            row.enabled = True
        else:
            if selected_plane_tracks == 1:
                row.enabled = True
            else:
                row.enabled = False
        row.prop(settings, "do_copy_to_clipboard")
        
        row = layout.row()
        row.scale_y = 2
        if plane_tracks == 0:
            row.enabled = False
        else:
            row.enabled = True
        row.operator("movieclip.power_pin_export_export")

    @classmethod
    def poll(cls, context):
        return context.edit_movieclip is not None

class PowerPinExportLegacy(bpy.types.Operator, bpy_extras.io_utils.ExportHelper):
    """Export a plane track to Adobe After Effects 6.0 compatible files"""
    bl_label = "Export to Adobe After Effects 6.0 Keyframe Data (Power Pin)"
    bl_idname = "export.power_pin_export_legacy"
    filename_ext = ""
    filter_glob = bpy.props.StringProperty(default="*", options={'HIDDEN'})

    def execute(self, context):
        # This is broken but I don't want to fix...
        if len(bpy.data.movieclips) != 1:
            raise ValueError("The legacy export method only allows one clip to be loaded into Blender at a time. You can either try the new export interface at „Clip Editor > Tools > Solve > AAE Export (Power Pin)“ or use „File > New“ to create a new Blender file.")
        clip = bpy.data.movieclips[0]
        settings = context.screen.PowerPinExportSettings

        for plane_track in clip.tracking.plane_tracks:
            PowerPinExportExport._export_to_file(clip, track, PowerPinExportExport._generate(clip, plane_track), self.filepath, settings.do_do_not_overwrite)     

classes = (PowerPinExportSettings,
           PowerPinExportExport,
           PowerPinExport,
           PowerPinExportLegacy)
           
def register_export_legacy(self, context):
    self.layout.operator(PowerPinExportLegacy.bl_idname, text="Adobe After Effects 6.0 Keyframe Data (Power Pin)")

def register():
    for class_ in classes:
        bpy.utils.register_class(class_)
        
    bpy.types.Screen.PowerPinExportSettings = bpy.props.PointerProperty(type=PowerPinExportSettings)
        
    bpy.types.TOPBAR_MT_file_export.append(register_export_legacy)

def unregister():
    bpy.types.TOPBAR_MT_file_export.remove(register_export_legacy)
    
    del bpy.types.Screen.PowerPinExportSettings
    
    for class_ in classes:
        bpy.utils.unregister_class(class_)

if __name__ == "__main__":
    register()
#    unregister() 



