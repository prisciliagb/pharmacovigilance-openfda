-- 1 ligne par mois : volume, gravité, croissance mois sur mois.
with monthly as (
    select
        date_trunc(receive_date, month) as receive_month,
        count(*) as report_count,
        countif(is_serious) as serious_count,
        countif(is_death) as death_count,
        countif(is_hospitalization) as hospitalization_count,
        countif(is_life_threatening) as life_threatening_count,
        countif(is_disabling) as disabling_count,
        countif(is_health_professional) as health_professional_count
    from {{ ref('fct_reports') }}
    group by receive_month
)

select
    receive_month,
    report_count,
    serious_count,
    report_count - serious_count as non_serious_count,
    death_count,
    hospitalization_count,
    life_threatening_count,
    disabling_count,
    round(safe_divide(serious_count, report_count), 4) as serious_rate,
    round(safe_divide(death_count, report_count), 4) as death_rate,
    round(safe_divide(hospitalization_count, report_count), 4) as hospitalization_rate,
    round(safe_divide(life_threatening_count, report_count), 4) as life_threatening_rate,
    round(safe_divide(health_professional_count, report_count), 4) as health_professional_rate,
    lag(report_count) over (order by receive_month) as previous_month_count,
    round(safe_divide(
        report_count - lag(report_count) over (order by receive_month),
        lag(report_count) over (order by receive_month)
    ), 4) as mom_growth,
    round(avg(report_count) over (order by receive_month rows between 2 preceding and current row), 1)
        as moving_avg_3m
from monthly
