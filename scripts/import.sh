#!/bin/bash

set -euo pipefail

if [ ! -f /data.osm.pbf ] && [ -z "$DOWNLOAD_PBF" ]; then
    echo "ERROR: No import file"
    exit 1
fi

if [ -n "$DOWNLOAD_PBF" ]; then
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
echo "INFO: Importing data..."
sudo -E -u renderer osm2pgsql --cache ${CACHE:-8000} -H $PGHOST -U $PGUSER -d gis --create --slim -G --hstore \
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
