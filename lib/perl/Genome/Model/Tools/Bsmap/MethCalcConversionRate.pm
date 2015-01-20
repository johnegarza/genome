package Genome::Model::Tools::Bsmap::MethCalcConversionRate;

use strict;
use warnings;
use Genome;

class Genome::Model::Tools::Bsmap::MethCalcConversionRate {
    is => 'Command',
    has => [
        snvs_file => {
            is => 'String',
            is_optional => 1,
            doc => 'Use snvs.hq file to calculate methylation conversion',
        },
        model_id => {
            is => 'String',
            is_optional => 1,
            doc => 'Use genome model ID to calculate methylation conversion',
        },
        output_file => {
            is => 'String',
            is_optional => 1,
            doc => 'Output methylation conversion',
        },
    ],
};

sub help_synopsis {
  return <<EOS
    gmt bsmap meth-calc-conversion-rate --model-id=394d6228a7b5487a9cb0ad0c448b5a44

    gmt bsmap meth-calc-conversion-rate --snvs-file=/gscmnt/gc9016/info/model_data/394d6228a7b5487a9cb0ad0c448b5a44/buildf92b6057072948c2a6056a3ee412d596/variants/snv/meth-ratio-2.74-d41d8cd98f00b204e9800998ecf8427e/MT/snvs.hq

EOS
}

sub help_brief {
    "calculate methylation conversion using Mitochondrial DNA or spiked lambda"
}

sub help_detail {
    "calculate methylation conversion using Mitochondrial DNA or spiked lambda"
}

sub bs_rate {
    my $filename = shift;
    my $chrom = shift;
	my $output_file = shift;

    my $count = 0;
    my $totalreads = 0;
    my $methreads = 0;

	my $reader = Genome::Utility::IO::SeparatedValueReader->create(
		headers => [qw(chr pos strand context ratio eff_CT_count C_count CT_count rev_G_count rev_GA_count CI_lower CI_upper)],
		separator => "\t",
		input => $filename,
	);
	while (my $data = $reader->next()) {
        if(($data->{strand} eq "-" && $data->{context} =~ /.CG../ ) || ($data->{strand} eq "+" && $data->{context} =~ /..CG./)){
            $totalreads = $totalreads + $data->{eff_CT_count};
            $methreads = $methreads + $data->{C_count};
        }
	}
	$reader->input->close();

    my $cfile = $output_file;
    if($chrom eq "MT"){
        print $cfile "\nMethylation conversion based on mtDNA:\n";
    }
    if($chrom eq "lambda"){
        print $cfile "\nMethylation conversion based on lambda:\n";
    }
    print $cfile "Meth reads\t=\t", $methreads, "\n";
    print $cfile "Total reads\t=\t", $totalreads, "\n";
    if ($totalreads != 0) {
        print $cfile "Bisulfite conversion (%)\t=\t", 100-($methreads/$totalreads*100), "\n\n";
    }
}

sub execute {
    my $self = shift;
    my $snvs_file = $self->snvs_file;
    my $model_id = $self->model_id;
    my $output_file = $self->output_file;

    if (!defined($snvs_file) && !defined($model_id) ){
        die("Must provide snvs file OR model ID.\n");
    }

    if (defined($snvs_file) && defined($model_id) ){
        die("Must provide snvs file OR model ID.\n");
    }

	my $cfile;
	if ($output) {
		open($cfile, '>', $output) or die;
	} else {
		$cfile = \*STDOUT;
	}


    if (defined($snvs_file)){
        # snvs
        if (-s "$snvs_file"){
            bs_rate($snvs_file, "MT", $cfile);
        }
        else {
            $self->error_message("can't find the snvs file");
        }
    }

    if (defined($model_id)){
        # get model IDs
        my $model = Genome::Model->get($model_id);
        # get the bam paths of the last succeeded build
        my $dir = $model->last_succeeded_build->data_directory;
        # flagstat 
        my @flagstat = glob("$dir/alignments/*flagstat");
        my (@field, $total, $duplicates, $mapped, $properly);
        for my $flagstat (@flagstat) {
            if (-s "$flagstat"){
                print $cfile "\nMethylation alignment status:\n";
                print $cfile $flagstat, "\n";

				my $flagstat_data = Genome::Model::Tools::Sam::Flagstat->parse_file_into_hashref($flagstat);
				print $cfile "Total read\t=\t", $flagstat_data->{total_reads}, "\n";

				print $cfile "Duplicates\t=\t", $flagstat_data->{reads_marked_duplicates}, "\n";
				if ($flagstat_data->{total_reads} != 0) {
					my $dupe_rate = $flagstat_data->{reads_marked_duplicates} / $flagstat_data->{total_reads} * 100;
					print $cfile "Duplicates rate (%)\t=\t", $dupe_rate, "\n";
				}

				print $cfile "Mapped read\t=\t", $flagstat_data->{reads_mapped}, "\n";
				if ($flagstat_data->{total_reads} != 0) {
					print $cfile "Mapped rate (%)\t=\t", $flagstat_data->{reads_mapped_percentage}, "\n";
				}

				print $cfile "Properly paired\t=\t", $flagstat_data->{reads_mapped_in_proper_pairs}, "\n";
				if ($flagstat_data->{total_reads} != 0) {
					print $cfile "Properly paired rate (%)\t=\t", $flagstat_data->{reads_mapped_in_proper_pairs_percentage}, "\n";
				}
            }
            else {
                $self->error_message("can't find flagstat file");
            }
        }

		my %cases = (
			MT => { glob => "$dir/variants/snv/meth-ratio-*/MT/snvs.hq", name => "mtDNA" },
			lambda => { glob => "$dir/variants/snv/meth-ratio-*/gi_9626243_ref_NC_001416.1_/snvs.hq", name => "lambda" },
		);
		for my $chrom (keys %cases) {
			my ($glob, $name) = ($cases{$chrom}{glob}, $cases{$chrom}{name});

			my @file = glob($glob);
			for my $file (@file) {
				if (-s "$file"){
					bs_rate($file, $chrom, $cfile);
				}
				else {
					$self->error_message("can't find $name snvs file");
				}
			}
		}
    }
	return 1;

}

1;
