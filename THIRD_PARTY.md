# MoMo Display — third-party notices

MoMo Display is provided under GPL-3.0-only. See LICENSE and Licenses/.

## MonitorControl

- Source: https://github.com/MonitorControl/MonitorControl
- Commit: `7cfe64500d19cbbcbf82121a91c826f658a403bd`
- License: MIT, retained in `Licenses/MonitorControl-MIT.txt`.
- Copyright © MonitorControl. @JoniVR, @theOneyouseek, @waydabber and others.
- Adapted files: `Sources/Arm64DDC.swift`, `Sources/Bridging-Header.h`.
- Changes: brightness-only integration, stricter unique display matching, validated DDC reply, IORegistry resource release, application wrapper.

## BrightIntosh

- Source: https://github.com/niklasr22/BrightIntosh
- Commit: `f6806b893926d3ed47424396d9f45575713b8709`
- License: GNU GPL version 3, retained in `Licenses/BrightIntosh-GPL-3.0.txt`.
- Copyright Niklas Rousset and BrightIntosh contributors.
- `Sources/DisplayEffects.swift` adapts the EDR Metal trigger and gamma technique from `GammaTechnique.swift`, `UI/Overlay.swift` and `OverlayWindow.swift`.
- Changes: independent per-display state, conservative 1.6× maximum, internal-display-only boost, capability/EDR/readback gating, explicit opt-in, bounded activation, original per-display gamma restoration, software-dimming fallback.

This is an independent project, not an official version of BetterDisplay, MonitorControl or BrightIntosh. No BetterDisplay or Lunar proprietary code is included. Sources fetched and modified 2026-11-02.
