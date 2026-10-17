#!/bin/zsh
# An SDL backend preference, not a universal controller driver.
# Uses only tools included with macOS. Run as your normal user, without sudo.
setopt NO_UNSET PIPE_FAIL
export LC_ALL=C
umask 077

readonly label='local.codex.8bitdo-sdl-compatibility'
readonly setting='SDL_JOYSTICK_MFI'
readonly user_home="${HOME:?HOME is not set}"
readonly support_dir="$user_home/Library/Application Support/8BitDo Compatibility"
readonly state_file="$support_dir/previous-setting.json"
readonly agent_dir="$user_home/Library/LaunchAgents"
readonly agent_file="$agent_dir/$label.plist"
readonly domain="gui/$UID"
readonly agent_xml='<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>local.codex.8bitdo-sdl-compatibility</string>
<key>ProgramArguments</key><array><string>/bin/launchctl</string><string>setenv</string><string>SDL_JOYSTICK_MFI</string><string>0</string></array>
<key>RunAtLoad</key><true/>
</dict></plist>'

launch_output='' launch_result=0 job_loaded=0
current_value='' current_set=0 saved_value='' saved_set=0
state_tmp='' agent_tmp='' transaction_active=0
had_state=0 had_agent=0 old_job_loaded=0 before_value='' before_set=0

error() { print -u2 -r -- "Error: $*"; return 1; }

# Preserve embedded and trailing newlines in environment values. The final
# separator carries the exit code and prevents command substitution trimming.
capture_launchctl() {
    local captured
    captured=$(/bin/launchctl "$@" 2>&1; local result=$?; print -rn -- $'\x1f'"$result")
    launch_result="${captured##*$'\x1f'}"
    launch_output="${captured%$'\x1f'*}"
    launch_output="${launch_output%$'\n'}"
    return "$launch_result"
}

run_launchctl() {
    capture_launchctl "$@" && return 0
    error "launchctl $1 failed ($launch_result): $launch_output"
}

check_job() {
    if capture_launchctl print "$domain/$label"; then
        job_loaded=1
    elif [[ "$launch_result" == 113 && "$launch_output" == *'Could not find service'* ]]; then
        job_loaded=0
    else
        error "Cannot inspect the login job ($launch_result): $launch_output"
        return 1
    fi
}

unload_job() {
    check_job || return 1
    if (( job_loaded )); then
        run_launchctl bootout "$domain/$label" || return 1
    fi
    check_job || return 1
    (( ! job_loaded )) || { error 'The login job is still loaded; the backup has been preserved.'; return 1; }
}

read_current() {
    run_launchctl getenv "$setting" || return 1
    current_value="$launch_output"
    current_set=0
    [[ -z "$current_value" ]] || current_set=1
}

restore_value() {
    if (( $1 )); then
        run_launchctl setenv "$setting" "$2"
    else
        run_launchctl unsetenv "$setting"
    fi
}

verify_agent() {
    [[ ! -L "$agent_file" ]] || { error 'The login configuration is a symbolic link; it was left untouched.'; return 1; }
    [[ -e "$agent_file" ]] || return 0
    [[ -f "$agent_file" ]] || { error 'The login configuration is not a regular file.'; return 1; }
    local actual expected
    actual=$(/usr/bin/plutil -convert xml1 -o - -- "$agent_file") || return 1
    expected=$(print -r -- "$agent_xml" | /usr/bin/plutil -convert xml1 -o - -- -) || return 1
    [[ "$actual" == "$expected" ]] || { error "A different login configuration already uses $agent_file; it was left untouched."; return 1; }
}

read_snapshot() {
    [[ -f "$state_file" && ! -L "$state_file" ]] || { error 'The saved configuration is not a regular file; nothing was changed.'; return 1; }
    local version key previous_type captured
    version=$(/usr/bin/plutil -extract version raw -expect integer -o - -- "$state_file") || return 1
    key=$(/usr/bin/plutil -extract key raw -expect string -o - -- "$state_file") || return 1
    [[ "$version" == 1 && "$key" == "$setting" ]] || { error 'The saved configuration has an unexpected format; nothing was changed.'; return 1; }
    saved_set=0 saved_value=''
    if previous_type=$(/usr/bin/plutil -type previousValue -- "$state_file" 2>/dev/null); then
        [[ "$previous_type" == string ]] || { error 'The previous setting is not a string; nothing was changed.'; return 1; }
        captured=$(/usr/bin/plutil -extract previousValue raw -expect string -o - -- "$state_file"; local result=$?; print -rn -- $'\x1f'"$result")
        [[ "${captured##*$'\x1f'}" == 0 ]] || { error 'Could not read the previous setting.'; return 1; }
        saved_value="${captured%$'\x1f'*}"
        saved_value="${saved_value%$'\n'}"
        saved_set=1
    fi
}

cleanup_temps() {
    [[ -z "$state_tmp" ]] || /bin/rm -f -- "$state_tmp"
    [[ -z "$agent_tmp" ]] || /bin/rm -f -- "$agent_tmp"
    return 0
}

rollback_enable() {
    transaction_active=0
    print -u2 -r -- 'Installation did not finish. Restoring the previous configuration.'
    if ! unload_job; then
        print -u2 -r -- 'The configuration and backup have been kept so Undo can be retried.'
        return 1
    fi
    local rollback_ok=1
    if (( had_agent && old_job_loaded )); then
        run_launchctl bootstrap "$domain" "$agent_file" || rollback_ok=0
    fi
    restore_value "$before_set" "$before_value" || rollback_ok=0
    if (( ! rollback_ok )); then
        print -u2 -r -- 'The configuration and backup have been kept so Undo can be retried.'
        return 1
    fi
    (( had_agent )) || /bin/rm -f -- "$agent_file" || return 1
    (( had_state )) || /bin/rm -f -- "$state_file" || return 1
}

TRAPEXIT() {
    local exit_result=$?
    if (( transaction_active )); then rollback_enable; fi
    cleanup_temps
    return "$exit_result"
}
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

enable_changes() {
    /bin/mkdir -p -- "$support_dir" "$agent_dir" || return 1
    if (( ! had_state )); then
        state_tmp=$(/usr/bin/mktemp "$support_dir/.previous-setting.XXXXXX") || return 1
        print -r -- '{"version":1,"key":"SDL_JOYSTICK_MFI"}' > "$state_tmp" || return 1
        if (( before_set )); then
            /usr/bin/plutil -insert previousValue -string "$before_value" -- "$state_tmp" || return 1
        fi
        /bin/chmod 600 "$state_tmp" || return 1
        /bin/mv -f -- "$state_tmp" "$state_file" || return 1
        state_tmp=''
    fi
    agent_tmp=$(/usr/bin/mktemp "$agent_dir/.8bitdo-sdl-compatibility.XXXXXX") || return 1
    print -r -- "$agent_xml" > "$agent_tmp" || return 1
    /usr/bin/plutil -lint -- "$agent_tmp" >/dev/null || return 1
    /bin/chmod 644 "$agent_tmp" || return 1
    /bin/mv -f -- "$agent_tmp" "$agent_file" || return 1
    agent_tmp=''
    unload_job || return 1
    run_launchctl bootstrap "$domain" "$agent_file" || return 1
    run_launchctl setenv "$setting" 0 || return 1
    read_current || return 1
    [[ "$current_value" == 0 ]] || { error 'The setting did not take effect.'; return 1; }
}

enable_compatibility() {
    verify_agent || return 1
    [[ ! -L "$state_file" ]] || { error 'The saved configuration is a symbolic link; it was left untouched.'; return 1; }
    [[ ! -e "$state_file" ]] || had_state=1
    [[ ! -e "$agent_file" ]] || had_agent=1
    check_job || return 1
    old_job_loaded=$job_loaded
    if (( old_job_loaded && ! had_agent )); then
        error 'A job with this name exists without our configuration file; it was left untouched.'
        return 1
    fi
    if (( had_state )); then read_snapshot || return 1
    elif (( had_agent )); then
        error 'The login configuration exists but its backup is missing; it was left untouched.'
        return 1
    fi
    read_current || return 1
    before_value="$current_value" before_set=$current_set
    transaction_active=1
    if enable_changes; then transaction_active=0
    else
        rollback_enable
        return 1
    fi
    print -r -- '8BitDo SDL compatibility is enabled and will be reapplied at login.'
    print -r -- 'Fully quit and reopen games, Steam, CrossOver, and mapping utilities.'
    print -r -- 'This helps SDL apps; Apple GameController-only apps are unchanged.'
}

disable_compatibility() {
    verify_agent || return 1
    if [[ ! -e "$state_file" && ! -L "$state_file" ]]; then
        print -r -- 'No saved installation was found. No settings were changed.'
        return 0
    fi
    read_snapshot || return 1
    unload_job || return 1
    read_current || return 1
    if [[ "$current_value" == 0 ]]; then
        restore_value "$saved_set" "$saved_value" || return 1
    else
        print -r -- 'The SDL setting was changed elsewhere and has been preserved.'
    fi
    /bin/rm -f -- "$agent_file" || return 1
    /bin/rm -f -- "$state_file" || return 1
    print -r -- '8BitDo SDL compatibility is removed. Fully quit and reopen affected apps.'
}

show_status() {
    read_current || return 1
    print -r -- "$setting=${current_value:-<unset>}"
    if [[ -e "$agent_file" ]]; then
        verify_agent || return 1
        print -r -- 'Login configuration: installed'
    else
        print -r -- 'Login configuration: not installed'
    fi
    check_job || return 1
    if (( job_loaded )); then
        print -r -- 'Login job: loaded'
    else
        print -r -- 'Login job: not loaded'
    fi
    print -r -- 'Scope: SDL-based apps; not a universal controller driver.'
}

[[ "$OSTYPE" == darwin* ]] || { error 'This workaround requires macOS 12 Monterey or newer.'; exit 1; }
macos_version=$(/usr/bin/sw_vers -productVersion) || exit 1
macos_major="${macos_version%%.*}"
[[ "$macos_major" == <-> ]] && (( macos_major >= 12 )) || {
    error 'This workaround requires macOS 12 Monterey or newer.'
    exit 1
}
(( UID != 0 )) || { error 'Run this as your normal Mac user, without sudo.'; exit 1; }
[[ "$user_home" == /* ]] || { error 'HOME must be an absolute path.'; exit 1; }
case "${1:-status}" in
    enable) enable_compatibility || exit 1 ;;
    disable) disable_compatibility || exit 1 ;;
    status) show_status || exit 1 ;;
    *) error 'Usage: compatibility.zsh [enable|disable|status]'; exit 1 ;;
esac
