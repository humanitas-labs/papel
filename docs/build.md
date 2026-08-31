# Build Paper

Paper uses [XcodeGen](https://github.com/yonaskolb/XcodeGen); the project file is generated from `project.yml`.

```bash
xcodegen generate
xcodebuild -project Paper.xcodeproj -scheme Paper -configuration Release build
```

## Tests

```bash
xcodebuild -project Paper.xcodeproj -scheme Paper \
  -destination 'platform=macOS' test
```

The build is warning-free. Tests cover byte-exact round trips, concealment geometry (line and document height never change on reveal), list and quote layout, undo paths, and the invariant that styling never edits the text. Setting `TEST_RUNNER_PAPER_PROBE_DIR=<dir>` additionally writes offscreen renders and restyle timings there for review. The README screenshot is one of those renders.
