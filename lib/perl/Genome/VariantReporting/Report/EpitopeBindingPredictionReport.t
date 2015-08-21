#!/usr/bin/env genome-perl

BEGIN {
    $ENV{UR_DBI_NO_COMMIT} = 1;
    $ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = 1;
}

use strict;
use warnings;

use above "Genome";
use Test::More;
use Genome::Utility::Test qw(compare_ok);
use Set::Scalar;
use List::MoreUtils qw(each_array);
use Genome::File::Vcf::Entry;
use Genome::VariantReporting::Report::TestHelper qw(test_report_result);

my $pkg = 'Genome::VariantReporting::Report::EpitopeBindingPredictionReport';
use_ok($pkg);

my $factory = Genome::VariantReporting::Framework::Factory->create();
isa_ok($factory->get_class('reports', $pkg->name), $pkg);

my $data_dir = __FILE__.".d";

subtest 'report subroutine' => sub {
    test_report_result(
        data_dir => $data_dir,
        pkg => $pkg,
        interpretations => interpretations(),
    );
};

done_testing;

sub interpretations {
    return {
        'epitope-variant-sequence' => {
            T => {
                variant_sequences => {
                    '>WT.PRAMEF4.p.R195H' => 'KKLKILGMPFRNIRSILKMVN',
                    '>MT.PRAMEF4.p.R195H' => 'KKLKILGMPFHNIRSILKMVN',
                }
            }
        },
    };
}

1;
