# my containers

the container i have on my server are:

- meld
- munin
- nextcloud
- plex
- qbittorrent

## meld

Just a test container that have ssh, fluxbox, and x11vnc installed. The objective of this container is to run a graphical app inside a docker container, remotely.

## munin

Is a utility to monitor the used resources of the server over time, it has a nice web interface and record the disk / network / cpu usage and many other things. This will be available only on the server or via ssh port forwarding of the port 9090.

## nextcloud

My private nextcloud server, it's the only services available from the web on port 80 and 8080. Because of this it need encription and strong security, this was done following the tutorial on their web site.

## plex

The plex instance is pretty much the standard one, the only particular thing is that the volume where it take the data point to the same folder where qbittorrent download it. This way whatever is downloaded with qbittorrent get automatically added to plex.

## qbittorrent

This is a custom image that allow the install of plugins inside of qbittorrent. This is done installing python in the dockerfile. Also it has support for jackett in the docker-compose.