<!--
  HOW TO ADD A VIDEO: upload the clip to GitHub (drag it into any issue or pull request comment box,
  or into the web editor for this file), then paste the resulting
  https://github.com/user-attachments/assets/... URL on its own line where the matching
  "VIDEO:" comment is below. A user-attachments URL on a line by itself embeds as a video player on GitHub.
  Replace that whole VIDEO comment with the URL when you paste it.
-->

<div align="center">

# MuffinEMU Game Compatibility

**Games reported working in MuffinEMU, the free Wii U emulator for iPhone and iPad.**

[![Games listed](https://img.shields.io/badge/games%20listed-10-E5652E?style=for-the-badge&labelColor=1d1d1f)](#compatible-games)
[![Report a game](https://img.shields.io/badge/report%20a%20game-open%20an%20issue-E5652E?style=for-the-badge&labelColor=1d1d1f&logo=github&logoColor=white)](https://github.com/MuffinEMU/Muffin-EMU/issues/new/choose)
[![Back to README](https://img.shields.io/badge/back%20to-README-E5652E?style=for-the-badge&labelColor=1d1d1f)](README.md)

</div>

---

This page lists games that players have reported running in MuffinEMU. Reports come from players of MuffinEMU, and from players of EspressU, an app built on the same emulator code, in October 2026. Frame rates depend on the device, on JIT, on graphic packs and on the version. It is also on the website: [muffinemu.github.io/MuffinEMU/docs/compatibility.html](https://muffinemu.github.io/MuffinEMU/docs/compatibility.html). Compatibility can vary between devices, so a game that works on one device is not guaranteed to work on every device.

> [!NOTE]
> This list does not guarantee perfect performance or full gameplay compatibility. Performance, graphics, stability, and overall playability may vary depending on your device and MuffinEMU version. Device-specific limits (on-screen controls, Vulkan on A12Z-class iPads, older GPUs) are listed under [Known issues in the README](README.md#status).

## Status legend

| Status | Meaning |
|---|---|
| **Runs well** | Reported at a steady 60 fps or close to it on at least one device. |
| **Playable** | Reported playable; frame rate or small problems vary. |
| **Runs with issues** | Starts and plays, with a clear problem such as audio or graphics. |
| **Doesn't work yet** | Reported not working. |
| **Reported working** | Reported working on at least one device, without more detail yet. |

## Compatible games

| Game | Status | Details |
|---|---|---|
| **Mario Kart 8** | Runs well | 60 fps on an iPhone 16. 59 to 60 fps on an iPad. Earlier build: 20 to 25 fps on an A16 iPad without graphic packs. Full report: [Mario Kart 8 compatibility report](https://github.com/MuffinEMU/Muffin-EMU/blob/main/docs/compat/mario-kart-8.md). |
| **Super Mario 3D World** | Runs well | 60 fps on an iPhone 13 with JIT. |
| **Splatoon** | Runs well | 60 fps on an iPhone 12. Another player reports 15 to 30 fps (device not stated). The Wii U version is light on the GPU, so it is a good first game to try. |
| **The Legend of Zelda: Breath of the Wild** | Playable | Runs really well on an iPhone 15 Pro. 23 to 30 fps with the FPS++ graphic pack on an iPhone 13 Pro Max. One player could not load a save the next day (black screen) on an iPhone 13 Pro Max. A12Z iPad Pro (2026-10-30 logs): 60 fps in the open world, about 26 fps in towns, on one emulated core; memory sits near the iOS limit, so long sessions can be killed; loads slowed over hours of play and the ground could vanish after a shrine or the lock screen, both addressed in the next release; keep Emulate missing effects off, this game uses none. |
| **Bayonetta** | Runs with issues | Plays, but the audio is delayed and the frame rate is unstable. Reported on an earlier build. |
| **Call of Duty: Black Ops II** | Runs with issues | Loads and plays. The graphics side still needs work. One report with a video. |
| **Need for Speed: Most Wanted** | Doesn't work yet | Reported not working on an iPhone 15 Pro with JIT on and keys set up. One report, not resolved yet. |
| **New Super Mario Bros. U** | Reported working | Reported working. |
| **Captain Toad: Treasure Tracker** | Reported working | Reported working. |
| **The Legend of Zelda: The Wind Waker HD** | Reported working | Reported working. |

Videos for each game can be added below as they are recorded.

### New Super Mario Bros. U

**Status:** Reported working.

<!-- VIDEO: New Super Mario Bros. U. Paste an uploaded GitHub video URL (https://github.com/user-attachments/assets/...) on its own line here. -->

### Super Mario 3D World

**Status:** Reported working.

<!-- VIDEO: Super Mario 3D World. Paste an uploaded GitHub video URL (https://github.com/user-attachments/assets/...) on its own line here. -->

### Mario Kart 8

**Status:** Reported working. Area-by-area status, evidence and device test steps: [Mario Kart 8 compatibility report](docs/compat/mario-kart-8.md).

<!-- VIDEO: Mario Kart 8. Paste an uploaded GitHub video URL (https://github.com/user-attachments/assets/...) on its own line here. -->

### Splatoon

**Status:** Reported working. Base game.

<!-- VIDEO: Splatoon. Paste an uploaded GitHub video URL (https://github.com/user-attachments/assets/...) on its own line here. -->

### Captain Toad: Treasure Tracker

**Status:** Reported working.

<!-- VIDEO: Captain Toad: Treasure Tracker. Paste an uploaded GitHub video URL (https://github.com/user-attachments/assets/...) on its own line here. -->

### The Legend of Zelda: The Wind Waker HD

**Status:** Reported working.

<!-- VIDEO: The Legend of Zelda: The Wind Waker HD. Paste an uploaded GitHub video URL (https://github.com/user-attachments/assets/...) on its own line here. -->

## Contributing

Have another game working in MuffinEMU, or tested one of these games on a different device? The quickest way to share it is #game-tests on the [MuffinEMU Discord](https://discord.gg/6FG8k29Q5); you can also open an issue as below.

**Help expand the compatibility list!** [Open a GitHub issue](https://github.com/MuffinEMU/Muffin-EMU/issues/new/choose) with the following information. If the game crashes or misbehaves, use the *Bug report* form.

| | What to include |
|---|---|
| **Game** | Title and region/version, if known. |
| **Device** | Your iPhone or iPad model. |
| **MuffinEMU version** | The version or build you tested. |
| **Results** | Does the game boot, reach gameplay, and run reliably? |
| **Notes** | Any graphical issues, crashes, performance problems, or other observations. |

Reports from different devices help build a more accurate picture of MuffinEMU's compatibility. Please share what you've tested, including any limitations you encountered.
