#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHOUTIUI_SHA="8cc926704d027ea1042af31b35c33b9ae4a5d007"
CHOUTI_SHA="50123c30ed0f53c7ce957a03700cedc148694c78"
COMPOSEUI_SHA="cc8a5c225f7db2a5e587f090320ef1ec6321bd17"
CHOUTIUI_PATCH="$ROOT_DIR/patches/choutiui-path-dependencies.patch"

clone_at_revision() {
    local name="$1"
    local url="$2"
    local revision="$3"
    local destination="$ROOT_DIR/research-repos/$name"

    if [[ ! -d "$destination/.git" ]]; then
        git clone "$url" "$destination"
    fi

    [[ -z "$(git -C "$destination" status --porcelain)" ]] \
        || { printf 'ERROR: %s has local changes\n' "$destination" >&2; return 1; }

    if ! git -C "$destination" cat-file -e "$revision^{commit}" 2>/dev/null; then
        git -C "$destination" fetch origin "$revision"
    fi
    git -C "$destination" checkout --detach --quiet "$revision"
}

vendor_choutiui() {
    mkdir -p "$ROOT_DIR/research-repos"

    clone_at_revision ChouTiUI https://github.com/honghaoz/ChouTiUI.git "$CHOUTIUI_SHA"
    clone_at_revision ChouTi https://github.com/honghaoz/ChouTi.git "$CHOUTI_SHA"
    clone_at_revision ComposeUI https://github.com/honghaoz/ComposeUI.git "$COMPOSEUI_SHA"

    git -C "$ROOT_DIR/research-repos/ChouTiUI" apply "$CHOUTIUI_PATCH"
    GIT_AUTHOR_DATE="2000-01-01T00:00:00Z" \
        GIT_COMMITTER_DATE="2000-01-01T00:00:00Z" \
        git -C "$ROOT_DIR/research-repos/ChouTiUI" \
        -c user.name=Nanyin \
        -c user.email=noreply@nanyin.local \
        -c commit.gpgSign=false \
        commit -am "Use vendored path dependencies"

    printf 'Vendored ChouTiUI dependencies are ready.\n'
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    vendor_choutiui
fi
