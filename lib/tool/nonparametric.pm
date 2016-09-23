package tool::nonparametric;

use strict;
use Moose;
use MooseX::Params::Validate;
use File::Copy 'cp';
use include_modules;
use data;
use log;
use filter_data;
use tool::modelfit;

extends 'tool';

has 'npsupp' => ( is => 'rw', isa => 'ArrayRef');

sub BUILD
{
    my $self = shift;
}

sub modelfit_setup
{
	my $self = shift;
	my $modelfit;
	my $input_model = $self->models->[0];

	# if there are no estimation results available for the input model, then run the input model and read the estimation results
	unless ($input_model->is_run) {
		my $orig_fit = tool::modelfit->new( %{common_options::restore_options(@common_options::tool_options)},
											base_directory => $self -> directory(),
											directory => undef,
											models => [$input_model],
											raw_results => undef,
											top_tool => 0 );
		tool::add_to_nmoutput(run => $orig_fit, extensions => ['ext','cov']);		
		ui -> print( category => 'all',	message => 'Running input model' );
		$orig_fit -> run;
	}
	
	# check output model
	unless (defined( $input_model->outputs->[0] )){
		die "No output object from input model.";
	}
	
	unless (defined( $input_model->outputs->[0]->get_single_value(attribute => 'ofv') )){
		die "In output model are no ofv's.";
	}
		
	# check if number of individuals is larger than any of npsupp values
	my $N_individuals = $input_model->outputs->[0]->nind();
	my $indiv_number = ${$N_individuals}[0];
	for (my $i=0; $i<scalar(@{$self->npsupp});$i++) {
		my $npsupp_value = ${$self->npsupp}[$i];
		if ($npsupp_value < $indiv_number) {
			ui -> print(category => 'all',
						message => "Number of individuals $indiv_number is larger than NPSUPP values $npsupp_value.");
		}
	}
	
	my $problems_amount = scalar (@{$input_model-> problems});
	# find problem number
	my $probnum;
	for (my $i=1; $i <= $problems_amount; $i++) {
		if ( defined($input_model->problems->[$i-1]->estimations) && (scalar(@{$input_model->problems->[$i-1]->estimations})>0)) {
			$probnum = $i;
			last;
		}
	}

	# Update  initial estimates with the final estimates from the estimation.
	$input_model->update_inits( from_output => $input_model->outputs->[0],
								problem_number => $probnum);
								
	# if estimation method is classical, set option MAXEVAL=1 in Estimation
	if ($input_model->problems->[$probnum-1]->estimations->[-1]->is_classical) {
		$input_model->set_option(problem_numbers => [$probnum],
								 record_name => 'estimation',
								 record_number => -1,
								 option_name => 'MAXEVAL',
								 option_value => 1,
								 fuzzy_match => 1);
	}
	
	my $filestem = $input_model ->filename();
	#this regex must be the same as used in modelfit.pm, for consistency
	$filestem =~ s/\.[^.]+$//; #last dot and extension

	$input_model -> set_records(type => 'nonparametric',
							record_strings => ['UNCONDITIONAL']);
	
	# copy input model and add record NONPARAMETRIC with option NPSUPP and one option values from npsupp array
	my @models_array=();
	foreach my $value (@{$self->npsupp}){
		push(@models_array,$input_model -> copy(filename => $filestem.'_'.$value.'.mod',
												copy_datafile => 0,
												copy_output => 0,
												write_copy => 0,
												output_same_directory => 1,
												directory => $self->directory.'/m1'));
	
		$models_array[-1] -> add_option(record_name => 'nonparametric',
									option_name => 'NPSUPP',
									option_value => $value);
		$models_array[-1] -> _write;
	}

	#basedirect $main_directory
	$modelfit = 
	tool::modelfit->new( %{common_options::restore_options(@common_options::tool_options)},
	  prepend_model_file_name => 1,
	  directory => undef,
	  min_retries => 0,
	  retries => 0,
	  copy_data => 0,
	  top_tool => 0,
	  raw_results_file => [$self -> directory.$self->raw_results_file->[0]],
	  raw_nonp_file => [$self -> directory.$self->raw_nonp_file->[0]],
	  models => \@models_array );
        
	$self->tools([]) unless (defined $self->tools);
	push(@{$self->tools}, $modelfit);
}

sub modelfit_analyze
{
    my $self = shift;
    my $added_column = add_column(filename => $self->raw_nonp_file->[0], npsupp => $self->npsupp);
	overwrite_csv(filename => $self->raw_nonp_file->[0], rows => $added_column);

}

sub add_column
{
	my %parm = validated_hash(\@_,
							  filename => { isa => 'Str', optional => 0 },
							  npsupp => {isa => 'ArrayRef', optional => 0},
		);
	my $filename = $parm{'filename'};
	my $npsupp = $parm{'npsupp'};
	
	# Read in a csv file
	open( CSV, '<'."$filename" ) || die "Could not open $filename for reading";
	my @lines;
	my @exp;
	my $amount;
	while (my $line = <CSV> ) {
		chomp($line);
		my @tmp = ();
		if ($line =~ /^\"/) { 
			@tmp = split(/","/,$line);  # split columns where row consist of headers
			$tmp[0] =~ s/['\"']//g; 
			$tmp[scalar(@tmp)-1] =~ s/['\"']//g; 
		} else {
			@tmp = split(/,/,$line); # split columns where row consist of numbers
		}
	push(@lines,\@tmp);
		push(@exp,$line);
	}
	close( CSV );
	
	# check if nonmem croaks (data for some columns are missing, starting from 1th row)
	unless (scalar(@{$lines[0]}) == scalar(@{$lines[1]})) {
		die "Some data in csv files are missing.";
	}
	# check if exists text: "run failed: NONMEM run failed"
	for (my $i=0; $i < scalar(@{$lines[1]}); $i++) {
		if ($lines[1][$i] eq 'run failed: NONMEM run failed') {
			die "NONMEM failed.";
		}
	}
	
	# search position of the column "npofv"
	my $element = 'npofv';
	my $position;
	for (my $i=0; $i < scalar(@{$lines[0]}); $i++) {
		if ($lines[0][$i] eq $element) {
			$position = $i;
		}
	}
		
	# add column
	my @rows = ();
	unless ( defined $npsupp && (scalar(@{$npsupp}) > 0) ) {
		die "Error: Npsupp values are not defined or there are no npsupp values.";
	} else {
		splice @{$lines[0]}, $position+1 , 0, 'npsupp';
		$rows[0] = '"'.join('","',@{$lines[0]}).'"'."\n";
		for (my $n=0; $n < scalar(@{$npsupp}); $n++) {
			splice @{$lines[$n+1]}, $position+1 , 0, $npsupp->[$n];
			$rows[$n+1] = join(',',@{$lines[$n+1]})."\n";
		}
	}
	
	return(\@rows);
}

sub overwrite_csv
{
	my %parm = validated_hash(\@_,
							  filename => { isa => 'Str', optional => 0 },
							  rows => {isa => 'ArrayRef', optional => 0},
		);
	my $filename = $parm{'filename'};
	my $rows = $parm{'rows'};

	#write a csv file
	open (my $fh, '>' ."$filename");
	for (my $n=0; $n < (scalar(@{$rows})); $n++) {
		print $fh $rows->[$n];	# write each row in the csv file. 
	}
	close $fh;	
}

no Moose;
__PACKAGE__->meta->make_immutable;
1;