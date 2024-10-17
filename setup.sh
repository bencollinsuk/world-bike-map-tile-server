#!/bin/bash

set -e

docker stop world-bike-map-tile-server-cyclosm || true

dir=$(pwd)

# docker volume rm osm-data
# docker volume create osm-data

docker build . -t bencollinsuk/world-bike-map-tile-server-cyclosm && \

# docker run --rm -e DOWNLOAD_PBF='' -e THREADS=12 -e "OSM2PGSQL_EXTRA_ARGS=-C 8192" -v $dir/run.sh:/run2.sh -v $dir/data.osm.pbf:/data.osm.pbf -v osm-data:/data/database/postgres --name world-bike-map-tile-server-cyclosm bencollinsuk/world-bike-map-tile-server-cyclosm import && \


docker run --rm --cpus="12" --shm-size="192m" -p 8080:80 -e THREADS=12 -e ALLOW_CORS=1 -e "OSM2PGSQL_EXTRA_ARGS=-C 8192" -v $dir/run.sh:/run2.sh -v osm-data:/data/database/postgres --name world-bike-map-tile-server-cyclosm bencollinsuk/world-bike-map-tile-server-cyclosm run