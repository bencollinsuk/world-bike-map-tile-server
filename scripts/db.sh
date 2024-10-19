#!/bin/bash

set -euo pipefail

if [ "$1" = "db" ]; then

    if [ ! -f /DB_INITIALIZED ]; then
        # Ensure that database directory is in right state
        chown postgres:postgres -R /var/lib/postgresql

        if [ ! -f /var/lib/postgresql/12/main/PG_VERSION ]; then
            sudo -u postgres /usr/lib/postgresql/12/bin/pg_ctl -D /var/lib/postgresql/12/main/ initdb -o "--locale C.UTF-8"
        fi

        cp /etc/postgresql/$PG_VERSION/main/postgresql.custom.conf.tmpl /etc/postgresql/$PG_VERSION/main/conf.d/postgresql.custom.conf
        sudo -u postgres echo "autovacuum = $AUTOVACUUM" >> /etc/postgresql/$PG_VERSION/main/conf.d/postgresql.custom.conf
        cat /etc/postgresql/$PG_VERSION/main/conf.d/postgresql.custom.conf

        service postgresql start

        sudo -u postgres createuser renderer
        sudo -u postgres createdb -E UTF8 -O renderer gis
        sudo -u postgres psql -d gis -c "CREATE EXTENSION postgis;"
        sudo -u postgres psql -d gis -c "CREATE EXTENSION hstore;"
        sudo -u postgres psql -d gis -c "ALTER TABLE geometry_columns OWNER TO renderer;"
        sudo -u postgres psql -d gis -c "ALTER TABLE spatial_ref_sys OWNER TO renderer;"
        sudo -u postgres psql -c "ALTER USER renderer PASSWORD '${PGPASSWORD:-renderer}'"

        # Fix postgres data privileges
        chown -R postgres: /var/lib/postgresql/ /data/database/postgres/
    else
        service postgresql start
    fi

    # Run while handling docker stop's SIGTERM
    stop_handler() {
        # kill -TERM "$child"
        service postgresql stop

        exit 0
    }

    touch /DB_INITIALIZED

    trap stop_handler SIGTERM

    while true; do
        sleep 1 
    done
fi

echo "invalid command"
exit 1
