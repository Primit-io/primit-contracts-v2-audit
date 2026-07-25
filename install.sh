#!/usr/bin/env bash
#
# One-shot dependency installer for all in-scope Foundry projects.
# Pins OpenZeppelin to v5.0.2 (identical to Primit mainnet build).
#
# Usage:
#   ./install.sh
#
# After running, each sub-repo is ready for `forge build` / `forge test`.

set -e
umask 022

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
FORGE_STD_TAG="v1.9.4"
OZ_TAG="v5.0.2"
OZ_UPGRADEABLE_TAG="v5.0.2"

install_libs() {
  local sub="$1"
  echo "─── Installing deps for $sub ───"
  cd "$REPO_ROOT/$sub"

  if [ ! -d "lib/forge-std" ]; then
    forge install foundry-rs/forge-std@$FORGE_STD_TAG --no-commit
  fi
  if [ ! -d "lib/openzeppelin-contracts" ]; then
    forge install OpenZeppelin/openzeppelin-contracts@$OZ_TAG --no-commit
  fi
  if [ ! -d "lib/openzeppelin-contracts-upgradeable" ]; then
    forge install OpenZeppelin/openzeppelin-contracts-upgradeable@$OZ_UPGRADEABLE_TAG --no-commit
  fi

  echo "  ✓ $sub · running forge build"
  forge build --skip test --skip script 2>&1 | tail -3
  echo ""
}

install_libs vault_contract
install_libs plp_contract
install_libs rebate_contract
install_libs referral_storage_contract

echo "═══════════════════════════════════════════════════════════════"
echo "  ✓ All in-scope projects built successfully"
echo "═══════════════════════════════════════════════════════════════"
