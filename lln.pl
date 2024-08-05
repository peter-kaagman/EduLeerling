#! /usr/bin/env perl

use v5.11;
use strict;
use warnings;
use Data::Dumper;
use FindBin;
use JSON;
use Config::Simple;
use Parallel::ForkManager;
use lib "$FindBin::Bin/../magister-perl/lib";
use lib "$FindBin::Bin/../msgraph-perl/lib";

use Magister; # Diverse magister functies
use MsGraph;
use Logger; # Om te loggen

my %config;
# Voorlopig maar ff de EduTeams config gebruiken
Config::Simple->import_from("$FindBin::Bin/../EduTeams/config/EduTeams.cfg", \%config) or die("No config: $!");

my $logger = Logger->new(
    'filename' => "$FindBin::Bin/Log/EduTeams.log",
    'verbose' => $config{'LOG_VERBOSE'}
);
$logger->make_log("$FindBin::Bin/$FindBin::Script started.");

# Magister data ophalen
# Magister object om magister dingen mee te doen
my $mag_session= Magister->new(
    'user'          => $config{'MAGISTER_USER'},
    'secret'        => $config{'MAGISTER_SECRET'},
    'endpoint'      => $config{'MAGISTER_URL'},
    'lesperiode'    => $config{'MAGISTER_LESPERIODE'}

);
# Dit zijn de leerlingen van het lopende schooljaar vlgs Magister
my $lln = $mag_session->getLeerlingen();
print Dumper $lln;

