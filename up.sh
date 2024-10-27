
# eval $(minikube -p minikube docker-env)

docker volume create osm-data
docker volume create osm-tiles
docker compose build
docker compose up -d

# Wait for localhost:8080 to be available
while ! curl -s http://localhost:8080 > /dev/null; do
    echo "Waiting for localhost:8080 to be available..."
    sleep 1
done

echo 'http://localhost:8080/?lat=0&lng=0&zoom=2'

