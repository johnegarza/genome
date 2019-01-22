package Genome::InstrumentData::Command::Import::WorkFlow::FastqsToBam;

use strict;
use warnings;

use Genome;

use Data::Dumper 'Dumper';
require File::Basename;
require File::Spec;
require Genome::Utility::Text;
require List::Util;
use Try::Tiny;

class Genome::InstrumentData::Command::Import::WorkFlow::FastqsToBam { 
    is => 'Command::V2',
    roles => [qw/ 
        Genome::InstrumentData::Command::Import::WorkFlow::Role::WithWorkingDirectory
        Genome::InstrumentData::Command::Import::WorkFlow::Role::RemovesInputFiles
    /],
    has_input => [
        fastq_paths => { 
            is => 'FilePath',
            is_many => 1,
            doc => 'Paths of the fastq[s] to convert to a bam.',
        },
        library => {
            is => 'Genome::Library',
            doc => 'The library to get the SAM RG header. The LB tag will use the library name, and the SM tag will use the sample name. The RG ID is an autogenerated id to be used as the instrument data ID.',
        },
    ],
    has_output => [ 
        output_path => {
            is => 'FilePath',
            calculate_from => [qw/ working_directory library /],
            calculate => q| return File::Spec->join($working_directory, Genome::Utility::Text::sanitize_string_for_filesystem($library->sample->name).'.bam'); |,
            doc => 'The path of the bam.',
        },
    ],
    has_optional_transient => {
        read_count => { is => 'Number', },
    },
};

sub execute {
    my $self = shift;
    $self->debug_message('Fastqs to bam...');

    my $get_fastq_read_counts = $self->_get_fastq_read_counts;
    return if not $get_fastq_read_counts;

    my $fastq_to_bam_ok = $self->_fastqs_to_bam;
    return if not $fastq_to_bam_ok;

    my $verify_bam_ok = $self->_verify_bam;
    return if not $verify_bam_ok;

    $self->debug_message('Fastqs to bam...done');
    return 1;
}

sub _get_fastq_read_counts {
    my $self = shift;
    $self->debug_message('Getting fastq read count...');

    my @line_counts;
    for my $fastq_path ( $self->fastq_paths ) {
        $self->debug_message('Fastq: %s', $fastq_path);
        my $line_count = Genome::Sys->line_count($fastq_path);
        $self->fatal_message('Fastq does not have any lines! %s', $fastq_path) if not $line_count > 0;
        $self->fatal_message('Fastq does not have correct number of lines! %s', $fastq_path) if $line_count % 4 != 0;
        $self->debug_message('Fastq line count: %s', $line_count);
        push @line_counts, $line_count;
    }

    $self->fatal_message('Fastqs do not have the same line counts!') if List::MoreUtils::uniq(@line_counts) != 1;
    my $read_count = List::Util::sum(@line_counts) / 4;
    $self->debug_message("Fastq read count: $read_count");

    return $self->read_count($read_count);
}

sub _fastqs_to_bam {
    my $self = shift;
    $self->debug_message('Run picard fastq to sam...');

    my @fastqs = $self->fastq_paths;
    $self->debug_message("Fastq 1: $fastqs[0]");

    my $output_bam_path = $self->output_path;

    my @cmd = (qw(/gapp/x64linux/opt/java/jre/jre1.8.0_31/bin/java -Xmx16g -jar /gscmnt/gc2560/core/software/picard/2.15.0/picard.jar FastqToSam), 'O='. $output_bam_path, 'SM='. $self->library->sample->name, 'LB='. $self->library->name, 'RG='. UR::Object::Type->autogenerate_new_object_id_uuid, 'F1='. $fastqs[0]);
    if ( $fastqs[1] ) {
        $self->debug_message("Fastq 2: $fastqs[1]");
        push @cmd, 'F2='. $fastqs[1];
    }
    $self->debug_message("Bam path: $output_bam_path");
    if ( not $cmd ) {
        $self->error_message('Failed to create sam to fastq command!');
        return;
    }
    my $success = try {
        Genome::Sys->shellcmd(
            cmd => \@cmd,
            input_files => \@fastqs,
            output_files => [ $output_bam_path ],
        );
    }
    catch {
        $self->error_message($_) if $_;
        $self->error_message('Failed to run picard fastq to sam!');
        return;
    };
    return if not $success;

    if ( not -s $output_bam_path ) {
        $self->error_message('Ran picard fastq to sam, but bam path does not exist!');
        return;
    }

    $self->debug_message('Run picard fastq to sam...done');
    return 1;
}

sub _verify_bam {
    my $self = shift;
    $self->debug_message('Verify bam...');

    my $helpers = Genome::InstrumentData::Command::Import::WorkFlow::Helpers->get;

    my $flagstat = $helpers->validate_bam($self->output_path);
    return if not $flagstat;

    $self->debug_message('Bam read count:  %s', $flagstat->{total_reads});
    $self->debug_message('Fastq read count: %s', $self->read_count);
    $self->fatal_message('Lost converting fastq to bam!') if $flagstat->{total_reads} != $self->read_count;

    $self->debug_message('Verify bam...done');
    return 1;
}

1;

