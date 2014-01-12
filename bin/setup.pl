#!/bin/env perl 

use Data::Dumper;
use strict;
use warnings;
use Parallel::ForkManager;

my $MODE_INSTANCES_CREATE = 100;

my $MODE_INSTANCES_DELETE = 101;

# instance specific 
my $MODE_MOUNT_EPHEMERAL_DISK = 102;
my $MODE_INSTALL_SGE = 201;
my $MODE_ADD_MULTIPLE_INSTANCES = 202;



my $SGE_INSTALLATION_POSTFIX = "GoogleCloud.SGE.installation.log";

# we need at least 2 arguments 
my $num_args = $#ARGV + 1;
if ($num_args < 2) {
	usage();
	exit(1);
}

# Config file
my $configFile = $ARGV[0];

# Mode 
my $mode = $ARGV[1];

# parse the config file
my ($zone, $ami, $instanceType, $numberOfCores, $instanceNamePrefix, $numberOfInstances, $master_node, $compute_nodes) = parseConfigFile($configFile);

# Get a local user
my $local_user = $ENV{LOGNAME};

# Print out the attributes after pasing the config file.
# For debugging purpose 
print "\n";
print "\nZONE:\t\t\t$zone";
print "\nAMI\t\t\t$ami";
print "\nINSTANCE NAME PREFIX\t$instanceNamePrefix";
print "\nINSTANCE TYPE\t\t$instanceType [ $numberOfCores core(s) ]";
print "\nNUMBER OF INSTANCES\t$numberOfInstances [ total number of cores " . $numberOfInstances * $numberOfCores . " ]";
print "\n\n";


# Get all the running instances 
my @instanceNames = getInstanceNames($zone);
	
# Perform different functions according to function mode
if ($mode == $MODE_INSTANCES_DELETE) {
	# Delete instance
	deleteInstances(\@instanceNames, $instanceNamePrefix, $zone);
} elsif ($mode == $MODE_INSTANCES_CREATE) {
	# Create instance
#	if (Check_Resources("instance", $numberOfInstances) && Check_Resources("cpu", $numberOfInstances*$numberOfCores)) {
		createInstances($zone, $ami, $instanceType, $instanceNamePrefix, $numberOfInstances);
#	}
} elsif ($mode == $MODE_MOUNT_EPHEMERAL_DISK) {
	# Mount ephemeral disks
	if ($num_args != 3) {
		print "\n\nplease include path prefix to mount emepheral devices...\n";
		usage();
		exit (0);
	} 
	my $path = $ARGV[2];
	create_mount_ephemeral(\@instanceNames, $instanceNamePrefix, $zone, $path, $numberOfInstances );
} elsif ($mode == $MODE_INSTALL_SGE) {
	create_SGE(\@instanceNames, $configFile, $instanceNamePrefix, $numberOfCores, $local_user);
} elsif ($mode == $MODE_ADD_MULTIPLE_INSTANCES) {
	print "\n\nAdding more compute power to existing SGE Cluster.";
	print "\nHow many instances would you want to add (1, 2, 3, ...)? ";
	chomp($numberOfInstances = <STDIN>);
	if (Check_Resources("cpu", $numberOfInstances*$numberOfCores) && Check_Resources("instance", $numberOfInstances)) {
		createInstances($zone, $ami, $instanceType, $instanceNamePrefix, $numberOfInstances);
		@instanceNames = getInstanceNames($zone);
		update_SGE (\@instanceNames, "add", $local_user, $numberOfInstances);
	}
} else {
	print "\n\n====================================================\n";
	print "\n\nInvalid input MODE!!!! Please see usage below\n";
	usage();
}


#
# usage 
#
sub usage {
	print "\n";
	print "\nThis script setup Google Cloud instances and Sun Grid Engine (SGE)";
	print "\n\nUsage: $0 [ FILE ] [ MODE ] ";
	print "\n\n\t[FILE]\t\tconfig file";
	print "\n\t[MODE]\t$MODE_INSTANCES_CREATE\tcreate instances based on the input configuration file";
	print "\n\t\t$MODE_INSTANCES_DELETE\tdelete all instances based on the instance prefix defined in the input configuration file";
	#print "\n\t\t$MODE_UPDATE_INSTANCE\tupdate packages on instance ";
	#print "\n\t\t$MODE_UPDATE_ETC_HOSTS\tupdate /etc/host file on an instance for SGE installation";
	print "\n\t\t$MODE_MOUNT_EPHEMERAL_DISK\tmount available ephemeral disk to individual instances";
	print "\n\t\t\t[PATH]\tpath prefix to mount ephemeral disk(s) to";
	print "\n";
	print "\n\t\t$MODE_INSTALL_SGE\tinstall Sun Grid Engine (SGE) on the instances created. ";
	print "\n\t\t$MODE_ADD_MULTIPLE_INSTANCES\tadd additional instances to the SGE cluster. ";
	print "\n\n";
	exit (2);
}


#
# Check Zone 
#
sub Check_Zone {

	my $my_zone = shift;
    my $available_zone;
    my $status;

    my @list_zones = `gcutil listzones | awk '{print \$2 \"\t\" \$6}'`;
    foreach my $i (@list_zones) {
        my @line = split("\t", $i);
        if (($i =~ /^us/) || ($i =~ /^europe/)) {
            $available_zone = $line[0];
            chomp($available_zone);
            # print "$available_zone";
            $status = $line[1];
            chomp($status);
            # print "$status";

            if (($available_zone eq $my_zone) && ($status eq "UP")) {
                return;
            } else {
                # Did not match;
            }
        }
    }
    # WARNING: us-central1-a is unavailable due to maintenance.

    print "\nWARNING:";
    print "\n\t$my_zone is unavailable due to maintenance.";
    print "\n\tPlease select different zones\n\n";
    exit 1;
}




#
# Check Resources
#
sub Check_Resources {

	my $property = shift;
	my $required_resource = shift;
	my $project_resources;
	my $current_resource;
	my $overall_resource;
	my $diff;
	my @line;


	$project_resources = `gcutil getproject | grep $property | awk '{print \$4}'`;
	chomp($project_resources);
	$project_resources =~ s/\n\|$//;
	@line = split("/", $project_resources);
	$current_resource = $line[0];
	$overall_resource = $line[1];
	$diff = $overall_resource - $current_resource;

	if ($property =~ /instance/) {
		if ($diff >= $required_resource) {
			return 1;
		} else {
			print "\nPROBLEM [POSSIBLE QUOTA_EXCEED]:";
			print "\n\tThe project resources: $property\[$current_resource/$overall_resource\] is not enough to create the demanded instances";
			print "\n\tYou are asking a total of $required_resource instances, where only $diff is available\n\n";
		}
	} elsif ($property =~ /cpu/) {
		if ($diff >= $required_resource) {
			return 1;
		} else {
			print "\nPROBLEM [POSSIBLE QUOTA_EXCEED]:";
			print "\n\tThe project resources: $property\[$current_resource/$overall_resource\] is not enough to create the demanded instances";
			print "\n\tYou are asking a total of $required_resource cores, where only $diff is available\n\n";
		}
	}
	exit (2);

}



#
# parse input config file
#
sub parseConfigFile {
	
	#assign config filename, open and read its contents into an array
	my $configFileName = shift ;
	my @line;
	my @options;

	open FILE, $configFileName or die "Could not find ${configFileName}\n";
	@options = <FILE>;

	#more options maybe added later in configuration file following format of:
	#	label: value
	foreach my $i (@options) {
		@line = split(" ", $i);
		if($i =~ /^ZONE:/) {
			$zone = $line[1];	
		} elsif($i =~ /^AMI:/) {
			$ami = $line[1];	
		} elsif($i =~ /^INSTANCE_TYPE:/) {
			$instanceType = $line[1];	
			my @fields = split ("-", $instanceType);
			$numberOfCores = $fields[2]; 
		} elsif($i =~ /^INSTANCE_NAME_PREFIX:/) {
			$instanceNamePrefix = $line[1];	
		} elsif($i =~ /^NUMBER_OF_INSTANCES:/) {
			$numberOfInstances = $line[1];	
		} elsif($i =~ /^MASTER_NODE:/) {
			$master_node = $line[1];
		} elsif($i =~ /^COMPUTE_NODES:/){
			$compute_nodes = $line[1];
		}
	}
	close FILE;
	return ($zone, $ami, $instanceType, $numberOfCores, $instanceNamePrefix, $numberOfInstances, $master_node, $compute_nodes);
}


#
# Read the counter 
#
sub  read_counter {
	
	my $filename = shift;
	my $counter;

	if (-e $filename) {
		open FILE, $filename or die "Could not open ${filename}: $!\n";
		my @line = <FILE>;
		foreach my $i (@line) {
			$counter = $i;
		}
		close FILE;
		chomp($counter);
		return $counter;
	} else {
		open (FILE, ">$filename") || die "Cannot open file: $!\n";
		$counter = 1000;
		print FILE "$counter";
		close FILE;
		return $counter;
	}
}


#
# MODE_CODE: 100
# Create Instances
#
sub createInstances {

	my ($zone, $ami, $instanceType, $instanceNamePrefix, $numberOfInstances) = @_;

	# counter starting from 1000
	my $counter = read_counter(".$instanceNamePrefix.counter.txt");
	my $machineName ;
	my $machineNames = "";
	for (my $n = 1; $n <= $numberOfInstances; $n++) {
		$machineName = $instanceNamePrefix . $counter ;
		$machineNames = $machineNames . $machineName . " ";
		$counter++;
	} 
	print "\n\n====================================================\n";
	print "\ncreating instances $machineNames ... \n\n";
	if (length($ami)==0) {
		system ("gcutil addinstance $machineNames --wait_until_running --machine_type=$instanceType --zone=$zone 2>&1 | tee  log/$instanceNamePrefix.instances.creation.log ");
	} else {
		system ("gcutil addinstance $machineNames --image=$ami --wait_until_running --machine_type=$instanceType --zone=$zone 2>&1 | tee log/$instanceNamePrefix.instances.creation.log ");
	}

	#update new counter to file.
	open (FILE, ">.$instanceNamePrefix.counter.txt") || die "Cannot open file: $!\n";
	print FILE "$counter";
	close FILE;	
}


# 
# MODE_CODE: 101
# Delete all instances based on the instance prefix 
# defined in the input configuration file
#
sub deleteInstances {

	my $array = shift;
	my @instanceNames = @$array;
	my $instancePrefix = shift;
	my $zone = shift;

	my $num_instance = @instanceNames;
	if ( $num_instance == 0) {
		print "\n\nNo running instances with prefix - $instancePrefix exist ...\n\n";
		return ;
	}

	my $instances = "";
	foreach my $k (@instanceNames){
		$instances = $instances . $k . " ";
	}
	print "\n\n====================================================\n";
	if (length($instances) > 0) {
		print "\ndeleting instances $instances ...\n\n";
		system ("gcutil deleteinstance --delete_boot_pd --force --zone=$zone -f $instances 2>&1 | tee  log/$instanceNamePrefix.instances.deletion.log ");
		print "\n\ndone deleting instances $instances\n\n";
	}
	#remove counter file
	unlink (".$instanceNamePrefix.counter.txt");
	unlink <$instanceNamePrefix*.$SGE_INSTALLATION_POSTFIX>;
	print "\n\n";
}


#
# Get the list of running instances and put them into array.
#
sub getInstanceNames {

	my $zone = shift;

	my @iNames = ();
	# query to get list of running of instances 
	# my @names = `gcutil listinstances --zone=$zone | grep project | awk '{ print \$2 }'`;
	my @names = `gcutil listinstances --zone=$zone | grep $zone | awk -F\\\| '{print \$2}'`;
	foreach my $n (@names) {
		# trim whitespaces 
		$n =~ s/^\s+//;
		$n =~ s/\s+$//;
		if ($n =~ /$instanceNamePrefix/) {
			push(@iNames, $n);
		}
	}
	if (scalar(@iNames) > 0) {
		print "====================================================\n\n";
		foreach my $k (@iNames){
			print "Running instances '$k' \n\n";
		}
	}
	return @iNames;
}


#
# MODE_CODE: 102
# Mount ephemeral disks
#
sub create_mount_ephemeral {

	my $array = shift;
	my @instanceNames = @$array;
	my $instancePrefix = shift;
	my $zone = shift;
	my $path = shift;
	my $num_of_nodes = shift;
	
	my $pm = Parallel::ForkManager->new($num_of_nodes);

	foreach my $k (@instanceNames) {
		$pm->start and next;
		AGAIN:
		system ("gcutil ssh $k 'cat | perl /dev/stdin $path' < bin/mount_ephemeral.pl ");
		if ($? != 0) {
			goto AGAIN;
		}	
		$pm->finish;
	}

	$pm->wait_all_children();

	print "\n\ndone ...\n\n";

}

#
# Check if SGE is installed or not
# check_sge: $master_node
#
sub check_sge {

	my $master_node = shift;

	my @output = `gcutil ssh $master_node 'ps aux | grep sge | cut --delimiter=" " --field=1 | head -2' `;
	my $num_ele = @output;

	if ($num_ele == 2) {
		chomp($output[0]);
		chomp($output[1]);
		if ($output[0] eq "sgeadmin" && $output[1] eq "sgeadmin") {
			return;
		} else {
			print "\nSGE is not installed and configured on master node - $master_node.\nPlese run the script with mode = 201\n";
			print "Abort ... \n";
			exit (2);
		}
	} else {
		print "\nSGE is not installed and configured on master node - $master_node\nPlese run the script with mode = 201\n";
		print "Abort ... \n";
		exit (2);
	}
}


#
# MODE_CODE: 201
# Remotely installing SGE 
#
sub installingSGE {

	my $action = shift;
	my $target = shift;
	my $arg = shift;

	if ($action eq "master") {
		print "Installing SGE on master node -  $target ... it may take a few minutes ... \n\n";
		AGAIN_master:
		system ("gcutil ssh $target 'cat | sudo bash /dev/stdin $arg' < bin/install_sge_master.sh &> log/$target.$SGE_INSTALLATION_POSTFIX");
		if ($? != 0) {
			goto AGAIN_master;
		}
		print "SGE master node  \($target\) installation ... done ...\n\n";
	} else {
		# Action = compute
		print "Installing SGE on compute node - $target ... it may take a few minutes ... \n\n";
		AGAIN_compute:
		system ("gcutil ssh $target 'cat | sudo bash /dev/stdin $arg' < bin/install_sge_compute.sh &> log/$target.$SGE_INSTALLATION_POSTFIX");
		if ($? != 0) {
			goto AGAIN_compute;
		}
		print "SGE compute node \($target\) installation ... done ...\n\n";
	}
}



#
# Purpose: Create SGE 
# Parameters: @instanceNames, $configFile, $instanceNamePrefix, $numberOfCores $local_user
# 
sub create_SGE {
	
	my $array = shift;
	my @instanceNames = @$array;
	my $configFile = shift;
	my $instanceNamePrefix = shift;
	my $numberOfCores = shift;
	my $local_user = shift; 
        my $token = `< /dev/urandom tr -dc a-zA-Z0-9 | head -c20`;
        # Assign master and compute nodes	
	my $master_node = $instanceNames[0];
	# Set number of compute nodes
	my $num_of_node = @instanceNames;


	# Initiate FORK
	my $pm = Parallel::ForkManager->new($num_of_node);

	# Check the number of instances.
	my $num_instance = @instanceNames;
	if ( $num_instance == 0) {
		print "\n\n====================================================\n";
		print "\nNo runing instances with prefix - \"$instanceNamePrefix\" exist to install SGE...\n\n";
		exit (2) ;
	}
        # first we need to install the master and when its completed we can fork compute installs
        my $mnode = shift @instanceNames;
	if ($mnode eq $master_node) {
            installingSGE("master", $mnode, $token);
        }

        ## fork to build compute nodes
	foreach my $k (@instanceNames) {
		
		# Fork starts
		$pm->start and next;

		if ($num_of_node != 1) {
			# Collect compute nodes
			my $arg = "$token,$master_node";
			installingSGE("compute", $k, $arg);
		} else {
			return;
		}
		
		# Fork finishes 
		$pm->finish;

	}
	$pm->wait_all_children;
	
}


#
# Add an instance as a node 
#
sub update_SGE {

	# List of my instanceNames
	my $array = shift;
	my @instanceNames = @$array;

	# What action it is (add)
	my $action = shift;
	# Local user
	my $local_user = shift;
	# Number of newly added instances
	my $numberOfInstances = shift;
	
	# Process the instanceNames list 
	my $new_nodes = "";
	my $master_node = $instanceNames[0]; # We make first element as our master_node. 
	my $index = $#instanceNames; # Get the index of the last element because it is the new added node
	for (my $i = 0; $i < $numberOfInstances; $i++) {
		my $node = $instanceNames[$index-$i];
		$new_nodes .= " ".$node;
	}
	$new_nodes =~ s/^\s+//;
	my @target_nodes = split(" ", $new_nodes);

	#Combine variables
	my $arg = $local_user." ".$new_nodes;

	# Check for SGE installation
	check_sge($master_node);

	# Start Fork
	my $pm = Parallel::ForkManager->new($numberOfInstances);
	if ($action eq "add") {
		
		# Update SGE master
		print "\nUpdating/Adding $new_nodes to $master_node configuration file ... \n\n";
		system ("gcutil ssh $master_node 'cat | perl /dev/stdin $arg' < bin/add_multiple_instances.pl &> $master_node.$SGE_INSTALLATION_POSTFIX");

		# Update SGE compute
		foreach my $k (@target_nodes) {
			$pm->start and next;
			installingSGE("compute", $k, $master_node);
			$pm->finish;
		}
		$pm->wait_all_children;
	} 
	
}



