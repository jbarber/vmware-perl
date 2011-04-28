#!/usr/bin/perl

=head1 NAME

get_macs.pl

=head1 SYNOPSIS

./get_macs.pl --username admin --password foo --host virtualcenter

=head1 ARGUMENTS

=over

=item --help

Show the arguments for this program.

=back

=head1 DESCRIPTION

Find the MAC addresses of all the NICs for all the VMs on B<virtualcenter>.

=head1 SEE ALSO

L<VMware Perl SDK|http://www.vmware.com/support/developer>

=head1 AUTHOR

Jonathan Barber - <jonathan.barber@gmail.com>

=cut

use strict;
use warnings;
use VMware::VIRuntime;

$Util::script_version = "1.0";

Opts::parse();
Opts::validate();
Util::connect();

# Get all VMs
my $vms = Vim::find_entity_views(
	view_type => 'VirtualMachine',
);

my @guests;
# Iterate over the VMs, getting their IPs and OS
foreach my $vm (@{ $vms }) {
	my @nics = grep {
		$_->isa("VirtualEthernetCard")
	} @{ $vm->config->hardware->device };

	for my $nic (@nics) {
		print $nic->macAddress, " ", $vm->name, "\n";
	}
}
Util::disconnect();
