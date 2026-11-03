{#
    Decides which schema each model is written to.

    prod: the schema named in dbt_project.yml, e.g. SILVER or GOLD.
    dev:  the developer's own schemas, e.g. RVASHISHT_SILVER and RVASHISHT_GOLD,
          using the DBT_DEV_PREFIX environment variable. Engineers can build
          and test on a branch without affecting anyone else.

    It also stops a target writing to the other environment's database.
#}
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- if target.name not in ['dev', 'prod'] -%}
        {{ exceptions.raise_compiler_error('Only the dev and prod targets are supported.') }}
    {%- endif -%}
    {%- if target.database != 'ESTIA_DBT_DEMO_' ~ (target.name | upper) -%}
        {{ exceptions.raise_compiler_error('Target database does not match the target name.') }}
    {%- endif -%}
    {%- set layer = (custom_schema_name or 'SILVER') | trim | upper -%}
    {%- if target.name == 'dev' -%}
        {{ env_var('DBT_DEV_PREFIX') | trim | upper }}_{{ layer }}
    {%- else -%}
        {{ layer }}
    {%- endif -%}
{%- endmacro %}
