#!/usr/bin/perl

=head1 NAME

find_os.pl

=head1 SYNOPSIS

./find_os.pl --username admin --password foo --host virtualcenter

=head1 ARGUMENTS

=over

=item --help

Show the arguments for this program.

=back

=head1 DESCRIPTION

Reports the OSs of all the VMs managed by B<virtualcenter>. Requires installation of VMware tools on each host to be accurate.

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

# Iterate over the VMs, printing their info
foreach my $vm (@{ $vms }) {
	print join(",",
		map { defined $_ ? $_ : "" }
		$vm->name, $vm->guest->guestState, $vm->guest->guestFamily, $vm->guest->guestFullName
	), "\n";
}

Util::disconnect();                                  
