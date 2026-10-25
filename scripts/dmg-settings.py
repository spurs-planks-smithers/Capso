# Fork: dmgbuild settings for the Nextshot disk image.
#
# dmgbuild writes the Finder view file (.DS_Store) itself. create-dmg asked
# Finder to lay out the window, and that failed on a Mac where Finder opens
# every window as a tab: the background picture never reached the image
# (2026-10-25).
#
# scripts/release-notarized.sh passes the paths:
#   dmgbuild -s scripts/dmg-settings.py -D app=<Nextshot.app> -D background=<tiff> <volume name> <out.dmg>
# The icon centers must match scripts/brand/make_dmg_background.swift.
import os.path

app = defines["app"]  # noqa: F821 (dmgbuild provides defines)
app_name = os.path.basename(app)

format = "UDZO"
filesystem = "HFS+"

files = [app]
symlinks = {"Applications": "/Applications"}
hide_extensions = [app_name]

# The volume icon in the Finder sidebar and on the desktop.
app_icon = os.path.join(app, "Contents", "Resources", "Nextshot.icns")
if os.path.exists(app_icon):
    icon = app_icon

background = defines["background"]  # noqa: F821
window_rect = ((200, 120), (660, 400))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False

arrange_by = None
show_icon_preview = False
label_pos = "bottom"
text_size = 13
icon_size = 128
icon_locations = {
    app_name: (170, 190),
    "Applications": (490, 190),
}
