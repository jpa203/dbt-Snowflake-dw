select dvdquantityonhand, dvdquantityonrent, dvdquantitylost
from {{ref('stg_dvd')}}
where dvdquantityonhand < 0
or dvdquantityonrent < 0
or dvdquantitylost < 0