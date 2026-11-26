# Godot 4.7.2 archive verification

2026-11-26. The coordinator fetched the official GitHub release `SHA512-SUMS.txt` and the release's macOS universal editor ZIP and standard export-template TPZ referenced by `tools/toolchain/pin/engine.txt`. `shasum -a 512` matched the publisher's checksum for both archives:

- Editor ZIP: `38aa16e5bba2083941fc5b3e54be0089bd4cc35e32415f5b9fd9a8a6a7b9818255d44532ea8ef94b5aef56c4b407c2d634fa4f657e4ebe681ebbf59b7bac69ca`
- Templates TPZ: `ca4d71c4d7b81dfc15d1a98baa07534aa95b03fdda78a0075b06672e1648d2e5f40980c9adc28d23e1b92e732ee7bf3461997aa804af74ec2fcd7a93ccb84079`

`unzip -p ... Godot.app/Contents/MacOS/Godot | shasum -a 256` matched the installed editor binary at `c7cccbf8fb143e34e02fd6521e09be2c2b974f0d5db080b19071c9c570718ccf`. The same method matched the installed `version.txt`, `macos.zip`, `windows_release_x86_64.exe`, and `linux_release.x86_64` templates against the verified TPZ; their SHA-256 digests are in `tools/toolchain/pin/checksums.txt`. Other templates and app bundle files were not compared. No software was installed. These comparisons do not establish target-platform launch behavior or verify the Python/toolchain pin.
