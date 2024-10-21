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

/* Flagging Metadata issues*/
update publicationswork
set metadataissue = true
where editionextent isnull
or "format" isnull 
or (editionpricesynchronisationtemplate isnull and producttype = 'EBook');

/*identifying second formats
 * excluding any non-paperbacks 
 * - format excludes trade paperbacks
 * - editionvistaprodtype excludes other paperbacks*/

update publicationswork
set issecondformat = false,
EarliestConfirmationDate = publicationdate - interval '1 year'
where binding not in ('Paperback','Hardback','Trade Paperback') 
;

update publicationswork
set issecondformat = False,
EarliestConfirmationDate = publicationdate - interval '1 year'
where binding  in ('Hardback','Trade Paperback');



/*Idenitfying earliest confirmation date of second editions*/

select * from publicationswork where binding = 'Paperback'

/*Identifying paperbacks that are published without a hardback or paperback*/

with seconds as (select a.isbn as paperback, b.isbn
from publicationswork a, publicationswork b
where a.workref = b.workref
and a.binding = 'Paperback' and b.binding in ('Hardback','Trade Paperback'))
update publicationswork
set issecondformat = false,
EarliestConfirmationDate = publicationdate - interval '1 year'
where isbn not in (select paperback from seconds) and binding = 'Paperback'
;

/*Identifying correct confirmation date of paperbacks published as second editions */

with seconds as (
select a.workref, a.isbn as paperbackIsbn, b.isbn as firstFormatIsbn, a.publicationdate as secondFormatDate, b.publicationdate as firstFormatDate
from publicationswork a, publicationswork b
where a.workref = b.workref
and a.binding = 'Paperback' and b.binding in ('Hardback','Trade Paperback'))
update publicationswork p
set issecondformat = true,
EarliestConfirmationDate = (select firstformatdate 
			from seconds s
			where s.paperbackisbn = p.isbn LIMIT 1) + interval '6 weeks' 
where isbn in (select paperbackisbn from seconds)
;



select * from works

create table works(
workref VARCHAR(25),
minsecondconfirmation date);

insert into works(workref,minsecondconfirmation, actualsecondconfirmation)
select workref,
min(publicationdate + interval '6 weeks'),
where isexcluded is null and w.binding = b.binding and b.bindingtype = 'first'
group by workref 


update publicationswork
set issecondformat = true,
earliestconfirmationdate =
	case when w.minsecondconfirmation > publicationdate - interval '1 year' then w.minsecondconfirmation
		 else publicationdate - interval '1 year'
	end
from works w, binding b
where b.bindingtype = 'second' and publicationswork.workref = w.workref and publicationswork.binding = b.binding 

select publicationdate, earliestconfirmationdate from publicationswork where issecondformat = 'true'
select editionvistaprodtype , count(*) from publicationswork group by editionvistaprodtype
select editionvistaprodtype , count(*) from publicationswork where binding is null group by editionvistaprodtype

select * from binding
update works 
set actualsecondconfirmation = (select min(publicationdate - interval '1 year')
from publicationswork p
where works.workref = p.workref and p.binding = 'Paperback')
where works.workref = p.workref

select * from works where minsecondconfirmation is null






with formats as(
select a.workref, a.isbn as paperbackIsbn, b.isbn as firstFormatIsbn, a.publicationdate as secondFormatDate, b.publicationdate as firstFormatDate
from publicationswork a, publicationswork b
where a.workref = b.workref
and a.binding = 'Paperback' and b.binding in ('Hardback','Trade Paperback')
and a.publicationdate > b.publicationdate)
update publicationswork p
set issecondformat = true,
EarliestConfirmationDate = case when (select firstformatdate 
			from formats f 
			where f.paperbackisbn = p.isbn LIMIT 1) + interval '6 weeks' > publicationdate - interval '1 year'
		then (select firstformatdate 
			from formats f 
			where f.paperbackisbn = p.isbn LIMIT 1) + interval '6 weeks'
	when (select firstformatdate 
			from formats f 
			where f.paperbackisbn = p.isbn LIMIT 1) + interval '6 weeks' <= publicationdate - interval '1 year'
		then publicationdate - interval '1 year'
		end
where isbn in (select paperbackisbn from formats)

;

select * from publicationswork where earliestconfirmationdate isnull

