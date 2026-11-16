hl.bind("CTRL+SUPER+ALT+Slash", hl.dsp.exec_cmd("xdg-open ~/.config/hypr/custom/keybinds.lua"), {description = "Edit user keybinds"} )

-- end-4 #3728, releasing super after super+key kept opening the overview on 0.57.
-- shell wants searchToggleReleaseInterrupt when a key goes down with super held.
-- 133/134 = Super_L/Super_R
hl.on("input.keyboard.key", function(keycode, _, state)
    if state ~= 1 or keycode == 133 or keycode == 134 then return end
    if hl.is_key_down(133) or hl.is_key_down(134) then
        hl.dispatch(hl.dsp.global("quickshell:searchToggleReleaseInterrupt"))
    end
end)
