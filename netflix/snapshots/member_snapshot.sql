{% snapshot members_snapshot %}

{{

    config (
        target_database = 'netflix',
        target_schema = 'snapshots',
        unique_key = 'memberid',
        strategy = 'check',
        check_cols = ['memberlastname', 'memberinitial', 'memberaddres', 'memberphone', 'memberemail']


    )
}}

select * from {{source ('netflix', 'member')}}

{% endsnapshot %}