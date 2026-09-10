<p align="center">
  <img src="Assets/AppIcon.png" width="128" height="128" alt="Codex Usage Widget hourglass app icon">
</p>

<h1 align="center">Codex Usage Widget</h1>

<p align="center">A native macOS floating capsule widget that keeps your Codex usage limits—and Credits when available—visible at a glance.</p>

<p align="center">It adapts to the usage windows reported by your local Codex service—either 5-hour and weekly limits, or a monthly limit.</p>

<p align="center">
  <a href="#installation">Installation</a> ·
  <a href="#privacy">Privacy</a> ·
  <a href="#build-from-source">Build from source</a>
</p>

## Codex usage at a glance

![Codex Usage Widget floating on a macOS desktop with 5-hour and weekly usage](Assets/codex-usage-widget-hero.png)

A real macOS desktop showing the floating widget with 5-hour and weekly usage remaining.

## Adapts to the data available

| Available data | Widget display |
| --- | --- |
| 5-hour and weekly limits | Two usage capsules |
| 5-hour and weekly limits, plus Credits | Two usage capsules plus a Credits capsule |
| Monthly limit | A Monthly capsule, plus Credits when available |

The widget displays only the usage windows and Credits data returned by your local Codex service.

## Menu Bar Controls

Check the latest usage summary and update time, refresh on demand, show or hide the desktop widget, and quit directly from the macOS menu bar.

![Codex Usage menu with the latest usage and update time, Hide Widget, Refresh Now, and Quit Codex Usage, beside the floating widget](Assets/menu-bar-controls.png)

## Highlights

- **Floating capsule widget** — Keep Codex usage visible in a compact, draggable, always-on-top desktop widget.
- **Adaptive usage windows** — See 5-hour and weekly limits or a monthly limit, depending on what the local Codex service provides.
- **Dynamic Credits display** — The Credits capsule appears only when a balance is available.
- **Native macOS experience** — Use the desktop widget together with a lightweight menu bar summary and controls.
- **Local-first privacy** — No credential scraping, browser-cookie access, telemetry, or account-data uploads.
- **Reliable refreshes** — Updates on local Codex events, every 60 seconds, after wake, and on demand.
- **Consistent account state** — Keeps the last successful reading through temporary failures and prevents stale session data from replacing current usage.

## Installation

A downloadable GitHub Release is planned. The current version can be built locally from source.

## Requirements

- macOS 13 Ventura or later.
- Swift 6 when building from source.
- Codex installed locally, either through the Codex CLI or a compatible ChatGPT app installation.
- A signed-in Codex/ChatGPT account.

The source builds for the architecture of the host Mac. The current V1 packaging script creates a single-architecture app for that host; it does not create a universal binary. Apple Silicon is verified locally. Intel source builds are expected to work but are not yet CI-verified.

Windows and Linux are not supported because the app uses AppKit and SwiftUI.

## Everyday use

Launch the app while Codex is installed and signed in. Drag the floating widget to reposition it. Use the menu bar icon to refresh, hide or show the widget, or quit.

## Credits

Credits are optional. The capsule appears only when the local Codex service provides a balance.

Credits are shown as their raw balance by default. This avoids presenting a currency conversion as an official OpenAI price.

On first use, the app creates this local configuration file:

```text
~/Library/Application Support/CodexUsageWidget/credit-display.json
```

To opt in to an estimated USD display, set `displayMode` to `estimatedUSD` and choose your own `usdPerCredit` value. The bundled `0.04` value is only a user-configurable project assumption. It is not an official or permanent OpenAI price. Estimated values are marked `est.` in the UI.

## Privacy

- The app communicates with the locally installed `codex app-server` over standard input/output.
- It requests `account/read` with token refresh disabled and `account/rateLimits/read`.
- It does not read `~/.codex/auth.json`.
- It does not read browser cookies or browser login data.
- It does not ask for, store, or upload API keys, passwords, or authentication tokens.
- It does not collect or upload account or usage data.
- Account information is processed only in memory on the local Mac. A one-way account fingerprint is used only to keep account and usage snapshots correctly associated; the email itself is not displayed or persisted by this app.
- Window position and the optional Credits display preference are stored locally.

The locally installed Codex service remains responsible for its own authenticated communication with OpenAI.

## Known Limitations

- macOS only; minimum version is macOS 13.
- The V1 build script creates an app for the current Mac architecture, not a universal binary.
- Developer ID signing, notarization, automatic updates, and automated releases are not included yet.
- Availability and shape of the local app-server response may change between Codex versions.
- Credits currency estimates depend entirely on the user's local assumption.

## Build from Source

```bash
git clone https://github.com/lylinnnnnn/codex-usage-widget.git
cd codex-usage-widget
swift build
swift test
./Scripts/build-app.sh
open build/CodexUsageWidget.app
```

The app bundle produced by the script is ad-hoc signed. Developer ID signing and notarization are intentionally outside the V1 scope.

For local UI development without reading an account, run:

```bash
swift run CodexUsageWidget --mock-usage
```

Set `CODEX_USAGE_WIDGET_CODEX_PATH` to an explicit executable path only when the automatic Codex lookup does not find your installation.

## Contributing

Issues and focused pull requests are welcome. Please run both commands before submitting a change:

```bash
swift build
swift test
```

Do not include credentials, account data, local logs, built apps, or machine-specific paths in issues or commits.

## License

MIT. See [LICENSE](LICENSE).

## Disclaimer

Unofficial project. Not affiliated with or endorsed by OpenAI.

Codex, ChatGPT, OpenAI, and related names and marks belong to their respective owners.
