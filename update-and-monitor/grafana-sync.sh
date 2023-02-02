#!/bin/bash

source .env

dash_path="./grafana/provisioning/dashboards"
dash_path=$(realpath $dash_path)

datasource_path="./grafana/provisioning/datasources"
datasource_path=$(realpath $datasource_path)

notification_path="./grafana/provisioning/notifications"
notification_path=$(realpath $notification_path)

if [ ! -d "$dash_path" ]; then
    echo "ERROR: $dash_path does not exist"
    exit 1
fi

if [ ! -d "$datasource_path" ]; then
    echo "ERROR: $datasource_path does not exist"
    exit 1
fi

if [ ! -d "$notification_path" ]; then
    echo "ERROR: $notification_path does not exist"
    exit 1
fi

grafana-sync() {
    docker run --rm \
        --volume "$2:/data" \
        --network "monitor-net" \
        ghcr.io/mpostument/grafana-sync:1.4.10 \
        $1 \
        --apikey="$GRFANA_API" \
        --directory="/data" \
        --url http://grafana:3000
    
    sudo chown -R $USER:$USER "$2"

    if stat -t "$2"/*.json >/dev/null 2>&1; then
        for f in "$2"/*.json; do
            jq '.' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
        done
    fi
}

grafana-sync pull-dashboards $dash_path
grafana-sync pull-datasources $datasource_path
grafana-sync pull-notifications $notification_path
