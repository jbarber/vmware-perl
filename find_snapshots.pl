#!/usr/bin/perl

=head1 NAME

find_snapshots.pl

=head1 SYNOPSIS

./find_snapshots.pl --username admin --password foo --host virtualcenter

=head1 ARGUMENTS

=over

=item --help

Show the arguments for this program.

=back

=head1 DESCRIPTION

Enumerate all VMs with snapshots.

=head1 SEE ALSO

L<VMware Perl SDK|http://www.vmware.com/support/developer>

=head1 AUTHOR

Jonathan Barber - <jonathan.barber@gmail.com>

=cut

use strict;
use warnings;
use VMware::VIRuntime;

$Util::script_version = "1.0";

# read/validate options and connect to the server
Opts::parse();
Opts::validate();
Util::connect();

# Get all VMs
my $vms = Vim::find_entity_views(
	view_type => 'VirtualMachine',
);

# Iterate over the VMs, printing their name if they have any snapshots
foreach my $vm (@{ $vms }) {
	print $vm->name, "\n" if $vm->snapshot;
}

Util::disconnect();
