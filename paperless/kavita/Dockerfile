FROM kizaing/kavita:latest

RUN apt-get update && \
    apt-get install libvips --no-install-recommends -y && \
    rm /kavita/libvips.so.42 && \
    rm -rf /var/lib/apt/lists/*
