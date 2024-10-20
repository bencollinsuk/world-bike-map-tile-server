#!/bin/bash

set -euo pipefail

# Initialize PostgreSQL and Apache
# createPostgresConfig
# service postgresql start
# service apache2 restart
# setPostgresPassword

# Configure renderd threads
sed -i -E "s/num_threads=[0-9]+/num_threads=${THREADS:-4}/g" /etc/renderd.conf

# # start cron job to trigger consecutive updates
# if [ "$UPDATES" = "enabled" ] || [ "$UPDATES" = "1" ]; then
#   /etc/init.d/cron start
# fi

# Run while handling docker stop's SIGTERM
stop_handler() {
    # kill -TERM "$child"
    exit 0
}

trap stop_handler SIGTERM

echo "Starting renderd with render_list using ${THREADS:-4} threads..."

sudo -u renderer renderd -c /etc/renderd.conf && 
# render_list --help
render_list -v -n ${THREADS:-4} -a -z 0 -Z 7
# render_list -v -n ${THREADS:-4} -a -z 8 -Z 8
# render_list -v -n ${THREADS:-4} -a -z 9 -Z 9
# render_list -v -n ${THREADS:-4} -a -z 10 -Z 10
# render_list -v -n ${THREADS:-4} -a -z 11 -Z 11
# render_list -v -n ${THREADS:-4} -a -z 13 -Z 13
# render_list -v -n ${THREADS:-4} -a -z 14 -Z 14

# render_list -v -n ${THREADS:-4} -a -z 8 -Z 8

# Edinburgh
# render_list -v -n ${THREADS:-4} -a -z 18 -Z 18 -x 130000 -X 132000 -y 85000 -Y 87000 

exit 0

