.PHONY: configure project check test

SIMULATOR_DESTINATION ?= platform=iOS Simulator,name=iPhone 17 Pro,OS=latest

configure:
	./Scripts/configure-posthog.sh

project: configure
	xcodegen generate

check: project
	xcodebuild -project PayMeTime.xcodeproj -scheme PayMeTime -destination '$(SIMULATOR_DESTINATION)' -configuration Debug build CODE_SIGNING_ALLOWED=NO

test: project
	xcodebuild -project PayMeTime.xcodeproj -scheme PayMeTime -destination '$(SIMULATOR_DESTINATION)' -configuration Debug test CODE_SIGNING_ALLOWED=NO
