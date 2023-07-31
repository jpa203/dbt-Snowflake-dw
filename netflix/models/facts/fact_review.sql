{{ config(materialized='table')}}

with transformation as (
    select 
    surrogate_id,
    r.memberid,
    g.genreid,
    r.starvalue
    from {{ref('stg_dvdreview')}} r
    join {{ref('stg_dvd')}} d on r.dvdid = d.dvdid
    join {{ref('stg_genre')}} g on g.genreid = d.genreid
),
month as (
SELECT surrogate_id, reviewdate, DATE_PART('YEAR', reviewdate) AS extracted_year, 
  DATE_PART('MONTH', reviewdate) AS extracted_month,
  CASE 
    WHEN DATE_PART('MONTH', reviewdate) = 1 THEN 'Jan'
    WHEN DATE_PART('MONTH', reviewdate) = 2 THEN 'Feb'
    WHEN DATE_PART('MONTH', reviewdate) = 3 THEN 'Mar'
    WHEN DATE_PART('MONTH', reviewdate) = 4 THEN 'Apr'
    WHEN DATE_PART('MONTH', reviewdate) = 5 THEN 'May'
    WHEN DATE_PART('MONTH', reviewdate) = 6 THEN 'June'
    WHEN DATE_PART('MONTH', reviewdate) = 7 THEN 'Jul'
    WHEN DATE_PART('MONTH', reviewdate) = 8 THEN 'Aug'
    WHEN DATE_PART('MONTH', reviewdate) = 9 THEN 'Sep'
    WHEN DATE_PART('MONTH', reviewdate) = 10 THEN 'Oct'
    WHEN DATE_PART('MONTH', reviewdate) = 11 THEN 'Nov'
    WHEN DATE_PART('MONTH', reviewdate) = 12 THEN 'Dec'
  END AS month_name
FROM {{ref('stg_dvdreview')}} 
),
month_transform as (
select * from transformation
left join month using(surrogate_id)
)
select 
memberid, 
genreid, 
monthid,
round(avg(starvalue),2) as avg_rating
from month_transform t
join {{ref('stg_month')}} m on m.month = t.month_name and m.year = t.extracted_year
group by (memberid, genreid, monthid)
