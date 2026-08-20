# cvm-profile

A [code-vm](https://github.com/wetransform-os/code-vm) profile that makes
[fish](https://fishshell.com) the agent's default shell, installs
[fisher](https://github.com/jorgebucaran/fisher), and installs/updates the
`stempler/config.fish` fish configuration.

## What it does

| Requirement | How |
|---|---|
| fish is installed | `packages: [fish]` in `profile.yaml` (apt, as root) |
| fisher is installed | `hook.sh` bootstraps fisher from a **pinned commit** |
| fish is the default shell | `shell: /usr/bin/fish` in `profile.yaml` |
| `stempler/config.fish` installed/updated | `hook.sh` runs `fisher install stempler/config.fish` |

The hook runs as the agent user on every boot and every `code-vm profile
apply`, and is idempotent: fisher is only bootstrapped when missing, and
`fisher install stempler/config.fish` both installs and refreshes to latest.

## Egress domains

The profile adds these to the code-vm allowlist (in `profile.yaml`):

- `raw.githubusercontent.com` — fisher bootstrap script
- `api.github.com` — fisher plugin tarball endpoint (`owner/repo`)
- `codeload.github.com` — where `api.github.com` redirects tarball downloads

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
