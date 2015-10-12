#!/etc/bin/perl


use strict;
use warnings;
use Test::More;
use Test::Exception;
use File::Path 'rmtree';
use FindBin qw($Bin);
use lib "$Bin/../.."; #location of includes.pm
use includes; #file with paths to PsN packages
use data;
use file;
use tool::lasso;
use common_options;

our $modeldir = $includes::testfiledir;

#use File::Spec;
#open STDERR, '>', File::Spec->devnull();		# Silence STDERR

dies_ok { tool::lasso::check_name(parameter => 'CL',covariate=>'APGR',factor => '2',version => 5) } "check name too long v 5";
dies_ok { tool::lasso::check_name(parameter => 'V',covariate=>'HEJSAN',H => 'H',version => 6) } "check name too long v 6";
lives_ok { tool::lasso::check_name(parameter => 'KA',covariate=>'OTHER',version => 7) } "check name long v 7";


my $model = model->new(filename => "$modeldir/pheno.mod", ignore_missing_data => 1);

my $relations = 'CL:WGT-2,SEX-1,RACE-1,,V:WGT-3-45.2,,KA:WGT-3,APGR-2';

my ($ref1,$breakpoints) = tool::lasso::parse_relations(relations => $relations);
is($breakpoints->{'V:WGT'},45.2,"lasso parse_relations breakpoint");
is($ref1->{'CL'}{'WGT'}{'form'},2,"lasso parse_relations 1");
is($ref1->{'CL'}{'SEX'}{'form'},1,"lasso parse_relations 2");
is($ref1->{'CL'}{'RACE'}{'form'},1,"lasso parse_relations 3");
is($ref1->{'V'}{'WGT'}{'form'},3,"lasso parse_relations 4");
is($ref1->{'KA'}{'WGT'}{'form'},3,"lasso parse_relations 5");
is($ref1->{'KA'}{'APGR'}{'form'},2,"lasso parse_relations 6");
is((scalar(keys %{$ref1})),3,'lasso parse relations count parameters');

is(tool::lasso::factor_string(parameter => 'CL',covariate => 'WT',thetanumber=>5, mean => 3, sd => 2),
   'CLWT = THETA(5)*(WT-3.00000)/2.00000*FACTOR', "factor string 1");

is(tool::lasso::final_theta_string(parameter => 'V',covariate => 'HAPGR',thetanumber=>3, mean => 2),
   'VHAPGR = THETA(3)*(HAPGR-2.00000)', "final_theta_string 1");

#WGT
my $mean2=1.52542372881356;
my $sd2=0.704564727537013;

#SEX
my $mean1=0.202702702702702;
my $sd1=0.404756978659315; 

#APGR hstick
my $mean=6.42373;
my $sd=2.23764;
my $hmean=1.49153;
my $hsd=1.33420;
my $break = 5.5;
my $nthetas = $model->nthetas;

$nthetas++;
tool::lasso::add_lasso_theta(model => $model,
							 parameter => 'CL',
							 covariate => 'SEX0',
							 thetanumber => $nthetas,
							 mean => $mean1,
							 sd => $sd1,
							 max => 1,
							 min => 0);
is($model->problems->[0]->thetas->[-1]->options->[0]->label,'TH'.$nthetas.' CLSEX0','add_lasso_theta label');
is($model->problems->[0]->thetas->[-1]->options->[0]->init,0.0001,'add_lasso_theta init');
cmp_float($model->problems->[0]->thetas->[-1]->options->[0]->lobnd,-0.50766,'add_lasso_theta lowbnd cat');
cmp_float($model->problems->[0]->thetas->[-1]->options->[0]->upbnd,1.99680,'add_lasso_theta upbnd cat');

$nthetas++;
tool::lasso::add_lasso_theta(model => $model,
							 parameter => 'CL',
							 covariate => 'WGT',
							 thetanumber => $nthetas,
							 mean => $mean2,
							 sd => $sd2,
							 max => 3.6,
							 min => 0.6);
is($model->problems->[0]->thetas->[-1]->options->[0]->label,'TH'.$nthetas.' CLWGT','add_lasso_theta label');
is($model->problems->[0]->thetas->[-1]->options->[0]->init,0.0001,'add_lasso_theta init');
cmp_float($model->problems->[0]->thetas->[-1]->options->[0]->lobnd,-0.33962,'add_lasso_theta lowbnd cont');
cmp_float($model->problems->[0]->thetas->[-1]->options->[0]->upbnd,0.76134,'add_lasso_theta upbnd cont');

$nthetas++;
tool::lasso::add_lasso_theta(model => $model,
							 parameter => 'CL',
							 covariate => 'APGR',
							 thetanumber => $nthetas,
							 mean => $mean,
							 sd => $sd,
							 max => 10,
							 min => 1);
is($model->problems->[0]->thetas->[-1]->options->[0]->label,'TH'.$nthetas.' CLAPGR','add_lasso_theta label');
is($model->problems->[0]->thetas->[-1]->options->[0]->init,0.0001,'add_lasso_theta init');
cmp_float($model->problems->[0]->thetas->[-1]->options->[0]->lobnd,-0.62569,'add_lasso_theta lowbnd hstick lo');
cmp_float($model->problems->[0]->thetas->[-1]->options->[0]->upbnd,0.41256,'add_lasso_theta upbnd hstick lo');

$nthetas++;
tool::lasso::add_lasso_theta(model => $model,
							 parameter => 'CL',
							 covariate => 'HAPGR',
							 thetanumber => $nthetas,
							 mean => $hmean,
							 sd => $hsd,
							 max => (10-$break),
							 min => 0);
is($model->problems->[0]->thetas->[-1]->options->[0]->label,'TH'.$nthetas.' CLHAPGR','add_lasso_theta label');
is($model->problems->[0]->thetas->[-1]->options->[0]->init,0.0001,'add_lasso_theta init');
cmp_float($model->problems->[0]->thetas->[-1]->options->[0]->lobnd,-0.44348,'add_lasso_theta lowbnd hstick hi');
cmp_float($model->problems->[0]->thetas->[-1]->options->[0]->upbnd,0.89452,'add_lasso_theta upbnd hstick hi');


is(tool::lasso::get_abssum(old_thetas => 2,nthetas => 6,adaptive => 0),
   'ABSSUM = ABS(THETA(3))+ABS(THETA(4))+ABS(THETA(5))+ABS(THETA(6))','get_abssum no adaptive');


my $dataobj = data->new(filename => $modeldir.'/pheno.dta',
						idcolumn => 1,
						missing_data_token => '-99',
						ignoresign => '@');

my $lassomodel = model->new(filename => "$modeldir/pheno.mod", ignore_missing_data => 1);

my ($parameter_covariate_form,$statistics) = tool::lasso::setup_covariates(relations => 'CL:WGT-2,APGR-1,,V:APGR-3',
																		   data => $dataobj,
																		   model => $model);
my ($usepred,$cutoffref,$t_theta,$weightref,$lambda_theta) = 
	tool::lasso::setup_lasso_model(lasso_model => $lassomodel,
								   parameter_covariate_form => $parameter_covariate_form,
								   t_value => 0.1,
								   statistics => $statistics,
								   missing_data_token => '-99');

is($usepred,0,'usepred setup_lasso_model');
is_deeply($cutoffref,[3,4,5,6,7,8,9,10,11,12,13,14],'cutoff thetas setup_lasso_model');
is($t_theta,15,'t theta setup_lasso_model');
is_deeply($weightref,[],'weight thetas setup_lasso_model');
is($lambda_theta,undef,'lambda theta setup_lasso_model');
is($parameter_covariate_form->{'CL'}{'APGR'}{'form'},1,'parcovform pheno 3');
is($parameter_covariate_form->{'CL'}{'APGR'}{'thetas'}{1},3,'parcovform pheno 4');
is($parameter_covariate_form->{'CL'}{'APGR'}{'thetas'}{2},4,'parcovform pheno 5');
is($parameter_covariate_form->{'CL'}{'APGR'}{'thetas'}{3},5,'parcovform pheno 6');
is($parameter_covariate_form->{'CL'}{'APGR'}{'thetas'}{4},6,'parcovform pheno 7');
is($parameter_covariate_form->{'CL'}{'APGR'}{'thetas'}{5},7,'parcovform pheno 8');
is($parameter_covariate_form->{'CL'}{'APGR'}{'thetas'}{6},8,'parcovform pheno 9');
is($parameter_covariate_form->{'CL'}{'APGR'}{'thetas'}{7},9,'parcovform pheno 10');
is($parameter_covariate_form->{'CL'}{'APGR'}{'thetas'}{9},10,'parcovform pheno 11');
is($parameter_covariate_form->{'CL'}{'APGR'}{'thetas'}{10},11,'parcovform pheno 12');
is($parameter_covariate_form->{'CL'}{'WGT'}{'form'},2,'parcovform pheno 1');
is($parameter_covariate_form->{'CL'}{'WGT'}{'theta'},12,'parcovform pheno 2');
is($parameter_covariate_form->{'V'}{'APGR'}{'form'},3,'parcovform pheno 13');
is($parameter_covariate_form->{'V'}{'APGR'}{'theta'},13,'parcovform pheno 14');
is($parameter_covariate_form->{'V'}{'APGR'}{'Htheta'},14,'parcovform pheno 15');

$model = model->new(filename => "$modeldir/mox1.mod", ignore_missing_data => 1);
my $dataobj = data->new(filename => "$modeldir/mox_simulated.csv",
						idcolumn => 1,
						missing_data_token => '-99',
						ignoresign => '@');

my ($parameter_covariate_form,$statistics) = 
	tool::lasso::setup_covariates(relations => 'CL:AGE-3,SEX-1,,V:AGE-2,ACE-1,DIG-1,WT-2',
								  data => $dataobj,
								  model => $model);

$lassomodel = model->new(filename => "$modeldir/mox1.mod", ignore_missing_data => 1);

($usepred,$cutoffref,$t_theta,$weightref,$lambda_theta) = 
	tool::lasso::setup_lasso_model(lasso_model => $lassomodel,
								   parameter_covariate_form => $parameter_covariate_form,
								   t_value => 0.1,
								   statistics => $statistics,
								   missing_data_token => '-99');
my %finalhash;
$finalhash{'theta'}={
'TVCL' => 3.29E+01,
'TVV' =>1.16E+02,
'TVKA' =>1.46E+00,
'LAG' => 8.28E-02,
'TH5 CLAGE' => 0.01,
'TH6 CLHAGE' => 0.01,
'TH7 CLSEX2' => 1.44E-02,
'TH8 VACE0' => -6.31E-02,
'TH9 VAGE' => -2.25E-02,
'TH10 VDIG0' => 1.02E-04,
'TH11 VWT' => 1.09E-04,
'TH12 T-VALUE' => 1.00E-01};
$finalhash{'omega'}={
'OMEGA(1,1)' => 6.43E-01,
'OMEGA(2,1)' => 8.01E-01  ,
'IIV (CL-V)' => 7.53E-01,
'IIV KA' => 5.14E-01,
'IOV CL' => 1.21E-03,
'IOV KA' =>  7.00E-03};
$finalhash{'sigma'}={'SIGMA(1,1)'=> 3.35E-01};
$lassomodel->update_inits(update_fix => 1,
						  from_hash => \%finalhash);


my ($refm,$factor)=tool::lasso::setup_optimal_model(lasso_optimal => $lassomodel,
													base_model => $model,
													parameter_covariate_form => $parameter_covariate_form,
													t_optimal => 0.1,
													cutoff => 0.005,
													statistics => $statistics,
													use_pred => $usepred,
													NOABORT_added => 0,
													directory => 'dirname',
													cutoff_thetas => $cutoffref );
my $abssum = abs($finalhash{'theta'}->{'TH5 CLAGE'})+abs($finalhash{'theta'}->{'TH6 CLHAGE'})+
	abs($finalhash{'theta'}->{'TH7 CLSEX2'})+abs($finalhash{'theta'}->{'TH8 VACE0'})+
	abs($finalhash{'theta'}->{'TH9 VAGE'})+abs($finalhash{'theta'}->{'TH10 VDIG0'})+
	abs($finalhash{'theta'}->{'TH11 VWT'});
cmp_float($factor,exp(1-($abssum/0.1)),'setup_optimal_model factor');

is($refm->problems->[0]->thetas->[0]->options->[0]->init,$finalhash{'theta'}->{'TVCL'},'setup_optimal_model init 1');
is($refm->problems->[0]->thetas->[1]->options->[0]->init,$finalhash{'theta'}->{'TVV'},'setup_optimal_model init 2');
is($refm->problems->[0]->thetas->[2]->options->[0]->init,$finalhash{'theta'}->{'TVKA'},'setup_optimal_model init 3');
is($refm->problems->[0]->thetas->[3]->options->[0]->init,$finalhash{'theta'}->{'LAG'},'setup_optimal_model init 4');

my $sd =sprintf("%.5f",$statistics->{'AGE'}{3}{'sd'});
my $init = exp(1-($abssum/0.1))*$finalhash{'theta'}->{'TH5 CLAGE'}/($sd);
cmp_float($refm->problems->[0]->thetas->[4]->options->[0]->init,$init,'setup_optimal_model init 5'); #CLSEX2

$sd =sprintf("%.5f",$statistics->{'AGE'}{3}{'H-sd'});
$init = exp(1-($abssum/0.1))*$finalhash{'theta'}->{'TH6 CLHAGE'}/($sd);
cmp_float($refm->problems->[0]->thetas->[5]->options->[0]->init,$init,'setup_optimal_model init 6'); #CLSEX2


$sd =sprintf("%.5f",$statistics->{'SEX'}{1}{'sd'}{2});
$init = exp(1-($abssum/0.1))*$finalhash{'theta'}->{'TH7 CLSEX2'}/($sd);
cmp_float($refm->problems->[0]->thetas->[6]->options->[0]->init,$init,'setup_optimal_model init 7'); #CLSEX2

$sd =sprintf("%.5f",$statistics->{'ACE'}{1}{'sd'}{0});
$init = exp(1-($abssum/0.1))*$finalhash{'theta'}->{'TH8 VACE0'}/($sd);
is($refm->problems->[0]->thetas->[7]->options->[0]->init,$init,'setup_optimal_model init 8'); #VACE0

$sd =sprintf("%.5f",$statistics->{'AGE'}{2}{'sd'});
$init = exp(1-($abssum/0.1))*$finalhash{'theta'}->{'TH9 VAGE'}/($sd);
is($refm->problems->[0]->thetas->[8]->options->[0]->init,$init,'setup_optimal_model init 9'); #VAGE

$model = model->new(filename => "$modeldir/pheno.mod", ignore_missing_data => 1);

$nthetas = $model->nthetas()+1;
tool::lasso::add_optimal_theta(model => $model,
							 parameter => 'CL',
							 covariate => 'WGT',
							 thetanumber => $nthetas,
							 factor => 3,
							 sd => 2,
							 estimate => 4);

is($model->problems->[0]->thetas->[-1]->options->[0]->label,'TH'.$nthetas.' CLWGT','add_optimal_theta label');
cmp_float($model->problems->[0]->thetas->[-1]->options->[0]->init,6,'add_optimal_theta init');
is($model->problems->[0]->thetas->[-1]->options->[0]->lobnd,undef,'add_optimal_theta lowbnd cont');
is($model->problems->[0]->thetas->[-1]->options->[0]->upbnd,undef,'add_optimal_theta upbnd cont');
is($model->problems->[0]->thetas->[-1]->options->[0]->fix,1,'add_optimal_theta fix');


done_testing();