{% test test_membership_cost(model, column_name) %}

with validation as (

    select
        {{ column_name }} as amount_paid

    from {{ model }}

),

validation_errors as (

    select
        amount_paid

    from validation
        -- if the membership cost is not equal to 20 or 25, test fails
    where amount_paid not in (20,25)

)

select *
from validation_errors

{% endtest %}