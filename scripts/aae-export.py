# Copyright (c) 2013, Martin Herkt
#
# Permission to use, copy, modify, and/or distribute this software for any
# purpose with or without fee is hereby granted, provided that the above
# copyright notice and this permission notice appear in all copies.
#
# THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES WITH
# REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY
# AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT,
# INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM
# LOSS OF USE, DATA OR PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE
# OR OTHER TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR
# PERFORMANCE OF THIS SOFTWARE.

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
import math, mathutils
from pathlib import Path

class AAEExportSettings(bpy.types.PropertyGroup):
    bl_label = "AAEExportSettings"
    bl_idname = "AAEExportSettings"
    
    do_also_export: bpy.props.BoolProperty(name="Auto export",
                                           description="Automatically export the selected track to file while copying",
                                           default=True)
    do_do_not_overwrite: bpy.props.BoolProperty(name="Do not overwrite",
                                                description="Generate unique files every time",
                                                default=False)

class AAEExportExportAll(bpy.types.Operator):
    bl_label = "Export"
    bl_description = "Export all tracking markers and plane tracks to AAE files next to the original movie clip"
    bl_idname = "movieclip.aae_export_export_all"

    def execute(self, context):
        clip = context.edit_movieclip
        settings = context.screen.AAEExportSettings

        for track in clip.tracking.tracks:
            AAEExportExportAll._export_to_file(clip, track, AAEExportExportAll._generate(clip, track), None, settings.do_do_not_overwrite)

        for plane_track in clip.tracking.plane_tracks:
            AAEExportExportAll._export_to_file(clip, plane_track, AAEExportExportAll._generate(clip, plane_track), None, settings.do_do_not_overwrite)
        
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

        for marker in track.markers:
            if not 0 < marker.frame <= clip.frame_duration:
                continue
            if marker.mute:
                continue

            if marker.__class__.__name__ == "MovieTrackingMarker":
                coords = marker.co
                corners = marker.pattern_corners
            else: # "MovieTrackingPlaneMarker"
                c = marker.corners
                coords = mathutils.geometry.intersect_line_line_2d(c[0], c[2], c[1], c[3])
                corners = [mathutils.Vector(p) - coords for p in c]
            
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

            p1 = mathutils.Vector(corners[0])
            p2 = mathutils.Vector(corners[1])
            mid = (p1 + p2) / 2
            diff = mid - mathutils.Vector((0,0))

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

        positions = "\n".join([posline.format(d[0], d[1], d[2]) for d in data]) + "\n\n"
        scales = "\n".join([scaleline.format(d[0], d[3], d[4]) for d in data]) + "\n\n"
        rotations = "\n".join([rotline.format(d[0], d[5]) for d in data]) + "\n\n"

        aae += "Anchor Point\n"
        aae += "\tFrame\tX pixels\tY pixels\tZ pixels\n"
        aae += positions

        aae += "Position\n"
        aae += "\tFrame\tX pixels\tY pixels\tZ pixels\n"
        aae += positions

        aae += "Scale\n"
        aae += "\tFrame\tX percent\tY percent\tZ percent\n"
        aae += scales

        aae += "Rotation\n"
        aae += "\tFrame Degrees\n"
        aae += rotations

        aae += "End of Keyframe Data\n"

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
                    coords = mathutils.geometry.intersect_line_line_2d(marker.corners[0], marker.corners[2], marker.corners[1], marker.corners[3])
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

        aae = AAEExportExportAll._generate(clip, context.selected_movieclip_tracks[0])
        
        AAEExportExportAll._copy_to_clipboard(context, aae)
        if settings.do_also_export:
            AAEExportExportAll._export_to_file(clip, context.selected_movieclip_tracks[0], aae, None, settings.do_do_not_overwrite)
        
        return {'FINISHED'}

class AAEExportCopyPlaneTrack(bpy.types.Operator):
    bl_label = "Copy"
    bl_description = "Copy selected plane track as AAE data to clipboard"
    bl_idname = "movieclip.aae_export_copy_plane_track"

    def execute(self, context):
        clip = context.edit_movieclip
        settings = context.screen.AAEExportSettings

        aae = AAEExportExportAll._generate(clip, clip.tracking.plane_tracks[0])

        AAEExportExportAll._copy_to_clipboard(context, aae)
        if settings.do_also_export:
            AAEExportExportAll._export_to_file(clip, clip.tracking.plane_tracks[0], aae, None, settings.do_do_not_overwrite)
        
        return {'FINISHED'}
    
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
        column.label(text="All tracks")
        column.prop(settings, "do_also_export")
        column.prop(settings, "do_do_not_overwrite")
        
        row = layout.row()
        row.scale_y = 2
        row.enabled = len(context.edit_movieclip.tracking.tracks) >= 1
        row.operator("movieclip.aae_export_export_all")

    @classmethod
    def poll(cls, context):
        return context.edit_movieclip is not None

class AAEExportLegacy(bpy.types.Operator, bpy_extras.io_utils.ExportHelper):
    """Export motion tracking markers to Adobe After Effects 6.0 compatible files"""
    bl_label = "Export to Adobe After Effects 6.0 Keyframe Data"
    bl_idname = "export.aae_export_legacy"
    filename_ext = ""
    filter_glob = bpy.props.StringProperty(default="*", options={'HIDDEN'})

    def execute(self, context):
        # This is broken but I don't want to fix...
        if len(bpy.data.movieclips) != 1:
            raise ValueError("The legacy export method only allows one clip to be loaded into Blender at a time. You can either try the new export interface at „Clip Editor > Tools > Solve > AAE Export“ or use „File > New“ to create a new Blender file.")
        clip = bpy.data.movieclips[0]
        settings = context.screen.AAEExportSettings

        for track in clip.tracking.tracks:
            AAEExportExportAll._export_to_file(clip, track, AAEExportExportAll._generate(clip, track), self.filepath, settings.do_do_not_overwrite)

        for plane_track in clip.tracking.plane_tracks:
            AAEExportExportAll._export_to_file(clip, track, AAEExportExportAll._generate(clip, plane_track), self.filepath, settings.do_do_not_overwrite)

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
