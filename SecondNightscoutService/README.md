# Second Nightscout Service for Loop

A second upload service for Loop, made from LoopKit's NightscoutService.
It sends the same data Loop sends to Nightscout (glucose, treatments, device
status, profile) to a second Nightscout-compatible site, while the regular
Nightscout service keeps working.

Differences from NightscoutService:

- Shown in Loop as "Second Nightscout" (identifier `SecondNightscoutService`,
  modules `SecondNightscoutServiceKit*`), so both services can be on at once.
- Its own keychain entries (`SecondNightscoutAPI`, `SecondNightscoutOTP...`): it
  never reads or changes the Nightscout service's URL, API secret or OTP.
- Upload only: remote commands (bolus, carbs, overrides) are ignored, and it
  never hands therapy settings back to Loop.

The site must answer at the root of its address (Loop calls `/api/v1/...` on
the host and ignores any folder in the URL).

## Packaging note

The plugin embeds both SecondNightscoutServiceKit and SecondNightscoutServiceKitUI.
NightscoutService only embeds its UI framework: its core framework reaches the
app through LoopOnboarding. Nothing does that for this copy, so without
embedding it the plugin cannot load and choosing it in Loop does nothing.
