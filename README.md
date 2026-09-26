# El-Commander - freaky quick file manager
A fast, safe dual-pane terminal file manager written in Rust, inspired by Midnight Commander.


## Installation
### Quick install (macOS / Linux):
```
curl -fsSL https://raw.githubusercontent.com/elkaszcz/el-commander-releases/main/install.sh | sh
```

### Quick install (Windows PowerShell):
```
irm https://raw.githubusercontent.com/elkaszcz/el-commander-releases/main/install.ps1 | iex
```


### PDF support (optional)

The viewer can show PDFs as rendered Markdown or as layout text (F3 cycles
Markdown → Text → Raw). This uses [liteparse](https://github.com/run-llama/liteparse)'s
`lit` with PDFium, a separate ~12 MB download that the installers offer
(answer `y` when asked). Each release ships it as `lit-<version>-<target>.tar.gz`,
covered by the same signed `SHA256SUMS` as `cm`, and it is installed to
`~/.cm/tools/lit/<version>/`.

```
curl -fsSL https://raw.githubusercontent.com/elkaszcz/el-commander-releases/main/install.sh | sh -s -- --with-pdf
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/elkaszcz/el-commander-releases/main/install.ps1))) -WithPdf
```

`--no-pdf` / `-NoPdf` (or `CM_WITH_PDF=0`) skip it without asking. Afterwards:

```
cm update --with-pdf     # add PDF support to an existing install
cm update --no-pdf       # remove it
cm --version             # shows whether PDF support is installed and verified
```

Once installed, `cm update` keeps it in step with `cm`. Not available for 32-bit ARM (armv7).
License texts for liteparse (Apache-2.0) and PDFium (BSD-3-Clause and its
third-party notices) are in each archive's `LICENSES/`.


## Verifying a download

Releases are signed with [Minisign](https://jedisct1.github.io/minisign/). The
install scripts and `cm --update` verify this automatically; to check a manual
download, use the public key in [`minisign.pub`](minisign.pub):

```
minisign -Vm SHA256SUMS -p minisign.pub   # verifies the checksum manifest
sha256sum -c SHA256SUMS                    # then verifies the archive
```

Public key: `RWQ2phjehTa48pOz8sOJEliKh7S5FVT+YBcyerOJTjrBXwsX7oAkWAwD`

### Update
```
cm --update
```

### Checking version
```
cm --version
```
