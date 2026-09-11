# The Page-Flip Runner — Production Asset Spec

The dynamic 2D vector loader: an ice-white runner striding across an open
isometric book whose pages flip on bent arc paths. Progress-driven
acceleration, a finish-line jump with particle dissolve, sky/ocean-blue
accents, pure transparent canvas.

**Three synchronized artifacts (keep in sync):**

| Artifact | Path | Role |
|---|---|---|
| Motion prototype | `tools/page_flip_runner_proto.py` | executable math source of truth |
| Preview loop | `docs/assets/page_flip_runner.gif` | rendered QC reference (progress 0→92 + finish) |
| Flutter component | `lib/presentation/components/page_flip_loader.dart` | production drop-in (`PageFlipLoader`) |

This document is the authoring spec for the native **Rive** build.

---

## 1. Artboard & palette

- Artboard: **480 × 480**, transparent background (no backdrop shapes).
- Runner anchor X = 240; foot/deck line Y = 292 (book deck centre);
  book iso origin Y = 296 − 26.
- Palette (hard contract):
  - Runner silhouette `#FFFFFF` (ice white); back limbs `#D4E3F4` @ 92%
  - Speed trails / page edges `#87CEEB` (sky blue)
  - Kinetic sparks / burst `#0077BE` (ocean blue), white-hot cores `#FFFFFF`
  - Paper `#EEF4FC`; covers `#1A2542` / `#212F52`; spine glow `#87CEEB` @ 27%

## 2. Bone hierarchy (vector rig)

```
root
└─ hipMaster            (x=240, y=276 · bob + air translate here)
   ├─ hip               (body root; LEAN rotates here, origin=hip)
   │  ├─ spine → chest
   │  │  ├─ neck → head
   │  │  │  └─ hair_1 → hair_2 → hair_3 → hair_4   (IK chain, free end)
   │  │  ├─ scarf_A_1 → … → scarf_A_5             (IK chain, free end)
   │  │  ├─ scarf_B_1 → … → scarf_B_5             (IK chain, free end)
   │  │  ├─ armF: shoulderF → elbowF → handF      (IK, 2-bone)
   │  │  └─ armB: shoulderB → elbowB → handB      (IK, 2-bone)
   │  ├─ legF: thighF → shinF → footF             (IK, 2-bone)
   │  └─ legB: thighB → shinB → footB             (IK, 2-bone)
   └─ book
      ├─ coverL / coverR / deckL / deckR / stackL / stackR   (static art)
      ├─ pageFlipA → pageA_arc (bone chain, 4 segments)
      ├─ pageFlipB → pageB_arc
      └─ pageFlipC → pageC_arc
```

- Limbs are **IK chains with bent knees/elbows** (never straight sticks):
  joints sit at 0.62×/0.92× stride offsets, knee lift 24–39 px.
- Torso is a tapered quad (shoulder width 21 px → hip width 13 px),
  weighted to `chest`. Head r = 13 px. Round caps/strokes everywhere.
- Secondary motion: hair + scarves are trailing IK chains; their sway
  amplitude = `2 + 6·speed01` px and phase-lead against the stride.

## 3. Animation phases & keyframe math

Timeline-driven values (implement as keyframed curves, NOT linear):

| Driver | 0–30% (jog) | 31–89% (sprint) |
|---|---|---|
| Stride frequency | 2.0 → 2.6 Hz (linear) | 2.6 → 5.2 Hz, **cubic-in** `bezier(0.55, 0, 1, 0.45)` |
| Lean (hip rotation) | 5° → 8° | 8° → 23°, cubic-in, same bezier |
| Page-flip rate | 1× (3 pages phased 0 / .33 / .66) | **2×** (flip cycle time halved) |
| Speed trail length | 15% → 30% of 130 px | 30% → 95%, cubic-in |
| Stride amplitude | 27 px | 27 → 44 px |
| Knee lift | 24 px | 24 → 39 px |

- Stride bounce: `-6·|sin(phase·2π)|` px on `hipMaster`, one key pair per
  stride, **custom ease `bezier(0.3, 0, 0.4, 1)`** into every contact pose.
- Foot contact fires: (a) page deck flex — `deckL/R` +1.5 px dip with
  `bezier(0.2, 0.8, 0.2, 1)` recovery; (b) **kinetic sparks** — 5 ocean-blue
  circles, 26° fan, 20–38 px/s, gravity 26 px/s², fade 100 ms, white core on
  every 2nd particle.
- Page flip arc (each page): the tip travels a **dome path** — height
  `96·(0.55 + 0.45·cos t)` px over the spine, lateral squeeze
  `0.82 + 0.18·cos(phase·π)`; rotate page bones along 4 arc segments and
  key the edge-stroke opacity 88% → 62%. Pages NEVER rotate flat.

## 4. State machine

**Inputs:**
- `progress` — Number, 0.0–100.0 (app binding)
- `isComplete` — Trigger

**States:**
1. **Jog** (0–30): base loop, 60 fps, stride 2.0–2.6 Hz. Blend-in
   instantaneous on load.
2. **Sprint** (31–89): same loop art, `progress` maps the frequency/lean/
   trail table above. Transition Jog→Sprint is a 250 ms blend with
   `bezier(0.45, 0, 0.55, 1)`; the sprint timeline re-times itself from the
   `progress` input (bind frequency via listener or timeline scaling).
3. **Finish** (trigger `isComplete`, fires from any state, interrupts
   immediately): 1.27 s (38 frames @30 fps):
   - 0–8%: final contact pose freezes into takeoff crouch
     (`bezier(0.6, 0, 0.4, 1)`)
   - 8–60%: parabolic launch, apex 84 px at 42%; **mid-air tuck** peaks at
     42% — knees fold (stride amplitude → 6 px), chest → knees 26 px,
     lean relaxes ×0.4
   - 40–100%: **dissolve** — 130 ocean/sky particles (3:1 ratio), golden-
     angle spread with ±0.5 rad jitter, per-particle random delay ≤30%,
     speeds 34–152 px/s, radial streak tails (last 14% of flight), gravity
     96 px/s², sizes 2.1–5.2 px shrinking 70%, flash ring (ocean, 4 px)
     expands 14→86 px in the first 32%; white-hot cores on 20% of particles
   - Runner art hidden at 42%; the loop never resumes after the trigger.
4. **(loop guard)** Finish exits nowhere — it holds the final empty-book
   frame and emits `onCompleted` at t=100%.

## 5. Export & integration

1. Rig per §2, key per §3, wire the state machine per §4.
2. Bind `progress` to the app's load fraction; nothing else is required —
   the Jog↔Sprint blend and re-timing are driven inside the state machine.
3. Export `.riv` (state machine enabled). Reasonable budget: < 90 KB.
4. Flutter drop-in today (until the `.riv` replaces it — both expose the
   identical contract):

```dart
PageFlipLoader(
  progress: uploadPercent,      // 0–100
  isComplete: finished,         // fires the jump + dissolve once
  onCompleted: () => context.push('/home'),
  size: 240,
)
```

The Rive runtime equivalent: `RiveAnimation.controller` with
`SMINumber progress` + `SMITrigger isComplete`.
