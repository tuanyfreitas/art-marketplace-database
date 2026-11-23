CREATE TABLE donation (
    id_donation BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

    id_user UUID,

    amount NUMERIC(10,2) NOT NULL CHECK (amount > 0),

    donation_status donation_status_enum NOT NULL DEFAULT 'pending',

    id_payment BIGINT,

    created_at TIMESTAMPTZ DEFAULT NOW(),

    CONSTRAINT fk_donation_user
        FOREIGN KEY (id_user)
        REFERENCES user_account(id_user)
        ON DELETE SET NULL,

    CONSTRAINT fk_donation_payment
        FOREIGN KEY (id_payment)
        REFERENCES payment(id_payment)
        ON DELETE SET NULL
);

-- índices
CREATE INDEX idx_donation_user ON donation(id_user);

CREATE INDEX idx_donation_status ON donation(donation_status);

CREATE INDEX idx_donation_created_at ON donation(created_at DESC);

-- evita múltiplos payments para mesma doação
CREATE UNIQUE INDEX idx_donation_payment
ON donation(id_payment)
WHERE id_payment IS NOT NULL;