#!/usr/bin/env genome-perl

use strict;
use warnings FATAL => 'all';

BEGIN {
    $ENV{UR_DBI_NO_COMMIT} = 1;
    $ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = 1;
};

use above "Genome";
use Sub::Install;
use Set::Scalar;
use Genome::Model::Tools::DetectVariants2::Result::Vcf;
use Genome::Model::Tools::Vcf::AnnotateWithReadcounts;
use Genome::Test::Factory::Process;
use Genome::VariantReporting::Framework::TestHelpers qw(
    test_cmd_and_result_are_in_sync
    get_translation_provider
    get_plan_object
);
use Genome::VariantReporting::Framework::Plan::TestHelpers qw(
    set_what_interpreter_x_requires
);
use Test::More;

my $RESOURCE_VERSION = 2;
my $data_dir = __FILE__.".d";

my $cmd_class = 'Genome::VariantReporting::Suite::BamReadcount::Annotate';
use_ok($cmd_class) or die;

my $result_class = 'Genome::VariantReporting::Suite::BamReadcount::AnnotateResult';
use_ok($result_class) or die;

set_what_interpreter_x_requires('bam-readcount');

my ($cmd, $tool_args) = generate_test_cmd();

ok($cmd->execute(), 'Command executed');
is(ref($cmd->output_result), $result_class, 'Found software result after execution');

my $expected_tool_args = {
    vcf_file => __FILE__,
    readcount_file_and_sample_name => ['rc_file1:sample1', 'rc_file2:sample2'],
};
is_deeply($tool_args, $expected_tool_args, 'Called Genome::Model::Tools::Vcf::AnnotateWithReadcounts with expected args');

test_cmd_and_result_are_in_sync($cmd);

done_testing();

sub generate_test_cmd {
    my $tool_args = {}; # gets filled in by $cmd->execute()
    Sub::Install::reinstall_sub({
        into => 'Genome::Model::Tools::Vcf::AnnotateWithReadcounts',
        as => '_execute_body',
        code => sub {
            my $self = shift;
            my $file = $self->output_file;
            `touch $file`;
            $tool_args->{vcf_file} = $self->vcf_file;
            $tool_args->{readcount_file_and_sample_name} = [$self->readcount_file_and_sample_name];
    }});

    my $rc_result1 = Genome::VariantReporting::Suite::BamReadcount::RunResult->__define__();
    my $rc_result2 = Genome::VariantReporting::Suite::BamReadcount::RunResult->__define__();

    Sub::Install::reinstall_sub({
        into => 'Genome::VariantReporting::Suite::BamReadcount::AnnotateResult',
        as => 'readcount_file_and_sample_names',
        code => sub {my $self = shift; return ['rc_file1:sample1', 'rc_file2:sample2'];},
    });

    my $process = Genome::Test::Factory::Process->setup_object();

    my $provider = get_translation_provider(version => $RESOURCE_VERSION);

    my $plan_file = File::Spec->join($data_dir, 'plan.yaml');
    my $plan = get_plan_object( plan_file => $plan_file, provider => $provider );

    my %params = (
        readcount_results => [$rc_result1, $rc_result2],
        input_vcf => __FILE__,
        variant_type => 'snvs',
        process_id => $process->id,
        plan_json => $plan->as_json,
    );
    my $cmd = $cmd_class->create(%params);
    return $cmd, $tool_args;
}
