#!/usr/bin/env perl

use strict;
use warnings;
use VMware::VIRuntime;

=head1 NAME

show_folders.pl

=head1 DESCRIPTION

List all of the virtual machine and host folders.

=head1 AUTHOR

Jonathan Barber - <jonathan.barber@gmail.com>

=cut

Opts::add_options(
	datacenter => {
		type => "=s",
		required => 0,
		help => "Datacenter name",
	},
);
Opts::parse();
Opts::validate();
Util::connect();

my $datacenter = Opts::get_option('datacenter');
my $dc = Vim::find_entity_view(
	view_type => 'Datacenter',
	defined $datacenter ? (filter => { name => $datacenter }) : (),
);
unless ($dc) {
	if (defined $datacenter) {
		die "Couldn't find a datacenter called '$datacenter'\n";
	}
	die "No datacenters found.\n";
}

sub get_folders {
	my ($folder, $indent) = @_;

	print " " x $indent, $folder->name, " - ",  ref $folder, "\n";
	# Nothing to do on nodes with no possibility of children
	# (virtualmachines for example)
	$folder->can("childEntity") or return;

	# Check if we can have children, but don't...
	my $children = $folder->childEntity || return;
	for my $child (@{$children}) {
		# Ignore VMs
		next if $child->type eq 'VirtualMachine';

		# Could probably make this quicker by using Vim::get_views to
		# get all of the folders at the same time
		get_folders(Vim::get_view(mo_ref => $child), $indent + 2);
	}
}

print "#" x 60, "\nGetting VM folders\n";
get_folders( Vim::get_view(mo_ref => $dc->vmFolder), 0);
print "\n";

print "#" x 60, "\nGetting compute folders\n";
get_folders( Vim::get_view(mo_ref => $dc->hostFolder), 0);
