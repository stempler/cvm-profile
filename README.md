# cvm-profile

A [code-vm](https://github.com/wetransform-os/code-vm) profile that makes
[fish](https://fishshell.com) the agent's default shell, installs
[fisher](https://github.com/jorgebucaran/fisher), installs/updates the
`stempler/config.fish` fish configuration, and installs and configures the
[Starship](https://starship.rs) prompt.

## What it does

| Requirement | How |
|---|---|
| fish is installed | `packages: [fish]` in `profile.yaml` (apt, as root) |
| fisher is installed | `hook.sh` bootstraps fisher from a **pinned commit** |
| fish is the default shell | `shell: /usr/bin/fish` in `profile.yaml` |
| `stempler/config.fish` installed/updated | `hook.sh` runs `fisher install stempler/config.fish` |
| Starship is installed | `hook.sh` downloads a **pinned, SHA256-verified** release binary to `~/.local/bin` |
| Starship is enabled + configured | `files/` ships the fish loader and `starship.toml` into the agent home |

The hook runs as the agent user on every boot and every `code-vm profile
apply`, and is idempotent: fisher is only bootstrapped when missing,
`fisher install stempler/config.fish` both installs and refreshes to latest,
and Starship is only re-downloaded when missing or when the pinned version
changes. The `files/` tree is (re)installed by code-vm on every apply, so the
shipped config is canonical.

## Starship prompt

Starship is delivered two ways, each suited to what it ships:

**Binary — via `hook.sh`.** The hook downloads the pinned Starship release
tarball and its published `.sha256` from GitHub, verifies the checksum
(aborting on any mismatch), and extracts the `starship` binary to
`~/.local/bin`. Only the `x86_64-unknown-linux-gnu` asset is fetched; the hook
fails loudly on any other architecture rather than installing the wrong binary.

**Config — via the `files/` tree.** code-vm installs every path under a
profile's `files/` directory into the agent home (mirroring the layout), before
hooks run. This profile ships:

- `files/.config/fish/conf.d/starship.fish` → `~/.config/fish/conf.d/starship.fish`
  — the loader: ensures `~/.local/bin` is on `PATH`, then runs
  `starship init fish | source`. It lives in `conf.d` so it loads independently
  of `stempler/config.fish`.
- `files/.config/starship.toml` → `~/.config/starship.toml` — a prompt tuned
  for the sandbox (host name, directory, git state, command duration,
  success/failure indicator; Nerd-Font-free symbols).

## Egress domains

The profile adds these to the code-vm allowlist (in `profile.yaml`):

- `raw.githubusercontent.com` — fisher bootstrap script
- `api.github.com` — fisher plugin tarball endpoint (`owner/repo`)
- `codeload.github.com` — where `api.github.com` redirects tarball downloads
- `github.com` — Starship release download URL (issues the 302 redirect)
- `release-assets.githubusercontent.com` — where the Starship asset bytes are served

## Usage

```bash
code-vm profile add git@github.com:stempler/cvm-profile.git stempler
```

Then activate it in `~/.config/code-vm/config.yaml`:

```yaml
profiles:
  - stempler
```

Apply to a running VM (boots apply it automatically):

```bash
code-vm profile apply
```

## Pinned fisher version

fisher is pinned to a commit SHA in `hook.sh` (currently **4.4.8**,
`a04308be92daa6cfecdbb0ca58b1e8508664cff2`) so the curl-piped bootstrap
fetches a known payload rather than tracking `main`. To upgrade, update both
the `FISHER_REF` SHA and the accompanying version comment.

## Pinned Starship version

Starship is pinned to a release tag in `hook.sh` (currently **1.26.0**,
`STARSHIP_VERSION=v1.26.0`) and the downloaded tarball is verified against the
release's published `.sha256`, so the install is a byte-for-byte known payload.
To upgrade, bump `STARSHIP_VERSION`, the accompanying version comment, and the
`# renovate: starship <version>` marker together.
