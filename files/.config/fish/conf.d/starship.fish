# Load the Starship prompt (https://starship.rs).
#
# Installed by the stempler cvm-profile hook into ~/.local/bin/starship, which
# fish does not put on PATH by default — so ensure it is present first. Living
# in conf.d means this loads independently of the stempler/config.fish plugin,
# for both interactive and login shells.

if not contains -- $HOME/.local/bin $PATH
    set -gx PATH $HOME/.local/bin $PATH
end

if type -q starship
    starship init fish | source
end
