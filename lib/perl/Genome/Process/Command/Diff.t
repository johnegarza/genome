#!/usr/bin/env genome-perl

BEGIN { 
    $ENV{UR_DBI_NO_COMMIT} = 1;
    $ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = 1;
}

use strict;
use warnings;

use above "Genome";
use Test::More;
use Cwd qw(abs_path);

my $pkg = 'Genome::Process::Command::Diff';
use_ok($pkg) || die;

{
    package TestProcess;

    use strict;
    use warnings FATAL => 'all';
    use Genome;

    class TestProcess {
        is => ["Genome::Process"],
    };

    sub symlink_results {
        my $self = shift;
        my $destination = shift;

        Genome::Sys->create_directory($destination);
        my $result = $self->result_with_label("test");
        Genome::Sys->symlink_directory($result->output_dir, $destination);
    }
}
{
    package TestResult;

    use strict;
    use warnings FATAL => 'all';
    use Genome;

    class TestResult {
        is => ['Genome::SoftwareResult'],
    };
}

my $p1 = TestProcess->create();
ok($p1, "Created TestProcess object");

my $p2 = TestProcess->create();
ok($p2, "Created 2nd TestProcess object");

my $result1 = TestResult->create(test_name => "result1");
$result1->add_user(user => $p1, label => 'test');

my $result2 = TestResult->create(test_name => "result2");
$result2->add_user(user => $p2, label => 'test');

my $test_dir = abs_path(__FILE__).".d";

my %tests = (
    identical  => {
        test_name  => 'Identical directories',
        diff_count => 0,
    },
    missing    => {
        test_name  => 'Missing file',
        diff_count => 1,
        diff_message => 'no file',
    },
);

while (my ($subdir, $test_info) = each %tests) {
    subtest $test_info->{test_name} => sub {
        $result1->output_dir(File::Spec->join($test_dir, 'original'));
        $result2->output_dir(File::Spec->join($test_dir, $subdir));
        my $cmd = Genome::Process::Command::Diff->create(
           new_process => $p1,
           blessed_process => $p2
        );
        ok($cmd, "Command created for test $subdir");
        ok($cmd->execute, "Command executed for test $subdir");
    };
}

done_testing;

