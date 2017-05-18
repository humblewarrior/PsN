package model_transformations;

use strict;
use warnings;
use include_modules;
use Cwd;
use model;
use PsN;
use MooseX::Params::Validate;

sub add_tv
{
    # Add TV (typical value) variable if it doesn't already exist for list of parameters
	my %parm = validated_hash(\@_,
        model => { isa => 'model' },
        parameters => { isa => 'ArrayRef' },
    );
    my $model = $parm{'model'};
    my $parameters = $parm{'parameters'};

    (my $code_record, my $code) = $model->get_pk_or_pred_code();

    my @add_params;     # Parameters that don't already have TVxx
    for my $param (@$parameters) {
        my $found = 0;
        for my $line (@$code) {
            if ($line =~ /^\s*TV$param\s*=/) {
                $found = 1;
            }
        }
        if (not $found) {
            push @add_params, $param;
        }
    }

    my @newcode;
    for my $line (@$code) {
        my $found = 0;
        for my $param (@add_params) {
            if ($line =~ /^(\s*)$param\s*=/) {
                push @newcode, "$1TV$param = 1";
                push @newcode, $line;
                push @newcode, "$1$param = $param * TV$param";
                $found = 1;
                last;
            }
        } 
        if (not $found) {
            push @newcode, $line;
        }
    }

    $model->set_code(record => $code_record, code => \@newcode);
}

sub full_omega_block
{
    # Replace all omegas into one big full block
    # FIXed and SAME omegas are assumed to be at the end and will be kept
    # Return 1 if model is already full block else 0
	my %parm = validated_hash(\@_,
        model => { isa => 'model' },
    );
    my $model = $parm{'model'};

    my $omegas = $model->problems->[0]->omegas;

    my $numetas = 0;
    my $keep_rest = 0;
    my @keep;
    for (my $i = 0; $i < scalar(@$omegas); $i++) {
        my $last = 0;
        if ($i == scalar(@$omegas) - 1) {
            $last = 1;
        }
        if (not $last and $omegas->[$i + 1]->same) {    # The next omega record is SAME
            $keep_rest = 1;
        }
        my $anyfix = 0;
        for my $option (@{$omegas->[$i]->options}) {
            if ($option->fix) {
                $anyfix = 1;
                last;
            }
        }
        if ($anyfix or $omegas->[$i]->fix) {        # Is record FIX or any option FIX
            $keep_rest = 1;
        }

        if ($keep_rest) {
            push @keep, $omegas->[$i];
        } else {
            if ($omegas->[$i]->is_block()) {
                $numetas += $omegas->[$i]->size;
            } else {
                $numetas += scalar(@{$omegas->[$i]->options});
            }
        }
    }

    if ($numetas == 0 or ($omegas->[0]->is_block() and $omegas->[0]->size == $numetas)) {  # No ETAS left or only one BLOCK
        return 1;
    }

    my $new_omega_block = omega_block(model => $model, start_eta => 1, end_eta => $numetas);

    $model->problems->[0]->omegas([ $new_omega_block, @keep ]);

    return 0;
}

sub omega_block
{
    # Transform a number of omegas into block
    # Return the new block without side effects
	my %parm = validated_hash(\@_,
        model => { isa => 'model' },
        start_eta => { isa => 'Int' },
        end_eta => { isa => 'Int' },
    );
    my $model = $parm{'model'};
    my $start_eta = $parm{'start_eta'};
    my $end_eta = $parm{'end_eta'};

    my $omega_matrix = $model->problems->[0]->get_filled_omega_matrix(start_eta => $start_eta, end_eta => $end_eta);
    my $size = @{$omega_matrix};
    my @record_arr = ( "\$OMEGA BLOCK($size)" );
    for (my $i = 0; $i < $size; $i++) {
        my $row = "";
        for (my $j = 0; $j <= $i; $j++) {
            $row .= $omega_matrix->[$i]->[$j] . ' ';
        }
        push @record_arr, "$row\n";
    }

    my $new_omega_block = model::problem::omega->new(record_arr => \@record_arr);

    return $new_omega_block;
}

sub boxcox_etas
{
    # Boxcox transform all or some ETAs of model
    # Assume only one $PROBLEM
	my %parm = validated_hash(\@_,
        model => { isa => 'model' },
        etas => { isa => 'ArrayRef', optional => 1 },       # An array of the etas to transform or unspecified for all etas
    );
    my $model = $parm{'model'};
	my $etas = $parm{'etas'};

    my $netas = $model->nomegas->[0];
    if (not defined $etas) {
        $etas = [1 .. $netas];
    }
    my $nthetas = $model->nthetas;

    # Transform ETAs
    for my $eta (@$etas) {
        for my $record (('pk', 'pred', 'error', 'des', 'aes', 'aesinitial', 'mix', 'infn')) {
		    if ($model->has_code(record => $record)) {  
			    my $code = $model->get_code(record => $record);
                for (my $i = 0; $i < scalar(@$code); $i++) {
                    $code->[$i] =~ s/(?<!\w)ETA\($eta\)/ETAT$eta/g;
                }
                $model->set_code(record => $record, code => $code);
            }
        }
	}

    # Prepend transformation code and add thetas
	my @code;
	my $code_record;
	if ($model->has_code(record => 'pk')) {
		@code = @{$model->get_code(record => 'pk')};
		$code_record = 'pk';
	} elsif ($model->has_code(record => 'pred')) {
		@code = @{$model->get_code(record => 'pred')};
		$code_record = 'pred';
	} else {
		croak("Neither PK nor PRED defined in " . $model->filename . "\n");
	}

    my $next_theta = $nthetas + 1;
    for my $i (@$etas) {
        my $line = "ETAT$i = (EXP(ETA($i))**THETA($next_theta) - 1) / (THETA($next_theta))";
        $next_theta++;
        unshift @code, $line;
        $model->add_records(type => 'theta', record_strings => [ '$THETA (-3, 0.01, 3)']); 
    }

    $model->set_code(record => $code_record, code => \@code);
}

sub remove_iiv
{
	my %parm = validated_hash(\@_,
        model => { isa => 'model' },
        fix => { isa => 'Bool', default => 0 },     # Set to fix removed iiv $OMEGAs else remove them
    );
    my $model = $parm{'model'};
    my $fix = $parm{'fix'};

    my $omegas = $model->problems->[0]->omegas;

    my $remove = find_omega_records(model => $model, type => 'iiv');

    if ($fix) {
        _fix_omegas(model => $model, omegas => $remove);
    } else {
        _remove_omegas(model => $model, omegas => $remove);
    }
}

sub remove_iov
{
	my %parm = validated_hash(\@_,
        model => { isa => 'model' },
        fix => { isa => 'Bool', default => 0 },     # Set to fix removed iiv $OMEGAs else remove them
    );
    my $model = $parm{'model'};
    my $fix = $parm{'fix'};

    my $omegas = $model->problems->[0]->omegas;

    my $remove = find_omega_records(model => $model, type => 'iov');

    if ($fix) {
        _fix_omegas(model => $model, omegas => $remove);
    } else {
        _remove_omegas(model => $model, omegas => $remove);
    }
}

sub find_omega_records
{
	my %parm = validated_hash(\@_,
        model => { isa => 'model' },
        type => { isa => 'Str' },     # Set to either 'iov' or 'iiv'
    );
    my $model = $parm{'model'};
    my $type = $parm{'type'};

    my $omegas = $model->problems->[0]->omegas;

    my @found;
    my $last = 0;
    for (my $i = 0; $i < scalar(@$omegas); $i++) {
        if ($i == scalar(@$omegas) - 1) {
            $last = 1;
        }
        unless ($omegas->[$i]->same or (not $last and $omegas->[$i + 1]->same) or $omegas->[$i]->fix) {    # Keep if IOV or block FIX
            if ($type eq 'iiv') {
                push @found, $omegas->[$i];
            }
        } else {
            if ($type eq 'iov') {
                push @found, $omegas->[$i];
            }
        }
    }

    return \@found;
}

sub _fix_omegas
{
	my %parm = validated_hash(\@_,
        model => { isa => 'model' },
        omegas => { isa => 'ArrayRef[model::problem::omega]' },
    );
    my $model = $parm{'model'};
    my $omegas = $parm{'omegas'};

    for my $omega (@$omegas) {
        if (defined $omega->type and $omega->type eq 'BLOCK' and not $omega->same) {
            $omega->fix(1);
        }
        for my $option (@{$omega->options}) {
            $option->init(0);
            if (not defined $omega->type or $omega->type ne 'BLOCK') {
                $option->fix(1);
            }
        }
    }
}

sub _remove_omegas
{
    # Remove omegas from model by removing both the
    # omega records, renumbering etas and setting
    # removed etas to constant zero.
	my %parm = validated_hash(\@_,
        model => { isa => 'model' },
        omegas => { isa => 'ArrayRef[model::problem::omega]' },
    );
    my $model = $parm{'model'};
    my $omegas = $parm{'omegas'};

    my $etas = _etas_from_omega_records(model => $model, omegas => $omegas);
    _remove_etas(model => $model, etas => $etas);
    _remove_omega_records(model => $model, omegas => $omegas);
}

sub _remove_omega_records
{
    # Remove specific omega records from model
	my %parm = validated_hash(\@_,
        model => { isa => 'model' },
        omegas => { isa => 'ArrayRef[model::problem::omega]' },
    );
    my $model = $parm{'model'};
    my $omegas = $parm{'omegas'};

    my @all_omegas = @{$model->problems->[0]->omegas};
    my @keep;
    for my $omega (@all_omegas) {
        if (not grep { $_ == $omega } @$omegas) {
            push @keep, $omega;
        } 
    }

    $model->problems->[0]->omegas(\@keep);
}

sub _remove_etas
{
    # Remove etas by changing the numbering and setting removed etas to constant 0.
	my %parm = validated_hash(\@_,
        model => { isa => 'model' },
        etas => { isa => 'ArrayRef[Int]' },
    );
    my $model = $parm{'model'};
    my $etas = $parm{'etas'};

    my $num_etas = _number_of_etas(model => $model);
    my %replace_hash; 
    my $current = 1;
    for (my $i = 1; $i <= $num_etas; $i++) {
        if (grep { $_ == $i } @$etas) {
            $replace_hash{$i} = 0;
        } else {
            $replace_hash{$i} = "ETA($current)";
            $current++;
        }
    }

    for my $record (('pk', 'pred', 'error', 'des', 'aes', 'aesinitial', 'mix', 'infn')) {
        if ($model->has_code(record => $record)) {  
            my $code = $model->get_code(record => $record);
            for (my $i = 0; $i < scalar(@$code); $i++) {
                $code->[$i] =~ s/(?<!\w)ETA\((\d+)\)/$replace_hash{$1}/g;
            }
            $model->set_code(record => $record, code => $code);
        }
    }
}

sub _number_of_etas
{
    # Return the number of etas in the model
	my %parm = validated_hash(\@_,
        model => { isa => 'model' },
    );
    my $model = $parm{'model'};
 
    my @all_omegas = @{$model->problems->[0]->omegas};

    my $num_etas = 0;
    for my $omega (@all_omegas) {
        my $record_size;
        if (defined $omega->size) {
            $record_size = $omega->size;
        } else {
            $record_size = scalar(@{$omega->options});
        }
        $num_etas += $record_size;
    }
    return $num_etas;
}

sub _etas_from_omega_records
{
    # Return a list of eta numbers from a list of omega records
	my %parm = validated_hash(\@_,
        model => { isa => 'model' },
        omegas => { isa => 'ArrayRef[model::problem::omega]' },
    );
    my $model = $parm{'model'};
    my $omegas = $parm{'omegas'};

    my @all_omegas = @{$model->problems->[0]->omegas};
    my @etas;

    my $current_eta = 1;
    my $remove_index = 0;
    for my $record (@all_omegas) {
        my $record_size;
        if (defined $record->size) {
            $record_size = $record->size;
        } else {
            $record_size = scalar(@{$record->options});
        }
        for my $remove_record (@$omegas) {
            if ($remove_record == $record) {
                push @etas, $current_eta .. $current_eta + $record_size - 1;
            }
        }
        $current_eta += $record_size;
    }

    return \@etas;
}


1;