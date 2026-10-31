-- 1 ligne par signalement. Incrémental : seuls les 30 derniers jours sont recalculés,
-- comme la fenêtre de rattrapage de l'ingestion.
{{
    config(
        materialized='incremental',
        incremental_strategy='merge',
        unique_key='safety_report_id',
        partition_by={'field': 'receive_date', 'data_type': 'date', 'granularity': 'month'},
        on_schema_change='append_new_columns'
    )
}}

select *
from {{ ref('int_reports_enriched') }}
{% if is_incremental() %}
where receive_date >= (select date_sub(max(receive_date), interval 30 day) from {{ this }})
{% endif %}
