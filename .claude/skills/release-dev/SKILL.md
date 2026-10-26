---
name: release-dev
description: Build the current working tree as Peek Dev and publish it to the rolling `dev` GitHub pre-release, so installed Peek Dev apps update in-app.
disable-model-invocation: true
---

# Release Peek Dev

Publishes the latest local code as a Peek Dev update. Uncommitted changes are included and the build is marked `-dirty`.

1. Show `git status --short` and `git log -1 --oneline` so the user sees what ships.
2. Run `scripts/build-release.sh dev`. It prints the DMG path and SHA-256; stop on any failure and report it.
3. Recreate the `dev` release so it lists first. GitHub orders releases by the date of the tag's commit, so the tag moves to the newest pushed `master`:
   - `gh release delete dev --cleanup-tag --yes` (skip if `gh release view dev` finds none), then `git tag -d dev` locally if present.
   - `gh release create dev dist/dev/Peek-Dev.dmg dist/dev/appcast.xml --prerelease --target master --title "Peek Dev" --notes "<title from dist/dev/appcast.xml>, build <sparkle:version>, SHA-256 <sha>"`
   It must stay a pre-release, or prod's `releases/latest` feed would pick it up. Installed apps briefly miss the feed between delete and create; the next check finds it.
4. Check the order: `gh release list --limit 2` shows `Peek Dev` first. If it does not, report it.
5. Report the build number and commit. Tell the user to choose **Check for Updates...** in Peek Dev's menu bar menu.
   First install only: download `Peek-Dev.dmg` from the `dev` release and drag it to Applications. Builds from `scripts/build-app.sh` have no feed and never update.
