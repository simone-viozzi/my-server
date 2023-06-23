#! /bin/sh

echo "sleeping..."
sleep 60
echo "sleep done"

echo "executing: $@"
exec "$@"
