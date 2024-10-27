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

echo "INFO: Starting renderd"
cat /etc/renderd.conf
PGPASSWORD=$PGPASSWORD
sudo -u renderer renderd -f -c /etc/renderd.conf &

child=$!
wait "$child"

exit 0
