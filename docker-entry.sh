#!/bin/sh
set -e

if [ -f tmp/pids/server.pid ]; then
  echo "Removing stale server PID file at tmp/pids/server.pid...."
  rm tmp/pids/server.pid
fi

echo "Checking Ruby gems..."
if ! bundle check > /dev/null 2>&1; then
  echo "Missing gems detected. Running bundle install..."
  bundle install
fi

echo "Running migrations..."
bundle exec rails db:migrate

echo "Seeding database..."
bundle exec rails db:seed

exec "$@"