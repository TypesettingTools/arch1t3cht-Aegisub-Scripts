bl_info = {
    "name": "Export: Adobe After Effects 6.0 Keyframe Data (Power Pin)",
    "description": "Export a plane track to Adobe After Effects 6.0 compatible files",
    "author": "arch1t3cht",
    "version": (0, 1, 0),
    "blender": (3, 2, 0),
    "location": "File > Export > Adobe After Effects 6.0 Keyframe Data (Power Pin)",
    "warning": "",
    "category": "Import-Export",
}

import itertools
import bpy

dataname = bl_info["location"].split(" > ")[2]

def corners_from_marker(marker):
    if marker.__class__.__name__ == "MovieTrackingPlaneMarker":
        return [list(c) for c in marker.corners]
    elif marker.__class__.__name__ == "MovieTrackingMarker":
        return [[marker.co[i] + cv for i, cv in enumerate(c)] for c in marker.pattern_corners]


def write_files(prefix, context):
    scene = context.scene
    fps = scene.render.fps / scene.render.fps_base

    for clipno, clip in enumerate(bpy.data.movieclips):
        for trackno, track in enumerate(itertools.chain(clip.tracking.tracks, clip.tracking.plane_tracks)):
            with open("{0}_c{1:02d}_{2}{3:02d}_{4}.txt".format(prefix, clipno, "planetrack" if track.__class__.__name__ == "MovieTrackingPlaneTrack" else "track", trackno, track.name.lower().replace(" ", "_")), "w") as f:
                f.write("Adobe After Effects 6.0 Keyframe Data\n\n")
                f.write("\tUnits Per Second\t{0:.3f}\n".format(fps))
                f.write("\tSource Width\t{0}\n".format(clip.size[0]))
                f.write("\tSource Height\t{0}\n".format(clip.size[1]))
                f.write("\tSource Pixel Aspect Ratio\t1\n")
                f.write("\tComp Pixel Aspect Ratio\t1\n")

                corners = [corners_from_marker(track.markers.find_frame(frameno)) for frameno in range(clip.frame_start, clip.frame_start + clip.frame_duration)]

                for pini, corneri in [(2, 3), (3, 2), (4, 0), (5, 1)]:
                    f.write(f"\nEffects\tCC Power Pin #1\tCC Power Pin-000{pini}\n")
                    f.write("\tFrame\tX pixels\tY pixels\n")

                    for i, plane in enumerate(corners):
                        corner = plane[corneri]
                        x = corner[0] * clip.size[0]
                        y = (1 - corner[1]) * clip.size[1]
                        f.write(f"\t{i}\t{x:.3f}\t{y:.3f}\n")

                f.write("\nEnd of Keyframe Data\n")

    return {'FINISHED'}

from bpy_extras.io_utils import ExportHelper
from bpy.props import StringProperty

class ExportAFXPP(bpy.types.Operator, ExportHelper):
    """Export a plane track to Adobe After Effects 6.0 compatible files"""
    bl_idname = "export.afxpp"
    bl_label = f"Export to {dataname}"
    filename_ext = ""
    filter_glob = StringProperty(default="*", options={'HIDDEN'})

    def execute(self, context):
        return write_files(self.filepath, context)

classes = (
    ExportAFXPP,
)

def menu_func_export(self, context):
    self.layout.operator(ExportAFXPP.bl_idname, text=dataname)


def register():
    from bpy.utils import register_class
    for cls in classes:
        register_class(cls)
    bpy.types.TOPBAR_MT_file_export.append(menu_func_export)

def unregister():
    from bpy.utils import unregister_class
    for cls in reversed(classes):
        unregister_class(cls)
    bpy.types.TOPBAR_MT_file_export.remove(menu_func_export)

if __name__ == "__main__":
    register()
