# Quantivita Design System

This document is the decision source for Quantivita product UI. The goal is one visual language across the iPhone app and the homeserver dashboard: clinical enough to be trusted, warm enough to feel personal, and dense enough for real health data.

## Product Feel

Quantivita is a private health command center. Screens should feel like a polished operating surface, not a marketing page. The interface presents recovery, sleep, cardio, activity, workouts, integrations, and exports as connected signals.

Use:

- Soft medical-tech surfaces, subtle glass, rounded cards, precise borders.
- Calm light mode with cool grey background and lime recovery accent.
- Dark mode with near-black depth, high-contrast text, and the same accent system.
- Compact cards with clear hierarchy: label, value, unit, short interpretation.
- Charts and rings as first-class UI, not decorative filler.

Avoid:

- Huge generic hero typography inside operational screens.
- Purple/orange-heavy gradients as the main identity.
- Nested cards inside cards.
- Long unrounded decimals.
- Status copy that exposes implementation details such as raw tokens.

## Core Tokens

The web dashboard and mobile app should map to these colors.

| Role | Light | Dark | Usage |
| --- | --- | --- | --- |
| Background | `#EEF3F6` | `#07090D` | App and page background |
| Surface | `#FFFFFF` | `#11161C` | Primary cards and panels |
| Raised surface | `#F5F8FA` | `#171D24` | Chips, tiles, inputs |
| Ink | `#0E1621` | `#F1F5F7` | Main text |
| Body | `#33404C` | `#C9D2DA` | Paragraph text |
| Muted | `#697784` | `#A0ACB8` | Labels and metadata |
| Outline | `#DBE4EA` | `#26313B` | Borders and dividers |
| Recovery | `#91D957` | `#B5F267` | Readiness, synced, positive |
| Sleep | `#49B7C9` | `#61D2E2` | Sleep and circadian signals |
| Activity | `#F06989` | `#FF7A9B` | Heart-rate and load emphasis |
| Strain | `#F0A43A` | `#FFC261` | Training load points and effort |
| Stress | `#A794FF` | `#B8AAFF` | Nervous-system context |

## Layout Rules

- Mobile screens use 18 px outer padding and 14-18 px vertical rhythm.
- Primary panels use 24 px radius. Small pills and inputs use 14-999 px radius.
- Operational cards should usually be 1 screen-width column on mobile.
- The first mobile viewport should show the app identity, recovery command panel, and at least one signal tile.
- Homescreen and overview metric cards always describe one synced day. Historical totals belong in trend/detail screens only.
- Bottom navigation remains the main mobile route switcher.
- Settings and integrations belong in personalization/settings, not on the fitness selection flow.

## Components

### Command Panel

Use for the main readiness or overview surface. It combines:

- Eyebrow label.
- Short title.
- One concise interpretation.
- Score ring or gauge.
- Two to four signal tiles.

### Stat Card

Use for repeat metrics. Structure:

- Icon tile.
- Uppercase label.
- Large value with rounded number.
- Short caption or delta.

### Integration Status

Use words consistently:

- Strava: `Connected` or `Not connected`.
- Quantivita API: `Synced`, `In sync`, or `Not synced`.
- Never show sync token as a normal user-facing login requirement.

## Typography

Use SF Pro on iOS and system UI elsewhere. Letter spacing stays at 0 or slightly positive for labels. Operational titles are compact and strong; large display text is reserved for command panels only.

## Number Formatting

- Recovery and sleep quality: whole percentage or score.
- Body Battery: whole `0-100` reserve score, charged by sleep/recovery and drained by stress, movement, and training through the day.
- Strain: whole `0-100%` daily load circle, never kcal. Internal scoring may use a nonlinear load model, but user-facing UI always displays percent.
- HRV: 0-1 decimals max, unit `ms`.
- Resting heart rate: whole number, unit `bpm`.
- Sleep: `7h 20m`.
- Distance: one decimal km over 1000 m.
- Energy: whole kcal.

## Implementation Contract

- Color values live in `lib/theme/quantivita_colors.dart` and `server/public/styles.css`.
- Score thresholds and labels live in `lib/config/health_score_policy.dart`.
- When adding a new score, define the thresholds in policy first, then consume the policy from models/controllers.
- If a visual decision is unclear, prefer the dashboard command-center style over older card-only screens.

## Research Model Contract

Quantivita follows a hybrid Garmin/WHOOP-inspired architecture:

- Recovery is a morning readiness score. It should be confidence-aware and based on personal baselines for HRV, RHR, sleep, strain, respiratory rate, and temperature deviation.
- Body Battery is an intraday reserve estimate. It is charged by recovery and sleep, drained by activity, steps, strain, and stress, and shown with a transparent factor breakdown.
- Strain is a separate daily load signal. The internal model may use nonlinear load, but the user-facing score is always `0-100%`.
- Sleep is evaluated against dynamic sleep need, not just duration. Sleep need starts from a baseline and increases with strain and sleep debt.
- Stress should be interpreted conservatively. During meaningful activity, stress-like physiology should be treated as activity/load context rather than pure mental stress.
- Every score that uses fallbacks or incomplete sensor data should expose confidence in the UI or detail sheet.
