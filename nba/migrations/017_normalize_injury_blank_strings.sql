-- Normalize injury fields so missing values are stored as NULL (not empty/blank strings).

UPDATE nba.injuries
SET
    injury_status = NULLIF(BTRIM(injury_status), ''),
    injury_type = NULLIF(BTRIM(injury_type), ''),
    injury_location = NULLIF(BTRIM(injury_location), ''),
    injury_details = NULLIF(BTRIM(injury_details), ''),
    injury_side = NULLIF(BTRIM(injury_side), ''),
    return_date = NULLIF(BTRIM(return_date), '')
WHERE
    (injury_status IS NOT NULL AND BTRIM(injury_status) = '') OR
    (injury_type IS NOT NULL AND BTRIM(injury_type) = '') OR
    (injury_location IS NOT NULL AND BTRIM(injury_location) = '') OR
    (injury_details IS NOT NULL AND BTRIM(injury_details) = '') OR
    (injury_side IS NOT NULL AND BTRIM(injury_side) = '') OR
    (return_date IS NOT NULL AND BTRIM(return_date) = '');

UPDATE nba.injuries_history
SET
    injury_status = NULLIF(BTRIM(injury_status), ''),
    injury_type = NULLIF(BTRIM(injury_type), ''),
    injury_location = NULLIF(BTRIM(injury_location), ''),
    injury_details = NULLIF(BTRIM(injury_details), ''),
    injury_side = NULLIF(BTRIM(injury_side), ''),
    return_date = NULLIF(BTRIM(return_date), '')
WHERE
    (injury_status IS NOT NULL AND BTRIM(injury_status) = '') OR
    (injury_type IS NOT NULL AND BTRIM(injury_type) = '') OR
    (injury_location IS NOT NULL AND BTRIM(injury_location) = '') OR
    (injury_details IS NOT NULL AND BTRIM(injury_details) = '') OR
    (injury_side IS NOT NULL AND BTRIM(injury_side) = '') OR
    (return_date IS NOT NULL AND BTRIM(return_date) = '');
