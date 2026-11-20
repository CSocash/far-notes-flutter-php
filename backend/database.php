<?php
// Configuration, the SQLite connection, start-up migrations and starter-list seeding.

declare(strict_types=1);

require_once __DIR__ . '/starter-regulations.php';

define('ROOT', dirname(__DIR__));
define('DATABASE_PATH', resolve_database_path(getenv('FAR_NOTES_DB') ?: ''));
define('SUBSECTIONS_PATH', ROOT . '/regulation-subsections.json');

function resolve_database_path(string $configured): string
{
    if ($configured === '') return ROOT . '/data/part91.sqlite';
    return str_starts_with($configured, '/') ? $configured : ROOT . '/' . $configured;
}

function now_ms(): int
{
    return (int) floor(microtime(true) * 1000);
}

function open_database(): PDO
{
    $dir = dirname(DATABASE_PATH);
    if (!is_dir($dir)) mkdir($dir, 0777, true);
    $db = new PDO('sqlite:' . DATABASE_PATH, null, null, [
        PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
        PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
        PDO::ATTR_STRINGIFY_FETCHES => false,
    ]);
    // Tests write to the same file from a second connection, so wait for a lock instead of failing.
    $db->exec('PRAGMA busy_timeout = 5000');
    $db->exec('PRAGMA foreign_keys = ON');
    return $db;
}

/** Runs a query and returns all rows. */
function rows(PDO $db, string $sql, array $params = []): array
{
    $statement = $db->prepare($sql);
    $statement->execute($params);
    return $statement->fetchAll();
}

/** Runs a query and returns the first row, or null. */
function row(PDO $db, string $sql, array $params = []): ?array
{
    $statement = $db->prepare($sql);
    $statement->execute($params);
    $result = $statement->fetch();
    return $result === false ? null : $result;
}

/** Runs a statement and returns the number of changed rows. */
function run(PDO $db, string $sql, array $params = []): int
{
    $statement = $db->prepare($sql);
    $statement->execute($params);
    return $statement->rowCount();
}

function subsection_catalog(): array
{
    static $catalog = null;
    if ($catalog === null) {
        $catalog = json_decode((string) file_get_contents(SUBSECTIONS_PATH), true, 512, JSON_THROW_ON_ERROR);
    }
    return $catalog;
}

/** "91.103 — Preflight action" -> "91.103", or null when the heading doesn't start with a number. */
function section_number_of(string $heading): ?string
{
    return preg_match('/^\s*(\d+\.\d+)/', $heading, $m) ? $m[1] : null;
}

/** The catalog's lettered paragraphs for a section, or one "Entire section" item when it has none. */
function subsection_definitions(string $part, ?string $sectionNumber): array
{
    $definitions = $sectionNumber === null ? [] : (subsection_catalog()['parts'][$part][$sectionNumber] ?? []);
    return $definitions ?: [['code' => '', 'title' => 'Entire section']];
}

function insert_subsection(PDO $db, int $regulationId, array $subsection, int $covered = 0, string $date = '', string $notes = ''): void
{
    run($db, '
        INSERT OR IGNORE INTO regulation_subsections (regulation_id, code, title, covered, date, notes)
        VALUES (?, ?, ?, ?, ?, ?)
    ', [$regulationId, $subsection['code'], $subsection['title'], $covered, $date, $notes]);
}

/** New-user seeding: both starter lists with their subsections. Call inside a transaction. */
function create_starter_regulations_for_user(PDO $db, int $userId): void
{
    run($db, 'UPDATE regulations SET user_id = ? WHERE user_id IS NULL', [$userId]);
    foreach (['61', '91'] as $part) {
        $count = row($db, 'SELECT COUNT(*) AS count FROM regulations WHERE part = ? AND user_id = ?', [$part, $userId])['count'];
        if ($count !== 0) continue;
        foreach (STARTER_REGULATIONS[$part] as [$sectionNumber, $heading]) {
            run($db, 'INSERT INTO regulations (user_id, part, regulation, is_locked) VALUES (?, ?, ?, 1)', [$userId, $part, $heading]);
            $regulationId = (int) $db->lastInsertId();
            foreach (subsection_definitions($part, $sectionNumber) as $subsection) {
                insert_subsection($db, $regulationId, $subsection);
            }
        }
    }
}

/**
 * Start-up migrations. They run once per server start (start.sh calls migrate.php), are idempotent,
 * and keep existing user data: legacy section-level covered/date/notes are copied into subsections.
 */
function migrate(PDO $db): void
{
    $db->exec("
        PRAGMA journal_mode = WAL;
        CREATE TABLE IF NOT EXISTS users (
          id INTEGER PRIMARY KEY,
          username TEXT NOT NULL COLLATE NOCASE UNIQUE,
          email TEXT NOT NULL COLLATE NOCASE UNIQUE,
          password_salt TEXT NOT NULL,
          password_hash TEXT NOT NULL,
          created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
        );
        CREATE TABLE IF NOT EXISTS regulations (
          id INTEGER PRIMARY KEY,
          user_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
          part TEXT NOT NULL DEFAULT '91',
          regulation TEXT NOT NULL DEFAULT '',
          is_locked INTEGER NOT NULL DEFAULT 0 CHECK (is_locked IN (0, 1)),
          covered INTEGER NOT NULL DEFAULT 0 CHECK (covered IN (0, 1)),
          date TEXT NOT NULL DEFAULT '',
          notes TEXT NOT NULL DEFAULT '',
          created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
          updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
        );
        CREATE TABLE IF NOT EXISTS regulation_subsections (
          id INTEGER PRIMARY KEY,
          regulation_id INTEGER NOT NULL REFERENCES regulations(id) ON DELETE CASCADE,
          code TEXT NOT NULL DEFAULT '',
          title TEXT NOT NULL DEFAULT '',
          covered INTEGER NOT NULL DEFAULT 0 CHECK (covered IN (0, 1)),
          date TEXT NOT NULL DEFAULT '',
          notes TEXT NOT NULL DEFAULT '',
          created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
          updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
          UNIQUE (regulation_id, code)
        );
        CREATE TABLE IF NOT EXISTS sessions (
          token_hash TEXT PRIMARY KEY,
          user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
          expires_at INTEGER NOT NULL,
          created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
        );
        CREATE TABLE IF NOT EXISTS password_resets (
          token_hash TEXT PRIMARY KEY,
          user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
          expires_at INTEGER NOT NULL,
          created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
        );
        -- PHP keeps no memory between requests, so the auth rate limits live here instead of in a Map.
        CREATE TABLE IF NOT EXISTS rate_limits (
          key TEXT PRIMARY KEY,
          count INTEGER NOT NULL,
          reset_at INTEGER NOT NULL
        );
    ");
    // Rate limits started empty on every boot of the Node server; keep that behavior.
    $db->exec('DELETE FROM rate_limits');
    run($db, 'DELETE FROM sessions WHERE expires_at <= ?', [now_ms()]);
    run($db, 'DELETE FROM password_resets WHERE expires_at <= ?', [now_ms()]);

    $columns = array_column(rows($db, 'PRAGMA table_info(regulations)'), 'name');
    if (!in_array('part', $columns, true)) {
        $db->exec("ALTER TABLE regulations ADD COLUMN part TEXT NOT NULL DEFAULT '91'");
    }
    if (!in_array('is_locked', $columns, true)) {
        $db->exec('ALTER TABLE regulations ADD COLUMN is_locked INTEGER NOT NULL DEFAULT 0 CHECK (is_locked IN (0, 1))');
    }
    if (!in_array('user_id', $columns, true)) {
        $db->exec('ALTER TABLE regulations ADD COLUMN user_id INTEGER REFERENCES users(id) ON DELETE CASCADE');
    }

    $db->beginTransaction();
    try {
        $legacyOwner = row($db, 'SELECT id FROM users ORDER BY id LIMIT 1');
        if ($legacyOwner) {
            run($db, 'UPDATE regulations SET user_id = ? WHERE user_id IS NULL', [$legacyOwner['id']]);
        }

        // Seed starter lists for any user who has none for a part.
        foreach (rows($db, 'SELECT id FROM users ORDER BY id') as $user) {
            foreach (['91', '61'] as $part) {
                $count = row($db, 'SELECT COUNT(*) AS count FROM regulations WHERE part = ? AND user_id = ?', [$part, $user['id']])['count'];
                if ($count !== 0) continue;
                foreach (STARTER_REGULATIONS[$part] as [, $heading]) {
                    run($db, 'INSERT INTO regulations (user_id, part, regulation, is_locked) VALUES (?, ?, ?, 1)', [$user['id'], $part, $heading]);
                }
            }
        }

        // Re-lock starter rows: a starter section number, or one of the first N rows per user and part.
        $starterNumbers = [];
        foreach (STARTER_REGULATIONS as $part => $list) $starterNumbers[$part] = array_column($list, 0);
        $starterCounts = [];
        foreach (rows($db, 'SELECT id, user_id, part, regulation FROM regulations ORDER BY id') as $regulation) {
            $ownerPart = $regulation['user_id'] . ':' . $regulation['part'];
            $partCount = $starterCounts[$ownerPart] ?? 0;
            $numbers = $starterNumbers[$regulation['part']] ?? [];
            $isStarterNumber = in_array(section_number_of($regulation['regulation']), $numbers, true);
            $isOriginalSeedRow = $numbers && $partCount < count($numbers);
            if ($isStarterNumber || $isOriginalSeedRow) run($db, 'UPDATE regulations SET is_locked = 1 WHERE id = ?', [$regulation['id']]);
            $starterCounts[$ownerPart] = $partCount + 1;
        }

        // Back-fill subsections from the catalog; catalog titles win.
        foreach (rows($db, 'SELECT id, part, regulation, covered, date, notes FROM regulations') as $regulation) {
            foreach (subsection_definitions($regulation['part'], section_number_of($regulation['regulation'])) as $subsection) {
                insert_subsection($db, $regulation['id'], $subsection, $regulation['covered'], $regulation['date'], $regulation['notes']);
                run($db, '
                    UPDATE regulation_subsections SET title = ?, updated_at = CURRENT_TIMESTAMP
                    WHERE regulation_id = ? AND code = ? AND title != ?
                ', [$subsection['title'], $regulation['id'], $subsection['code'], $subsection['title']]);
            }
        }
        $db->commit();
    } catch (Throwable $error) {
        $db->rollBack();
        throw $error;
    }
}
