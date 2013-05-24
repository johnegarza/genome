#!/usr/bin/env genome-perl

BEGIN {
    $ENV{UR_DBI_NO_COMMIT} = 1;
    $ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = 1;
    $ENV{UR_COMMAND_DUMP_STATUS_MESSAGES} = 1;
}

use strict;
use warnings;

use above "Genome";
use Data::Dumper;
use Test::More;

use_ok('Genome::Sample::Command::Import::Manager') or die;
use_ok('Genome::Sample::Command::Import') or die;
Genome::Sample::Command::Import::_create_import_command_for_config({
        nomenclature => 'TeSt',
        name_regexp => '(TeSt-\d+)\-\d\d',
        taxon_name => 'human',
        #sample_attributes => [qw/ tissue_desc /],# tests array
        #individual_attributes => { # tests hash
        #    gender => { valid_values => [qw/ male female /], }, # tests getting meta from individual
        #    individual_common_name => {
        #        calculate_from => [qw/ _individual_name /],
        #        calculate => sub{ my $_individual_name = shift; $_individual_name =~ s/^TEST\-//i; return $_individual_name; },
        #    },
        #},
    });

class Reference { has => [ name => {}, ], };
my $ref = Reference->create(id => -333, name => 'reference-1');
ok($ref, 'created reference');
class Genome::Model::Ref {
    is => 'Genome::Model',
    has_param => [
        aligner => { is => 'Text', },
    ],
    has_input => [
        reference => { is => 'Reference', },
    ],
};
my $pp = Genome::ProcessingProfile::Ref->create(id => -333, name => 'ref pp #1', aligner => 'bwa');
ok($pp, 'create pp');

my $manager = Genome::Sample::Command::Import::Manager->create(
    working_directory => 'example/valid',
);
ok($manager, 'create manager');
ok($manager->execute, 'execute');
is($manager->namespace, 'Test', 'got namespace');
my $sample_name = 'TeSt-0000-00';
my %expected_samples = ( 
     $sample_name => {
        name => $sample_name,
        original_data_path => [ 'original.bam' ],
        importer_params => {
            name => $sample_name,
            sample_attributes => [qw/ gender='female' race='spaghetti' religion='pastafarian' /],
        },
        status => 'import_pend',
        job_status => 'pend',
        sample => Genome::Sample->get(name => $sample_name),
        model => Genome::Model::Ref->get('subject.name' => $sample_name),
        instrument_data => undef, bam_path => undef,
    },
);
my $samples = $manager->samples;
is_deeply($manager->samples, \%expected_samples, 'samples match');
ok(!$samples->{$sample_name}->{model}->auto_assign_inst_data, 'model auto_assign_inst_data is off');
ok(!$samples->{$sample_name}->{model}->auto_build_alignments, 'model auto_build_alignments is off');
print Dumper($samples);

# fail - no config file
$manager = Genome::Sample::Command::Import::Manager->create(
    working_directory => 'example/invalid/no-config-yaml',
);
ok($manager, 'create manager');
ok(!$manager->execute, 'execute');
is($manager->error_message, "Property 'config_file': Config file does not exist! ".$manager->config_file, 'correct error');

# fail - no config file
$manager = Genome::Sample::Command::Import::Manager->create(
    working_directory => 'example/invalid/no-sample-csv',
);
ok($manager, 'create manager');
ok(!$manager->execute, 'execute');
is($manager->error_message, "Property 'sample_csv_file': Sample csv file does not exist! ".$manager->sample_csv_file, 'correct error');

# fail - no name column in csv
$manager = Genome::Sample::Command::Import::Manager->create(
    working_directory => 'example/invalid/no-name-column-in-sample-csv',
);
ok($manager, 'create manager');
ok(!$manager->execute, 'execute');
is($manager->error_message, 'Property \'sample_csv_file\': No "name" column in sample csv! '.$manager->sample_csv_file, 'correct error');

done_testing();
