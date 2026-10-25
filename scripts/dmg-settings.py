# dmgbuild layout for the Bornolipi disk image: the app on the left, Applications on the right, an
# arrow between them. Used by scripts/make-dmg.sh; values come from -D app=... -D background=...
import os

app = defines["app"]
files = [app]
symlinks = {"Applications": defines.get("applications", "/Applications")}  # system-path-ok: release default; DMG_TEST=1 points it at a scratch folder
format = "UDZO"
background = defines["background"]
window_rect = ((200, 160), (600, 380))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
icon_size = 112
text_size = 13
icon_locations = {os.path.basename(app): (160, 190), "Applications": (440, 190)}
hide_extension = [os.path.basename(app)]
