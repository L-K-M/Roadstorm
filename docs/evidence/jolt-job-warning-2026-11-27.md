# Jolt job-system warning investigation

On the pinned Godot `4.7.2.stable.official.ed1daf0bf`, one earlier structural
probe emitted a job-system capacity warning and still passed all 58 checks.
The warning was absent in 15 earlier attempts, four later isolated reruns,
and three additional headless runs on 2026-11-27. The warning is emitted at
most once per process, so warning-line counts do not measure event frequency.

The pinned [Godot job-system implementation](https://github.com/godotengine/godot/blob/ed1daf0bf001b61586d9930840f2f1394092c079/modules/jolt_physics/spaces/jolt_job_system.cpp)
waits and reclaims completed jobs when its free list is exhausted; the pinned
[Jolt settings](https://github.com/godotengine/godot/blob/ed1daf0bf001b61586d9930840f2f1394092c079/thirdparty/jolt_physics/Jolt/Physics/PhysicsSettings.h)
set its capacity to 2,048 jobs. The source path retries allocation rather
than explicitly dropping a job. The observed warning-run probe result matched
the non-warning results for the tested scenarios. This limited observation
cannot establish general simulation correctness or bound the duration of a
stall. Capacity and liveness remain open for realistic workloads.

Investigation: LongCat 2.5 job `4f8a5b52-196c-485c-bcd4-049a9ad9823f`,
headless on Apple M4 Max, macOS 27.0.1, input `27ae79e`. The complete local
report and three isolated run logs are retained in its ignored job directory.
No settings were changed. Follow-up should reproduce the warning under a
bounded representative workload and measure duration while checking simulation
invariants; do not suppress it or infer that untested workloads are safe.
