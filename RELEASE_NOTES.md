## What changed

- Run one CPU core by default, and stop sleeping the cores when hot
- Release notes now say what actually changed in each version, instead of repeating the install instructions.

MuffinEMU, Wii U emulation for iPhone and iPad, built from commit a0560b51695ea8b30efba3b42ed016f8f265c8c3.

**`MuffinEMU.ipa`** - SideStore / AltStore / LiveContainer. Unsigned; they re-sign
with your own Apple ID at install.

**`MuffinEMU-fakesigned.ipa`** - TrollStore or jailbroken only, with the JIT
entitlements embedded.

The recompiler needs a JIT enabler (StikJIT, SideStore, LiveContainer) and the
"Use the recompiler (JIT)" switch in Settings; without both it runs the
interpreter. `MuffinEMU.app.dSYM.zip` is only needed to symbolicate a crash report.

MuffinEMU is built on Cemu. Some MeloCafe cores and bug fixes have been brought over to MuffinEMU.

**Full changelog**: https://github.com/kiddreads/MuffinEMU/compare/v4.1...v4.2
