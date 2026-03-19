# HWIP Plugins — Moved to deepspan-hwip

> **This directory is empty.** HWIP plugin implementations have been migrated to the
> [`deepspan-hwip`](https://github.com/myorg/deepspan-hwip) repository.

## Migrated plugins

| Plugin | New location |
|---|---|
| `accel` | `deepspan-hwip/accel/` |
| `codec` | `deepspan-hwip/codec/` |

## Adding a new HWIP type

See [`deepspan-hwip`](https://github.com/myorg/deepspan-hwip) for the standard
onboarding workflow:

```bash
# In deepspan-hwip:
cp -r accel/ <type>/
vi <type>/hwip.yaml          # edit opcodes + register map
deepspan-codegen --descriptor <type>/hwip.yaml --out <type>/gen/
# then: go.work + CMakePresets.json + ci-<type>.yml
```

## Platform stable interfaces

HWIP plugins depend only on **Tier-1** interfaces defined in
[`../STABLE_API.md`](../STABLE_API.md):

- `github.com/myorg/deepspan/server/pkg/hwip.Submitter`
- CMake: `Deepspan::deepspan-appframework`, `Deepspan::deepspan-userlib`
- Python: `deepspan.client.HwipExtension`
