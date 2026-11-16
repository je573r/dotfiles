# dotfiles

cachyos + hyprland, running end-4 dots (illogical impulse) on top. no i dont rice... this repo is just my preferences that sits on top of whatever end4's installer does so i dont lose it when something breaks or i reinstall

laptop is an ideapad gaming 3 15ARH7 if that ever matters

## whats here

- `hypr/custom/` - my keybinds + the super key fix. end4 shouldnt touch custom/ so these just get copied once and survive updates
- `hypr/hypridle.conf` + `hyprlock.conf` - idle/lock timings
- `patches/` - edits to files the end4 updater WILL overwrite. run `./patches/apply.sh` after every end4 update, this is basically the whole point of the repo
  - idle-keep-awake - keep awake toggle broken on hyprland 0.57, like 3 separate bugs stacked on each other...
  - ai-groq-nim - openai compatible api support for the sidebar ai (groq / nvidia nim, yes free apis)
  - general-shadow-renderpower - 0.57 refuses shadow render_power above 4, end4 had 10 idk why
- `quickshell-extra/` - whole new files added. copy the contents into `~/.config/quickshell/ii/` keeping the dir structure
- `config/` - fish, kitty, foot, fuzzel, starship
- `illogical-impulse/config.json` - end4 shell settings, has the groq/nvidia models for the ai sidebar. re-add keys from the sidebar, not like its useful anyway
- `packages.txt` - pacman -Qqe dump, refresh it once in a while

## fresh install order

1. cachyos
2. end4 dots - https://github.com/end-4/dots-hyprland
3. copy hypr/custom, the two confs, config/ stuff and illogical-impulse/config.json to their places under ~/.config (starship.toml goes directly in ~/.config/)
4. copy quickshell-extra contents into ~/.config/quickshell/ii/
5. ./patches/apply.sh
6. pacman -S --needed - < packages.txt (some are aur, paru handles both)
7. re-add the ai api keys in the sidebar
