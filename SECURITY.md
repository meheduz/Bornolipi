# Security

## Reporting a vulnerability

Please report security problems privately, using GitHub's **Report a vulnerability** button on the
repository's Security tab, rather than in a public issue. Include the Bornolipi version, the macOS
version, and steps to reproduce. If the button is missing, open a public issue that only asks for a
private contact, without details. You should get a reply within a week.

## What Bornolipi does and does not do

- The keyboard (`BornolipiKeyboard.app`) never connects to the internet: it shares a library with the app
  that includes the app's update check, but nothing in the keyboard calls it. What you type never
  leaves your Mac.
- The Bornolipi app connects only to `api.github.com`, to read the latest release's version and notes,
  at most once a day while the app runs (on by default; turn off "Check for updates automatically"),
  or when you click **Check Now**. The request has no cookies and no identifying headers.
- Bornolipi never downloads or installs an update by itself, and asks for no administrator password,
  Accessibility, Input Monitoring or Full Disk Access permission.
- Password fields always receive plain letters: macOS turns third-party keyboards off there.

## Release integrity

Each release is built with `scripts/test.sh release`, checked with `scripts/check-release.sh` and uploaded by hand. Each release
lists the SHA-256 checksum of its disk image (`SHA256SUMS`); compare it with your download. Releases are not signed with a
Developer ID and not notarized; see [docs/INSTALL.md](docs/INSTALL.md) for what that means and
[docs/DECISIONS.md](docs/DECISIONS.md) (D-07) for the update design.
