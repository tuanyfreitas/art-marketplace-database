CREATE TABLE address (
    id_address UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    id_user UUID NOT NULL,

    street VARCHAR(255) NOT NULL,
    number VARCHAR(10),
    complement VARCHAR(100),
    district VARCHAR(100) NOT NULL,
    city VARCHAR(100) NOT NULL,

    state CHAR(2) NOT NULL
    CHECK (state ~ '^[A-Z]{2}$'),

    postal_code CHAR(8) NOT NULL
    CHECK (postal_code ~ '^[0-9]{8}$'),

    country VARCHAR(100) NOT NULL DEFAULT 'Brasil'
    CHECK (TRIM(country) <> ''),

    address_type address_type_enum NOT NULL DEFAULT 'shipping',
    is_default BOOLEAN NOT NULL DEFAULT FALSE,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    
    CONSTRAINT chk_address_fields_not_blank
    CHECK (
        LENGTH(TRIM(street)) > 0
        AND LENGTH(TRIM(district)) > 0
        AND LENGTH(TRIM(city)) > 0
    ),

    CONSTRAINT fk_address_user
    FOREIGN KEY (id_user)
    REFERENCES user_account(id_user)
    ON DELETE CASCADE,

    CONSTRAINT unq_address_user
    UNIQUE (id_user, id_address)
);

-- Garante apenas um endereço padrão por usuário e por tipo
CREATE UNIQUE INDEX idx_unique_default_address
ON address(id_user, address_type)
WHERE is_default = TRUE;