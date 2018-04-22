#!/bin/bash
echo "This will install the needed hooks to your HOME directory"
echo "Press ctrl+c if thats not what you want"
cp -r hookah/git-hell-commands $HOME/
cp -r helpers $HOME/
cp nginxproxy.sh $HOME/
mkdir $HOME/apps
mkdir $HOME/certs
