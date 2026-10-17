# Loop heartbeat push — install guide

Loop with Omnipod DASH + Nightscout CGM has nothing that wakes it in the background, so iOS only
lets it run every 15–20 minutes. This adds a "heartbeat": your server watches Nightscout and, the
moment a new reading arrives, sends a push to Loop. The patched Loop treats that push exactly like a
RileyLink heartbeat: it fetches the reading and loops.

```
CGM → uploader → Nightscout (nsval.mooo.com) ──poll every 10 s── loop-heartbeat.php (bg.inforap.com, WHC)
                                                                        │ APNs push
iPhone: Loop wakes → fetches new reading from Nightscout → loops ◄──────┘
```

Files:

| File | Goes to |
|---|---|
| `loop_heartbeat.patch` | GitHub repo `sircsaba/LoopWorkspace`, folder `custom_patches/` |
| `server/loop-heartbeat.php` | WHC account, folder `~/loop-heartbeat/` (outside `public_html`) |
| `AuthKey_XXXXXXXXXX.p8` (your Apple key) | WHC, same folder `~/loop-heartbeat/` |

---

## 1. Loop app (GitHub browser build)

1. In `sircsaba/LoopWorkspace` on GitHub: **Add file → Upload files**, upload
   `loop_heartbeat.patch` into a new folder `custom_patches/` (type `custom_patches/` in the name box), commit to `main`.
2. Edit `.github/workflows/build_loop.yml`. Under the line `# Submodule xxxxx patches:` add:

   ```yaml
             git apply --directory=Loop -v --whitespace=fix ./custom_patches/loop_heartbeat.patch
   ```

   (Same indentation as the `curl ... | git apply` template lines above it. Put it **before** the
   `/bin/bash -c "$(curl -fsSL ...CustomizationSelect.sh)"` block.)
3. Run **Actions → 4. Build Loop**, install the new build from TestFlight.
4. Open Loop once after installing so it registers for push and uploads its new device token
   to Nightscout (Settings → Services → Nightscout must be on, which it is for you).

What the patch changes (3 files in `Loop/Loop`): `AppDelegate.swift` recognises a push carrying
`loop-heartbeat`; `LoopAppManager.swift` runs the heartbeat, keeps Loop awake 25 s for the pump,
hides/clears heartbeat notifications; `DeviceDataManager.swift` adds `remoteHeartbeatDidFire`,
which calls the same CGM refresh a pump heartbeat does.

## 2. Apple push key

If your Nightscout already has `LOOP_APNS_KEY` set (for remote commands), reuse that same key, Key ID
and Team ID. Otherwise:

1. developer.apple.com → Certificates, IDs & Profiles → **Keys → +**
2. Name it `Loop heartbeat`, tick **Apple Push Notifications service (APNs)**, Continue → Register.
3. **Download** `AuthKey_<KEYID>.p8` (only downloadable once). Note the **Key ID**.
4. Your **Team ID** is at the top right of the developer site (Membership).

## 3. Server (WHC)

1. In cPanel **File Manager** (or SFTP) create `/home/<cpanel-user>/loop-heartbeat/` — *not* inside `public_html`.
2. Upload `loop-heartbeat.php` and `AuthKey_<KEYID>.p8` there.
3. Edit the CONFIG block at the top of `loop-heartbeat.php`:
   - `ns_url` → `https://nsval.mooo.com` (already set)
   - `ns_token` → a Nightscout token with `readable` role, if your site isn't public
   - `apns_key_file` → `__DIR__ . '/AuthKey_<KEYID>.p8'`
   - `apns_key_id`, `team_id`
   - leave `device_token` / `bundle_id` empty (read from Nightscout automatically)
4. Test over SSH (cPanel → Terminal):

   ```bash
   cd ~/loop-heartbeat
   chmod 600 AuthKey_*.p8
   php loop-heartbeat.php --check     # must show Latest SGV, Bundle id, Token, APNs key found, JWT OK
   php loop-heartbeat.php --test      # must print "Heartbeat sent"
   ```

   An `APNs error: HTTP 400 BadDeviceToken` means the build is a sandbox build — set `apns_env` to `sandbox`.
   `HTTP 403` means Key ID / Team ID / key file don't match.
5. cPanel → **Cron Jobs** → Add New Cron Job, "Once Per Minute (* * * * *)", command:

   ```
   /usr/local/bin/php /home/<cpanel-user>/loop-heartbeat/loop-heartbeat.php >/dev/null 2>&1
   ```

   Each run watches Nightscout for 50 s, checking every 10 s, so a new reading triggers a push within ~10 s.

## Event log (Glucose Monitor)

When the Glucose Monitor server is in a folder next to `loop-heartbeat/` (e.g. `~/bg.inforap.com`,
with `lib/eventlog.php`), every push is also written to its event log, next to the readings and
the loop runs: Glucose Monitor › Settings › **Logs**. Nothing to set up.

## 4. Check it works

- `~/loop-heartbeat/heartbeat.log` should show `Heartbeat sent (new reading …)` every 5 minutes.
- In Loop, lock the phone for 30 minutes, then check the glucose and loop history: points should be every 5 minutes.
- Loop Settings → Issue Report → search `Remote heartbeat push did fire`.

**If gaps remain:** Apple rations invisible (`background`) pushes per app. If the log shows a push every
5 minutes but Loop still only runs every 15–20, set `'mode' => 'passive'`. That sends a quiet
notification (no sound, no banner, goes to Notification Centre) which iOS delivers reliably, and Loop
deletes it as soon as it wakes. Optionally set `'keepalive_min' => 10` to wake Loop even when no
reading arrives.

**Limits:** never swipe Loop closed in the app switcher (iOS then blocks all pushes to it), and
Low Power Mode reduces background pushes.
