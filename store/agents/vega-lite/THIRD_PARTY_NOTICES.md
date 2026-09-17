# Third-party notices

This harness is a wrapper. Everything that draws a chart belongs to its upstream authors, and their
licences travel with it. Versions are pinned in `package-lock.json` with SHA-512 integrity and
installed into the package by `toolchain/setup.sh`; nothing is installed globally.

| Component | Version | Licence | Used for | Licence text |
|---|---|---|---|---|
| [Vega-Lite](https://vega.github.io/vega-lite/) | 6.4.3 | BSD-3-Clause | the chart grammar, its schema and compiler | [LICENSE-vega](LICENSE-vega) |
| [Vega](https://vega.github.io/vega/) | 6.4.0 | BSD-3-Clause | rendering charts to SVG, in Node and in the pane | [LICENSE-vega](LICENSE-vega) |
| [Vega-Embed](https://github.com/vega/vega-embed) | 7.2.0 | BSD-3-Clause | the interactive chart in the pane and in exported HTML | [LICENSE-vega](LICENSE-vega) |
| [Ajv](https://ajv.js.org) | 8.18.0 | MIT | validating a chart against the pinned Vega-Lite schema | in the installed package |
| [ajv-formats](https://github.com/ajv-validator/ajv-formats) | 3.0.1 | MIT | schema string formats | in the installed package |
| [resvg-wasm](https://github.com/yisibl/resvg-js) | 2.6.2 | MPL-2.0 | rasterising chart snapshots offline, as WebAssembly | in the installed package |
| [opentype.js](https://github.com/opentypejs/opentype.js) | 2.0.0 | MIT | measuring text with the real font, so layout matches the raster | in the installed package |
| [Inter](https://github.com/rsms/inter), via [@expo-google-fonts/inter](https://github.com/expo/google-fonts) | Inter 4 (package 0.4.2) | SIL OFL 1.1 | the typeface in chart snapshots | [LICENSE-inter](LICENSE-inter) |

The Vega, Vega-Lite and Vega-Embed browser bundles are also embedded verbatim in the self-contained
HTML that `vl export` writes, together with their credit and licence notice.

The harness itself — `AGENTS.md`, the skill, the toolchain scripts, the viewer — is MIT, see
[LICENSE](LICENSE).
