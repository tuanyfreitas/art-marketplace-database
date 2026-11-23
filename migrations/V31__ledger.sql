CREATE TABLE ledger (
    id_ledger BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

    id_user UUID NOT NULL,

    reference_type ledger_reference_enum NOT NULL,
    reference_id UUID,

    entry_type ledger_type_enum NOT NULL,
    direction ledger_direction_enum NOT NULL,

    amount NUMERIC(10,2) NOT NULL CHECK (amount > 0),

    currency VARCHAR(10) NOT NULL DEFAULT 'BRL',

    created_at TIMESTAMPTZ DEFAULT NOW(),

    CONSTRAINT fk_ledger_user
        FOREIGN KEY (id_user)
        REFERENCES user_account(id_user)
        ON DELETE RESTRICT
);

CREATE INDEX idx_ledger_user ON ledger(id_user);
CREATE INDEX idx_ledger_reference ON ledger(reference_type, reference_id);
CREATE INDEX idx_ledger_created_at ON ledger(created_at);
CREATE INDEX idx_ledger_user_created ON ledger(id_user, created_at DESC);
