# Monitor Glucose Service for Loop

A second upload service for Loop, made from LoopKit's NightscoutService.
It sends the same data Loop sends to Nightscout (glucose, treatments, device
status, profile) to a separate Nightscout-compatible server, such as
`https://bg.example.com`. Nightscout keeps working at the same time.

Differences from NightscoutService:

- Service name "Monitor Glucose" (identifier `MonitorGlucoseService`), modules `MonitorGlucoseServiceKit*`.
- Its own keychain entries (`MonitorGlucoseAPI`, `MonitorGlucoseOTP...`), so it never reads or
  changes the Nightscout service's address, secret or remote-command keys.
- Upload only: remote commands (bolus, carbs, overrides) are ignored, and it
  never hands therapy settings back to Loop.

The server must answer at the root of its address (Loop calls `/api/v1/...`
on the host and ignores any folder in the address).
