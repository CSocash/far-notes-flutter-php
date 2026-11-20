<?php
// Runs the start-up migrations once, before start.sh starts the web server.
// PHP handles each request in a fresh process, so this can't live in router.php.

declare(strict_types=1);

require_once __DIR__ . '/database.php';

migrate(open_database());
echo 'SQLite database: ' . DATABASE_PATH . PHP_EOL;
