#!/bin/zsh
/bin/zsh "${0:A:h}/compatibility.zsh" status
result=$?
print
if [[ -t 0 ]]; then read -r '?Press Return to close. '; fi
exit "$result"
