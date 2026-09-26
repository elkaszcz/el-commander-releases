#!/bin/sh
# el-commander (cm) installer for macOS and Linux.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/elkaszcz/el-commander-releases/main/install.sh | sh
#   curl -fsSL .../install.sh | sh -s -- --with-pdf     # also install PDF support
#   curl -fsSL .../install.sh | sh -s -- --no-pdf       # don't ask about it
#
# Downloads the latest release, verifies its Minisign signature and SHA-256
# checksum, installs the `cm` binary to ~/tools, and adds ~/tools to your PATH.
#
# PDF support (liteparse `lit`, for the viewer's PDF views) is optional. The
# installer asks on the terminal; --with-pdf / --no-pdf or CM_WITH_PDF=1/0
# answer in advance. With no terminal and no answer, it is not installed.
# It goes to ~/.cm/tools/lit/<version>/, verified like cm, and `cm update`
# keeps it current (`cm update --with-pdf` / `--no-pdf` change your mind).
set -eu

REPO="elkaszcz/el-commander-releases"
INSTALL_DIR="$HOME/tools"
BIN="cm"
# Release signing key (#28). Must match MINISIGN_PUBKEY in the binary
# (crates/elc-app/src/update.rs) and the -P key in release.yml.
MINISIGN_PUBKEY="RWQ2phjehTa48pOz8sOJEliKh7S5FVT+YBcyerOJTjrBXwsX7oAkWAwD"

red='\033[31m'; green='\033[32m'; reset='\033[0m'
err()  { printf "${red}Error:${reset} %s\n" "$1" >&2; exit 1; }
warn() { printf "${red}Warning:${reset} %s\n" "$1" >&2; }
info() { printf '%s\n' "$1"; }
ok()   { printf "${green}%s${reset}\n" "$1"; }

# 0. Options. want_pdf: 1 = install PDF support, 0 = don't, "" = ask.
want_pdf=""
case "${CM_WITH_PDF:-}" in
  1|y|yes|true)  want_pdf=1 ;;
  0|n|no|false)  want_pdf=0 ;;
  "") ;;
  *) err "CM_WITH_PDF must be 1 or 0 (got '${CM_WITH_PDF}')." ;;
esac
for arg in "$@"; do
  case "$arg" in
    --with-pdf) want_pdf=1 ;;
    --no-pdf)   want_pdf=0 ;;
    *) err "Unknown option: $arg (supported: --with-pdf, --no-pdf)" ;;
  esac
done

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
      armv7l|armv7)  target="armv7-unknown-linux-gnueabihf" ;;
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

# 3. Download the archive, the checksum manifest, and its signature.
info "Downloading $asset ..."
dl "$base/$asset" "$tmp/$asset"                     || err "Download failed: $base/$asset"
dl "$base/SHA256SUMS" "$tmp/SHA256SUMS"             || err "Could not download SHA256SUMS."
dl "$base/SHA256SUMS.minisig" "$tmp/SHA256SUMS.minisig" \
  || err "Could not download SHA256SUMS.minisig."

# 3b. Verify the SHA256SUMS signature against the release key (#28). This is
#     what makes a leaked publish token insufficient to ship a malicious
#     binary: forging the manifest requires the (separate) signing key.
if command -v minisign >/dev/null 2>&1; then
  info "Verifying signature ..."
  minisign -Vm "$tmp/SHA256SUMS" -x "$tmp/SHA256SUMS.minisig" -P "$MINISIGN_PUBKEY" \
    >/dev/null || err "Signature verification failed -- refusing to install."
else
  printf "${red}Warning:${reset} minisign not installed; skipping signature verification.\n" >&2
  printf "         The SHA-256 checksum is still enforced below. For full\n" >&2
  printf "         verification install minisign: https://jedisct1.github.io/minisign/\n" >&2
fi

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
sha256() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'
  else shasum -a 256 "$1" | awk '{print $1}'; fi
}

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

# 5b. Optional PDF support: liteparse `lit`, listed in the same verified
#     SHA256SUMS. A failure here leaves cm installed and PDF support off.
pdf_note=""
install_pdf() {
  lit_asset="$(awk -v t="$target" '
      { n = $2; sub(/^\*/, "", n) }
      n ~ ("^lit-[0-9]+\\.[0-9]+\\.[0-9]+-" t "\\.tar\\.gz$") { print n; exit }
    ' "$tmp/SHA256SUMS")"
  if [ -z "$lit_asset" ]; then
    warn "This release has no PDF support package for $target; skipping it."
    return 0
  fi
  lit_ver="$(printf '%s\n' "$lit_asset" | sed -E 's/^lit-([0-9]+\.[0-9]+\.[0-9]+)-.*/\1/')"
  case "$os" in
    Darwin) lib="libpdfium.dylib" ;;
    *)      lib="libpdfium.so" ;;
  esac
  root="$HOME/.cm/tools/lit"
  dest="$root/$lit_ver"
  if [ -x "$dest/lit" ]; then
    info "PDF support (lit $lit_ver) is already installed."
    return 0
  fi

  info "Downloading $lit_asset ..."
  dl "$base/$lit_asset" "$tmp/$lit_asset" || { warn "Download failed: $base/$lit_asset"; return 1; }
  lit_expected="$(awk -v n="$lit_asset" '{ m = $2; sub(/^\*/, "", m) } m == n { print $1; exit }' "$tmp/SHA256SUMS")"
  [ "$(sha256 "$tmp/$lit_asset")" = "$lit_expected" ] \
    || { warn "Checksum mismatch for $lit_asset -- PDF support not installed."; return 1; }

  # Only the expected regular files under the one expected directory: no
  # links, no `..`, nothing else (cm's own installer refuses the same).
  top="lit-$lit_ver-$target"
  if tar -tvzf "$tmp/$lit_asset" | grep -Eq '^[^-d]'; then
    warn "$lit_asset contains links or special files -- PDF support not installed."; return 1
  fi
  bad="$(tar -tzf "$tmp/$lit_asset" | grep -Ev "^$top/((lit|$lib)|LICENSES/([A-Za-z0-9._-]+)?)?\$" || true)"
  if [ -n "$bad" ] || tar -tzf "$tmp/$lit_asset" | grep -q '\.\.'; then
    warn "$lit_asset holds unexpected entries -- PDF support not installed."; return 1
  fi

  mkdir -p "$HOME/.cm/tools"
  chmod 700 "$HOME/.cm/tools"
  mkdir -p "$root"
  chmod 700 "$root"
  stage="$(mktemp -d "$root/.install-$lit_ver.XXXXXX")"   # 0700
  if ! tar -xzf "$tmp/$lit_asset" -C "$stage" \
     || [ ! -f "$stage/$top/lit" ] || [ ! -f "$stage/$top/$lib" ]; then
    rm -rf "$stage"; warn "Could not unpack $lit_asset -- PDF support not installed."; return 1
  fi
  chmod 700 "$stage/$top"
  if [ "$os" = "Darwin" ]; then
    xattr -dr com.apple.quarantine "$stage/$top" 2>/dev/null || true
  fi
  rm -rf "$dest"   # an interrupted earlier install, without a usable lit
  mv "$stage/$top" "$dest"
  rm -rf "$stage"
  pdf_note="PDF support (lit $lit_ver) installed to $dest"
}

if [ "$target" = "armv7-unknown-linux-gnueabihf" ]; then
  [ "$want_pdf" = "1" ] && warn "PDF support isn't available for armv7 yet."
else
  if [ -z "$want_pdf" ]; then
    # Ask on the terminal: with `curl | sh`, stdin is this script.
    if (: </dev/tty) 2>/dev/null; then
      echo
      info "Install PDF support? (liteparse \`lit\`, ~12 MB download)"
      info "It adds the viewer's PDF views: Markdown and layout text (F3)."
      printf 'Install PDF support? [y/N] '
      read -r answer </dev/tty || answer=""
      case "$answer" in
        y|Y|yes|YES) want_pdf=1 ;;
        *)           want_pdf=0 ;;
      esac
    else
      want_pdf=0
    fi
  fi
  if [ "$want_pdf" = "1" ]; then
    install_pdf || info "You can retry later with: cm update --with-pdf"
  fi
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
[ -n "$pdf_note" ] && ok "Success: $pdf_note"
if [ -n "$configured" ]; then
  info "Updated $configured (added ~/tools to PATH + cm directory-follow wrapper)."
  info "Open a new terminal (or run: . \"$configured\"), then run: cm"
else
  info "Your shell config already has the el-commander block. Run: cm"
fi
