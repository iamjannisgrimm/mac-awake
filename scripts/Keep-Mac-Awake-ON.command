#!/bin/zsh
# Prevent system sleep, including lid-close sleep. Persists until switched off.
# Only changes SleepDisabled; existing sleep/display timers stay untouched.
set -eu

print 'Enabling keep-awake mode (charger and battery).'
print 'macOS may ask for your administrator password; typing is invisible.'
/usr/bin/sudo /usr/bin/pmset -a disablesleep 1
power_settings=$(/usr/bin/pmset -g)
if ! print -r -- "$power_settings" | /usr/bin/awk '$1 == "SleepDisabled" && $2 == 1 { found=1 } END { exit !found }'; then
    print -u2 'Could not verify SleepDisabled=1. Check: pmset -g'
    exit 1
fi
print 'Keep-awake is ON, including on battery and after restarting.'
print 'Run Keep-Mac-Awake-OFF.command to allow sleep again.'
print 'Keep the Mac ventilated and preferably plugged in.'
print 'The display will turn off in 5 seconds. You can then close the lid.'
/bin/sleep 5
if ! /usr/bin/pmset displaysleepnow; then
    print -u2 'Keep-awake is enabled, but the display-off request failed.'
    exit 1
fi
