CREATE TABLE artwork_price_history (

    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

    id_artwork UUID NOT NULL
    REFERENCES artwork(id_artwork)
    ON DELETE RESTRICT,

    old_price NUMERIC(10,2) CHECK (old_price >= 0),

    new_price NUMERIC(10,2) NOT NULL CHECK (new_price >= 0),

    changed_by UUID
        REFERENCES user_account(id_user),

    changed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

CONSTRAINT chk_price_changed
    CHECK (old_price IS DISTINCT FROM new_price)
);


CREATE INDEX idx_price_history_artwork_date ON artwork_price_history(id_artwork, changed_at DESC);


-- Registra automaticamente o preço inicial e as alterações de preço
CREATE OR REPLACE FUNCTION log_artwork_price_change()
RETURNS TRIGGER AS $$
BEGIN
    -- Registra o preço inicial da obra
    IF TG_OP = 'INSERT' THEN

        INSERT INTO artwork_price_history (
            id_artwork,
            old_price,
            new_price
        )
        VALUES (
            NEW.id_artwork,
            NULL,
            NEW.price
        );

    -- Registra somente alterações efetivas de preço
    ELSIF TG_OP = 'UPDATE' THEN

        IF NEW.price IS DISTINCT FROM OLD.price THEN

            INSERT INTO artwork_price_history (
                id_artwork,
                old_price,
                new_price
            )
            VALUES (
                NEW.id_artwork,
                OLD.price,
                NEW.price
            );

        END IF;

    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Registra automaticamente o histórico de preços da obra
CREATE TRIGGER trg_artwork_price_history
AFTER INSERT OR UPDATE OF price ON artwork
FOR EACH ROW
EXECUTE FUNCTION log_artwork_price_change();