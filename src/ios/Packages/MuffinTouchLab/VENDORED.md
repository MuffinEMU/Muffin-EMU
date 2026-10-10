# MuffinTouchLab (vendored)

[![MuffinEMU](https://img.shields.io/badge/MuffinEMU-Vendored-E5652E)](../../../../README.md) [Back to the README](../../../../README.md)

The on-screen control schemes offered under Settings > On-screen Controls > Control style
(Zone, Float, Adaptive, Frame, Racing). Vendored from MuffinEMU-TouchLab at commit
`fbc9ba9` on its `feature/racing-mode` branch (not yet on its main), copied by hand with the
same steps as `tools/export-to-muffinemu.sh`, which refuses a commit that isn't on main. The
next export from main will carry these files once that branch is merged there.

> [!WARNING]
> Do not edit these files here. Change them in MuffinEMU-TouchLab, run its checks, and
> re-export - otherwise the next export silently overwrites the change.

Checks: `swift run --package-path src/ios/Packages/MuffinTouchLab touchlab-check`
