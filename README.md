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
