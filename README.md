# NemoClaw — OpenClaw Plugin for OpenShell

Migrate and run OpenClaw inside OpenShell with optional NIM-backed inference.

## Architecture

```
nemoclaw/                           Thin TypeScript plugin (in-process with OpenClaw gateway)
├── src/
│   ├── index.ts                    Plugin entry — registers all nemoclaw commands
│   ├── commands/
│   │   ├── launch.ts               Fresh install (prefers OpenShell-native for net-new)
│   │   ├── migrate.ts              Migrate host OpenClaw into sandbox
│   │   ├── connect.ts              Interactive shell into sandbox
│   │   ├── status.ts               Blueprint run state + sandbox health
│   │   ├── logs.ts                 Stream logs from blueprint/sandbox/inference
│   │   └── eject.ts                Rollback to host install from snapshot
│   └── blueprint/
│       ├── resolve.ts              Version resolution, cache management
│       ├── verify.ts               Digest verification, compatibility checks
│       ├── exec.ts                 Subprocess execution of blueprint runner
│       └── state.ts                Persistent state (run IDs, snapshots)
├── openclaw.plugin.json            Plugin manifest
└── package.json                    Commands declared under openclaw.extensions

nemoclaw-blueprint/                 Versioned blueprint artifact (separate release stream)
├── blueprint.yaml                  Manifest — version, profiles, compatibility
├── orchestrator/
│   └── runner.py                   CLI runner — plan / apply / status / rollback
├── policies/
│   └── openclaw-sandbox.yaml       Strict baseline network + filesystem policy
├── migrations/
│   └── snapshot.py                 Snapshot / restore / cutover / rollback logic
└── iac/                            (future) Declarative infrastructure modules
```

## Quick Start

### For existing OpenClaw users (primary path)

```bash
openclaw plugins install ./nemoclaw
openclaw nemoclaw migrate --profile ollama
openclaw nemoclaw connect
```

### For net-new users (OpenShell-native preferred)

```bash
openshell sandbox create --from openclaw --name openclaw
openshell sandbox connect openclaw
```

## Commands

| Command | Description |
|---------|-------------|
| `openclaw nemoclaw launch` | Fresh install into OpenShell (warns net-new users) |
| `openclaw nemoclaw migrate` | Migrate host OpenClaw into sandbox (snapshot + cutover) |
| `openclaw nemoclaw connect` | Interactive shell into the sandbox |
| `openclaw nemoclaw status` | Blueprint state, sandbox health, inference config |
| `openclaw nemoclaw logs` | Stream logs (sandbox, blueprint, inference) |
| `openclaw nemoclaw eject` | Rollback to host installation from snapshot |

## Inference Profiles

| Profile | Provider | Model | Use Case |
|---------|----------|-------|----------|
| `default` | NVIDIA cloud | nemotron-3-super | Production, requires API key |
| `nim-local` | Local NIM service | nemotron-3-super | On-prem, NIM deployed as pod |
| `ollama` | Ollama | llama3.1:8b | Local development, no API key |

## Design Principles

1. **Thin plugin, versioned blueprint** — Plugin stays small and stable; orchestration logic evolves independently
2. **Respect CLI boundaries** — Plugin commands live under `nemoclaw` namespace, never override built-in OpenClaw commands
3. **Supply chain safety** — Immutable versioned artifacts with digest verification
4. **OpenShell-native for net-new** — Don't force double-install; prefer `openshell sandbox create`
5. **Snapshot everything** — Every migration creates a restorable backup
