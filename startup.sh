#!/bin/sh

# Add startup delay for database initialization
sleep 5

# Create .env file
echo "ACTUAL_SERVER_URL=https://actual.tifan.me" >/home/node/.env
echo "ACTUAL_SYNC_ID=278a95d3-2467-4941-8125-24765283a859" >>/home/node/.env
echo "ACTUAL_PASSWORD=\"$ACTUAL_PASSWORD\"" >>/home/node/.env

# Map Cloud Run's PORT to N8N_PORT if it exists
if [ -n "$PORT" ]; then
  export N8N_PORT="$PORT"
fi

# Print environment variables for debugging
echo "Database settings:"
echo "DB_TYPE: $DB_TYPE"
echo "DB_POSTGRESDB_HOST: $DB_POSTGRESDB_HOST"
echo "DB_POSTGRESDB_PORT: $DB_POSTGRESDB_PORT"
echo "N8N_PORT: $N8N_PORT"

# Start n8n with its original entrypoint
exec /docker-entrypoint.sh
