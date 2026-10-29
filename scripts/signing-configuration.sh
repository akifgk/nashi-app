#!/bin/zsh
# Source from the repository root. Configuration contains a public certificate
# fingerprint, never a private key or a Keychain password.

nashi_load_signing_configuration() {
  local configuration=${NASHI_SIGNING_CONFIG:-"$PWD/Configuration/Signing.plist"}
  local configured_mode="" configured_identity=""
  if [[ -f "$configuration" ]]; then
    plutil -lint "$configuration" >/dev/null || { print -u2 "Invalid signing configuration: $configuration"; return 1; }
    configured_mode=$(plutil -extract Mode raw -expect string -o - "$configuration") || { print -u2 "Signing configuration requires a string Mode."; return 1; }
    if plutil -type IdentitySHA1 "$configuration" >/dev/null 2>&1; then
      configured_identity=$(plutil -extract IdentitySHA1 raw -expect string -o - "$configuration") || { print -u2 "IdentitySHA1 must be a string."; return 1; }
    fi
  elif [[ -n "${NASHI_SIGNING_CONFIG:-}" ]]; then
    print -u2 "Signing configuration does not exist: $configuration"; return 1
  fi

  nashi_signing_mode=${NASHI_SIGNING_MODE:-${configured_mode:-ad-hoc}}
  nashi_signing_identity=${NASHI_SIGNING_IDENTITY:-$configured_identity}
  if [[ -z "$nashi_signing_identity" && "$nashi_signing_mode" == ad-hoc ]]; then nashi_signing_identity="-"; fi
  case "$nashi_signing_mode" in
    ad-hoc)
      if [[ "$nashi_signing_identity" != "-" ]]; then print -u2 "A certificate identity requires explicit local, apple-development, or developer-id signing mode."; return 1; fi
      nashi_signing_flags=(--force --sign - --options 0 --timestamp=none)
      ;;
    local|apple-development|developer-id)
      if [[ ! "$nashi_signing_identity" =~ '^[0-9A-Fa-f]{40}$' ]]; then print -u2 "Stable signing requires the exact 40-hex certificate SHA-1, not a certificate name."; return 1; fi
      nashi_signing_identity=${nashi_signing_identity:u}
      nashi_signing_flags=(--force --sign "$nashi_signing_identity")
      if [[ "$nashi_signing_mode" != developer-id ]]; then
        nashi_signing_flags+=(--options 0 --timestamp=none)
      else
        nashi_signing_flags+=(--options runtime --timestamp)
      fi
      ;;
    *) print -u2 "Signing Mode must be ad-hoc, local, apple-development, or developer-id."; return 1 ;;
  esac
  if [[ -n "${NASHI_NOTARY_PROFILE:-}" && "$nashi_signing_mode" != developer-id ]]; then
    print -u2 "Notarization requires developer-id signing mode."; return 1
  fi
  export NASHI_SIGNING_MODE="$nashi_signing_mode"
  export NASHI_SIGNING_IDENTITY="$nashi_signing_identity"
}

nashi_require_release_signing() {
  local scope=${1:-release}
  if [[ "$nashi_signing_mode" == apple-development || "$nashi_signing_mode" == developer-id ]]; then return 0; fi
  # The release integration fixture uses an isolated, validated loopback feed.
  # Publishing never accepts this exception, even when its flag is inherited.
  if [[ "$scope" == local-test && "${NASHI_ALLOW_AD_HOC_TEST_RELEASE:-}" == 1 ]]; then return 0; fi
  if [[ "$nashi_signing_mode" == local ]]; then
    python3 scripts/build-credential-broker.py || {
      print -u2 "Local update releases require the verified frozen credential broker matching the main app certificate. Restore it or complete the explicit reviewed initialization."
      return 1
    }
    return 0
  fi
  print -u2 "Release signing is not configured. Pin an Apple Development or Developer ID certificate in Configuration/Signing.plist; ad-hoc releases are refused."
  return 1
}

nashi_verify_release_app() {
  nashi_verify_signing_identity "$1" || return 1
  if [[ "$nashi_signing_mode" == local ]]; then
    python3 scripts/build-credential-broker.py --verify-app "$1" || return 1
  fi
}

nashi_verify_signing_identity() {
  local code=$1
  if [[ "$nashi_signing_mode" == ad-hoc ]]; then return 0; fi
  codesign --verify --strict --test-requirement "=certificate leaf = H\"$nashi_signing_identity\"" "$code" || return 1
  if [[ "$nashi_signing_mode" == developer-id ]]; then
    codesign --verify --strict --test-requirement '=anchor apple generic and certificate leaf[field.1.2.840.113635.100.6.1.13] exists' "$code" || {
      print -u2 "developer-id mode requires an Apple-issued Developer ID Application certificate."; return 1
    }
  elif [[ "$nashi_signing_mode" == apple-development ]]; then
    # Apple's securityd development branch: WWDR CA and Mac Development leaf.
    # https://github.com/apple-oss-distributions/Security/blob/db15acbe6a7f257a859ad9a3bb86097bfe0679d9/securityd/src/clientid.cpp#L207-L211
    codesign --verify --strict --test-requirement '=anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.1] exists and certificate leaf[field.1.2.840.113635.100.6.1.12] exists' "$code" || {
      print -u2 "apple-development mode requires an Apple-issued Mac Development certificate."; return 1
    }
  fi
}
