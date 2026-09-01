-- user_id, idempotency_key, function_name(could be enum)

-- reasons to go with enum: 
-- when you know that once a function has been made idempotent, it won't be a non idempotent function
-- if a function can have idempotency today, but not in future, then use VARCHAR, OR TEXT instead, because
-- removing ani tem from an ENUM is a pain.
-- in my case, a function can only have idempotency and will not be removed, so i am going with ENUM.
-- adding items is also seamless for enums

CREATE TYPE idempotent_functions AS ENUM('send_money');

CREATE TABLE idempotent_responses_accounts(
    customer_id     UUID                 NOT NULL,
    account_number  UUID                 NOT NULL, 
    idempotency_key UUID                 NOT NULL,
    method_name     idempotent_functions NOT NULL,
    response        JSONB                NOT NULL,
    added_on        TIMESTAMPTZ          NOT NULL DEFAULT now(),
    expires_at      TIMESTAMPTZ          NOT NULL DEFAULT now() + INTERVAL '72 Hours'
    UNIQUE                               (customer_id, idempotency_key, method_name),
    FOREIGN KEY                          (customer_id, account_number) 
    REFERENCES user_bank_accounts        (customer_id, account_number)
)

ALTER TABLE idempotent_responses_accounts ADD COLUMN added_on TIMESTAMPTZ NOT NULL DEFAULT now();

ALTER TABLE idempotent_responses_accounts ADD COLUMN expires_at TIMESTAMPTZ NOT NULL DEFAULT now() + INTERVAL '72 Hours'
