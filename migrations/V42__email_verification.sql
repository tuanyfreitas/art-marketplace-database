CREATE TABLE email_verification (
    id_verification BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

    id_user UUID NOT NULL,

    token_hash TEXT NOT NULL UNIQUE,

    requested_at TIMESTAMPTZ DEFAULT NOW(),

    expires_at TIMESTAMPTZ NOT NULL,

    verified_at TIMESTAMPTZ,

    ip_origin INET,

    user_agent TEXT,

    CONSTRAINT fk_email_verification_user
        FOREIGN KEY (id_user)
        REFERENCES user_account(id_user)
        ON DELETE CASCADE,

    CONSTRAINT chk_email_verification_dates
        CHECK (expires_at > requested_at)
);

-- por usuário
CREATE INDEX idx_email_verification_user
ON email_verification(id_user);

-- expiração (limpeza)
CREATE INDEX idx_email_verification_expiration
ON email_verification(expires_at);

-- tokens pendentes
CREATE INDEX idx_email_verification_pending
ON email_verification(id_user)
WHERE verified_at IS NULL;

CREATE UNIQUE INDEX idx_unique_active_email_verification
ON email_verification(id_user)
WHERE verified_at IS NULL;

--invalidar tokens antigos
CREATE OR REPLACE FUNCTION invalidate_old_email_tokens()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE email_verification
    SET verified_at = NOW()
    WHERE id_user = NEW.id_user
    AND verified_at IS NULL;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_invalidate_old_email_tokens
BEFORE INSERT ON email_verification
FOR EACH ROW
EXECUTE FUNCTION invalidate_old_email_tokens();