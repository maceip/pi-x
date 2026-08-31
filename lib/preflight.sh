#!/usr/bin/env bash
# Shared discovery for RAM, uv/mtplx, and compatible local models.
# Sourced by run_agent.sh, start_mtplx.sh, and test_pi_setup.sh.

: "${PI_X_MIN_RAM_GB:=80}"
: "${PI_X_MIN_MTPLX:=2.10.1}"
: "${PI_X_FALLBACK_MODEL_REPO:=Youssofal/Qwen3.6-27B-MTPLX-Optimized-Speed}"
: "${PI_X_FALLBACK_MODEL_URL:=https://huggingface.co/Youssofal/Qwen3.6-27B-MTPLX-Optimized-Speed}"

pi_x_log() { printf ' [pi-x] %s\n' "$*"; }
pi_x_err() { printf ' [pi-x] %s\n' "$*" >&2; }

pi_x_ask() {
    local prompt="$1" reply=""
    if [[ -r /dev/tty ]]; then
        printf '%s' "$prompt" > /dev/tty && IFS= read -r reply < /dev/tty || true
    elif [[ -t 0 ]]; then
        printf '%s' "$prompt" && IFS= read -r reply || true
    else
        pi_x_err "Non-interactive shell cannot answer: ${prompt}"
        return 1
    fi
    [[ "$(printf '%s' "$reply" | tr '[:upper:]' '[:lower:]' | xargs)" =~ ^(y|yes)$ ]]
}

pi_x_version_ge() {
    [[ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -n 1)" == "$1" ]]
}

pi_x_total_ram_bytes() {
    if [[ "$(uname -s)" == "Darwin" ]]; then
        sysctl -n hw.memsize 2>/dev/null || echo 0
    else
        awk '/MemTotal:/ { print $2 * 1024; exit }' /proc/meminfo 2>/dev/null || echo 0
    fi
}

pi_x_require_ram() {
    local bytes gb
    bytes="$(pi_x_total_ram_bytes)"
    gb=$((bytes / 1024 / 1024 / 1024))
    if (( gb <= PI_X_MIN_RAM_GB )); then
        pi_x_err "Detected ${gb}GB RAM (requires >${PI_X_MIN_RAM_GB}GB Apple Silicon)."
        exit 1
    fi
    pi_x_log "RAM check passed (${gb}GB total)."
    export MTPLX_MEMORY_LIMIT_BYTES="${MTPLX_MEMORY_LIMIT_BYTES:-$((bytes * 90 / 100))}"
    export MTPLX_WIRED_LIMIT_BYTES="${MTPLX_WIRED_LIMIT_BYTES:-$((bytes * 85 / 100))}"
}

pi_x_prepend_path() {
    local dir="$1"
    if [[ -d "$dir" && ":${PATH}:" != *":${dir}:"* ]]; then
        export PATH="${dir}:${PATH}"
    fi
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

pi_x_mtplx_version_of() {
    local bin="$1" ver=""
    ver="$("$bin" --version 2>/dev/null | grep -Eo '[0-9]+(\.[0-9]+)+' | head -n 1 || true)"
    if [[ -z "$ver" ]]; then
        local py="$(dirname "$bin")/python"
        if [[ -x "$py" ]]; then
            ver="$("$py" -c "import importlib.metadata as m; print(m.version('mtplx'))" 2>/dev/null || true)"
        fi
    fi
    printf '%s\n' "$ver"
}

pi_x_discover_mtplx() {
    MTPLX_BIN="" MTPLX_VERSION="" MTPLX_SOURCE=""
    HAS_UV="$(command -v uv >/dev/null 2>&1 && echo yes || echo no)"

    local roots=(
        "${HOME}/.venv" "${HOME}/venv" "${HOME}/.mtplx/venv" "${HOME}/.mtplx/.venv"
        "${HOME}/mtplx/.venv" "${HOME}/MTPLX/.venv" "${HOME}/.local/share/uv/tools/mtplx"
        "${UV_PROJECT_ENVIRONMENT:-}"
    )
    if [[ "$HAS_UV" == "yes" ]]; then
        local tool_dir="$(uv tool dir 2>/dev/null || true)"
        if [[ -n "$tool_dir" ]]; then
            roots+=("${tool_dir}/mtplx" "$tool_dir")
        fi
    fi

    for r in "${roots[@]}"; do
        if [[ -n "$r" && -d "$r" ]]; then
            for cand in "${r}/bin/mtplx" "${r}/.venv/bin/mtplx" "${r}/venv/bin/mtplx"; do
                if [[ -x "$cand" ]]; then
                    MTPLX_BIN="$cand"
                    MTPLX_SOURCE="venv:${r}"
                    break 2
                fi
            done
        fi
    done

    if [[ -z "$MTPLX_BIN" ]]; then
        if command -v mtplx >/dev/null 2>&1; then
            MTPLX_BIN="$(command -v mtplx)"
            MTPLX_SOURCE="path"
        elif python3 -c "import importlib.util,sys; sys.exit(0 if importlib.util.find_spec('mtplx') else 1)" 2>/dev/null; then
            MTPLX_BIN="$(command -v python3)"
            MTPLX_SOURCE="python-module"
        fi
    fi

    if [[ -n "$MTPLX_BIN" ]]; then
        if [[ "$MTPLX_SOURCE" == "python-module" ]]; then
            MTPLX_VERSION="$(python3 -c "import importlib.metadata as m; print(m.version('mtplx'))" 2>/dev/null || true)"
        else
            MTPLX_VERSION="$(pi_x_mtplx_version_of "$MTPLX_BIN")"
            pi_x_prepend_path "$(dirname "$MTPLX_BIN")"
        fi
        pi_x_log "Found mtplx ${MTPLX_VERSION:-unknown} (${MTPLX_SOURCE}) at ${MTPLX_BIN}."
    fi
}

pi_x_install_or_upgrade_mtplx() {
    local action="$1"
    pi_x_log "${action}ing mtplx ${PI_X_MIN_MTPLX}+ ..."
    if [[ "$HAS_UV" == "yes" ]]; then
        if [[ -n "${MTPLX_BIN:-}" && -x "$(dirname "$MTPLX_BIN")/python" ]]; then
            uv pip install --python "$(dirname "$MTPLX_BIN")/python" "mtplx>=${PI_X_MIN_MTPLX}"
        else
            uv tool install "mtplx>=${PI_X_MIN_MTPLX}" --upgrade
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
    local action=""
    if [[ -z "${MTPLX_BIN:-}" ]]; then
        action="install"
    elif [[ -z "${MTPLX_VERSION:-}" ]] || ! pi_x_version_ge "$MTPLX_VERSION" "$PI_X_MIN_MTPLX"; then
        action="upgrade"
    fi

    if [[ -n "$action" ]]; then
        if pi_x_ask "Install/upgrade mtplx ${PI_X_MIN_MTPLX}+ now? [y/N] "; then
            pi_x_install_or_upgrade_mtplx "$action"
            if [[ -n "${MTPLX_BIN:-}" ]] && pi_x_version_ge "${MTPLX_VERSION:-0}" "$PI_X_MIN_MTPLX"; then
                return 0
            fi
            pi_x_err "mtplx ${PI_X_MIN_MTPLX}+ is still not available after ${action}."
            exit 1
        fi
        pi_x_err "Harness requires mtplx ${PI_X_MIN_MTPLX}+. Exiting."
        exit 1
    fi
}

pi_x_dir_looks_like_model() {
    local dir="$1"
    if [[ ! -d "$dir" ]] || [[ ! -f "${dir}/config.json" && ! -f "${dir}/mtplx_runtime.json" ]]; then
        return 1
    fi
    compgen -G "${dir}/*.safetensors" >/dev/null 2>&1 || compgen -G "${dir}/model-*.safetensors" >/dev/null 2>&1
}

pi_x_name_is_flash_next_4bit() {
    local lower="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
    [[ "$lower" == *qwen3.8* && "$lower" == *flash* && "$lower" == *next* ]] || \
    [[ "$lower" == *qwen3-8*flash*next* || "$lower" == *qwen3.8-flash-next* ]] || \
    [[ "$lower" == *qwen3.6-27b-mtplx-optimized-speed* ]]
}

pi_x_discover_model() {
    if [[ -n "${MODEL_PATH:-}" && -d "$MODEL_PATH" ]]; then
        return 0
    fi

    local roots=(
        "${HOME}/models" "${HOME}/Models" "${HOME}/.mtplx/models"
        "${HOME}/.cache/huggingface/hub" "${PI_X_ROOT:-}/models" "${PWD}/models"
    )
    for root in "${roots[@]}"; do
        if [[ -d "$root" ]]; then
            for child in "$root"/*; do
                local base="$(basename "$child")"
                if pi_x_name_is_flash_next_4bit "$base"; then
                    if pi_x_dir_looks_like_model "$child"; then
                        MODEL_PATH="$child"
                        return 0
                    fi
                    for snap in "$child"/snapshots/*; do
                        if pi_x_dir_looks_like_model "$snap"; then
                            MODEL_PATH="$snap"
                            return 0
                        fi
                    done
                fi
            done
        fi
    done

    if [[ -n "${MTPLX_BIN:-}" ]]; then
        local listing="$("${MTPLX_BIN}" models 2>/dev/null || true)"
        while IFS= read -r line; do
            if pi_x_name_is_flash_next_4bit "$line"; then
                local maybe="$(printf '%s' "$line" | awk '{print $NF}')"
                if [[ -d "$maybe" ]]; then
                    MODEL_PATH="$maybe"
                    return 0
                fi
                local slug="$(printf '%s' "$line" | grep -Eo '[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+' | head -n 1 || true)"
                if [[ -n "$slug" ]]; then
                    local cached="${HOME}/.mtplx/models/${slug//\//--}"
                    if [[ -d "$cached" ]]; then
                        MODEL_PATH="$cached"
                        return 0
                    fi
                fi
            fi
        done <<< "$listing"
    fi
    return 1
}

pi_x_download_fallback_model() {
    local dest="${HOME}/.mtplx/models/${PI_X_FALLBACK_MODEL_REPO//\//--}"
    mkdir -p "$(dirname "$dest")"
    pi_x_log "Downloading ${PI_X_FALLBACK_MODEL_REPO} -> ${dest}"

    if [[ -n "${MTPLX_BIN:-}" ]] && "${MTPLX_BIN}" pull --help >/dev/null 2>&1; then
        "${MTPLX_BIN}" pull "$PI_X_FALLBACK_MODEL_REPO"
        if pi_x_dir_looks_like_model "$dest"; then
            MODEL_PATH="$dest"
            return 0
        fi
        if pi_x_discover_model; then
            return 0
        fi
    fi

    local py="python3"
    if [[ -n "${MTPLX_BIN:-}" && -x "$(dirname "$MTPLX_BIN")/python" ]]; then
        py="$(dirname "$MTPLX_BIN")/python"
    fi

    mkdir -p "$dest"
    $py - "$PI_X_FALLBACK_MODEL_REPO" "$dest" <<'PY'
import sys
repo, dest = sys.argv[1], sys.argv[2]
try:
    from huggingface_hub import snapshot_download
except ImportError:
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "huggingface_hub"])
    from huggingface_hub import snapshot_download
snapshot_download(repo_id=repo, local_dir=dest)
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

    pi_x_err "No compatible 4-bit Qwen 3.8 Flash-Next model found in ~/models or ~/.mtplx/models."
    if pi_x_ask "Download ${PI_X_FALLBACK_MODEL_REPO} now? [y/N] "; then
        if pi_x_download_fallback_model; then
            export MODEL_PATH
            return 0
        fi
        pi_x_err "Download failed or directory incomplete."
        exit 1
    fi
    pi_x_err "Model required. Exiting."
    exit 1
}

pi_x_preflight() {
    local root="${PI_X_ROOT:-$(pwd)}"
    if [[ -f "${root}/config.env" ]]; then
        source "${root}/config.env"
    fi
    pi_x_bootstrap_path
    pi_x_require_ram
    pi_x_require_mtplx
    pi_x_require_model
    export MODEL_PATH MTPLX_BIN MTPLX_SOURCE MTPLX_VERSION
}
