#!/bin/bash

set -euo pipefail

# set -x

echo "INFO: Running carto"
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

# # if ! psql -h $PGHOST -U $PGUSER -d gis -c 'SELECT ST_SRID("way") FROM planet_osm_polygon limit 1'; then
# if [ "$1" == "import" ]; then
rm /import-status/ready || true

if [ ! -f /osm-data/data.osm.pbf ] && [ -z "$DOWNLOAD_PBF" ]; then
    echo "ERROR: No import file"
    exit 1
fi

echo "INFO: Importing data..."

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
echo "INFO: Importing data done"
touch /import-status/ready

# sudo -u renderer touch /data/database/planet-import-complete

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

echo "INFO: Starting renderd with render_list using ${THREADS:-4} threads..."

sudo -u renderer renderd -c /etc/renderd.conf && 
# render_list --help

# Loop through each zoom level
for zoom in $(seq 0 $MAX_ZOOM); do
    # Render tiles for the calculated tile range at the current zoom level
    echo "INFO: Rendering zoom level $zoom..."
    perl /render_list_geo.pl -m default -t /var/lib/mod_tile/ -n ${THREADS:-4} -z $zoom -Z $zoom -x -10.8545 -X 1.7620 -y 49.8634 -Y 60.8606
    # render_list -v -n ${THREADS:-4} -a -z $zoom -Z $zoom -x $min_x -y $min_y -X $max_x -Y $max_y
done

echo "INFO: Rendering done"
exit 0
