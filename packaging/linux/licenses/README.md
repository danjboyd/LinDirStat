# Runtime license texts

The license files of the GNUstep runtime the Linux AppImage bundles, copied
from upstream so `scripts/package-stage.sh` can write the AppImage's notices
without local checkouts of those projects (the gnustep-cli-new install does
not carry them).

| File | Upstream |
| --- | --- |
| `libs-base-COPYING.LIB` | gnustep/libs-base `COPYING.LIB` (last changed in `4b33151`) |
| `libs-gui-COPYING.LIB` | gnustep/libs-gui `COPYING.LIB` (`7afdd32`) |
| `libs-back-COPYING.LIB` | gnustep/libs-back `COPYING.LIB` (`250ebdf`; the same at the pinned `bf3b3ce`) |
| `libobjc2-COPYING` | gnustep/libobjc2 `COPYING` (`07758fe`) |
| `libdispatch-LICENSE` | swiftlang/swift-corelibs-libdispatch `LICENSE` (`9ccd785`) |
| `libs-back-COPYING` | gnustep/libs-back `COPYING` (`f3805b1`): the GPL-3.0 text, which libs-back's URW fonts (`Fonts/Helvetica.nfont`) refer to |
| `adwaita-icon-theme-LGPL-3` | The LGPL-3.0 text (Debian's `/usr/share/common-licenses/LGPL-3`), for the Adwaita symbolic icons in `Source/Resources/Icons` (both packages) |
| `appimage-type2-runtime-LICENSE` | AppImage/type2-runtime `LICENSE` (`4cac606`), the runtime appimagetool puts at the front of the AppImage |
