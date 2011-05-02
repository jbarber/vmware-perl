#!/usr/bin/env perl

=head1 NAME

create_user.pl

=head1 SYNOPSIS

create_user.pl [--username root] --password sekret --host 10.10.10.10 [--newusername|--nu] foobar [--newuserpassword|--np] evenmoresekret [--addtogroup] [--help|-h] [--man]

=head1 DESCRIPTION

Creates a user in ESX that can SSH into the host. If the user exists, then change the password to that given and make sure the user can log in via SSH.

=head1 OPTIONS

=over

=item --username root

User to connect to ESX as, defaults to root.

=item --password

Password for --username

=item --host

ESX host IP/hostname.

=item --newusername | --nu

ESX new user username.

=item --newusepassword | --np

Password for --newusername.

=item --addtogroup

If the user already exists, force the addition of the user to the root group. This appears to be required to allow users to ssh into ESX 4.0. The argument is optional because if the user is already a member of a group then it will cause an error message in ESX and it doesn't appear to be possible to find out beforehand what the group membership of a user is.

=item --help | -h

Command line help.

=item --man

Show the man page.

=back 

=head1 AUTHOR

Jonathan Barber - <jonathan.barber@gmail.com>

=cut

use strict;
use warnings;
use Getopt::Long;
use Pod::Usage;
use VMware::VIRuntime;

my ($user, $passwd, $host, $newuser, $newpasswd, $addgroup, $help, $man);
GetOptions(
	"username=s" => \$user,
	"password=s" => \$passwd,
	"host=s" => \$host,
	"newusername|nu=s" => \$newuser,
	"newuserpassword|np=s" => \$newpasswd,
	"addtogroup" => \$addgroup,
	"help|h" => \$help,
	"man" => \$man,
) or pod2usage(2);
$help && pod2usage(-verbose => 0);
$man  && pod2usage(-verbose => 2);

$user      ||= "root";
$passwd    || die "Missing --password argument\n";
$host      || die "Missing ESX --host argument\n";
$newuser   ||= $ENV{USER};
$newpasswd || die "Missing --newuserpassword argument\n";

my $login = Vim::login(
	service_url => "https://$host/sdk/vimService",
	user_name => $user,
	password => $passwd,
) || die $!; 
END { $login && $login->logout; }

my $user_info = HostPosixAccountSpec->new(
	id => $newuser,
	password => $newpasswd,
	shellAccess => 1,
);

my $sc = Vim::get_service_content;
my $ud = Vim::get_view(mo_ref => $sc->userDirectory());
my $am = Vim::get_view(mo_ref => $sc->accountManager());

my ($search) = @{ $ud->RetrieveUserGroups(
	searchStr => $user_info->id,
	exactMatch => 1,
	findUsers => 1,
	findGroups => 0,
) };

if ($search) {
	warn "User exists, updating.\n";
	$am->UpdateUser(user => $user_info);

	if ($addgroup) {
		my $group = "root";
		eval {
			$am->AssignUserToGroup(
				user => $user_info->id,
				group => $group,
			);
		};
		if ($@) {
			warn "User was already a member of the group '$group'\n";
		}
	}
}
else {
	warn "User missing, creating.\n";
	$am->CreateUser(user => $user_info);
	$am->AssignUserToGroup(
		user => $user_info->id,
		group => "root"
	);
}
