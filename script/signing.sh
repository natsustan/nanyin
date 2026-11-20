#!/usr/bin/env bash
# Shared signing, sourced by build scripts. Produces NANYIN_SIGNING_SETTINGS
# for xcodebuild from NANYIN_CONFIGURATION: Debug signs with the Apple
# Development certificate, Release with Developer ID (timestamped, ready to
# notarize).
#
# The identity must stay the same across builds: the Keychain recognises the
# app by its signature and asks again whenever it changes. The team is read
# from the certificate; with several matching certificates, set
# NANYIN_DEVELOPMENT_TEAM and NANYIN_CODE_SIGN_IDENTITY explicitly.
if [[ "${NANYIN_CONFIGURATION:-Debug}" == "Release" ]]; then
    NANYIN_IDENTITY_KIND="Developer ID Application"
else
    NANYIN_IDENTITY_KIND="Apple Development"
fi

if [[ -z "${NANYIN_DEVELOPMENT_TEAM:-}" ]]; then
    if [[ -n "${NANYIN_CODE_SIGN_IDENTITY:-}" ]]; then
        echo "Set NANYIN_DEVELOPMENT_TEAM alongside NANYIN_CODE_SIGN_IDENTITY." >&2
        exit 1
    fi
    IDENTITIES=()
    while IFS= read -r identity; do
        [[ -n "$identity" ]] && IDENTITIES+=("$identity")
    done < <(security find-identity -p codesigning -v | sed -n "s/.*\"\($NANYIN_IDENTITY_KIND: [^\"]*\)\".*/\1/p")
    if [[ ${#IDENTITIES[@]} -ne 1 ]]; then
        echo "Set NANYIN_DEVELOPMENT_TEAM and NANYIN_CODE_SIGN_IDENTITY to a stable signing identity (found ${#IDENTITIES[@]} $NANYIN_IDENTITY_KIND identities)." >&2
        exit 1
    fi
    NANYIN_DEVELOPMENT_TEAM="$(security find-certificate -c "${IDENTITIES[0]}" -p |
        openssl x509 -noout -subject -nameopt multiline |
        sed -n 's/^[[:space:]]*organizationalUnitName[[:space:]]*=[[:space:]]*//p')"
    : "${NANYIN_DEVELOPMENT_TEAM:?Could not read the certificate team; set NANYIN_DEVELOPMENT_TEAM explicitly.}"
fi

NANYIN_SIGNING_SETTINGS=(
    "DEVELOPMENT_TEAM=$NANYIN_DEVELOPMENT_TEAM"
    "CODE_SIGN_IDENTITY=${NANYIN_CODE_SIGN_IDENTITY:-$NANYIN_IDENTITY_KIND}"
)
if [[ "${NANYIN_CONFIGURATION:-Debug}" == "Release" ]]; then
    NANYIN_SIGNING_SETTINGS+=("OTHER_CODE_SIGN_FLAGS=--timestamp")
fi
