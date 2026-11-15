#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UPSTREAM="$ROOT/_upstream"
VULN_COMMIT="bc51a67ccff86f2c691375f3cc92ee8c0a9fc369"
FIXED_COMMIT="3d1ddc42ffd920c2fef968e122d641eb31590aa9"
REPO_URL="https://github.com/csx-protocol/csx-contracts"

mkdir -p "$ROOT/worktrees"

if [ ! -d "$UPSTREAM/.git" ] && [ ! -f "$UPSTREAM/.git" ]; then
  echo "Cloning upstream repository..."
  git clone "$REPO_URL" "$UPSTREAM"
else
  echo "Upstream repository already present."
fi

git -C "$UPSTREAM" fetch --all --tags

for name_commit in "vulnerable:$VULN_COMMIT" "fixed:$FIXED_COMMIT"; do
  name="${name_commit%%:*}"
  commit="${name_commit##*:}"
  wt="$ROOT/worktrees/$name"
  if [ ! -d "$wt" ]; then
    echo "Creating worktree: $name ($commit)"
    git -C "$UPSTREAM" worktree add "$wt" "$commit"
  else
    echo "Worktree exists: $name"
  fi
done

for wt in "$ROOT/worktrees/vulnerable" "$ROOT/worktrees/fixed"; do
  echo "Installing dependencies in $wt..."
  (cd "$wt" && npm install)

  cat > "$wt/foundry.toml" <<'TOML'
[profile.default]
src = "contracts"
test = "test"
out = "out"
libs = ["node_modules", "lib"]
solc_version = "0.8.18"
optimizer = true
optimizer_runs = 200
remappings = [
  "@openzeppelin/=node_modules/@openzeppelin/"
]
TOML

  mkdir -p "$wt/test/mocks"
  cp "$ROOT/test/mocks/"*.sol "$wt/test/mocks/"
  cp "$ROOT/test/CSXStakingRegression.t.sol" "$wt/test/"

  # Fixed commit needs a duration set for streaming rewards in tests; handled in test via vm.warp/setup.
done

echo "Setup complete."
