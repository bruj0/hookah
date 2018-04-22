#!/bin/sh -x
mkdir -p $HOME/apps
mkdir -p $HOME/certs
docker run -d -p 80:80 -p 443:443 -v $HOME/certs:/etc/nginx/certs -v /var/run/docker.sock:/tmp/docker.sock:ro jwilder/nginx-proxy
