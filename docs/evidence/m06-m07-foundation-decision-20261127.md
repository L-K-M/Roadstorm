# M0.6 and M0.7 foundation decision — 2026-11-27

Source state inspected: coordinator main 9685008 (the content of the two foundation records was unchanged by the active CI, camera, body and HUD workers). This is a subtask decision, not M0 acceptance or a renderer freeze.

## M0.6: provisional machine and review-capability inventory

Accepted as a recorded inventory. docs/MACHINE_INVENTORY.md §§0–13 names the actual Mac/OS/GPU/display and provisional gl_compatibility renderer, checks both available renderers at startup without claiming a performance comparison, records the 60 Hz/Jolt setting, and identifies capture methods with a baseline resolution defect and its later correction. It states that no physical controller or audio input was available, visual review was capture-mediated, audio output was observable but unheard, and Windows/Linux game launches were not tested. The committed reconciliation in §13 separates historical baseline observations from later source/toolchain evidence. M3 must measure representative four-view performance before selecting the renderer; M1/M3/M5 hardware and perceptual gates remain open.

## M0.7: status and ownership infrastructure

Accepted as established. docs/STATUS.md is a chronological live status and ownership ledger; docs/IMPLEMENTATION_LOG.md records provenance and integration decisions; docs/evidence/ holds decision/evidence records. The run has one coordinator lease at work/agents/coordinator.lock/owner.txt and isolated worker task/session/log directories under work/agents/. The repository ignore rule /work/ is active: git check-ignore returned work/agents/coordinator.lock/owner.txt. Other tested ignore paths were .godot/example, build/example, saves/example and .env. The coordinator records input SHAs, owned paths, actual routes, active sessions, test results, reviews and open gates. These mechanisms do not guarantee future status accuracy by themselves; refresh them at each integration batch.

M0.2, M0.3, M0.4, M0.5 and whole M0 remain open. In particular the standard public LongCat/StepFun provider terms have an unresolved release-rights issue, even though development continues at the owner's direction.
