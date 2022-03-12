*********************************************************************
*  Assignment:    PROJECT                                         
*                                                                    
*  Description:   Project of BIOS 669 - analyzing relationship of 
*					crime rate and income and substance treatment 
*                   program in NY State
*
*  Name:          Hantong Hu
*
*  Date:          4/10/2019                                        
*------------------------------------------------------------------- 
*  Job name:      Project_hantongh.sas   
*
*  Purpose:       Analyzing relationship of crime rate and income 
*				  and substance treatment program in NY State
*                                         
*  Language:      SAS, VERSION 9.4  
*
*  Input:         All data sets in Data folder 
*
*  Output:        PDF file
*                                                                    
********************************************************************;

%LET job=Project;
%LET onyen=hantongh;
%LET outdir=/folders/myfolders/BIOS-669/Project/Output;

OPTIONS NODATE MERGENOBY=WARN VARINITCHK=WARN ;
FOOTNOTE "Job &job._&onyen run on &sysdate at &systime";
LIBNAME data "/folders/myfolders/BIOS-669/Project/Data";


ODS pdf FILE="&outdir/&job._&onyen..pdf" STYLE=JOURNAL;

/* Import data: crime rate and treatment program */

* Keep only index_related (total) variables for crime data set (1990-2017);
proc import datafile="/folders/myfolders/BIOS-669/Project/Data/Index__Violent__Property__and_Firearm_Rates_By_County__Beginning_1990.csv"
			out=county_crime(keep=county year population index_count index_rate)
			dbms=csv
			replace;
	guessingrows=2000;
run;

* Program Treatment Data set (2007-2017);
proc import datafile="/folders/myfolders/BIOS-669/Project/Data/Chemical_Dependence_Treatment_Program_Admissions__Beginning_2007.csv"
			out=county_treatment
			dbms=csv
			replace;
	guessingrows=3000;
run;

* NY State Median Income (1990-2017);
proc import datafile="/folders/myfolders/BIOS-669/Project/Data/statistic_id205974_new-york---median-household-income-from-1990-to-2017.xlsx"
			out=ny_income(rename=(b=yearchar c=income) keep=b c)
			dbms=xlsx
			replace;
	getnames=no;
	datarow=6;
	sheet='Data';
run;

/* Basic data checking */

title 'Basic data checking for county_crime and county_treatment';
proc contents data=county_crime; run;
ods startpage=off;
proc means data=county_crime missing;
	var population index_count index_rate;
run;
proc freq data=county_crime;
	tables year/missing;
run;

proc contents data=county_treatment; run;
proc means data=county_treatment missing;
	var admissions;
run;
proc freq data=county_treatment;
	tables year*County_of_Program_Location age_group Primary_Substance_Group
			Program_Category Service_Type /missing nocol nocum norow;
run;

proc contents data=ny_income; run;
proc freq data=ny_income; tables yearchar/missing; run;
proc means data=ny_income missing; var income; run;
ods startpage=on;

/* Derive new variables/data sets from existing data sets */

* Calculate overall New York State crime rate for each year;
proc sql;
	create table ny_crime as
		select year,100000*sum(index_count)/sum(population) as overall_rate label='NYS crime rate (*10,000)'
		/* Rate is inflated	by 100,000 to be consistent with original data set */
			from county_crime
			group by year
			order by year;
quit;

data ny_income;
	set ny_income;
	year=input(yearchar,best12.);
	
	label year='Year' income='Household Income (N.Y. State)';
	drop yearchar;
run;

* Merge income and crime rate;
proc sql;
	create table ny_crime_income as
		select c.year, i.income, c.overall_rate
			from ny_crime as c, ny_income as i
			where c.year=i.year;
quit;

/* Data Checking for ny_crime_income */

title 'Data Checking for ny_crime_income';
proc contents data=ny_crime_income; run;
ods startpage=off;
proc means data=ny_crime_income missing;
	var income overall_rate;
run;
ods startpage=on;

/*** Overall Analysis - State level ***/

/* Scatter plot for crime rate, income per year, and relation between
	crime rate and income */
title 'Trend of Crime Rate and Median Income by Year';
proc sgplot data=ny_crime_income;
	series x=year y=overall_rate;
run;
proc sgplot data=ny_crime_income;
	series x=year y=income;
run;

* These two graphs indicate crime rate decreases and income increases 
	as years pass;
* Thus do a scatter plot for crime*income with reversed income;

title 'Scatter Plot for Crime Rate and Income';
proc sgplot data=ny_crime_income;
	scatter x=income y=overall_rate/ 
			datalabel=year;
run;

data ny_incomeinv;
	set ny_crime_income;
	incomeinv=1/income;
	label income='Inverse Income';
run;

* Approximately linear relation between crime rate and 1/income;
title 'Linear relation between income and 1/crime rate';
proc sgplot data=ny_incomeinv;
	scatter x=incomeinv y=overall_rate/
			datalabel=year markerattrs=(symbol=plus) legendlabel='Year';
	reg x=incomeinv y=overall_rate/ markerattrs=(symbol=plus);
	xaxis label='Inverse Income';
run;
* Observe Unusual patterns starting from 2007;
* Start county-level analysis;


/*** County-level Analysis ***/
 
/* Import data sets: Write a macro to import median 
	household income from all data sets */
data _null_;
	filename income "/folders/myfolders/BIOS-669/Project/Data/IncomeByCounty";
	did=dopen("income");
	numfiles=dnum(did);
	
	do i=1 to numfiles;
		physname=dread(did,i);
		if scan(physname,2,'.')='csv' then do;
			name=catx('_',scan(physname,1,'_'),scan(physname,2,'_'));
			call symputx(name,physname);
		end;
	end;
	rc=dclose(did);
run;	

options nomlogic nomprint nosymbolgen;
%macro importcounty(start=,end=);

%do i=&start. %to &end.;
%let yoi=%sysfunc(substr(&i,3,2));

/* Let row 2 of data set be label of var obtained from row 1 */
proc import datafile="/folders/myfolders/BIOS-669/Project/Data/IncomeByCounty/&&&ACS_&yoi." out=x dbms=csv replace;
	getnames=yes;
run;


proc import datafile="/folders/myfolders/BIOS-669/Project/Data/IncomeByCounty/&&&ACS_&yoi." out=data dbms=csv replace;
	getnames=yes;
	datarow=3;
run;

data x ;
	set x(obs=1);
run;
proc transpose data=x out=temp;
	var _all_;
run;

proc sql;
	create table varlist as
	select c.name,t.col1 as label
		from dictionary.columns as c,
				temp as t
		where libname="WORK" and memname="DATA" and c.name=t._name_;
quit;

/* REGX - find var name that expresses median household 
	income (specified in label, provided by dictionary) */

data _null_;
	set varlist;
	retain testRegEx;
	
	if _N_=1 then do;
		testRegEx=prxparse("/^[Hh]ouseholds.*[Ee]st.*Median/");
		
		if missing(testRegEx) then do;
			putlog 'ERROR regex is malformed';
			stop;
		end;
	end;
	
	if prxmatch(testRegEx, strip(label)) then do;
		call symputx('medianvar',name);
	end;
	
	if prxmatch(testRegEx, strip(label));
run;

/* Create data set for each year */
data county_&yoi.;
	set data;
	
	length county $20 year 4;
	label county='County' year='Year';
	
	year=&i.;
	county=scan(geo_display_label,1);
	
	rename &medianvar.=Median_income;
	keep year county &medianvar.;
run;

%end;

%mend;

%importcounty(start=2007,end=2017);

/* Merge with county crime rate data set */
data county_income;
	set county_07 county_08 county_09 county_10
		county_11 county_12 county_13 county_14
		county_15 county_16 county_17;
run;

proc sql;
	create table county_crime_income as
	select cr.county, cr.year, cr.index_rate,
			c.median_income, 1/c.median_income as incomeinv
		from county_crime as cr
			left join
				county_income as c
			on cr.county=c.county and cr.year=c.year
		where cr.year>=2007;
quit;

/* Sort and check data */

proc sort data=county_crime_income;
	by year county;
run;

title 'Check data for county_crime_income';
proc means data=county_crime_income missing;
	by year;
	var median_income index_rate;
run;
ods startpage=off;
proc univariate data=county_crime_income noprint;
	histogram index_rate;
run;
proc univariate data=county_crime_income noprint;
	histogram median_income;
run;

* Boxplot for each year to check outliers;
proc sgplot data=county_crime_income;
	vbox median_income/ group=year;
run;
proc sgplot data=county_crime_income;
	vbox index_rate/ group=year datalabel=county;
run;
ods startpage=on;
title;

/* Create a macro to plot income*1/crime rate for all counties with 
   at least one non-missing value */ 

%macro plotcounty;

* Proc SQL to check if any county has no observation, if has no
observation, delete county;
proc sql noprint;
	select distinct county into :validcounty separated by ' '
		from county_crime_income
		group by county
		having max(median_income)<>.;
quit;

%let i=1;
%do %until (%scan(&validcounty,&i)= );
	%let cname = %scan(&validcounty,&i);
	
	title "&cname.";
	proc sgplot data=county_crime_income;
		series x=incomeinv y=index_rate/datalabel=year;
		xaxis label="1/Income";
		yaxis label="Crime Rate*100000";
		where county="&cname.";
	run;

	%let i = %eval(&i+1);
%end;

%mend;

%plotcounty;

* Ratio of income and 1/crime rate is no longer linear, thus 
introducing treatment data;

* Make a new data set with total # of admissions per category per
county per year, and one observation for each year & each county;

proc sql;
	create table treatment as
	select year, county_of_program_location, program_category,
			sum(ct.admissions) as total
		from county_treatment as ct
		group by program_category,county_of_program_location,year;
quit;

proc sort data=treatment;
	by year county_of_program_location;
run;
proc transpose data=treatment out=trans_treatment(drop=_name_);
	by year county_of_program_location;
	id program_category;
	var total;
run;

proc sql;		
	create table county as
	select cci.*,t.crisis,t.inpatient,t.opioid_treatment_program,
			t.outpatient,t.residential
		from county_crime_income as cci, trans_treatment as t
		where cci.year=t.year and cci.county=t.county_of_program_location;
quit;

title 'Scatter plot of crime rate and treatment category';
proc sgplot data=county;
	scatter x=crisis y=index_rate;
run;
ods startpage=off;
proc sgplot data=county;
	scatter x=inpatient y=index_rate;
run;
proc sgplot data=county;
	scatter x=opioid_treatment_program y=index_rate;
run;
proc sgplot data=county;
	scatter x=outpatient y=index_rate;
run;
proc sgplot data=county;
	scatter x=residential y=index_rate;
run;
ods startpage=on;

* Since the scatter plot didn't indicate too much linear relationship
between total admission per category and crime rate, and also there
 are too many missing values if analyzing each program category as 
 a predictor, so will use only total admissions per county per year;

proc sql;
	create table treatment as
	select year, county_of_program_location, sum(ct.admissions) as total
		from county_treatment as ct
		group by county_of_program_location,year;
quit;

proc sql;		
	create table county as
	select cci.*,t.total
		from county_crime_income as cci, treatment as t
		where cci.year=t.year and cci.county=t.county_of_program_location;
quit;

title 'Histogram of total treatment admission in counties';
proc sgplot data=county;
	histogram total;
run;

/* Perform linear regression */
proc standard DATA=county MEAN=0 STD=1 OUT=stan_county;
	var incomeinv total;
run;

proc sql noprint; select int(count(*)/2) into :num from stan_county; quit; 
proc surveyselect data=stan_county n=&num. method=srs out=train seed=669; run;
proc sql;
	create table test as
	select * from stan_county except
	select * from train;
quit;

title 'Linear regression model';
proc glm data=train;
	model index_rate=incomeinv total;
run;

data testing;
	set test;
	y=1994.515203+220.157122*incomeinv+250.727529*total;
	diff=y-index_rate;
	diffsq=diff*diff;
run;

title 'Fit model to test set';
proc means data=testing sum noprint;
var diffsq;
output out=testresult sum=/autoname;
run;

data testresult;
	set testresult;
	mse=diffsq_sum/&num.;
run;

title 'MSE for test set';
proc print data=testresult;
	var mse;
run;

ods pdf close;