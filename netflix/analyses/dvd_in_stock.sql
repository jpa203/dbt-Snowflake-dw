select * from {{ref('stg_dvd')}}
order by dvdquantityonhand 
order by desc 
limit 1 
