-- Module 6 — Axes d'analyse et KPI de pharmacovigilance, calculés sur les marts dbt.
-- Rappel : on parle de signalements, jamais de risque (pas de dénominateur de patients exposés).


-- =========================================================================
-- Axe 1 — Volume et tendance : les signalements augmentent-ils ? Y a-t-il des pics ?
-- =========================================================================
select receive_month, report_count, previous_month_count, mom_growth, moving_avg_3m
from `pharmaco-openfda-pg.dbt_dev_marts.mart_monthly_kpis`
order by receive_month;

-- Pics journaliers : jours au-dessus de 1,5 × la moyenne mobile sur 7 jours
with daily as (
    select receive_date, count(*) as report_count
    from `pharmaco-openfda-pg.dbt_dev_marts.fct_reports`
    group by receive_date
)
select
    receive_date,
    format_date('%A', receive_date) as weekday,
    report_count,
    round(avg(report_count) over (order by receive_date rows between 6 preceding and current row), 0) as moving_avg_7d
from daily
qualify report_count > 1.5 * avg(report_count) over (order by receive_date rows between 6 preceding and current row)
order by report_count desc;

-- Volume moyen par jour de la semaine (effet des jours ouvrés)
select
    format_date('%u-%A', receive_date) as weekday,
    round(count(*) / count(distinct receive_date), 0) as avg_reports_per_day
from `pharmaco-openfda-pg.dbt_dev_marts.fct_reports`
group by weekday
order by weekday;


-- =========================================================================
-- Axe 2 — Gravité : quelle part des cas est grave, et de quelle façon ?
-- =========================================================================
select
    count(*) as report_count,
    round(100 * countif(is_serious) / count(*), 1) as serious_pct,
    round(100 * countif(is_death) / count(*), 1) as death_pct,
    round(100 * countif(is_hospitalization) / count(*), 1) as hospitalization_pct,
    round(100 * countif(is_life_threatening) / count(*), 1) as life_threatening_pct,
    round(100 * countif(is_disabling) / count(*), 1) as disabling_pct
from `pharmaco-openfda-pg.dbt_dev_marts.fct_reports`;

select receive_month, serious_rate, death_rate, hospitalization_rate, life_threatening_rate
from `pharmaco-openfda-pg.dbt_dev_marts.mart_monthly_kpis`
order by receive_month;


-- =========================================================================
-- Axe 3 — Médicaments et réactions : lesquels dominent ?
-- =========================================================================
-- Top 10 médicaments suspects, avec taux de gravité et écart au taux global
select drug_name, pharm_class, report_count, serious_rate, death_rate, serious_rate_gap
from `pharmaco-openfda-pg.dbt_dev_marts.mart_drug_safety`
order by report_count desc
limit 10;

-- Top 10 réactions (signalements distincts avec au moins un médicament suspect)
select reaction, count(distinct safety_report_id) as report_count
from `pharmaco-openfda-pg.dbt_dev_marts.fct_drug_reactions`
group by reaction
order by report_count desc
limit 10;

-- Top 10 couples médicament suspect × réaction
select drug_name, reaction, count(*) as report_count
from `pharmaco-openfda-pg.dbt_dev_marts.fct_drug_reactions`
group by drug_name, reaction
order by report_count desc
limit 10;

-- Médicaments à fort volume (≥ 1 000 signalements) les plus éloignés du taux de gravité global
select drug_name, report_count, serious_rate, global_serious_rate, serious_rate_gap
from `pharmaco-openfda-pg.dbt_dev_marts.mart_drug_safety`
where report_count >= 1000
order by abs(serious_rate_gap) desc
limit 10;


-- =========================================================================
-- Axe 4 — Profil patient : qui est concerné ?
-- =========================================================================
select
    age_group,
    sex_label,
    count(*) as report_count,
    round(100 * countif(is_serious) / count(*), 1) as serious_pct
from `pharmaco-openfda-pg.dbt_dev_marts.fct_reports`
group by age_group, sex_label
order by age_group, sex_label;

-- Gravité et polymédication par tranche d'âge
select
    age_group,
    count(*) as report_count,
    round(100 * countif(is_serious) / count(*), 1) as serious_pct,
    round(avg(drug_count), 2) as avg_drug_count
from `pharmaco-openfda-pg.dbt_dev_marts.fct_reports`
group by age_group
order by age_group;


-- =========================================================================
-- Axe 5 — Géographie et déclarants : d'où viennent les cas, qui les déclare ?
-- =========================================================================
select
    occur_country,
    count(*) as report_count,
    round(100 * count(*) / sum(count(*)) over (), 1) as share_pct,
    round(100 * countif(is_serious) / count(*), 1) as serious_pct
from `pharmaco-openfda-pg.dbt_dev_marts.fct_reports`
group by occur_country
order by report_count desc
limit 10;

select
    coalesce(reporter_label, 'Inconnu') as reporter,
    count(*) as report_count,
    round(100 * count(*) / sum(count(*)) over (), 1) as share_pct,
    round(100 * countif(is_serious) / count(*), 1) as serious_pct
from `pharmaco-openfda-pg.dbt_dev_marts.fct_reports`
group by reporter
order by report_count desc;

-- Top 10 fabricants (médicament suspect)
select top_manufacturer, sum(report_count) as report_count
from `pharmaco-openfda-pg.dbt_dev_marts.mart_drug_safety`
where top_manufacturer is not null
group by top_manufacturer
order by report_count desc
limit 10;


-- =========================================================================
-- Axe 6 — Détection de signaux (PRR)
-- =========================================================================
-- Vue d'ensemble : nombre de couples et de signaux, selon le volume minimal de cas
select
    min_cases,
    countif(report_count >= min_cases) as pair_count,
    countif(report_count >= min_cases and is_signal) as signal_count
from `pharmaco-openfda-pg.dbt_dev_marts.mart_signal_prr`,
    unnest([3, 10, 50, 100]) as min_cases
group by min_cases
order by min_cases;

-- Signaux les plus solides : au moins 50 cas, classés par khi-deux
select drug_name, reaction, report_count, prr, chi_square
from `pharmaco-openfda-pg.dbt_dev_marts.mart_signal_prr`
where is_signal and report_count >= 50
order by chi_square desc
limit 15;
