---
name: release-prod
description: Release the latest master as a new Peek version on GitHub Releases, so installed Peek apps update in-app.
disable-model-invocation: true
---

# Release Peek

Publishes the latest pushed `master` as a prod release. Confirm with the user before every commit, push, and publish.

1. Check the tree. Stop and report if any fails:
   - On `master`, `git status --short` is empty.
   - `git fetch` and HEAD equals `origin/master`.
   - CI passed for HEAD: `gh run list --commit $(git rev-parse HEAD)`.
2. Pick the version. Read `MARKETING_VERSION` in `project.yml`. If release `v<version>` already exists (`gh release view v<version>`):
   - Propose the next version from the commits since the last tag, and ask the user.
   - Set `MARKETING_VERSION`, and add a `CHANGELOG.md` section in the existing format, drafted from `git log <last tag>..HEAD`. Show both to the user.
   - On approval, commit as "Release Peek <version>" and push. Wait for CI on that commit.
3. Run `scripts/build-release.sh`. It prints the DMG path and SHA-256; stop on any failure.
4. Ask the user to confirm, then publish as the latest release, not a pre-release:
   `gh release create v<version> dist/Peek-<version>.dmg dist/appcast.xml --target $(git rev-parse HEAD) --latest --title "Peek <version>" --notes "<this version's CHANGELOG section>"`
5. Report the release URL and SHA-256. Tell the user to choose **Check for Updates...** in Peek's menu bar menu.
