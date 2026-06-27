#!/usr/bin/env bash
# Interactive installer for a fresh (or existing) macOS machine.
#
# Pure bash, and intentionally bash-3.2-compatible — macOS ships bash 3.2
# (/bin/bash), and this runs before Homebrew (and a newer bash) exist. No
# associative arrays, no bash-4 features. Driven by the `# group:NAME` tags in
# install/Brewfile (see install/REPRODUCIBILITY.md).
#
# Steps:
#   1. Symlink configs into ~/.config/ (from manifest.yaml)
#   2. Let you pick which package groups to install
#   3. brew bundle the selected subset (Core is always included)
#
# Usage:  install/install.sh                  # interactive group picker
#         install/install.sh --core           # non-interactive, Core only
#         install/install.sh --all            # non-interactive, everything
#         install/install.sh --include-stale  # also install not-recently-used apps
#
# Apps (casks/mas) not opened recently are tagged without `used:recent` and are
# skipped by default; core + CLI tools are always eligible. Toggle with `s` in
# the menu or --include-stale.

set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BREWFILE="$SCRIPT_DIR/Brewfile"
MANIFEST="$SCRIPT_DIR/manifest.yaml"

bold=$'\033[1m'; dim=$'\033[2m'; grn=$'\033[32m'; ylw=$'\033[33m'; cyn=$'\033[36m'; rst=$'\033[0m'
say()  { printf "%s\n" "$*"; }
hdr()  { printf "\n%s==> %s%s\n" "$bold" "$*" "$rst"; }
ok()   { printf "  %s✓%s %s\n" "$grn" "$rst" "$*"; }
warn() { printf "  %s!%s %s\n" "$ylw" "$rst" "$*"; }
have() { command -v "$1" &>/dev/null; }

# Group menu order. 'core' is implicit (always installed) and never shown as a
# toggle. Deliberately ABSENT (so never shown and never installed): `_dep`
# (transitive deps brew resolves on its own) and `_untagged` (newly-dumped
# packages awaiting a group — merge-brewfile-tags.py warns about these).
GROUP_ORDER=(shell editor terminal dev dev-apps jetbrains data cloud creative audio video writing office productivity reading comms security maintenance utilities remote system fonts games extras)

# bash 3.2 has no associative arrays, so labels are a case function and
# selection state is an indexed array (SEL) parallel to GROUP_ORDER.
group_label() {
  case "$1" in
    shell)        echo "Shell & CLI tools";;
    editor)       echo "Editor support (LSPs, formatters, prose tools)";;
    terminal)     echo "Terminal emulators (beyond core)";;
    dev)          echo "Dev runtimes & tooling (node, python, rust, docker…)";;
    dev-apps)     echo "Dev GUI apps (Xcode, GitHub, UTM, Godot…)";;
    jetbrains)    echo "JetBrains IDEs (CLion, DataGrip, PyCharm, WebStorm)";;
    data)         echo "Data science (Jupyter, R, NumPy, VisiData, DataSpell)";;
    cloud)        echo "Cloud & work CLIs (aws, cloudflare, terraform…)";;
    creative)     echo "Creative & graphics (Affinity, Pixelmator, Blender…)";;
    audio)        echo "Audio (Logic, GarageBand, Audacity, plugins…)";;
    video)        echo "Video (Infuse, VLC, HandBrake…)";;
    writing)      echo "Writing & notes (Scrivener, Ulysses, Marked…)";;
    office)       echo "Office (iWork, Microsoft Office)";;
    productivity) echo "Productivity (OmniFocus, Things, Alfred, Hazel…)";;
    reading)      echo "Reading & research (Kindle, Zotero, Bookends…)";;
    comms)        echo "Communication (Telegram, Discord, Zoom)";;
    security)     echo "Security (Little Snitch, KnockKnock, AdBlock…)";;
    maintenance)  echo "Maintenance (DaisyDisk, OnyX, archives…)";;
    utilities)    echo "Utilities (Chrome, ChatGPT, misc)";;
    remote)       echo "Remote & transfer (Screens, Prompt, Transmit…)";;
    system)       echo "System & menu bar (AppGrid, Hot, frameworks…)";;
    fonts)        echo "Fonts";;
    games)        echo "Games & toys";;
    extras)       echo "Extras (uncategorized — review these)";;
    *)            echo "$1";;
  esac
}

# Groups pre-selected when the menu opens.
DEFAULT_ON=(shell editor dev)
# Skip not-recently-used apps (casks/mas without `used:recent`) by default.
INCLUDE_STALE=0
# Selection state, parallel to GROUP_ORDER (SEL[i]=1 means group i selected).
SEL=()

group_index() {
  local i
  for i in "${!GROUP_ORDER[@]}"; do
    [[ "${GROUP_ORDER[$i]}" == "$1" ]] && { echo "$i"; return; }
  done
  echo -1
}

# entries tagged for a group; app lines may have a trailing ` used:recent`, so
# match the group name followed by space-or-EOL (keeps `dev` distinct from `dev-apps`).
count_group()        { local c; c=$(grep -cE "# group:$1( |\$)" "$BREWFILE" 2>/dev/null); echo "${c:-0}"; }
count_group_recent() { local c; c=$(grep -E "# group:$1( |\$)" "$BREWFILE" 2>/dev/null | grep -c 'used:recent'); echo "${c:-0}"; }

# ---------------------------------------------------------------------------
# Symlinks (config_symlinks / home_symlinks blocks of manifest.yaml)
# ---------------------------------------------------------------------------
# Parse a `  source: ~/target` block ($1) and create the symlinks. Source is a
# repo-relative path (may contain `/`); target is expanded from `~`. $2 = header.
link_block() {
  local block="$1"
  hdr "$2"
  [[ -f "$MANIFEST" ]] || { warn "no manifest.yaml — skipping"; return; }
  awk -v blk="$block" '
    $0 ~ "^" blk ":"   {inblk=1; next}
    /^[a-z_]+:/        {inblk=0}
    inblk && /^[[:space:]]+[A-Za-z0-9_.\/-]+:[[:space:]]*/ {
      sub(/#.*/, ""); gsub(/[[:space:]]/, "");
      split($0, kv, ":"); print kv[1] "\t" kv[2]
    }' "$MANIFEST" | while IFS=$'\t' read -r src tgt; do
    [[ -z "$src" || -z "$tgt" ]] && continue
    tgt="${tgt/#\~/$HOME}"
    local abs="$REPO_ROOT/$src"
    [[ -e "$abs" ]] || { warn "$src not in repo — skipping"; continue; }
    mkdir -p "$(dirname "$tgt")"
    if [[ -L "$tgt" && "$(readlink "$tgt")" == "$abs" ]]; then
      ok "$tgt (already linked)"
    elif [[ -e "$tgt" && ! -L "$tgt" ]]; then
      warn "$tgt exists and is not a symlink — leaving it; remove it manually to link"
    else
      ln -sfn "$abs" "$tgt" && ok "$tgt -> $src"
    fi
  done
}
link_configs() { link_block config_symlinks "Symlinking configs into ~/.config/"; }
link_home()    { link_block home_symlinks   "Symlinking dotfiles into ~/"; }

# ---------------------------------------------------------------------------
# Shell framework (oh-my-zsh + powerlevel10k + plugins)
# ---------------------------------------------------------------------------
# The always-symlinked zsh/.zshrc hard-requires oh-my-zsh and loads the
# powerlevel10k theme + zsh-syntax-highlighting plugin, so install them here
# regardless of which groups were chosen. Idempotent; safe to re-run.
clone_if_absent() {
  local url="$1" dir="$2" name="$3"
  if [[ -d "$dir" ]]; then ok "$name (present)"; return; fi
  if git clone --depth=1 "$url" "$dir" >/dev/null 2>&1; then ok "$name"; else warn "$name clone failed"; fi
}
install_shell_framework() {
  hdr "Installing shell framework (oh-my-zsh, powerlevel10k, plugins)"
  if ! have git; then warn "git not found — skipping (install Xcode CLT or the dev group, then re-run)"; return; fi
  local data="${XDG_DATA_HOME:-$HOME/.local/share}"
  local omz="$data/.oh-my-zsh"
  clone_if_absent "https://github.com/ohmyzsh/ohmyzsh.git" "$omz" "oh-my-zsh"
  [[ -d "$omz" ]] || return
  local custom="$omz/custom"
  clone_if_absent "https://github.com/romkatv/powerlevel10k.git"             "$custom/themes/powerlevel10k"            "powerlevel10k"
  clone_if_absent "https://github.com/zsh-users/zsh-syntax-highlighting.git" "$custom/plugins/zsh-syntax-highlighting" "zsh-syntax-highlighting"
  clone_if_absent "https://github.com/zsh-users/zsh-autosuggestions.git"     "$custom/plugins/zsh-autosuggestions"     "zsh-autosuggestions"
}

# ---------------------------------------------------------------------------
# Group selection
# ---------------------------------------------------------------------------
print_menu() {
  clear 2>/dev/null || true
  say "${bold}Choose package groups to install${rst}"
  say "${dim}Core (Claude Code, Obsidian) is always installed.${rst}"
  say ""
  local i g mark tot rec extra
  for i in "${!GROUP_ORDER[@]}"; do
    g="${GROUP_ORDER[$i]}"
    mark=" "; [[ "${SEL[$i]:-0}" == 1 ]] && mark="${grn}x${rst}"
    tot="$(count_group "$g")"; rec="$(count_group_recent "$g")"
    extra=""
    (( rec > 0 && rec < tot )) && extra=" ${cyn}${rec} recent${rst}"
    printf "  %2d) [%s] %-12s %s%s (%s)%s%s\n" "$((i+1))" "$mark" "$g" "$(group_label "$g")" "$dim" "$tot" "$rst" "$extra"
  done
  printf "\n  %sCore${rst} [%sx%s] always       Claude Code, Obsidian, daily-driver CLI %s(%s)%s\n" "$dim" "$grn" "$rst" "$dim" "$(count_group core)" "$rst"
  local stale_state; (( INCLUDE_STALE )) && stale_state="${ylw}INCLUDED${rst}" || stale_state="${dim}skipped${rst}"
  printf "\n  ${dim}Not-recently-used apps:${rst} %s ${dim}(press ${rst}s${dim} to toggle)${rst}\n" "$stale_state"
  say "${dim}Number=toggle group  ${rst}a${dim}=all  ${rst}n${dim}=none  ${rst}s${dim}=stale apps  ${rst}Enter${dim}=install  ${rst}q${dim}=quit${rst}"
}

select_groups() {
  local g idx i choice
  for g in "${DEFAULT_ON[@]}"; do idx="$(group_index "$g")"; (( idx >= 0 )) && SEL[$idx]=1; done
  while true; do
    print_menu
    printf "> "
    # Read from the controlling terminal so the menu works under `curl … | bash`,
    # where stdin is the pipe (not the keyboard). No tty → fall through to defaults.
    read -r choice </dev/tty 2>/dev/null || break
    case "$choice" in
      "" ) break ;;
      q|Q ) say "Aborted."; exit 0 ;;
      a|A ) for i in "${!GROUP_ORDER[@]}"; do SEL[$i]=1; done ;;
      n|N ) for i in "${!GROUP_ORDER[@]}"; do SEL[$i]=0; done ;;
      s|S ) INCLUDE_STALE=$(( INCLUDE_STALE ^ 1 )) ;;
      *[!0-9]* ) : ;;  # ignore non-numeric
      * )
        idx=$((choice-1))
        if (( idx >= 0 && idx < ${#GROUP_ORDER[@]} )); then
          SEL[$idx]=$(( ${SEL[$idx]:-0} ^ 1 ))
        fi ;;
    esac
  done
}

selected_list() {
  local out="core" i
  for i in "${!GROUP_ORDER[@]}"; do
    [[ "${SEL[$i]:-0}" == 1 ]] && out+=" ${GROUP_ORDER[$i]}"
  done
  echo "$out"
}

# ---------------------------------------------------------------------------
# Brew bundle the selected subset
# ---------------------------------------------------------------------------
run_bundle() {
  local selected="$1"
  local tmp; tmp="$(mktemp -t Brewfile.XXXXXX)"
  # taps are always included; then any entry whose group is selected. Apps
  # (casks/mas) without `used:recent` are skipped unless INCLUDE_STALE — core
  # and CLI (brew) entries are never skipped.
  grep -E '^tap ' "$BREWFILE" > "$tmp"
  local skipped=0
  while IFS= read -r line; do
    local g kind; g="$(sed -nE 's/.*# group:([a-z_-]+).*/\1/p' <<<"$line")"; kind="${line%% *}"
    [[ -z "$g" ]] && continue
    [[ " $selected " == *" $g "* ]] || continue
    if [[ "$g" == core || "$kind" == brew || "$line" == *used:recent* ]] || (( INCLUDE_STALE )); then
      echo "$line" >> "$tmp"
    else
      skipped=$((skipped+1))
    fi
  done < <(grep -E '^(brew|cask|mas) ' "$BREWFILE")

  local n; n="$(grep -cE '^(brew|cask|mas) ' "$tmp")"
  hdr "Installing $n packages from groups: $selected"
  (( skipped > 0 )) && say "  ${dim}($skipped not-recently-used app(s) skipped — press ${rst}s${dim} in the menu or pass ${rst}--include-stale${dim} to add them)${rst}"
  if ! have brew; then warn "Homebrew not found — run bootstrap.sh first"; rm -f "$tmp"; return 1; fi
  say "${dim}(brew resolves dependencies automatically — _dep-tagged formulae are pulled in as needed)${rst}"
  brew bundle install --file="$tmp" --no-upgrade
  local rc=$?
  rm -f "$tmp"
  (( rc == 0 )) && ok "brew bundle complete" || warn "brew bundle exited $rc — review output above"
  return $rc
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
main() {
  local mode=""
  for a in "$@"; do
    case "$a" in
      --include-stale) INCLUDE_STALE=1 ;;
      --core) mode=core ;;
      --all)  mode=all ;;
      -h|--help) sed -n '2,22p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; return 0 ;;
    esac
  done
  link_configs
  link_home
  case "$mode" in
    core) run_bundle "core" ;;
    all)  INCLUDE_STALE=1; run_bundle "core ${GROUP_ORDER[*]}" ;;
    *)    select_groups; run_bundle "$(selected_list)" ;;
  esac
  install_shell_framework
  hdr "Done"
  say "Re-run anytime to add more groups. Inventory drift: ${cyn}install/refresh-inventory.sh${rst}"
}

main "$@"
