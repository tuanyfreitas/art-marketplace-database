CREATE TABLE user_account (
    id_user UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    person_type CHAR(1) NOT NULL CHECK (person_type IN ('F','J')),

    cpf VARCHAR(11) UNIQUE CHECK (cpf ~ '^[0-9]{11}$'),
    cnpj VARCHAR(14) UNIQUE CHECK (cnpj ~ '^[0-9]{14}$'),

    name VARCHAR(255),
    surname VARCHAR(255),
    legal_name VARCHAR(255),

    email VARCHAR(255) NOT NULL
    CHECK (
        email = TRIM(email)
        AND email ~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
    ),
    landline VARCHAR(25)
    CHECK (landline ~ '^[0-9]{10}$'),
    phone VARCHAR(25) NOT NULL
    CHECK (phone ~ '^[0-9]{10,11}$'),
    birthdate DATE
    CHECK (birthdate IS NULL OR birthdate <= CURRENT_DATE),
    profile_photo_url TEXT,
    password_hash VARCHAR(255) NOT NULL
    CHECK (LENGTH(TRIM(password_hash)) > 0),

    account_status account_status_enum NOT NULL DEFAULT 'pending',
    terms_accepted_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_login_at TIMESTAMPTZ,

    ip_origin INET,
    failed_attempts INT NOT NULL DEFAULT 0 CHECK (failed_attempts >= 0),
    email_verified_at TIMESTAMPTZ,
    locked_at TIMESTAMPTZ,

    CONSTRAINT chk_user_names_not_blank
    CHECK (
        (name IS NULL OR LENGTH(TRIM(name)) > 0)
        AND (surname IS NULL OR LENGTH(TRIM(surname)) > 0)
        AND (legal_name IS NULL OR LENGTH(TRIM(legal_name)) > 0)
    ),

    CONSTRAINT chk_user_cpf_cnpj
        CHECK (
            (person_type='F' AND cpf IS NOT NULL AND cnpj IS NULL AND name IS NOT NULL AND surname IS NOT NULL)
            OR
            (person_type='J' AND cnpj IS NOT NULL AND cpf IS NULL AND legal_name IS NOT NULL)
        )
);


-- Índices

CREATE INDEX idx_user_account_failed_attempts
ON user_account(failed_attempts)
WHERE failed_attempts > 0;

CREATE UNIQUE INDEX uq_user_account_email_lower
ON user_account (LOWER(email));

--atualizar automaticamente o campo updated_at sempre que o usuário for alterado.
CREATE TRIGGER trg_user_updated_at
BEFORE UPDATE ON user_account
FOR EACH ROW
EXECUTE FUNCTION update_updated_at();