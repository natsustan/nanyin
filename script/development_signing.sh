#!/usr/bin/env bash
# Shared development signing, sourced by build scripts. Produces
# NANYIN_SIGNING_SETTINGS for xcodebuild.
#
# The identity must stay the same across builds: the Keychain recognises the
# app by its signature and asks again whenever it changes. The team is read
# from the certificate; with several Apple Development certificates, set
# NANYIN_DEVELOPMENT_TEAM and NANYIN_CODE_SIGN_IDENTITY explicitly.
if [[ -z "${NANYIN_DEVELOPMENT_TEAM:-}" ]]; then
    if [[ -n "${NANYIN_CODE_SIGN_IDENTITY:-}" ]]; then
        echo "Set NANYIN_DEVELOPMENT_TEAM alongside NANYIN_CODE_SIGN_IDENTITY." >&2
        exit 1
    fi
    DEVELOPMENT_IDENTITIES=()
    while IFS= read -r identity; do
        [[ -n "$identity" ]] && DEVELOPMENT_IDENTITIES+=("$identity")
    done < <(security find-identity -p codesigning -v | sed -n 's/.*"\(Apple Development: [^"]*\)".*/\1/p')
    if [[ ${#DEVELOPMENT_IDENTITIES[@]} -ne 1 ]]; then
        echo "Set NANYIN_DEVELOPMENT_TEAM and NANYIN_CODE_SIGN_IDENTITY to a stable development identity (found ${#DEVELOPMENT_IDENTITIES[@]} Apple Development identities)." >&2
        exit 1
    fi
    NANYIN_DEVELOPMENT_TEAM="$(security find-certificate -c "${DEVELOPMENT_IDENTITIES[0]}" -p |
        openssl x509 -noout -subject -nameopt multiline |
        sed -n 's/^[[:space:]]*organizationalUnitName[[:space:]]*=[[:space:]]*//p')"
    : "${NANYIN_DEVELOPMENT_TEAM:?Could not read the development certificate team; set NANYIN_DEVELOPMENT_TEAM explicitly.}"
fi

NANYIN_SIGNING_SETTINGS=(
    "DEVELOPMENT_TEAM=$NANYIN_DEVELOPMENT_TEAM"
    "CODE_SIGN_IDENTITY=${NANYIN_CODE_SIGN_IDENTITY:-Apple Development}"
)
