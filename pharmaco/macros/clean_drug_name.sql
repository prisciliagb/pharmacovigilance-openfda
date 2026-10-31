{#
    Nettoie un nom de médicament déclaré en texte libre :
    majuscules, contenu entre parenthèses retiré, dosage et tout ce qui suit retirés
    (« METFORMIN 500 MG TABLETS » → « METFORMIN »), ponctuation et espaces multiples réduits.
#}
{% macro clean_drug_name(column) %}
    nullif(trim(regexp_replace(
        regexp_replace(
            regexp_replace(
                regexp_replace(upper({{ column }}), r'\([^)]*\)', ' '),
                r'\s*\d+([.,]\d+)?\s*(MG|MCG|UG|G|ML|L|IU|UNITS?|MEQ|%)\b.*$', ''
            ),
            r'[^A-Z0-9 /-]', ' '
        ),
        r'\s+', ' '
    )), '')
{% endmacro %}
