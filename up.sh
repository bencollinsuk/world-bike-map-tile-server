
eval $(minikube -p minikube docker-env)
docker volume create osm-data
docker volume create osm-tiles
docker compose up -d
echo 'http://localhost:8080/?lat=0&lng=0&zoom=2'
