CREATE TABLE notification (
    id_notification BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

    id_user UUID NOT NULL,

    type notification_type_enum NOT NULL,

    title TEXT,
    message TEXT,

    is_read BOOLEAN NOT NULL DEFAULT FALSE,

    metadata JSONB,

    created_at TIMESTAMPTZ DEFAULT NOW(),

    CONSTRAINT fk_notification_user
        FOREIGN KEY (id_user)
        REFERENCES user_account(id_user)
        ON DELETE CASCADE
);

-- principal (feed do usuário)
CREATE INDEX idx_notification_user_read ON notification(id_user, is_read);

-- ordenação por data
CREATE INDEX idx_notification_user_date ON notification(id_user, created_at DESC);

-- busca por tipo
CREATE INDEX idx_notification_type ON notification(type);