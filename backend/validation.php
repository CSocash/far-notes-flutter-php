<?php
// Pure input checks shared by router.php and setup-user.php.
// Each check_* function returns an error message for the client, or null when the value is valid.

declare(strict_types=1);

const PASSWORD_MIN_LENGTH = 15;
const PASSWORD_MAX_BYTES = 1024;
const USERNAME_PATTERN = '/^[A-Za-z0-9._-]{1,64}$/D';
const EMAIL_PATTERN = '/^[^\s@]+@[^\s@]+\.[^\s@]+$/Du';
const EMAIL_MAX_LENGTH = 254;

/** Characters (code points), so "😀" counts once. Works without the mbstring extension. */
function char_length(string $value): int
{
    $count = preg_match_all('/./su', $value);
    return $count === false ? strlen($value) : $count;
}

function is_iso_date(mixed $value): bool
{
    if ($value === '') return true;
    if (!is_string($value) || !preg_match('/^(\d{4})-(\d{2})-(\d{2})$/D', $value, $m)) return false;
    return checkdate((int) $m[2], (int) $m[3], (int) $m[1]);
}

function check_username(string $username): ?string
{
    return preg_match(USERNAME_PATTERN, $username)
        ? null
        : 'Username must be 1-64 characters and use only letters, numbers, periods, underscores, or hyphens.';
}

function check_email(string $email): ?string
{
    return char_length($email) <= EMAIL_MAX_LENGTH && preg_match(EMAIL_PATTERN, $email)
        ? null
        : 'Enter a valid email address.';
}

// Length is counted in characters; the limit is in UTF-8 bytes.
function check_password(string $password): ?string
{
    if (char_length($password) < PASSWORD_MIN_LENGTH) return 'Password must be at least ' . PASSWORD_MIN_LENGTH . ' characters.';
    if (strlen($password) > PASSWORD_MAX_BYTES) return 'Password must be ' . PASSWORD_MAX_BYTES . ' bytes or fewer.';
    return null;
}
