#!/bin/zsh
# Run as the logged-in user. Only the sleep shortcuts need administrator access.
set -eu
repo_dir="${0:A:h}"
install_root="$HOME"
activate=1
while (( $# )); do
    case "$1" in
        --prefix) (( $# >= 2 )) || { print -u2 'Missing --prefix path'; exit 2; }; install_root="${2:A}"; shift 2 ;;
        --no-activate) activate=0; shift ;;
        --help|-h)
            print 'Usage: ./setup.sh [--no-activate] [--prefix PATH]'
            print 'Custom prefixes require --no-activate (for staging/testing).'
            exit 0 ;;
        *) print -u2 "Unknown option: $1"; exit 2 ;;
    esac
done
[[ "$(/usr/bin/uname -s)" == Darwin ]] || { print -u2 'Mac Awake requires macOS.'; exit 1; }
(( EUID != 0 )) || { print -u2 'Run setup as your normal user, without sudo.'; exit 1; }
[[ "$install_root" == "$HOME" || "$activate" == 0 ]] || { print -u2 'Use --no-activate with a custom prefix.'; exit 2; }
major_version=$(/usr/bin/sw_vers -productVersion)
(( ${major_version%%.*} >= 14 )) || { print -u2 'macOS 14 or newer is required.'; exit 1; }
/usr/bin/xcrun --find swiftc >/dev/null 2>&1 || {
    print -u2 'Install Apple Command Line Tools with: xcode-select --install'
    print -u2 'After installation finishes, run setup again.'
    exit 1
}
for mode in On Off; do
    [[ -s "$repo_dir/Shortcuts/Keep Mac Awake $mode.shortcut" ]] || {
        print -u2 "Missing signed shortcut: Keep Mac Awake $mode. Download the complete repository."
        exit 1
    }
done
app_dir="$install_root/Applications/Mac Awake.app"
scripts_dir="$install_root/Library/Scripts/Keep Mac Awake"
agent_dir="$install_root/Library/LaunchAgents"
agent="$agent_dir/com.jannisgrimm.mac-awake.plist"
service="gui/$UID/com.jannisgrimm.mac-awake"
temp_dir=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp/}mac-awake-install.XXXXXX")
trap '/bin/rm -rf "$temp_dir"' EXIT

# Compile and verify everything before touching an installed copy.
/bin/zsh "$repo_dir/scripts/build.sh" "$temp_dir/Mac Awake.app"
/usr/bin/plutil -create xml1 "$temp_dir/agent.plist"
/usr/bin/plutil -insert Label -string com.jannisgrimm.mac-awake "$temp_dir/agent.plist"
/usr/bin/plutil -insert ProgramArguments -json '[]' "$temp_dir/agent.plist"
/usr/bin/plutil -insert ProgramArguments.0 -string "$app_dir/Contents/MacOS/MacAwake" "$temp_dir/agent.plist"
/usr/bin/plutil -insert RunAtLoad -bool YES "$temp_dir/agent.plist"
/usr/bin/plutil -insert KeepAlive -json '{"SuccessfulExit":false}' "$temp_dir/agent.plist"
/usr/bin/plutil -insert LimitLoadToSessionType -string Aqua "$temp_dir/agent.plist"
/usr/bin/plutil -insert ProcessType -string Interactive "$temp_dir/agent.plist"
/usr/bin/plutil -lint "$temp_dir/agent.plist"

# Preserve existing app, scripts and launch configuration on every replacement.
backup_base="$install_root/Library/Application Support/Mac Awake/Backups"
mkdir -p "$backup_base"
backup_dir=$(/usr/bin/mktemp -d "$backup_base/install-$(/bin/date +%Y%m%d-%H%M%S).XXXXXX")
[[ ! -e "$app_dir" ]] || /usr/bin/ditto "$app_dir" "$backup_dir/Mac Awake.app"
[[ ! -e "$scripts_dir" ]] || /usr/bin/ditto "$scripts_dir" "$backup_dir/Keep Mac Awake"
[[ ! -e "$agent" ]] || /bin/cp "$agent" "$backup_dir/com.jannisgrimm.mac-awake.plist"
if (( activate )); then
    if /bin/launchctl print "$service" >/dev/null 2>&1; then
        /bin/launchctl bootout "$service"
    fi
    # Match only our installed executable, never another user's/process's name.
    for pid in ${(f)"$(/bin/ps -axo pid=,comm= | /usr/bin/awk -v app="$app_dir/Contents/MacOS/MacAwake" 'substr($0, index($0, "/")) == app {print $1}')"}; do
        [[ -n "$pid" ]] || continue
        /bin/kill -TERM "$pid"
        for attempt in {1..50}; do
            /bin/kill -0 "$pid" 2>/dev/null || break
            /bin/sleep 0.1
        done
        if /bin/kill -0 "$pid" 2>/dev/null; then
            print -u2 'Mac Awake is still exiting. Wait for it to quit, then rerun setup.'
            exit 1
        fi
    done
fi
mkdir -p "$install_root/Applications" "$scripts_dir/MenuBar" "$agent_dir"
if [[ -e "$app_dir" ]]; then /bin/mv "$app_dir" "$temp_dir/previous.app"; fi
/usr/bin/ditto "$temp_dir/Mac Awake.app" "$app_dir"
for mode in ON OFF; do
    /usr/bin/install -m 755 "$repo_dir/scripts/Keep-Mac-Awake-$mode.command" "$scripts_dir/Keep-Mac-Awake-$mode.command"
done
/bin/cp "$repo_dir/Sources/main.swift" "$scripts_dir/MenuBar/main.swift"
/usr/bin/install -m 644 "$temp_dir/agent.plist" "$agent"
if (( ! activate )); then
    print "Staged at $install_root. No app launched, shortcuts imported or sleep settings changed."
    exit 0
fi

# Shortcuts has no supported silent-import CLI. Open each missing signed file,
# let macOS show Add Shortcut, and verify the exact name before continuing.
for mode in On Off; do
    name="Keep Mac Awake $mode"
    existing=$(/usr/bin/shortcuts list) || { print -u2 'Cannot list Shortcuts. Open Shortcuts and run setup again.'; exit 1; }
    if ! print -r -- "$existing" | /usr/bin/grep -Fxq "$name"; then
        print "In Shortcuts, add '$name' without renaming it. Waiting up to 5 minutes…"
        /usr/bin/open "$repo_dir/Shortcuts/$name.shortcut"
        added=0
        for attempt in {1..150}; do
            existing=$(/usr/bin/shortcuts list) || exit 1
            if print -r -- "$existing" | /usr/bin/grep -Fxq "$name"; then added=1; break; fi
            /bin/sleep 2
        done
        (( added )) || { print -u2 "'$name' was not imported. Add it and run setup again."; exit 1; }
    else
        print "Keeping existing shortcut: $name"
    fi
done
/bin/launchctl enable "$service"
/bin/launchctl bootstrap "gui/$UID" "$agent"
/bin/sleep 2
/bin/launchctl print "$service" | /usr/bin/grep -q 'state = running' || {
    print -u2 'App installed but not running. Check System Settings > General > Login Items.'
    exit 1
}
print 'Mac Awake is running and registered to start at login.'
print 'Click the menu bar icon to toggle; right-click for options.'
print 'Sleep settings were not changed by setup.'
print "Previous installation backup: $backup_dir"
