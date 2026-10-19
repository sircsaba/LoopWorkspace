# Monitor Glucose Service for Loop

A second upload service for Loop, made from LoopKit's NightscoutService.
It sends the same data Loop sends to Nightscout (glucose, treatments, device
status, profile) to a separate Nightscout-compatible server, such as
`https://bg.inforap.com`. Nightscout keeps working at the same time.

Differences from NightscoutService:

- Shown in Loop as "Monitor Glucose Service" (internal identifier `InforapService`, modules `InforapServiceKit*`).
- Its own keychain entries (`InforapAPI`, `InforapOTP...`), so it never reads or
  changes the Nightscout service's address, secret or remote-command keys.
- Upload only: remote commands (bolus, carbs, overrides) are ignored, and it
  never hands therapy settings back to Loop.

The server must answer at the root of its address (Loop calls `/api/v1/...`
on the host and ignores any folder in the address).


## Packaging note

The plugin embeds both InforapServiceKit and InforapServiceKitUI. (NightscoutService only embeds its UI framework: its core framework reaches the app through LoopOnboarding. Nothing does that for this copy, so without embedding it the plugin cannot load and choosing it in Loop does nothing.)
