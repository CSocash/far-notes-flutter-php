<?php
// Password hashing shared by router.php and setup-user.php.
//
// Same scheme as the Node server: scrypt (N=16384, r=8, p=1), 64-byte key, and the salt is a 32-character
// hex string used as text. libsodium's scryptsalsa208sha256 picks N, r and p from opslimit/memlimit;
// these two values give exactly N=16384, r=8, p=1, so accounts made by the Node server still sign in.

declare(strict_types=1);

const SCRYPT_OPSLIMIT = 524288;    // libsodium: maxN = opslimit / 32 = 16384, then N = 2^14 = 16384
const SCRYPT_MEMLIMIT = 67108864;  // above 32 * opslimit, so p stays 1
const SCRYPT_KEY_BYTES = 64;

function new_password_salt(): string
{
    return bin2hex(random_bytes(16)); // 32 characters, which is libsodium's required salt length
}

/** Returns the raw 64-byte scrypt key. The salt must be 32 bytes (a salt from new_password_salt). */
function scrypt_key(string $password, string $salt): string
{
    return sodium_crypto_pwhash_scryptsalsa208sha256(SCRYPT_KEY_BYTES, $password, $salt, SCRYPT_OPSLIMIT, SCRYPT_MEMLIMIT);
}

function hash_password(string $password, string $salt): string
{
    return bin2hex(scrypt_key($password, $salt));
}
