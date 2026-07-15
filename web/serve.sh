#!/usr/bin/env bash
# Serve the handbook as a local website at http://127.0.0.1:8000
# Requires uv (https://docs.astral.sh/uv/) — no other setup needed.
set -euo pipefail
cd "$(dirname "$0")"
exec uvx --with mkdocs-material mkdocs serve -f mkdocs.yml -a 127.0.0.1:8000
