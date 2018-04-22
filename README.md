# Instant App deployment from GIT
by Rodrigo A. Diaz Leven 

- - [Instant App deployment from GIT](#instant-app-deployment-from-git)
  * [Introduction](#introduction)
  * [Diagram of workflow](#diagram-of-workflow)
  * [Server configuration](#server-configuration)
    + [Pre requisites](#pre-requisites)
    + [Installation](#installation)
  * [Deployment](#deployment)
  * [How it works](#how-it-works)
    + [Git Shell command: newapp](#git-shell-command--newapp)
    + [Git Hook for post-receive](#git-hook-for-post-receive)
    + [Nginx-Proxy](#nginx-proxy)
## Introduction

This article is about how to deploy to a server directly from our GIT client, either from command line or from a GUI.

We will use docker-compose to orchestrate our fleet of Docker containers  and deploy directly to our server.

This could be useful for a simple app we are creating or a small service we need to deploy and test outside of our development machine.

Almost everything will be automated, including the Nginx configuration which is handled by a very useful project called Nginx-Proxy https://github.com/jwilder/nginx-proxy

This creates a container with an added application that listen to Docker events and creates configuration on the fly for Nginx using environment variables for our apps.

## Diagram of workflow

![](https://raw.githubusercontent.com/bruj0/hookah/master/Direct%20Deployment%20with%20Git.png)

## Server configuration

### Pre requisites

We need to install GIT , Docker and Docker-compose.

Please check their documentation for installation instructions:

- https://git-scm.com/downloads
- https://docs.docker.com/install/
- https://docs.docker.com/compose/install/

Ideally you would have a domain name wildcard record pointed to the public IP address of this server, either at the root level or a subdomain:

```
*.apps  IN  A   MY_SERVER_IP_ADDRESS
```

This way you will not need to add an A record for each of your apps and you can directly access them after deployment trough: test.apps.example.com

Optionally, it helps to have a wildcard SSL certificate for the same reasons.

You can get a free one from Lets Encrypt using docker, you will need to prove that you are the owner of the domain by adding TXT records to the domain.

```
# docker run -it --rm --name letsencrypt \
	-v "/etc/letsencrypt:/etc/letsencrypt" \
	-v "/var/lib/letsencrypt:/var/lib/letsencrypt" \
	quay.io/letsencrypt/letsencrypt:latest \
		certonly \
		-d example.com \
		-d *.example.com \
		--manual \
		--preferred-challenges dns \
		--server https://acme-v02.api.letsencrypt.org/directory
```

### Installation

We need to create a new user that will run our applications, we will use hookah for this article but you can choose what you want or use one already created.

This user will use git-shell as his shell so it can run our hooks.

```bash
# useradd -m -s /usr/bin/git-shell hookah
```

Switch to the new user with su:

```bash
# su -s /bin/bash hookah
```

Clone the repo for this project and install the hooks:

```
$ git clone https://github.com/bruj0/hookah.git
$ cd hookah
$ ./install-hookah.sh
```

This will install everything to your HOME directory:

- apps -> where our apps will live
- certs -> SSL certificates if you want to use HTTPS
- git-shell-commands -> The scripts that creates defaults for our apps
- helpers -> The GIT hooks what will deploy our server
- vhosts.d -> Virtual Host customizations

Start the Nginx-Proxy container

```
$ $HOME/nginxproxy.sh
```

Optional add your ssh public key to the authorized keys for this user to $HOME/.ssh/authorized_keys

## Deployment

For testing this we will use a very simple application for file sharing called Linx https://github.com/andreimarcu/linx-server

From our development machine:

```bash
$ ssh hookah@apps.example.com "newapp files"
Adding new app files
Creating directory /home/hookah/apps/files
Creating GIT repository
Initialized empty Git repository in /home/hookah/apps/files/
Copying hooks
Symlinking ssl certs
$ mkdir linx
$ cd linx
$ git init
$ git remote add hookah hookah@apps.example.com:apps/files
$ vi Dockerfile
$ vi docker-compose.yml
```

Dockerfile:

```dockerfile
FROM golang:alpine

RUN set -ex \
        && apk add --no-cache --virtual .build-deps git \
        && go get github.com/andreimarcu/linx-server \
        && apk del .build-deps
RUN mkdir -p /data/files && mkdir -p /data/meta && chown -R 65534:65534 /data

VOLUME ["/data/files", "/data/meta"]

EXPOSE 8080
USER nobody
```

docker-compose.yml:

```yaml
version: "3"
services:
  files:
    build: .
    volumes:
      - files:/data/files
      - meta:/data/meta
    entrypoint:
      - "/go/bin/linx-server"
      - "-bind=0.0.0.0:8080"
      - "-filespath=/data/files/"
      - "-metapath=/data/meta/"
      - "-sitename=Files"
      - "-allowhotlink"
      - "-realip"
      - "-siteurl=https://files.example.com"
    ports:
      - "8080:8080"
    environment:
      - VIRTUAL_HOST=files.example.com
      - VIRTUAL_PORT=8080
    network_mode: "bridge"
volumes:
  files:
  meta:
```

Notice here the environment variables VIRTUAL_HOST and VIRTUAL_PORT which should point to the FQDN of our application and the container port , in this case 8080.

Finally we deploy:

```bash
$ git commit -am "first commit"
$ git push hookah master
Counting objects: 5, done.
Delta compression using up to 2 threads.
Compressing objects: 100% (3/3), done.
Writing objects: 100% (5/5), 579 bytes | 579.00 KiB/s, done.
Total 5 (delta 0), reused 0 (delta 0)
remote: Hooking compose with 0000000000000000000000000000000000000000 2b814aad59842f6148fab6d1fe2a7b2faba09055 refs/heads/master
remote: Ref refs/heads/master received. Deploying master branch to production...
remote: files uses an image, skipping
remote: Pulling files (andreimarcu/linx-server:latest)...
remote: latest: Pulling from andreimarcu/linx-server
remote: Digest: sha256:92cab16dc0a2b557f494ff8b2edc13c5028e79d4e5b89d80215836576c8d5108
remote: Status: Downloaded newer image for andreimarcu/linx-server:latest
remote: Creating files_src_files_1 ... 
remote: 
To apps.example.com:apps/files
 * [new branch]      master -> master
```

If everything worked you can open a browser to http://files.example.com and you will this

![](https://cloud.githubusercontent.com/assets/4650950/10530123/4211e946-7372-11e5-9cb5-9956c5c49d95.png)

## How it works

### Git Shell command: newapp

When we execute the "newapp" command using ssh a script is called that will:

- Create a GIT repository for the application in the server
- Copy a scripts that will hook the post-receive hook in this repository
- Create a directory from where it will be run, under $HOME/apps
- Copy SSL certificates

$HOME/git-shell-commands/newapp

```bash
#!/bin/bash
DOMAIN="example.com"
APP_DIR=$HOME/apps
echo "Adding new app $1"
echo "Creating $APP_DIR/$1"
mkdir -p $APP_DIR/$1
cd $APP_DIR/$1

echo "Creating repository"
git init --bare

echo "Copying hooks"
cp $HOME/helpers/post-receive $APP_DIR/$1/hooks/

echo "Symlinking ssl certs"
ln -s /etc/letsencrypt/archive/$DOMAIN/fullchain1.pem $HOME/certs/$1.$DOMAIN.crt.
ln -s etc/letsencrypt/archive/$DOMAIN/privkey1.pem $HOME/certs/$1.$DOMAIN.key.

```

### Git Hook for post-receive

This hook is a bash script that will run after our the push operation is finished.

We then checkout a copy of this data to a separate directory from where we call docker-compose and anything else needed for this application to be deployed.

As a precaution we check that the branch that we deploy is master but this is optional.

```bash
#!/bin/bash
BRANCH="master"
GIT_DIR=$(pwd)
TARGET="${GIT_DIR}_src"
while read oldrev newrev ref
do
    # only checking out the master (or whatever branch you would like to deploy)
     if [[ $ref = refs/heads/"$BRANCH" ]];
     then
        echo "Hooking compose with $oldrev $newrev $ref"
        #$HOME/go/bin/compose-hook "$oldrev" "$newrev" "$ref"
        echo "Ref $ref received. Deploying ${BRANCH} branch to production..."
        mkdir -p $TARGET
    	/usr/bin/git --work-tree=$TARGET --git-dir=$GIT_DIR checkout -f
    	cd $TARGET
    	/usr/bin/docker-compose build
    	/usr/bin/docker-compose up --detach --force-recreate
     else
         echo "Ref $ref received. Doing nothing: only the ${BRANCH} branch may be deployed on this server."
     fi
done

```

### Nginx-Proxy

As the description of this project says:

> nginx-proxy sets up a container running nginx and [docker-gen](https://github.com/jwilder/docker-gen). docker-gen generates reverse proxy configs for nginx and reloads nginx when containers are started and stopped.
>
> 

If we look at the logs of this container we can see it in action:

```
$ docker logs nginx-proxy
dockergen.1 | 2018/04/22 02:34:58 Received event start for container 36448e307719
dockergen.1 | 2018/04/22 02:34:58 Generated '/etc/nginx/conf.d/default.conf' from 4 containers
dockergen.1 | 2018/04/22 02:34:58 Running 'nginx -s reload'
```

