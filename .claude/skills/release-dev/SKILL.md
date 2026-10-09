---
name: release-dev
description: Build the current working tree as Peek Dev and publish it to the rolling `dev` GitHub pre-release, so installed Peek Dev apps update in-app.
disable-model-invocation: true
---

# Release Peek Dev

Publishes the latest local code as a Peek Dev update. Uncommitted changes are included and the build is marked `-dirty`.

1. Show `git status --short` and `git log -1 --oneline` so the user sees what ships.
2. Run `scripts/build-release.sh dev`. It prints the DMG path and SHA-256; stop on any failure and report it.
3. Make sure the `dev` release exists: `gh release view dev`. If it does not, create it once:
   `gh release create dev --prerelease --target master --title "Peek Dev" --notes "Rolling QA build of Peek Dev."`
   It must stay a pre-release, or prod's `releases/latest` feed would pick it up.
4. Upload the DMG first, then the appcast, so the feed never points at a missing DMG:
   - `gh release upload dev dist/dev/Peek-Dev.dmg --clobber`
   - `gh release upload dev dist/dev/appcast.xml --clobber`
5. Update the notes with the build: `gh release edit dev --notes "<title from dist/dev/appcast.xml>, build <sparkle:version>, SHA-256 <sha>"`.
6. Report the build number and commit. Tell the user to choose **Check for Updates...** in Peek Dev's menu bar menu.
   First install only: download `Peek-Dev.dmg` from the `dev` release and drag it to Applications. Builds from `scripts/build-app.sh` have no feed and never update.
