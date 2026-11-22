from pathlib import Path

app = Path(defines["app"])
format = "UDZO"
filesystem = "HFS+"
files = [str(app)]
symlinks = {"Applications": "/Applications"}
icon = str(app / "Contents/Resources/AppIcon.icns")
background = defines["background"]
window_rect = ((180, 180), (720, 460))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
include_icon_view_settings = True
include_list_view_settings = False
arrange_by = None
icon_size = 112
text_size = 14
label_pos = "bottom"
icon_locations = {app.name: (195, 257), "Applications": (525, 257)}
