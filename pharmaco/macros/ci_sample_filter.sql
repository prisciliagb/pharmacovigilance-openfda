{#
    En CI, limite la source aux 30 derniers jours chargés pour réduire le coût des tests.
    Ailleurs (dev), ne filtre rien.
#}
{% macro ci_sample_filter() %}
    {% if target.name == 'ci' %}
        where receive_date >= (
            select date_sub(max(receive_date), interval 30 day)
            from {{ source('openfda', 'openfda_drug_event') }}
        )
    {% endif %}
{% endmacro %}
