#!/bin/bash

set -euo pipefail

# if [ "$#" -ne 1 ]; then
#     echo "usage: <import|run>"
#     echo "commands:"
#     echo "    import: Set up the database and import /data/region.osm.pbf"
#     echo "    run: Runs Apache and renderd to serve tiles at /tile/{z}/{x}/{y}.png"
#     echo "environment variables:"
#     echo "    THREADS: defines number of threads used for importing / tile rendering"
#     echo "    UPDATES: consecutive updates (enabled/disabled)"
#     echo "    NAME_LUA: name of .lua script to run as part of the style"
#     echo "    NAME_STYLE: name of the .style to use"
#     echo "    NAME_MML: name of the .mml file to render to mapnik.xml"
#     echo "    NAME_SQL: name of the .sql file to use"
#     exit 1
# fi

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
sudo cat /home/renderer/.pgpass

# RESULT=$(PGPASSWORD=$PGPASSWORD psql -h $PGHOST -U $PGUSER -d gis -c "SELECT EXISTS (SELECT 1 FROM information_schema.views WHERE table_name = 'planet_osm_polygon');")

# # Trim whitespace from result
# RESULT=$(echo "$RESULT" | xargs)
PGPASSWORD=$PGPASSWORD

if ! psql -h $PGHOST -U $PGUSER -d gis -c 'SELECT ST_SRID("way") FROM planet_osm_polygon limit 1'; then

    if [ ! -f /osm-data/data.osm.pbf ] && [ -z "$DOWNLOAD_PBF" ]; then
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
        echo "INFO: Running wget $WGET_ARGS $DOWNLOAD_PBF -O /osm-data/data.osm.pbf"
        wget "$WGET_ARGS" "$DOWNLOAD_PBF" -O /osm-data/data.osm.pbf
        if [ -n "$DOWNLOAD_POLY" ]; then
                echo "INFO: Download PBF-POLY file: $DOWNLOAD_POLY"
            wget "$WGET_ARGS" "$DOWNLOAD_POLY" -O /data.poly
            fi
        echo "INFO: Download done"
    fi

    if [ "$UPDATES" = "enabled" ]; then
        # determine and set osmosis_replication_timestamp (for consecutive updates)
        osmium fileinfo /osm-data/data.osm.pbf > /var/lib/mod_tile/osm-data/data.osm.pbf.info
        osmium fileinfo /osm-data/data.osm.pbf | grep 'osmosis_replication_timestamp=' | cut -b35-44 > /var/lib/mod_tile/replication_timestamp.txt
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
        /osm-data/data.osm.pbf 

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


#     exit 0
# fi

# if [ "$1" == "render" ]; then
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

    # Define the UK bounding box in latitude and longitude
    west=-10.8545
    south=49.8634
    east=1.7620
    north=60.8606

    # Define zoom range
    min_zoom=0
    max_zoom=${MAX_ZOOM:-15}

    # Function to convert lat/lon to tile coordinates
    latlon_to_tile() {
        local lat=$1
        local lon=$2
        local zoom=$3

        # Calculate x and y tile numbers using Web Mercator projection
        local x=$(echo "($lon + 180) / 360 * (2 ^ $zoom)" | bc -l)
        local sin_lat=$(echo "s($lat * 4 * a(1) / 180)" | bc -l)
        local y=$(echo "(1 - l((1 + $sin_lat) / (1 - $sin_lat)) / (4 * a(1))) / 2 * (2 ^ $zoom)" | bc -l)

        # Convert to integer values
        x=$(printf "%.0f" "$x")
        y=$(printf "%.0f" "$y")
        echo "$x $y"
    }

    # Loop through each zoom level
    for zoom in $(seq $min_zoom $max_zoom); do
        # Calculate tile coordinates for the bounding box
        read min_x min_y <<< $(latlon_to_tile $north $west $zoom)
        read max_x max_y <<< $(latlon_to_tile $south $east $zoom)
        
        # Render tiles for the calculated tile range at the current zoom level
        echo "INFO: Rendering zoom level $zoom..."
        render_list -v -n ${THREADS:-4} -a -z $zoom -Z $zoom -x $min_x -y $min_y -X $max_x -Y $max_y
    done

fi

# if [ "$1" == "run" ]; then
    # Clean /tmp
    rm -rf /tmp/*

    echo "INFO: Waiting for PostgreSQL to be ready..."
    until PGPASSWORD=$PGPASSWORD psql -h $PGHOST -U $PGUSER -d gis -c 'SELECT ST_SRID("way") FROM planet_osm_polygon limit 1'; do
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
    sudo cat ~/.pgpass

    echo "INFO: Waiting for PostgreSQL to be ready..."
    until PGPASSWORD=$PGPASSWORD psql -h $PGHOST -U $PGUSER -d gis -c '\q'; do
        echo "INFO: PostgreSQL is not ready yet. Retrying..."
        sleep 3
    done

    echo "INFO: PostgreSQL is ready"

    service apache2 restart

    # Configure renderd threads
    sed -i -E "s/num_threads=[0-9]+/num_threads=${THREADS:-4}/g" /etc/renderd.conf
    # TODO!
    sed -i -E "s/localhost/$PGHOST/g" /etc/renderd.conf

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
# fi

echo "invalid command"
exit 1
