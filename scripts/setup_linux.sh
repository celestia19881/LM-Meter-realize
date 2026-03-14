#!/usr/bin/env bash
# =============================================================================
# setup_linux.sh  –  Automated one-shot environment setup for LM-Meter on
#                    a remote Linux server (Ubuntu 20.04 / 22.04 LTS).
#
# Usage:
#   chmod +x scripts/setup_linux.sh
#   bash scripts/setup_linux.sh
#
# This script installs:
#   - System dependencies (Java 17, ADB, build tools)
#   - Rust 1.75.0 (for cross-compiling HuggingFace tokenizers)
#   - Android SDK + NDK 27.0.11718014 (headless / command-line tools)
#   - Miniconda (if not already present)
#   - Conda environments for phase-level and kernel-level profiling
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
ANDROID_SDK_DIR="$HOME/android-sdk"
MINICONDA_DIR="$HOME/miniconda3"
NDK_VERSION="27.0.11718014"
RUST_VERSION="1.75.0"
CMDLINE_TOOLS_URL="https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip"

# ─────────────────────────── helpers ───────────────────────────────────────
log()  { echo -e "\033[1;34m[INFO]\033[0m  $*"; }
ok()   { echo -e "\033[1;32m[ OK ]\033[0m  $*"; }
warn() { echo -e "\033[1;33m[WARN]\033[0m  $*"; }
err()  { echo -e "\033[1;31m[ERR ]\033[0m  $*" >&2; exit 1; }

command_exists() { command -v "$1" &>/dev/null; }

# ─────────────────────────── 1. System packages ────────────────────────────
install_system_packages() {
  log "Installing system packages …"
  sudo apt-get update -qq
  sudo apt-get install -y \
      curl wget git build-essential cmake \
      openjdk-17-jdk \
      android-tools-adb \
      unzip zip \
      libssl-dev pkg-config \
      python3-dev \
      ca-certificates \
      gnupg \
      lsb-release
  ok "System packages installed."
}

# ─────────────────────────── 2. Java 17 ────────────────────────────────────
configure_java() {
  log "Configuring Java 17 …"
  JAVA_HOME_PATH=$(update-java-alternatives --list 2>/dev/null \
    | grep "java-17" | awk '{print $3}' | head -1)
  if [[ -z "$JAVA_HOME_PATH" ]]; then
    JAVA_HOME_PATH="/usr/lib/jvm/java-17-openjdk-amd64"
  fi

  add_to_bashrc "export JAVA_HOME=\"$JAVA_HOME_PATH\""
  add_to_bashrc 'export PATH=$JAVA_HOME/bin:$PATH'
  export JAVA_HOME="$JAVA_HOME_PATH"
  export PATH="$JAVA_HOME/bin:$PATH"

  java -version 2>&1 | grep -q "17" || err "Java 17 not found. Check installation."
  ok "Java 17 configured (JAVA_HOME=$JAVA_HOME)."
}

# ─────────────────────────── 3. Rust 1.75.0 ────────────────────────────────
install_rust() {
  if command_exists rustc && [[ "$(rustc --version 2>/dev/null)" == *"$RUST_VERSION"* ]]; then
    ok "Rust $RUST_VERSION already installed. Skipping."
    return
  fi

  log "Installing Rust $RUST_VERSION …"
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain "$RUST_VERSION"
  # shellcheck source=/dev/null
  source "$HOME/.cargo/env"
  rustup toolchain install "$RUST_VERSION"
  rustup default "$RUST_VERSION"
  rustup target add --toolchain "$RUST_VERSION" aarch64-linux-android
  rustup override set "$RUST_VERSION"

  add_to_bashrc 'if [ -f "$HOME/.cargo/env" ]; then . "$HOME/.cargo/env"; else export PATH="$HOME/.cargo/bin:$PATH"; fi'
  add_to_bashrc "export RUSTUP_TOOLCHAIN=$RUST_VERSION"

  ok "Rust $RUST_VERSION installed."
}

# ─────────────────────────── 4. Android SDK / NDK ──────────────────────────
install_android_sdk() {
  if [[ -d "$ANDROID_SDK_DIR/ndk/$NDK_VERSION" ]]; then
    ok "Android NDK $NDK_VERSION already installed. Skipping."
    return
  fi

  log "Installing Android command-line tools …"
  mkdir -p "$ANDROID_SDK_DIR/cmdline-tools"
  wget -q "$CMDLINE_TOOLS_URL" -O /tmp/cmdline-tools.zip
  unzip -q /tmp/cmdline-tools.zip -d "$ANDROID_SDK_DIR/cmdline-tools"
  mv "$ANDROID_SDK_DIR/cmdline-tools/cmdline-tools" \
     "$ANDROID_SDK_DIR/cmdline-tools/latest" 2>/dev/null || true
  rm -f /tmp/cmdline-tools.zip

  add_to_bashrc "export ANDROID_HOME=$ANDROID_SDK_DIR"
  add_to_bashrc 'export PATH=$PATH:$ANDROID_HOME/cmdline-tools/latest/bin'
  add_to_bashrc 'export PATH=$PATH:$ANDROID_HOME/platform-tools'
  export ANDROID_HOME="$ANDROID_SDK_DIR"
  export PATH="$PATH:$ANDROID_SDK_DIR/cmdline-tools/latest/bin"
  export PATH="$PATH:$ANDROID_SDK_DIR/platform-tools"

  log "Installing Android platform-tools and NDK $NDK_VERSION …"
  yes | sdkmanager --licenses > /dev/null 2>&1 || true
  sdkmanager "platform-tools" "ndk;$NDK_VERSION"

  add_to_bashrc "export ANDROID_NDK=$ANDROID_SDK_DIR/ndk/$NDK_VERSION"
  add_to_bashrc "export TVM_NDK_CC=$ANDROID_SDK_DIR/ndk/$NDK_VERSION/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android24-clang"
  export ANDROID_NDK="$ANDROID_SDK_DIR/ndk/$NDK_VERSION"
  export TVM_NDK_CC="$ANDROID_NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android24-clang"

  ok "Android SDK and NDK $NDK_VERSION installed."
}

# ─────────────────────────── 5. Miniconda ──────────────────────────────────
install_miniconda() {
  if command_exists conda; then
    ok "Conda already installed. Skipping."
    return
  fi

  log "Installing Miniconda …"
  wget -q "https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh" \
      -O /tmp/miniconda.sh
  bash /tmp/miniconda.sh -b -p "$MINICONDA_DIR"
  rm -f /tmp/miniconda.sh

  "$MINICONDA_DIR/bin/conda" init bash
  # shellcheck source=/dev/null
  source "$HOME/.bashrc" 2>/dev/null || true
  export PATH="$MINICONDA_DIR/bin:$PATH"

  ok "Miniconda installed at $MINICONDA_DIR."
}

# ─────────────────────────── 6. Conda environments ─────────────────────────
create_conda_envs() {
  log "Configuring conda channels …"
  conda config --add channels conda-forge
  conda config --set channel_priority flexible

  ENV_DIR="$REPO_ROOT/environment"

  for yaml_file in \
      "$ENV_DIR/conda-linux-x86_64-infer.yaml" \
      "$ENV_DIR/conda-linux-x86_64-kernel.yaml"; do
    env_name=$(grep '^name:' "$yaml_file" | awk '{print $2}')
    if conda env list | grep -q "^$env_name "; then
      ok "Conda environment '$env_name' already exists. Skipping."
    else
      log "Creating conda environment '$env_name' from $yaml_file …"
      conda env create -f "$yaml_file"
      ok "Environment '$env_name' created."
    fi
  done
}

# ─────────────────────────── helpers ───────────────────────────────────────
# Append a line to ~/.bashrc only if it is not already present.
add_to_bashrc() {
  local line="$1"
  grep -qxF "$line" "$HOME/.bashrc" 2>/dev/null || echo "$line" >> "$HOME/.bashrc"
}

# ─────────────────────────── main ──────────────────────────────────────────
main() {
  log "=== LM-Meter Linux Setup ==="
  log "Repository root: $REPO_ROOT"

  install_system_packages
  configure_java
  install_rust
  install_android_sdk
  install_miniconda
  create_conda_envs

  log ""
  ok "=== Setup complete! ==="
  log ""
  log "Next steps:"
  log "  1. Reload your shell:          source ~/.bashrc"
  log "  2. Activate an environment:    conda activate lm-meter-infer"
  log "  3. Connect an Android device:  adb devices"
  log "  4. Collect data:               bash scripts/data_relavant/option2_stream_logcats_and_pull_traces.sh"
  log "  5. Analyze results:            jupyter lab test/quick_start.ipynb"
  log ""
  warn "Build scripts (build_all_e2e_*.sh) require an Android device"
  warn "connected via ADB before execution."
}

main "$@"
