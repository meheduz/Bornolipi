# Releasing (free distribution)

Bornolipi is distributed at no cost: an ad-hoc signed universal disk image on GitHub Releases. No Apple
Developer Program membership, Homebrew, Xcode or Terminal is needed by users. Nothing is published
without the maintainer doing it by hand.

1. Keep `VERSION` (numeric, for the bundles: 0.1.0) and `RELEASE_LABEL` (the public name: 0.1.0-beta.1) and add the release's section to `CHANGELOG.md`.
   Raise `BUILD_NUMBER` above every build anyone may have installed: the app replaces the installed
   keyboard only when the one it carries has a higher version or build number.
2. Check: `scripts/test.sh` (lint, tests, evaluations, security). `BORNOLIPI_ALLOW_INSTALL=1 scripts/dev-install.sh &&
   scripts/e2e-test.sh` also types through macOS, but replaces the installed keyboard. Then the manual checks
   listed in [RELEASE-READINESS.md](RELEASE-READINESS.md), or record each one there as not verified.
3. Build: `scripts/make-dmg.sh` (universal arm64 + x86_64, ad-hoc signed). It prints the SHA-256.
4. Confirm both architectures inside the image: mount it and run `lipo -archs` on
   `Bornolipi.app/Contents/MacOS/Bornolipi` and `Bornolipi.app/Contents/Resources/BornolipiKeyboard.app/Contents/MacOS/BornolipiKeyboard`.
5. GitHub: create the release by hand with the image built and tested above. The manual **Release**
   workflow builds a new image on GitHub (a different checksum, not the one you tested) and uses
   CHANGELOG.md as the notes, so for 0.1.0 it is not used.

Run `scripts/check-release.sh build/Bornolipi-<version>.dmg`. Its integrity checks (contents, identities,
version and build number, minimum macOS, universal binaries, valid signatures) must all pass, also for
these free ad-hoc builds; the Release workflow stops on a failure. Developer ID, notarization and
Gatekeeper checks apply only to a Developer ID build; for an ad-hoc build the script says so instead.

## Publishing a beta

Nothing is published without the maintainer doing it by hand.

1. The repository is `github.com/meheduz/Bornolipi`; keep the name exactly `Bornolipi`, because the
   app's update check reads `api.github.com/repos/meheduz/Bornolipi/releases/latest`.
2. Tag the release commit with the release label, for example `v0.1.0-beta.1`, and create a GitHub
   release marked **pre-release** with the image built and tested above and its `SHA256SUMS`.
   The update check reads only the latest stable release, so beta testers are not offered betas
   automatically; they download them from the release page.
3. Download the image from the release page, compare its SHA-256 with `SHA256SUMS`, and open the
   app from that download once to confirm the Gatekeeper prompt and Open Anyway.

## Release notes template

```
Bornolipi 0.1.0 — Bangla Phonetic Keyboard for macOS 13 or later (Apple silicon and Intel). Free and open source (MPL-2.0).

Tested on <macOS version and Mac type actually tested>; not yet tested on <the rest>.

Install: download Bornolipi-0.1.0.dmg, drag Bornolipi to Applications, open it, and follow the setup assistant.
Step-by-step guide: https://github.com/meheduz/Bornolipi/blob/main/docs/INSTALL.md

Not signed with an Apple Developer ID and not notarized: Bornolipi is a free project without a paid Apple
membership. macOS will warn you the first time; allow Bornolipi with Apple's Open Anyway button in
System Settings > Privacy & Security (details in the guide). Never turn Gatekeeper off.

SHA-256 of Bornolipi-0.1.0.dmg: <paste from scripts/make-dmg.sh>
```


## If a Developer ID becomes available later

`SIGN_IDENTITY=... scripts/build.sh`, `scripts/make-dmg.sh` and `NOTARY_PROFILE=... scripts/notarize.sh`
produce a signed, notarized image; `scripts/check-release.sh` then passes.
