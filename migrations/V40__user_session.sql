-- gerenciamento das sessões de quem está logado. controla quem está logado no sistema, em quais dispositivos e até quando.
CREATE TABLE user_session (
    id_session BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

    id_user UUID NOT NULL,

    session_token_hash TEXT NOT NULL UNIQUE,

    created_at TIMESTAMPTZ DEFAULT NOW(),

    expires_at TIMESTAMPTZ NOT NULL,

    revoked_at TIMESTAMPTZ,

    ip_origin INET,

    user_agent TEXT,

    CONSTRAINT fk_session_user
        FOREIGN KEY (id_user)
        REFERENCES user_account(id_user)
        ON DELETE CASCADE,

    CONSTRAINT chk_session_dates
        CHECK (expires_at > created_at)
);

-- sessões por usuário
CREATE INDEX idx_session_user ON user_session(id_user);

-- sessões ativas
CREATE INDEX idx_session_active
ON user_session(id_user)
WHERE revoked_at IS NULL;

-- expiração (limpeza automática / cron)
CREATE INDEX idx_session_expiration ON user_session(expires_at);
