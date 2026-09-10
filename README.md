<h1>  <img src="assets/icon_128.png" alt="Hearsay icon" width="30"/> Hearsay</h1>

**Local speech-to-text for macOS.** Hold a key, speak, release — your words appear right where your cursor is. Everything runs on your Mac. 

![Demo](assets/demo.gif)

## Install

**[⬇ Download the latest release](https://github.com/swairshah/hearsay/releases/latest)** — open the DMG and drag Hearsay to Applications.

Or with Homebrew:

```bash
brew install --cask swairshah/tap/hearsay
```

## How to use

| Action | Default shortcut |
|--------|-----|
| **Record** | Hold **Right Option (⌥)** and speak |
| **Transcribe** | Release the key — text is pasted at your cursor |
| **Hands-free mode** | **⌥Space** to toggle recording, **Space** or **Esc** to stop |
| **Screenshot while recording** | **⌥4** to select a region, **⌥3** for the full screen — images are referenced in your transcript |

All shortcuts (and the Hold vs. Toggle activation style) are customizable in **Settings → Keyboard Shortcuts**.

Transcribed text is pasted at your cursor and copied to the clipboard — both behaviors can be toggled in Settings.

Every transcription is saved locally in **History** — find recent ones in the menu bar dropdown, or open the Hearsay window and click any line to copy it again. If a transcription ever fails, the audio is kept and you can retry it from History with one click.

## First launch

1. Grant **Microphone** permission when prompted
2. Grant **Accessibility** permission (System Settings → Privacy & Security → Accessibility)
3. Pick a speech model to download:
   - **Parakeet** — English and multilingual, Apple Silicon (recommended)
   - **Qwen** — fast and high-quality, works on all Macs including Intel
   - **Whisper** — English transcription (Apple Silicon)

You can download, switch between, and delete models anytime from the **Models** tab.

## The Hearsay window

Everything lives in one window with a sidebar:

- **Settings** — clipboard/paste behavior, sound effects, dock icon, history size, and keyboard shortcuts
- **Models** — download, activate, and delete speech models: Qwen Fast (0.6B) / Quality (1.7B), Whisper tiny.en / small.en, Parakeet English (v2) / Multilingual (v3)
- **Microphone** — pick your input device
- **Replacements** — automatic text substitutions applied to transcripts
- **Cleanup** & **Post Processing** — rules and LLM-powered polishing for transcribed text
- **History** — every transcription, click a line to copy it, retry failed ones
- **Permissions** — check and fix Microphone/Accessibility access

## Requirements

- macOS 13 (Ventura) or later
- Apple Silicon or Intel

## For developers

- Hearsay ships with a `hearsay` CLI (`hearsay dictate`, `hearsay history`, `hearsay logs`, …). Apps and editor extensions can use Hearsay as a local dictation provider — see the [Local API Integration Guide](docs/local-api-integration-guide.md).
- Speech backends: [qwen-asr](https://github.com/antirez/qwen-asr) by antirez, [WhisperKit](https://github.com/argmaxinc/WhisperKit), and NVIDIA Parakeet via [FluidAudio](https://github.com/FluidInference/FluidAudio).
- Build instructions and architecture: [DEVELOPMENT.md](DEVELOPMENT.md)

## License

MIT
