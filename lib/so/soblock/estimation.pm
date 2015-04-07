package so::soblock::estimation;

use strict;
use warnings;
use Moose;
use MooseX::Params::Validate;
use include_modules;
use XML::LibXML;

use so::table;
use so::soblock::estimation::populationestimates;
use so::soblock::estimation::precisionpopulationestimates;
use so::soblock::estimation::individualestimates;
use so::soblock::estimation::residual;
use so::soblock::estimation::likelihood;


has 'PopulationEstimates' => ( is => 'rw', isa => 'so::soblock::estimation::populationestimates' );
has 'PrecisionPopulationEstimates' => ( is => 'rw', isa => 'so::soblock::estimation::precisionpopulationestimates' );
has 'IndividualEstimates' => ( is => 'rw', isa => 'so::soblock::estimation::individualestimates' );
has 'Residual' => ( is => 'rw', isa => 'so::soblock::estimation::residual' );
has 'Predictions' => ( is => 'rw', isa => 'so::table' );
has 'Likelihood' => ( is => 'rw', isa => 'so::soblock::estimation::likelihood' );


sub BUILD
{
    my $self = shift;

    my $pe = so::soblock::estimation::populationestimates->new();
    $self->PopulationEstimates($pe);
    my $ppe = so::soblock::estimation::precisionpopulationestimates->new();
    $self->PrecisionPopulationEstimates($ppe);
    my $ie = so::soblock::estimation::individualestimates->new();
    $self->IndividualEstimates($ie);
    my $res = so::soblock::estimation::residual->new();
    $self->Residual($res);
    my $l = so::soblock::estimation::likelihood->new();
    $self->Likelihood($l);
}

sub xml
{
    my $self = shift;

    my $est;

    my $pe = $self->PopulationEstimates->xml();
    my $ppe = $self->PrecisionPopulationEstimates->xml();
    my $ie = $self->IndividualEstimates->xml();
    my $res = $self->Residual->xml();
    my $pred;
    if (defined $self->Predictions) {
        $pred = $self->Predictions->xml();
    }
    my $l = $self->Likelihood->xml();

    if (defined $pe or defined $ppe or defined $ie or defined $res or defined $pred or defined $l) {
        $est = XML::LibXML::Element->new("Estimation");

        if (defined $pe) {
            $est->appendChild($pe);
        }

        if (defined $ppe) {
            $est->appendChild($ppe);
        }

        if (defined $ie) {
            $est->appendChild($ie);
        }

        if (defined $res) {
            $est->appendChild($res);
        }

        if (defined $pred) {
            $est->appendChild($pred);
        }

        if (defined $l) {
            $est->appendChild($l);
        }
    }

    return $est;
}


no Moose;
__PACKAGE__->meta->make_immutable;
1;
