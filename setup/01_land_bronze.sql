-- ===========================================================================
-- Creates a demo environment and loads sample bronze data.
--
-- In a production setup, Azure Data Factory lands source extracts into BRONZE.
-- This script stands in for that pipeline. All data is sample data.
--
-- Run with Execute All in the Snowflake extension, once per environment:
--   1. With demo_db set to ESTIA_DBT_DEMO_DEV.
--   2. With demo_db set to ESTIA_DBT_DEMO_PROD.
-- The script stops with an error if the database already exists.
-- dbt creates the SILVER and GOLD schemas (or a developer's own schemas) itself.
-- ===========================================================================

SET demo_db = 'ESTIA_DBT_DEMO_DEV';

CREATE DATABASE IDENTIFIER($demo_db)
    COMMENT = 'dbt medallion demo';
USE DATABASE IDENTIFIER($demo_db);
CREATE SCHEMA BRONZE COMMENT = 'Raw data landed by ingestion. Not managed by dbt.';
USE SCHEMA BRONZE;

-- Columns are text, as a file copy produces. _source_file and _loaded_at
-- record which file each row came from and when it was loaded.
CREATE TABLE FACILITIES (
    facility_id   VARCHAR,
    facility_name VARCHAR,
    state         VARCHAR,
    _source_file  VARCHAR DEFAULT 'care_system/facilities_20260401.csv',
    _loaded_at    VARCHAR DEFAULT '2026-04-01 02:00:00'
);

INSERT INTO FACILITIES (facility_id, facility_name, state) VALUES
    ('F001', '  Demo Wattle House', 'vic'),
    ('F002', 'Demo Banksia Lodge  ', 'nsw'),
    ('F003', 'Demo Paperbark Place', 'qld');

CREATE TABLE RESIDENTS (
    resident_id  VARCHAR,
    facility_id  VARCHAR,
    _source_file VARCHAR DEFAULT 'care_system/residents_20260401.csv',
    _loaded_at   VARCHAR DEFAULT '2026-04-01 02:00:00'
);

INSERT INTO RESIDENTS (resident_id, facility_id) VALUES
    ('R001', 'F001'), ('R002', 'F001'), ('R003', 'F001'), ('R004', 'F001'),
    ('R005', 'F002'), ('R006', 'F002'), ('R007', 'F002'), ('R008', 'F002'),
    ('R009', 'F003'), ('R010', 'F003'), ('R011', 'F003'), ('R012', 'F003');

CREATE TABLE INCIDENTS (
    incident_id   VARCHAR,
    resident_id   VARCHAR,
    incident_date VARCHAR,
    incident_type VARCHAR,
    _source_file  VARCHAR DEFAULT 'incident_system/incidents_20260401.csv',
    _loaded_at    VARCHAR DEFAULT '2026-04-01 02:05:00'
);

INSERT INTO INCIDENTS (incident_id, resident_id, incident_date, incident_type) VALUES
    ('I001', 'R001', '2026-01-03', 'Fall'),
    ('I002', 'R002', '2026-01-08', 'Fall'),
    ('I003', 'R003', '2026-01-15', 'Medication Error'),
    ('I004', 'R004', '2026-01-26', 'Wound'),
    ('I005', 'R005', '2026-01-04', 'Fall'),
    ('I006', 'R006', '2026-01-14', 'Other'),
    ('I007', 'R007', '2026-01-24', 'Wound'),
    ('I008', 'R009', '2026-01-06', 'Medication Error'),
    ('I009', 'R010', '2026-01-17', 'Wound'),
    ('I010', 'R011', '2026-01-29', 'Other'),
    ('I011', 'R001', '2026-02-02', 'Fall'),
    ('I012', 'R002', '2026-02-12', 'Wound'),
    ('I013', 'R003', '2026-02-22', 'Other'),
    ('I014', 'R005', '2026-02-03', 'Fall'),
    ('I015', 'R006', '2026-02-09', 'Fall'),
    ('I016', 'R007', '2026-02-17', 'Medication Error'),
    ('I017', 'R008', '2026-02-26', 'Other'),
    ('I018', 'R009', '2026-02-05', 'Fall'),
    ('I019', 'R010', '2026-02-15', 'Wound'),
    ('I020', 'R012', '2026-02-25', 'Other'),
    ('I021', 'R001', '2026-03-01', 'Medication Error'),
    ('I022', 'R003', '2026-03-11', 'Wound'),
    ('I023', 'R004', '2026-03-21', 'Other'),
    ('I024', 'R005', '2026-03-04', 'Fall'),
    ('I025', 'R007', '2026-03-14', 'Wound'),
    ('I026', 'R008', '2026-03-24', 'Other'),
    ('I027', 'R009', '2026-03-02', 'Fall'),
    ('I028', 'R010', '2026-03-10', 'Fall'),
    ('I029', 'R011', '2026-03-20', 'Medication Error'),
    ('I030', 'R012', '2026-03-30', 'Other');
