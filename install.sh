#!/bin/sh
# el-commander (cm) installer for macOS and Linux.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/elkaszcz/el-commander-releases/main/install.sh | sh
#
# Downloads the latest release, verifies its SHA-256 checksum, installs the
# `cm` binary to ~/tools, and adds ~/tools to your PATH.
set -eu

REPO="elkaszcz/el-commander-releases"
INSTALL_DIR="$HOME/tools"
BIN="cm"

red='\033[31m'; green='\033[32m'; reset='\033[0m'
err()  { printf "${red}Error:${reset} %s\n" "$1" >&2; exit 1; }
info() { printf '%s\n' "$1"; }
ok()   { printf "${green}%s${reset}\n" "$1"; }

# 1. Detect platform -> Rust target triple.
os="$(uname -s)"
arch="$(uname -m)"
case "$os" in
  Darwin)
    case "$arch" in
      x86_64)        target="x86_64-apple-darwin" ;;
      arm64|aarch64) target="aarch64-apple-darwin" ;;
      *) err "Unsupported macOS architecture: $arch" ;;
    esac ;;
  Linux)
    case "$arch" in
      x86_64)        target="x86_64-unknown-linux-gnu" ;;
      aarch64|arm64) target="aarch64-unknown-linux-gnu" ;;
      *) err "Unsupported Linux architecture: $arch" ;;
    esac ;;
  *) err "Unsupported OS: $os. On Windows, use install.ps1 instead." ;;
esac

# Need a downloader.
if command -v curl >/dev/null 2>&1; then
  dl()    { curl -fsSL "$1" -o "$2"; }
  fetch() { curl -fsSL "$1"; }
elif command -v wget >/dev/null 2>&1; then
  dl()    { wget -qO "$2" "$1"; }
  fetch() { wget -qO- "$1"; }
else
  err "Neither curl nor wget is installed."
fi

# 2. Resolve the latest release tag.
info "Fetching latest release of $REPO ..."
tag="$(fetch "https://api.github.com/repos/$REPO/releases/latest" \
  | grep '"tag_name"' | head -1 \
  | sed -E 's/.*"tag_name"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/')"
[ -n "$tag" ] || err "Could not determine the latest release tag."
info "Latest version: $tag"

asset="cm-${tag}-${target}.tar.gz"
base="https://github.com/$REPO/releases/download/$tag"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT INT TERM

# 3. Download the archive and the checksum manifest.
info "Downloading $asset ..."
dl "$base/$asset" "$tmp/$asset"         || err "Download failed: $base/$asset"
dl "$base/SHA256SUMS" "$tmp/SHA256SUMS" || err "Could not download SHA256SUMS."

# 4. Verify the checksum before touching the filesystem.
info "Verifying checksum ..."
expected="$(grep " $asset\$" "$tmp/SHA256SUMS" | awk '{print $1}')"
[ -n "$expected" ] || err "No checksum entry found for $asset."
if command -v sha256sum >/dev/null 2>&1; then
  actual="$(sha256sum "$tmp/$asset" | awk '{print $1}')"
elif command -v shasum >/dev/null 2>&1; then
  actual="$(shasum -a 256 "$tmp/$asset" | awk '{print $1}')"
else
  err "Need sha256sum or shasum to verify the download."
fi
[ "$expected" = "$actual" ] || err "Checksum mismatch -- refusing to install."

# 5. Extract and install.
info "Installing to $INSTALL_DIR ..."
mkdir -p "$INSTALL_DIR"
tar xzf "$tmp/$asset" -C "$tmp"
binpath="$(find "$tmp" -type f -name "$BIN" | head -1)"
[ -n "$binpath" ] || err "Binary '$BIN' not found inside the archive."
cp "$binpath" "$INSTALL_DIR/$BIN"
chmod +x "$INSTALL_DIR/$BIN"

# macOS: clear the quarantine attribute so Gatekeeper doesn't block it.
if [ "$os" = "Darwin" ]; then
  xattr -d com.apple.quarantine "$INSTALL_DIR/$BIN" 2>/dev/null || true
fi

# 6. Configure the shell: put ~/tools on PATH and install the `cm` wrapper that
#    follows el-commander into its last directory when you quit.
shellname="$(basename "${SHELL:-sh}")"
case "$shellname" in
  zsh)  rc="$HOME/.zshrc" ;;
  bash) [ "$os" = "Darwin" ] && rc="$HOME/.bash_profile" || rc="$HOME/.bashrc" ;;
  *)    rc="$HOME/.profile" ;;
esac
touch "$rc"

configured=""
marker="# >>> el-commander (cm) >>>"
if ! grep -qF "$marker" "$rc" 2>/dev/null; then
  if [ "$shellname" = "zsh" ] || [ "$shellname" = "bash" ]; then
    cat >> "$rc" <<'EOF'

# >>> el-commander (cm) >>>
export PATH="$HOME/tools:$PATH"
cm() {
    command cm "$@"
    local lastdir="${XDG_CACHE_HOME:-$HOME/.cache}/el-commander/lastdir"
    if [ -f "$lastdir" ]; then
        local dir
        dir=$(cat "$lastdir")
        if [ -d "$dir" ] && [ "$dir" != "$PWD" ]; then
            cd "$dir" || return
        fi
    fi
}
# <<< el-commander (cm) <<<
EOF
  else
    cat >> "$rc" <<'EOF'

# >>> el-commander (cm) >>>
export PATH="$HOME/tools:$PATH"
# <<< el-commander (cm) <<<
EOF
  fi
  configured="$rc"
fi

# 7. Report.
echo
ok "Success: cm $tag installed to $INSTALL_DIR/$BIN"
if [ -n "$configured" ]; then
  info "Updated $configured (added ~/tools to PATH + cm directory-follow wrapper)."
  info "Open a new terminal (or run: . \"$configured\"), then run: cm"
else
  info "Your shell config already has the el-commander block. Run: cm"
fi
