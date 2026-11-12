#!/bin/zsh
# Restore normal sleep eligibility without changing existing sleep/display timers.
set -eu

print 'Restoring normal sleep behavior.'
print 'macOS may ask for your administrator password; typing is invisible.'
/usr/bin/sudo /usr/bin/pmset -a disablesleep 0
power_settings=$(/usr/bin/pmset -g)
if ! print -r -- "$power_settings" | /usr/bin/awk '$1 == "SleepDisabled" && $2 == 0 { found=1 } END { exit !found }'; then
    print -u2 'Could not verify SleepDisabled=0. Check: pmset -g'
    exit 1
fi
print 'Keep-awake is OFF. Normal sleep is allowed again.'
print 'Your existing sleep and display timers are unchanged.'
print 'If Amphetamine or another keep-awake app is active, end its session too.'
