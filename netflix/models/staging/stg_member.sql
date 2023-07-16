{{ config(materialized='incremental')}}

with source as (

select * from {{source('netflix', 'member')}}

)

select *, current_timestamp() as ingestion_timestamp, 'Y' as current_flag from source

{% if is_incremental() %}

 where ingestion_timestamp > (select max(ingestion_timestamp) from {{ this }})

{% endif %}
