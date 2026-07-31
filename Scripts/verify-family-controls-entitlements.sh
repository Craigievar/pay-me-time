#!/bin/sh

set -eu

screenbump_team_id="9JWU7V7424"
screenbump_app_group="group.com.nonagon.Screenbump"
screenbump_project_file="PayMeTime.xcodeproj/project.pbxproj"
screenbump_temp_dir=""

screenbump_cleanup() {
    if [ -n "$screenbump_temp_dir" ] && [ -d "$screenbump_temp_dir" ]; then
        rm -rf "$screenbump_temp_dir"
    fi
}

trap screenbump_cleanup EXIT HUP INT TERM

screenbump_fail() {
    echo "Family Controls verification failed: $*" >&2
    exit 1
}

screenbump_verify_plist() {
    screenbump_entitlements_file="$1"

    [ -f "$screenbump_entitlements_file" ] || screenbump_fail "missing $screenbump_entitlements_file"

    screenbump_family_controls_value="$(
        /usr/libexec/PlistBuddy -c 'Print :com.apple.developer.family-controls' \
            "$screenbump_entitlements_file" 2>/dev/null || true
    )"
    [ "$screenbump_family_controls_value" = "true" ] || \
        screenbump_fail "$screenbump_entitlements_file does not enable com.apple.developer.family-controls"

    /usr/libexec/PlistBuddy -c 'Print :com.apple.security.application-groups' \
        "$screenbump_entitlements_file" 2>/dev/null | grep -Fq "$screenbump_app_group" || \
        screenbump_fail "$screenbump_entitlements_file does not include $screenbump_app_group"
}

screenbump_verify_configuration() {
    [ -f project.yml ] || screenbump_fail "run this command from the repository root"
    [ -f "$screenbump_project_file" ] || screenbump_fail "missing $screenbump_project_file; run make project first"

    screenbump_yaml_entitlement_count="$(
        grep -Fc 'com.apple.developer.family-controls: true' project.yml || true
    )"
    [ "$screenbump_yaml_entitlement_count" -eq 5 ] || \
        screenbump_fail "project.yml must enable Family Controls for exactly five shipping targets"

    screenbump_yaml_team_count="$(grep -Fc 'DEVELOPMENT_TEAM: 9JWU7V7424' project.yml || true)"
    [ "$screenbump_yaml_team_count" -eq 1 ] || \
        screenbump_fail "project.yml must sign with Nonagon LLC team $screenbump_team_id"

    for screenbump_entitlements_file in \
        Config/PayMeTime.entitlements \
        Config/PayMeTimeShieldConfiguration.entitlements \
        Config/PayMeTimeShieldAction.entitlements \
        Config/PayMeTimeDeviceActivityMonitor.entitlements \
        Config/PayMeTimeDeviceActivityReport.entitlements
    do
        screenbump_verify_plist "$screenbump_entitlements_file"

        screenbump_project_reference_count="$(
            grep -Fc "CODE_SIGN_ENTITLEMENTS = $screenbump_entitlements_file;" \
                "$screenbump_project_file" || true
        )"
        [ "$screenbump_project_reference_count" -eq 2 ] || \
            screenbump_fail "$screenbump_project_file must reference $screenbump_entitlements_file in Debug and Release"
    done

    echo "Verified Family Controls configuration for all five Screenbump shipping targets."
}

screenbump_signed_entitlement_has_value() {
    screenbump_entitlements_text="$1"
    screenbump_key="$2"
    screenbump_expected_type="$3"
    screenbump_expected_value="$4"

    printf '%s\n' "$screenbump_entitlements_text" | awk \
        -v key="$screenbump_key" \
        -v expected_type="$screenbump_expected_type" \
        -v expected_value="$screenbump_expected_value" '
            index($0, "[Key] " key) { in_key = 1; next }
            in_key && index($0, "[" expected_type "] " expected_value) { found = 1; exit }
            in_key && index($0, "[Key]") { exit }
            END { exit(found ? 0 : 1) }
        '
}

screenbump_verify_signed_bundle() {
    screenbump_bundle_path="$1"
    screenbump_bundle_identifier="$2"

    [ -d "$screenbump_bundle_path" ] || screenbump_fail "missing signed bundle $screenbump_bundle_path"

    screenbump_signed_entitlements="$(
        /usr/bin/codesign -d --entitlements - "$screenbump_bundle_path" 2>&1
    )" || screenbump_fail "could not read signed entitlements from $screenbump_bundle_path"

    screenbump_signed_entitlement_has_value \
        "$screenbump_signed_entitlements" \
        "com.apple.developer.family-controls" \
        "Bool" \
        "true" || screenbump_fail "$screenbump_bundle_identifier is missing the signed Family Controls entitlement"

    screenbump_signed_entitlement_has_value \
        "$screenbump_signed_entitlements" \
        "application-identifier" \
        "String" \
        "$screenbump_team_id.$screenbump_bundle_identifier" || \
        screenbump_fail "$screenbump_bundle_identifier is not signed by Nonagon LLC team $screenbump_team_id"

    screenbump_signed_entitlement_has_value \
        "$screenbump_signed_entitlements" \
        "com.apple.security.application-groups" \
        "String" \
        "$screenbump_app_group" || screenbump_fail "$screenbump_bundle_identifier is missing $screenbump_app_group"
}

screenbump_verify_app() {
    screenbump_app_path="$1"

    screenbump_verify_signed_bundle \
        "$screenbump_app_path" \
        "com.nonagon.Screenbump"
    screenbump_verify_signed_bundle \
        "$screenbump_app_path/PlugIns/PayMeTimeShieldConfiguration.appex" \
        "com.nonagon.Screenbump.ShieldConfiguration"
    screenbump_verify_signed_bundle \
        "$screenbump_app_path/PlugIns/PayMeTimeShieldAction.appex" \
        "com.nonagon.Screenbump.ShieldAction"
    screenbump_verify_signed_bundle \
        "$screenbump_app_path/PlugIns/PayMeTimeDeviceActivityMonitor.appex" \
        "com.nonagon.Screenbump.DeviceActivityMonitor"
    screenbump_verify_signed_bundle \
        "$screenbump_app_path/Extensions/PayMeTimeDeviceActivityReport.appex" \
        "com.nonagon.Screenbump.DeviceActivityReport"

    echo "Verified signed Family Controls entitlements for Screenbump and all four extensions."
}

screenbump_mode="${1:-configuration}"

case "$screenbump_mode" in
    configuration)
        screenbump_verify_configuration
        ;;
    archive)
        [ "$#" -eq 2 ] || screenbump_fail "usage: $0 archive /path/to/Screenbump.xcarchive"
        screenbump_verify_app "$2/Products/Applications/PayMeTime.app"
        ;;
    ipa)
        [ "$#" -eq 2 ] || screenbump_fail "usage: $0 ipa /path/to/Screenbump.ipa"
        [ -f "$2" ] || screenbump_fail "missing IPA $2"
        screenbump_temp_dir="$(mktemp -d)"
        /usr/bin/unzip -q "$2" -d "$screenbump_temp_dir"
        screenbump_verify_app "$screenbump_temp_dir/Payload/PayMeTime.app"
        ;;
    *)
        screenbump_fail "unknown mode $screenbump_mode"
        ;;
esac
