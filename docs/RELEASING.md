# Releasing

Copicol follows [Semantic Versioning](https://semver.org). The version lives in `project.yml`: `MARKETING_VERSION` (for example `0.2.0`) and the build number `CURRENT_PROJECT_VERSION`.

## Publishing a release

1. On a branch from `main`, move the **Unreleased** entries of `CHANGELOG.md` under a new `## [X.Y.Z] - YYYY-MM-DD` heading and update the comparison links at the bottom of the file.
2. In `project.yml`, set `MARKETING_VERSION` to `X.Y.Z` and increment `CURRENT_PROJECT_VERSION`.
3. Check locally:

   ```sh
   scripts/build-release.sh          # universal build, signature checks, disk image and checksum
   scripts/release-notes.sh X.Y.Z    # notes that will be published
   ```

4. Commit (`chore: release X.Y.Z`), open a pull request and merge it once CI passes.
5. Tag the merge commit and push the tag:

   ```sh
   git switch main && git pull
   git tag -a vX.Y.Z -m "Copicol X.Y.Z"
   git push origin vX.Y.Z
   ```

6. The **Release** workflow (`.github/workflows/release.yml`) checks that the tag matches `MARKETING_VERSION`, runs the tests, builds the universal app and publishes a GitHub release with the `Copicol-X.Y.Z.dmg` disk image, its `.sha256` checksum and the changelog notes.

If the workflow fails, fix the problem on `main`, delete the tag (`git push --delete origin vX.Y.Z` and `git tag -d vX.Y.Z`), then tag again.

## Signing

Release builds are signed **ad hoc**: they run on any Mac, but Gatekeeper warns on first launch and macOS resets the Accessibility permission after each update. The README explains both workarounds to users.

## Planned distribution channels

None of these is set up yet; each requires a paid Apple Developer Program membership.

- **Developer ID signing and notarization** of the GitHub releases, which removes the Gatekeeper warning and keeps the Accessibility permission across updates.
- **Homebrew cask**, once releases are notarized.
- **Mac App Store**: the app is already sandboxed.
