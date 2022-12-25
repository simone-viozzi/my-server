#! /bin/bash

docker-compose down
docker volume rm ocis_wopi_ocis-config ocis_wopi_wopi-recovery
rm -rf /data/wd-red/ocis/ocis-data/*

echo -e "\nDONE"