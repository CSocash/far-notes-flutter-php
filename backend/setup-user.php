<?php
// Creates the initial account: INITIAL_PASSWORD='at-least-15-chars' php backend/setup-user.php
// Refuses to overwrite an existing account. Runs the migrations first, so the tables exist.

declare(strict_types=1);

require_once __DIR__ . '/database.php';
require_once __DIR__ . '/validation.php';
require_once __DIR__ . '/passwords.php';

$username = trim(getenv('INITIAL_USERNAME') ?: 'VMC43');
$email = trim(getenv('INITIAL_EMAIL') ?: 'VMC43@test.com');
$password = getenv('INITIAL_PASSWORD') ?: '';

function fail(string $message): never
{
    fwrite(STDERR, $message . PHP_EOL);
    exit(1);
}

if ($password === '') fail('Set INITIAL_PASSWORD to the initial account password before running setup-user.');
$error = check_password($password) ?? check_username($username) ?? check_email($email);
if ($error !== null) fail($error);

$db = open_database();
migrate($db);
if (row($db, 'SELECT COUNT(*) AS count FROM users')['count'] > 0) {
    fail('An account already exists. Initial account setup will not overwrite it.');
}
$salt = new_password_salt();
$db->beginTransaction();
run($db, 'INSERT INTO users (username, email, password_salt, password_hash) VALUES (?, ?, ?, ?)', [$username, $email, $salt, hash_password($password, $salt)]);
create_starter_regulations_for_user($db, (int) $db->lastInsertId());
$db->commit();
echo "Initial account {$username} ({$email}) created. The password is stored as a salted hash." . PHP_EOL;
