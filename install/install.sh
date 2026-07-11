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
#   2. Ensure a per-machine SSH key exists (~/.ssh/id_ed25519)
#   3. Let you pick which package groups to install (browse contents with `v`)
#   4. Review the exact package list, then brew bundle it (Core always included)
#   5. Pick which LaunchAgents (install/launchagents/*.plist) this machine runs
#
# Usage:  install/install.sh                  # interactive group picker
#         install/install.sh --core           # non-interactive, Core only
#         install/install.sh --all            # non-interactive, everything
#         install/install.sh --groups a,b,c   # non-interactive: these groups + core (their apps install regardless of recency)
#         install/install.sh --launchagents a,b   # non-interactive: install these launchagents (labels, or 'all'/'none')
#         install/install.sh --include-stale  # also install not-recently-used apps
#         install/install.sh --dry-run        # print the resolved package list and exit (no install)
#
# In the interactive menu: number toggles a group, `v` browses a group's
# packages (kind, recent/stale, descriptions), and Enter shows a review of the
# exact list before anything is installed. Combine --dry-run with --core/--all/
# --groups to preview a non-interactive selection.
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
GROUP_ORDER=(shell editor terminal dev dev-apps llm jetbrains data cloud creative audio video writing office productivity reading comms security safari-extensions maintenance utilities remote system fonts games extras)

# bash 3.2 has no associative arrays, so labels are a case function and
# selection state is an indexed array (SEL) parallel to GROUP_ORDER.
group_label() {
  case "$1" in
    shell)        echo "Shell & CLI tools";;
    editor)       echo "Editor support (LSPs, formatters, prose tools)";;
    terminal)     echo "Terminal emulators (beyond core)";;
    dev)          echo "Dev runtimes & tooling (node, python, rust, docker…)";;
    dev-apps)     echo "Dev GUI apps (Chrome, Xcode, GitHub, UTM, Godot…)";;
    llm)          echo "Agent & LLM tooling (Ollama, ChatGPT, HuggingFace, sandboxing…)";;
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
    security)     echo "Security (Little Snitch, KnockKnock, Micro Snitch…)";;
    safari-extensions) echo "Safari extensions (Tampermonkey, AdBlock Pro, clippers…)";;
    maintenance)  echo "Maintenance (DaisyDisk, OnyX, archives…)";;
    utilities)    echo "Utilities (misc GUI apps)";;
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
# --dry-run: resolve and print the package list, install nothing.
DRY_RUN=0
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
# Brewfile row parsing (shared by browse / review / bundle)
# ---------------------------------------------------------------------------
# Emit one row per brew/cask/mas entry, fields joined by the ASCII unit
# separator (\037 — chosen because a whitespace IFS collapses empty fields, which
# would shift the raw line into an empty description column):
#   group US kind US name US recent(0|1) US description US rawline
# `brew bundle dump --describe` writes a `# <description>` comment directly above
# an entry (some casks/mas have none → empty field). The raw line is preserved
# verbatim so the generated Brewfile keeps mas `id:` args etc. intact.
all_rows() {
  awk '
    BEGIN { US = sprintf("%c", 31) }
    /^# / && $0 !~ /^# group:/ { d = substr($0, 3); next }   # capture a description comment
    /^(brew|cask|mas) / {
      kind = $1
      match($0, /"[^"]+"/); name = substr($0, RSTART+1, RLENGTH-2)
      g = ""; if (match($0, /# group:[A-Za-z0-9_-]+/)) g = substr($0, RSTART+8, RLENGTH-8)
      rec = ($0 ~ /used:recent/) ? 1 : 0
      print g US kind US name US rec US d US $0
      d = ""; next
    }
    { d = "" }                                               # any other line clears a pending description
  ' "$BREWFILE"
}

# Would this entry be installed given the current INCLUDE_STALE setting?
# Core and CLI (brew) entries are always eligible; recently-used apps too.
# Not-recently-used casks/mas are skipped unless INCLUDE_STALE.  Args: group kind rec
is_included() {
  [[ "$1" == core || "$2" == brew || "$3" == 1 ]] && return 0
  (( INCLUDE_STALE )) && return 0
  return 1
}

# Print a single group's packages with kind, recent/stale status, description.
browse_group() {
  local g="$1" grp kind name rec desc raw state shown=0
  hdr "$(group_label "$g")  ${dim}[$g]${rst}"
  while IFS=$'\037' read -r grp kind name rec desc raw; do
    [[ "$grp" == "$g" ]] || continue
    shown=$((shown+1))
    if [[ "$kind" == brew || "$g" == core ]]; then state="${dim}always${rst}"
    elif (( rec )); then                              state="${cyn}recent${rst}"
    else                                              state="${ylw}stale ${rst}"; fi
    printf "  %-5s %-26s %b  %s\n" "$kind" "$name" "$state" "${desc:+$dim$desc$rst}"
  done < <(all_rows)
  (( shown == 0 )) && say "  ${dim}(no packages in this group)${rst}"
  say ""
  printf "%s(Enter to return to the menu)%s " "$dim" "$rst"
  read -r _ </dev/tty 2>/dev/null || true
}

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
      i = index($0, ":"); print substr($0, 1, i-1) "\t" substr($0, i+1)
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
  # Gate on a finalized clone (.git), not bare dir existence: an interrupted
  # clone can leave a partial dir that a `-d` check would treat as complete.
  if [[ -e "$dir/.git" ]]; then ok "$name (present)"; return; fi
  [[ -d "$dir" ]] && rm -rf "$dir"   # partial/interrupted clone — start clean
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
}

# ---------------------------------------------------------------------------
# SSH key (per-machine identity)
# ---------------------------------------------------------------------------
# Each machine gets its own ed25519 keypair, generated here — private keys are
# never migrated between machines. After a fresh install, register the pubkey
# with GitHub and any ssh hosts.
ensure_ssh_key() {
  hdr "SSH key"
  local key="$HOME/.ssh/id_ed25519"
  if [[ -f "$key" ]]; then ok "id_ed25519 (present)"; return 0; fi
  have ssh-keygen || { warn "ssh-keygen not found — skipping"; return 0; }
  mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
  local host; host="$(scutil --get LocalHostName 2>/dev/null || hostname -s)"
  if ssh-keygen -t ed25519 -N "" -f "$key" -C "nelson@${host}" >/dev/null; then
    ok "generated ~/.ssh/id_ed25519 (nelson@${host})"
    say "  ${ylw}Register the public key:${rst} gh ssh-key add ~/.ssh/id_ed25519.pub --title \"${host}\""
    say "  ${dim}(and append it to authorized_keys on hosts you ssh into)${rst}"
  else
    warn "ssh-keygen failed"
  fi
}

# ---------------------------------------------------------------------------
# LaunchAgents (install/launchagents/*.plist)
# ---------------------------------------------------------------------------
# Per-machine background jobs. The plists are committed here (secrets stay in
# external files they reference); each machine picks the subset it should run.
LAUNCHAGENTS_DIR="$SCRIPT_DIR/launchagents"
LAUNCHAGENTS=""   # --launchagents: comma-separated labels, or 'all' / 'none'

launchagent_desc() {
  case "$1" in
    dev.tickle.daemon)               echo "Tickle job daemon (agent-approvals stack)";;
    love.nelson.obsidian)            echo "Obsidian at login w/ perf flags (8GB heap, no throttling)";;
    com.nelson.cloudflared-obsidian) echo "Cloudflare tunnel for remote vault MCP (needs token file)";;
    com.nelson.comms-agent)          echo "Comms agent at login (tmux + claude --remote-control; needs ~/agents/comms)";;
    com.nelson.legal-mail.poll)      echo "Poll legal mail every 2h (needs ~/repos/legal-mail)";;
    com.nelson.refresh-contacts)     echo "Nightly contacts.json rebuild (needs refresh-contacts)";;
    com.nelson.vault-mcp-remote)     echo "Remote vault MCP proxy (needs plugin build + env file)";;
    com.nelson.vault-skills-export)  echo "Hourly vault-skills export tick";;
    *)                               echo "";;
  esac
}

install_launchagent() {
  local plist="$1" label tgt
  label="$(basename "$plist" .plist)"
  tgt="$HOME/Library/LaunchAgents/$label.plist"
  mkdir -p "$HOME/Library/LaunchAgents"
  if [[ -f "$tgt" ]] && cmp -s "$plist" "$tgt"; then
    ok "$label (already installed)"
    return 0
  fi
  cp "$plist" "$tgt" || { warn "$label — copy failed"; return 1; }
  # Reload cleanly: bootout is a no-op when not loaded; bootstrap loads the copy.
  launchctl bootout "gui/$(id -u)" "$tgt" 2>/dev/null
  if launchctl bootstrap "gui/$(id -u)" "$tgt" 2>/dev/null; then
    ok "$label (installed + loaded)"
  else
    warn "$label — copied, but launchctl bootstrap failed (missing binary/paths on this machine?)"
  fi
}

# $1 = 1 when running non-interactively (--core/--all/--groups): no picker.
install_launchagents() {
  local noninteractive="${1:-0}" plists=() p label i choice picked mark
  for p in "$LAUNCHAGENTS_DIR"/*.plist; do [[ -e "$p" ]] && plists+=("$p"); done
  (( ${#plists[@]} )) || return 0
  hdr "LaunchAgents"
  case "$LAUNCHAGENTS" in
    none) say "  ${dim}skipped (--launchagents none)${rst}"; return 0 ;;
    all)  for p in "${plists[@]}"; do install_launchagent "$p"; done; return 0 ;;
    "")   : ;;  # fall through
    *)
      local _l; IFS=',' read -ra _l <<<"$LAUNCHAGENTS"
      for label in "${_l[@]}"; do
        [[ -z "$label" ]] && continue
        if [[ -f "$LAUNCHAGENTS_DIR/$label.plist" ]]; then
          install_launchagent "$LAUNCHAGENTS_DIR/$label.plist"
        else
          warn "unknown launchagent '$label' — available: $(cd "$LAUNCHAGENTS_DIR" && ls ./*.plist | sed 's|^\./||; s/\.plist$//' | tr '\n' ' ')"
        fi
      done
      return 0 ;;
  esac
  if (( noninteractive )); then
    say "  ${dim}skipped (pass --launchagents LABEL,LABEL / all / none in non-interactive runs)${rst}"
    return 0
  fi
  say "${dim}Per-machine background jobs — pick what this machine should run. [x] = already present.${rst}"
  for i in "${!plists[@]}"; do
    label="$(basename "${plists[$i]}" .plist)"
    mark=" "; [[ -f "$HOME/Library/LaunchAgents/$label.plist" ]] && mark="${grn}x${rst}"
    printf "  %2d) [%b] %-34s %s%s%s\n" "$((i+1))" "$mark" "$label" "$dim" "$(launchagent_desc "$label")" "$rst"
  done
  printf "\ninstall which? (e.g. '1 3', a=all, Enter=skip) > "
  read -r choice </dev/tty 2>/dev/null || choice=""
  case "$choice" in
    "")  say "  ${dim}skipped${rst}" ;;
    a|A) for p in "${plists[@]}"; do install_launchagent "$p"; done ;;
    *)
      for picked in $choice; do
        [[ "$picked" =~ ^[0-9]+$ ]] || continue
        i=$((picked-1))
        (( i >= 0 && i < ${#plists[@]} )) && install_launchagent "${plists[$i]}"
      done ;;
  esac
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
  printf "\n  %2d) [%sx%s] %-12s Core — always installed (Claude Code, Obsidian, CLI) %s(%s)%s\n" 0 "$grn" "$rst" "core" "$dim" "$(count_group core)" "$rst"
  local stale_state; (( INCLUDE_STALE )) && stale_state="${ylw}INCLUDED${rst}" || stale_state="${dim}skipped${rst}"
  printf "\n  ${dim}Not-recently-used apps:${rst} %s ${dim}(press ${rst}s${dim} to toggle)${rst}\n" "$stale_state"
  say "${dim}Number=toggle  ${rst}v${dim}=view a group  ${rst}a${dim}=all  ${rst}n${dim}=none  ${rst}s${dim}=stale apps  ${rst}Enter${dim}=review & install  ${rst}q${dim}=quit${rst}"
}

# Pre-select the default-on groups. Called once, before the menu opens, so
# re-entering menu_loop (e.g. via "back" from the review step) keeps selections.
seed_defaults() {
  local g idx
  for g in "${DEFAULT_ON[@]}"; do idx="$(group_index "$g")"; (( idx >= 0 )) && SEL[$idx]=1; done
}

menu_loop() {
  local i choice vnum vidx
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
      v|V )
        printf "view which group number? (0 = core) > "
        read -r vnum </dev/tty 2>/dev/null || vnum=""
        if [[ "$vnum" == "core" || "$vnum" == 0 ]]; then
          browse_group core
        elif [[ "$vnum" =~ ^[0-9]+$ ]]; then
          vidx=$((vnum-1))
          (( vidx >= 0 && vidx < ${#GROUP_ORDER[@]} )) && browse_group "${GROUP_ORDER[$vidx]}"
        fi ;;
      *[!0-9]* ) : ;;  # ignore other non-numeric input
      * )
        vidx=$((choice-1))
        if (( vidx >= 0 && vidx < ${#GROUP_ORDER[@]} )); then
          SEL[$vidx]=$(( ${SEL[$vidx]:-0} ^ 1 ))
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
# Write the taps + selected/eligible package lines into $2. Echoes the count of
# not-recently-used apps that were skipped. Raw lines are preserved verbatim so
# mas `id:` args survive. Shared by preview_plan and run_bundle.
compute_bundle() {
  local selected="$1" out="$2"
  grep -E '^tap ' "$BREWFILE" > "$out"
  local skipped=0 grp kind name rec desc raw
  while IFS=$'\037' read -r grp kind name rec desc raw; do
    [[ " $selected " == *" $grp "* ]] || continue
    if is_included "$grp" "$kind" "$rec"; then
      printf '%s\n' "$raw" >> "$out"
    else
      skipped=$((skipped+1))
    fi
  done < <(all_rows)
  echo "$skipped"
}

# Review step: print exactly what will be installed (grouped, with descriptions
# and recent/stale markers) and what will be skipped. Installs nothing.
preview_plan() {
  local selected="$1"
  local grp kind name rec desc raw gg total=0 skipped=0 header
  local skipped_list=""
  hdr "Review — packages to install"
  say "${dim}Groups: $selected${rst}"
  say ""
  local order=(core "${GROUP_ORDER[@]}")
  for gg in "${order[@]}"; do
    [[ " $selected " == *" $gg "* ]] || continue
    header=0
    while IFS=$'\037' read -r grp kind name rec desc raw; do
      [[ "$grp" == "$gg" ]] || continue
      if is_included "$grp" "$kind" "$rec"; then
        if (( ! header )); then
          printf "  %s%s%s ${dim}[%s]${rst}\n" "$bold" "$(group_label "$gg")" "$rst" "$gg"; header=1
        fi
        total=$((total+1))
        local mark=""
        [[ "$kind" != brew && "$gg" != core ]] && { (( rec )) && mark=" ${cyn}·recent${rst}" || mark=" ${ylw}·stale${rst}"; }
        printf "     %-5s %-24s %b%b\n" "$kind" "$name" "${desc:+$dim$desc$rst}" "$mark"
      else
        skipped=$((skipped+1)); skipped_list+="     $kind $name"$'\n'
      fi
    done < <(all_rows)
  done
  say ""
  say "${bold}$total package(s) will be installed.${rst}"
  if (( skipped > 0 )); then
    say "${dim}$skipped not-recently-used app(s) will be SKIPPED (press ${rst}s${dim} / use ${rst}--include-stale${dim} to add):${rst}"
    printf "%b" "${dim}${skipped_list}${rst}"
  fi
}

run_bundle() {
  local selected="$1"
  if (( DRY_RUN )); then
    preview_plan "$selected"
    hdr "Dry run — nothing installed"
    return 0
  fi
  local tmp; tmp="$(mktemp -t Brewfile.XXXXXX)"
  local skipped; skipped="$(compute_bundle "$selected" "$tmp")"

  local n; n="$(grep -cE '^(brew|cask|mas) ' "$tmp")"
  hdr "Installing $n packages from groups: $selected"
  (( skipped > 0 )) && say "  ${dim}($skipped not-recently-used app(s) skipped — press ${rst}s${dim} in the menu or pass ${rst}--include-stale${dim} to add them)${rst}"
  if ! have brew; then warn "Homebrew not found — run bootstrap.sh first"; rm -f "$tmp"; return 1; fi
  # `mas` (the App Store CLI) is in core, so it's always in the bundle, and brew
  # bundle installs formulae before mas entries — Mac App Store apps resolve with
  # no bootstrap here. (Installing them still needs you signed into the App Store.)
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
  local mode="" groups="" groups_given=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --include-stale) INCLUDE_STALE=1 ;;
      --dry-run) DRY_RUN=1 ;;
      --core) mode=core ;;
      --all)  mode=all ;;
      --groups) shift; groups="${1:-}"; groups_given=1 ;;
      --groups=*) groups="${1#*=}"; groups_given=1 ;;
      --launchagents) shift; LAUNCHAGENTS="${1:-}" ;;
      --launchagents=*) LAUNCHAGENTS="${1#*=}" ;;
      -h|--help) sed -n '2,31p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; return 0 ;;
      *) warn "ignoring unrecognized argument '$1' (see --help; --groups takes ONE comma-separated list)" ;;
    esac
    shift
  done
  # --dry-run must not mutate anything — including symlinks (running from a
  # secondary checkout would otherwise silently repoint live configs at it).
  if (( DRY_RUN )); then
    say "${dim}dry-run: skipping symlinks${rst}"
  else
    link_configs
    link_home
    ensure_ssh_key
  fi
  case "$mode" in
    core) run_bundle "core" ;;
    all)  INCLUDE_STALE=1; run_bundle "core ${GROUP_ORDER[*]}" ;;
    *)
      if (( groups_given )); then
        # non-interactive: install exactly the named groups (comma-separated) + core.
        if [[ -z "$groups" ]]; then
          warn "--groups given an empty value — nothing to do (did you mean --all, or 'GROUP,GROUP'?)"; return 1
        fi
        # Explicitly naming a group means you want it — don't stale-skip its apps.
        INCLUDE_STALE=1
        local sel="core" g matched=0
        # split on commas without glob/word-split surprises (read -ra, IFS=,)
        local _g; IFS=',' read -ra _g <<<"$groups"
        for g in "${_g[@]}"; do
          [[ -z "$g" ]] && continue
          if [[ "$g" == core || " ${GROUP_ORDER[*]} " == *" $g "* ]]; then
            sel+=" $g"; matched=1
          else
            warn "unknown group '$g' — skipping (groups are the # group: tags in install/Brewfile)"
          fi
        done
        if (( ! matched )); then
          warn "no valid groups in --groups '$groups' — nothing to install (run --help for group names)"; return 1
        fi
        run_bundle "$sel"
      else
        seed_defaults
        menu_loop
        if (( DRY_RUN )); then
          run_bundle "$(selected_list)"        # short-circuits to preview_plan
        else
          # Review the resolved list, then confirm / go back / abort.
          local ans
          while true; do
            preview_plan "$(selected_list)"
            printf "\n%sProceed with install?%s [%sY%s/n, %sb%s=back to menu] > " \
              "$bold" "$rst" "$grn" "$rst" "$cyn" "$rst"
            read -r ans </dev/tty 2>/dev/null || ans=""
            case "$ans" in
              ""|y|Y) run_bundle "$(selected_list)"; break ;;
              n|N)    say "Aborted — nothing installed."; return 0 ;;
              b|B)    menu_loop ;;
              *)      : ;;
            esac
          done
        fi
      fi
      ;;
  esac
  local ni=0; [[ -n "$mode" || $groups_given -eq 1 ]] && ni=1
  (( DRY_RUN )) || install_launchagents "$ni"
  install_shell_framework
  hdr "Done"
  say "Re-run anytime to add more groups. Inventory drift: ${cyn}install/refresh-inventory.sh${rst}"
}

main "$@"
