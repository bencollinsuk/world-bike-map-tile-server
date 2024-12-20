#!/bin/bash

set -euo pipefail


if [ ! -f /DB_INITIALIZED ]; then

    # Ensure that database directory is in right state
    mkdir -p /data/database/postgres/
    chown renderer: /data/database/
    chown -R postgres: /var/lib/postgresql /data/database/postgres/
    if [ ! -f /data/database/postgres/PG_VERSION ]; then
        sudo -u postgres /usr/lib/postgresql/$PG_VERSION/bin/pg_ctl -D /data/database/postgres/ initdb -o "--locale C.UTF-8"
    fi

    cp /etc/postgresql/$PG_VERSION/main/postgresql.custom.conf.tmpl /etc/postgresql/$PG_VERSION/main/conf.d/postgresql.custom.conf
    sudo -u postgres echo "autovacuum = $AUTOVACUUM" >> /etc/postgresql/$PG_VERSION/main/conf.d/postgresql.custom.conf
    cat /etc/postgresql/$PG_VERSION/main/conf.d/postgresql.custom.conf

    echo "INFO: Initializing database..."
    service postgresql start

    sudo -u postgres psql -c "ALTER SYSTEM SET work_mem='${PG_WORK_MEM:-256MB}';"
    sudo -u postgres psql -c "ALTER SYSTEM SET maintenance_work_mem='${PG_MAINTENANCE_WORK_MEM:-1024MB}';"

    # sudo -u postgres createuser renderer
    sudo -u postgres psql -c "CREATE ROLE renderer WITH LOGIN PASSWORD '${PGPASSWORD:-renderer}'";
    sudo -u postgres createdb -E UTF8 -O renderer gis
    sudo -u postgres psql -d gis -c "CREATE EXTENSION postgis;"
    sudo -u postgres psql -d gis -c "CREATE EXTENSION hstore;"
    sudo -u postgres psql -d gis -c "ALTER TABLE geometry_columns OWNER TO renderer;"
    sudo -u postgres psql -d gis -c "ALTER TABLE spatial_ref_sys OWNER TO renderer;"
    sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE gis TO renderer;"

    # Fix postgres data privileges
    chown -R postgres: /var/lib/postgresql/ /data/database/postgres/
else
    echo "INFO: Starting PostgreSQL... $PGPASSWORD"
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

echo "ERROR: Invalid command"
exit 1
