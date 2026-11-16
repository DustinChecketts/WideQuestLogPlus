# Changelog

## 1.2.1 — WoW Forever quest log refinements

### Improved
- Refined Forever's independent quest-details pane using Blizzard's native parchment and Rewards artwork.
- Improved quest-description scrolling behind the Rewards section and kept bottom action buttons visible.
- Matched native reward presentation more closely, including item quality borders, reward spacing, and XP/money typography.
- Matched Blizzard's red usability tint for rewards the character cannot currently equip.
- Refined quest-title icon alignment and preserved quest level and ID display.
- Added shared in-game options, including the option to keep the full Rewards section visible.

### Compatibility
- Preserved native quest-log presentation on Classic Era and Classic Anniversary TBC.
- Removed experimental vignette diagnostics from the release candidate.

### Verification
- Forever visual and reward-usability behavior verified in user-provided in-game comparisons.
- Classic Era and Anniversary regression testing and automated release checks should be confirmed before publishing.

## 1.2.0 — WoW Forever support

### Added
- Initial WoW Forever compatibility with a two-pane Classic-style quest log.
- Quest list, quest details, quest levels and IDs, objectives, rewards, tooltips, and vertical resizing on Forever.
- Shared compatibility and layout modules supporting Forever, Classic Anniversary TBC, and Classic Era.

### Preserved
- Blizzard's native quest log presentation for Classic Anniversary TBC and Classic Era.
- Existing Classic quest log enhancements and keyboard toggle behavior.

### Notes
- WoW Forever and Classic Anniversary TBC were tested before release.
- Final Classic Era regression testing has not been reported.
- A unified options panel and further visual refinements were planned for later releases.
