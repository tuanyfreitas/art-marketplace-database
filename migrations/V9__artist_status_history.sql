CREATE TABLE artist_status_history (
    id_status_history BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

    id_artist UUID NOT NULL,

    old_status artist_status_enum,
    new_status artist_status_enum NOT NULL,

    updated_by UUID,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT fk_artist_status_history_artist
    FOREIGN KEY (id_artist)
    REFERENCES artist(id_artist)
    ON DELETE CASCADE,

    CONSTRAINT fk_artist_status_history_updated_by
    FOREIGN KEY (updated_by)
    REFERENCES user_account(id_user)
    ON DELETE SET NULL
);

CREATE INDEX idx_artist_status_history_created_at ON artist_status_history(created_at DESC);
CREATE INDEX idx_artist_status_history_artist_date ON artist_status_history(id_artist, created_at DESC);

-- para registrar a mudança de status no histórico
CREATE OR REPLACE FUNCTION log_artist_status_change()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.artist_status IS DISTINCT FROM OLD.artist_status THEN

        INSERT INTO artist_status_history (
            id_artist,
            old_status,
            new_status,
            updated_by,
            created_at
        )
        VALUES (
            NEW.id_artist,
            OLD.artist_status,
            NEW.artist_status,
            NULLIF(current_setting('app.user_id', true), '')::UUID,
            NOW()
        );

    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- registra no histórico apenas quando o status do artista
-- realmente mudar
CREATE TRIGGER trg_artist_status_history
AFTER UPDATE ON artist
FOR EACH ROW
WHEN (OLD.artist_status IS DISTINCT FROM NEW.artist_status)
EXECUTE FUNCTION log_artist_status_change();
