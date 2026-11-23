CREATE TABLE password_reset (
    id_reset BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

    id_user UUID NOT NULL,

    token_hash TEXT NOT NULL UNIQUE,

    requested_at TIMESTAMPTZ DEFAULT NOW(),

    expires_at TIMESTAMPTZ NOT NULL,

    used_at TIMESTAMPTZ,

    ip_origin INET,

    user_agent TEXT,

    CONSTRAINT fk_password_reset_user
        FOREIGN KEY (id_user)
        REFERENCES user_account(id_user)
        ON DELETE CASCADE,

    CONSTRAINT chk_reset_dates
        CHECK (expires_at > requested_at)
);

-- índices
CREATE INDEX idx_password_reset_user ON password_reset(id_user);
CREATE INDEX idx_password_reset_expiration ON password_reset(expires_at);
CREATE INDEX idx_password_reset_active
ON password_reset(id_user)
WHERE used_at IS NULL;

-- garante 1 token ativo
CREATE UNIQUE INDEX idx_unique_active_reset
ON password_reset(id_user)
WHERE used_at IS NULL;

-- função
CREATE OR REPLACE FUNCTION invalidate_old_resets()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE password_reset
    SET used_at = NOW()
    WHERE id_user = NEW.id_user
    AND used_at IS NULL;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- trigger
CREATE TRIGGER trg_invalidate_old_resets
BEFORE INSERT ON password_reset
FOR EACH ROW
EXECUTE FUNCTION invalidate_old_resets();