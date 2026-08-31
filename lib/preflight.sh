#!/usr/bin/env bash
# Shared discovery for RAM, uv/mtplx, and a compatible local model.
# Sourced by run_agent.sh and start_mtplx.sh. Do not execute directly.

: "${PI_X_MIN_RAM_GB:=80}"
: "${PI_X_MIN_MTPLX:=2.10.1}"
: "${PI_X_FALLBACK_MODEL_REPO:=Youssofal/Qwen3.6-27B-MTPLX-Optimized-Speed}"
: "${PI_X_FALLBACK_MODEL_URL:=https://huggingface.co/Youssofal/Qwen3.6-27B-MTPLX-Optimized-Speed}"

pi_x_log() { printf ' [pi-x] %s\n' "$*"; }
pi_x_err() { printf ' [pi-x] %s\n' "$*" >&2; }

# Always prompt on the real terminal so `curl | bash` still works.
pi_x_ask() {
    local prompt="$1" reply=""
    if [[ -r /dev/tty ]]; then
        printf '%s' "$prompt" > /dev/tty
        IFS= read -r reply < /dev/tty || true
    elif [[ -t 0 ]]; then
        printf '%s' "$prompt"
        IFS= read -r reply || true
    else
        pi_x_err "No interactive terminal available to answer: ${prompt}"
        return 1
    fi
    reply="$(printf '%s' "$reply" | tr '[:upper:]' '[:lower:]' | xargs)"
    case "$reply" in
        y|yes) return 0 ;;
        *) return 1 ;;
    esac
}

pi_x_version_ge() {
    # Return 0 if $1 >= $2 (dotted numeric versions).
    local left="$1" right="$2"
    [[ "$(printf '%s\n%s\n' "$left" "$right" | sort -V | tail -n 1)" == "$left" ]]
}

pi_x_total_ram_bytes() {
    if [[ "$(uname -s)" == "Darwin" ]]; then
        sysctl -n hw.memsize
        return
    fi
    if [[ -r /proc/meminfo ]]; then
        awk '/MemTotal:/ { print $2 * 1024; exit }' /proc/meminfo
        return
    fi
    echo 0
}

pi_x_require_ram() {
    local bytes gb
    bytes="$(pi_x_total_ram_bytes)"
    if [[ -z "$bytes" || "$bytes" == "0" ]]; then
        pi_x_err "Could not determine total system RAM."
        pi_x_err "This harness currently only works on machines with more than ${PI_X_MIN_RAM_GB}GB of RAM."
        exit 1
    fi
    gb=$((bytes / 1024 / 1024 / 1024))
    PI_X_RAM_BYTES="$bytes"
    PI_X_RAM_GB="$gb"
    if (( gb <= PI_X_MIN_RAM_GB )); then
        pi_x_err "Detected ${gb}GB total RAM."
        pi_x_err "This harness currently only works on machines with more than ${PI_X_MIN_RAM_GB}GB of RAM."
        pi_x_err "Please run it on a larger unified-memory machine (typically 96GB+ Apple Silicon)."
        exit 1
    fi
    pi_x_log "RAM check passed (${gb}GB total)."

    # Scale MTPLX memory knobs from the machine instead of a 128GB-only preset.
    if [[ -z "${MTPLX_MEMORY_LIMIT_BYTES:-}" ]]; then
        export MTPLX_MEMORY_LIMIT_BYTES="$((bytes * 90 / 100))"
    fi
    if [[ -z "${MTPLX_WIRED_LIMIT_BYTES:-}" ]]; then
        export MTPLX_WIRED_LIMIT_BYTES="$((bytes * 85 / 100))"
    fi
}

pi_x_prepend_path() {
    local dir="$1"
    [[ -d "$dir" ]] || return 0
    case ":${PATH}:" in
        *":${dir}:"*) ;;
        *) export PATH="${dir}:${PATH}" ;;
    esac
}

pi_x_bootstrap_path() {
    pi_x_prepend_path "${HOME}/.local/bin"
    pi_x_prepend_path "/opt/homebrew/bin"
    pi_x_prepend_path "/usr/local/bin"
    if [[ -d "${HOME}/.nvm/versions/node" ]]; then
        local latest
        latest="$(ls -1d "${HOME}/.nvm/versions/node"/v* 2>/dev/null | sort -V | tail -n 1 || true)"
        if [[ -n "$latest" ]]; then
            pi_x_prepend_path "${latest}/bin"
        fi
    fi
}

pi_x_uv_bin() {
    command -v uv 2>/dev/null || true
}

pi_x_probe_mtplx_bin() {
    local candidate="$1"
    if [[ -n "$candidate" && -x "$candidate" ]]; then
        printf '%s\n' "$candidate"
        return 0
    fi
    return 1
}

pi_x_homedir_uv_venvs() {
    local d
    for d in \
        "${HOME}/.venv" \
        "${HOME}/venv" \
        "${HOME}/.mtplx/venv" \
        "${HOME}/.mtplx/.venv" \
        "${HOME}/mtplx/.venv" \
        "${HOME}/MTPLX/.venv" \
        "${HOME}/.local/share/uv/tools/mtplx" \
        "${UV_PROJECT_ENVIRONMENT:-}"; do
        [[ -n "$d" ]] || continue
        printf '%s\n' "$d"
    done
    if command -v uv >/dev/null 2>&1; then
        local tool_dir
        tool_dir="$(uv tool dir 2>/dev/null || true)"
        if [[ -n "$tool_dir" ]]; then
            printf '%s\n' "${tool_dir}/mtplx"
            printf '%s\n' "$tool_dir"
        fi
    fi
}

pi_x_mtplx_from_venv() {
    local root="$1"
    local cand
    for cand in \
        "${root}/bin/mtplx" \
        "${root}/.venv/bin/mtplx" \
        "${root}/venv/bin/mtplx"; do
        if pi_x_probe_mtplx_bin "$cand"; then
            return 0
        fi
    done
    return 1
}

pi_x_mtplx_version_of() {
    local bin="$1" ver=""
    ver="$("$bin" --version 2>/dev/null | grep -Eo '[0-9]+(\.[0-9]+)+' | head -n 1 || true)"
    if [[ -z "$ver" ]]; then
        ver="$("$bin" version 2>/dev/null | grep -Eo '[0-9]+(\.[0-9]+)+' | head -n 1 || true)"
    fi
    if [[ -z "$ver" ]]; then
        local py
        py="$(dirname "$bin")/python"
        if [[ -x "$py" ]]; then
            ver="$("$py" -c "import importlib.metadata as m; print(m.version('mtplx'))" 2>/dev/null || true)"
        fi
    fi
    printf '%s\n' "$ver"
}

pi_x_discover_mtplx() {
    MTPLX_BIN=""
    MTPLX_VERSION=""
    MTPLX_SOURCE=""
    HAS_UV="no"

    local uv_bin
    uv_bin="$(pi_x_uv_bin)"
    if [[ -n "$uv_bin" ]]; then
        HAS_UV="yes"
        pi_x_log "Found uv at ${uv_bin}."
        local root found=""
        while IFS= read -r root; do
            [[ -n "$root" ]] || continue
            if found="$(pi_x_mtplx_from_venv "$root")"; then
                MTPLX_BIN="$found"
                MTPLX_SOURCE="uv-venv:${root}"
                break
            fi
        done < <(pi_x_homedir_uv_venvs)

        if [[ -z "$MTPLX_BIN" ]]; then
            if found="$(command -v mtplx 2>/dev/null || true)"; then
                MTPLX_BIN="$found"
                MTPLX_SOURCE="path-after-uv"
            elif python3 -c "import importlib.util,sys; sys.exit(0 if importlib.util.find_spec('mtplx') else 1)" 2>/dev/null; then
                MTPLX_BIN="$(command -v python3)"
                MTPLX_SOURCE="python-module"
            fi
        fi
    else
        pi_x_log "uv is not installed; looking for a system/python mtplx."
        local found=""
        found="$(command -v mtplx 2>/dev/null || true)"
        if [[ -n "$found" ]]; then
            MTPLX_BIN="$found"
            MTPLX_SOURCE="path"
        else
            local root
            for root in "${HOME}/.mtplx/venv" "${HOME}/.mtplx/.venv" "${HOME}/MTPLX/.venv"; do
                if found="$(pi_x_mtplx_from_venv "$root")"; then
                    MTPLX_BIN="$found"
                    MTPLX_SOURCE="venv:${root}"
                    break
                fi
            done
        fi
        if [[ -z "$MTPLX_BIN" ]]; then
            if python3 -c "import importlib.util,sys; sys.exit(0 if importlib.util.find_spec('mtplx') else 1)" 2>/dev/null; then
                MTPLX_BIN="$(command -v python3)"
                MTPLX_SOURCE="python-module"
            fi
        fi
    fi

    if [[ -n "$MTPLX_BIN" ]]; then
        if [[ "$MTPLX_SOURCE" == "python-module" ]]; then
            MTPLX_VERSION="$(python3 -c "import importlib.metadata as m; print(m.version('mtplx'))" 2>/dev/null || true)"
        else
            MTPLX_VERSION="$(pi_x_mtplx_version_of "$MTPLX_BIN")"
        fi
        pi_x_log "Found mtplx ${MTPLX_VERSION:-unknown} (${MTPLX_SOURCE}) at ${MTPLX_BIN}."
    fi
}

pi_x_mtplx_cmd() {
    if [[ "${MTPLX_SOURCE:-}" == "python-module" ]]; then
        python3 -m mtplx "$@"
    else
        "${MTPLX_BIN}" "$@"
    fi
}

pi_x_install_or_upgrade_mtplx() {
    local action="$1"
    pi_x_log "${action}ing mtplx ${PI_X_MIN_MTPLX}+ ..."
    if [[ "$HAS_UV" == "yes" ]]; then
        if uv tool list 2>/dev/null | grep -qi '^mtplx'; then
            uv tool install "mtplx>=${PI_X_MIN_MTPLX}" --upgrade
        elif [[ -n "${MTPLX_BIN:-}" && -x "$(dirname "$MTPLX_BIN")/python" ]]; then
            uv pip install --python "$(dirname "$MTPLX_BIN")/python" "mtplx>=${PI_X_MIN_MTPLX}"
        elif [[ -d "${HOME}/.venv" ]]; then
            uv pip install --python "${HOME}/.venv/bin/python" "mtplx>=${PI_X_MIN_MTPLX}"
        else
            uv tool install "mtplx>=${PI_X_MIN_MTPLX}"
        fi
    elif command -v python3 >/dev/null 2>&1; then
        python3 -m pip install -U "mtplx>=${PI_X_MIN_MTPLX}"
    else
        pi_x_err "Cannot ${action} mtplx: neither uv nor python3 is available."
        exit 1
    fi
    pi_x_discover_mtplx
}

pi_x_require_mtplx() {
    pi_x_discover_mtplx
    local need_action=""
    if [[ -z "${MTPLX_BIN:-}" ]]; then
        need_action="install"
        pi_x_err "mtplx was not found."
    elif [[ -z "${MTPLX_VERSION:-}" ]]; then
        need_action="upgrade"
        pi_x_err "Could not determine the installed mtplx version."
    elif ! pi_x_version_ge "$MTPLX_VERSION" "$PI_X_MIN_MTPLX"; then
        need_action="upgrade"
        pi_x_err "Found mtplx ${MTPLX_VERSION}, but this harness needs ${PI_X_MIN_MTPLX} or newer."
    fi

    if [[ -n "$need_action" ]]; then
        if pi_x_ask "Install/upgrade mtplx ${PI_X_MIN_MTPLX}+ now? [y/N] "; then
            pi_x_install_or_upgrade_mtplx "$need_action"
            if [[ -z "${MTPLX_BIN:-}" ]] || ! pi_x_version_ge "${MTPLX_VERSION:-0}" "$PI_X_MIN_MTPLX"; then
                pi_x_err "mtplx ${PI_X_MIN_MTPLX}+ is still not available after the install attempt."
                exit 1
            fi
        else
            pi_x_err "Okay — not changing your Python environment."
            pi_x_err "This harness needs mtplx ${PI_X_MIN_MTPLX} or newer. Exiting."
            exit 1
        fi
    fi

    if [[ "${MTPLX_SOURCE:-}" != "python-module" ]]; then
        pi_x_prepend_path "$(dirname "$MTPLX_BIN")"
    fi
}

pi_x_dir_looks_like_model() {
    local dir="$1"
    [[ -d "$dir" ]] || return 1
    [[ -f "${dir}/config.json" || -f "${dir}/mtplx_runtime.json" ]] || return 1
    local has_weights=0
    shopt -s nullglob
    local f
    for f in "${dir}"/*.safetensors "${dir}"/model-*.safetensors "${dir}"/mtp/*.safetensors; do
        has_weights=1
        break
    done
    shopt -u nullglob
    (( has_weights == 1 ))
}

pi_x_name_is_flash_next_4bit() {
    local name="$1"
    local lower
    lower="$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]')"
    # Accept Qwen 3.8 Flash-Next 4-bit family, plus the published Optimized-Speed siblings.
    if [[ "$lower" == *qwen3.8* && "$lower" == *flash* && "$lower" == *next* ]]; then
        return 0
    fi
    if [[ "$lower" == *qwen3-8*flash*next* || "$lower" == *qwen3.8-flash-next* ]]; then
        return 0
    fi
    if [[ "$lower" == *qwen3.6-27b-mtplx-optimized-speed* ]]; then
        return 0
    fi
    return 1
}

pi_x_scan_model_roots() {
    local root
    for root in \
        "${HOME}/models" \
        "${HOME}/Models" \
        "${HOME}/.mtplx/models" \
        "${HOME}/.cache/huggingface/hub" \
        "${PI_X_ROOT:-}/models" \
        "${PWD}/models"; do
        [[ -d "$root" ]] && printf '%s\n' "$root"
    done
}

pi_x_discover_model() {
    MODEL_PATH="${MODEL_PATH:-}"
    if [[ -n "$MODEL_PATH" && -d "$MODEL_PATH" ]]; then
        pi_x_log "Using MODEL_PATH=${MODEL_PATH}"
        return 0
    fi

    local root child snap
    while IFS= read -r root; do
        [[ -d "$root" ]] || continue
        # Direct folders: ~/models/Qwen3.8-Flash-Next-...
        shopt -s nullglob
        for child in "$root"/*; do
            local base
            base="$(basename "$child")"
            if pi_x_name_is_flash_next_4bit "$base" && pi_x_dir_looks_like_model "$child"; then
                MODEL_PATH="$child"
                shopt -u nullglob
                return 0
            fi
            # Hugging Face hub snapshots: models--Org--Name/snapshots/<rev>
            if [[ "$base" == models--* ]] && pi_x_name_is_flash_next_4bit "$base"; then
                for snap in "$child"/snapshots/*; do
                    if pi_x_dir_looks_like_model "$snap"; then
                        MODEL_PATH="$snap"
                        shopt -u nullglob
                        return 0
                    fi
                done
            fi
        done
        shopt -u nullglob
    done < <(pi_x_scan_model_roots)

    # Ask mtplx what it already cached.
    if [[ -n "${MTPLX_BIN:-}" ]]; then
        local listing
        listing="$(pi_x_mtplx_cmd models 2>/dev/null || true)"
        if [[ -n "$listing" ]]; then
            local line
            while IFS= read -r line; do
                if pi_x_name_is_flash_next_4bit "$line"; then
                    local maybe
                    maybe="$(printf '%s' "$line" | awk '{print $NF}')"
                    if [[ -d "$maybe" ]]; then
                        MODEL_PATH="$maybe"
                        return 0
                    fi
                    # Cached under ~/.mtplx/models as org--name
                    local slug
                    slug="$(printf '%s' "$line" | grep -Eo '[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+' | head -n 1 || true)"
                    if [[ -n "$slug" ]]; then
                        local cached="${HOME}/.mtplx/models/${slug//\//--}"
                        if pi_x_dir_looks_like_model "$cached"; then
                            MODEL_PATH="$cached"
                            return 0
                        fi
                    fi
                fi
            done <<< "$listing"
        fi
    fi

    return 1
}

pi_x_download_fallback_model() {
    local dest="${HOME}/.mtplx/models/${PI_X_FALLBACK_MODEL_REPO//\//--}"
    mkdir -p "$(dirname "$dest")"
    pi_x_log "Downloading ${PI_X_FALLBACK_MODEL_REPO}"
    pi_x_log "Destination: ${dest}"

    if [[ -n "${MTPLX_BIN:-}" ]] && pi_x_mtplx_cmd pull --help >/dev/null 2>&1; then
        pi_x_mtplx_cmd pull "$PI_X_FALLBACK_MODEL_REPO"
        if pi_x_dir_looks_like_model "$dest"; then
            MODEL_PATH="$dest"
            return 0
        fi
        # mtplx pull may have placed it under a slightly different cache name
        if pi_x_discover_model; then
            return 0
        fi
    fi

    local py="python3"
    if [[ -n "${MTPLX_BIN:-}" && -x "$(dirname "$MTPLX_BIN")/python" ]]; then
        py="$(dirname "$MTPLX_BIN")/python"
    elif [[ "$HAS_UV" == "yes" ]]; then
        py="uv run python"
    fi

    mkdir -p "$dest"
    $py - "$PI_X_FALLBACK_MODEL_REPO" "$dest" <<'PY'
import sys
from pathlib import Path

repo, dest = sys.argv[1], sys.argv[2]
try:
    from huggingface_hub import snapshot_download
except ImportError:
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "huggingface_hub"])
    from huggingface_hub import snapshot_download

print(f" [pi-x] Fetching {repo} with huggingface_hub (progress below)...", flush=True)
snapshot_download(
    repo_id=repo,
    local_dir=dest,
)
print(f" [pi-x] Download complete: {dest}", flush=True)
PY
    if pi_x_dir_looks_like_model "$dest"; then
        MODEL_PATH="$dest"
        return 0
    fi
    return 1
}

pi_x_require_model() {
    if pi_x_discover_model; then
        pi_x_log "Using local model: ${MODEL_PATH}"
        export MODEL_PATH
        return 0
    fi

    pi_x_err "No compatible 4-bit Qwen 3.8 Flash-Next model was found."
    pi_x_err "Looked in ~/models, ~/.mtplx/models, and the Hugging Face cache."
    pi_x_err "Fallback checkpoint: ${PI_X_FALLBACK_MODEL_URL}"
    if pi_x_ask "Download ${PI_X_FALLBACK_MODEL_REPO} now? [y/N] "; then
        if ! pi_x_download_fallback_model; then
            pi_x_err "Download finished but the model directory does not look complete."
            exit 1
        fi
        pi_x_log "Using downloaded model: ${MODEL_PATH}"
        export MODEL_PATH
        return 0
    fi
    pi_x_err "Okay — not downloading a model. Exiting."
    exit 1
}

pi_x_preflight() {
    local root="${PI_X_ROOT:-$(pwd)}"
    if [[ -f "${root}/config.env" ]]; then
        # shellcheck disable=SC1090
        source "${root}/config.env"
    fi
    pi_x_bootstrap_path
    pi_x_require_ram
    pi_x_require_mtplx
    pi_x_require_model
    export MODEL_PATH
    export MTPLX_BIN
    export MTPLX_SOURCE
    export MTPLX_VERSION
}
