# Machine and capability inventory (M0.6)

Owned file: `docs/MACHINE_INVENTORY.md` (PLAN.md M0.6 — "Record machines/OS/controllers,
provisional renderer and capture methods. Inventory visual/audio/control review
capabilities"). The original inventory was produced by job
`9370f30f-fbd7-42cb-b401-a69ff4d7a2b5`; the current reconciliation was produced by job
`e3a69af4-46c2-461c-90ff-26a62922606f` and edited only this file. Read §0 first.

Baseline under inventory: `ee0ec19` ("Add initial Godot boot shell and smoke check").
Observed 2026-11-26, ~22:05–22:30 local time, on the single development Mac available to
this project.

This document records **observed facts and the commands that produced them**. It is not a
claim that anything was tested perceptually, on a real controller, or on any platform other
than the one described below. Where a fact is unknown it is listed as unknown; nothing here
upgrades an untested platform to a verified one.

No serial numbers, hardware UUIDs, Bluetooth addresses, account names, hostnames, signing
identities or credentials were collected or recorded. Values that were read while probing
but deliberately excluded from this file are noted in [Deliberately not recorded](#deliberately-not-recorded).

---

## 0. Reconciliation status (read this first)

This record was reconciled on 2026-11-27 by job `e3a69af4-46c2-461c-90ff-26a62922606f`
(LongCat 2.5 via Pi) against the specified input `94fd0ec` ("Record Python verifier safety
rechecks") and later committed evidence/review commits. The shared checkout advanced during
reconciliation; the latest commit read was `d8cd39c` ("Clarify Python pin evidence and
comparison results"). Between them sit review/evidence commits (`5f69dd2`, `2049beb`) and
one CI-tooling commit (`675ec1c`, owned elsewhere) whose committed evidence is read here.
The reconciliation edited only `docs/MACHINE_INVENTORY.md`; every fact below comes from
committed Git objects, committed evidence/review files, or the job reports they cite. It
performed no GUI/desktop, controller, audio, perceptual or cross-platform observation, and
it re-ran only the local identity spot-checks listed in §13.4.

**Sections 1–12 are the historical `ee0ec19` baseline** (observed 2026-11-26 by job
`9370f30f-fbd7-42cb-b401-a69ff4d7a2b5`, StepFun 5 Preview). They are preserved as history
with their attribution. Parenthetical *(updated, §13.x)* notes mark rows that later committed
evidence supersedes; §13 details each change. Nothing in §§1–12 is presented as a fresh
measurement by the reconciliation.

| Baseline (`ee0ec19`) | Committed evidence at the observed tip |
| --- | --- |
| 3D physics backend left at `DEFAULT` (§4) | `project.godot` sets `"Jolt Physics"` explicitly; interpolation on; 60 Hz. A committed contrast run shows `DEFAULT` behaved as **GodotPhysics3D**, so the baseline inference is superseded. `docs/evidence/jolt-settings.md` inventories all 32 Jolt settings (none overridden); warning open |
| `export_presets.cfg` absent; no package could be built (§2, §10.7) | `export_presets.cfg` tracked since `7b27c2f`, refined `245ee1d`/`8c6c928`: three placeholder desktop presets (macOS universal ad-hoc mode 1, Windows x86-64, Linux x86-64), unnotarized, exclude filter verified |
| Windowed boot-scene run only | Known launch: mode-1 macOS export + headless launch on `d4501e3` (job `e2ecffdc…`) exited 0 and reached the placeholder menu; ad-hoc, Gatekeeper-rejected. Earlier `7b27c2f` windowed mode-3 smoke remains history. Not windowed/current-mode/Intel/Windows/Linux |
| Templates present; no Windows/Linux host (§9) | Hosted Ubuntu runs built all three presets: runs 45924755902 (`245ee1d`), 45928824558 (`8c6c928`), and 45934306464 (`675ec1c`, four jobs green). Packages uploaded, never launched on Windows/Linux; named reviews keep the CI/export gate open |
| Local SHA-256 only; `expected_sha256` empty (§2, §10.6) | Editor binary and selected templates match publisher SHA-512/SHA-256 archives (`docs/evidence/godot-4.7.2-archive-verification.md`; pin files `upstream_verified=yes`). Four python.org 3.15.2 artifacts digest- and Sigstore-verified; installed Homebrew build not authenticated by those signatures |
| `gl_compatibility` provisional until M3 (§3) | Unchanged at the observed tip; still provisional; M3's representative tests remain authoritative. No new renderer measurement |
| No controller, no audio input, capture-mediated visual review (§5–§7) | Unchanged; hardware/perceptual gates remain open |

An export template, a cross-export or a hosted export is not a target-OS launch. The
baseline's untested platforms stay untested.

---

## 1. Host hardware and operating system

| Fact | Observed value | Command |
| --- | --- | --- |
| Operating system | macOS 27.0.1, build 26A434 | `sw_vers` |
| Kernel | Darwin 27.0.0, `xnu-13432.1.9~1/RELEASE_ARM64_T6041`, arm64 | `uname -a` |
| Machine | Mac Studio (model identifier `Mac16,9`) | `sysctl -n hw.model` |
| CPU | Apple M4 Max, 10 performance + 4 efficiency cores = 14 logical CPUs | `sysctl -n hw.perflevel0.physicalcpu hw.perflevel1.physicalcpu` |
| Memory | 38,654,705,664 bytes (36 GiB); swap 3 GiB total, ~1.7 GiB in use at the time | `sysctl -n hw.memsize`, `sysctl -n vm.swapusage` |
| GPU | Apple M4 Max integrated, 32 cores, Metal 4 | `system_profiler SPDisplaysDataType` |
| Display | One display: "JetKVM v1", 1920×1080, 60.00 Hz, main, mirror off. The host is a Mac Studio, which has no built-in panel, so the only display surface is this remote capture/KVM device | `system_profiler SPDisplaysDataType`, Godot `DisplayServer.screen_get_size()` → `(1920, 1080)`, `get_screen_count()` → `1` |
| Usable desktop area | Godot `DisplayServer.screen_get_usable_rect()` → origin (0, 30), size 1920×960 | Godot probe (see §6) |
| Storage | 460 GiB system volume, 194 GiB available | `df -h /` |

Consequences for the project:

* The host satisfies the Apple Silicon macOS target in `docs/TECHNICAL_DESIGN.md`
  ("Apple Silicon macOS 14 or later"); macOS 27.0.1 is newer than the stated minimum.
* The single 1920×1080 display is the only visual surface. BENCHMARKS' four-player 1080p
  layout is four 960×540 panels, which fits this display, but no four-panel run has been
  measured here (M3's job).
* The JetKVM device is a remote capture/KVM unit. Screen contents reach a remote viewer
  through it; whether it also carries audio back to a remote listener is **unknown**.

## 2. Engine and toolchain

| Fact | Observed value | Command |
| --- | --- | --- |
| Engine | Godot **4.7.2.stable.official.ed1daf0bf** (Standard, official build) | `godot --headless --version` |
| Binary | `/opt/homebrew/bin/godot` → `/Applications/Godot.app/Contents/MacOS/Godot` (351,312,912 bytes) | `readlink -f`, `ls -l` |
| Locally computed SHA-256 | `c7cccbf8fb143e34e02fd6521e09be2c2b974f0d5db080b19071c9c570718ccf` | `shasum -a 256` |
| Checksum provenance | **Not verified by this task.** `tools/ci/pin/engine.txt` leaves `expected_sha256` empty and `ci.sh capture --check` reports "engine checksum: NOT RECORDED". The value above is what this host has installed, computed locally. An independent verification record produced by the toolchain job (`docs/evidence/godot-4.7.2-archive-verification.md`, `tools/toolchain/pin/checksums.txt`) reports the same editor SHA-256, so the two agree; this task did not repeat the archive download. (Updated, §13.4: the editor binary and selected templates are publisher-checksummed in committed evidence; scope is selected files only.) | `tools/ci/pin/engine.txt`, `sh tools/ci/ci.sh capture --check` |
| Export templates | `~/Library/Application Support/Godot/export_templates/4.7.2.stable` (1.9 GiB), `version.txt` = `4.7.2.stable` | `ls`, `cat version.txt` |
| Template platforms present | macOS (`macos.zip`), Windows (release/debug × x86_32, x86_64, arm64), Linux (release/debug × x86_32, x86_64, arm32, arm64), Web, Android, iOS | directory listing |
| Python | Python 3.15.2 (`/opt/homebrew/bin/python3`) | `python3 --version` |
| Compiler | Xcode 27.2 SDK; Apple clang 21.0.0 (clang-2100.4.1.1), arm64-apple-darwin27.0.0 | `xcrun --show-sdk-version`, `clang --version` |
| Capture tools | `ffmpeg` 9.0.2, `ffprobe`, `screencapture`, `osascript` | `command -v` |
| Other | `cmake`, `jq`, `git` present | `command -v` |
| Codesigning | One Apple Development identity exists in the login keychain (details deliberately not recorded). No Developer ID / notarization credentials were inspected | `security find-identity -v -p codesigning` |

Consequences for the project:

* The installed engine matches the M0.1 pin (`major=4 minor=7 patch=2`, tag `4.7.2-stable`)
  and the templates match the engine. `ci.sh capture --check` reports
  `engine pin: 4.7.2.stable.official.ed1daf0bf matches pinned 4.7.2`.
* Templates for Windows and Linux exist locally, but a template file is not a launch test.
  `docs/TECHNICAL_DESIGN.md` requires native tests on each OS before any supported-platform
  claim; **no Windows or Linux host is available to this project**, so those remain untested.
* `export_presets.cfg` did not exist at this baseline, so `ci.sh export` could not build a
  package then. (Updated, §13.2: the file is now tracked with three placeholder desktop
  presets; they are not verified release packages.) That gap is closed as a file, not as a
  verified platform.

## 3. Renderer and GPU behaviour on this host

The project's provisional renderer is `gl_compatibility` (`project.godot`
`rendering/renderer/rendering_method`), provisional until M3 per PLAN.md and
`docs/TECHNICAL_DESIGN.md`.

Both candidate renderers were started with a real display driver on this host, each in a
scratch copy under `/tmp` (the checkout was not modified):

| Project renderer | Godot banner | `RenderingServer.get_video_adapter_name()` | `get_video_adapter_api_version()` |
| --- | --- | --- | --- |
| `gl_compatibility` (current) | `OpenGL API 4.1 Metal - 91.7 - Compatibility - Using Device: Apple - Apple M4 Max` | `Apple M4 Max` | `4.1 Metal - 91.7` |
| `forward_plus` | `Metal 4.0 - Forward+ - Using Device #0: Apple - Apple M4 Max (Apple9)` | `Apple M4 Max (Apple9)` | `4.0` |

Observed and only that: both renderers initialise, present frames and exit cleanly on this
GPU. **No frame-time, memory, draw-call or visual-quality comparison has been made.** M3's
representative one/four-view measurements remain the authority for renderer selection; the
`mobile` renderer was not started here and its behaviour on this host is unknown.

(Updated, §0: the committed project still sets `gl_compatibility`; it remains
provisional until M3, and this reconciliation made no new renderer measurement.)

## 4. Physics backend

| Fact | Observed value | Command |
| --- | --- | --- |
| 3D physics engine setting | `physics/3d/physics_engine` = `DEFAULT` **(updated: committed HEAD sets `"Jolt Physics"`, §13.1)** | Godot probe |
| Available backends (engine property hints) | `DEFAULT, Jolt Physics, GodotPhysics3D, Dummy` | `ProjectSettings.get_property_list()` |
| Jolt settings compiled in | Yes — `physics/jolt_physics_3d/simulation/...` and `.../queries/...` properties exist | same probe |
| Tick rate | 60 Hz (`physics/common/physics_ticks_per_second=60`), physics interpolation on | `project.godot`, probe |

At this baseline the project left the backend at `DEFAULT` and inferred Jolt from the engine
build. Committed evidence now shows `DEFAULT` behaved as **GodotPhysics3D** on this build, and
the committed project selects `"Jolt Physics"` explicitly (§13.1); the inference above is
superseded. `docs/evidence/jolt-settings.md` inventories all 32 Jolt-specific settings — none
overridden by the game — and the intermittent job-system warning remains open.

## 5. Controllers and input

| Fact | Observed value | Command |
| --- | --- | --- |
| Connected joypads (Godot) | **0**, in both a headless run and a windowed run | `Input.get_connected_joypads()` |
| USB controller devices | `system_profiler SPControllerDataType` empty; `ioreg -p IOUSB` lists only host controllers, a USB hub, and two storage devices | as shown |
| Bluetooth | Controller present and on, **no paired devices reported** | `system_profiler SPBluetoothDataType` |
| HID devices seen | `3Dconnexion Virtual Keyboard/Mouse/Data` (driver-level virtual devices, not gamepads) | `ioreg -r -c IOHIDDevice` |

Consequences for the project:

* **No real-controller verification is possible on this machine today.** M1.6, M3 and M5 all
  require gamepad evidence (four gamepads, and keyboard plus three gamepads); that evidence is
  blocked until a controller is supplied. Nothing in this document should be read as
  controller testing.
* Keyboard input reaches this session through the JetKVM remote link, so a locally attached
  keyboard cannot be distinguished from KVM-forwarded input. Whether a physical keyboard is
  attached at all is **unknown**; only that key events arrive.
* Synthetic input events can be generated for automated checks, but per PLAN.md they cannot
  replace hardware verification.

## 6. Visual review capability

* A windowed engine run works on this host: `res://scenes/boot.tscn` started, printed
  `[boot] handing off to menu: res://scenes/main_menu.tscn` and `[menu] placeholder menu
  shown`, and the window was visible on the single display.
* Still capture: `screencapture -x` produced a 1920×1080 RGBA PNG of the desktop while
  the game window was open (290 KB). Region capture also works: `screencapture -x -R 0,0,960,540`
  produced a 960×540 PNG.
* Video capture of the desktop: `ffmpeg -f avfoundation -framerate 60 -i 0:none -t 3`
  produced an h264 1920×1080 @ 60 FPS file, 180 frames, 2.98 s. The only avfoundation video
  device is `[0] Capture screen 0`.
* **No agent on this machine can see the screen directly.** Visual review by an agent is only
  possible through a capture that is then read as an image or video. A human reviewer looking
  at the display or at a capture remains the stronger path, and is required for the perceptual
  gates in BENCHMARKS ("an attractive isolated screenshot" does not close them).

## 7. Audio capability

| Fact | Observed value | Command |
| --- | --- | --- |
| Output devices (Godot) | `["Default", "JetKVM v1 (48)", "Mac Studio Speakers (86)"]` | `AudioServer.get_output_device_list()` |
| Output devices (system) | `JetKVM v1` (HDMI transport) and `Mac Studio Speakers` (built-in, default) | `system_profiler SPAudioDataType` |
| Mix rate | 48000 Hz; speaker mode stereo (0) | `AudioServer.get_mix_rate()`, `get_speaker_mode()` |
| Input devices | **None.** Godot lists `["Default"]` only, avfoundation lists no audio devices, and `SPAudioDataType` lists no input device | as shown |
| Capture pipeline audio track | Godot's movie writer emitted a 48 kHz PCM audio track alongside the video in the capture test below | `ffprobe` on the produced AVI |

Consequences for the project:

* The engine can output audio here, but **there is no microphone or line input**, so no agent
  can record the build's own output on this machine. Audio-quality review (music, effects, mix
  comfort, loop continuity) requires a human listener or an agent with an audio input path.
  This keeps the BENCHMARKS audio gate open regardless of what automated checks pass.
* `AudioDirector` is specified to use one explicit shared output; this host has two selectable
  outputs, which is enough to exercise device selection but not four-listener behaviour.

## 8. Bounded checks performed (evidence)

All engine probes ran **outside the checkout**, in `/tmp/rs-minv*` scratch directories, so no
repository file and no `.godot/` import cache in the shared checkout was written. The
temporary directories and their captures were deleted afterwards. My ownership is limited to
this file, so no capture was placed under the `docs/evidence/` directory that another job
created while this work was in progress (see §10 item 12).

| # | Check | Command (abridged) | Result |
| --- | --- | --- | --- |
| 1 | OS/CPU/RAM facts | `sw_vers`, `uname -a`, `sysctl -n hw.ncpu hw.physicalcpu hw.memsize hw.model hw.perflevel*.physicalcpu` | §1 |
| 2 | GPU/display/audio/controller facts | `system_profiler SPDisplaysDataType SPAudioDataType SPControllerDataType SPBluetoothDataType`, `ioreg -r -c IOHIDDevice`, `ioreg -p IOUSB` | §1, §5, §7 |
| 3 | Engine version | `godot --headless --version` | `4.7.2.stable.official.ed1daf0bf` |
| 4 | Engine checksum (local) | `shasum -a 256 /Applications/Godot.app/Contents/MacOS/Godot` | §2; agrees with the toolchain job's verified editor digest |
| 5 | Headless environment probe | `godot --headless --path /tmp/rs-minv --script probe.gd` | OS/model/processor/threads correct; video adapter empty and 0 screens (dummy drivers, as expected headless) |
| 6 | Windowed environment probe | `godot --path /tmp/rs-minv-proj --script probe3.gd` | display driver `macOS`; adapter `Apple M4 Max`; API `4.1 Metal - 91.7`; audio devices and 0 joypads as in §5/§7 |
| 7 | Renderer comparison | same probe with `rendering_method` set to `forward_plus` in a scratch copy | §3 |
| 8 | Physics backend hints | `ProjectSettings.get_property_list()` probe | §4 |
| 9 | Windowed boot scene | `godot --path /tmp/rs-minv-proj res://scenes/boot.tscn` (12 s bounded) | boot → menu handoff, no script errors, window rendered |
| 10 | Still capture of the game window | `screencapture -x`, `screencapture -x -R 0,0,960,540` | 1920×1080 and 960×540 PNGs |
| 11 | Desktop video capture | `ffmpeg -f avfoundation -framerate 60 -i 0:none -t 3` | 1920×1080 @ 60 FPS h264, 180 frames |
| 12 | Project capture readiness | `sh tools/ci/ci.sh capture --check` (in a scratch copy) | PASS: engine pin matches, templates installed, display available, 3 scenes listed; checksum reported NOT RECORDED |
| 13 | Project capture probe | `sh tools/ci/ci.sh capture --probe` (in a scratch copy) | PASS: `res://scenes/boot.tscn`, 6 frames, 0.2 s, 283,444 bytes, "100% of real-time speed". `ci.sh` reported the requested `resolution=640x360`, but `ffprobe` shows the recorded video stream is **1920×1080** mjpeg with a 48 kHz PCM audio track |
| 14 | Project capture at panel resolution | `sh tools/ci/ci.sh capture --target res://scenes/main_menu.tscn --frames 60 --fps 60 --resolution 960x540` | PASS: 60 frames, 1.0 s, 2,759,500 bytes. The engine logged "Movie Maker mode enabled, recording movie in 1920×1080 @ 60 FPS" and `ffprobe` confirms **1920×1080** mjpeg plus a 48 kHz PCM audio track — the requested `--resolution 960x540` was not honoured. Reported CPU render time for the placeholder menu averaged 0.19 ms/frame — a placeholder-shell figure, not a performance result |
| 15 | Project environment report script | `godot [--headless] --script res://tools/ci/scripts/environment_report.gd` | **Fails to parse**: `Static function "get_output_device_name()" not found in base "GDScriptNativeClass"` at line 33. `ci.sh doctor` therefore cannot run on any host until that line is fixed. Reported here as an observed defect; `tools/ci/**` is owned by another job and was not modified. (Updated, §13.5: the committed script uses `AudioServer.output_device` and parses.) |

Checks 13 and 14 share one discrepancy: the `--resolution` value passed to the capture path is
not honoured on this host. Both recordings came out at the project's 1920×1080 window size, so
the current capture path cannot be asked for a 960×540 panel on this machine. That matters for
M2.6/M5 capture planning and for BENCHMARKS' "four 960×540 panels" convention. It is recorded
as a limitation, not fixed here.

Timing observations from checks 9–14 were taken while other delegated jobs were running
concurrently on this machine (for example a `tools/tick_probe` headless run), so they are not
isolated measurements.

## 9. Platform coverage against the commitments

| Committed target (`docs/TECHNICAL_DESIGN.md`) | Status on this host |
| --- | --- |
| Apple Silicon macOS 14 or later | Host qualifies (macOS 27.0.1, Apple M4 Max). Engine, boot scene, capture and windowed rendering observed. No gameplay, performance or perceptual result |
| Windows 11 x86-64 | **Untested.** No Windows host available; only export templates exist |
| Ubuntu 24.04 x86-64 | **Untested.** No Linux host available; only export templates exist |
| Intel Mac, browser, mobile, console | Outside the initial commitment; not attempted |

An installed export template is not evidence that a package launches, and a successful export
would not verify a platform. Cross-platform claims stay open.

(Updated at the observed tip, §§13.2–13.3.) The committed project now carries placeholder
export presets. A macOS mode-1 package was exported and launched **headless** on this host
(`d4501e3`), and hosted Ubuntu runs built all three presets (`245ee1d`, `8c6c928`). Those runs
do not launch a Windows, Linux or Intel target; the untested statuses above stand, and the
CI/export gate remains open.

## 10. Gaps, unknowns and open items

Recorded explicitly, per M0.6 and M0's acceptance ("Record missing target hardware
explicitly"):

1. **No gamepad is available.** No controller, hotplug, remapping or four-player ownership
   evidence can be produced on this machine. M1.6/M3/M5 hardware gates remain open.
2. **No audio input device.** No recording, no agent listening review. The audio quality gate
   stays open.
3. **Visual review is capture-mediated only.** Agents cannot view the display directly.
4. **No Windows or Linux host.** Cross-platform physics, launch and packaging checks are
   impossible here.
5. **Mobile renderer untested** on this host; only `gl_compatibility` and `forward_plus` were
   started.
6. **Engine checksum.** The locally computed SHA-256 in §2 was not compared with an archive
   download by this task; the toolchain job's record (`docs/evidence/godot-4.7.2-archive-verification.md`)
   reports the same editor digest, so the two agree. M0.1's own pin file still leaves
   `expected_sha256` empty. (Updated, §13.4: the editor binary and selected templates are now
   publisher-checksummed, and both pin files carry `upstream_verified=yes` for their stated scope;
   the empty local-install field is superseded.)
7. **`export_presets.cfg` was missing at this baseline**, so no native package could be produced then
   (M0.4/M0.5). (Updated, §13.2: the file now exists with three placeholder presets;
   producing packages is no longer blocked by its absence, though no package is a verified
   release.)
8. **`tools/ci/scripts/environment_report.gd` did not parse at this baseline** (`AudioServer.get_output_device_name()`),
   so `ci.sh doctor` — the project's own environment recorder — failed on every host. Owner:
   `tools/ci/**` (job `93555487-a479-4ecb-ac23-9e95067144cf`). Audio facts in §7 were obtained
   with an equivalent probe instead. (Updated, §13.5: the committed script parses via
   `AudioServer.output_device`; follow-up owner `6848aca2…`.)
9. **Capture resolution was not honoured** by the capture path tested at this baseline: both `capture --probe`
   (requested 640×360) and `capture --target ... --resolution 960x540` recorded 1920×1080
   (checks 13–14). Owner: `tools/ci/**`. (Updated, §13.5: committed `ci.sh` applies a
   viewport override for `--resolution` and verifies the recorded resolution with `ffprobe`;
   not re-run by this reconciliation.)
10. **Usable desktop height is 1920×960** while the display is 1920×1080 (a 30 px top inset
    plus a further 90 px reserved). The cause was not determined; it affects any full-screen
    1080p layout check.
11. **Whether the JetKVM passes audio to a remote listener is unknown**, so the practical
    value of the host's audio output for human review is unconfirmed.
12. **Evidence directory.** `docs/evidence/` appeared while this document was being written
    (created by the toolchain job, which recorded `godot-4.7.2-archive-verification.md` there).
    The captures produced for §8 were kept in `/tmp` and deleted, because this task owns only
    this file; when the evidence directory's ownership and naming are settled, the checks in §8
    should be re-run there with their outputs retained. (Updated: `docs/evidence/` is now
    committed and holds the Godot archive verification, Jolt settings/warning and Python
    source-verification records.)
13. **Concurrency.** Other delegated jobs were running on this machine during these checks;
    nothing here is an isolated benchmark.

## 11. Deliberately not recorded

Read while probing but excluded from this document because M0.6 asks for no serial numbers,
private identifiers or credentials: the machine's hostname and hardware UUID, the Bluetooth
controller's address, product/vendor IDs, the USB device serials and paths, the codesigning
identity's name and key hash, and any account or token material. None of these were copied
into the repository.

## 12. Re-checking this inventory

Every fact above can be reproduced with the commands in §8, run from a scratch copy so the
shared checkout and its `.godot/` import cache stay untouched:

```sh
sw_vers; uname -a
sysctl -n hw.model hw.ncpu hw.physicalcpu hw.memsize hw.perflevel0.physicalcpu hw.perflevel1.physicalcpu
system_profiler SPDisplaysDataType SPAudioDataType SPControllerDataType SPBluetoothDataType
ioreg -r -c IOHIDDevice | grep -E '"Product"|"Transport"'
godot --headless --version
shasum -a 256 /Applications/Godot.app/Contents/MacOS/Godot
sh tools/ci/ci.sh capture --check      # run from a scratch copy, not the shared checkout
```

Renderer, physics-backend, audio-device and joypad facts need a small `SceneTree` script run
with `--script` (see checks 5–8); the same script must be run twice, once `--headless` and once
with a display driver, because the headless drivers report dummies.

## 13. Committed evidence behind the reconciliation

Each item cites a committed file or report; the reconciliation did not re-run these checks.
The baseline reproduction commands remain in §12.

### 13.1 Explicit Jolt selection (supersedes §4's `DEFAULT`)

* `project.godot` at the observed tip sets `physics/3d/physics_engine="Jolt Physics"`, with
  `common/physics_interpolation=true` and `common/physics_ticks_per_second=60`. The
  baseline's `DEFAULT` observation was true at `ee0ec19` and is retained as history.
* `tools/tick_probe/evidence/2026-11-26-apple-m4-max-jolt/README.md` records that the earlier
  DEFAULT-backend probe results are superseded: the contrast run under explicit
  `GodotPhysics3D` reproduces them bit-for-bit on every contact metric, so `DEFAULT`
  behaved as GodotPhysics3D on this build. Re-recorded Jolt runs passed 58/58 structural
  checks in three pacing modes and matched 600-tick accelerated/realtime endpoints. Direct
  backend identity remains unobservable from GDScript; the pin is verified through the
  setting value plus that contrast (`docs/STATUS.md` job `9725ba2c…`).
* `docs/evidence/jolt-settings.md` (committed `10d9e51`, job `52ab36a7…`) inventoried all 32
  `physics/jolt_physics_3d/*` settings of the pinned build: the game overrides exactly three
  physics entries (backend, interpolation, tick rate) and sets **none** of the 32 Jolt-specific
  values, which therefore run at engine defaults. Nothing was pinned by that job.
* `docs/evidence/jolt-job-warning-2026-11-27.md` (committed `063dd2c`, job `4f8a5b52…`)
  records the intermittent job-system capacity warning: pinned source waits and reclaims
  completed jobs when the free list is exhausted; capacity is 2,048 jobs; the warning was
  absent across the investigation's reruns, and liveness/capacity for representative workloads
  remains open.

### 13.2 Export presets and the known mode-1 macOS headless launch

* `export_presets.cfg` is tracked (added `7b27c2f`; `245ee1d` fixed hosted validation;
  `8c6c928` preserved per-preset evidence). It defines three placeholder desktop presets:
  `macOS Apple Silicon` (universal architecture, min macOS 14.0, built-in ad-hoc signing
  mode 1, `notarization/notarization=0`), `Windows x86-64`, and `Linux x86-64`. Each carries
  an exclude filter checked by `tools/export_smoke/lib/pack_inventory.py`. The file's own
  header states that it is not a verified release package and that Windows/Linux builds are
  cross-exports not launched here.
* Known launch evidence, mode 1, headless: job `e2ecffdc-e0d2-4b5f-8d1a-624e762f3911`
  (LongCat, candidate `d4501e3`) exported the committed macOS preset with the pinned editor
  and ran the exported bundle through `launch_macos_app.sh --skip-windowed`: headless exit 0,
  log reached `[boot] handing off to menu` / `[menu] placeholder menu shown`; `codesign
  --verify` passed as ad-hoc; `spctl` rejected the unnotarized build; ZIP SHA-256
  `e1553e8a9dce3d10189147a19d9f8947718bcfd7d78ac6b11a04b45b62bff4be`. `docs/STATUS.md`
  records the coordinator checking that hash and log. This is not windowed, current-mode,
  Intel, Windows or Linux launch evidence, and not gameplay or a release.
* Earlier windowed history: the coordinator launched the `7b27c2f` macOS smoke ZIP windowed
  and saw the placeholder menu in a captured image (`docs/STATUS.md`). That build predates
  the mode-1 change and remains a local shell smoke, not a supported-platform claim.

### 13.3 Hosted Linux cross-exports

* Hosted Ubuntu runs have built all three presets on the pinned editor. Run 45924755902
  (`245ee1d`) completed all three jobs including validation and exports; run 45928824558
  (`8c6c928`) completed all three jobs with passing pack inventories for macOS, Windows and
  Linux and a 21-file scoped `export-logs` artifact (`review/implementation/
  m0-ci-sol-recheck-245ee1d.md`, `m0-ci-sol-recheck-8c6c928.md`). These prove package
  creation and upload, not target launches.
* Latest observed hosted result: run 45934306464 on `675ec1c` passed all four jobs. Sol's
  recheck confirmed sequential exports of all three presets, filenames tied to the candidate
  SHA, success-gated package upload, and the new Godot-independent contract suites; it still
  returned **changes required** for a medium concurrent-invocation provenance defect and a
  low attempt-identifier gap (`review/implementation/m0-ci-sol-recheck-675ec1c.md`). The
  independent Opus 5.5 review also returned **changes required**, static only, for a
  test-coverage/documentation defect plus non-blocking nits (`review/implementation/
  m0-ci-opus-5-5-675ec1c-independent.md`).
* `675ec1c` added index-status propagation, stale-report removal and success-gated upload in
  response to the `8c6c928` findings. Because both named reviews of `675ec1c` remain
  changes-required and no Windows/Linux launch exists, the CI/export gate stays open.
* Package follow-up `f463de0e…` exported all three platforms locally from `f9779b5` plus the
  then-uncommitted preset overlay; inventories passed and macOS launched headless;
  Windows/Linux were not launched (`docs/STATUS.md`).

### 13.4 Pinned checksum and Sigstore evidence

* Godot: `docs/evidence/godot-4.7.2-archive-verification.md` records the official release
  `SHA512-SUMS.txt` matching the macOS editor ZIP (`38aa16e5…`) and export-template TPZ
  (`ca4d71c4…`), and the installed editor binary SHA-256 `c7cccbf8…`, `version.txt`,
  `macos.zip`, `windows_release_x86_64.exe` and `linux_release.x86_64` matching verified
  archive members. `tools/toolchain/pin/engine.txt` and `tools/ci/pin/engine.txt` carry
  `upstream_verified=yes` with scope notes; the CI pin also pins the Linux editor ZIP and TPZ
  SHA-512 digests that `ci.sh` verifies before extraction. Scope is selected files only;
  other bundle files and non-target templates were not compared, and no target platform was
  launched. A CI test job once truncated the installed Linux template during a corruption
  test; it was restored from a matching local copy and `tools/toolchain/verify.sh` confirmed
  the pinned digests afterwards (`docs/STATUS.md`).
* Python: `docs/PYTHON_TOOLCHAIN_EVIDENCE.md` records the selected interpreter as Homebrew core
  `python@3.15` 3.15.2 (arm64 bottle poured 2026-11-06) and ties the distribution channel to
  Homebrew-published digests. All four pinned python.org 3.15.2 artifacts matched published
  SHA-256, and Sigstore verification against `hugo@python.org` /
  `https://github.com/login/oauth` passed with wrong-identity, wrong-issuer and tampered-bytes
  controls failing. This authenticates publisher artifact bytes only; the installed Homebrew
  build is not authenticated by those signatures, its API JWS was not verified, and the
  framework code-signature anomaly remains open.
* Reconciliation spot-checks performed for this section (read-only; latest run during
  reconciliation):

```sh
$ git rev-parse HEAD
d8cd39cbfe926ba5321f59b4cc1ada727fd44b08
$ sw_vers
ProductName: macOS / ProductVersion: 27.0.1 / BuildVersion: 26A434
$ uname -a
Darwin <host-redacted> 27.0.0 Darwin Kernel Version 27.0.0: ... RELEASE_ARM64_T6041 arm64
$ sysctl -n hw.model hw.ncpu hw.memsize
Mac16,9 / 14 / 38654705664
$ godot --headless --version
4.7.2.stable.official.ed1daf0bf
$ shasum -a 256 /Applications/Godot.app/Contents/MacOS/Godot
c7cccbf8fb143e34e02fd6521e09be2c2b974f0d5db080b19071c9c570718ccf
```

These agree with §§1–2 and are not new hardware, controller, audio, perceptual or launch
observations.

### 13.5 Baseline tooling defects superseded

* `tools/ci/scripts/environment_report.gd` at the observed tip uses `AudioServer.output_device`
  (line 33); the baseline parse error (`get_output_device_name()`) is gone in committed code.
* `tools/ci/ci.sh` at the observed tip applies a viewport override for `--resolution` (line
  1505) and verifies the recorded resolution with `ffprobe`, failing on mismatch (lines
  1532–1539). Both are owned by the CI job and were not re-run by this reconciliation.

### 13.6 Limits that remain unchanged

No physical controller; no audio input; agents cannot view the display directly; no Windows,
Linux or Intel Mac host; renderer still provisional until M3; every perceptual gate needs a
human or capable reviewer; a cross-export, hosted export or installed template is not a
target-OS launch. See §§5–7, §9 and §10.

## Follow-up: committed evidence after the baseline

The baseline's tooling snapshot was extended by later committed work owned elsewhere: CI and
export repair `a3a8cdb9…` (committed `245ee1d`, `8c6c928`), package-content follow-up
`f463de0e…`, mode-1 macOS smoke `e2ecffdc…`, CI hardening `675ec1c`, and its independent
reviews (`2049beb`). None of it closes M0: both named reviews of `675ec1c` remain
changes-required, a clean GitHub-hosted runner for the current candidate has no recorded
result, and Windows/Linux/Intel launches, controller/audio/perceptual verification, and M3
renderer measurements remain open. `docs/STATUS.md` (owned elsewhere) is the running
record; this file owns only the machine/capability inventory.
