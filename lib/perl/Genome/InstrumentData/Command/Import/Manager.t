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
require Digest::MD5;
require Genome::Utility::Test;
use Test::More;

use_ok('Genome::InstrumentData::Command::Import::Manager') or die;

my $test_dir = Genome::Utility::Test->data_dir_ok('Genome::InstrumentData::Command::Import::Manager', 'v1');
my $source_files_tsv = $test_dir.'/info.tsv';
my @source_files = (qw/ bam1 bam2 bam3 /);

# Sample needed
my $manager = Genome::InstrumentData::Command::Import::Manager->create(
    source_files_tsv => $source_files_tsv,
    list_config => "printf %s NOTHING_TO_SEE_HERE;1;2",
    launch_config => "echo %{job_name} LAUNCH!",
);
ok($manager, 'create manager');
ok($manager->execute, 'execute');

my $imports_aryref = $manager->_imports;
is_deeply([ map { $_->{status} } @$imports_aryref ], [qw/ no_sample no_sample no_sample /], 'imports aryref status');
is_deeply([ map { $_->{sample_name} } @$imports_aryref ], [qw/ TeSt-0000-00 TeSt-0000-00 TeSt-0000-01 /], 'imports aryref sample_name');
is_deeply([ map { $_->{source_files} } @$imports_aryref ], \@source_files, 'imports aryref source_files');
is_deeply([ map { $_->{instrument_data_attributes} } @$imports_aryref ], [ ["lane=\'8\'"], ["lane=\'8\'"], ["lane=\'7\'"], ], 'imports aryref instrument_data_attributes');
is_deeply([ map { $_->{job_name} } @$imports_aryref ], [qw/ TeSt-0000-00.1 TeSt-0000-00.2 TeSt-0000-01.1 /], 'imports aryref job_name');
ok(!grep({ $_->{job_status} } @$imports_aryref), 'imports aryref does not have job_status');
ok(!grep({ $_->{sample} } @$imports_aryref), 'imports aryref does not have sample');
ok(!grep({ $_->{libraries} } @$imports_aryref), 'imports aryref does not have library');
ok(!grep({ $_->{instrument_data} } @$imports_aryref), 'imports aryref does not have instrument_data');
ok(!grep({ $_->{instrument_data_file} } @$imports_aryref), 'imports aryref does not have instrument_data_file');

# Define samples
my $base_sample_name = 'TeSt-0000-0';
my @samples;
for (0..1) { 
    push @samples, Genome::Sample->__define__(
        id => -111 + $_,
        name => $base_sample_name.$_,
        nomenclature => 'TeSt',
    );
}
is(@samples, 2, 'define 2 samples');

# Library needed
$manager = Genome::InstrumentData::Command::Import::Manager->create(
    source_files_tsv => $source_files_tsv,
    list_config => "printf %s NOTHING_TO_SEE_HERE;1;2",
    launch_config => "echo %{job_name} LAUNCH!",
);
ok($manager, 'create manager');
ok($manager->execute, 'execute');

$imports_aryref = $manager->_imports;
is_deeply([ map { $_->{status} } @$imports_aryref ], [qw/ no_library no_library no_library /], 'imports aryref status');
is_deeply([ map { $_->{sample_name} } @$imports_aryref ], [qw/ TeSt-0000-00 TeSt-0000-00 TeSt-0000-01 /], 'imports aryref sample_name');
is_deeply([ map { $_->{source_files} } @$imports_aryref ], \@source_files, 'imports aryref source_files');
is_deeply([ map { $_->{instrument_data_attributes} } @$imports_aryref ], [ ["lane=\'8\'"], ["lane=\'8\'"], ["lane=\'7\'"], ], 'imports aryref instrument_data_attributes');
is_deeply([ map { $_->{job_name} } @$imports_aryref ], [qw/ TeSt-0000-00.1 TeSt-0000-00.2 TeSt-0000-01.1 /], 'imports aryref job_name');
is_deeply([ map { $_->{sample} } @$imports_aryref ], [$samples[0], $samples[0], $samples[1]], 'imports aryref sample');
ok(!grep({ $_->{libraries} } @$imports_aryref), 'imports aryref does not have library');
ok(!grep({ $_->{job_status} } @$imports_aryref), 'imports aryref does not have job_status');
ok(!grep({ $_->{instrument_data} } @$imports_aryref), 'imports aryref does not have instrument_data');
ok(!grep({ $_->{instrument_data_file} } @$imports_aryref), 'imports aryref does not have instrument_data_file');

# Define libraries
my @libraries;
for (0..1) { 
    push @libraries, Genome::Library->__define__(
        id => -222 + $_,
        name => $base_sample_name.$_.'-extlibs',
        sample => $samples[$_]
    );
}
is(@libraries, 2, 'define 2 libraries');

# Import needed
$manager = Genome::InstrumentData::Command::Import::Manager->create(
    source_files_tsv => $source_files_tsv,
    list_config => "printf %s NOTHING_TO_SEE_HERE;1;2",
);
ok($manager, 'create manager');
ok($manager->execute, 'execute');

$imports_aryref = $manager->_imports;
is_deeply([ map { $_->{status} } @$imports_aryref ], [qw/ needed needed needed /], 'imports aryref status');
is_deeply([ map { @{$_->{libraries}} } @$imports_aryref ], [$libraries[0], $libraries[0], $libraries[1]], 'imports aryref library');
ok(!grep({ $_->{job_status} } @$imports_aryref), 'imports aryref does not have job_status');
ok(!grep({ $_->{instrument_data} } @$imports_aryref), 'imports aryref does not have instrument_data');
ok(!grep({ $_->{instrument_data_file} } @$imports_aryref), 'imports aryref does not have instrument_data_file');

is($manager->_list_command, 'printf %s NOTHING_TO_SEE_HERE', '_list_command');
is($manager->_list_job_name_column, 0, '_list_job_name_column');
is($manager->_list_status_column, 1, '_list_status_column');

# One has import running, others are needed
$manager = Genome::InstrumentData::Command::Import::Manager->create(
    source_files_tsv => $source_files_tsv,
    list_config => 'printf "%s %s\\n%s %s\\n%s %s" TeSt-0000-00.1 pend TeSt-0000-00.2 run TeSt-0000-01.1 run;1;2',
    launch_config => "echo %{job_name} LAUNCH!",
);
ok($manager, 'create manager');
ok($manager->execute, 'execute');

$imports_aryref = $manager->_imports;
is_deeply([ map { $_->{status} } @$imports_aryref ], [qw/ pend run run /], 'imports aryref status');
is_deeply([ map { $_->{job_status} } @$imports_aryref ], [qw/ pend run run /], 'imports aryref job_status');
ok(!grep({ $_->{instrument_data} } @$imports_aryref), 'imports aryref does not have instrument_data');
ok(!grep({ $_->{instrument_data_file} } @$imports_aryref), 'imports aryref does not have instrument_data_file');

# Print commands
$manager = Genome::InstrumentData::Command::Import::Manager->create(
    source_files_tsv => $source_files_tsv,
    launch_config => "echo %{job_name} LAUNCH!", # successful imports, will not launch
    show_import_commands => 1,
);
ok($manager, 'create manager');
ok($manager->execute, 'execute');

# Create inst data
my @inst_data;
for my $import_hashref ( @$imports_aryref ) {
    my $inst_data = Genome::InstrumentData::Imported->__define__(
        original_data_path => $import_hashref->{source_files},
        sample => $import_hashref->{sample},
        subset_name => '1-XXXXXX',
        sequencing_platform => 'solexa',
        import_format => 'bam',
        description => 'import test',
    );
    $inst_data->add_attribute(attribute_label => 'bam_path', attribute_value => $source_files_tsv);
    push @inst_data, $inst_data;
}
is(@inst_data, 3, 'define 3 inst data');

# Fake successful imports by pointing bam_path to existing info.tsv
$manager = Genome::InstrumentData::Command::Import::Manager->create(
    source_files_tsv => $source_files_tsv,
    list_config => "printf %s NOTHING_TO_SEE_HERE;1;2",
    launch_config => "echo %{job_name} LAUNCH!", # successful imports, will not launch
);
ok($manager, 'create manager');
ok($manager->execute, 'execute');

$imports_aryref = $manager->_imports;
is_deeply([ map { $_->{status} } @$imports_aryref ], [qw/ success success success /], 'imports aryref status');
is_deeply([ map { $_->{instrument_data} } @$imports_aryref ], \@inst_data, 'imports aryref instrument_data');
is_deeply([ map { $_->{instrument_data_file} } @$imports_aryref ], [$source_files_tsv, $source_files_tsv, $source_files_tsv], 'imports aryref source_files');
ok(!grep({ $_->{job_status} } @$imports_aryref), 'imports aryref does not have job_status');

is_deeply(
    [ map { $manager->_resolve_launch_command_for_import($_) } @$imports_aryref ],
    [
        "echo TeSt-0000-00.1 LAUNCH! genome instrument-data import basic --sample name=TeSt-0000-00 --source-files bam1 --import-source-name TeSt --instrument-data-properties lane='8'",
        "echo TeSt-0000-00.2 LAUNCH! genome instrument-data import basic --sample name=TeSt-0000-00 --source-files bam2 --import-source-name TeSt --instrument-data-properties lane='8'",
        "echo TeSt-0000-01.1 LAUNCH! genome instrument-data import basic --sample name=TeSt-0000-01 --source-files bam3 --import-source-name TeSt --instrument-data-properties lane='7'",
     ],
     'launch commands',
);

# fail - no name column in csv
$manager = Genome::InstrumentData::Command::Import::Manager->create(
    source_files_tsv => $test_dir.'/invalid-no-sample-name-column.tsv',
);
ok($manager, 'create manager');
ok(!$manager->execute, 'execute failed');
is($manager->error_message, 'Property \'source_files_tsv\': No "sample_name" column in sample info file! '.$manager->source_files_tsv, 'correct error');

done_testing();
