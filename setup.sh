#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "$0")" && pwd)"
python_bin="${PYTHON:-}"
if [[ -z "$python_bin" ]]; then
  if command -v python3 >/dev/null 2>&1; then
    python_bin="$(command -v python3)"
  elif command -v python >/dev/null 2>&1; then
    python_bin="$(command -v python)"
  elif command -v brew >/dev/null 2>&1; then
    brew install python@3.12
    python_bin="$(brew --prefix python@3.12)/bin/python3.12"
  else
    printf '%s\n' 'Python was not found and no supported automatic package installer is available.' >&2
    exit 1
  fi
fi
force_arg=""
configure_key=false
for argument in "$@"; do
  case "$argument" in
    --force) force_arg="--force" ;;
    --configure-key-from-stdin) configure_key=true ;;
    *) printf '%s\n' "Unknown option: $argument" >&2; exit 2 ;;
  esac
done

cell_ppt_key=""
if [[ "$configure_key" == true ]]; then
  IFS= read -r cell_ppt_key
  [[ -n "$cell_ppt_key" ]] || { printf '%s\n' 'No API key was received on standard input.' >&2; exit 1; }
fi

if ! "$python_bin" -c 'import sys; assert (3, 11) <= sys.version_info[:2] < (3, 15)'; then
  if command -v brew >/dev/null 2>&1; then
    brew install python@3.12
    python_bin="$(brew --prefix python@3.12)/bin/python3.12"
  else
    printf '%s\n' 'A compatible Python was not found and no supported automatic package installer is available.' >&2
    exit 1
  fi
fi
"$python_bin" -m pip install --disable-pip-version-check --requirement "$project_root/requirements.lock"
if [[ -n "$force_arg" ]]; then
  "$python_bin" "$project_root/install.py" "$force_arg"
else
  "$python_bin" "$project_root/install.py"
fi

installed_skill="$HOME/.codex/skills/cell_gd"
"$python_bin" "$installed_skill/scripts/configure_runtime.py" \
  --output "$installed_skill/runtime-profile.json"

key_configured=false
if [[ "$configure_key" == true ]]; then
  printf '%s\n' "$cell_ppt_key" | "$python_bin" "$installed_skill/scripts/set_xiaomiao_key.py" --from-stdin
  unset cell_ppt_key
  "$python_bin" "$installed_skill/scripts/xiaomiao.py" verify >/dev/null
  key_configured=true
elif "$python_bin" "$installed_skill/scripts/xiaomiao.py" verify >/dev/null 2>&1; then
  key_configured=true
fi

doctor_args=()
if [[ "$key_configured" == true ]]; then doctor_args+=(--verify-api); fi
"$python_bin" "$project_root/doctor.py" "${doctor_args[@]}"
printf '%s\n' "SETUP_OK|skill=cell_gd|platform=macos|runtime_matched=true|api_key_configured=$key_configured|restart_codex=true"
