{#
    Decides which schema each model is written to.

    personal: an engineer's own schemas in DEV, e.g. JSMITH_SILVER and
              JSMITH_GOLD, from the DBT_DEV_PREFIX environment variable.
              Used when an engineer deploys their feature branch.
    dev:      shared SILVER and GOLD in DEV, built from main.
    prod:     SILVER and GOLD in PROD, built from main.

    It also stops a target writing to the wrong database.
#}
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- set databases = {'personal': 'ESTIA_DBT_DEMO_DEV', 'dev': 'ESTIA_DBT_DEMO_DEV',
                         'prod': 'ESTIA_DBT_DEMO_PROD'} -%}
    {%- if target.name not in databases -%}
        {{ exceptions.raise_compiler_error('Only the personal, dev and prod targets are supported.') }}
    {%- endif -%}
    {%- if target.database | upper != databases[target.name] -%}
        {{ exceptions.raise_compiler_error('Target database does not match the target name.') }}
    {%- endif -%}
    {%- set layer = (custom_schema_name or 'SILVER') | trim | upper -%}
    {%- if target.name == 'personal' -%}
        {%- set prefix = env_var('DBT_DEV_PREFIX', '') | trim | upper -%}
        {%- if prefix in ['', 'NOT_SET'] -%}
            {{ exceptions.raise_compiler_error('Set DBT_DEV_PREFIX to your name to build into your own schemas.') }}
        {%- endif -%}
        {{ prefix }}_{{ layer }}
    {%- else -%}
        {{ layer }}
    {%- endif -%}
{%- endmacro %}
