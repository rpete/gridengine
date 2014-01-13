GridEngine
===========

** These scripts assume gcutil is already configured and ready to go in your current path **
These scripts use the chef-repo git repo to create a GridEngine cluster with master 
and N-nodes without using NFS.

Documentations
=====================

For simple test you may just clone the GridEngine repo and edit the config.txt file to reflect the number of nodes
you want and the type of VM you need. 

git clone git://github.com/rpete/gridengine.git

# adds gce key to ssh-agent
$. env.sh

# Now create some instances
$bin/setup.pl config.txt 100

# Now install GridEngine on the nodes
$bin/setup.pl config.txt 201


# To delete ALL GridEngine nodes and disks associated
$bin/setup.pl config.txt 101

**NOTE: The master node is the first node
