.PHONY: configure project check test verify-entitlements verify-archive-entitlements verify-ipa-entitlements

SIMULATOR_DESTINATION ?= platform=iOS Simulator,name=iPhone 17 Pro,OS=latest

configure:
	./Scripts/configure-posthog.sh

project: configure
	xcodegen generate

check: project
	xcodebuild -project PayMeTime.xcodeproj -scheme PayMeTime -destination '$(SIMULATOR_DESTINATION)' -configuration Debug build CODE_SIGNING_ALLOWED=NO

test: project
	xcodebuild -project PayMeTime.xcodeproj -scheme PayMeTime -destination '$(SIMULATOR_DESTINATION)' -configuration Debug test CODE_SIGNING_ALLOWED=NO

verify-entitlements: project
	./Scripts/verify-family-controls-entitlements.sh configuration

verify-archive-entitlements:
	@test -n "$(ARCHIVE)" || (echo 'Usage: make verify-archive-entitlements ARCHIVE=/path/to/Screenbump.xcarchive' && exit 1)
	./Scripts/verify-family-controls-entitlements.sh archive '$(ARCHIVE)'

verify-ipa-entitlements:
	@test -n "$(IPA)" || (echo 'Usage: make verify-ipa-entitlements IPA=/path/to/Screenbump.ipa' && exit 1)
	./Scripts/verify-family-controls-entitlements.sh ipa '$(IPA)'
