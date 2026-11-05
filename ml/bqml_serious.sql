-- Module 7 — Prédire la gravité d'un signalement avec BigQuery ML.
-- Source : dbt_dev_marts.ml_features_serious (features sans fuite de données, cible is_serious).
--
-- Découpage temporel : les données chargées couvrent avril → juin 2026.
--   entraînement : avril et mai 2026      test : juin 2026
-- Le mois de réception n'est pas utilisé comme feature : juin n'existe pas dans l'entraînement.


-- 1. Baseline : part de signalements graves sur la période de test.
-- Un modèle qui prédit toujours « grave » atteint cette exactitude.
select
    countif(is_serious) / count(*) as serious_share,
    countif(is_serious) / count(*) as always_serious_accuracy,
    count(*) as test_rows
from `pharmaco-openfda-pg.dbt_dev_marts.ml_features_serious`
where receive_date >= '2026-06-01';


-- 2. Modèle simple : régression logistique, classes pondérées
create or replace model `pharmaco-openfda-pg.ml.serious_logreg`
options (
    model_type = 'LOGISTIC_REG',
    input_label_cols = ['is_serious'],
    auto_class_weights = true,
    data_split_method = 'NO_SPLIT'
) as
select * except (safety_report_id, receive_date, receive_month)
from `pharmaco-openfda-pg.dbt_dev_marts.ml_features_serious`
where receive_date < '2026-06-01';


-- 3. Modèle plus fort : boosted tree, explicabilité globale activée
create or replace model `pharmaco-openfda-pg.ml.serious_boosted_tree`
options (
    model_type = 'BOOSTED_TREE_CLASSIFIER',
    input_label_cols = ['is_serious'],
    auto_class_weights = true,
    data_split_method = 'NO_SPLIT',
    max_iterations = 50,
    early_stop = false,
    enable_global_explain = true
) as
select * except (safety_report_id, receive_date, receive_month)
from `pharmaco-openfda-pg.dbt_dev_marts.ml_features_serious`
where receive_date < '2026-06-01';


-- 4. Évaluation sur la période de test (seuil 0,5)
select 'logistic_reg' as model, *
from ml.evaluate(
    model `pharmaco-openfda-pg.ml.serious_logreg`,
    (select * from `pharmaco-openfda-pg.dbt_dev_marts.ml_features_serious` where receive_date >= '2026-06-01')
)
union all
select 'boosted_tree' as model, *
from ml.evaluate(
    model `pharmaco-openfda-pg.ml.serious_boosted_tree`,
    (select * from `pharmaco-openfda-pg.dbt_dev_marts.ml_features_serious` where receive_date >= '2026-06-01')
);


-- 5. Variables les plus importantes (boosted tree)
select feature, round(attribution, 4) as attribution
from ml.global_explain(model `pharmaco-openfda-pg.ml.serious_boosted_tree`)
order by attribution desc;


-- 6. Prédictions du boosted tree pour Power BI, sur tous les signalements
create or replace table `pharmaco-openfda-pg.ml.predictions_serious` as
select
    safety_report_id,
    receive_date,
    if(receive_date >= '2026-06-01', 'test', 'train') as dataset_split,
    is_serious,
    predicted_is_serious,
    (select p.prob from unnest(predicted_is_serious_probs) as p where p.label) as serious_probability
from ml.predict(
    model `pharmaco-openfda-pg.ml.serious_boosted_tree`,
    (select * from `pharmaco-openfda-pg.dbt_dev_marts.ml_features_serious`)
);
