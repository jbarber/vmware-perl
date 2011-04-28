#!/usr/bin/perl

use strict;
use warnings;
use Getopt::Long;
use Pod::Usage;
use VMware::VIRuntime;

=head1 NAME

brute_esx.pl

=head1 SYNOPSIS

./brute_esx.pl --passwords ~/passwords.txt --host myesx.foo.com --user root --verbose

=head1 DESCRIPTION

Tries to find out the ESX password for a username. Gets the passwords from a file, format of one password per line.

Useful if you know that the machine has a user, but the password could be one of the normal "defaults".

=head1 OPTIONS

=over

=item --user root

The username to try and log in with, normally root.

=item --passwords ~/passwords.txt

Path to a file containing passwords to try. Should just be a list of passwords, one per line.

=item --host myesx.foo.com

The host you want to try to log into.

=item --verbose

Report all errors when a log in fails.

=back

=head1 SEE ALSO

L<VMware Perl SDK|http://www.vmware.com/support/developer>

=head1 AUTHOR

Jonathan Barber - <jonathan.barber@gmail.com>

=cut

my ($passwords, $host, $user, $verbose, $help, $man);
GetOptions(
	"host=s" => \$host,
	"user=s" => \$user,
	"passwords=s" => \$passwords,
	"verbose|v" => \$verbose,
	"help|h" => \$help,
	"man" => \$man,
) or pod2usage(2);

$help      && pod2usage(2);
$man       && pod2usage(-verbose => 2);
$user      || die "missing required --user\n";
$host      || die "missing required --host\n";
$passwords || die "missing required path to passwords file (--passwords)\n";

my %credentials = (
	$user => [ getpasswd( glob $passwords ) ],
);

sub getpasswd {
	my ($fn) = @_;
	open my $fh, $fn or die "Couldn't open password file $fn: $!\n";
	return map { chomp; $_ } <$fh>;
}

sub trylogin {
	my ($host, $user, $password) = @_;
	Vim::login(
		service_url => "https://$host/sdk/vimService",
		user_name => $user,
		password => $password, 
	); 
}

sub trycredentials {
	my ($host, $credentials) = @_;
	
	for my $username (keys %{$credentials}) {
		for my $password (@{$credentials->{$username}}) {
			if (my $login = eval { trylogin($host, $username, $password ) } ) {
				return $login, $username, $password;
			}
			if ($@) {
				if ($@ =~ /Server version unavailable/) {
					warn "$@: Try setting the environment varialbe PERL_LWP_SSL_VERIFY_HOSTNAME=0\n" 

				}
				else {
					warn "$@\n" if $verbose;
				}
			}
		}
	}
	return ();
}

my ($login, $username, $password) = trycredentials($host, \%credentials);
if ($login) {
	print "Logged into $host as $username with $password\n";
	$login->logout;
}
else {
	warn "Couldn't authenticate to $host\n";
}
