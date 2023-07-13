create or replace database netflix

create or replace schema netflix_schema

create or replace table netflix.public.dvd(
    dvdid int not null,
    dvdtitle varchar(256),
    genreid int references netflix.public.genre (genreid),
    ratingid int references netflix.public.rating (ratingid),
    dvdreleasedate timestamp,
    theaterreleasedate timestamp,
    dvdquantityonhand int,
    dvdquantityonrent int, 
    dvdquantitylost int,
    constraint primary_key primary key (dvdid)
)

create or replace table netflix.public.dvdreview(
    memberid int not null references netflix.public.member(memberid),
    dvdid int not null references netflix.public.dvd (dvdid),
    starvalue int,
    reviewdate timestamp,
    comment varchar(256)
)

create or replace table netflix.public.genre(
    genreid int not null,
    genrename varchar(256),
    constraint primary_key primary key (genreid)
)

create or replace table netflix.public.member(
    memberid int not null,
    memberfirstname varchar(256),
    memberlastname varchar(256),
    memberinitial varchar(20),
    memberaddres varchar(256),
    memberaddressid int references netflix.public.zipcode (zipcodeid), 
    memberphone int, 
    memberemail varchar(256),
    memberpassword varchar(256),
    membershipid int references netflix.public.membership (membershipid),
    membershipsincedate timestamp,
    constraint primary_key primary key (memberid)
)

create or replace table netflix.public.membership(
    membershipid int not null,
    memmbershiptype varchar(256),
    membershiplimitpermonth int,
    membershipmonthlyprice decimal,
    membershipmonthlytax decimal,
    membershipdvdlostprice decimal,
    dvdattime int,
    constraint primary_key primary key (membershipid)
)

create or replace table netflix.public.movieperson (
    personid int not null,
    personfirstname varchar(256),
    personlastname varchar (256),
    personinitial varchar (256),
    persondateofbirth timestamp,
    constraint primary_key primary key (personid)
)

create or replace table netflix.public.moviepersonrole(
    personid int not null references netflix.public.movieperson (personid),
    roleid int not null references netflix.public.role (roleid),
    dvdid int not null references netflix.public.dvd (dvdid)
)

create or replace table netflix.public.role(
    roleid int not null,
    rolename varchar(256),
    constraint primary_key primary key (roleid)
)

create or replace table netflix.public.payment (
    paymentid int not null, 
    memberid int not null references netflix.public.member (memberid),
    amountpaid decimal,
    amountpaiddate timestamp,
    amountpaiduntildate timestamp,
    constraint primary_key primary key (paymentid)
)

create or replace table netflix.public.payment_history(
    paymenthistoryid int not null, 
    memberid int references netflix.public.member (memberid),
    paymentid int references netflix.public.payment (paymentid),
    amountpaid decimal,
    amountpaid_new decimal,
    amountpaiddate timestamp,
    amountpaiddate_new timestamp,
    amountpaiduntildate timestamp,
    amountpaiduntildate_new timestamp,
    changetype int,
    time_stamp timestamp,
    constraint primary_key primary key (paymenthistoryid)

)

create or replace table netflix.public.rating (
    ratingid int not null,
    ratingname varchar(256),
    ratingdescription varchar (256),
    constraint primary_key primary key (ratingid)
)

create or replace table netflix.public.rental(
    rentalid int not null,
    memberid int not null references netflix.public.member (memberid),
    dvdid int not null references netflix.public.dvd (dvdid),
    rentalrequestdate timestamp,
    rentalshippeddate timestamp,
    rentalreturneddate timestamp,
    constraint primary_key primary key (rentalid)
)

create or replace table netflix.public.rentalqueue(
    memberid int not null references netflix.public.member (memberid),
    dvdid int not null references netflix.public.dvd (dvdid),
    dateaddedinqueue timestamp,
    dvdqueueposition int
)

create or replace table netflix.public.state(
    stateid int not null,
    statename varchar(256),
    constraint primary_key primary key (stateid)
)

create or replace table netflix.public.zipcode(
    zipcodeid int not null,
    zipcode int,
    stateid int references netflix.public.state(stateid),
    cityid int references netflix.public.city (cityid),
    constraint primary_key primary key (zipcodeid)
    
)

create or replace table netflix.public.city(
    cityid int not null,
    cityname varchar(100),
    constraint primary_key primary key (cityid)
)

// COPY

create or replace stage city_stage
url = 's3://netflix-data-lake/public/city/'
credentials = (aws_key_id ='AKIASPKJ6RJCR3VKE2AT', aws_secret_key = 'qOPPDwcwExNZ1NZ2cDGWokU0OJTyX4ShZpQUkZsR')

list @city_stage;

copy into netflix.public.city
    from @city_stage
    file_format = (type = csv field_delimiter = ',' skip_header = 1)

select * from netflix.public.city;


create or replace stage dvd_stage
url = 's3://netflix-data-lake/public/dvd/'
credentials = (aws_key_id ='AKIASPKJ6RJCR3VKE2AT', aws_secret_key = 'qOPPDwcwExNZ1NZ2cDGWokU0OJTyX4ShZpQUkZsR')

list @dvd_stage;

copy into netflix.public.dvd
    from @dvd_stage
    file_format = (type = csv field_delimiter = ',' FIELD_OPTIONALLY_ENCLOSED_BY = '0x22'
 skip_header = 1)

create or replace stage dvd_review
url = 's3://netflix-data-lake/public/dvdreview/'
credentials = (aws_key_id ='AKIASPKJ6RJCR3VKE2AT', aws_secret_key = 'qOPPDwcwExNZ1NZ2cDGWokU0OJTyX4ShZpQUkZsR');

list @dvd_review;

copy into netflix.public.dvdreview
    from @dvd_review
    file_format = (type = csv field_delimiter = ',' skip_header = 1);

select * from netflix.public.dvdreview;

create or replace stage genre
url = 's3://netflix-data-lake/public/genre/'
credentials = (aws_key_id ='AKIASPKJ6RJCR3VKE2AT', aws_secret_key = 'qOPPDwcwExNZ1NZ2cDGWokU0OJTyX4ShZpQUkZsR');

list @genre;

copy into netflix.public.genre
    from @genre
    file_format = (type = csv field_delimiter = ',' skip_header = 1);

select * from netflix.public.genre;

create or replace stage member
url = 's3://netflix-data-lake/public/member/'
credentials = (aws_key_id ='AKIASPKJ6RJCR3VKE2AT', aws_secret_key = 'qOPPDwcwExNZ1NZ2cDGWokU0OJTyX4ShZpQUkZsR');

list @member;

copy into netflix.public.member
    from @member
    file_format = (type = csv field_delimiter = ',' skip_header = 1);

select * from netflix.public.member;

create or replace stage membership
url = 's3://netflix-data-lake/public/membership/'
credentials = (aws_key_id ='AKIASPKJ6RJCR3VKE2AT', aws_secret_key = 'qOPPDwcwExNZ1NZ2cDGWokU0OJTyX4ShZpQUkZsR');

list @membership;

copy into netflix.public.membership
    from @membership
    file_format = (type = csv field_delimiter = ',' skip_header = 1);

select * from netflix.public.membership;

create or replace stage movieperson
url = 's3://netflix-data-lake/public/movieperson/'
credentials = (aws_key_id ='AKIASPKJ6RJCR3VKE2AT', aws_secret_key = 'qOPPDwcwExNZ1NZ2cDGWokU0OJTyX4ShZpQUkZsR');

list @movieperson;

copy into netflix.public.movieperson
    from @movieperson
    file_format = (type = csv field_delimiter = ',' skip_header = 1);

select * from netflix.public.movieperson;

create or replace stage moviepersonrole
url = 's3://netflix-data-lake/public/moviepersonrole/'
credentials = (aws_key_id ='AKIASPKJ6RJCR3VKE2AT', aws_secret_key = 'qOPPDwcwExNZ1NZ2cDGWokU0OJTyX4ShZpQUkZsR');

list @moviepersonrole;

copy into netflix.public.moviepersonrole
    from @moviepersonrole
    file_format = (type = csv field_delimiter = ',' skip_header = 1);

select * from netflix.public.moviepersonrole;

create or replace stage payment
url = 's3://netflix-data-lake/public/payment/'
credentials = (aws_key_id ='AKIASPKJ6RJCR3VKE2AT', aws_secret_key = 'qOPPDwcwExNZ1NZ2cDGWokU0OJTyX4ShZpQUkZsR');

list @payment;

copy into netflix.public.payment
    from @payment
    file_format = (type = csv field_delimiter = ',' skip_header = 1);

select * from netflix.public.payment;

create or replace stage rating
url = 's3://netflix-data-lake/public/rating/'
credentials = (aws_key_id ='AKIASPKJ6RJCR3VKE2AT', aws_secret_key = 'qOPPDwcwExNZ1NZ2cDGWokU0OJTyX4ShZpQUkZsR');

list @rating;

copy into netflix.public.rating
    from @rating
    file_format = (type = csv field_delimiter = ',')
    on_error = continue;

select * from netflix.public.rating;


create or replace stage rental
url = 's3://netflix-data-lake/public/rental/'
credentials = (aws_key_id ='AKIASPKJ6RJCR3VKE2AT', aws_secret_key = 'qOPPDwcwExNZ1NZ2cDGWokU0OJTyX4ShZpQUkZsR');

list @rental;

copy into netflix.public.rental
    from @rental
    file_format = (type = csv field_delimiter = ',')
    on_error = continue;

select * from netflix.public.rental;

create or replace stage rentalqueue
url = 's3://netflix-data-lake/public/rentalqueue/'
credentials = (aws_key_id ='AKIASPKJ6RJCR3VKE2AT', aws_secret_key = 'qOPPDwcwExNZ1NZ2cDGWokU0OJTyX4ShZpQUkZsR');

list @rentalqueue;

copy into netflix.public.rentalqueue
    from @rentalqueue
    file_format = (type = csv field_delimiter = ',')
    on_error = continue;

select * from netflix.public.rentalqueue;

create or replace stage role
url = 's3://netflix-data-lake/public/role/'
credentials = (aws_key_id ='AKIASPKJ6RJCR3VKE2AT', aws_secret_key = 'qOPPDwcwExNZ1NZ2cDGWokU0OJTyX4ShZpQUkZsR');

list @role;

copy into netflix.public.role
    from @role
    file_format = (type = csv field_delimiter = ',')
    on_error = continue;

select * from netflix.public.role;

create or replace stage state
url = 's3://netflix-data-lake/public/state/'
credentials = (aws_key_id ='AKIASPKJ6RJCR3VKE2AT', aws_secret_key = 'qOPPDwcwExNZ1NZ2cDGWokU0OJTyX4ShZpQUkZsR');

list @state;

copy into netflix.public.state
    from @state
    file_format = (type = csv field_delimiter = ',')
    on_error = continue;

select * from netflix.public.state;

create or replace stage zipcode
url = 's3://netflix-data-lake/public/zipcode/'
credentials = (aws_key_id ='AKIASPKJ6RJCR3VKE2AT', aws_secret_key = 'qOPPDwcwExNZ1NZ2cDGWokU0OJTyX4ShZpQUkZsR');

list @zipcode;

copy into netflix.public.zipcode
    from @zipcode
    file_format = (type = csv field_delimiter = ',')
    on_error = continue;

select * from netflix.public.zipcode;


