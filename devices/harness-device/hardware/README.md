# Harness device hardware

Mechanical and electrical design files for the harness-device.

## PCB (`pcb/`)

Designed in EasyEDA Pro.

| File | Contents |
|---|---|
| `ProPrj_Harness_1.75_AMOLED.epro2` | EasyEDA Pro project (schematic + PCB layout source) |
| `SCH_SCH_Harness_1.75.pdf` | Schematic export (PDF) |
| `production/Gerber_PCB_Harness/` | Gerbers + drill files for fabrication (RS-274X / Excellon) |
| `production/BOM_Harness_1.75_AMOLED_PCB_Harness_1.75.xlsx` | Bill of materials |
| `production/PickAndPlace_PCB_Harness.xlsx` | Pick-and-place (CPL) data for assembly |

Open the `.epro2` project in [EasyEDA Pro](https://pro.easyeda.com/) to edit the schematic/layout.

## 3D (`3d/`)

Formats are STEP (`.step`), suitable for import into any major CAD tool (FreeCAD, SolidWorks,
Fusion 360, etc.).

| File | Part |
|---|---|
| `Housing.step` | Main enclosure housing |
| `Iron_base.step` | Iron counterweight block (keeps the device from tipping/sliding on a desk) |
| `USB_clamp.step` | Clamp that holds the USB-C port PCB in place |
| `Button.step` | Physical button cap/actuator |

`Harness.step` (the full assembled harness, ~120 MB) is not included in this commit — it exceeds
GitHub's 100 MB per-file limit for a normal push. It will follow in a separate change (via Git LFS
or a release asset).
