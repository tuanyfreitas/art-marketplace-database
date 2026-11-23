CREATE TABLE artwork_reservation (
    id_reservation BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

    id_artwork UUID NOT NULL,
    id_user UUID NOT NULL,
    quantity INT NOT NULL DEFAULT 1 CHECK (quantity > 0),
    reserved_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    expires_at TIMESTAMPTZ NOT NULL
        DEFAULT (NOW() + INTERVAL '20 minutes'),

    active BOOLEAN NOT NULL DEFAULT TRUE,

    CONSTRAINT chk_reservation_expiration
    CHECK (expires_at = reserved_at + INTERVAL '20 minutes'),

    CONSTRAINT fk_reservation_artwork
    FOREIGN KEY (id_artwork)
    REFERENCES artwork(id_artwork)
    ON DELETE RESTRICT,

    CONSTRAINT fk_reservation_user
    FOREIGN KEY (id_user)
    REFERENCES user_account(id_user)
    ON DELETE RESTRICT
);

CREATE INDEX idx_reservation_active_artwork
ON artwork_reservation(id_artwork)
WHERE active = TRUE;

CREATE INDEX idx_reservation_active_expires
ON artwork_reservation(expires_at)
WHERE active = TRUE;

-- Desativa reservas expiradas e libera as unidades no estoque
-- A função deve ser executada a cada 1 minuto por um agendador externo
CREATE OR REPLACE FUNCTION expire_artwork_reservations()
RETURNS INTEGER AS $$
DECLARE
    expired_count INTEGER;
BEGIN
    UPDATE artwork_reservation
    SET active = FALSE
    WHERE active = TRUE
      AND expires_at <= NOW();

    GET DIAGNOSTICS expired_count = ROW_COUNT;

    RETURN expired_count;
END;
$$ LANGUAGE plpgsql;

-- Controla a quantidade reservada no estoque
CREATE OR REPLACE FUNCTION manage_artwork_reservation_stock()
RETURNS TRIGGER AS $$
BEGIN

    -- Protege os dados de uma reserva já criada
    IF TG_OP = 'UPDATE' THEN

        IF NEW.id_artwork IS DISTINCT FROM OLD.id_artwork
        OR NEW.id_user IS DISTINCT FROM OLD.id_user
        OR NEW.quantity IS DISTINCT FROM OLD.quantity
        OR NEW.reserved_at IS DISTINCT FROM OLD.reserved_at
        OR NEW.expires_at IS DISTINCT FROM OLD.expires_at THEN
     RAISE EXCEPTION
         'Não é permitido alterar os dados originais de uma reserva existente';
END IF;

-- Impede reativar uma reserva desativada
IF OLD.active = FALSE AND NEW.active = TRUE THEN
    RAISE EXCEPTION
        'Não é permitido reativar uma reserva desativada';
END IF;
    END IF;


 -- Ao criar uma reserva ativa, reserva as unidades no estoque
IF TG_OP = 'INSERT' AND NEW.active = TRUE THEN

    -- Impede criar uma reserva ativa com prazo vencido
    IF NEW.expires_at <= NOW() THEN
        RAISE EXCEPTION
            'Não é permitido criar uma reserva com prazo já vencido';
    END IF;

    UPDATE artwork_stock
    SET reserved_units = reserved_units + NEW.quantity
    WHERE id_artwork = NEW.id_artwork
      AND total_units - sold_units - reserved_units >= NEW.quantity;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'Estoque insuficiente ou não cadastrado para a obra %',
            NEW.id_artwork;
    END IF;

END IF;

    -- Libera as unidades quando uma reserva é desativada
    IF TG_OP = 'UPDATE'
       AND OLD.active = TRUE
       AND NEW.active = FALSE THEN

        UPDATE artwork_stock
        SET reserved_units = reserved_units - OLD.quantity
        WHERE id_artwork = OLD.id_artwork;

        IF NOT FOUND THEN
            RAISE EXCEPTION
                'Estoque não encontrado para a obra %',
                OLD.id_artwork;
        END IF;

    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Atualiza o estoque ao criar ou modificar uma reserva
CREATE TRIGGER trg_manage_artwork_reservation_stock
AFTER INSERT OR UPDATE ON artwork_reservation
FOR EACH ROW
EXECUTE FUNCTION manage_artwork_reservation_stock();


-- Impede a exclusão direta de reservas
CREATE OR REPLACE FUNCTION prevent_artwork_reservation_delete()
RETURNS TRIGGER AS $$
BEGIN
    RAISE EXCEPTION
        'Não é permitido excluir reservas. Desative a reserva para liberar o estoque.';
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_prevent_artwork_reservation_delete
BEFORE DELETE ON artwork_reservation
FOR EACH ROW
EXECUTE FUNCTION prevent_artwork_reservation_delete();