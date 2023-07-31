{{ config(materialized='incremental')}}

with source as (

    select * from {{source('netflix','dvdreview')}}
)

select {{dbt_utils.generate_surrogate_key(['memberid', 'dvdid'])}} as surrogate_id, * from source 

{% if is_incremental() %}


  where reviewdate >= (select max(reviewdate) from {{source('netflix','dvdreview')}})

{% endif %}