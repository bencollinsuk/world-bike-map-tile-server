#!/bin/bash

set -euo pipefail

function createPostgresConfig() {
  cp /etc/postgresql/$PG_VERSION/main/postgresql.custom.conf.tmpl /etc/postgresql/$PG_VERSION/main/conf.d/postgresql.custom.conf
  sudo -u postgres echo "autovacuum = $AUTOVACUUM" >> /etc/postgresql/$PG_VERSION/main/conf.d/postgresql.custom.conf
  cat /etc/postgresql/$PG_VERSION/main/conf.d/postgresql.custom.conf
}

function setPostgresPassword() {
    sudo -u postgres psql -c "ALTER USER renderer PASSWORD '${PGPASSWORD:-renderer}'"
}


if [ "$1" = "db" ]; then
    # Clean /tmp
    rm -rf /tmp/*

    # Fix postgres data privileges
    chown -R postgres: /var/lib/postgresql/ /data/database/postgres/

    # Initialize PostgreSQL and Apache
    createPostgresConfig
    service postgresql start
    # service apache2 restart
    setPostgresPassword

    # Run while handling docker stop's SIGTERM
    stop_handler() {
        # kill -TERM "$child"
        service postgresql stop

        exit 0
    }

    trap stop_handler SIGTERM

    while true; do
        sleep 1  # Sleep keeps CPU usage low while waiting
    done

    # child=$!
    # wait "$child"

fi

echo "invalid command"
exit 1
