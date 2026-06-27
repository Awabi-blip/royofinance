CREATE TYPE e_branch_size AS ENUM('enterprise', 'new', 'medium');
DROP TABLE IF EXISTS bank_branches;
CREATE TABLE IF NOT EXISTS bank_branches(
    branch_number SMALLSERIAL,
    city SMALLINT NOT NULL,
    branch_size e_branch_size NOT NULL,
    PRIMARY KEY(branch_number),
    FOREIGN KEY(city) REFERENCES cities(id)
);

INSERT INTO bank_branches(
    city, branch_size
)
VALUES(
    (SELECT id from cities where name = 'Karachi'),
    'enterprise'::e_branch_size
);

INSERT INTO bank_branches(
    city, branch_size
)
VALUES(
    (SELECT id from cities where name = 'Lahore'),
    'new'::e_branch_size
);


SELECT * from bank_branches