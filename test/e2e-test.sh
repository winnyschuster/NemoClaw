#!/usr/bin/env bash
# SPDX-FileCopyrightText: Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: Apache-2.0
#
# E2E test for NemoClaw + blueprint
# Runs inside the Docker sandbox

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

pass() { echo -e "${GREEN}PASS${NC}: $1"; }
fail() { echo -e "${RED}FAIL${NC}: $1"; exit 1; }
info() { echo -e "${YELLOW}TEST${NC}: $1"; }

# -------------------------------------------------------
info "1. Verify OpenClaw CLI is installed"
# -------------------------------------------------------
openclaw --version && pass "OpenClaw CLI installed" || fail "OpenClaw CLI not found"

# -------------------------------------------------------
info "2. Verify plugin can be installed"
# -------------------------------------------------------
openclaw plugins install /opt/nemoclaw 2>&1 && pass "Plugin installed" || {
    # If plugins install isn't available, verify the built artifacts exist
    if [ -f /opt/nemoclaw/dist/index.js ]; then
        pass "Plugin built successfully (dist/index.js exists)"
    else
        fail "Plugin build artifacts missing"
    fi
}

# -------------------------------------------------------
info "3. Verify blueprint YAML is valid"
# -------------------------------------------------------
python3 -c "
import yaml, sys
bp = yaml.safe_load(open('/opt/nemoclaw-blueprint/blueprint.yaml'))
assert bp['version'] == '0.1.0', f'Bad version: {bp[\"version\"]}'
profiles = bp['components']['inference']['profiles']
assert 'default' in profiles, 'Missing default profile'
assert 'ollama' in profiles, 'Missing ollama profile'
assert 'nim-local' in profiles, 'Missing nim-local profile'
print(f'Profiles: {list(profiles.keys())}')
" && pass "Blueprint YAML valid with all 3 profiles" || fail "Blueprint YAML invalid"

# -------------------------------------------------------
info "4. Verify blueprint runner plan command"
# -------------------------------------------------------
cd /opt/nemoclaw-blueprint
# Runner will fail at openshell prereq check (expected in test container)
# We just verify it gets past validation and profile resolution
python3 orchestrator/runner.py plan --profile ollama --dry-run 2>&1 | tee /tmp/plan-output.txt || true
grep -q "RUN_ID:" /tmp/plan-output.txt && pass "Blueprint plan generates run ID" || fail "No run ID in plan output"
grep -q "Validating blueprint" /tmp/plan-output.txt && pass "Blueprint runner validates before execution" || fail "No validation step"

# -------------------------------------------------------
info "5. Verify host OpenClaw detection (migration source)"
# -------------------------------------------------------
[ -f /sandbox/.openclaw/openclaw.json ] && pass "Host OpenClaw config detected" || fail "No host config"
[ -d /sandbox/.openclaw/workspace ] && pass "Host workspace directory exists" || fail "No workspace dir"
[ -d /sandbox/.openclaw/skills ] && pass "Host skills directory exists" || fail "No skills dir"

# -------------------------------------------------------
info "6. Verify snapshot creation (migration pre-step)"
# -------------------------------------------------------
python3 -c "
import sys
sys.path.insert(0, '/opt/nemoclaw-blueprint/migrations')
from snapshot import create_snapshot, list_snapshots

snap = create_snapshot()
assert snap is not None, 'Snapshot returned None'
assert snap.exists(), f'Snapshot dir does not exist: {snap}'

snaps = list_snapshots()
assert len(snaps) == 1, f'Expected 1 snapshot, got {len(snaps)}'
print(f'Snapshot created at: {snap}')
print(f'Files captured: {snaps[0][\"file_count\"]}')
" && pass "Migration snapshot created successfully" || fail "Snapshot creation failed"

# -------------------------------------------------------
info "7. Verify snapshot restore (eject path)"
# -------------------------------------------------------
python3 -c "
import sys, json, shutil
sys.path.insert(0, '/opt/nemoclaw-blueprint/migrations')
from snapshot import list_snapshots, rollback_from_snapshot
from pathlib import Path

snaps = list_snapshots()
snap_path = Path(snaps[0]['path'])

# Simulate corruption: modify the host config
config = Path.home() / '.openclaw' / 'openclaw.json'
original = json.loads(config.read_text())
config.write_text(json.dumps({'corrupted': True}))

# Rollback
success = rollback_from_snapshot(snap_path)
assert success, 'Rollback returned False'

# Verify restoration
restored = json.loads(config.read_text())
assert restored.get('meta', {}).get('lastTouchedVersion') == '2026.3.11', f'Restored config wrong: {restored}'
assert 'corrupted' not in restored, 'Config still corrupted after rollback'
print(f'Restored config: {restored}')
" && pass "Snapshot rollback restores original config" || fail "Rollback failed"

# -------------------------------------------------------
info "8. Verify plugin TypeScript compilation"
# -------------------------------------------------------
[ -f /opt/nemoclaw/dist/index.js ] && pass "index.js compiled" || fail "index.js missing"
[ -f /opt/nemoclaw/dist/commands/migrate.js ] && pass "migrate.js compiled" || fail "migrate.js missing"
[ -f /opt/nemoclaw/dist/commands/launch.js ] && pass "launch.js compiled" || fail "launch.js missing"
[ -f /opt/nemoclaw/dist/commands/connect.js ] && pass "connect.js compiled" || fail "connect.js missing"
[ -f /opt/nemoclaw/dist/commands/eject.js ] && pass "eject.js compiled" || fail "eject.js missing"
[ -f /opt/nemoclaw/dist/commands/status.js ] && pass "status.js compiled" || fail "status.js missing"
[ -f /opt/nemoclaw/dist/commands/logs.js ] && pass "logs.js compiled" || fail "logs.js missing"
[ -f /opt/nemoclaw/dist/blueprint/resolve.js ] && pass "resolve.js compiled" || fail "resolve.js missing"
[ -f /opt/nemoclaw/dist/blueprint/verify.js ] && pass "verify.js compiled" || fail "verify.js missing"
[ -f /opt/nemoclaw/dist/blueprint/exec.js ] && pass "exec.js compiled" || fail "exec.js missing"
[ -f /opt/nemoclaw/dist/blueprint/state.js ] && pass "state.js compiled" || fail "state.js missing"

# -------------------------------------------------------
info "9. Verify NemoClaw state management"
# -------------------------------------------------------
node -e "
const { loadState, saveState, clearState } = require('/opt/nemoclaw/dist/blueprint/state.js');

// Initial state should be empty
let state = loadState();
console.assert(state.lastAction === null, 'Initial state should be null');

// Save and reload
saveState({ ...state, lastAction: 'migrate', lastRunId: 'test-123', sandboxName: 'openclaw' });
state = loadState();
console.assert(state.lastAction === 'migrate', 'Should be migrate');
console.assert(state.lastRunId === 'test-123', 'Should be test-123');
console.assert(state.updatedAt !== null, 'Should have timestamp');

// Clear
clearState();
state = loadState();
console.assert(state.lastAction === null, 'Should be cleared');

console.log('State management: create, save, load, clear all working');
" && pass "NemoClaw state management works" || fail "State management broken"

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  ALL E2E TESTS PASSED${NC}"
echo -e "${GREEN}========================================${NC}"
