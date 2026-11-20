<?php
// The whole HTTP layer: auth, the regulation API and the static-file allowlist.
// Run through PHP's built-in server (start.sh): php -S 127.0.0.1:3000 backend/router.php
// It answers every request itself, so the built-in server never serves a file from disk on its own.

declare(strict_types=1);

require_once __DIR__ . '/database.php';
require_once __DIR__ . '/validation.php';
require_once __DIR__ . '/passwords.php';

const MAX_BODY_BYTES = 16384;
const SUPPORTED_PARTS = ['61', '91'];
const SESSION_MAX_AGE_MS = 7 * 24 * 60 * 60 * 1000;
const RESET_MAX_AGE_MS = 30 * 60 * 1000;
const RATE_LIMIT_WINDOW_MS = 15 * 60 * 1000;
// Tracker files only signed-in users may load; everything else static must be in PUBLIC_PATHS.
const TRACKER_PATHS = ['/', '/index.html', '/app.js', '/app-core.js'];
const PUBLIC_PATHS = [
    '/login', '/login.html', '/create-account', '/create-account.html', '/forgot-password', '/forgot-password.html',
    '/reset-password', '/reset-password.html', '/styles.css', '/aircraft-front-view.png',
    '/login.js', '/create-account.js', '/forgot-password.js', '/reset-password.js', '/api-client.js',
];
const STATIC_FILES = [
    '/' => ['index.html', 'text/html; charset=utf-8'],
    '/index.html' => ['index.html', 'text/html; charset=utf-8'],
    '/login' => ['login.html', 'text/html; charset=utf-8'],
    '/login.html' => ['login.html', 'text/html; charset=utf-8'],
    '/create-account' => ['create-account.html', 'text/html; charset=utf-8'],
    '/create-account.html' => ['create-account.html', 'text/html; charset=utf-8'],
    '/forgot-password' => ['forgot-password.html', 'text/html; charset=utf-8'],
    '/forgot-password.html' => ['forgot-password.html', 'text/html; charset=utf-8'],
    '/reset-password' => ['reset-password.html', 'text/html; charset=utf-8'],
    '/reset-password.html' => ['reset-password.html', 'text/html; charset=utf-8'],
    '/styles.css' => ['styles.css', 'text/css; charset=utf-8'],
    '/aircraft-front-view.png' => ['aircraft-front-view.png', 'image/png'],
    '/app.js' => ['app.js', 'text/javascript; charset=utf-8'],
    '/app-core.js' => ['app-core.js', 'text/javascript; charset=utf-8'],
    '/api-client.js' => ['api-client.js', 'text/javascript; charset=utf-8'],
    '/login.js' => ['login.js', 'text/javascript; charset=utf-8'],
    '/create-account.js' => ['create-account.js', 'text/javascript; charset=utf-8'],
    '/forgot-password.js' => ['forgot-password.js', 'text/javascript; charset=utf-8'],
    '/reset-password.js' => ['reset-password.js', 'text/javascript; charset=utf-8'],
];

/** Thrown inside a handler to answer with a JSON error. */
final class HttpError extends Exception
{
    public function __construct(public readonly int $status, string $message)
    {
        parent::__construct($message);
    }
}

// ---------- Request and response helpers ----------

function header_value(string $name): string
{
    $value = $_SERVER['HTTP_' . strtoupper(str_replace('-', '_', $name))] ?? '';
    return is_string($value) ? $value : '';
}

/** Origins of the app shells: the Capacitor app used these, and the Flutter app sends one of them too. */
function app_origins(): array
{
    $configured = getenv('FAR_NOTES_APP_ORIGINS');
    $list = $configured === false ? 'capacitor://localhost,https://localhost' : $configured;
    return array_values(array_filter(array_map('trim', explode(',', $list))));
}

function is_app_origin(string $origin): bool
{
    return $origin !== '' && in_array($origin, app_origins(), true);
}

function is_allowed_origin(): bool
{
    $origin = header_value('Origin');
    return $origin === '' || $origin === 'http://' . header_value('Host') || is_app_origin($origin);
}

function require_allowed_origin(): void
{
    if (!is_allowed_origin()) throw new HttpError(403, 'Request origin is not allowed.');
}

function is_app_client(): bool
{
    return header_value('X-Far-Notes-Client') === 'app';
}

function send_json(int $status, mixed $payload): void
{
    http_response_code($status);
    header('Content-Type: application/json; charset=utf-8');
    header('Cache-Control: no-store');
    header('X-Content-Type-Options: nosniff');
    echo json_encode($payload, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE | JSON_THROW_ON_ERROR);
}

function redirect(string $location): void
{
    http_response_code(302);
    header('Location: ' . $location);
    header('Cache-Control: no-store');
}

/** The JSON body as an array. A JSON value that isn't an object counts as an object with no fields. */
function read_json(): array
{
    $length = (int) ($_SERVER['CONTENT_LENGTH'] ?? 0);
    if ($length > MAX_BODY_BYTES) throw new HttpError(413, 'Request body is too large.');
    $raw = (string) file_get_contents('php://input', false, null, 0, MAX_BODY_BYTES + 1);
    if (strlen($raw) > MAX_BODY_BYTES) throw new HttpError(413, 'Request body is too large.');
    try {
        $body = json_decode($raw, false, 512, JSON_THROW_ON_ERROR);
    } catch (JsonException) {
        throw new HttpError(400, 'Request body must be valid JSON.');
    }
    return is_object($body) ? get_object_vars($body) : [];
}

function text_field(array $body, string $name, bool $trim = true): string
{
    $value = $body[$name] ?? '';
    if (!is_string($value)) return '';
    return $trim ? trim($value) : $value;
}

function log_line(string $message): void
{
    file_put_contents('php://stderr', $message . PHP_EOL);
}

// ---------- Sessions and rate limits ----------

/**
 * The website authenticates with the HttpOnly cookie; the app sends "Authorization: Bearer <token>".
 * Requests from an app origin authenticate by bearer token only, so allowing those origins can't
 * turn a website cookie into a cross-site request.
 */
function session_token(): ?string
{
    if (preg_match('/^Bearer ([a-f0-9]{64})$/D', header_value('Authorization'), $m)) return $m[1];
    if (is_app_origin(header_value('Origin'))) return null;
    $cookie = $_COOKIE['study_session'] ?? null;
    return is_string($cookie) ? $cookie : null;
}

function authenticated_user(PDO $db): ?array
{
    $token = session_token();
    if ($token === null || !preg_match('/^[a-f0-9]{64}$/D', $token)) return null;
    $session = row($db, '
        SELECT users.id, users.username, users.email, sessions.expires_at
        FROM sessions JOIN users ON users.id = sessions.user_id
        WHERE sessions.token_hash = ?
    ', [hash('sha256', $token)]);
    if (!$session) return null;
    if ($session['expires_at'] <= now_ms()) {
        run($db, 'DELETE FROM sessions WHERE token_hash = ?', [hash('sha256', $token)]);
        return null;
    }
    return $session;
}

function set_session_cookie(string $token): void
{
    header('Set-Cookie: study_session=' . $token . '; Path=/; HttpOnly; SameSite=Strict; Max-Age=' . intdiv(SESSION_MAX_AGE_MS, 1000));
}

function clear_session_cookie(): void
{
    header('Set-Cookie: study_session=; Path=/; HttpOnly; SameSite=Strict; Max-Age=0');
}

/** Counts an attempt; false once more than $limit attempts came from this address in 15 minutes. */
function consume_rate_limit(PDO $db, string $key, int $limit = 8): bool
{
    if (getenv('FAR_NOTES_DISABLE_RATE_LIMIT') === '1') return true;
    $now = now_ms();
    $mapKey = $key . ':' . ($_SERVER['REMOTE_ADDR'] ?? 'unknown');
    $db->exec('BEGIN IMMEDIATE');
    try {
        $attempt = row($db, 'SELECT count, reset_at FROM rate_limits WHERE key = ?', [$mapKey]);
        if (!$attempt || $attempt['reset_at'] <= $now) {
            run($db, 'INSERT OR REPLACE INTO rate_limits (key, count, reset_at) VALUES (?, 1, ?)', [$mapKey, $now + RATE_LIMIT_WINDOW_MS]);
            $count = 1;
        } else {
            $count = $attempt['count'] + 1;
            run($db, 'UPDATE rate_limits SET count = ? WHERE key = ?', [$count, $mapKey]);
        }
        $db->exec('COMMIT');
    } catch (Throwable $error) {
        $db->exec('ROLLBACK');
        throw $error;
    }
    return $count <= $limit;
}

// ---------- Auth endpoints ----------

/** Returns true when the path was an auth endpoint and has been answered. */
function handle_auth_request(PDO $db, string $path, string $method): bool
{
    if ($path === '/api/auth/me' && $method === 'GET') {
        $user = authenticated_user($db);
        send_json(200, $user ? ['authenticated' => true, 'username' => $user['username'], 'email' => $user['email']] : ['authenticated' => false]);
        return true;
    }

    if ($path === '/api/auth/login' && $method === 'POST') {
        require_allowed_origin();
        if (!consume_rate_limit($db, 'login')) throw new HttpError(429, 'Too many sign-in attempts. Please wait 15 minutes and try again.');
        $body = read_json();
        $identifier = text_field($body, 'username');
        $password = text_field($body, 'password', false);
        $user = row($db, 'SELECT id, username, email, password_salt, password_hash FROM users WHERE username = ? OR email = ?', [$identifier, $identifier]);
        // Hash even when there is no such user, so the response time doesn't reveal which usernames exist.
        $supplied = scrypt_key($password, $user ? $user['password_salt'] : str_pad('invalid-account-salt', 32, '-'));
        $stored = $user ? (string) hex2bin($user['password_hash']) : str_repeat("\0", SCRYPT_KEY_BYTES);
        if (!$user || !hash_equals($stored, $supplied)) throw new HttpError(401, 'Username or password is incorrect.');
        $token = bin2hex(random_bytes(32));
        $now = now_ms();
        run($db, 'DELETE FROM sessions WHERE expires_at <= ?', [$now]);
        run($db, 'INSERT INTO sessions (token_hash, user_id, expires_at) VALUES (?, ?, ?)', [hash('sha256', $token), $user['id'], $now + SESSION_MAX_AGE_MS]);
        set_session_cookie($token);
        send_json(200, is_app_client() ? ['username' => $user['username'], 'token' => $token] : ['username' => $user['username']]);
        return true;
    }

    if ($path === '/api/auth/register' && $method === 'POST') {
        require_allowed_origin();
        if (!consume_rate_limit($db, 'register', 5)) throw new HttpError(429, 'Too many account creation attempts. Please wait 15 minutes and try again.');
        $body = read_json();
        $username = text_field($body, 'username');
        $email = text_field($body, 'email');
        $password = text_field($body, 'password', false);
        $credentialsError = check_username($username) ?? check_email($email) ?? check_password($password);
        if ($credentialsError !== null) throw new HttpError(400, $credentialsError);
        if (row($db, 'SELECT id FROM users WHERE username = ? OR email = ?', [$username, $email])) {
            throw new HttpError(409, 'That username or email is already in use.');
        }
        $salt = new_password_salt();
        $passwordHash = hash_password($password, $salt);
        $db->exec('BEGIN IMMEDIATE');
        try {
            run($db, 'INSERT INTO users (username, email, password_salt, password_hash) VALUES (?, ?, ?, ?)', [$username, $email, $salt, $passwordHash]);
            create_starter_regulations_for_user($db, (int) $db->lastInsertId());
            $db->exec('COMMIT');
        } catch (Throwable $error) {
            $db->exec('ROLLBACK');
            // Two requests for the same name can both pass the check above; the UNIQUE index stops the second.
            if ($error instanceof PDOException && str_contains($error->getMessage(), 'UNIQUE')) {
                throw new HttpError(409, 'That username or email is already in use.');
            }
            throw $error;
        }
        send_json(201, ['accountCreated' => true]);
        return true;
    }

    if ($path === '/api/auth/logout' && $method === 'POST') {
        require_allowed_origin();
        $token = session_token();
        if ($token !== null) run($db, 'DELETE FROM sessions WHERE token_hash = ?', [hash('sha256', $token)]);
        clear_session_cookie();
        send_json(200, ['loggedOut' => true]);
        return true;
    }

    if ($path === '/api/auth/forgot-password' && $method === 'POST') {
        require_allowed_origin();
        if (!consume_rate_limit($db, 'reset')) throw new HttpError(429, 'Too many reset requests. Please wait 15 minutes and try again.');
        $body = read_json();
        $user = row($db, 'SELECT id, email FROM users WHERE email = ?', [text_field($body, 'email')]);
        if ($user) {
            $token = bin2hex(random_bytes(32));
            run($db, 'DELETE FROM password_resets WHERE user_id = ?', [$user['id']]);
            run($db, 'INSERT INTO password_resets (token_hash, user_id, expires_at) VALUES (?, ?, ?)', [hash('sha256', $token), $user['id'], now_ms() + RESET_MAX_AGE_MS]);
            log_line("Password reset link for {$user['email']} (expires in 30 minutes):");
            log_line('http://127.0.0.1:' . ($_SERVER['SERVER_PORT'] ?? '3000') . '/reset-password#token=' . $token);
        }
        send_json(200, ['message' => 'If an account matches that address, a reset link is available in the local server terminal.']);
        return true;
    }

    if ($path === '/api/auth/reset-password' && $method === 'POST') {
        require_allowed_origin();
        $body = read_json();
        $token = text_field($body, 'token', false);
        $password = text_field($body, 'password', false);
        $invalidLink = 'This reset link is invalid or has expired. Request a new one.';
        if (!preg_match('/^[a-f0-9]{64}$/D', $token)) throw new HttpError(400, $invalidLink);
        $passwordError = check_password($password);
        if ($passwordError !== null) throw new HttpError(400, $passwordError);
        $reset = row($db, 'SELECT user_id FROM password_resets WHERE token_hash = ? AND expires_at > ?', [hash('sha256', $token), now_ms()]);
        if (!$reset) throw new HttpError(400, $invalidLink);
        $salt = new_password_salt();
        run($db, 'UPDATE users SET password_salt = ?, password_hash = ? WHERE id = ?', [$salt, hash_password($password, $salt), $reset['user_id']]);
        run($db, 'DELETE FROM password_resets WHERE user_id = ?', [$reset['user_id']]);
        run($db, 'DELETE FROM sessions WHERE user_id = ?', [$reset['user_id']]);
        send_json(200, ['passwordUpdated' => true]);
        return true;
    }

    return false;
}

// ---------- Regulation endpoints ----------

function requested_part(): string
{
    $part = $_GET['part'] ?? '91';
    if (!is_string($part) || !in_array($part, SUPPORTED_PARTS, true)) throw new HttpError(400, 'Part must be 61 or 91.');
    return $part;
}

function subsection_json(array $subsection): array
{
    return [
        'id' => $subsection['id'],
        'code' => $subsection['code'],
        'title' => $subsection['title'],
        'covered' => (bool) $subsection['covered'],
        'date' => $subsection['date'],
        'notes' => $subsection['notes'],
    ];
}

function regulation_json(PDO $db, array $regulation): array
{
    $subsections = rows($db, 'SELECT id, code, title, covered, date, notes FROM regulation_subsections WHERE regulation_id = ? ORDER BY id', [$regulation['id']]);
    return [
        'id' => $regulation['id'],
        'regulation' => $regulation['regulation'],
        'isLocked' => (bool) $regulation['is_locked'],
        'subsections' => array_map('subsection_json', $subsections),
    ];
}

function find_regulation(PDO $db, int $id, string $part, int $userId): ?array
{
    return row($db, 'SELECT id, regulation, part, is_locked FROM regulations WHERE id = ? AND part = ? AND user_id = ?', [$id, $part, $userId]);
}

/** Returns true when the path was a regulation endpoint and has been answered. */
function handle_api_request(PDO $db, array $user, string $path, string $method): bool
{
    $userId = (int) $user['id'];

    if ($path === '/api/regulations' && $method === 'GET') {
        $part = requested_part();
        $regulations = rows($db, 'SELECT id, regulation, is_locked FROM regulations WHERE part = ? AND user_id = ? ORDER BY id', [$part, $userId]);
        send_json(200, array_map(fn ($regulation) => regulation_json($db, $regulation), $regulations));
        return true;
    }

    if ($path === '/api/regulations' && $method === 'POST') {
        require_allowed_origin();
        $part = requested_part();
        $body = read_json();
        $regulation = $body['regulation'] ?? '';
        if (!is_string($regulation)) throw new HttpError(400, 'Regulation must be text.');
        $db->exec('BEGIN IMMEDIATE');
        try {
            run($db, "INSERT INTO regulations (user_id, part, regulation, covered, date, notes) VALUES (?, ?, ?, 0, '', '')", [$userId, $part, $regulation]);
            $regulationId = (int) $db->lastInsertId();
            run($db, "INSERT INTO regulation_subsections (regulation_id, code, title) VALUES (?, '', 'Entire section')", [$regulationId]);
            $db->exec('COMMIT');
        } catch (Throwable $error) {
            $db->exec('ROLLBACK');
            throw $error;
        }
        send_json(201, regulation_json($db, find_regulation($db, $regulationId, $part, $userId)));
        return true;
    }

    if (preg_match('#^/api/regulations/(\d+)$#D', $path, $m) && $method === 'PATCH') {
        require_allowed_origin();
        $part = requested_part();
        $id = (int) $m[1];
        $existing = find_regulation($db, $id, $part, $userId);
        if (!$existing) throw new HttpError(404, 'Regulation not found.');
        if ($existing['is_locked']) throw new HttpError(403, 'This regulation heading is protected and cannot be edited.');
        $body = read_json();
        if (!is_string($body['regulation'] ?? null)) throw new HttpError(400, 'Regulation must be text.');
        $changed = run($db, 'UPDATE regulations SET regulation = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ? AND part = ? AND user_id = ?', [$body['regulation'], $id, $part, $userId]);
        if ($changed === 0) throw new HttpError(404, 'Regulation not found.');
        send_json(200, regulation_json($db, find_regulation($db, $id, $part, $userId)));
        return true;
    }

    if (preg_match('#^/api/subsections/(\d+)$#D', $path, $m) && $method === 'PATCH') {
        require_allowed_origin();
        $part = requested_part();
        $body = read_json();
        $subsection = row($db, '
            SELECT s.id FROM regulation_subsections s JOIN regulations r ON r.id = s.regulation_id
            WHERE s.id = ? AND r.part = ? AND r.user_id = ?
        ', [(int) $m[1], $part, $userId]);
        if (!$subsection) throw new HttpError(404, 'Subsection not found.');
        $updates = [];
        $values = [];
        if (array_key_exists('covered', $body)) {
            if (!is_bool($body['covered'])) throw new HttpError(400, 'Covered must be true or false.');
            $updates[] = 'covered = ?';
            $values[] = $body['covered'] ? 1 : 0;
        }
        if (array_key_exists('date', $body)) {
            if (!is_iso_date($body['date'])) throw new HttpError(400, 'Date must be a valid YYYY-MM-DD date.');
            $updates[] = 'date = ?';
            $values[] = $body['date'];
        }
        if (array_key_exists('notes', $body)) {
            if (!is_string($body['notes'])) throw new HttpError(400, 'Notes must be text.');
            $updates[] = 'notes = ?';
            $values[] = $body['notes'];
        }
        if (!$updates) throw new HttpError(400, 'Provide at least one field to update.');
        $updates[] = 'updated_at = CURRENT_TIMESTAMP';
        $values[] = $subsection['id'];
        run($db, 'UPDATE regulation_subsections SET ' . implode(', ', $updates) . ' WHERE id = ?', $values);
        send_json(200, subsection_json(row($db, 'SELECT id, code, title, covered, date, notes FROM regulation_subsections WHERE id = ?', [$subsection['id']])));
        return true;
    }

    return false;
}

// ---------- Static files ----------

function serve_static(string $path): void
{
    [$file, $type] = STATIC_FILES[$path];
    http_response_code(200);
    header('Content-Type: ' . $type);
    header('X-Content-Type-Options: nosniff');
    header('Cache-Control: no-cache');
    readfile(ROOT . '/' . $file);
}

// ---------- Dispatch ----------

function handle_request(): void
{
    $method = $_SERVER['REQUEST_METHOD'] ?? 'GET';
    $path = parse_url($_SERVER['REQUEST_URI'] ?? '/', PHP_URL_PATH);
    if (!is_string($path)) throw new HttpError(400, 'Invalid request URL.');

    // CORS for the app shells only. No Allow-Credentials: the app never relies on cookies.
    $origin = header_value('Origin');
    if (is_app_origin($origin)) {
        header('Access-Control-Allow-Origin: ' . $origin);
        header('Vary: Origin');
    }
    if ($method === 'OPTIONS') {
        if (!is_app_origin($origin)) throw new HttpError(403, 'Request origin is not allowed.');
        http_response_code(204);
        header('Access-Control-Allow-Methods: GET, POST, PATCH');
        header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Far-Notes-Client');
        header('Access-Control-Max-Age: 600');
        return;
    }

    $db = open_database();
    if (handle_auth_request($db, $path, $method)) return;

    $user = authenticated_user($db);
    $isApi = str_starts_with($path, '/api/');
    if ($isApi && !$user) throw new HttpError(401, 'Sign in required.');
    if (in_array($path, TRACKER_PATHS, true) && !$user) {
        redirect('/login');
        return;
    }
    if (in_array($path, ['/login', '/login.html', '/create-account', '/create-account.html'], true) && $user) {
        redirect('/');
        return;
    }

    if ($isApi) {
        if (!handle_api_request($db, $user, $path, $method)) throw new HttpError(404, 'API endpoint not found.');
        return;
    }
    if ($method !== 'GET' && $method !== 'HEAD') throw new HttpError(405, 'Method not allowed.');
    if (!in_array($path, PUBLIC_PATHS, true) && !in_array($path, TRACKER_PATHS, true)) throw new HttpError(404, 'Not found.');
    serve_static($path);
}

try {
    handle_request();
} catch (HttpError $error) {
    send_json($error->status, ['error' => $error->getMessage()]);
} catch (Throwable $error) {
    log_line('Request failed. ' . $error);
    if (!headers_sent()) send_json(500, ['error' => 'An unexpected server error occurred.']);
}
