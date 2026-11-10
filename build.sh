#!/bin/zsh
# Usage: ./build.sh            -> build/EventHorizon.app
#        ./build.sh install    -> also installs to /Applications and launches
#        ./build.sh release    -> universal (Apple Silicon + Intel) build/EventHorizon.zip + .zip.sig + .sbom.cdx.json
#        ./build.sh keygen     -> creates the release signing key in the Keychain (once)
set -e
cd "$(dirname "$0")"

APP="build/EventHorizon.app"

if [[ "$1" == "keygen" ]]; then
    swift scripts/sign.swift keygen
    echo "Key saved in Keychain as \"EventHorizon Signing Key\". Paste the public key above into releasePublicKey in Sources/UpdateChecker.swift."
    exit 0
fi

if [[ "$1" == "release" ]]; then
    git fetch -q origin main
    if [[ "$(git branch --show-current)" != "main" || -n "$(git status --porcelain --untracked-files=no)" \
          || "$(git rev-parse HEAD)" != "$(git rev-parse origin/main)" ]]; then
        echo "Releases are built from main only: check out main, commit everything and pull first." >&2
        exit 1
    fi
    swift build -c release --arch arm64 --arch x86_64
    BINARY=".build/apple/Products/Release/EventHorizon"
else
    swift build -c release
    BINARY=".build/release/EventHorizon"
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/"
cp Info.plist "$APP/Contents/"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
# Ad-hoc identity is normally the binary hash, which changes every build and makes macOS
# re-ask for folder access. Pinning the requirement to the bundle ID keeps permissions across builds.
codesign --force --sign - -r='designated => identifier "com.kasperback.eventhorizon"' "$APP"
echo "Built $APP"

if [[ "$1" == "install" ]]; then
    pkill -x EventHorizon || true
    rm -rf /Applications/EventHorizon.app
    cp -R "$APP" /Applications/
    open /Applications/EventHorizon.app
    echo "Installed and launched"
fi

if [[ "$1" == "release" ]]; then
    ditto -c -k --keepParent "$APP" build/EventHorizon.zip
    swift scripts/sign.swift sign build/EventHorizon.zip > build/EventHorizon.zip.sig
    python3 scripts/sbom.py "$BINARY" build/EventHorizon.sbom.cdx.json
    echo "Packaged build/EventHorizon.zip, .zip.sig and .sbom.cdx.json. Upload all three to the release."
fi
