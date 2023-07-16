-- removing punctuation

{{ config(materialized='incremental')}}
with source as (
    
    select 
    ratingid,
    ratingname, 
    REGEXP_REPLACE(ratingdescription, '"', '') as ratingdescription
    from {{source('netflix', 'rating')}}
) 

select * from source