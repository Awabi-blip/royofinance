CREATE TABLE IF NOT EXISTS cities(
    id SMALLSERIAL,
    name TEXT UNIQUE,
    PRIMARY KEY(id)
);
INSERT INTO cities (name)
SELECT DISTINCT(CITY) from STAGING;
SELECT * FROM cities;
SELECT city FROM staging;
CREATE TABLE STAGING(
    city TEXT,
    lat TEXT,
    lng TEXT,
    country TEXT,
    iso2 TEXT,
    admin_name TEXT,
    capital TEXT,
    population TEXT,
    population_proper TEXT
);

