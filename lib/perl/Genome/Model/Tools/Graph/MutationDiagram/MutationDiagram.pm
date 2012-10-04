#TODO:: Remove the dependancies on the MG namespace
#----------------------------------
# $Authors: dlarson bshore $
# $Date: 2008-09-16 16:33:54 -0500 (Tue, 16 Sep 2008) $
# $Revision: 38655 $
# $URL: svn+ssh://svn/srv/svn/gscpan/perl_modules/trunk/MG/MutationDiagram.pm $
#----------------------------------
package Genome::Model::Tools::Graph::MutationDiagram::MutationDiagram;
#------------------------------------------------
our $VERSION = '1.0';
#------------------------------------------------
use strict;
use warnings;
use Carp;

use FileHandle;
use Genome;

use SVG;
use Genome::Model::Tools::Graph::MutationDiagram::MutationDiagram::View;
use Genome::Model::Tools::Graph::MutationDiagram::MutationDiagram::Backbone;
use Genome::Model::Tools::Graph::MutationDiagram::MutationDiagram::Domain;
use Genome::Model::Tools::Graph::MutationDiagram::MutationDiagram::Mutation;
use Genome::Model::Tools::Graph::MutationDiagram::MutationDiagram::Legend;
use Genome::Model::Tools::Graph::MutationDiagram::MutationDiagram::LayoutManager;

my @VEP_MUTATION_PRIORITY = (
    'ESSENTIAL_SPLICE_SITE',
    'FRAMESHIFT_CODING',
    'STOP_GAINED',
    'NON_SYNONYMOUS_CODING'
);

my %VEP_MUTATION_PRIORITIES;
@VEP_MUTATION_PRIORITIES{@VEP_MUTATION_PRIORITY} = 0..$#VEP_MUTATION_PRIORITY;

#------------------------------------------------
sub new {
    my ($class, %arg) = @_;

    my $self = {
        _mutation_file => $arg{annotation} || '',
        _annotation_format => $arg{annotation_format},
        _basename => $arg{basename} || '',
        _reference_transcripts => $arg{reference_transcripts} || '',
        _annotation_build_id => $arg{annotation_build_id} || '',
        _output_directory => $arg{output_directory} || '.',
        _vep_frequency_field => $arg{vep_frequency_field},
    };

    if ($self->{_annotation_build_id}) {
        $self->{_build} = Genome::Model::Build->get($self->{_annotation_build_id});
    }
    elsif ($self->{_reference_transcripts}) {
        my ($model_name, $version) = split('/', $self->{_reference_transcripts});
        my $model = Genome::Model->get(name => $model_name);
        unless ($model){
            $self->error_message("couldn't get reference transcripts set for $model_name");
            return;
        }
        my $build = $model->build_by_version($version);
        $self->{_build} = $build;
    }
    else {
        confess "No value supplied for reference_transcripts or annotation_build_id, abort!";
    }

    unless ($self->{_build}){
        $self->error_message("couldn't load reference trascripts set");
        return;
    }
    $self->{_reference_build_id} = $self->{_build}->reference_sequence_id;
    print STDERR "Using reference transcripts " . $self->{_build}->name . "\n";

    my @custom_domains =();
    if(defined($arg{custom_domains})) {
        my @domain_specification = split(',',$arg{custom_domains});

        while(@domain_specification) {
            my %domain = (type => "CUSTOM");
            @domain{qw(name start end)} = splice @domain_specification,0,3;
            push @custom_domains, \%domain;
        }
    }

    $self->{_custom_domains} = \@custom_domains;

    my @hugos = ();
    if (defined($arg{hugos})) {
        @hugos = split(',',$arg{hugos});
    }
    unless (scalar(@hugos)) {
        @hugos = qw( ALL );
    }
    $self->{_hugos} = \@hugos;
    bless($self, ref($class) || $class);
    die "No mutation file passed to $class" unless $arg{annotation};

    if ($self->{_annotation_format} eq 'vep') {
        $self->_parse_vep_annotation;
    }
    elsif ($self->{_annotation_format} eq 'tgi') {
        $self->Annotation;
    } else {
        die "Unknown annotation file format $self->{_annotation_format}";
    }
    $self->MakeDiagrams();
    return $self;
}

sub _get_transcript_and_domains {
    my ($self, $transcript_name) = @_;
    my $build = $self->{_build};
    my @features;
    my $transcript;
    for my $data_directory ($build->determine_data_directory){
        my $t = Genome::Transcript->get(
            data_directory => $data_directory,
            transcript_name => $transcript_name,
            reference_build_id => $self->{_reference_build_id}
            );
        next unless $t;
        $transcript = $t;
        push(@features, Genome::InterproResult->get(
            data_directory => $data_directory,
            transcript_name => $transcript_name,
            chrom_name => $transcript->chrom_name
            ));
    }
    if (!defined $transcript) {
        warn "No transcript found for $transcript_name";
        return;
    }

    my @domains;
    for my $feature (@features) {
        my ($source, @domain_name_parts) = split(/_/, $feature->name);
        # Some domain names are underbar delimited, but sources aren't.
        # Reassemble the damn domain name if necessary
        my $domain_name;
        if (scalar (@domain_name_parts) > 1){
            $domain_name = join("_", @domain_name_parts);
        }else{
            $domain_name = pop @domain_name_parts;
        }
        push @domains, {
            name => $domain_name,
            source => $source,
            start => $feature->start,
            end => $feature->stop
        };
    }
    push(@domains, @{$self->{_custom_domains}}) if $self->{_custom_domains}->[0];
    return $transcript, @domains;
}

sub _add_mutation {
    my ($self, %params) = @_;
    $self->{_data} = {} unless defined $self->{_data};
    my $data = $self->{_data};

    my $hugo = $params{hugo};
    my $transcript_name = $params{transcript_name};
    my $protein_length = $params{protein_length};
    my $protein_position = $params{protein_position};
    my $mutation = $params{mutation};
    my $class = $params{class};
    my $domains = $params{domains};
    my $frequency = $params{frequency} || 1;

    print STDERR "Adding mutation $hugo $transcript_name $mutation\n";

    $data->{$hugo}{$transcript_name}{length} = $protein_length;
    push @{$data->{$hugo}{$transcript_name}{domains}}, @$domains;

    if (defined($protein_position)) {
        unless (exists($data->{$hugo}{$transcript_name}{mutations}{$mutation})) {
            $data->{$hugo}{$transcript_name}{mutations}{$mutation} =
            {
                res_start => $protein_position,
                class => $class,
            };
        }
        $data->{$hugo}{$transcript_name}{mutations}{$mutation}{frequency} += $frequency;
    }
}

sub argmin(@) { # really perl?
    my @arr = @_;
    return unless @arr;
    return 0 if @arr <= 1;

    my $minidx = 0;
    for my $i (1..$#arr) {
        $minidx = $i if $arr[$i] < $arr[$minidx];
    }
    return $minidx;
}

sub _get_vep_mutation_class {
    my $type = shift;
    my @types = split(",", $type);
    my @type_matches = grep {defined $VEP_MUTATION_PRIORITIES{$_}} @types;
    return $type unless @type_matches;
    my @priorities = @VEP_MUTATION_PRIORITIES{@type_matches};
    my $idx = argmin(@priorities);
    return $type_matches[$idx];
}

sub _get_vep_extra_fields_hash {
    my $extra = shift;
    return { map { split("=") } split(";", $extra) }
}

sub _parse_vep_annotation {
    my $self = shift;

    my $build = $self->{_build};
    my $vep_file = $self->{_mutation_file};
    my $fh = Genome::Sys->open_file_for_reading($vep_file);
    print STDERR "Parsing VEP annotation file...\n";

    my $graph_all = $self->{_hugos}->[0] eq 'ALL' ? 1 : 0;
    my %hugos;
    unless($graph_all) {
        %hugos = map {$_ => 1} @{$self->{_hugos}}; #convert array to hashset
    }

    my $header = $fh->getline;
    chomp $header;

    while(my $line = $fh->getline) {
        chomp $line;
        my @fields = split("\t", $line);
        my ($hugo,$transcript_name,$class,$protein_pos,$aa_change) = @fields[3,4,6,9,10];
        next unless(defined($transcript_name) && $transcript_name !~ /^\s*$/);

        if($graph_all || exists($hugos{$hugo})) {
            $class = _get_vep_mutation_class($class);
            my ($transcript, @domains) = $self->_get_transcript_and_domains($transcript_name);
            next unless $transcript;
            #add to the data hash for later graphing
            my ($orig_aa, $new_aa) = split("/", $aa_change);
            $orig_aa |= '';
            $new_aa |= '';
            my $mutation = join($protein_pos, $orig_aa, $new_aa);
            next if $mutation eq '--';
            my $extra = _get_vep_extra_fields_hash($fields[-1]);
            my $frequency = 1;
            $frequency = $extra->{$self->{_vep_frequency_field}} if exists $extra->{$self->{_vep_frequency_field}};
            next if !$frequency;

            $self->_add_mutation(
                hugo => $hugo,
                transcript_name => $transcript_name,
                protein_length => $transcript->amino_acid_length,
                protein_position => $protein_pos,
                mutation => $mutation,
                class => $class,
                domains => \@domains,
                frequency => $frequency
            );
        }
    }
}

sub Annotation {
    #loads from annotation file format
    my $self = shift;

    my $build = $self->{_build};
    my $annotation_file = $self->{_mutation_file};
    my $fh = new FileHandle;
    unless($fh->open("$annotation_file")) {
        die "Could not open annotation file $annotation_file";
    }
    print STDERR "Parsing annotation file...\n";
    my %data;
    my $graph_all = $self->{_hugos}->[0] eq 'ALL' ? 1 : 0;
    my %hugos;
    unless($graph_all) {
        %hugos = map {$_ => 1} @{$self->{_hugos}}; #convert array to hashset
    }

    Genome::Model::Tools::Annotate::AminoAcidChange->class();  # Get the module loaded
    while(my $line = $fh->getline) {
        chomp $line;
        next if $line =~/^chromosome/;
        my @fields = split /\t/, $line;
        my ($hugo,$transcript_name,$class,$aa_change) = @fields[6,7,13,15];
        unless(defined($transcript_name) && $transcript_name !~ /^\s*$/ && $transcript_name ne '-') {
            next;
        }

        if($graph_all || exists($hugos{$hugo})) {
            my ($residue1, $res_start, $residue2, $res_stop, $new_residue) = @{Genome::Model::Tools::Annotate::AminoAcidChange::check_amino_acid_change_string(amino_acid_change_string => $aa_change)};
            my $mutation = $aa_change;
            $mutation =~ s/p\.//g;

            my ($transcript, @domains) = $self->_get_transcript_and_domains($transcript_name);
            next unless $transcript;

            $self->_add_mutation(
                hugo => $hugo,
                transcript_name => $transcript_name,
                protein_length => $transcript->amino_acid_length,
                protein_position => $res_start,
                mutation => $mutation,
                class => $class,
                domains => \@domains
            );

        }
    }
}

sub get_protein_length{
    my $self = shift; #TODO: this is not at all kosher, inuitive, or good.  Fix it when this becomes a UR object
    my $transcript_name = shift;
    my $build = $self->{_build};
    my $transcript;
    for my $dir ($build->determine_data_directory){
        $transcript = Genome::Transcript->get(data_directory => $dir, transcript_name => $transcript_name, reference_build_id => $self->{_reference_build_id});
        last if $transcript;
    }
    return 0 unless $transcript;
    return 0 unless $transcript->protein;
    return length($transcript->protein->amino_acid_seq);
}

sub Data {
    my ($self) = @_;
    return $self->{_data};
}

sub MakeDiagrams {
    my ($self) = @_;
    my $data = $self->{_data};
    my $basename = join("/", $self->{_output_directory}, $self->{_basename});
    foreach my $hugo (keys %{$data}) {
        foreach my $transcript (keys %{$data->{$hugo}}) {
            unless($self->{_data}{$hugo}{$transcript}{length}) {
                warn "$transcript has no protein length and is likely non-coding. Skipping...\n";
                next;
            }
            my $svg_file = $basename . $hugo . '_' . $transcript . '.svg';
            my $svg_fh = new FileHandle;
            unless ($svg_fh->open (">$svg_file")) {
                die "Could not create file '$svg_file' for writing $$";
            }
            $self->Draw($svg_fh,
                $hugo, $transcript,
                $self->{_data}{$hugo}{$transcript}{length},
                $self->{_data}{$hugo}{$transcript}{domains},
                $self->{_data}{$hugo}{$transcript}{mutations}
            );
            $svg_fh->close();
        }
    }
    return $self;
}

sub Draw {
    my ($self, $svg_fh, $hugo, $transcript, $length, $domains, $mutations) = @_;
    $DB::single = 1;
    my $document = Genome::Model::Tools::Graph::MutationDiagram::MutationDiagram::View->new(width=>'800',height=>'600',
        'viewport' => {x => 0, y => 0,
            width => 1600,
            height => 1200},
        left_margin => 50,
        right_margin => 50,
        id => "main_document");
    my $svg = $document->svg;

    my $backbone = Genome::Model::Tools::Graph::MutationDiagram::MutationDiagram::Backbone->new(parent => $document,
        gene => $hugo,
        protein_length => $length,
        backbone_height
        =>
        50,
        style => {fill => 'none', stroke => 'black'},
        id => "protein_diagram",
        $document->content_view);
    $backbone->draw;

    my @colors = qw( aliceblue azure blanchedalmond burlywood coral cyan darkgray darkmagenta darkred darkslategray deeppink dodgerblue fuchsia goldenrod grey indigo lavenderblush lightcoral lightgreen lightseagreen lightsteelblue mediumblue mediumslateblue midnightblue olivedrab palegoldenrod papayawhip plum rosybrown sandybrown slategrey tan );
    my $color = 0;
    my %domains;
    my %domains_location;
    my %domain_legend;
    foreach my $domain (@{$domains}) {
        if ($domain->{source} eq 'superfamily') {
            next;
        }
        my $domain_color;
        if (exists($domain_legend{$domain->{name}})) {
            $domain_color = $domain_legend{$domain->{name}};
        } else {
            $domain_color = $colors[$color++];
            $domain_legend{$domain->{name}} = $domain_color;
        }
        if (exists($domains_location{$domain->{name}}{$domain->{start} . $domain->{end}})) {
            next;
        }
        $domains_location{$domain->{name}}{$domain->{start} . $domain->{end}} += 1;
        $domains{$domain->{name}} += 1;
        my $subid = '';
        if ($domains{$domain->{name}} > 1) {
            $subid = '_subid' . $domains{$domain->{name}};
        }
        my $test_domain = Genome::Model::Tools::Graph::MutationDiagram::MutationDiagram::Domain->new(backbone => $backbone,
            start_aa => $domain->{start},
            stop_aa => $domain->{end},
            id => 'domain_' . $domain->{name} . $subid,
            text => $domain->{name},
            style => { fill => $domain_color,
                stroke => 'black'});
        $color++;
        $test_domain->draw;
    }
    my $domain_legend =
    Genome::Model::Tools::Graph::MutationDiagram::MutationDiagram::Legend->new(backbone => $backbone,
        id => 'domain_legend',
        x => $length / 2,
        values => \%domain_legend,
        object => 'rectangle',
        style => {stroke => 'black', fill => 'none'});
    $domain_legend->draw;

    my @mutation_objects;
    my %mutation_class_colors = (
        # tgi annotator colors
        'frame_shift_del' => 'darkolivegreen',
        'frame_shift_ins' => 'crimson',
        'in_frame_del' => 'gold',
        'missense' => 'cornflowerblue',
        'nonsense' => 'goldenrod',
        'splice_site_del' => 'orchid',
        'splice_site_ins' => 'saddlebrown',
        'splice_site_snp' => 'lightpink',

        # vep annotator colors
        'essential_splice_site' => 'orchid',
        'frameshift_coding' => 'darkolivegreen',
        'stop_gained' => 'goldenrod',
        'non_synonymous_coding' => 'cornflowerblue',


        'other' => 'black',
    );
    my %mutation_legend;
    my $max_frequency = 0;
    my $max_freq_mut;
    foreach my $mutation (keys %{ $mutations}) {
        $mutations->{$mutation}{res_start} ||= 0;
        my $mutation_color = $mutation_class_colors{lc($mutations->{$mutation}{class})};
        $mutation_color ||= $mutation_class_colors{'other'};
        $mutation_legend{$mutations->{$mutation}{class}} = $mutation_color;
        my $mutation_element =
        Genome::Model::Tools::Graph::MutationDiagram::MutationDiagram::Mutation->new(backbone => $backbone,
            id => $mutation,
            start_aa => $mutations->{$mutation}{res_start},
            text => $mutation,
            frequency => $mutations->{$mutation}{frequency},
            color => $mutation_color,
            style => {stroke => 'black', fill => 'none'});


        #jitter labels as a test
        push @mutation_objects, $mutation_element;
        if($mutations->{$mutation}{frequency} > $max_frequency) {
            $max_frequency = $mutations->{$mutation}{frequency};
            $max_freq_mut = $mutation_element;
        }
    }
    map {$_->vertically_align_to($max_freq_mut)} @mutation_objects;
    my $mutation_legend =
    Genome::Model::Tools::Graph::MutationDiagram::MutationDiagram::Legend->new(backbone => $backbone,
        id => 'mutation_legend',
        x => 0,
        values => \%mutation_legend,
        object => 'circle',
        style => {stroke => 'black', fill => 'none'});
    $mutation_legend->draw;


    my $layout_manager = Genome::Model::Tools::Graph::MutationDiagram::MutationDiagram::LayoutManager->new(iterations => 1000,
        max_distance => 13, spring_constant => 6, spring_force => 1, attractive_weight => 5 );
    $layout_manager->layout(@mutation_objects);

    map {$_->draw;} (@mutation_objects);

    # now render the SVG object, implicitly use svg namespace
    print $svg_fh $svg->xmlify;
}
