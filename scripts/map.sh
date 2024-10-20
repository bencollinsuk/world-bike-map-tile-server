#!/bin/bash

set -euo pipefail

# Clean /tmp
rm -rf /tmp/*

# Configure Apache CORS
if [ "$ALLOW_CORS" == "enabled" ] || [ "$ALLOW_CORS" == "1" ]; then
    echo "export APACHE_ARGUMENTS='-D ALLOW_CORS'" >> /etc/apache2/envvars
fi

# # Initialize PostgreSQL and Apache
# # createPostgresConfig
# # service postgresql start
service apache2 restart
# # setPostgresPassword

# Configure renderd threads
sed -i -E "s/num_threads=[0-9]+/num_threads=${THREADS:-4}/g" /etc/renderd.conf

# start cron job to trigger consecutive updates
if [ "$UPDATES" = "enabled" ] || [ "$UPDATES" = "1" ]; then
    /etc/init.d/cron start
fi

# Run while handling docker stop's SIGTERM
stop_handler() {
    kill -TERM "$child"
}
trap stop_handler SIGTERM

sleep 2

echo "Starting renderd"
sudo -u renderer renderd -f -c /etc/renderd.conf &

child=$!
wait "$child"

# service postgresql stop

exit 0
