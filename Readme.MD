# C6g3 Transformers

Live editing tools for the **BeamNG.drive Vehicle Editor**. They let you place, rotate, scale and tune parts of a vehicle in 3D while the vehicle is spawned, then copy the result back into your JBeam. You don't need to reload the vehicle to see a change.

| Tool | Edits | Needs |
|---|---|---|
| **Speaker Transformer** | `c6g3SoundSystem_Speakers` (position, rotation, radius, cone, gain, filters, resonance, distortion, stereo channel) | `c6g3SoundSystem` extension |
| **Live EQ** | `c6g3SoundSystem_EQs` (preamp and per-band gain) | `c6g3SoundSystem` extension |
| **Prop Trigger Transformer** | `propTriggers` (shape, position, rotation, size) | `propTriggers` extension |

---

## Installation

1. Download **`c6g3Transformers.zip`** from the [Releases](https://github.com/C6G3/BNG-C6g3Transformers/releases) page.
2. Drag the zip, **unextracted**, into your BeamNG user mods folder:
   ```
   %LOCALAPPDATA%\BeamNG\BeamNG.drive\current\mods\
   ```
   *(Paste that path into the File Explorer address bar to jump straight there.)*
3. Start (or restart) BeamNG.drive and check that **c6g3Transformers** is enabled in the Mod Manager.
4. Spawn a vehicle that uses the system you want to edit (see the requirements table above).

To uninstall, delete the zip or disable it in the Mod Manager.

> **Zip only.** BeamNG only loads `.zip` mods, so a `.rar` or `.7z` placed in `mods\` is ignored.

<details>
<summary>Building the release zip from this repo</summary>

Zip the **contents** of the `c6g3Transformers` folder, not the folder itself, so the zip root looks like this:

```
c6g3Transformers.zip
├── lua/ge/extensions/editor/vehicleEditor/liveEditor/
│   ├── veSpeakerTransformer.lua
│   ├── veLiveEQ.lua
│   └── vePropTriggerTransformer.lua
├── lua/ge/extensions/core/input/actions/c6g3Transformers.json
└── settings/inputmaps/keyboard_c6g3Transformers.json
```
</details>

## Opening the tools

1. Open the World Editor (**F11**).
2. Go to **Window → Vehicles → Vehicle Editor**.
3. In the Vehicle Editor, switch to the **Live Editor** tab and open the **Apps** menu.
4. Pick **Speaker Transformer**, **Live EQ** or **Prop Trigger Transformer**. Each one opens in its own dockable window.

While the Speaker Transformer or Prop Trigger Transformer window is open, the vehicle itself is made **unselectable** in the World Editor. Clicks in the viewport then pick speakers or triggers instead of selecting the whole car. The previous setting comes back when you close the window.

## Keyboard shortcuts

While a speaker or prop trigger is **picked** in its transformer window, these keys control that object's gizmo instead of the World Editor's own gizmo:

| Key | Speaker Transformer | Prop Trigger Transformer |
|---|---|---|
| **1** | Toggle **Move** gizmo | Toggle **Move** gizmo |
| **2** | Toggle **Rotate** gizmo | Toggle **Rotate** gizmo |
| **3** | Toggle **Radius** (scale) gizmo | Toggle **Scale** gizmo |

Press the same key again to turn the gizmo off. The keys are ignored while you're typing in a text field. When nothing is picked, or the window is closed, 1/2/3 go back to the World Editor's normal translate/rotate/scale.

To rebind them, go to **Options → Controls → Bindings → Editor** and look for the actions starting with *Speaker Transformer:* and *Prop Trigger Transformer:*.

> **Edits are live but not saved.** Every change is applied to the running vehicle right away. To keep it, use the **Copy** / **Master Copy** buttons and paste the values into your `.jbeam`. Reloading the vehicle (Ctrl+R) resets everything to what's in the JBeam.

---

## 1. Speaker Transformer

Use it to position and voice the 3D speakers of a `c6g3SoundSystem` vehicle while you listen to them.

### Picking a speaker

1. Click **Pick Speaker** (it changes to **Picking...**).
2. Hover over the vehicle. Every speaker is drawn as a small green dot, and the one under the cursor is highlighted orange with a label showing its name and mode.
3. If several speakers overlap along the ray, **scroll the mouse wheel** to cycle between them.
4. **Left-click** to select it.

The selected speaker is drawn with:
- a translucent **sphere** showing its radius,
- a **green ring** for the inner cone angle and an **orange ring** for the outer cone angle,
- a **cyan line** pointing in the firing direction,
- red/green/blue local **axis lines**,
- a label showing its name, gain and mode.

### Two placement modes (detected automatically)

| Mode | When | Frame the speaker is relative to |
|---|---|---|
| **Standard 3-Node** | speaker has `idRef`, `idX`, `idY` and no `targetProp` | a frame built from the three nodes: `idRef` is the origin, `idX` sets X, `idY` sets the plane |
| **Prop-Attached** | speaker has `targetProp` | the live world transform of that prop (follows animated props such as doors) |

`baseTranslation` (metres) and `baseRotation` (degrees, X→Y→Z) are applied in that local frame.

### Toolbar

- **Master Copy JSON**: copies a complete, clean JBeam entry for the selected speaker to the clipboard, ready to paste into `c6g3SoundSystem_Speakers`.
- **Gizmo: ... / Clear**: shows which 3D gizmo is active and turns it off.

### Sections

**Movement (Local)**: X/Y/Z inputs for `baseTranslation`.
- `-` / `+` buttons nudge one axis by the step value shown between them (you can type a different step).
- **Move** turns on the 3D translate gizmo. Drag it in the viewport.
- **Copy** copies `"x":…, "y":…, "z":…` to the clipboard.
- **Reset** restores the value the vehicle was spawned with.

**Rotation (Local)**: works the same way for `baseRotation` in degrees, with a **Rotate** gizmo. Angles wrap to 0–360.

**Dimensions & Acoustic Frustum**
- **Radius (m)**: driver size. It also sets the default crossover (a smaller driver means a higher crossover). The **Scale** gizmo changes it too.
- **Inner / Outer Cone Angle**: full-level and fade-out zones of the speaker's directivity. Watch the green and orange rings update as you drag.

**Audio Gain & Filter Tuning**
- **Stereo Channel**: route the speaker to **Left**, **Center (L+R)**, **Right** or **Subwoofer (LFE)**.
- **Gain (dB)**: speaker output level.
- **Outer Gain (dB)**: level outside the outer cone.
- **Low / High Cutoff (Hz)** and **Low / High Slope (dB/oct)**: the speaker's own band-pass.
- **Crossover (Hz)**: split between the directional (mid/high) and omni (bass) radiation paths.

**Resonance Tuning**: one peaking EQ band for the driver's natural resonance: **Peak Freq**, **Peak Gain**, **Peak Q**.

**Overdrive & Distortion**
- **Dist Threshold (dB)**: level above which the driver starts to saturate. 0 dB or higher means no distortion.
- **Distortion Factor**: how hard it saturates. 0 is a clean bypass.
- Distortion is applied at the driver stage, so it reacts to the amp signal (master volume and EQ). Lower the threshold or turn up the volume to hear it.

> **Tip:** every slider has a small box to its right with the slider's **maximum**. Type a bigger number if you need more range, for example more than +30 dB of gain.

### Speaker JBeam reference

```jsonc
"c6g3SoundSystem_Speakers": {
    "front_left_speaker": {
        "name": "front_left_speaker",
        "idRef": "d19l", "idX": "d18l", "idY": "d16l",   // or "targetProp": "door_FL"
        "radius": 0.080,
        "baseRotation": [87.5, -2.4, -29.5],
        "baseTranslation": [0.272, -0.106, 0.424],
        "coneInnerAngle": 70.7,
        "coneOuterAngle": 179.5,
        "coneOuterGaindB": -14.1,
        "lowFreqCutoff": 60,  "highFreqCutoff": 10000,
        "lowSlope": 18,       "highSlope": 12,
        "crossoverHz": 350,
        "peakFreq": 210, "peakGain": 2.5, "peakQ": 1.4,
        "distThresholddB": -2.5,
        "distFactor": 0.0,
        "channel": "left",
        "gaindB": 0.0
    }
}
```

---

## 2. Live EQ

A mixing desk for every `c6g3SoundSystem_EQs` block on the current vehicle. Values are read from the sound system every frame, so the window always shows the current state.

### Using it

1. Open **Live EQ** with the World Editor active and a sound-system vehicle spawned.
2. Each EQ block shows its **index**, **name**, the **channels** it applies to and its **gain range**.
3. **Preamp**: overall gain for that block. A block with no frequencies works as a plain amplifier, for example a subwoofer amp.
4. **Band sliders**: one per frequency, labelled with its Hz and Q. Drag to boost or cut, and you hear the result immediately.
5. **Reload JBeam EQs**: throws away the live tweaks and re-reads the EQs from the vehicle data.

The slider limits come from each block's `minGain` / `maxGain`. To keep a setting, copy the numbers into `gains` / `preamp` in your JBeam.

If the window says *"No c6g3SoundSystem_EQs found"*, add a section like the one below and reload the vehicle with **Ctrl+Shift+R**.

### EQ JBeam reference

```jsonc
"c6g3SoundSystem_EQs": {
    "speakers_eq": {
        "name": "speakers_eq",
        "preamp": -3.0,                              // dB
        "channels": ["left", "right", "center"],     // or "all" / omit for every speaker
        "frequencies": [60, 350, 1000, 4000, 10000], // Hz, one peaking band each
        "gains": [-1.9, -1.8, 0.6, 2.6, 2.1],        // dB, one per frequency
        "Q": [1.4, 1.4, 1.0, 1.0, 0.7],              // per band, or a single number for all
        "minGain": -15.0,
        "maxGain": 15.0,
        "smoothingTime": 0.05
    },
    "subwoofer_amp": {
        "name": "subwoofer_amp",
        "preamp": 6.0,
        "channels": ["subwoofer"],
        "frequencies": [],                           // empty = amplifier only
        "minGain": -10.0,
        "maxGain": 24.0
    }
}
```

---

## 3. Prop Trigger Transformer

Use it to place, rotate and resize the clickable `propTriggers` zones on a vehicle (buttons, switches, handles) and see their hit volume in 3D.

### Picking a trigger

1. Click **Pick Prop Trigger** (it changes to **Picking...**).
2. Hover over the vehicle. Triggers are highlighted under the cursor and labelled with `trigger: <id> | type: <shape>`.
3. **Scroll the mouse wheel** to cycle through overlapping triggers, then **left-click** to select one.

The selected trigger's volume is drawn in the viewport: a wireframe box for `box`/`mesh`, or a sphere for `sphere`.

Like speakers, a trigger is positioned either relative to a **3-node frame** (`idRef`, `idX`, `idY`) or to a **`targetProp`** (follows the prop's live transform).

### Sections

- **Master Copy**: copies the selected trigger as a ready-to-paste JBeam **table row** in the right column order for its mode:
  - prop-attached: `["id", "targetProp", "type", size, "action", baseTranslation, baseRotation, ""]`
  - node-based: `["id", "idRef", "idX", "idY", "type", size, baseRotation, "", "", baseTranslation, "action"]`
- **Shape**: switch between **Box**, **Sphere** and **Mesh**. The size is converted for you (box to sphere uses the largest axis, sphere to box uses a cube).
- **Movement (Local)**: `baseTranslation` X/Y/Z with step `-`/`+`, a **Gizmo** (translate), **Copy** and **Reset**.
- **Rotation (Local)**: `baseRotation` in degrees with the same controls. Press **Enter** to commit a typed value.
- **Offsets (from initial load)**: how far the trigger has moved and rotated since the vehicle spawned, with **Copy** buttons. This is handy if your JBeam stores offsets rather than absolute values.
- **Scale**: X/Y/Z size for box and mesh, or **Radius** for sphere (the sphere is drawn using `size` as a diameter, matching how `propTriggers` treats it). Each has a **Gizmo** (scale).

Every change re-applies the triggers on the live vehicle, so you can test the new hit zone right away by clicking it in game.

---

## Typical workflow

1. Spawn the vehicle, open the World Editor and the Vehicle Editor.
2. Open the tool you need and **pick** the speaker or trigger.
3. Rough it into place with the **gizmo**, then fine-tune with the numeric fields and step buttons.
4. For speakers, play music and tune gain, filters, cone and distortion **by ear** in real time. Use **Live EQ** for the overall tone.
5. Click **Master Copy** and paste the result over the old entry in your `.jbeam`.
6. Reload the vehicle (Ctrl+R) to confirm the saved values match what you tuned.

## Troubleshooting

| Symptom | Fix |
|---|---|
| Window says *"No c6g3SoundSystem speakers found"* | The vehicle has no `c6g3SoundSystem_Speakers` section, or the vehicle data was cached before you added it. Reload the vehicle. |
| *"c6g3SoundSystem extension not loaded"* (Live EQ) | The sound-system mod isn't installed or active for this vehicle. |
| Clicking in the viewport selects the whole car | Make sure the transformer window is open: the vehicle only becomes unselectable while it is. |
| Changes vanished after a reload | Expected: edits live in memory only. Paste the **Master Copy** output into your JBeam. |
| Distortion makes no audible difference | Lower **Dist Threshold** (for example to -12 dB) or raise the master volume. Nothing distorts unless the signal goes above the threshold. |

## Credits

- Author: **C6G3** (Wamburu G.)

## License

[MIT](LICENSE)
