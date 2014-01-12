#!/bin/bash

TOKEN=$1;

# Function call: Install SGE on Master node
#===================================================

# Install general package
apt-get update
apt-get -y install language-pack-en-base
/usr/sbin/locale-gen en_IN.UTF-8
/usr/sbin/update-locale LANG=en_IN.UTF-8

# Install Git
sudo apt-get -y install git

# Install JAVA
sudo apt-get -y install openjdk-6-jre

mkdir -p /etc/chef
echo -e "{\n\"gridengine\": {\n\"token_key\": \"$TOKEN\"},\n\"run_list\": [\n\"recipe[gridengine::master]\" ]\n}\n" >/etc/chef/node.json
echo -e "log_level       :info\nlog_location    STDOUT\nfile_cache_path \"/var/chef-solo\"\ncookbook_path   [\"/var/chef-repo/site-cookbooks\", \"/var/chef-repo/cookbooks\"]\nrole_path       \"/var/chef-repo/roles\"\njson_attribs    \"/etc/chef/node.json\"\n" > /etc/chef/solo.rb

 apt-get -y install build-essential
 apt-get -y install python-setuptools
 apt-get -y install git
 apt-get -y install curl
 apt-get -y install libxml2-dev
 apt-get -y install libxslt-dev
 export HOME=/root
 curl -L http://www.opscode.com/chef/install.sh | sudo bash -s - -v 10.18.0
 /opt/chef/embedded/bin/gem install aws-sdk --no-rdoc --no-ri
 /opt/chef/embedded/bin/gem install libwebsocket --version 0.1.5
 /opt/chef/embedded/bin/gem install pusher-client --version 0.2.1
 /opt/chef/embedded/bin/gem install librarian
 mkdir -p /var/chef-repo
 mkdir -p /var/chef
 mkdir -p /var/chef-solo
 git clone git://github.com/rpete/chef-repo.git /var/chef-repo
 chef-solo -l debug

