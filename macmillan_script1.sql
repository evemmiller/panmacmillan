select version();

SELECT *
FROM pg_catalog.pg_tables

drop table publicactionsraw;

/*
 CREATE TABLE FOR data
*/

CREATE TABLE publicationsraw (
WorkRef VARCHAR(255), 
VISTAPublisher VARCHAR(255) ,
PublicationDate VARCHAR(255),
WorkAlert VARCHAR(255) ,
ExcludedFromConfirmation VARCHAR(255) ,
ConfirmationRestrictionAdded VARCHAR(255) ,
ConfirmationNotes VARCHAR(255) ,
WorkStatus VARCHAR(255) ,
Imprint VARCHAR(255) ,
CommissioningEditor VARCHAR(255) ,
ISBN VARCHAR(255),
ProductType VARCHAR(255) ,
EditionTarget VARCHAR(255),
Binding VARCHAR(255) ,
Format VARCHAR(255) ,
EditionVISTAProdType VARCHAR(255),
EditionPriceSynchronisationTemplate VARCHAR(255),
EditionExtent VARCHAR(255),
EditionEmbargoedUntil VARCHAR(255)
);

drop table VISTAPublisher;
drop table WorkAlert ;
drop table WorkStatus;
drop table Imprint;
drop table CommissioningEditor;
drop table ProductType;
drop table EditionTarget;
drop table Binding;
drop table Format;

/*
 create tables of each column
 */

create table VISTAPublisher as select distinct VISTAPublisher from publicationsraw;
create table WorkAlert as select distinct WorkAlert from publicationsraw;
create table WorkStatus as select distinct WorkStatus from publicationsraw;
create table Imprint as select distinct Imprint from publicationsraw;
create table CommissioningEditor as select distinct CommissioningEditor from publicationsraw;
create table ProductType as select distinct ProductType from publicationsraw;
create table EditionTarget as select distinct EditionTarget from publicationsraw;
create table Binding as select distinct Binding, 'first' as bindingtype from publicationsraw;
create table Format as select distinct Format from publicationsraw;
create table EditionVISTAProdType as select distinct EditionVISTAProdType from publicationsraw;
create table EditionPriceSynchronisationTemplate as select distinct EditionPriceSynchronisationTemplate from publicationsraw;

select * from  VISTAPublisher;
select * from  WorkAlert ;
select * from  WorkStatus;
select * from  Imprint;
select * from  CommissioningEditor;
select * from  ProductType;
select * from  EditionTarget;
select * from  Binding;
select * from  Format;

update Binding set bindingtype = 'second' where binding = 'Paperback'

select * from  EditionVISTAProdType;
select * from  EditionPriceSynchronisationTemplate;

/*
 create working table 
 
 *including additional columns to determine exclusion from confirmation */

drop table publicactionswork;


CREATE TABLE publicationswork (
WorkRef VARCHAR (255), 
VISTAPublisher VARCHAR (255) ,
PublicationDate date,
WorkAlert VARCHAR (255) ,
ExcludedFromConfirmation VARCHAR (255) ,
ConfirmationRestrictionAdded VARCHAR (255) ,
ConfirmationNotes VARCHAR (255) ,
WorkStatus VARCHAR (255) ,
Imprint VARCHAR (255) ,
CommissioningEditor VARCHAR (255) ,
ISBN VARCHAR (13) primary key,
ProductType VARCHAR(255) ,
EditionTarget VARCHAR(255),
Binding VARCHAR(255) ,
Format VARCHAR(255) ,
EditionVISTAProdType VARCHAR(255),
EditionPriceSynchronisationTemplate VARCHAR(255),
EditionExtent VARCHAR(255),
EditionEmbargoedUntil date,
IsExcluded BOOLEAN,
ExcludedReason VARCHAR(255),
MetadataIssue VARCHAR(255),
IsSecondFormat VARCHAR(10),
EarliestConfirmationDate date
);

/* insert data into work table */
insert into publicationswork 
select p.WorkRef, 
p.VISTAPublisher,
to_date(p.PublicationDate, 'dd/MM/yyyy') as PublicationDate,
p.WorkAlert,
p.ExcludedFromConfirmation,
p.ConfirmationRestrictionAdded,
p.ConfirmationNotes,
p.WorkStatus,
p.Imprint,
p.CommissioningEditor,
p.ISBN,
p.ProductType,
p.EditionTarget,
p.Binding,
p.Format,
p.EditionVISTAProdType,
p.EditionPriceSynchronisationTemplate,
p.EditionExtent,
to_date(p.EditionEmbargoedUntil, 'dd/MM/yyyy') as EditionEmbargoedUntil
from publicationsraw p
; 


/* fix issue where exclusion date included in confirmation notes*/
update publicationswork set EditionEmbargoedUntil = to_date(RIGHT(ConfirmationNotes, 10),'dd/MM/yyyy')
where ConfirmationNotes like '%Embargo%' 
and (editionembargoeduntil isnull
		or EditionEmbargoedUntil < to_date(RIGHT(ConfirmationNotes, 10),'dd/MM/yyyy') 
	)
;

/* exclude editions that have been excluded from confirmation */
update publicationswork set isexcluded = true , ExcludedReason = 'excluded from confirmation'
where excludedfromconfirmation = 'Yes';

/*exclude editions that have been marked confidential*/
update publicationswork
set ExcludedReason = case 
						when ExcludedReason isnull then 'confidential' 
						else concat(ExcludedReason, ', confidential') 
					 end,
	isexcluded = true
where ConfirmationNotes like '%Confidential%';
 
/*exclude editions that are embargoed*/
update publicationswork
set ExcludedReason = case 
						when ExcludedReason isnull then concat('embargoed until ', CAST(editionembargoeduntil as VARCHAR))
						else concat(ExcludedReason,', embargoed until ', CAST(editionembargoeduntil as VARCHAR))
						end,
	isexcluded = true
where editionembargoeduntil notnull and editionembargoeduntil > CAST(CURRENT_TIMESTAMP AS DATE);

/*exclude editions that are pre-acquisation*/
update publicationswork
set ExcludedReason = case 
						when ExcludedReason isnull then 'Pre-Acquisition' 
						else concat(ExcludedReason, ', Pre-Acquisition') 
					 end,
	isexcluded = true
where workstatus like 'Pre-Acquisition';

update publicationswork set isexcluded = False
where isexcluded is null
;

/* Flagging Metadata issues*/
update publicationswork
set metadataissue = true
where editionextent isnull
or "format" isnull 
or (editionpricesynchronisationtemplate isnull and producttype = 'EBook');

/*identifying second formats and setting confirmation date
 * excluding any non-paperbacks 
 * - format excludes trade paperbacks
 * - editionvistaprodtype excludes other paperbacks*/
create table works(
workref VARCHAR(25),
minsecondconfirmation date);

insert into works(workref,minsecondconfirmation, actualsecondconfirmation)
select workref,
min(publicationdate + interval '6 weeks'),
where isexcluded is null and w.binding = b.binding and b.bindingtype = 'first'
group by workref 

/* set confirmation date for first editions*/
update publicationswork
set issecondformat = false,
EarliestConfirmationDate = publicationdate - interval '1 year'
from binding b
where b.bindingtype != 'second' and publicationswork.binding = b.binding 
;

/* set confirmation date for editions without a binding type*/
update publicationswork
set issecondformat = false,
EarliestConfirmationDate = publicationdate - interval '1 year'
where binding is null
;

/* set confirmation date for paperbacks that are not second editions*/
update publicationswork
set issecondformat = false,
EarliestConfirmationDate = publicationdate - interval '1 year'
from binding b, works w
where b.bindingtype = 'second' 
	and publicationswork.binding = b.binding  
	and publicationswork.isbn not in (select workref from works)
;

/* set confirmation date for paperbacks that are second editions*/

update publicationswork
set issecondformat = true,
earliestconfirmationdate =
	case when w.minsecondconfirmation > publicationdate - interval '1 year' then w.minsecondconfirmation
		 else publicationdate - interval '1 year'
	end
from works w, binding b
where b.bindingtype = 'second' and publicationswork.workref = w.workref and publicationswork.binding = b.binding 

