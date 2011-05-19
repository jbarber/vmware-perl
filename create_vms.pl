#!/usr/bin/perl

=head1 NAME

create_vms.pl

=head1 SYNOPSIS

./create_vms.pl --file input.yml

=head1 ARGUMENTS

=over

=item --help

Show the arguments for this program.

=back

=head1 DESCRIPTION

Create virtual machines from a YAML configuration file.

After the machines are created, a YAML representation is printed with the default values and the MAC addresses of the NICs filled in.

=head1 YAML EXAMPLE

Multiple hosts can be specified, seperate each one with "---".

Values that have a default are optional. If no disks or nics are specified then none will be created.

  ---
  name: foobar               # Required: name of the VM
  datacenter: DC             # Defaults to the first datacenter found
  computepath: prod/cluster1 # Required: path to the datacenter compute resource to create the VM on
  folder: client1/web        # Defaults to the root folder to create the VM in
  datastore: my-storage      # Defaults to the datastore in computepath with the most free space
  # Type of OS to install, valid options are here:
  # http://www.vmware.com/support/developer/vc-sdk/visdk25pubs/ReferenceGuide/vim.vm.GuestOsDescriptor.GuestOsIdentifier.html
  os: rhel5_64Guest          # Defaults to otherGuest64
  cpus: 2                    # Defaults to 2
  ram: 2048                  # Defaults to 2048MB
  # Array of disks to create - no default
  disks: 
    - thin: 1                # Optional, defaults to 1, 0 for thick disks
      size: 16777216         # Size in KiloBytes
  # Array of NICs to create - no default
  nics:
    - network: TST           # Required: name of the portgroup
      type: e1000            # Defaults to e1000
      connected: 1           # Defaults to 1 - interface is connected at boot

=head1 BUGS

None known at the moment.

=head1 TODO

=over

=item * Auto-selection of host/DRS cluster.

=item * Setting of advanced configuration options.

=back

=head1 SEE ALSO

L<VMware Perl SDK|http://www.vmware.com/support/developer>

=head1 AUTHOR

Jonathan Barber - <jonathan.barber@gmail.com>

=cut

use strict;
use warnings;
use Data::Dumper;
use YAML qw(LoadFile Load Dump);
use VMware::VIRuntime;
use feature "switch";

$Util::script_version = "1.0";

my %opts = (
	file => {
		type => "=s",
		help => "YAML file path",
		required => 0,
	},
);

# read/validate options and connect to the server
Opts::add_options(%opts);
Opts::parse();
Opts::validate();

sub load_yaml {
	my ($fn) = @_;
	if ($fn) {
		return LoadFile($fn);
	}
	else {
		my (@data) = Load(join "", <STDIN>);
		close STDIN;
		return @data;
	}
}

# Calculate the total disk size required, assuming thick disks, and including
# swap file
sub total_vm_size {
	my ($vm) = @_;
	my $size;
	for my $disk (@{$vm->{disks}}) {
		$size += $disk->{size};
	}
	$size += $vm->{ram};
}

# Get the next available unit number... Hmm. Should be changed to object so each VM can have a new one.
{
	my $unit = 0;
	sub unit_number { $unit++ }
	sub reset_unit_number { $unit = 0 };
}

# Compares two arrays, $src and $tar.
# If $src has more elements than $tar, return -1
# If there is a difference in array elements, returns 0
# If $tar is bigger than $src, but all of $src elements match $tar, return 1
# return 2 if they are the same
sub match_array {
	my ($src, $tar) = @_;
	if (@{$src} > @{$tar}) {
		return -1;
	}
	for (my $i = 0; $i < @{$tar}; $i++) {
		# $tar is bigger than $src, can't match - but  might in the future
		if ($i >= @{$src}) {
			return 1;
		}

		# Element of $a is not equal to $b
		if ($src->[$i] ne $tar->[$i]) {
			return 0;
		}
	}
	return 2;
}

# Find a folder (stored as an array ref of the path components) from a root
# $folder. The current path is the array ref $current.
sub find_folder {
	my ($folder, $current, $target) = @_;

	my @current = (@{$current}, $folder->name);
	my $match = match_array(\@current, $target);

	if ($match <= 0) {
		return;
	}
	# On the right track...
	elsif ($match == 1) {
		$folder->can("childEntity") or return;
		my $children = $folder->childEntity || return;
		for my $child (@{$children}) {
			next if $child->type eq 'VirtualMachine';
			my $res = find_folder( Vim::get_view(mo_ref => $child), \@current, $target );
			return $res if $res;
		}
	}      
	# We have a winner!
	else {
		return $folder;
	}
}

# Find a compute resource at $path
sub get_host {
	my ($dc, $path) = @_;

	if ($path) {
		return find_folder(
			Vim::get_view(mo_ref => $dc->hostFolder),
			[], $path
		);
	}
	# Pick one at random
	else {
		die "TODO: Not yet implemented!\n";
	}
}

sub get_vmfolder {
	my ($dc, $path) = @_;

	$path //= [ "vm" ];
	return find_folder(
		Vim::get_view(mo_ref => $dc->vmFolder),
		[], $path
	);
}

# Check the datastore exists on the host, if no datastore is given, return the
# store with the greatest free space
sub get_ds_name {
	my ($host, $store) = @_;

	my @datastores = @{ Vim::get_views(mo_ref_array => $host->datastore) };
	if ($store) {
		my ($target) = grep { $_->summary->name eq $store } @datastores;
		if ($target) {
			return $target->summary->name;
		}
	}
	else {
		my ($target) = sort { $b->summary->freeSpace <=> $a->summary->freeSpace } @datastores;
		return $target->summary->name;
	}
}

sub create_ide_ctl {
	my ($vm) = @_;
	my $ctl = VirtualIDEController->new(
		key => int(200), # Magic value...
		device => [3000],
		busNumber => 0,
	);

	return VirtualDeviceConfigSpec->new(
		device => $ctl,
		operation => VirtualDeviceConfigSpecOperation->new('add')
	);
}

# Create the controller configuraton
# TODO: Change controller type depending on cfg
sub create_ctl {
	my ($vm) = @_;
	my $ctl = VirtualLsiLogicController->new(
		key => 0,
		device => [0],
		busNumber => 0,
		sharedBus => VirtualSCSISharing->new('noSharing')
	);

	return VirtualDeviceConfigSpec->new(
		device => $ctl,
		operation => VirtualDeviceConfigSpecOperation->new('add')
	);
}

# Create the disk configuration
sub create_disks {
	my ($vm, $ds) = @_;

	my @disks;
	for my $disk (@{$vm->{disks}}) {
		my $backing = VirtualDiskFlatVer2BackingInfo->new(
			thinProvisioned => $disk->{thin},
			diskMode => 'persistent',
			fileName => $ds
		);

		my $disk = VirtualDisk->new(
			backing => $backing,
			controllerKey => 0,
			key => 0,
			unitNumber => unit_number(),
			capacityInKB => $disk->{size},
		);

		push @disks, VirtualDeviceConfigSpec->new(
			device => $disk,
			fileOperation => VirtualDeviceConfigSpecFileOperation->new('create'),
			operation => VirtualDeviceConfigSpecOperation->new('add')
		);
	}
	return @disks;
}

sub create_cdrom {
	my ($vm, $ctl) = @_;
	my @devices;
	my $cdrom = VirtualCdrom->new(
		backing => VirtualCdromRemotePassthroughBackingInfo->new(
			deviceName => "/dev/null",
			exclusive => 0,
		),
		connectable => VirtualDeviceConnectInfo->new(
			allowGuestControl => 1,
			connected => 0,
			startConnected => 0,
		),
		controllerKey => int( $ctl->device->key ),
		unitNumber => 0,
		key => int(3000), # Magic value...
	);
		
	push @devices, VirtualDeviceConfigSpec->new(
		device => $cdrom,
		operation => VirtualDeviceConfigSpecOperation->new('add')
	);
	return @devices;
}

# Create the NIC configuration
sub create_nics {
	my ($vm, $host) = @_;
	my %networks = map { $_->name => $_ } @{ Vim::get_views(mo_ref_array => $host->network) };

	my @nics;
	for my $nic (@{$vm->{nics}}) {
		# TODO: Exit more cleanly
		exists $networks{ $nic->{network} } || die "No such network: ".$nic->{network}."\n";

		my $backing = VirtualEthernetCardNetworkBackingInfo->new(
			deviceName => $nic->{network},
			network => $networks{ $nic->{network} },
		);

		my $connection = VirtualDeviceConnectInfo->new(
			allowGuestControl => 1,
			connected => 0,
			startConnected => $nic->{connected},
		);

		my @args = (
			backing => $backing,
			key => 0,
			unitNumber => unit_number(),
			addressType => 'generated',
			connectable => $connection,
		);

		my $device;
		given ($nic->{type}) {
			when (undef) { $device = VirtualE1000->new(@args) }
			when ("e1000") { $device = VirtualE1000->new(@args) }
			when ("pcnet32") { $device = VirtualPCNet32->new(@args) }
			when ("vmxnet") { $device = VirtualVmxnet->new(@args) }
		}

		push @nics, VirtualDeviceConfigSpec->new(
			device => $device,
			operation => VirtualDeviceConfigSpecOperation->new('add')
		);
	}

	return @nics;
}

# Get the datacenter
sub get_dc {
	my ($datacenter) = @_;

	my @dc_view = @{ Vim::find_entity_views(
		view_type => 'Datacenter',
		defined $datacenter ? (filter => { name => $datacenter }) : (),
	) };

	return shift @dc_view;
}

# Get the folder to put the VM in
sub get_folder {
	my ($dc, $vm) = @_;

	if ($vm) {
	}
	else {
		return Vim::get_view(mo_ref => $dc->vmFolder);
	}
}

sub do_defaults {
	my ($vm) = @_;
	my %defaults = (
		ram => 2048,
		cpus => 2,
		os => "otherGuest64",
	);
	my $def_or_replace = sub {
		my ($hash, $key, $value) = @_;
		$hash->{$key} = $value unless defined $hash->{$key}
	};

	while (my ($key, $value) = each %defaults) {
		$def_or_replace->( $vm, $key, $value);
	}

	for my $nic (@{$vm->{nics}}) {
		$def_or_replace->($nic, "connected", 1);
		$def_or_replace->($nic, "type", "e1000");
	}

	for my $disk (@{$vm->{disks}}) {
		$def_or_replace->($disk, "thin", 1);
	}
}

# Add the MAC's from the created VM (@vmnics) to the configuration used to
# create the VM ($vm)
sub add_nic_macs {
	my ($vm, @vmnics) = @_;
	my $nics = $vm->{nics};

	die "Number of NICs in guest not the same as requested\n" unless @vmnics == @{$nics};
	for (my $i = 0; $i < @vmnics; $i++) {
		$nics->[$i]->{macaddress} = $vmnics[$i]->macAddress;
	}
}

# Check required values are provided.
sub check_config {
	my ($vm) = @_;
	my @missing = grep { not exists $vm->{$_} } qw(name computepath);
	if (@missing) {
	       	die "Missing required configuration items:\n".join("\n", @missing)."\n";
	}
}

# Load configuration from YAML
my @vms = load_yaml( Opts::get_option('file') );
Util::connect();

# Iterate over the VMs and create them
for my $vm (@vms) {
	do_defaults($vm);
	check_config($vm);
	reset_unit_number();

	# 1. Find the datacenter
	my $dc = get_dc( $vm->{datacenter} ) || warn "No datacenter's found! Skipping\n" && next;
	$vm->{datacenter} //= $dc->name;

	# 2. Get the compute resource
	my $host = get_host( $dc, [ "host", split qr#/#, $vm->{computepath} || "" ] ) || warn "No such host ".$vm->{host}." for ".$vm->{name}."\n" && next;

	# 3. Find the datastore
	my $ds = do {
		my $tmp = get_ds_name(
			$host,
			$vm->{datastore},
		) || warn "Datastore not found: ".$vm->{datastore}."\n" && next;
		$vm->{datastore} = $tmp;
		"[$tmp]";
	};

	# 4. Create devices
	my @devices = create_ctl;
	my $ide = create_ide_ctl;
	push @devices, create_ide_ctl;
	push @devices, create_disks( $vm, $ds );
	push @devices, create_nics( $vm, $host );
	push @devices, create_cdrom( $vm, $ide );

	my $files = VirtualMachineFileInfo->new(
		logDirectory => undef,
		snapshotDirectory => undef,
		suspendDirectory => undef,
		vmPathName => $ds,
	);
	my $vm_config_spec = VirtualMachineConfigSpec->new(
		name => $vm->{name},
		memoryMB => $vm->{ram},
		files => $files,
		numCPUs => $vm->{cpus},
		guestId => $vm->{os},
		deviceChange => \@devices,
	);

	# Find the folder to put the VM under
	my $folder = get_vmfolder( $dc, [ "vm", split qr#/#, $vm->{folder} || "" ] ) || warn "Couldn't find a folder to put the VM in\n" && next;

	# Actually create the VM
	my $moref = $folder->CreateVM(
		config => $vm_config_spec,
		pool => $host->resourcePool
	);

	# Find the NIC MACs
	my $new_vm = Vim::get_view(mo_ref => $moref);
	my @nics = grep { $_->isa("VirtualEthernetCard") } @{ $new_vm->config->hardware->device };
	add_nic_macs($vm, @nics);
}
# Report the resulting VMs
print Dump(@vms);
Util::disconnect();
