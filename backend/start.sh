#!/bin/sh
# Starts the PHP server: migrations first, then PHP's built-in web server with router.php.
# Same settings as the Node server: PORT (default 3000), HOST (default 127.0.0.1), FAR_NOTES_DB,
# FAR_NOTES_DISABLE_RATE_LIMIT and FAR_NOTES_APP_ORIGINS.
set -e
cd "$(dirname "$0")/.."
php backend/migrate.php
HOST="${HOST:-127.0.0.1}"
PORT="${PORT:-3000}"
echo "FAA Regulations Study Log is running at http://$HOST:$PORT"
# Several workers, so one slow request (password hashing) doesn't hold up the others.
export PHP_CLI_SERVER_WORKERS="${PHP_CLI_SERVER_WORKERS:-4}"
exec php -S "$HOST:$PORT" backend/router.php
