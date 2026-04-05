# Style Picker Relocation Design

## Goal

Remove the style picker from the input bar. Apply style automatically based on the frontmost app. Move the picker to the action bar so users can override the style after seeing the result.

## Background

The input bar currently shows a persistent `Picker` (88px wide, menu style) displaying the active template name. This takes up space in the primary input area and implies the user should choose a style before submitting — but since the app already auto-selects a style based on the frontmost app (`ContextCapture.suggestedTemplateID`), this picker is noise 90% of the time. Users only need it when the auto-selected style produced a result they don't like.

## Design

### Input bar

Remove `stylePicker` entirely from `inputBar`. No visual indicator of the current template is shown here. The auto-selection happens silently on window open (existing behavior, no change needed).

### Action bar

Add `stylePicker` to `actionBar`, placed between the "修改意见" button and the lock icon. This bar is only visible when a result is showing (`showResult == true`), which is exactly when style adjustment is relevant.

Layout order in `actionBar`:
```
修改意见  |  [style picker]  Spacer  🔒  重新生成  接受并复制
```

The picker keeps its current appearance: `.pickerStyle(.menu)`, `.frame(width: 88)`, `.labelsHidden()`.

### Auto-selection behavior

No change. On `show(context:)`, `suggestedTemplateID` is applied if available; otherwise `builtins[0]` is used. This already works.

### No fallback in input bar

No "auto" label, no indicator. The input bar is for input only. Users who want a specific style wait until the result appears and adjust from there.

## Files Changed

- Modify: `Sources/Murmur/Confirm/ConfirmWindow.swift`
  - Remove `stylePicker` from `inputBar` (line ~92)
  - Add `stylePicker` to `actionBar` after "修改意见" button (line ~250)

## Out of Scope

- Persisting the user's manual override across sessions
- Showing which style is currently active in the input bar
- Any change to `ContextCapture` or template matching logic
