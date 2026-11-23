CREATE TABLE artist (
    id_artist UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    id_user UUID NOT NULL UNIQUE,

    artist_name VARCHAR(255) NOT NULL
    CHECK (LENGTH(TRIM(artist_name)) > 0),
    bio TEXT
    CHECK (bio IS NULL OR LENGTH(TRIM(bio)) > 0),

    artist_status artist_status_enum NOT NULL DEFAULT 'pending',

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT fk_artist_user
        FOREIGN KEY (id_user)
        REFERENCES user_account(id_user)
        ON DELETE CASCADE
);

CREATE INDEX idx_artist_status ON artist(artist_status);
CREATE INDEX idx_artist_created_at ON artist(created_at);
CREATE INDEX idx_artist_name ON artist(artist_name);

-- trigger updated_at
CREATE TRIGGER trg_artist_updated_at
BEFORE UPDATE ON artist
FOR EACH ROW
EXECUTE FUNCTION update_updated_at();


-- TRANSIÇÕES DE STATUS
CREATE TABLE artist_status_transition (
    from_status artist_status_enum NOT NULL,
    to_status artist_status_enum NOT NULL,

    PRIMARY KEY (from_status, to_status)
);

-- transições permitidas
INSERT INTO artist_status_transition (from_status, to_status) VALUES
('pending','under_review'),

('under_review','approved'),
('under_review','rejected'),

('rejected','under_review'),

('approved','suspended'),
('approved','inactive'),

('suspended','approved'),
('inactive','approved');

-- FUNÇÃO DE VALIDAÇÃO
CREATE OR REPLACE FUNCTION validate_artist_status_transition()
RETURNS TRIGGER AS $$
BEGIN

    -- permitir INSERT (estado inicial)
    IF TG_OP = 'INSERT' THEN
        RETURN NEW;
    END IF;

    -- evitar update inútil
    IF OLD.artist_status = NEW.artist_status THEN
        RETURN NEW;
    END IF;

    -- validar transição
    IF NOT EXISTS (
        SELECT 1
        FROM artist_status_transition
        WHERE from_status = OLD.artist_status
          AND to_status = NEW.artist_status
    ) THEN
        RAISE EXCEPTION 
        USING ERRCODE = 'check_violation',
        MESSAGE = format(
            'Invalid artist status transition from %s to %s',
            OLD.artist_status, NEW.artist_status
        );
    END IF;

    RETURN NEW;

END;
$$ LANGUAGE plpgsql;


-- TRIGGER DE VALIDAÇÃO
CREATE TRIGGER trg_validate_artist_status
BEFORE UPDATE ON artist
FOR EACH ROW
WHEN (OLD.artist_status IS DISTINCT FROM NEW.artist_status)
EXECUTE FUNCTION validate_artist_status_transition();