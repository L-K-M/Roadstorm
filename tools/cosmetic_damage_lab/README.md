# M1.8/M5.9 cosmetic damage lab

Headless contract lab for `src/presentation/cosmetic_damage_state.gd`.

## Files

- `validate_cosmetic_damage_lab.gd` headless SceneTree entry point
- `cosmetic_damage_lab_checks.gd` cases and assertions
- `failure_probe.gd` deliberate failing-check proof
- `run_validation.sh` private frozen-archive runner

## Running

```sh
tools/cosmetic_damage_lab/run_validation.sh
```

Exit 0 requires validator `pass:true`, zero failed checks, and a nonzero failure probe. No M1.8/M5.9/full game acceptance is claimed.
