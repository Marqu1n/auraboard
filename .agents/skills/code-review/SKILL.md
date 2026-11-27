---
name: code-review
description: >-
  Structured review checklist used by the independent read-only reviewer
  subagent at the end of every build phase.
---

# Independent Code Review Checklist

The `reviewer` subagent (read-only, never the author of the code under review) must verify every item below before issuing `VERDICT: APPROVE`:

## 1. TDD & Test Quality
- Git history shows Red (failing test) -> Green (implementation) progression.
- No tests use `skip: true`, weakened assertions, or wall-clock `Future.delayed` flakiness.
- Playback state machine and fade/crossfade timing are verified deterministically via fake engine + fake clock.

## 2. Correctness & Domain Semantics
- **Effect**: one-shot, minimal latency, overlaps freely, per-pad retrigger (`restart` vs `layer`).
- **Music**: loops gaplessly by default, single active music track, switching crossfades old -> new, stopping fades out.
- **Ambience**: loops gaplessly, multiple layer concurrently, fades in on start and fades out on stop.
- **Stop All**: fades everything out smoothly (no hard cut), always reachable.
- **Interrupted transitions**: tapping a pad while fading in/out, or starting Music C while A->B is crossfading, transitions cleanly without stuck states or leaked audio handles.

## 3. Mid-Session UX, Material 3 & Accessibility
- Playing, looping, fading-in, fading-out, and error states are distinguishable without color alone (icons, badges, progress rings/bars, motion/labels).
- Explicit Edit Mode protects Play Mode from accidental drag, rename, or delete.
- All interactive targets >= 48dp; semantic labels present; survives `2.0x` text scale factor; responsive on phone/tablet and portrait/landscape.

## 4. Offline, Privacy & Resilience
- `android/app/src/main/AndroidManifest.xml` has NO `INTERNET` permission.
- No remote fonts, remote assets, accounts, analytics, or ads.
- Imported files copied into app-private storage; corrupt/missing files surface clear pad error state without crashing.
- Atomic persistence; backup archive round-trips folders, pads, settings, and audio bytes.
- Background playback, audio focus (notifications don't kill music; calls pause & resume), wakelock option, and no auto-resume after kill.
