#!/usr/bin/env perl

=head1 NAME

relocate_vms.pl

=head1 SYNOPSIS

./relocate_vms.pl VMNAME --filter "^FC"

=head1 DESCRIPTION

Command to migrate a VM from one datastore to another and back again. In the process turning it's VMDKs from thick provisioned to thin.

The target datastore is the largest one that the host running the VM has access to that isn't excluded by the --filter argument.

This command will not return until the VM has finished migrating.

=head1 ARGUMENTS

=over

=item --filter 

The names of the datastores on the host that the VM is on are filter by this regex. The largest is then selected to migrate the VM to.

=back 

=head1 SEE ALSO

L<VMware Perl SDK|http://www.vmware.com/support/developer>

=head1 AUTHOR

Jonathan Barber - <jonathan.barber@gmail.com>

=cut

use strict;
use warnings;
use Data::Dumper;
use VMware::VIRuntime;

$Util::script_version = "1.0";

Opts::add_options(
	filter => {
		type => "=s",
		help => "regex to filter which datastores a VM can be migrated to",
		required => 0,
	},
);
Opts::parse();
Opts::validate();
Util::connect();

sub get_datastores {
	my ($vm) = @_;
	return map {
		Vim::get_view( mo_ref => $_ )
	} @{ Vim::get_view( mo_ref => $vm->runtime->host )->datastore };
}

sub pick_ds {
	my ($vm, $pattern) = @_;

	my @ds = get_datastores($vm);
	my @pick = sort {
		$b->info->freeSpace <=> $a->info->freeSpace
	} grep { $_->name =~ $pattern } @ds;
	return $pick[0];
}

sub get_source_ds {
	my ($vm) = @_;

	my (@src_ds) = map { Vim::get_view(mo_ref => $_) } @{ $vm->datastore };
	if (@src_ds > 1) {
		die $vm->name, ": has data on more than one datastore, giving up on migration\n";
	}
	return $src_ds[0];
}

# Get VM
$ARGV[0] || die "Not given a VM name\n";
my $filter = do {
	my $pattern = Opts::get_option('filter') || ".*";
	qr/$pattern/;
};
my $vm = Vim::find_entity_view(
	view_type => 'VirtualMachine',
	filter => { name => $ARGV[0] }
);
$vm || die "Couldn't find a VM with the name '$ARGV[0]'\n";

my ($source) = get_source_ds($vm);
my ($target) = pick_ds($vm, $filter);

warn $vm->name, ": relocating from ", $source->name, " to ", $target->name, "\n";
$vm->RelocateVM(
	spec => VirtualMachineRelocateSpec->new(
		datastore => $target->{mo_ref},
		transform => VirtualMachineRelocateTransformation->new('sparse')
	)
);

warn $vm->name, ": relocating from ", $target->name, " to ", $source->name, "\n";
$vm->RelocateVM(
	spec => VirtualMachineRelocateSpec->new(
		datastore => $source->{mo_ref}
	)
);

print $vm->name, ": finished\n\n";
