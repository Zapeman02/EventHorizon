#!/bin/zsh
# Usage: ./scripts/release.sh
# Asks for the new version, merges the version bump into main through a PR (main is protected),
# then builds, signs and publishes the GitHub release from the updated main.
# Needs: the signing key in the Keychain (./build.sh keygen) and the GitHub CLI logged in (gh auth login).
set -e
cd "$(dirname "$0")/.."

alert() {
    osascript -e 'on run argv' -e 'display alert (item 1 of argv) message (item 2 of argv)' -e 'end run' "$1" "$2" >/dev/null
}

fail() {
    echo "$1" >&2
    osascript -e 'on run argv' -e 'display alert "Release failed" message (item 1 of argv) as critical' -e 'end run' "$1" >/dev/null
    exit 1
}

trap 'fail "A step failed (line $LINENO). See the Terminal output."' ERR

[[ -z "$(git status --porcelain --untracked-files=no)" ]] || fail "Commit or stash your changes first."
if ! swift scripts/sign.swift public >/dev/null 2>&1; then
    expected=$(sed -n 's/.*releasePublicKey = "\(.*\)".*/\1/p' Sources/UpdateChecker.swift)
    key=$(osascript -e 'text returned of (display dialog "No signing key on this Mac yet. Paste the private key from your password manager:" default answer "" with hidden answer buttons {"Cancel", "Save"} default button "Save" with title "Release EventHorizon")' 2>/dev/null) \
        || { echo "Cancelled."; exit 0; }
    print -rn -- "$key" | swift scripts/sign.swift import "$expected" || fail "That key doesn't match the app's public key. Nothing was saved."
    unset key
fi
gh auth status >/dev/null 2>&1 || fail "The GitHub CLI isn't logged in. Run: gh auth login"

git checkout -q main
git pull -q --ff-only

current=$(defaults read "$PWD/Info.plist" CFBundleShortVersionString)
parts=(${(s:.:)current})
parts[-1]=$((parts[-1] + 1))
suggested=${(j:.:)parts}

version=$(osascript -e 'on run argv' \
    -e 'text returned of (display dialog "New version (current is " & item 1 of argv & "):" default answer (item 2 of argv) buttons {"Cancel", "Release"} default button "Release" with title "Release EventHorizon")' \
    -e 'end run' "$current" "$suggested" 2>/dev/null) || { echo "Cancelled."; exit 0; }

[[ "$version" =~ '^[0-9]+(\.[0-9]+)*$' ]] || fail "\"$version\" is not a version number like $suggested."
[[ "$version" != "$current" && "$(printf '%s\n%s\n' "$current" "$version" | sort -V | tail -1)" == "$version" ]] \
    || fail "$version is not newer than $current."
[[ -z "$(git ls-remote --tags origin "v$version")" ]] || fail "The tag v$version already exists on GitHub."

branch="release/v$version"
echo "Bumping version to $version on $branch"
git checkout -q -b "$branch"
sed -i '' -e "s|<key>CFBundleShortVersionString</key><string>[^<]*</string>|<key>CFBundleShortVersionString</key><string>$version</string>|" \
          -e "s|<key>CFBundleVersion</key><string>[^<]*</string>|<key>CFBundleVersion</key><string>$version</string>|" Info.plist
git commit -q -am "Bump version to $version"
git push -q -u origin "$branch"
gh pr create --base main --head "$branch" --title "Release v$version" --body "Bump version to $version." >/dev/null

echo "Waiting for CI"
for _ in {1..24}; do
    [[ "$(gh pr view "$branch" --json statusCheckRollup --jq '.statusCheckRollup | length')" -gt 0 ]] && break
    sleep 5
done
gh pr checks "$branch" --watch --interval 15 >/dev/null || fail "CI failed for $branch. Nothing was released."
gh pr merge "$branch" --merge --delete-branch >/dev/null

git checkout -q main
git pull -q --ff-only

echo "Building and signing v$version"
./build.sh release
git tag "v$version"
git push -q origin "v$version"
gh release create "v$version" build/EventHorizon.zip build/EventHorizon.zip.sig build/EventHorizon.sbom.cdx.json \
    --title "EventHorizon $version" --generate-notes >/dev/null

echo "Released v$version"
alert "EventHorizon v$version is released" "https://github.com/Zapeman02/EventHorizon/releases/tag/v$version"
