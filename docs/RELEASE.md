# Publishing a release

AudioRouter currently uses local ad-hoc signing. A successful build or signature check is not Apple notarization and does not prove compatibility with every output device.

1. Run `./test.sh` and `./build.sh` from the AudioRouter folder on a Mac.
2. Extract `dist/AudioRouter.zip` into a temporary folder and verify the app with `codesign --verify --deep --strict AudioRouter.app`.
3. Run the listening checks in the main README on the exact build being released. Record the macOS version, chip, output devices, and results. Label untested configurations clearly.
4. Create a GitHub release using a project-specific tag such as `audiorouter-v0.2.2` in a multi-project repository. Upload the ZIP as an asset, with its architecture in the asset name (for example, `AudioRouter-0.2.2-arm64.zip`). Do not commit build caches or app bundles into source control.
5. Include `shasum -a 256 dist/AudioRouter.zip` in the release notes and describe the ad-hoc signing status. Add the real release download link to the README only after the asset is published.

The build script compiles for the machine's native CPU architecture. An Apple silicon build is not a universal or Intel build. An Intel release requires its own build and runtime verification.

For a conventional notarized download, the maintainer needs Apple Developer Program membership and a Developer ID Application signing identity. Sign with the appropriate hardened runtime configuration, submit to Apple's notarization service, staple the accepted ticket, and test the downloaded artifact before replacing the ad-hoc release. Keep signing credentials out of the repository. See [Apple's notarization documentation](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).

Before publishing into an existing repository, check its license and contribution rules. Public visibility alone does not grant an open-source license; use the repository owner's chosen license and make its scope clear.
