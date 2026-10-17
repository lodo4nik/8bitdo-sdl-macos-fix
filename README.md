# 8BitDo macOS Fix

Helps SDL-based games and controller utilities recognize the **8BitDo Ultimate 2C
Wireless** on macOS. The fix is applied automatically whenever you log in.

Requires **macOS 12 or newer**. Tested over Bluetooth on macOS 27.2 with
SDL2 Gamepad Tool and CrossOver.

## Installation

1. Click **Code → Download ZIP** on GitHub and extract the folder.
2. Double-click **Enable Compatibility.command**.
3. Fully quit and reopen your games and launchers, including Steam or CrossOver.

No administrator password or extra software is required. Run without `sudo`.

You can also install from Terminal inside the downloaded folder:

```sh
zsh "Enable Compatibility.command"
```

## Status and removal

- Double-click **Status.command** to check whether the fix is enabled.
- Double-click **Undo Compatibility.command** to remove it, then reopen affected apps.

The setting affects all SDL controllers. If another controller behaves worse,
use Undo. Apps that use only Apple's GameController API are not supported by
this workaround.

[MIT License](LICENSE)
