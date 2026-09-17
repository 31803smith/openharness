# Harness device hardware

Mechanical design files for the harness-device enclosure. Formats are STEP (`.step`), suitable for
import into any major CAD tool (FreeCAD, SolidWorks, Fusion 360, etc.).

PCB/schematic sources are not included yet.

## 3D (`3d/`)

| File | Part |
|---|---|
| `Housing.step` | Main enclosure housing |
| `Iron_base.step` | Base/stand plate |
| `USB_clamp.step` | USB cable strain-relief clamp |
| `Button.step` | Physical button cap/actuator |

`Harness.step` (the full assembled harness, ~120 MB) is not included in this commit — it exceeds
GitHub's 100 MB per-file limit for a normal push. It will follow in a separate change (via Git LFS
or a release asset).
