# Building and installing kev-labs Docker container

You need up to 30GB of disk space for the container. If you need to move the container to a different location then change the

data-root

key in

/etc/docker/daemon.json


## Start your docker service. This depends on your system but likely either:

sudo dockerd

or 

sudo systemctl start docker

## Set your GitHub Personal Access Token:

export GH_TOKEN=<token>

## Then execute 

make build
