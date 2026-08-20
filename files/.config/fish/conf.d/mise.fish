# Activate mise (https://mise.jdx.dev) for fish shells.
#
# mise is provided by the base sandbox image; this only wires it into the
# shell (shims + env + the `mise` helper). Guarded so the shell still starts
# cleanly if mise is ever absent.

if type -q mise
    mise activate fish | source
end
