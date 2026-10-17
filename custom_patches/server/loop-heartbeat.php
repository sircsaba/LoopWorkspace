<?php
/**
 * Loop heartbeat for bg.example.com
 * ---------------------------------
 * Watches Nightscout for a new CGM reading and, as soon as one appears, sends a push
 * notification (APNs) to Loop on the iPhone. The patched Loop build treats that push like a
 * pump Bluetooth heartbeat: it wakes up, fetches the reading from Nightscout and loops.
 *
 * Run from cron every minute:
 *   * * * * * /usr/local/bin/php /home/USER/loop-heartbeat/loop-heartbeat.php >/dev/null 2>&1
 *
 * Manual commands (SSH):
 *   php loop-heartbeat.php --test     send one heartbeat now, print the APNs answer
 *   php loop-heartbeat.php --check    show config, latest reading and device token, send nothing
 *   php loop-heartbeat.php --verbose  normal run, printing what it does
 */

// =============================== CONFIGURATION ===============================
$CONFIG = [
    // Nightscout site Loop reads its CGM data from (the same URL as in Loop's Nightscout CGM settings).
    'ns_url'        => 'https://nsval.mooo.com',
    // Nightscout access token with "readable" role (Admin Tools → Subjects). Leave '' if the site is public.
    'ns_token'      => '',

    // Apple push key (.p8) — Apple Developer → Certificates, IDs & Profiles → Keys → "Apple Push Notifications service".
    'apns_key_file' => __DIR__ . '/AuthKey_XXXXXXXXXX.p8',
    'apns_key_id'   => 'XXXXXXXXXX',   // 10-character Key ID shown with the key
    'team_id'       => 'YYYYYYYYYY',   // your Apple Developer Team ID

    // Loop's device token and bundle id. Leave '' to read them automatically from the Nightscout
    // profile (Loop uploads them there in loopSettings.deviceToken / loopSettings.bundleIdentifier).
    'device_token'  => '',
    'bundle_id'     => '',

    // 'production' for TestFlight / browser builds, 'sandbox' only for builds run straight from Xcode.
    'apns_env'      => 'production',

    // 'background' = invisible silent push (Apple may throttle these).
    // 'passive'    = quiet notification (no sound, no banner) that Loop deletes as soon as it wakes;
    //                use this if 'background' still leaves gaps of 15–20 minutes.
    'mode'          => 'background',

    // How long one cron run keeps watching for a new reading, and how often it checks (seconds).
    // 50 / 10 means a new reading is noticed within ~10 s while cron starts the script every minute.
    'watch_seconds' => 50,
    'poll_seconds'  => 10,

    // Ignore readings older than this (minutes) — no point waking Loop for stale data.
    'max_age_min'   => 6,

    // Extra safety: also send a heartbeat if none was sent for this many minutes, even without a new
    // reading, so Loop keeps checking the pump (0 = off).
    'keepalive_min' => 0,
];
// ============================================================================

$STATE_FILE = __DIR__ . '/heartbeat-state.json';
$LOG_FILE   = __DIR__ . '/heartbeat.log';
$LOCK_FILE  = __DIR__ . '/heartbeat.lock';

// Glucose Monitor event log: when the Glucose Monitor server (a folder next to
// this one with lib/eventlog.php and config.php, e.g. ~/bg.example.com) is
// found, each push is also written to its log (Settings › Logs in the app).
$EVENT_CFG = null;
foreach (glob(dirname(__DIR__) . '/*/lib/eventlog.php') ?: [] as $f) {
    $site = dirname($f, 2);
    if (is_file("$site/config.php")) {
        require_once $f;
        $EVENT_CFG = require "$site/config.php";
        EventLog::timezone($EVENT_CFG);
        break;
    }
}

function eventlog(string $msg): void {
    global $EVENT_CFG;
    static $db = null;
    if (!is_array($EVENT_CFG) || !class_exists('EventLog') || !EventLog::enabled('push')) return;
    try {
        $db ??= new PDO($EVENT_CFG['db_dsn'], $EVENT_CFG['db_user'] ?? null, $EVENT_CFG['db_pass'] ?? null, [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]);
        EventLog::add($db, 'push', $msg);
    } catch (Throwable $e) {
    }
}

$args    = array_slice($argv ?? [], 1);
$VERBOSE = in_array('--verbose', $args) || in_array('--test', $args) || in_array('--check', $args);

function logmsg(string $msg): void {
    global $LOG_FILE, $VERBOSE;
    $line = date('Y-m-d H:i:s') . "  $msg\n";
    if ($VERBOSE) echo $line;
    if (is_file($LOG_FILE) && filesize($LOG_FILE) > 200000) {
        // keep the log small on shared hosting
        $keep = substr(file_get_contents($LOG_FILE), -100000);
        file_put_contents($LOG_FILE, $keep);
    }
    file_put_contents($LOG_FILE, $line, FILE_APPEND);
    eventlog($msg);
}

function load_state(): array {
    global $STATE_FILE;
    $s = is_file($STATE_FILE) ? json_decode(file_get_contents($STATE_FILE), true) : null;
    return is_array($s) ? $s : [];
}

function save_state(array $s): void {
    global $STATE_FILE;
    file_put_contents($STATE_FILE, json_encode($s, JSON_PRETTY_PRINT));
}

function ns_get(string $path): ?array {
    global $CONFIG;
    $url = rtrim($CONFIG['ns_url'], '/') . $path;
    if ($CONFIG['ns_token'] !== '') {
        $url .= (strpos($url, '?') === false ? '?' : '&') . 'token=' . urlencode($CONFIG['ns_token']);
    }
    $ch = curl_init($url);
    curl_setopt_array($ch, [
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_TIMEOUT        => 15,
        CURLOPT_HTTPHEADER     => ['Accept: application/json'],
    ]);
    $body = curl_exec($ch);
    $code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    $err  = curl_error($ch);
    curl_close($ch);
    if ($body === false || $code !== 200) {
        logmsg("Nightscout $path failed: HTTP $code $err");
        return null;
    }
    $data = json_decode($body, true);
    return is_array($data) ? $data : null;
}

/** Latest SGV entry: ['date' => ms, 'sgv' => value] or null. */
function latest_reading(): ?array {
    $e = ns_get('/api/v1/entries/sgv.json?count=1');
    if (!$e || !isset($e[0]['date'])) return null;
    return ['date' => (int)$e[0]['date'], 'sgv' => $e[0]['sgv'] ?? null];
}

/** [deviceToken, bundleId] from config or from the Nightscout profile Loop uploads. */
function loop_target(array &$state): array {
    global $CONFIG;
    $token  = $CONFIG['device_token'];
    $bundle = $CONFIG['bundle_id'];
    if ($token !== '' && $bundle !== '') return [$token, $bundle];

    // Cache the profile lookup for an hour; Loop only changes the token after a reinstall.
    if (!empty($state['token']) && !empty($state['bundle']) && time() - ($state['token_checked'] ?? 0) < 3600) {
        return [$token ?: $state['token'], $bundle ?: $state['bundle']];
    }
    $p = ns_get('/api/v1/profile.json?count=1');
    $ls = $p[0]['loopSettings'] ?? [];
    if (!empty($ls['deviceToken']) && !empty($ls['bundleIdentifier'])) {
        if (($state['token'] ?? '') !== $ls['deviceToken']) logmsg("Device token from Nightscout profile: " . substr($ls['deviceToken'], 0, 8) . "…");
        $state['token']         = $ls['deviceToken'];
        $state['bundle']        = $ls['bundleIdentifier'];
        $state['token_checked'] = time();
    }
    return [$token ?: ($state['token'] ?? ''), $bundle ?: ($state['bundle'] ?? '')];
}

function b64url(string $s): string {
    return rtrim(strtr(base64_encode($s), '+/', '-_'), '=');
}

/** Convert an OpenSSL DER ECDSA signature to the 64-byte r||s form JWT ES256 needs. */
function der_to_raw(string $der): string {
    $pos = 2;                                   // skip SEQUENCE tag + length
    if (ord($der[1]) & 0x80) $pos += ord($der[1]) & 0x7f;
    $parts = [];
    for ($i = 0; $i < 2; $i++) {
        $pos++;                                 // INTEGER tag
        $len = ord($der[$pos++]);
        $int = substr($der, $pos, $len);
        $pos += $len;
        $int = ltrim($int, "\x00");
        $parts[] = str_pad($int, 32, "\x00", STR_PAD_LEFT);
    }
    return $parts[0] . $parts[1];
}

/** APNs provider token, reused for 50 minutes (Apple allows up to 60). */
function apns_jwt(array &$state): ?string {
    global $CONFIG;
    if (!empty($state['jwt']) && time() - ($state['jwt_iat'] ?? 0) < 3000) return $state['jwt'];

    $pem = @file_get_contents($CONFIG['apns_key_file']);
    $key = $pem ? openssl_pkey_get_private($pem) : false;
    if (!$key) {
        logmsg("Cannot read APNs key file " . $CONFIG['apns_key_file']);
        return null;
    }
    $iat    = time();
    $header = b64url(json_encode(['alg' => 'ES256', 'kid' => $CONFIG['apns_key_id']]));
    $claims = b64url(json_encode(['iss' => $CONFIG['team_id'], 'iat' => $iat]));
    if (!openssl_sign("$header.$claims", $der, $key, OPENSSL_ALGO_SHA256)) {
        logmsg("openssl_sign failed");
        return null;
    }
    $state['jwt']     = "$header.$claims." . b64url(der_to_raw($der));
    $state['jwt_iat'] = $iat;
    return $state['jwt'];
}

/** Send one heartbeat push. Returns true on HTTP 200. */
function send_heartbeat(array &$state, string $reason): bool {
    global $CONFIG;
    [$token, $bundle] = loop_target($state);
    if ($token === '' || $bundle === '') {
        logmsg("No device token / bundle id (set them in CONFIG or check Loop's Nightscout upload)");
        return false;
    }
    $jwt = apns_jwt($state);
    if (!$jwt) return false;

    $passive = $CONFIG['mode'] === 'passive';
    $aps = ['content-available' => 1];
    if ($passive) {
        $aps['alert'] = ['title' => 'Loop', 'body' => 'Checking for new glucose data'];
        $aps['interruption-level'] = 'passive';
        $aps['thread-id'] = 'loop-heartbeat';
    }
    $payload = json_encode(['aps' => $aps, 'loop-heartbeat' => 1, 'sent' => time()]);

    $host = $CONFIG['apns_env'] === 'sandbox' ? 'api.sandbox.push.apple.com' : 'api.push.apple.com';
    $ch = curl_init("https://$host/3/device/$token");
    curl_setopt_array($ch, [
        CURLOPT_HTTP_VERSION   => CURL_HTTP_VERSION_2_0,
        CURLOPT_POST           => true,
        CURLOPT_POSTFIELDS     => $payload,
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_TIMEOUT        => 15,
        CURLOPT_HTTPHEADER     => [
            "authorization: bearer $jwt",
            "apns-topic: $bundle",
            'apns-push-type: ' . ($passive ? 'alert' : 'background'),
            'apns-priority: ' . ($passive ? '10' : '5'),
            'apns-expiration: ' . (time() + 240),   // a heartbeat older than 4 minutes is useless
            'apns-collapse-id: loop-heartbeat',
            'content-type: application/json',
        ],
    ]);
    $body = curl_exec($ch);
    $code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    $err  = curl_error($ch);
    curl_close($ch);

    if ($code === 200) {
        $state['last_push'] = time();
        logmsg("Heartbeat sent ($reason, {$CONFIG['mode']})");
        return true;
    }
    logmsg("APNs error: HTTP $code $err $body");
    if ($code === 403) unset($state['jwt']);            // bad/expired provider token → rebuild next time
    if (in_array($code, [400, 410]) && strpos((string)$body, 'Token') !== false) {
        unset($state['token'], $state['token_checked']); // device token changed → reread profile
    }
    return false;
}

// ================================== MAIN ====================================

if (!function_exists('curl_init') || !defined('CURL_HTTP_VERSION_2_0')) {
    logmsg("PHP curl with HTTP/2 support is required for APNs");
    exit(1);
}

$lock = fopen($LOCK_FILE, 'c');
if (!flock($lock, LOCK_EX | LOCK_NB)) exit(0);      // previous run still watching

$state = load_state();

if (in_array('--check', $args)) {
    echo "Nightscout:  {$CONFIG['ns_url']}\n";
    $r = latest_reading();
    echo "Latest SGV:  " . ($r ? $r['sgv'] . ' at ' . date('Y-m-d H:i:s', intdiv($r['date'], 1000)) : 'none') . "\n";
    [$t, $b] = loop_target($state);
    echo "Bundle id:   " . ($b ?: 'NOT FOUND') . "\n";
    echo "Token:       " . ($t ? substr($t, 0, 12) . '…' : 'NOT FOUND') . "\n";
    echo "APNs key:    " . (is_readable($CONFIG['apns_key_file']) ? 'found' : 'MISSING') . "\n";
    echo "JWT:         " . (apns_jwt($state) ? 'OK' : 'FAILED') . "\n";
    save_state($state);
    exit(0);
}

if (in_array('--test', $args)) {
    send_heartbeat($state, 'manual test');
    save_state($state);
    exit(0);
}

$deadline = time() + max(0, (int)$CONFIG['watch_seconds']);
do {
    $r = latest_reading();
    if ($r) {
        $ageMin = (time() - intdiv($r['date'], 1000)) / 60;
        if ($r['date'] > ($state['last_date'] ?? 0) && $ageMin <= $CONFIG['max_age_min']) {
            $age = time() - intdiv($r['date'], 1000);
            $what = 'new Nightscout reading ' . $r['sgv'] . ' mg/dL, measured ' . date('H:i:s', intdiv($r['date'], 1000))
                . ', seen ' . ($age < 60 ? "$age s" : intdiv($age, 60) . ' min ' . ($age % 60) . ' s') . ' later';
            if (send_heartbeat($state, $what)) {
                $state['last_date'] = $r['date'];
            }
            save_state($state);
        } elseif ($CONFIG['keepalive_min'] > 0
                  && time() - ($state['last_push'] ?? 0) >= $CONFIG['keepalive_min'] * 60) {
            send_heartbeat($state, 'keep-alive');
            save_state($state);
        }
    }
    if (time() + $CONFIG['poll_seconds'] > $deadline) break;
    sleep($CONFIG['poll_seconds']);
} while (true);

save_state($state);
