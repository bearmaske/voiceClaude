# VoiceClaude: macOS Menu-Bar Voice Input App

## Overview

A macOS 14+ menu-bar voice input app that records audio while the Fn key is held, transcribes speech via Apple Speech Recognition (streaming), optionally refines via LLM, and injects the resulting text into the currently focused input field.

## Architecture

Single-process Swift app running as LSUIElement (no Dock icon). Built with Swift Package Manager.

### Components

1. **AppDelegate** — App entry point, menu bar setup, permission checks
2. **FnKeyMonitor** — CGEvent tap for global Fn key press/release detection, suppresses Fn to prevent emoji picker
3. **AudioEngine** — AVAudioEngine wrapper for recording + real-time RMS level metering
4. **SpeechRecognizer** — SFSpeechRecognizer streaming transcription, default locale zh-CN
5. **LLMRefiner** — OpenAI-compatible API client for post-transcription correction
6. **TextInjector** — Clipboard-based text injection with CJK input method handling
7. **CapsulePanel** — NSPanel (nonactivating) floating window with waveform + transcription display
8. **WaveformView** — 5-bar waveform driven by real-time RMS audio levels
9. **SettingsManager** — UserDefaults persistence for language, LLM config
10. **SettingsWindowController** — LLM settings window (API Base URL, Key, Model)

### Data Flow

```
Fn press → AudioEngine.start() + SpeechRecognizer.start() + CapsulePanel.show()
         ↓
Audio buffer → RMS level → WaveformView (real-time)
         ↓
Audio buffer → SFSpeechRecognizer → partial transcription → CapsulePanel label
         ↓
Fn release → AudioEngine.stop() + SpeechRecognizer.finish()
         ↓
         → [if LLM enabled] LLMRefiner.refine(text) → CapsulePanel "Refining..."
         ↓
Final text → TextInjector.inject(text) → CapsulePanel.dismiss()
```

## Fn Key Monitoring

- CGEvent tap at `.cghidEventTap` level, listening for `.flagsChanged` events
- Detect Fn by checking `CGEventFlags.maskSecondaryFn` bit toggling
- Return `nil` from tap callback to suppress Fn event (prevents emoji picker)
- Requires Accessibility permission — app auto-prompts via `AXIsProcessTrustedWithOptions` on launch

## Audio & Speech Recognition

- AVAudioEngine with input node tap for PCM audio
- RMS calculated per buffer: `sqrt(mean(samples^2))`, converted to normalized 0-1 range
- SFSpeechRecognizer with `SFSpeechAudioBufferRecognitionRequest` for streaming
- Default locale: `Locale(identifier: "zh_Hans")` (Simplified Chinese)
- Language options stored in UserDefaults, switchable from menu:
  - English (en-US)
  - Simplified Chinese (zh_Hans)
  - Traditional Chinese (zh_Hant)
  - Japanese (ja-JP)
  - Korean (ko-KR)

## Capsule Floating Window

- **Container:** NSPanel with `.nonactivatingPanel`, `.fullSizeContentView`, `.hudWindow` style masks. Level: `.floating`. No titlebar, no buttons.
- **Background:** NSVisualEffectView with `.hudWindow` material, `.active` state
- **Shape:** Height 56px, corner radius 28px, capsule
- **Position:** Screen bottom center, 80px from bottom edge
- **Content:**
  - Left: WaveformView (44x32px) — 5 vertical bars
  - Right: NSTextField label, width 160-560px elastic

### Waveform Animation

- 5 bars with weights [0.5, 0.8, 1.0, 0.75, 0.55]
- Driven by real-time RMS: `barHeight = baseHeight * weight * smoothedRMS`
- Smoothing envelope: attack coefficient 0.40, release coefficient 0.15
- Random jitter: +/-4% per bar per frame for organic feel
- Minimum bar height: 4px
- Bars have rounded caps, spacing 4px

### Animations

- **Entrance:** Spring animation, 0.35s duration — scale from 0.5 to 1.0, fade in
- **Text width change:** 0.25s ease-in-out transition on panel width
- **Exit:** 0.22s scale down to 0.8 + fade out

## Text Injection

1. Save current pasteboard contents (all types)
2. Set pasteboard to transcribed text
3. Check current input source via `TISCopyCurrentKeyboardInputSource`
4. If input source is CJK (id contains "Chinese", "Japanese", "Korean", "Pinyin", "Wubi", etc.):
   a. Switch to ASCII source (find "com.apple.keylayout.ABC" or "com.apple.keylayout.US")
   b. Simulate Cmd+V via CGEvent
   c. Restore original input source
5. Else: simulate Cmd+V directly
6. After 100ms delay, restore original pasteboard contents

## LLM Refinement

### API

- OpenAI-compatible chat completions endpoint
- Configurable: API Base URL, API Key, Model
- Stored in UserDefaults (API Key in UserDefaults for simplicity)

### System Prompt

```
You are a speech-recognition post-processor. Your ONLY job is to fix obvious transcription errors. Rules:
1. Fix Chinese homophone errors (e.g. wrong tones/characters from speech recognition)
2. Fix English technical terms that were incorrectly transcribed as Chinese (e.g. "配森"→"Python", "杰森"→"JSON", "瑞科特"→"React")
3. Fix obvious English word boundary errors
4. DO NOT rewrite, rephrase, polish, or restructure any text
5. DO NOT add or remove punctuation beyond what's needed for fixes
6. DO NOT change any text that appears correct
7. If the entire input appears correct, return it exactly as-is
8. Return ONLY the corrected text, no explanations
```

### Settings Window

- Standard NSWindow with 3 text fields: API Base URL, API Key (secure-ish), Model
- Test button: sends a test request to verify config
- Save button: persists to UserDefaults

## Menu Bar

- SF Symbol icon: `mic.fill` (normal), `mic.badge.waveform` (recording)
- Menu items:
  - Language submenu (radio selection): English, 简体中文 (default), 繁體中文, 日本語, 한국어
  - Separator
  - LLM Refinement submenu:
    - Enable/Disable toggle
    - Settings...
  - Separator
  - Quit VoiceClaude

## Build System

- Swift Package Manager with `Package.swift` (macOS 14+, executable target)
- Makefile targets: `build`, `run`, `install`, `clean`
- Build output: `VoiceClaude.app` bundle in `build/`
- Code signing with `-` (ad-hoc)
- Info.plist with LSUIElement=true

## Permissions

- **Accessibility:** Required for CGEvent tap. Auto-prompt on launch via `AXIsProcessTrustedWithOptions(prompt: true)`. Show alert with instructions if denied.
- **Microphone:** Requested on first recording via AVAudioSession. Standard system prompt.
- **Speech Recognition:** Requested on first use via SFSpeechRecognizer.requestAuthorization.
