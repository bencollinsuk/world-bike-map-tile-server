#!/bin/bash

set -euo pipefail

if [ "$#" -ne 1 ]; then
    echo "usage: <import|run>"
    echo "commands:"
    echo "    import: Set up the database and import /data/region.osm.pbf"
    echo "    run: Runs Apache and renderd to serve tiles at /tile/{z}/{x}/{y}.png"
    echo "environment variables:"
    echo "    THREADS: defines number of threads used for importing / tile rendering"
    echo "    UPDATES: consecutive updates (enabled/disabled)"
    echo "    NAME_LUA: name of .lua script to run as part of the style"
    echo "    NAME_STYLE: name of the .style to use"
    echo "    NAME_MML: name of the .mml file to render to mapnik.xml"
    echo "    NAME_SQL: name of the .sql file to use"
    exit 1
fi

# set -x

mkdir -p /home/renderer/src \
 && cd /home/renderer/src \
 && cd world-bike-map-cartocss-style \
 && sed -i 's/dbname: "osm"/dbname: "gis"/g' project.mml \
 && sed -i "s/database_host/$PGHOST/g" project.mml \
 && carto project.mml > mapnik.xml

cd /

sudo -E -u renderer echo "$PGHOST:5432:gis:$PGUSER:$PGPASSWORD" > /home/renderer/.pgpass
sudo chmod 0600 /home/renderer/.pgpass
sudo cat /home/renderer/.pgpass # postgres-service-blue:5432:gis:renderer:renderer

echo "INFO: Waiting for PostgreSQL to be ready..."
until PGPASSWORD=$PGPASSWORD psql -h $PGHOST -U $PGUSER -d gis -c '\q'; do
    echo "INFO: PostgreSQL is not ready yet. Retrying..."
    sleep 3
done

echo "INFO: PostgreSQL is ready"

if [ "$1" == import ]; then
    if [ ! -f /data.osm.pbf ] && [ -z "$DOWNLOAD_PBF" ]; then
        echo "ERROR: No import file"
        exit 1
    fi
 
    echo "INFO: Running carto"
    mkdir -p /home/renderer/src \
    && cd /home/renderer/src \
    && cd world-bike-map-cartocss-style \
    && sed -i 's/dbname: "osm"/dbname: "gis"/g' project.mml \
    && sed -i "s/database_host/$PGHOST/g" project.mml \
    && carto project.mml > mapnik.xml \
    && cd /

    if [ -n "${DOWNLOAD_PBF:-}" ]; then
        echo "INFO: Download PBF file: $DOWNLOAD_PBF"
    echo "INFO: Running wget $WGET_ARGS $DOWNLOAD_PBF -O /data.osm.pbf"
    wget "$WGET_ARGS" "$DOWNLOAD_PBF" -O /data.osm.pbf
    if [ -n "$DOWNLOAD_POLY" ]; then
            echo "INFO: Download PBF-POLY file: $DOWNLOAD_POLY"
        wget "$WGET_ARGS" "$DOWNLOAD_POLY" -O /data.poly
        fi
    echo "INFO: Download done"
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
    echo "INFO: Running osm2pgsql"
    sudo -E -u renderer osm2pgsql --verbose --cache ${CACHE:-8000} -d postgresql://$PGUSER:renderer@$PGHOST:5432/gis --create --slim -G --hstore \
        --number-processes ${THREADS:-8} \
        ${OSM2PGSQL_EXTRA_ARGS} \
        /data.osm.pbf 

    echo "INFO: Importing data done. Creating indexes..."
    # sudo chmod 777 /root/.postgresql/postgresql.crt
    sudo -E -u postgres psql -d gis -f /indexes.sql

    echo "INFO: Creating views..."
    sudo -E -u postgres psql -d gis -f views.sql
    echo "INFO: Finished creating views"
    sudo -E -u postgres psql -d gis -c "\dv"

    sudo -E -u postgres psql -d gis -c "ALTER VIEW cyclosm_ways OWNER TO renderer;"
    sudo -E -u postgres psql -d gis -c "ALTER VIEW cyclosm_amenities_point OWNER TO renderer;"
    sudo -E -u postgres psql -d gis -c "ALTER VIEW cyclosm_amenities_poly OWNER TO renderer;"
    sudo -E -u postgres psql -d gis -c "ALTER VIEW cyclosm_ways OWNER TO renderer;"
    sudo -E -u postgres psql -d gis -c "\dv"



    # Register that data has changed for mod_tile caching purposes
    touch /var/lib/mod_tile/planet-import-complete
    # sudo -u renderer touch /data/database/planet-import-complete


    exit 0
fi

if [ "$1" == "render" ]; then
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
    render_list -v -n ${THREADS:-4} -a -z 0 -Z ${MAX_ZOOM:-3}

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

if [ "$1" == "run" ]; then
    # Clean /tmp
    rm -rf /tmp/*

    echo "INFO: Waiting for PostgreSQL to be ready..."
    until PGPASSWORD=$PGPASSWORD psql -h $PGHOST -U $PGUSER -d gis -c '\q'; do
        echo "INFO: PostgreSQL is not ready yet. Retrying..."
        sleep 3
    done

    echo "INFO: PostgreSQL is ready"


    # # migrate old files
    # if [ -f /data/database/PG_VERSION ] && ! [ -d /data/database/postgres/ ]; then
    #     mkdir /data/database/postgres/
    #     mv /data/database/* /data/database/postgres/
    # fi
    # if [ -f /nodes/flat_nodes.bin ] && ! [ -f /data/database/flat_nodes.bin ]; then
    #     mv /nodes/flat_nodes.bin /data/database/flat_nodes.bin
    # fi
    # if [ -f /data/tiles/data.poly ] && ! [ -f /data/database/region.poly ]; then
    #     mv /data/tiles/data.poly /data/database/region.poly
    # fi

    # # sync planet-import-complete file
    # if [ -f /data/tiles/planet-import-complete ] && ! [ -f /data/database/planet-import-complete ]; then
    #     cp /data/tiles/planet-import-complete /data/database/planet-import-complete
    # fi
    # if ! [ -f /data/tiles/planet-import-complete ] && [ -f /data/database/planet-import-complete ]; then
    #     cp /data/database/planet-import-complete /data/tiles/planet-import-complete
    # fi

    # # Fix postgres data privileges
    # chown -R postgres: /var/lib/postgresql/ /data/database/postgres/

    # Configure Apache CORS
    if [ "$ALLOW_CORS" == "enabled" ] || [ "$ALLOW_CORS" == "1" ]; then
        echo "export APACHE_ARGUMENTS='-D ALLOW_CORS'" >> /etc/apache2/envvars
    fi

    echo "INFO: Writing pgpass file..."
    echo "$PGHOST:5432:gis:$PGUSER:$PGPASSWORD" > ~/.pgpass
    sudo chmod 0600 ~/.pgpass
    whoami
    sudo cat ~/.pgpass # postgres-service-blue:5432:gis:renderer:renderer

    echo "INFO: Waiting for PostgreSQL to be ready..."
    until PGPASSWORD=$PGPASSWORD psql -h $PGHOST -U $PGUSER -d gis -c '\q'; do
        echo "INFO: PostgreSQL is not ready yet. Retrying..."
        sleep 3
    done

    echo "INFO: PostgreSQL is ready"

    service apache2 restart

    # Configure renderd threads
    sed -i -E "s/num_threads=[0-9]+/num_threads=${THREADS:-4}/g" /etc/renderd.conf

    # start cron job to trigger consecutive updates
    if [ "${UPDATES:-}" == "enabled" ] || [ "${UPDATES:-}" == "1" ]; then
        /etc/init.d/cron start
        sudo -u renderer touch /var/log/tiles/run.log; tail -f /var/log/tiles/run.log >> /proc/1/fd/1 &
        sudo -u renderer touch /var/log/tiles/osmosis.log; tail -f /var/log/tiles/osmosis.log >> /proc/1/fd/1 &
        sudo -u renderer touch /var/log/tiles/expiry.log; tail -f /var/log/tiles/expiry.log >> /proc/1/fd/1 &
        sudo -u renderer touch /var/log/tiles/osm2pgsql.log; tail -f /var/log/tiles/osm2pgsql.log >> /proc/1/fd/1 &
    fi

    # Run while handling docker stop's SIGTERM
    stop_handler() {
        kill -TERM "$child"
    }
    trap stop_handler SIGTERM

    sleep 2

    echo "Starting renderd"
    cat /etc/renderd.conf
    PGPASSWORD=$PGPASSWORD
    sudo -u renderer renderd -f -c /etc/renderd.conf &

    child=$!
    wait "$child"

    exit 0
fi

echo "invalid command"
exit 1
