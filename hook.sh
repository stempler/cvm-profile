#!/usr/bin/env bash
#
# code-vm profile hook: ensure fisher is installed and (re)install the
# stempler/config.fish plugin.
#
# Runs as the agent user (devuser), through the egress proxy, on every boot
# and every `code-vm profile apply`. It must therefore be idempotent.

set -euo pipefail

FISH_BIN=/usr/bin/fish

# Fisher is pinned to a specific commit so the curl-piped bootstrap fetches a
# byte-for-byte known payload (raw.githubusercontent.com/<SHA>/... is
# content-addressed by commit) rather than whatever `main` happens to be.
# Bump both the version comment and the SHA together.
#
# renovate: fisher 4.4.8
FISHER_REF=a04308be92daa6cfecdbb0ca58b1e8508664cff2
FISHER_RAW="https://raw.githubusercontent.com/jorgebucaran/fisher/${FISHER_REF}/functions/fisher.fish"

# 1. Ensure fisher is installed. `functions -q fisher` triggers fish's
#    autoloader, so this is true once the function file is on disk.
if ! "$FISH_BIN" -c 'functions -q fisher'; then
    echo "hook: installing fisher (${FISHER_REF})"
    curl -fsSL "$FISHER_RAW" \
        | "$FISH_BIN" -c "source /dev/stdin && fisher install jorgebucaran/fisher@${FISHER_REF}"
else
    echo "hook: fisher already present"
fi

# 2. Install stempler/config.fish, or update it to latest if already installed.
#    `fisher install` is idempotent and refreshes the plugin on each run.
echo "hook: installing/updating stempler/config.fish"
"$FISH_BIN" -c 'fisher install stempler/config.fish'

echo "hook: done"
