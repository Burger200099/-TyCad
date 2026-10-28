#!/bin/sh
# Builds the program with the Free Pascal compiler and the Lazarus LCL (GTK2); the executable goes to ./bin/schematic.
# Set LAZ to your Lazarus directory if it is not the Debian/Ubuntu one. Printing needs the Printer4Lazarus and CairoCanvas packages (compiled units under components/).
# (Lazarus users: open schematic.lpi; it has the same paths and writes to ./bin as well.)
LAZ=${LAZ:-/usr/lib/lazarus/3.0}
HERE=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$HERE/bin" "$HERE/lib"
exec fpc -MObjFPC -Scgi -O1 -Xs -dLCL -dLCLgtk2 \
  -Fu"$HERE/src" -Fu"$HERE/src/comp" -Fu"$HERE/src/forms" -Fu"$HERE/src/frames" \
  -Fu"$LAZ/lcl/units/x86_64-linux/gtk2" -Fu"$LAZ/lcl/units/x86_64-linux" \
  -Fu"$LAZ/components/lazutils/lib/x86_64-linux" \
  -Fu"$LAZ/components/printers/lib/x86_64-linux/gtk2" -Fu"$LAZ/components/cairocanvas/lib/x86_64-linux/gtk2" \
  -FU"$HERE/lib" -FE"$HERE/bin" "$HERE/schematic.lpr" "$@"
