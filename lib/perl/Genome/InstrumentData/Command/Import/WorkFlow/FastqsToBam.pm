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
    roles => [qw/ Genome::InstrumentData::Command::Import::WorkFlow::Role::WithWorkingDirectory /],
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
};

sub execute {
    my $self = shift;
    $self->debug_message('Fastqs to bam...');

    my $unarchive_if_necessary = $self->_unarchive_fastqs_if_necessary;
    return if not $unarchive_if_necessary;

    my $fastq_to_bam_ok = $self->_fastqs_to_bam;
    return if not $fastq_to_bam_ok;

    my $verify_bam_ok = $self->_verify_bam;
    return if not $verify_bam_ok;

    $self->debug_message('Fastqs to bam...done');
    return 1;
}

sub _unarchive_fastqs_if_necessary {
    my $self = shift;
    $self->debug_message('Unarchive fastqs if necessary...');

    my @new_fastq_paths;
    for my $fastq_path ( $self->fastq_paths ) {
        if ( $fastq_path !~ /\.gz$/ ) {
            $self->debug_message('Unarchive not necessary for '.$fastq_path);
            push @new_fastq_paths, $fastq_path;
            next;
        }
        $self->debug_message('Unarchiving: '.$fastq_path);
        
        my $success = try {
            Genome::Sys->shellcmd(cmd => [ 'gunzip', $fastq_path ]);
        }
        catch {
            $self->error_message($_) if $_;
            $self->error_message('Failed to gunzip fastq!');
            return;
        };
        return if not $success;

        my $unarchived_fastq_path = $fastq_path;
        $unarchived_fastq_path =~ s/\.gz$//;
        $self->debug_message("Unarchived fastq: $unarchived_fastq_path");
        if ( not -s $unarchived_fastq_path ) {
            $self->error_message('Unarchived fastq does not exist!');
            return;
        }
        push @new_fastq_paths, $unarchived_fastq_path;
        unlink $fastq_path;
    }
    $self->fastq_paths(\@new_fastq_paths);

    $self->debug_message('Unarchive fastqs if necessary...');
    return 1;
}

sub _fastqs_to_bam {
    my $self = shift;
    $self->debug_message('Run picard fastq to sam...');

    my @fastqs = $self->fastq_paths;
    $self->debug_message("Fastq 1: $fastqs[0]");
    my $output_bam_path = $self->output_path;
    my %fastq_to_sam_params = (
        fastq => $fastqs[0],
        output => $output_bam_path,
        quality_format => 'Standard',
        sample_name => $self->library->sample->name,
        library_name => $self->library->name,
        read_group_name => UR::Object::Type->autogenerate_new_object_id_uuid,
        use_version => '1.113',
    );
    if ( $fastqs[1] ) {
        $self->debug_message("Fastq 2: $fastqs[1]");
        $fastq_to_sam_params{fastq2} = $fastqs[1];
    }
    $self->debug_message("Bam path: $output_bam_path");

    my $cmd = Genome::Model::Tools::Picard::FastqToSam->create(%fastq_to_sam_params);
    if ( not $cmd ) {
        $self->error_message('Failed to create sam to fastq command!');
        return;
    }
    my $success = try {
        $cmd->execute;
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

    $self->debug_message('Bam read count: '.$flagstat->{total_reads});

    $self->debug_message('Verify bam...done');
    return 1;
}

1;

