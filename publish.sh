#!/bin/bash

set -e

docker compose build

# gcloud auth login
gcloud config set project simple-cycle-map-365616
gcloud auth configure-docker europe-central2-docker.pkg.dev
# gcloud container clusters get-credentials wbm-k8s --zone europe-central2


docker tag world-bike-map-tile-server-db:latest europe-central2-docker.pkg.dev/simple-cycle-map-365616/wbm-osm/world-bike-map-tile-server-db:latest

docker tag world-bike-map-tile-server:latest europe-central2-docker.pkg.dev/simple-cycle-map-365616/wbm-osm/world-bike-map-tile-server:latest

docker push europe-central2-docker.pkg.dev/simple-cycle-map-365616/wbm-osm/world-bike-map-tile-server-db:latest

docker push europe-central2-docker.pkg.dev/simple-cycle-map-365616/wbm-osm/world-bike-map-tile-server:latest
