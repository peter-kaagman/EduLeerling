#! /usr/bin/env perl

use v5.11;
use utf8;
use strict;
use warnings;
use Data::Dumper;
use FindBin;
use JSON;
#use Text::CSV qw( csv );
use Switch;
use Config::Simple;
use lib "$FindBin::Bin/../magister-perl/lib";
use lib "$FindBin::Bin/../msgraph-perl/lib";

use Magister; # Diverse magister functies
use MsUsers;
use MsSpoList;

binmode(STDOUT, ":utf8");

my $ToDo;
my %config;
Config::Simple->import_from("$FindBin::Bin/config/lln.cfg", \%config) or die("No config: $!");


# Magister data ophalen
# Magister object om magister dingen mee te doen
my $mag_session= Magister->new(
    'user'          => $config{'MAGISTER_USER'},
    'secret'        => $config{'MAGISTER_SECRET'},
    'endpoint'      => $config{'MAGISTER_URL'},
    'lesperiode'    => $config{'MAGISTER_LESPERIODE'}

);

my $az_session = MsUsers->new(
	'app_id'        => $config{'APP_ID'},
	'app_secret'    => $config{'APP_PASS'},
	'tenant_id'     => $config{'TENANT_ID'},
	'login_endpoint'=> $config{'LOGIN_ENDPOINT'},
	'graph_endpoint'=> $config{'GRAPH_ENDPOINT'},
	#'filter'        => '$filter=endswith(mail,\'atlascollege.nl\')', 
	'filter'        => '$filter=userType eq \'Member\'', 
    'select'        => '$select=id,displayName,userPrincipalName,department,jobTitle,givenName,surname,employeeId',
	#'consistencylevel' => 'eventual',
);

my $locaties = {
   '0' => "OSG West-Friesland",
   '2' => "Copernicus SG",
   '4' => "SG De Dijk",
   '8' => "SG Newton",
   '9' => 'SG De Triade' 
};


# Dit zijn de leerlingen van het lopende schooljaar vlgs Magister
my $lln_mg = $mag_session->getLeerlingen();

# Dit zijn de leerlingen van het lopende schooljaar vlgs Magister
my $tmp = $az_session->users_fetch();
# Hash van maken met alleen leerlig accounts
my $lln_az;
foreach my $account (@{$tmp}){
    if ($account->{'userPrincipalName'} =~ /^[Bb]1\d{5}\@atlascollege.nl/){
        $lln_az->{ lc($account->{'userPrincipalName'}) } = $account;
    }
}

# Azure versus Magister
while (my($upn,$account) = each(%{$lln_az})){
    if (! $lln_mg->{$upn}){
        push @{$ToDo->{'delete'}}, $account;
    }
}
# Magister versus Azure
while (my($upn,$account) = each(%{$lln_mg})){
    if (! $lln_az->{$upn}){
        $account->{'locatie'} = $locaties->{$account->{'locatie_index'}};
        push @{$ToDo->{'create'}}, $account;
    }
}

# Verhuizing
while (my($upn,$account) = each (%{$lln_mg})){
    if ($lln_az->{$upn}){
        if ( lc($locaties->{$account->{'locatie_index'}}) ne lc($lln_az->{$upn}->{'department'}) ){
            $account->{'locatie_nieuw'} = $locaties->{$account->{'locatie_index'}};
            $account->{'locatie_oud'} =   $lln_az->{$upn}->{'department'};
            push @{$ToDo->{'move'}}, $account;
        }
    }
}

# Properties
while (my($upn,$account) = each (%{$lln_mg})){
    if ($lln_az->{$upn}){
        # Init
        my $b_nummer = 'b'.$account->{'stamnr'};
        my $jobTitle;
        if ($account->{'klas'}){
            $jobTitle = 'Leerling '. $locaties->{$account->{'locatie_index'}} . ', klas: ' . $account->{'klas'};
        }else{
            $jobTitle = 'Leerling '. $locaties->{$account->{'locatie_index'}} . ', studie: ' . $account->{'studie'};
        }
        my $surname;
        if ($account->{'tv'}){
            $surname = $account->{'tv'} . ' ' . $account->{'a_naam'};
        }else{
            $surname = $account->{'a_naam'};
        }
        my $displayName = $account->{'v_naam'} . ' ' . $surname;

        # locatie
        if ($locaties->{$account->{'locatie_index'}} ne $lln_az->{$upn}->{'department'}){
            $ToDo->{'mutate'}->{$b_nummer}->{'locatie'} = $locaties->{$account->{'locatie_index'}};
            # $ToDo->{'mutate'}->{$b_nummer}->{'locatie_org'} = $lln_az->{$upn}->{'department'};
        }
        # jobTitle
        if (
            ($lln_az->{$upn}->{'jobTitle'})&&
            ($jobTitle ne $lln_az->{$upn}->{'jobTitle'})
        ){
            $ToDo->{'mutate'}->{$b_nummer}->{'title'} = $jobTitle;
            # $ToDo->{'mutate'}->{$b_nummer}->{'title_org'} = $lln_az->{$upn}->{'jobTitle'};
        }
        # givenName
        if ($account->{'v_naam'} ne $lln_az->{$upn}->{'givenName'}){
            $ToDo->{'mutate'}->{$b_nummer}->{'voornaam'} = $account->{'v_naam'};
            # $ToDo->{'mutate'}->{$b_nummer}->{'voornaam_org'} = $lln_az->{$upn}->{'givenName'};
        }
        # surname
        if ($surname ne $lln_az->{$upn}->{'surname'}){
            $ToDo->{'mutate'}->{$b_nummer}->{'achternaam'} = $surname;
            # $ToDo->{'mutate'}->{$b_nummer}->{'achternaam_org'} = $lln_az->{$upn}->{'surname'};
        }
        # displayName
        if ($displayName ne $lln_az->{$upn}->{'displayName'}){
            $ToDo->{'mutate'}->{$b_nummer}->{'displayName'} = $displayName;
            # $ToDo->{'mutate'}->{$b_nummer}->{'displayName_org'} = $lln_az->{$upn}->{'displayName'};
        }
        # upn
        if ($upn ne $lln_az->{$upn}->{'userPrincipalName'}){
            $ToDo->{'mutate'}->{$b_nummer}->{'upn'} = $upn;
            # $ToDo->{'mutate'}->{$b_nummer}->{'upn_org'} = $lln_az->{$upn}->{'userPrincipalName'};
        }
        # Employee ID
        if ( (! $lln_az->{$upn}->{'employeeId'}) || ($account->{'stamnr'} ne $lln_az->{$upn}->{'employeeId'}) ){
            $ToDo->{'mutate'}->{$b_nummer}->{'employeeId'} = $account->{'stamnr'};
        }
    }
}
 say Dumper $ToDo;
 exit 1;
if ($ToDo){
    # Opzoeklijstje maken van bestaande tickets
    my $spo_object = MsSpoList->new(
        'app_id'        => $config{'APP_ID'},
        'app_secret'    => $config{'APP_PASS'},
        'tenant_id'     => $config{'TENANT_ID'},
        'site_naam'     => 'support',
        'list_naam'     => 'ITSM360_Tickets',
        'login_endpoint'=> $config{'LOGIN_ENDPOINT'},
        'graph_endpoint'=> $config{'GRAPH_ENDPOINT'},
    );
    my $list = $spo_object->list_items(
        'expand=fields(select=Title)',
        'filter=fields/StatusLookupId eq \'1\' and fields/AssignedTeamLookupId eq \'4\' and startswith(fields/Title, \'Mutatie\')'
    );
    # $list is een AoH met open tickets indexed op ticket nummer, een array met b nummers is handiger
    my @b_nummers;
    while(my($ticket,$entry) = each %{$list}){
        if ($entry->{'Title'} =~ /Mutatie: (b\d{6})/){
            push @b_nummers, $1;
        }
    }
    while (my($type,$actions) = each %{$ToDo}){
        switch ($type){
            case 'delete'{
                say 'Delete';
                foreach my $entry (@{$actions}){
                    if($entry->{'userPrincipalName'} =~ /^(b\d{6})\@.*/){
                        if(! grep( /$1$/, @b_nummers)){
                            my $description;
                            $description .= '<p><b>Zoals afgesproken deactioveren, niet verwijderen.</b></p>';
                            $description .= "<br>";
                            $description .= "<p>Leerling deactiveren: $1</p>";
                            my $payload = {
                                "fields" => {
                                    'SLAPriorityLookupId' => '5',
                                    'StatusLookupId' => '1',
                                    'TicketType' => 'Incident',
                                    'RequesterLookupId' => '12',
                                    'AssignedTeamLookupId' => '4',
                                    'Origin' => 'Self Service',
                                    'Title'	=> "Mutatie: $1 $type",
                                    'Description' => $description
                                }
                            };
                            my $result = $spo_object->list_item_create($payload);
                            if (! $result->is_success){
                                print Dumper $result;
                            }
                        }else{
                            say "Is al een ticket voor $type $entry->{'userPrincipalName'}";
                        }
                    }
                }
            }
            case 'create'{
                say 'Create';
                foreach my $entry (@{$actions}){
                    my $b_nummer = 'b'.$entry->{'stamnr'};
                    if(! grep( /$b_nummer$/, @b_nummers)){
                        my $fullName;
                        if ($entry->{'tv'}){
                            $fullName = "$entry->{'v_naam'} $entry->{'tv'} $entry->{'a_naam'}";
                        }else{
                            $fullName = "$entry->{'v_naam'} $entry->{'a_naam'}";
                        }
                        my $description;
                        $description .= "<p>Graag een account maken voor:</p><br>";
                        $description .= "<p>b_nummer: $b_nummer</p>";
                        $description .= "<p>upn: $b_nummer\@atlascollege.nl</p>";
                        $description .= "<p>Naam: $fullName</p>";
                        $description .= "<p>Locatie: $entry->{'locatie'}</p>";
                        my $payload = {
                            "fields" => {
                                'SLAPriorityLookupId' => '5',
                                'StatusLookupId' => '1',
                                'TicketType' => 'Incident',
                                'RequesterLookupId' => '12',
                                'AssignedTeamLookupId' => '4',
                                'Origin' => 'Self Service',
                                'Title'	=> "Mutatie: $b_nummer $type $entry->{'locatie'}",
                                'Description' => $description
                            }
                        };
                        my $result = $spo_object->list_item_create($payload);
                        if (! $result->is_success){
                            print Dumper $result;
                        }
                    }else{
                        say "Is al een ticket voor $type $b_nummer";
                    }
                }
            }
            case 'move'{
                say 'Move';
                foreach my $entry (@{$actions}){
                    my $b_nummer = 'b'.$entry->{'stamnr'};
                    if(! grep( /$b_nummer$/, @b_nummers)){
                        my $description;
                        $description .= "<p>Leerling $b_nummer verhuizen van $entry->{'locatie_oud'} naar $entry->{'locatie_nieuw'}</p>";
                        my $payload = {
                            "fields" => {
                                'SLAPriorityLookupId' => '5',
                                'StatusLookupId' => '1',
                                'TicketType' => 'Incident',
                                'RequesterLookupId' => '12',
                                'AssignedTeamLookupId' => '4',
                                'Origin' => 'Self Service',
                                'Title'	=> "Mutatie: $b_nummer $type",
                                'Description' => $description
                            }
                        };
                        my $result = $spo_object->list_item_create($payload);
                        if (! $result->is_success){
                            print Dumper $result;
                        }

                    }else{
                        say "Is al een ticket voor $type $b_nummer";
                    }
                }
            }
            case 'mutate'{
                say 'mutate';
                open(my $FH, '>', "$FindBin::Bin/mutaties/mutaties.json") or die $!;
                my $json = JSON->new->allow_nonref;
                print $FH $json->pretty->encode($actions);
            }
            else {
                say "Default action for $type";
                my $json = JSON->new->allow_nonref;
                say $json->pretty->encode($actions);
            }
        }
    }
}

