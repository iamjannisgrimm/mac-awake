# Mac Awake

A small native macOS menu bar app, two Apple Shortcuts, and two command scripts to turn the Mac's sleep override on and off. This packages the original Mac Awake setup with a portable installer and automatic launch at login.

## Install on another Mac

Requires **macOS 14 or newer**, Apple Silicon or Intel, an administrator account for changing sleep settings, and Apple's Command Line Tools (or Xcode). If Git or Swift is missing, run `xcode-select --install`, finish Apple's installation, then continue.

```sh
git clone https://github.com/iamjannisgrimm/mac-awake.git
cd mac-awake
./setup.sh
```

Run setup as your normal logged-in user, **without sudo**. It compiles the app for that Mac, installs it, opens each missing shortcut for you to click **Add Shortcut**, and starts the menu bar app. Keep the names **Keep Mac Awake On** and **Keep Mac Awake Off**. Existing shortcuts with those names are preserved; to replace an older copy, open the corresponding file in `Shortcuts/` and choose **Replace**.

If macOS asks, enable **Allow Running Scripts** in Shortcuts → Settings → Advanced. The shortcuts use **Run as Administrator**, so macOS may request your password when you toggle. These are macOS-controlled confirmations, not steps an installer silently accepts. [Apple's Shortcuts command-line documentation](https://support.apple.com/guide/shortcuts-mac/apd455c82f02/mac) describes running and signing shortcuts.

Setup does **not** change your current sleep setting. On a fresh Mac, click the new menu bar icon to enable keep-awake mode. It installs:

| Component | Location |
| --- | --- |
| Menu bar app | `~/Applications/Mac Awake.app` |
| ON / OFF commands | `~/Library/Scripts/Keep Mac Awake/` |
| App source copy | `~/Library/Scripts/Keep Mac Awake/MenuBar/main.swift` |
| Login launch agent | `~/Library/LaunchAgents/com.jannisgrimm.mac-awake.plist` |
| Backups of replaced files | `~/Library/Application Support/Mac Awake/Backups/` |

The installer can be rerun. It backs up replaced components, preserves existing named shortcuts, and reloads the same launch agent. Shortcuts embed the command script, so they work with any username and do not depend on the administrator process's home directory. No Homebrew, third-party keep-awake app, or background root service is needed.

## Use

- **Left-click** the sun/moon menu bar item to toggle. **Right-click** for explicit on/off, refresh, shortcut editing, and quit.
- **On** runs `sudo pmset -a disablesleep 1`, verifies the setting, waits five seconds, then requests display sleep. This is a persistent system-wide override for charger and battery, including lid-close sleep on supported hardware.
- **Off** runs `sudo pmset -a disablesleep 0` and verifies it. Your existing sleep and display timers stay unchanged.
- The app checks the actual `pmset` state every five seconds and after wake. An unreadable state displays `?` and blocks toggling instead of guessing.
- Quitting the app **keeps the current sleep setting**. The app starts at the next login; the override itself can persist across restarts independently of the app.

The command files also run directly in Terminal. Other apps, such as Amphetamine, can independently prevent sleep even when this override is Off. Hardware, macOS, low battery, and thermal protection can affect closed-lid behavior; verify it on each target Mac. Keep an awake Mac ventilated, especially with its lid closed, and do not leave it running inside a bag.

## Startup and recovery

If the icon is missing, run `open "$HOME/Applications/Mac Awake.app"` or rerun `./setup.sh`. Check **System Settings → General → Login Items** if macOS blocks background startup. The launch agent uses `RunAtLoad` and restarts an unexpected app failure, while an intentional Quit remains respected until the next login.

To stop launching at login:

```sh
launchctl bootout "gui/$(id -u)/com.jannisgrimm.mac-awake"
mv "$HOME/Library/LaunchAgents/com.jannisgrimm.mac-awake.plist" "$HOME/.Trash/"
```

To remove the setup, first run **Keep Mac Awake Off** if you want normal sleep, unload the launch agent as above, then move the app and script folder to Trash and delete the two shortcuts in Shortcuts. Removing the files alone does not reset the persistent sleep override. Backups remain available separately.

## Development and verification

```sh
./scripts/build.sh
python3 tests/verify.py
./setup.sh --prefix '/tmp/mac-awake-staging' --no-activate
```

The build compiles and ad-hoc signs the app, runs its state-parser checks, and verifies its code signature. Python 3 is only needed for development tests. Tests simulate `pmset` to exercise success, denied authorization, failed reads, mismatched settings, and display-off failure without changing the test machine's power settings. The staged installer writes only under the given prefix and does not launch the app, import shortcuts, or change power settings.

`./scripts/build-shortcuts.sh` regenerates the readable shortcut plists from the command scripts and signs shareable `.shortcut` files. Signing sends the shortcut to Apple for validation and requires that service to be available. Commit both readable and signed files after regenerating. Normal installation uses the included signed files and does not need to sign them again.

The app builds natively for the target Mac. A local build/test is not proof of closed-lid operation on every Mac model or macOS release.
