#!/usr/bin/env bash
# =============================================================================
# build_toolchain.sh  --  install and/or verify the simulation-only toolchain
#
# Tools this project needs (all free, no hardware):
#   verilator                 primary cycle-accurate simulator + C++ harness
#   iverilog (Icarus)         secondary simulator / CI cross-check
#   gtkwave                   waveform viewer
#   riscv64-unknown-elf-gcc   compile rv32im asm/C test programs (via multilib)
#   spike (riscv-isa-sim)     golden ISA reference model for trace-compare
#   dtc (device-tree-compiler) Spike build dependency
#   python3 + venv            trace viewer / perf tooling (M5+)
#
# ASSUMPTIONS
#   * Primary target: Ubuntu 22.04 / 24.04 (apt).  This is what CI uses.
#   * macOS (Homebrew) hints are printed but not auto-run.
#   * Spike is not packaged on apt, so it is built from source into $PREFIX.
#
# USAGE
#   ./scripts/build_toolchain.sh            # install packaged tools, build Spike, verify
#   ./scripts/build_toolchain.sh --check    # verify only, install nothing
#   BUILD_SPIKE=0 ./scripts/build_toolchain.sh   # skip the Spike source build
#   PREFIX=$HOME/riscv ./scripts/build_toolchain.sh
#
# NOTE
#   This script was authored and syntax-checked (`bash -n`) but the actual
#   package installs must run on your machine — that is exactly what the M0
#   exit criterion verifies. Read it before running; it uses sudo for apt.
# =============================================================================
set -euo pipefail

PREFIX="${PREFIX:-$HOME/riscv}"
BUILD_SPIKE="${BUILD_SPIKE:-1}"
CHECK_ONLY=0
[[ "${1:-}" == "--check" ]] && CHECK_ONLY=1

info()  { printf '\033[1;34m[info]\033[0m  %s\n' "$*"; }
ok()    { printf '\033[1;32m[ ok ]\033[0m  %s\n' "$*"; }
warn()  { printf '\033[1;33m[warn]\033[0m  %s\n' "$*"; }
die()   { printf '\033[1;31m[fail]\033[0m  %s\n' "$*" >&2; exit 1; }

have() { command -v "$1" >/dev/null 2>&1; }

detect_os() {
  if [[ "$(uname -s)" == "Darwin" ]]; then echo "macos"; return; fi
  if have apt-get; then echo "debian"; return; fi
  echo "other"
}

OS="$(detect_os)"
info "Detected OS class: $OS"
info "Install prefix (Spike): $PREFIX"

# -----------------------------------------------------------------------------
# Install packaged tools
# -----------------------------------------------------------------------------
install_packages() {
  case "$OS" in
    debian)
      info "Installing packaged tools via apt (requires sudo)..."
      sudo apt-get update
      sudo apt-get install -y \
        build-essential git \
        verilator iverilog gtkwave \
        gcc-riscv64-unknown-elf \
        device-tree-compiler \
        python3 python3-venv python3-pip \
        autoconf automake libtool
      ;;
    macos)
      warn "macOS detected. Run these manually (Homebrew):"
      cat <<'EOF'
  brew install verilator icarus-verilog gtkwave dtc python
  # RISC-V toolchain (rv32 multilib) and Spike:
  brew tap riscv-software-src/riscv
  brew install riscv-tools            # provides riscv gcc + spike (may be slow)
EOF
      warn "Skipping automated install on macOS. Re-run with --check after installing."
      return 0
      ;;
    *)
      die "Unsupported OS for automated install. Install the tools listed in the header manually, then run: $0 --check"
      ;;
  esac
}

# -----------------------------------------------------------------------------
# Build Spike (riscv-isa-sim) from source -- not packaged on apt
# -----------------------------------------------------------------------------
build_spike() {
  if have spike; then ok "spike already on PATH; skipping source build."; return 0; fi
  [[ "$BUILD_SPIKE" == "1" ]] || { warn "BUILD_SPIKE=0 -> skipping Spike build."; return 0; }

  info "Building Spike from source into $PREFIX ..."
  mkdir -p "$PREFIX/src"
  if [[ ! -d "$PREFIX/src/riscv-isa-sim" ]]; then
    git clone --depth 1 https://github.com/riscv-software-src/riscv-isa-sim.git \
      "$PREFIX/src/riscv-isa-sim"
  fi
  (
    cd "$PREFIX/src/riscv-isa-sim"
    mkdir -p build && cd build
    ../configure --prefix="$PREFIX"
    make -j"$(nproc)"
    make install
  )
  warn "Add Spike to your PATH (e.g. in ~/.bashrc):"
  echo "  export PATH=\"$PREFIX/bin:\$PATH\""
}

# -----------------------------------------------------------------------------
# Verify everything, print versions, summarize
# -----------------------------------------------------------------------------
RISCV_GCC=""
pick_riscv_gcc() {
  for g in riscv32-unknown-elf-gcc riscv64-unknown-elf-gcc; do
    if have "$g"; then RISCV_GCC="$g"; return 0; fi
  done
  return 1
}

verify() {
  local fails=0
  info "Verifying toolchain..."

  for t in verilator iverilog gtkwave dtc python3; do
    if have "$t"; then ok "$t -> $($t --version 2>&1 | head -1)"; else warn "$t missing"; ((fails++)); fi
  done

  if pick_riscv_gcc; then
    ok "$RISCV_GCC -> $($RISCV_GCC --version | head -1)"
    # confirm the rv32im/ilp32 multilib actually exists
    if echo 'int main(){return 0;}' | \
       "$RISCV_GCC" -march=rv32im -mabi=ilp32 -nostdlib -x c - -o /tmp/_rv32_probe.elf 2>/dev/null; then
      ok "rv32im/ilp32 multilib present (test link succeeded)"
      rm -f /tmp/_rv32_probe.elf
    else
      warn "rv32im/ilp32 target failed to link. The packaged toolchain may lack rv32 multilib."
      warn "Fallback: build riscv-gnu-toolchain from source with --with-arch=rv32im --with-abi=ilp32."
      ((fails++))
    fi
  else
    warn "no riscv*-unknown-elf-gcc found"; ((fails++))
  fi

  if have spike; then ok "spike -> $(spike --version 2>&1 | head -1 || echo present)"; else warn "spike missing (build it, then re-add PATH)"; ((fails++)); fi

  echo
  if (( fails == 0 )); then
    ok "All required tools verified. You are ready for the M0 hello + Verilator smoke."
  else
    warn "$fails item(s) missing/incomplete. See messages above."
    warn "Re-run without --check to install, or fix the flagged item, then: $0 --check"
    return 1
  fi
}

# -----------------------------------------------------------------------------
main() {
  if (( CHECK_ONLY == 0 )); then
    install_packages
    build_spike
  fi
  verify
}
main "$@"
