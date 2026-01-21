EventQ

Install
1) Copy the "EventQ" folder into:
   World of Warcraft/_retail_/Interface/AddOns/
2) Restart WoW or run /reload.
3) On the character select screen, click AddOns and ensure "EventQ" is enabled.

Settings (modern Settings UI)
- Esc -> Settings -> AddOns -> EventQ
- Or type: /eventq config

Slash commands
- /eventq
  Toggles the EventQ main window.

- /eventq config
- /eventq settings
  Opens the EventQ Settings category.

Calendar Event popup
- The Calendar Event popup uses modern DropdownButton menus.
- Category and Instance menus use Blizzard's default WowStyle1 highlight.

Troubleshooting
- If the Settings entry does not appear, verify you are on Retail and the addon is enabled, then /reload.
- If the Calendar menus show "Loading instances...", wait a moment and click Retry.
- If you suspect a UI taint issue, reproduce once, then reload and test with other addons disabled.

Support diagnostics
- The quickest sanity check is to run:
  /eventq
  /eventq config
  and confirm the window and Settings category open without errors.
