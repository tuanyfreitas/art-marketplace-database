CREATE TABLE user_newsletter (
    id_user UUID PRIMARY KEY,

    is_subscribed BOOLEAN NOT NULL DEFAULT TRUE,

    subscribed_at TIMESTAMPTZ DEFAULT NOW(),
    unsubscribed_at TIMESTAMPTZ,

    CONSTRAINT fk_user_newsletter_user
        FOREIGN KEY (id_user)
        REFERENCES user_account(id_user)
        ON DELETE CASCADE,

    --consistência de estado
    CONSTRAINT chk_newsletter_status
        CHECK (
            (is_subscribed = TRUE AND unsubscribed_at IS NULL)
            OR
            (is_subscribed = FALSE AND unsubscribed_at IS NOT NULL)
        )
);

-- listar inscritos (marketing)
CREATE INDEX idx_newsletter_active
ON user_newsletter(is_subscribed)
WHERE is_subscribed = TRUE;