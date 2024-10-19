#!/bin/bash

set -euo pipefail

if [ "$#" -ne 1 ]; then
    echo "usage: <import|run>"
    echo "commands:"
    echo "    import: Set up the database and import /data.osm.pbf"
    echo "    run: Runs Apache and renderd to serve tiles at /tile/{z}/{x}/{y}.png"
    echo "environment variables:"
    echo "    THREADS: defines number of threads used for importing / tile rendering"
    echo "    UPDATES: consecutive updates (enabled/disabled)"
    exit 1
fi


if [ "$1" == "import" ]; then
    sleep 2

    if [ ! -f /data.osm.pbf ] && [ -z "$DOWNLOAD_PBF" ]; then
        echo "ERROR: No import file"
        exit 1
    fi

    if [ -n "$DOWNLOAD_PBF" ]; then
        echo "INFO: Download PBF file: $DOWNLOAD_PBF"
        wget "$WGET_ARGS" "$DOWNLOAD_PBF" -O /data.osm.pbf
        if [ -n "$DOWNLOAD_POLY" ]; then
            echo "INFO: Download PBF-POLY file: $DOWNLOAD_POLY"
            wget "$WGET_ARGS" "$DOWNLOAD_POLY" -O /data.poly
        fi
    fi

    if [ "$UPDATES" = "enabled" ]; then
        # determine and set osmosis_replication_timestamp (for consecutive updates)
        osmium fileinfo /data.osm.pbf > /var/lib/mod_tile/data.osm.pbf.info
        osmium fileinfo /data.osm.pbf | grep 'osmosis_replication_timestamp=' | cut -b35-44 > /var/lib/mod_tile/replication_timestamp.txt
        REPLICATION_TIMESTAMP=$(cat /var/lib/mod_tile/replication_timestamp.txt)

        # initial setup of osmosis workspace (for consecutive updates)
        sudo -u renderer openstreetmap-tiles-update-expire $REPLICATION_TIMESTAMP
    fi

    # copy polygon file if available
    if [ -f /data.poly ]; then
        sudo -u renderer cp /data.poly /var/lib/mod_tile/data.poly
    fi

    # Import data
    echo "INFO: Importing data..."
    sudo -E -u renderer osm2pgsql --cache ${CACHE:-8000} -H db -U renderer -d gis --create --slim -G --hstore \
        --number-processes ${THREADS:-8} \
        ${OSM2PGSQL_EXTRA_ARGS} \
        /data.osm.pbf

    echo "INFO: Importing data done. Creating indexes..."
    # sudo chmod 777 /root/.postgresql/postgresql.crt
    sudo -E -u postgres psql -d gis -f indexes.sql

    echo "INFO: Creating views..."
    sudo -E -u postgres psql -d gis -f views.sql
    sudo -E -u postgres psql -d gis -c "ALTER VIEW cyclosm_ways OWNER TO renderer;"
    sudo -E -u postgres psql -d gis -c "ALTER VIEW cyclosm_amenities_point OWNER TO renderer;"
    sudo -E -u postgres psql -d gis -c "ALTER VIEW cyclosm_amenities_poly OWNER TO renderer;"
    sudo -E -u postgres psql -d gis -c "ALTER VIEW cyclosm_ways OWNER TO renderer;"

    # Register that data has changed for mod_tile caching purposes
    touch /var/lib/mod_tile/planet-import-complete

    exit 0
fi

if [ "$1" = "run" ]; then

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
fi

if [ "$1" = "render" ]; then

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
fi

echo "invalid command"
exit 1
