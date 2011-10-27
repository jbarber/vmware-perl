#!/usr/bin/env perl

=head1 NAME

find_thick.pl - Find VMware hosts that don't have thin provisioned disks

=head1 SYNOPSIS

./find_thick.pl --username admin --password foo --host virtualcenter

=head1 ARGUMENTS

=over

=item --help

Show the arguments for this program.

=back

=head1 DESCRIPTION

Enumerate all VMs without thin provisioned disks.

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

{
	my %mo_cache;
	sub cache_mo {
		my ($sub) = @_;
		if (exists $mo_cache{ $sub->{type} }{ $sub->{value} }) {
			return $mo_cache{ $sub->{type} }{ $sub->{value} };
		}
		else {
			return $mo_cache{ $sub->{type} }{ $sub->{value} } = Vim::get_view(mo_ref => $sub);
		}
	}
}

sub get_folder {
	my ($folder, @names) = @_;

	my $name = $folder->name;
	if ($folder->parent) {
		return get_folder(
			cache_mo( $folder->parent ),
			($name, @names),
		);
	}
	else {
		return ($name, @names);
	}
}

sub has_thick {
	my (@devices) = @_;

	my @thick;
	for my $device (@devices) {
		if ($device->isa("VirtualDisk")) {
			if ($device->backing->can("thinProvisioned")) {
				if (!$device->backing->thinProvisioned()) {
					push @thick, $device;
				}
			}
			else {
				push @thick, $device;
			}
		}
	}
	return @thick;
}

Opts::parse();
Opts::validate();
Util::connect();

# Get all VMs
my $vms = Vim::find_entity_views(
	view_type => 'VirtualMachine',
	#filter => { name => 'ies-dev-evl-rhev-m' }
);

my @guests;
# Iterate over the VMs, getting their IPs and OS
foreach my $vm (@{ $vms }) {

	unless ($vm->config) {
		warn $vm->name, " missing config!\n";
		next;
	}

	unless ($vm->config->hardware) {
		warn $vm->name, " missing hardware!\n";
		next;
	}

	my @thick = has_thick( @{$vm->config->hardware->device} );
	if (@thick) {
		print join("/", get_folder($vm)), ": ", $vm->name, "\n";
	}
}
Util::disconnect();
