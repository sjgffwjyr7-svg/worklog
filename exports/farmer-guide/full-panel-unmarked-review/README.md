# Full-controller still review — added cyan annotations removed

These are **still layout examples only**, with no new narration or video. The whole controller stays at **1792 × 784**, fixed at **x64, y165**, on every panel cue. The crop removes only the old top/bottom caption bands. All controller groups remain visible at the same size and position; only the required target outline and instruction banner change.

## Review stills

- `stills/full-panel-single-confirm-bright.jpg`
- `stills/full-panel-single-confirm-dim.jpg`
- `stills/full-panel-entry-pair-bright.jpg`
- `stills/full-panel-entry-pair-dim.jpg`

The single-Confirm example highlights only the lower-left **Teat Cleaning / Confirm** control, with **TAP ONCE**. The entry example highlights both **Entrance Gate + Teat Cleaning**, with **PRESS TOGETHER** and the immediate-arm-movement warning. Bright/dim are still examples of the flash effect. No animation has been rendered. **PRESS AND HOLD** remains a steady outline in the preserved cue plan; no numerical hold duration is invented.

## Source and exact edit scope

The source is a **retouched photo-derived reference**, not a recovered original photograph. The prior generated reference had two cyan annotation outlines baked into it. An image-editing tool supplied replacement annotation pixels, which were composited **only inside a reviewed cyan-stroke mask** onto the existing native reference. The validated native PNG has **7,493 changed pixels**, all inside that mask, and **zero changed pixels outside it**. Protected button faces, printed symbols, switches, lamps, emergency stop and all other control groups are pixel-identical to the pre-retouch native reference. The validation found **zero cyan core pixels remaining**.

The exact pixel-identity guarantee applies to the **native 1672 × 941 PNG before resizing**. Mechanical resizing and JPEG output naturally resample/compress pixels. This composition keeps the validated source control appearance; it does not claim lamp illumination, a selected mode, a pressed button, successful calibration or an untouched original photograph.

Source validation: `restoration-validation.json`.

`full-panel-shot-manifest.json` preserves all **43 narration cue keys**, including **24 full-panel controller cues**. Other screen/equipment reference cues remain labelled honestly. Actual alignment, sponge-contact and both horn/tube-position footage gaps remain; the still examples do not fill them.

Rebuild only these four stills:

```sh
python /workspace/vms300-video/farmer-full-panel-unmarked-review/build_full_panel_review.py
```

The unmarked working reference is also supplied as `Controller_Working_Reference_Unmarked_1600x900.png`. [Download the controller-only JPEG](VMS300_Full_Controller_Unmarked_Reference.jpg?raw=1). Both are retouched reference derivatives; neither is labelled as the recovered original photo. The queued20%-faster narration remains ready; the existing MP4 is unchanged until the final-render request.
