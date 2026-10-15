# Full-controller layout review

Status: still-image planning only. No new audio or video has been rendered.

The whole controller is displayed at **1792 × 784** on a 1920 × 1080 canvas, fixed at **x64, y165**. The title and action label remain outside the photograph. Every controller cue uses exactly the same crop, scale and position: only the target outline and action label change. The crop removes only the old top/bottom title bands and retains the complete controller.

## Review examples

- `stills/full-panel-entry-pair-bright.jpg`
- `stills/full-panel-entry-pair-dim.jpg`

The entry example identifies **Entrance Gate + Teat Cleaning together**, with the immediate-arm-movement warning. Bright and dim are still examples of the desired flashing effect, not a rendered animation.

## Important source limitation

The available source is a generated photo-derived graphic. Its two cyan entry-button outlines are baked into the pixels. Those two controls are both required for the entry example, so it is valid for reviewing this composition. When identifying another single control, those inactive cyan outlines would conflict with the requested “only the required buttons” treatment.

The final single-button frames therefore require the clean original controller photograph. No source hardware has been painted out, hidden, recreated or relabelled. No lamp state or pressed-button state has been altered. **This review is not a claim that a clean original photograph is available.**

## Preserved plan

`full-panel-shot-manifest.json` retains all 43 narration cue keys. Every controller cue uses this full-panel transform and its exact existing target coordinates. Individual-control stills have not been generated from the unsuitable source. Non-controller reference cues are retained; no screen/equipment illustration is claimed to be a genuine site photograph.

Action distinctions remain: **TAP ONCE**, **PRESS AND HOLD**, **PRESS TOGETHER**. Highlights identify a control; they do not simulate a button press or change an indicator.

Rebuild the review stills with:

```sh
python /workspace/vms300-video/farmer-full-panel-review/build_full_panel_review.py
```

Before applying the plan to a newly supplied clean photograph, fit the button rectangles to that exact photo and verify each target. The current preview coordinates must not be reused blindly on a different image. The queued20%-faster narration remains prepared for the next edition; this still review does not render that edition.
