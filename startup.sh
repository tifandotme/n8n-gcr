#!/bin/sh

# Add startup delay for database initialization
sleep 5

# Map Cloud Run's PORT to N8N_PORT if it exists
if [ -n "$PORT" ]; then
  export N8N_PORT="$PORT"
fi

# Check npm global prefix and package
echo "NPM global prefix: $(npm config get prefix)"
echo "Checking @actual-app/api: $(npm list -g @actual-app/api 2>/dev/null || echo 'Not found')"

# Print environment variables for debugging
echo "Database settings:"
echo "DB_TYPE: $DB_TYPE"
echo "DB_POSTGRESDB_HOST: $DB_POSTGRESDB_HOST"
echo "DB_POSTGRESDB_PORT: $DB_POSTGRESDB_PORT"
echo "N8N_PORT: $N8N_PORT"

# Start n8n with its original entrypoint
exec /docker-entrypoint.sh
