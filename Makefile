# Contributor task runner — same recipes as the Justfile; use whichever
# tool you have (`just` or plain `make`).

.PHONY: build test app run dmg clean

build:
	swift build

test:
	DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test

app:
	scripts/build_app.sh

run: app
	open dist/Voltio.app

dmg:
	scripts/dist.sh

clean:
	swift package clean
