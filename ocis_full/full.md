# Folder Structure

```
ocis_full
├── README.md
├── clamav.yml
├── collabora.yml
├── config
│   ├── ocis
│   │   ├── app-registry.yaml
│   │   ├── apps.yaml
│   │   ├── banned-password-list.txt
│   │   └── csp.yaml
│   └── onlyoffice
│       ├── entrypoint-override.sh
│       └── local.json
├── debug-collaboration-collabora.yml
├── debug-collaboration-onlyoffice.yml
├── debug-ocis.yml
├── docker-compose.yml
├── full.md
├── inbucket.yml
├── minio.yml
├── monitoring_tracing
│   ├── monitoring-oo.yml
│   └── monitoring.yml
├── onlyoffice.yml
├── s3ng.yml
├── tika.yml
└── web_extensions
    ├── drawio.yml
    ├── extensions.yml
    ├── externalsites.yml
    ├── importer.yml
    ├── jsonviewer.yml
    ├── progressbars.yml
    └── unzip.yml
```

## File: `README.md`
*(Relative Path: `README.md`)*

```markdown
---
document this deployment example in: docs/ocis/deployment/ocis_full.md
---

# Infinite Scale WOPI Deployment Example

This deployment example is documented in two locations for different audiences:

* In the [Admin Documentation](https://doc.owncloud.com/ocis/latest/index.html)\
  Providing two variants using detailed configuration step by step guides:\
  [Local Production Setup](https://doc.owncloud.com/ocis/next/depl-examples/ubuntu-compose/ubuntu-compose-prod.html) and [Deploy Infinite Scale on the Hetzner Cloud](https://doc.owncloud.com/ocis/next/depl-examples/ubuntu-compose/ubuntu-compose-hetzner.html).\
  Note that these examples use LetsEncrypt certificates and are intended for production use.

* In the [Developer Documentation](https://owncloud.dev/ocis/deployment/ocis_full/)\
  Providing details which are more developer focused. This description can also be used when deviating from the default.\
  Note that this examples uses self signed certificates and is intended for testing purposes.

```

---
## File: `clamav.yml`
*(Relative Path: `clamav.yml`)*

```
---
services:
  ocis:
    environment:
      ANTIVIRUS_SCANNER_TYPE: "clamav"
      ANTIVIRUS_CLAMAV_SOCKET: "/var/run/clamav/clamd.sock"
      # the antivirus service needs manual startup, see .env and ocis.yaml for START_ADDITIONAL_SERVICES
      # configure the antivirus service
      POSTPROCESSING_STEPS: "virusscan"
      # PROXY_TLS is set to "false", the download url has no https
      STORAGE_USERS_DATA_GATEWAY_URL: http://ocis:9200/data
    volumes:
      - "clamav-socket:/var/run/clamav"

  clamav:
    image: clamav/clamav:${CLAMAV_DOCKER_TAG:-latest}
    # release notes: https://blog.clamav.net
    networks:
      ocis-net:
    volumes:
      - "clamav-socket:/tmp"
      - "clamav-db:/var/lib/clamav"
    logging:
      driver: ${LOG_DRIVER:-local}
    restart: always

volumes:
  clamav-socket:
  clamav-db:

```

---
## File: `collabora.yml`
*(Relative Path: `collabora.yml`)*

```
---
services:
  traefik:
    networks:
      ocis-net:
        aliases:
          - ${COLLABORA_DOMAIN:-collabora.owncloud.test}
          - ${WOPISERVER_DOMAIN:-wopiserver.owncloud.test}
  ocis:
    environment:
      # make collabora the secure view app
      FRONTEND_APP_HANDLER_SECURE_VIEW_APP_ADDR: com.owncloud.api.collaboration.CollaboraOnline
      GRAPH_AVAILABLE_ROLES: "b1e2218d-eef8-4d4c-b82d-0f1a1b48f3b5,a8d5fe5e-96e3-418d-825b-534dbdf22b99,fb6c3e19-e378-47e5-b277-9732f9de6e21,58c63c02-1d89-4572-916a-870abc5a1b7d,2d00ce52-1fc2-4dbc-8b95-a73b73395f5a,1c996275-f1c9-4e71-abdf-a42f6495e960,312c0871-5ef7-4b3a-85b6-0e4074c64049,aa97fe03-7980-45ac-9e50-b325749fd7e6"

  collaboration:
    image: ${OCIS_DOCKER_IMAGE:-owncloud/ocis}:${OCIS_DOCKER_TAG:-latest}
    networks:
      ocis-net:
    depends_on:
      ocis:
        condition: service_started
      collabora:
        condition: service_healthy
    entrypoint:
      - /bin/sh
    command: [ "-c", "ocis collaboration server" ]
    environment:
      COLLABORATION_GRPC_ADDR: 0.0.0.0:9301
      COLLABORATION_HTTP_ADDR: 0.0.0.0:9300
      MICRO_REGISTRY: "nats-js-kv"
      MICRO_REGISTRY_ADDRESS: "ocis:9233"
      COLLABORATION_WOPI_SRC: https://${WOPISERVER_DOMAIN:-wopiserver.owncloud.test}
      COLLABORATION_APP_NAME: "CollaboraOnline"
      COLLABORATION_APP_PRODUCT: "Collabora"
      COLLABORATION_APP_ADDR: https://${COLLABORA_DOMAIN:-collabora.owncloud.test}
      COLLABORATION_APP_ICON: https://${COLLABORA_DOMAIN:-collabora.owncloud.test}/favicon.ico
      COLLABORATION_APP_INSECURE: "${INSECURE:-true}"
      COLLABORATION_CS3API_DATAGATEWAY_INSECURE: "${INSECURE:-true}"
      COLLABORATION_LOG_LEVEL: ${LOG_LEVEL:-info}
      OCIS_URL: https://${OCIS_DOMAIN:-ocis.owncloud.test}
    volumes:
      # configure the .env file to use own paths instead of docker internal volumes
      - ${OCIS_CONFIG_DIR:-ocis-config}:/etc/ocis
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.collaboration.entrypoints=https"
      - "traefik.http.routers.collaboration.rule=Host(`${WOPISERVER_DOMAIN:-wopiserver.owncloud.test}`)"
      - "traefik.http.routers.collaboration.tls.certresolver=http"
      - "traefik.http.routers.collaboration.service=collaboration"
      - "traefik.http.services.collaboration.loadbalancer.server.port=9300"
    logging:
      driver: ${LOG_DRIVER:-local}
    restart: always

  collabora:
    image: collabora/code:24.04.12.3.1
    # release notes: https://www.collaboraonline.com/release-notes/
    networks:
      ocis-net:
    environment:
      aliasgroup1: https://${WOPISERVER_DOMAIN:-wopiserver.owncloud.test}:443
      DONT_GEN_SSL_CERT: "YES"
      extra_params: |
        --o:ssl.enable=${COLLABORA_SSL_ENABLE:-true} \
        --o:ssl.ssl_verification=${COLLABORA_SSL_VERIFICATION:-true} \
        --o:ssl.termination=true \
        --o:welcome.enable=false \
        --o:net.frame_ancestors=${OCIS_DOMAIN:-ocis.owncloud.test}
      username: ${COLLABORA_ADMIN_USER:-admin}
      password: ${COLLABORA_ADMIN_PASSWORD:-admin}
    cap_add:
      - MKNOD
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.collabora.entrypoints=https"
      - "traefik.http.routers.collabora.rule=Host(`${COLLABORA_DOMAIN:-collabora.owncloud.test}`)"
      - "traefik.http.routers.collabora.tls.certresolver=http"
      - "traefik.http.routers.collabora.service=collabora"
      - "traefik.http.services.collabora.loadbalancer.server.port=9980"
    logging:
      driver: ${LOG_DRIVER:-local}
    restart: always
    command: ["bash", "-c", "coolconfig generate-proof-key ; /start-collabora-online.sh"]
    healthcheck:
      test: [ "CMD", "curl", "-f", "http://localhost:9980/hosting/discovery" ]

```

---
## File: `debug-collaboration-collabora.yml`
*(Relative Path: `debug-collaboration-collabora.yml`)*

```
---
services:

  collaboration:
    command: [ "-c", "dlv --listen=:40000 --headless=true --continue --check-go-version=false --api-version=2 --accept-multiclient exec /usr/bin/ocis collaboration server" ]
    environment:
      COLLABORATION_LOG_LEVEL: debug
    ports:
      - 40001:40000

```

---
## File: `debug-collaboration-onlyoffice.yml`
*(Relative Path: `debug-collaboration-onlyoffice.yml`)*

```
---
services:

  collaboration-oo:
    command: [ "-c", "dlv --listen=:40002 --headless=true --continue --check-go-version=false --api-version=2 --accept-multiclient exec /usr/bin/ocis collaboration server" ]
    environment:
      COLLABORATION_LOG_LEVEL: debug
    ports:
      - 40002:40002

```

---
## File: `debug-ocis.yml`
*(Relative Path: `debug-ocis.yml`)*

```
---
services:

  ocis:
    command: [ "-c", "ocis init || true; dlv --listen=:40000 --headless=true --continue --check-go-version=false --api-version=2 --accept-multiclient exec /usr/bin/ocis server" ]
    ports:
      - 40000:40000

```

---
## File: `docker-compose.yml`
*(Relative Path: `docker-compose.yml`)*

```
---
services:
  ocis:
    image: ${OCIS_DOCKER_IMAGE:-owncloud/ocis}:${OCIS_DOCKER_TAG:-latest}
    # changelog: https://github.com/owncloud/ocis/tree/master/changelog
    # release notes: https://doc.owncloud.com/ocis_release_notes.html
    networks:
      ocis-net:
    entrypoint:
      - /bin/sh
    # run ocis init to initialize a configuration file with random secrets
    # it will fail on subsequent runs, because the config file already exists
    # therefore we ignore the error and then start the ocis server
    command: ["-c", "ocis init || true; ocis server"]
    environment:
      # enable services that are not started automatically
      OCIS_ADD_RUN_SERVICES: ${START_ADDITIONAL_SERVICES}
      OCIS_URL: https://${OCIS_DOMAIN:-ocis.owncloud.test}
      OCIS_LOG_LEVEL: ${LOG_LEVEL:-info}
      OCIS_LOG_COLOR: "${LOG_PRETTY:-false}"
      OCIS_LOG_PRETTY: "${LOG_PRETTY:-false}"
      # do not use SSL between Traefik and oCIS
      PROXY_TLS: "false"
      # make the REVA gateway accessible to the app drivers
      GATEWAY_GRPC_ADDR: 0.0.0.0:9142
      # INSECURE: needed if oCIS / Traefik is using self generated certificates
      OCIS_INSECURE: "${INSECURE:-false}"
      # basic auth (not recommended, but needed for eg. WebDav clients that do not support OpenID Connect)
      PROXY_ENABLE_BASIC_AUTH: "${PROXY_ENABLE_BASIC_AUTH:-false}"
      # admin user password
      IDM_ADMIN_PASSWORD: "${ADMIN_PASSWORD:-admin}" # this overrides the admin password from the configuration file
      # demo users
      IDM_CREATE_DEMO_USERS: "${DEMO_USERS:-false}"
      # email server (if configured)
      NOTIFICATIONS_SMTP_HOST: "${SMTP_HOST}"
      NOTIFICATIONS_SMTP_PORT: "${SMTP_PORT}"
      NOTIFICATIONS_SMTP_SENDER: "${SMTP_SENDER:-oCIS notifications <notifications@${OCIS_DOMAIN:-ocis.owncloud.test}>}"
      NOTIFICATIONS_SMTP_USERNAME: "${SMTP_USERNAME}"
      NOTIFICATIONS_SMTP_INSECURE: "${SMTP_INSECURE}"
      # make the registry available to the app provider containers
      MICRO_REGISTRY_ADDRESS: 127.0.0.1:9233
      NATS_NATS_HOST: 0.0.0.0
      NATS_NATS_PORT: 9233
      PROXY_CSP_CONFIG_FILE_LOCATION: /etc/ocis/csp.yaml
      # these three vars are needed to the csp config file to include the web office apps and the importer
      COLLABORA_DOMAIN: ${COLLABORA_DOMAIN:-collabora.owncloud.test}
      ONLYOFFICE_DOMAIN: ${ONLYOFFICE_DOMAIN:-onlyoffice.owncloud.test}
      COMPANION_DOMAIN: ${COMPANION_DOMAIN:-companion.owncloud.test}
      # enable to allow using the banned passwords list
      OCIS_PASSWORD_POLICY_BANNED_PASSWORDS_LIST: banned-password-list.txt
    volumes:
      - ./config/ocis/app-registry.yaml:/etc/ocis/app-registry.yaml
      - ./config/ocis/csp.yaml:/etc/ocis/csp.yaml
      - ./config/ocis/banned-password-list.txt:/etc/ocis/banned-password-list.txt
      # configure the .env file to use own paths instead of docker internal volumes
      - ${OCIS_CONFIG_DIR:-ocis-config}:/etc/ocis
      - ${OCIS_DATA_DIR:-ocis-data}:/var/lib/ocis
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.ocis.entrypoints=https"
      - "traefik.http.routers.ocis.rule=Host(`${OCIS_DOMAIN:-ocis.owncloud.test}`)"
      - "traefik.http.routers.ocis.tls.certresolver=http"
      - "traefik.http.routers.ocis.service=ocis"
      - "traefik.http.services.ocis.loadbalancer.server.port=9200"
    logging:
      driver: ${LOG_DRIVER:-local}
    restart: always

volumes:
  certs:
  ocis-config:
  ocis-data:

networks:
  ocis-net:

```

---
## File: `inbucket.yml`
*(Relative Path: `inbucket.yml`)*

```
---
services:
  ocis:
    environment:
      NOTIFICATIONS_SMTP_HOST: inbucket
      NOTIFICATIONS_SMTP_PORT: 2500
      NOTIFICATIONS_SMTP_SENDER: oCIS notifications <notifications@${OCIS_DOMAIN:-ocis.owncloud.test}>
      NOTIFICATIONS_SMTP_USERNAME: notifications@${OCIS_DOMAIN:-ocis.owncloud.test}
      # the mail catcher uses self signed certificates
      NOTIFICATIONS_SMTP_INSECURE: "true"

  inbucket:
    image: inbucket/inbucket
    # changelog: https://github.com/inbucket/inbucket/blob/main/CHANGELOG.md
    networks:
      - ocis-net
    entrypoint:
      - /bin/sh
    command: [ "-c", "apk add openssl; openssl req -subj '/CN=inbucket.test' -x509 -sha256 -nodes -days 365 -newkey rsa:2048 -keyout /tmp/server.key -out /tmp/server.crt; /start-inbucket.sh" ]
    environment:
      INBUCKET_SMTP_TLSENABLED: "true"
      INBUCKET_SMTP_TLSPRIVKEY: /tmp/server.key
      INBUCKET_SMTP_TLSCERT: /tmp/server.crt
      INBUCKET_STORAGE_MAILBOXMSGCAP: 1000
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.inbucket.entrypoints=https"
      - "traefik.http.routers.inbucket.rule=Host(`${INBUCKET_DOMAIN:-mail.owncloud.test}`)"
      - "traefik.http.routers.inbucket.tls.certresolver=http"
      - "traefik.http.routers.inbucket.service=inbucket"
      - "traefik.http.services.inbucket.loadbalancer.server.port=9000"
    logging:
      driver: ${LOG_DRIVER:-local}
    restart: always

```

---
## File: `minio.yml`
*(Relative Path: `minio.yml`)*

```
---
services:
  minio:
    image: minio/minio:latest
    # release notes: https://github.com/minio/minio/releases
    networks:
      ocis-net:
    entrypoint:
      - /bin/sh
    command:
      [
        "-c",
        "mkdir -p /data/${S3NG_BUCKET:-ocis-bucket} && minio server --console-address ':9001' /data",
      ]
    volumes:
      - minio-data:/data
    environment:
      MINIO_ACCESS_KEY: ${S3NG_ACCESS_KEY:-ocis}
      MINIO_SECRET_KEY: ${S3NG_SECRET_KEY:-ocis-secret-key}
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.minio.entrypoints=https"
      - "traefik.http.routers.minio.rule=Host(`${MINIO_DOMAIN:-minio.owncloud.test}`)"
      - "traefik.http.routers.minio.tls.certresolver=http"
      - "traefik.http.routers.minio.service=minio"
      - "traefik.http.services.minio.loadbalancer.server.port=9001"
    logging:
      driver: ${LOG_DRIVER:-local}
    restart: always

volumes:
  minio-data:

```

---
## File: `onlyoffice.yml`
*(Relative Path: `onlyoffice.yml`)*

```
---
services:
  traefik:
    networks:
      ocis-net:
        aliases:
          - ${ONLYOFFICE_DOMAIN:-onlyoffice.owncloud.test}
          - ${WOPISERVER_ONLYOFFICE_DOMAIN:-wopiserver-oo.owncloud.test}

  collaboration-oo:
    image: ${OCIS_DOCKER_IMAGE:-owncloud/ocis}:${OCIS_DOCKER_TAG:-latest}
    networks:
      ocis-net:
    depends_on:
      ocis:
        condition: service_started
      onlyoffice:
        condition: service_healthy
    entrypoint:
      - /bin/sh
    command: [ "-c", "ocis collaboration server" ]
    environment:
      COLLABORATION_GRPC_ADDR: 0.0.0.0:9301
      COLLABORATION_HTTP_ADDR: 0.0.0.0:9300
      MICRO_REGISTRY: "nats-js-kv"
      MICRO_REGISTRY_ADDRESS: "ocis:9233"
      COLLABORATION_WOPI_SRC: https://${WOPISERVER_ONLYOFFICE_DOMAIN:-wopiserver-oo.owncloud.test}
      COLLABORATION_APP_NAME: "OnlyOffice"
      COLLABORATION_APP_PRODUCT: "OnlyOffice"
      COLLABORATION_APP_ADDR: https://${ONLYOFFICE_DOMAIN:-onlyoffice.owncloud.test}
      COLLABORATION_APP_ICON: https://${ONLYOFFICE_DOMAIN:-onlyoffice.owncloud.test}/web-apps/apps/documenteditor/main/resources/img/favicon.ico
      COLLABORATION_APP_INSECURE: "${INSECURE:-true}"
      COLLABORATION_CS3API_DATAGATEWAY_INSECURE: "${INSECURE:-true}"
      COLLABORATION_LOG_LEVEL: ${LOG_LEVEL:-info}
      COLLABORATION_APP_PROOF_DISABLE: "true"
      OCIS_URL: https://${OCIS_DOMAIN:-ocis.owncloud.test}
    volumes:
      # configure the .env file to use own paths instead of docker internal volumes
      - ${OCIS_CONFIG_DIR:-ocis-config}:/etc/ocis
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.collaboration-oo.entrypoints=https"
      - "traefik.http.routers.collaboration-oo.rule=Host(`${WOPISERVER_ONLYOFFICE_DOMAIN:-wopiserver-oo.owncloud.test}`)"
      - "traefik.http.routers.collaboration-oo.tls.certresolver=http"
      - "traefik.http.routers.collaboration-oo.service=collaboration-oo"
      - "traefik.http.services.collaboration-oo.loadbalancer.server.port=9300"
    logging:
      driver: ${LOG_DRIVER:-local}
    restart: always

  onlyoffice:
    # if you want to use oo enterprise edition, use: onlyoffice/documentserver-ee:<version>
    # note, you also need to add a volume, see below
    image: onlyoffice/documentserver:8.3.0
    # changelog https://github.com/ONLYOFFICE/DocumentServer/releases
    networks:
      ocis-net:
    entrypoint:
      - /bin/sh
      - /entrypoint-override.sh
    environment:
      WOPI_ENABLED: "true"
      # self-signed certificates
      USE_UNAUTHORIZED_STORAGE: "${INSECURE:-false}"
    volumes:
      # paths are relative to the main compose file
      - ./config/onlyoffice/entrypoint-override.sh:/entrypoint-override.sh
      - ./config/onlyoffice/local.json:/etc/onlyoffice/documentserver/local.dist.json
      # if you want to use oo enterprise edition, you need to add a volume for the license file
      # for details see: Registering your Enterprise Edition version -->
      # https://helpcenter.onlyoffice.com/installation/docs-enterprise-install-docker.aspx
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.onlyoffice.entrypoints=https"
      - "traefik.http.routers.onlyoffice.rule=Host(`${ONLYOFFICE_DOMAIN:-onlyoffice.owncloud.test}`)"
      - "traefik.http.routers.onlyoffice.tls.certresolver=http"
      - "traefik.http.routers.onlyoffice.service=onlyoffice"
      - "traefik.http.services.onlyoffice.loadbalancer.server.port=80"
      # websockets can't be opened when this is omitted
      - "traefik.http.middlewares.onlyoffice.headers.customrequestheaders.X-Forwarded-Proto=https"
      - "traefik.http.routers.onlyoffice.middlewares=onlyoffice"
    logging:
      driver: ${LOG_DRIVER:-local}
    restart: always
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost/hosting/discovery"]

```

---
## File: `s3ng.yml`
*(Relative Path: `s3ng.yml`)*

```
---
services:
  ocis:
    environment:
      # activate s3ng storage driver
      STORAGE_USERS_DRIVER: s3ng
      # keep system data on ocis storage since this are only small files atm
      STORAGE_SYSTEM_DRIVER: ocis
      # s3ng specific settings
      STORAGE_USERS_S3NG_ENDPOINT: ${S3NG_ENDPOINT:-http://minio:9000}
      STORAGE_USERS_S3NG_REGION: ${S3NG_REGION:-default}
      STORAGE_USERS_S3NG_ACCESS_KEY: ${S3NG_ACCESS_KEY:-ocis}
      STORAGE_USERS_S3NG_SECRET_KEY: ${S3NG_SECRET_KEY:-ocis-secret-key}
      STORAGE_USERS_S3NG_BUCKET: ${S3NG_BUCKET:-ocis-bucket}

```

---
## File: `tika.yml`
*(Relative Path: `tika.yml`)*

```
---
services:
  tika:
    image: ${TIKA_IMAGE:-apache/tika:latest-full}
    # release notes: https://tika.apache.org
    networks:
      ocis-net:
    restart: always
    logging:
      driver: ${LOG_DRIVER:-local}

  ocis:
    environment:
      # fulltext search
      SEARCH_EXTRACTOR_TYPE: tika
      SEARCH_EXTRACTOR_TIKA_TIKA_URL: http://tika:9998
      FRONTEND_FULL_TEXT_SEARCH_ENABLED: "true"

```

---
## File: `full.md`
*(Relative Path: `full.md`)*

```markdown

```

---
## File: `config/ocis/app-registry.yaml`
*(Relative Path: `config/ocis/app-registry.yaml`)*

```
app_registry:
  mimetypes:
  - mime_type: application/vnd.oasis.opendocument.text
    extension: odt
    name: OpenDocument
    description: OpenDocument text document
    icon: ''
    default_app: Collabora
    allow_creation: true
  - mime_type: application/vnd.oasis.opendocument.spreadsheet
    extension: ods
    name: OpenSpreadsheet
    description: OpenDocument spreadsheet document
    icon: ''
    default_app: Collabora
    allow_creation: true
  - mime_type: application/vnd.oasis.opendocument.presentation
    extension: odp
    name: OpenPresentation
    description: OpenDocument presentation document
    icon: ''
    default_app: Collabora
    allow_creation: true
  - mime_type: application/vnd.openxmlformats-officedocument.wordprocessingml.document
    extension: docx
    name: Microsoft Word
    description: Microsoft Word document
    icon: ''
    default_app: OnlyOffice
    allow_creation: true
  - mime_type: application/vnd.openxmlformats-officedocument.wordprocessingml.form
    extension: docxf
    name: Form Document
    description: Form Document
    icon: ''
    default_app: OnlyOffice
    allow_creation: false
  - mime_type: application/vnd.openxmlformats-officedocument.spreadsheetml.sheet
    extension: xlsx
    name: Microsoft Excel
    description: Microsoft Excel document
    icon: ''
    default_app: OnlyOffice
    allow_creation: true
  - mime_type: application/vnd.openxmlformats-officedocument.presentationml.presentation
    extension: pptx
    name: Microsoft PowerPoint
    description: Microsoft PowerPoint document
    icon: ''
    default_app: OnlyOffice
    allow_creation: true
  - mime_type: application/pdf
    extension: pdf
    name: PDF form
    description: PDF form document
    icon: ''
    default_app: OnlyOffice
    allow_creation: true
  - mime_type: application/vnd.jupyter
    extension: ipynb
    name: Jupyter Notebook
    description: Jupyter Notebook
    icon: ''
    default_app: ''
    allow_creation: true

```

---
## File: `config/ocis/apps.yaml`
*(Relative Path: `config/ocis/apps.yaml`)*

```
importer:
  config:
    companionUrl: https://${COMPANION_DOMAIN|companion.owncloud.test}
    supportedClouds:
      - WebdavPublicLink
      #- OneDrive # needs a client id and secret
      #- GoogleDrive # needs a client id and secret and an addition to the DNS zone
external-sites:
  config:
    sites:
      # For settings see: https://github.com/owncloud/web-extensions/tree/main/packages/web-app-external-sites
      - name: ownCloud
        url: "https://owncloud.dev"
        target: embedded
        color: "#0D856F"
        icon: cloud
        priority: 50
      - name: Wikipedia
        url: "https://www.wikipedia.org"
        target: external
        color: "#0D856F"
        icon: book
        priority: 51

```

---
## File: `config/ocis/banned-password-list.txt`
*(Relative Path: `config/ocis/banned-password-list.txt`)*

```
password
12345678
123
ownCloud
ownCloud-1

```

---
## File: `config/ocis/csp.yaml`
*(Relative Path: `config/ocis/csp.yaml`)*

```
directives:
  child-src:
    - '''self'''
  connect-src:
    - '''self'''
    - 'blob:'
    - 'https://${COMPANION_DOMAIN|companion.owncloud.test}/'
    - 'wss://${COMPANION_DOMAIN|companion.owncloud.test}/'
    - 'https://raw.githubusercontent.com/owncloud/awesome-ocis/'
  default-src:
    - '''none'''
  font-src:
    - '''self'''
  frame-ancestors:
    - '''self'''
  frame-src:
    - '''self'''
    - 'blob:'
    - 'https://embed.diagrams.net/'
    # In contrary to bash and docker the default is given after the | character
    - 'https://${ONLYOFFICE_DOMAIN|onlyoffice.owncloud.test}/'
    - 'https://${COLLABORA_DOMAIN|collabora.owncloud.test}/'
    # This is needed for the external-sites web extension when embedding sites
    - 'https://owncloud.dev'
  img-src:
    - '''self'''
    - 'data:'
    - 'blob:'
    - 'https://raw.githubusercontent.com/owncloud/awesome-ocis/'
    # In contrary to bash and docker the default is given after the | character
    - 'https://${ONLYOFFICE_DOMAIN|onlyoffice.owncloud.test}/'
    - 'https://${COLLABORA_DOMAIN|collabora.owncloud.test}/'
  manifest-src:
    - '''self'''
  media-src:
    - '''self'''
  object-src:
    - '''self'''
    - 'blob:'
  script-src:
    - '''self'''
    - '''unsafe-inline'''
  style-src:
    - '''self'''
    - '''unsafe-inline'''

```

---
## File: `config/onlyoffice/entrypoint-override.sh`
*(Relative Path: `config/onlyoffice/entrypoint-override.sh`)*

```
#!/bin/sh
set -e

# we can't mount it directly because the run-document-server.sh script wants to move it
cp /etc/onlyoffice/documentserver/local.dist.json /etc/onlyoffice/documentserver/local.json

/app/ds/run-document-server.sh

```

---
## File: `config/onlyoffice/local.json`
*(Relative Path: `config/onlyoffice/local.json`)*

```
{
  "services": {
    "CoAuthoring": {
      "sql": {
        "type": "postgres",
        "dbHost": "localhost",
        "dbPort": "5432",
        "dbName": "onlyoffice",
        "dbUser": "onlyoffice",
        "dbPass": "onlyoffice"
      },
      "token": {
        "enable": {
          "request": {
            "inbox": true,
            "outbox": true
          },
          "browser": true
        },
        "inbox": {
          "header": "Authorization"
        },
        "outbox": {
          "header": "Authorization"
        }
      },
      "secret": {
        "inbox": {
          "string": "B8LjkNqGxn6gf8bkuBUiMwyuCFwFddnu"
        },
        "outbox": {
          "string": "B8LjkNqGxn6gf8bkuBUiMwyuCFwFddnu"
        },
        "session": {
          "string": "B8LjkNqGxn6gf8bkuBUiMwyuCFwFddnu"
        }
      }
    }
  },
  "rabbitmq": {
    "url": "amqp://guest:guest@localhost"
  },
  "FileConverter": {
		"converter": {
			"inputLimits": [
				{
				"type": "docx;dotx;docm;dotm",
				"zip": {
					"uncompressed": "1GB",
					"template": "*.xml"
				}
				},
				{
				"type": "xlsx;xltx;xlsm;xltm",
				"zip": {
					"uncompressed": "1GB",
					"template": "*.xml"
				}
				},
				{
				"type": "pptx;ppsx;potx;pptm;ppsm;potm",
				"zip": {
					"uncompressed": "1GB",
					"template": "*.xml"
				}
				}
			]
		}
	}
}

```

---
## File: `monitoring_tracing/monitoring-oo.yml`
*(Relative Path: `monitoring_tracing/monitoring-oo.yml`)*

```
---

services:
  ocis:
    environment:
      # tracing
      OCIS_TRACING_ENABLED: "true"
      OCIS_TRACING_TYPE: "jaeger"
      OCIS_TRACING_ENDPOINT: jaeger-agent:6831
      # metrics
      # if oCIS runs as a single process, all  <debug>/metrics endpoints
      # will expose the same metrics, so it's sufficient to query one endpoint
      PROXY_DEBUG_ADDR: 0.0.0.0:9205

  collaboration-oo:
    environment:
      # tracing
      OCIS_TRACING_ENABLED: "true"
      OCIS_TRACING_TYPE: "jaeger"
      OCIS_TRACING_ENDPOINT: jaeger-agent:6831
      # metrics
      COLLABORATION_DEBUG_ADDR: 0.0.0.0:9304

networks:
  ocis-net:
    external: true

```

---
## File: `monitoring_tracing/monitoring.yml`
*(Relative Path: `monitoring_tracing/monitoring.yml`)*

```
---

services:
  ocis:
    environment:
      # tracing
      OCIS_TRACING_ENABLED: "true"
      OCIS_TRACING_TYPE: "jaeger"
      OCIS_TRACING_ENDPOINT: jaeger-agent:6831
      # metrics
      # if oCIS runs as a single process, all  <debug>/metrics endpoints
      # will expose the same metrics, so it's sufficient to query one endpoint
      PROXY_DEBUG_ADDR: 0.0.0.0:9205

  collaboration:
    environment:
      # tracing
      OCIS_TRACING_ENABLED: "true"
      OCIS_TRACING_TYPE: "jaeger"
      OCIS_TRACING_ENDPOINT: jaeger-agent:6831
      # metrics
      COLLABORATION_DEBUG_ADDR: 0.0.0.0:9304

networks:
  ocis-net:
    external: true

```

---
## File: `web_extensions/drawio.yml`
*(Relative Path: `web_extensions/drawio.yml`)*

```
---
services:
  ocis:
    depends_on:
      drawio-init:
        condition: service_completed_successfully

  drawio-init:
    image: owncloud/web-extensions:draw-io-0.3.0
    user: root
    volumes:
      - ocis-apps:/apps
    entrypoint:
      - /bin/sh
    command: ["-c", "cp -R /var/lib/nginx/html/draw-io/ /apps"]

```

---
## File: `web_extensions/extensions.yml`
*(Relative Path: `web_extensions/extensions.yml`)*

```
services:
  ocis:
    volumes:
      - ocis-apps:/var/lib/ocis/web/assets/apps

volumes:
  ocis-apps:

```

---
## File: `web_extensions/externalsites.yml`
*(Relative Path: `web_extensions/externalsites.yml`)*

```
---
services:
  ocis:
    depends_on:
      externalsites-init:
        condition: service_completed_successfully

  externalsites-init:
    image: owncloud/web-extensions:external-sites-0.3.0
    user: root
    volumes:
      - ocis-apps:/apps
    entrypoint:
      - /bin/sh
    command: ["-c", "cp -R /var/lib/nginx/html/external-sites/ /apps"]

```

---
## File: `web_extensions/importer.yml`
*(Relative Path: `web_extensions/importer.yml`)*

```
---
services:
  traefik:
    networks:
      ocis-net:
        aliases:
          - ${COMPANION_DOMAIN:-companion.owncloud.test}
  ocis:
    volumes:
      # the cloud importer needs to be enabled in the web.yaml
      - ./config/ocis/apps.yaml:/etc/ocis/apps.yaml
    depends_on:
      importer-init:
        condition: service_completed_successfully

  importer-init:
    image: owncloud/web-extensions:importer-0.1.0
    user: root
    volumes:
      - ocis-apps:/apps
    entrypoint:
      - /bin/sh
    command: [ "-c", "cp -R /var/lib/nginx/html/importer/ /apps" ]

  companion:
    image: ${COMPANION_IMAGE:-owncloud/uppy-companion:3.12.13-owncloud}
    networks:
      - ocis-net
    environment:
      NODE_ENV: production
      NODE_TLS_REJECT_UNAUTHORIZED: 0
      COMPANION_DATADIR: /tmp/companion/
      COMPANION_DOMAIN: ${COMPANION_DOMAIN:-companion.owncloud.test}
      COMPANION_PROTOCOL: https
      COMPANION_UPLOAD_URLS: "^https://${OCIS_DOMAIN:-ocis.owncloud.test}/"
      COMPANION_ONEDRIVE_KEY: "${COMPANION_ONEDRIVE_KEY}"
      COMPANION_ONEDRIVE_SECRET: "${COMPANION_ONEDRIVE_SECRET}"
    volumes:
      - companion-data:/tmp/companion/
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.companion.entrypoints=https"
      - "traefik.http.routers.companion.rule=Host(`${COMPANION_DOMAIN:-companion.owncloud.test}`)"
      - "traefik.http.routers.companion.tls.certresolver=http"
      - "traefik.http.routers.companion.service=companion"
      - "traefik.http.services.companion.loadbalancer.server.port=3020"
    logging:
      driver: ${LOG_DRIVER:-local}
    restart: always

volumes:
  companion-data:

```

---
## File: `web_extensions/jsonviewer.yml`
*(Relative Path: `web_extensions/jsonviewer.yml`)*

```
---
services:
  ocis:
    depends_on:
      jsonviewer-init:
        condition: service_completed_successfully

  jsonviewer-init:
    image: owncloud/web-extensions:json-viewer-0.3.0
    user: root
    volumes:
      - ocis-apps:/apps
    entrypoint:
      - /bin/sh
    command: ["-c", "cp -R /var/lib/nginx/html/json-viewer/ /apps"]

```

---
## File: `web_extensions/progressbars.yml`
*(Relative Path: `web_extensions/progressbars.yml`)*

```
---
services:
  ocis:
    depends_on:
      progressbars-init:
        condition: service_completed_successfully

  progressbars-init:
    image: owncloud/web-extensions:progress-bars-0.3.0
    user: root
    volumes:
      - ocis-apps:/apps
    entrypoint:
      - /bin/sh
    command: ["-c", "cp -R /var/lib/nginx/html/progress-bars/ /apps"]

```

---
## File: `web_extensions/unzip.yml`
*(Relative Path: `web_extensions/unzip.yml`)*

```
---
services:
  ocis:
    depends_on:
      unzip-init:
        condition: service_completed_successfully

  unzip-init:
    image: owncloud/web-extensions:unzip-0.4.0
    user: root
    volumes:
      - ocis-apps:/apps
    entrypoint:
      - /bin/sh
    command: ["-c", "cp -R /var/lib/nginx/html/unzip/ /apps"]

```

---
