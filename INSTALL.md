# INSTALLATION — READ FIRST

## The crash ("Cannot hit test a render box that has never been laid out")

This crash is caused by files from the original `timetable_ui_redesign_pack.zip`.
Those files contain broken widgets. This zip REPLACES them all.

## How to apply

1. Copy the entire `lib/` folder from this zip into your project:
   `D:\Projects\timetable_app\lib\`  ← replace everything here

2. Do NOT copy any files from `timetable_ui_redesign_pack.zip` back in.
   Specifically these 6 files in that pack are broken and must NOT be used:
   - `widgets/glass_card.dart`        ← has BackdropFilter + AnimatedContainer
   - `widgets/hover_glass_card.dart`  ← has AnimatedContainer + Matrix4
   - `widgets/slide_fade_in.dart`     ← has SlideTransition + AnimationController
   - `widgets/glow_action_button.dart`← has AnimationController + .repeat()
   - `widgets/sliding_glass_panel.dart`← has AnimatedContainer width animation
   - `utils/app_theme.dart`           ← has BoxDecoration gradient TabBar indicator

3. Run: `flutter clean && flutter pub get && flutter run`

## Why these crash on Windows

Flutter's Windows renderer marks semantics parent-data dirty whenever a
compositing layer is forced (BackdropFilter, gradient BoxDecoration on TabBar
indicator, AnimationController.repeat() rebuilding 60x/sec). This causes
`!semantics.parentDataDirty` assertion failures which prevent layout from
completing, causing the "never been laid out" hit-test crash in a loop.
