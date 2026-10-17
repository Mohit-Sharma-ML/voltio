# Contributor task runner — `just` (https://github.com/casey/just).
# A Makefile with the same recipes is checked in too; use either.

default:
    @just --list

# Quick debug build
build:
    swift build

# Full test suite (Xcode toolchain — survives swiftly/standalone Swift shadowing Xcode's)
test:
    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test

# Runnable .app in dist/
app:
    scripts/build_app.sh

# Build and open the app
run: app
    open dist/Voltio.app

# Release DMG in dist/ (free-signing by default; see scripts/dist.sh for notarization mode)
dmg:
    scripts/dist.sh

# Clean build artifacts
clean:
    swift package clean
