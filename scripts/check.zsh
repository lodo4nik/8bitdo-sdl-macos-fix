#!/bin/zsh
# Static checks only. Never enable/disable compatibility or access a controller.
setopt ERR_EXIT NO_UNSET PIPE_FAIL
readonly repo_dir="${0:A:h:h}"
cd -- "$repo_dir"

required_files=(
    README.md LICENSE
    compatibility.zsh 'Enable Compatibility.command' 'Undo Compatibility.command'
    Status.command scripts/check.zsh .gitignore .gitattributes
    .github/workflows/check.yml
)
for repo_file in "${required_files[@]}"; do
    [[ -s "$repo_file" ]] || { print -u2 -r -- "Missing or empty file: $repo_file"; exit 1; }
done

shell_files=(compatibility.zsh *.command scripts/*.zsh)
for repo_file in "${shell_files[@]}"; do
    /bin/zsh -n "$repo_file"
    [[ -x "$repo_file" ]] || { print -u2 -r -- "Missing executable permission: $repo_file"; exit 1; }
    [[ "$(/usr/bin/head -n 1 "$repo_file")" == '#!/bin/zsh' ]] || {
        print -u2 -r -- "Unexpected interpreter: $repo_file"
        exit 1
    }
    if LC_ALL=C /usr/bin/grep -q $'\r' "$repo_file"; then
        print -u2 -r -- "CRLF line endings: $repo_file"
        exit 1
    fi
done

if [[ -d .git ]]; then
    /usr/bin/git diff --check
    /usr/bin/git diff --cached --check
fi
print -r -- "Static checks passed for ${#shell_files} scripts. No user settings were changed."
