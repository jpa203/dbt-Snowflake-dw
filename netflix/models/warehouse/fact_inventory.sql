{{ config(materialized='table')}}

with source as (
    select 
    d.dvdid,
    g.genreid,
    r.ratingid,
    sum(dvdquantityonhand + dvdquantityonrent) as dvdtotalquantity, 
    sum(dvdquantitylost) as dvdtotallost,
    sum(dvdquantityonrent) as dvdtotalrent, 
    ((1 - (sum(dvdquantityonrent) / sum(dvdquantityonhand))) * 100) as dvdstock
    from {{ref('stg_dvd')}} d
    left join {{ref('stg_genre')}} g on d.genreid = g.genreid
    left join {{ref('stg_rating')}} r on r.ratingid = d.ratingid
    group by (d.dvdid, g.genreid, r.ratingid)
),
month as (
SELECT dvdid, DATE_PART('YEAR', ingestion_timestamp) AS extracted_year, 
  DATE_PART('MONTH', ingestion_timestamp) AS extracted_month, DATE_PART('DAY', ingestion_timestamp) as extracted_day,
  CASE 
    WHEN DATE_PART('MONTH', ingestion_timestamp) = 1 THEN 'Jan'
    WHEN DATE_PART('MONTH', ingestion_timestamp) = 2 THEN 'Feb'
    WHEN DATE_PART('MONTH', ingestion_timestamp) = 3 THEN 'Mar'
    WHEN DATE_PART('MONTH', ingestion_timestamp) = 4 THEN 'Apr'
    WHEN DATE_PART('MONTH', ingestion_timestamp) = 5 THEN 'May'
    WHEN DATE_PART('MONTH', ingestion_timestamp) = 6 THEN 'June'
    WHEN DATE_PART('MONTH', ingestion_timestamp) = 7 THEN 'Jul'
    WHEN DATE_PART('MONTH', ingestion_timestamp) = 8 THEN 'Aug'
    WHEN DATE_PART('MONTH', ingestion_timestamp) = 9 THEN 'Sep'
    WHEN DATE_PART('MONTH', ingestion_timestamp) = 10 THEN 'Oct'
    WHEN DATE_PART('MONTH', ingestion_timestamp) = 11 THEN 'Nov'
    WHEN DATE_PART('MONTH', ingestion_timestamp) = 12 THEN 'Dec'
  END AS month_name
FROM {{ref('stg_dvd')}} 
), 
final as (
select * from source
left join month using (dvdid)
)
select dvdid, genreid, ratingid, monthid, dvdtotalquantity, dvdtotallost, dvdtotalrent,  dvdpercentagestock
from (
    select dvdid, genreid, ratingid, monthid, dvdtotalquantity, dvdtotallost, dvdtotalrent, round(dvdstock) as dvdpercentagestock,
           MAX(extracted_day) as max_extracted_day
    from final f
    join {{ref('stg_month')}} m on m.month = f.month_name
    where year = YEAR(CURRENT_DATE())
    group by dvdid, genreid, ratingid, monthid, dvdtotalquantity, dvdtotallost, dvdtotalrent, dvdpercentagestock
) maxdate
group by dvdid, genreid, ratingid, monthid, dvdtotalquantity, dvdtotallost, dvdtotalrent, dvdpercentagestock, max_extracted_day




