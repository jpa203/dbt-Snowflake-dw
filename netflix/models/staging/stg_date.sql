{{ config(materialized='table')}}


with source as (

    select * from {{source('netflix','date')}}
)
select 
date as fulldate,
day_name_abv as day,
month_name_abv as month,
quarter_num as quarter, 
REGEXP_REPLACE(year, ',', '') as year
from source
where fulldate > '2015-01-01'