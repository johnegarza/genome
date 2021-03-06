#!/usr/bin/env genome-perl

use strict;
use warnings;

use above "Genome";
use Test::More;
use Test::Exception;

my $pkg = 'Genome::Model::Tools::Picard';
use_ok($pkg);

my $picard = $pkg->create();

isa_ok($picard, $pkg);

# should get default versions since we do not specify
my $picard_version = $picard->use_version();
ok(-e $picard->path_for_picard_version($picard_version), "picard version ($picard_version) exists");


my $newest_picard_version = $picard->latest_version();
ok(-e $picard->path_for_picard_version($newest_picard_version), "newest picard version ($newest_picard_version) exists");

## email test
SKIP: {
    skip 'monitor_shellcmd test can be annoying', 3 unless($ENV{'MONITOR_SHELLCMD_TEST'});

    my $test_subcmd;

    ok($test_subcmd = File::Temp->new(SUFFIX => ".pl"), 'opening temp pl');
    $test_subcmd->autoflush(1);
    ok($test_subcmd->print(q|
#!/usr/bin/env genome-perl

use strict;
use warnings;

use IO::Handle;

STDOUT->autoflush(1);

for (0..6) {
    sleep 1;

    if ($_ && $_ % 5 == 0) {
        sleep 7;
    }
    print $_ . "\n";
}
|),'writing temp pl');

    my $picard_cmd = $pkg->create(
        _monitor_check_interval => 1,
        _monitor_stdout_interval => 5,
        _monitor_mail_to => Genome::Sys->username,
    );

    my $rv;
    ok($rv = $picard_cmd->monitor_shellcmd({
        cmd => 'perl ' . $test_subcmd->filename
    }),'run temp pl');

};

subtest "Version compare" => sub {
    my @less_cases = (
        ["1.85", "1.123"],
        ["1.05", "1.05.1"]
        );

    for my $v (@less_cases) {
        ok($pkg->version_compare($v->[0], $v->[1]) < 0, "$v->[0] < $v->[1]");
        ok($pkg->version_compare($v->[1], $v->[0]) > 0, "$v->[1] > $v->[0]");
        ok($pkg->version_compare($v->[0], $v->[0]) == 0, "$v->[0] == $v->[0]");
        ok($pkg->version_compare($v->[1], $v->[1]) == 0, "$v->[1] == $v->[1]");
    }
};

class PicardTest {
    is => $pkg,
    has => { minimum_version_required => { is => 'Text', }, },
};
my $obj = PicardTest->create;

subtest "Enforce minimum version" => sub {


    # These are ordered from greatest to least
    my @versions = $pkg->_versions_serial;
    for my $i (0..$#versions) {
        my @failures;

        my $ver = $versions[$i];
        $obj->use_version($ver);

        # For each version greater than or equal to the given version
        for my $j (0..($i-1)) {
            my $min_ver = $versions[$j];
            # omg hush!
            $obj->minimum_version_required($min_ver);
            eval { $obj->enforce_minimum_version_required; };
            if (!$@) {
                push @failures, "$min_ver > $ver";
            }
        }

        # For each version less than the given version
        for my $j ($i..$#versions) {
            my $min_ver = $versions[$j];
            $obj->minimum_version_required($min_ver);
            if (!$obj->enforce_minimum_version_required) {
                push @failures, "$min_ver <= $ver";
            }
        }

        ok(!@failures, "version $ver behaves as expected")
            or diag("Failures: " . Data::Dumper::Dumper(\@failures));
    }

};

subtest 'Available picard versions' => sub{
    plan tests => 3;

    $obj->minimum_version_required(undef);
    my @versions = $obj->available_picard_versions;
    ok(@versions, 'all available picard versions');

    $obj->minimum_version_required($versions[2]);
    my @versions_with_miniumum_required = $obj->available_picard_versions;
    is(@versions_with_miniumum_required, 3, '3 available versions with minimum required version set');
    cmp_ok(
        @versions, '>', @versions_with_miniumum_required, 
        'less versions available with minimum set',
    );

};

done_testing();
