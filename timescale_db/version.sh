#!/bin/bash

echo "TimescaleDB default versions across PostgreSQL 13-17:"
echo "===================================================="

PG_VERSIONS=("13" "14" "15" "16" "17")

for pg_version in "${PG_VERSIONS[@]}"; do
    container_name="pg${pg_version}_check"
    
    docker run --name $container_name -e POSTGRES_PASSWORD=password -d timescale/timescaledb:latest-pg${pg_version} >/dev/null 2>&1
    
    if [ $? -eq 0 ]; then
        sleep 8
        
        # Extract just the TimescaleDB default version
        version=$(docker exec $container_name psql -U postgres -t -c "SELECT default_version FROM pg_available_extensions WHERE name = 'timescaledb';" 2>/dev/null | xargs)
        
        echo "PostgreSQL $pg_version: TimescaleDB $version"
        
        docker stop $container_name >/dev/null 2>&1
        docker rm $container_name >/dev/null 2>&1
    else
        echo "PostgreSQL $pg_version: Image not available"
    fi
done

echo "Done!"