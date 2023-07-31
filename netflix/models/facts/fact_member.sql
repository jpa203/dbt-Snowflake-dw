{{ config(materialized='table')}}


with transformation as (

    select 
    m.memberid,
    d.dvdid,
    s.stateid,
    p.paymentid,
    ms.membershipid,
    membershipmonthlyprice,
    (membershipmonthlyprice/30) as membershipdailycost, 
    (membershipdailycost * (DATEDIFF(day, membershipsincedate::TIMESTAMP, current_date())))
               AS membertotalvalue,
    CASE
        WHEN membertotalvalue >= 300 then membershipmonthlyprice *0.25
        WHEN membertotalvalue between 200 and 299 then membershipmonthlyprice * 0.10
        WHEN membertotalvalue < 100 then 0
    end as discountoffer,
    date(m.ingestion_timestamp) as date
    from {{ref('stg_member')}} m
    join {{source('netflix', 'rental')}} r on m.memberid = r.memberid
    join {{ref('stg_dvd')}} d on d.dvdid = r.dvdid
    join {{ref('stg_payment')}} p on p.memberid = m.memberid
    join {{ref('stg_membership')}} ms on m.membershipid = ms.membershipid
    join {{source('netflix', 'zipcode')}} z on z.zipcodeid = m.memberaddressid
    join {{ref('stg_state')}} s on s.stateid = z.stateid
    where m.current_flag = 'Y'
),
fact_member as (
    SELECT 
    * 
    from transformation
    join {{ref('dim_date')}} dt on dt.fulldate = date
)
select memberid, dvdid, stateid, paymentid, membershipid, round(membershipmonthlyprice) as membershipcost, round(membertotalvalue) as membervalue, 
round(discountoffer,2) as discount from fact_member 


