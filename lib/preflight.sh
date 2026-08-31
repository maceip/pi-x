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
    # Check for Rosetta 2 translation on Apple Silicon
    if [[ "$(uname -s)" == "Darwin" ]]; then
        local translated=0
        translated="$(sysctl -n sysctl.proc_translated 2>/dev/null || echo 0)"
        if [[ "$translated" == "1" || "$(uname -m)" == "x86_64" ]]; then
            if [[ "$(sysctl -n machdep.cpu.brand_string 2>/dev/null)" =~ Apple ]]; then
                pi_x_log "Detected x86_64/Rosetta process on Apple Silicon. Relaunching in native arm64..."
                exec arch -arm64 bash "$0" "$@"
            fi
        fi
    fi

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
    pi_x_prepend_path "${HOME}/.bun/bin"
    pi_x_prepend_path "${HOME}/.volta/bin"
    pi_x_prepend_path "${HOME}/.asdf/shims"
    pi_x_prepend_path "${HOME}/.asdf/bin"
    pi_x_prepend_path "${HOME}/.local/share/mise/shims"
    pi_x_prepend_path "${HOME}/.local/share/mise/bin"
    pi_x_prepend_path "${HOME}/.proto/shims"
    pi_x_prepend_path "${HOME}/.proto/bin"
    pi_x_prepend_path "${HOME}/.local/share/fnm/current/bin"
    pi_x_prepend_path "${HOME}/.fnm/current/bin"

    # Homebrew Node formulas
    for brew_node in /opt/homebrew/opt/node /opt/homebrew/opt/node@* /usr/local/opt/node /usr/local/opt/node@*; do
        [[ -d "${brew_node}/bin" ]] && pi_x_prepend_path "${brew_node}/bin"
    done

    # NVM node versions
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
    [[ -d "$dir" ]] || return 1

    local cfg="${dir}/config.json"
    if [[ ! -f "$cfg" && ! -f "${dir}/mtplx_runtime.json" && ! -f "${dir}/params.json" ]]; then
        return 1
    fi

    # Check for weights directly or via symlink in snapshots
    if compgen -G "${dir}/*.safetensors" >/dev/null 2>&1 || \
       compgen -G "${dir}/model-*.safetensors" >/dev/null 2>&1 || \
       compgen -G "${dir}/mtp/*.safetensors" >/dev/null 2>&1 || \
       [[ -f "${dir}/model.safetensors.index.json" ]] || \
       compgen -G "${dir}/*.bin" >/dev/null 2>&1; then
        return 0
    fi

    # Check for symlinked files (common in HF hub snapshots)
    if [[ -d "${dir}" ]] && find -L "${dir}" -maxdepth 2 -name "*.safetensors" 2>/dev/null | grep -q .; then
        return 0
    fi

    return 1
}

pi_x_model_config_is_compatible() {
    local dir="$1"
    local cfg="${dir}/config.json"
    [[ -f "$cfg" ]] || return 1

    # Check model_type or architectures in config.json
    local model_type="" arch=""
    model_type="$(grep -Eo '"model_type"\s*:\s*"[^"]+"' "$cfg" 2>/dev/null | cut -d'"' -f4 | tr '[:upper:]' '[:lower:]' || true)"
    arch="$(grep -Eo '"architectures"\s*:\s*\[\s*"[^"]+"' "$cfg" 2>/dev/null | cut -d'"' -f4 | tr '[:upper:]' '[:lower:]' || true)"

    if [[ "$model_type" =~ (qwen4_exp|qwen3_8|qwen3\.8|qwen3_6|qwen2_5|qwen2) ]] || \
       [[ "$arch" =~ (qwen3_8|qwen4exp|qwen2) ]]; then
        return 0
    fi
    return 1
}

pi_x_name_is_flash_next_4bit() {
    local dir_or_name="$1"
    local lower="$(printf '%s' "$(basename "$dir_or_name")" | tr '[:upper:]' '[:lower:]')"

    if [[ "$lower" == *qwen3.8* && "$lower" == *flash* && "$lower" == *next* ]] || \
       [[ "$lower" == *qwen3-8*flash*next* || "$lower" == *qwen3.8-flash-next* ]] || \
       [[ "$lower" == *qwen3.6-27b-mtplx-optimized-speed* ]]; then
        return 0
    fi

    if [[ -d "$dir_or_name" ]] && pi_x_model_config_is_compatible "$dir_or_name"; then
        return 0
    fi
    return 1
}

pi_x_discover_model() {
    if [[ -n "${MODEL_PATH:-}" && -d "$MODEL_PATH" ]]; then
        return 0
    fi

    local roots=(
        "${HOME}/models" "${HOME}/Models" "${HOME}/.mtplx/models"
        "${HF_HOME:-${HOME}/.cache/huggingface}/hub"
        "${HF_HUB_CACHE:-}"
        "${XDG_CACHE_HOME:-${HOME}/.cache}/huggingface/hub"
        "${PI_X_ROOT:-}/models" "${PWD}/models"
    )

    # Also check attached /Volumes external drives
    shopt -s nullglob
    for ext in /Volumes/*/models /Volumes/*/cache/huggingface/hub; do
        [[ -d "$ext" ]] && roots+=("$ext")
    done
    shopt -u nullglob

    for root in "${roots[@]}"; do
        if [[ -n "$root" && -d "$root" ]]; then
            for child in "$root"/*; do
                local base="$(basename "$child")"
                # Direct folder check
                if pi_x_dir_looks_like_model "$child" && pi_x_name_is_flash_next_4bit "$child"; then
                    MODEL_PATH="$child"
                    return 0
                fi
                # Hugging Face hub snapshot check
                if [[ -d "${child}/snapshots" ]] && pi_x_name_is_flash_next_4bit "$base"; then
                    for snap in "${child}/snapshots"/*; do
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

pi_x_verify_mtplx_runtime() {
    local py="python3"
    if [[ -n "${MTPLX_BIN:-}" && -x "$(dirname "$MTPLX_BIN")/python" ]]; then
        py="$(dirname "$MTPLX_BIN")/python"
    fi

    if ! "$py" -c "import mtplx; import mlx.core" 2>/dev/null; then
        pi_x_err "Warning: Python runtime at ${py} failed to import mlx.core or mtplx."
        if pi_x_ask "Attempt automatic virtualenv repair with uv/pip? [y/N] "; then
            pi_x_install_or_upgrade_mtplx "repair"
        fi
    fi
}

pi_x_preflight() {
    local root="${PI_X_ROOT:-$(pwd)}"
    if [[ -f "${root}/config.env" ]]; then
        source "${root}/config.env"
    fi
    pi_x_bootstrap_path
    pi_x_require_ram
    pi_x_require_mtplx
    pi_x_verify_mtplx_runtime
    pi_x_require_model
    export MODEL_PATH MTPLX_BIN MTPLX_SOURCE MTPLX_VERSION
}
