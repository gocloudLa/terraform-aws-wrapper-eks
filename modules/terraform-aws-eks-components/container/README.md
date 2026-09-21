# kube-apply image

A normal Amazon Linux 2023 image with `jq`, AWS CLI, `kubectl`, Helm, and
`scripts/kube-apply.sh`.

| File | What it is |
|---|---|
| `Dockerfile` | Image Builder template (`FROM` + run `install.sh`) |
| `install.sh` | Package install. Edit this to add binaries. |
| `scripts/kube-apply.sh` | Fargate entrypoint |

Image Builder cannot `COPY` from this folder (it does not use it as Docker
context), so Terraform runs `install.sh` inside the build and then writes
`kube-apply.sh` to `/usr/local/bin/kube-apply`.
