CREATE TABLE order_status_history (
    id_status_history BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

    id_order BIGINT NOT NULL,

    old_status order_status_enum,
    new_status order_status_enum NOT NULL,

    changed_by UUID
        REFERENCES user_account(id_user),

    note TEXT,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT chk_order_status_changed
    CHECK (old_status IS DISTINCT FROM new_status),

    CONSTRAINT fk_order_status_history_order
    FOREIGN KEY (id_order)
    REFERENCES customer_order(id_order)
    ON DELETE RESTRICT
);

CREATE INDEX idx_order_status_history_order_date ON order_status_history(id_order, created_at DESC);

-- Define as transições permitidas entre os status do pedido
CREATE TABLE order_status_transition (
    old_status order_status_enum NOT NULL,
    new_status order_status_enum NOT NULL,

    PRIMARY KEY (old_status, new_status),

    CONSTRAINT chk_order_status_transition
        CHECK (old_status <> new_status)
);

INSERT INTO order_status_transition (old_status, new_status)
VALUES
    ('created', 'awaiting_payment'),
    ('created', 'cancelled'),
    ('awaiting_payment', 'confirmed'),
    ('awaiting_payment', 'cancelled'),
    ('confirmed', 'processing'),
    ('confirmed', 'cancelled'),
    ('processing', 'completed'),
    ('processing', 'cancelled');

    -- Valida as transições de status do pedido
CREATE OR REPLACE FUNCTION validate_order_status_transition()
RETURNS TRIGGER AS $$
BEGIN

    IF TG_OP = 'INSERT' THEN

        IF NEW.order_status <> 'created' THEN
            RAISE EXCEPTION
                'Todo pedido deve iniciar com o status created';
        END IF;

        RETURN NEW;

    END IF;

    IF NEW.order_status IS DISTINCT FROM OLD.order_status THEN

        IF NOT EXISTS (
            SELECT 1
            FROM order_status_transition
            WHERE old_status = OLD.order_status
              AND new_status = NEW.order_status
        ) THEN
            RAISE EXCEPTION
                'Transição de status não permitida: % -> %',
                OLD.order_status,
                NEW.order_status;
        END IF;

    END IF;

    RETURN NEW;

END;
$$ LANGUAGE plpgsql;


CREATE TRIGGER trg_validate_order_status_transition
BEFORE INSERT OR UPDATE OF order_status ON customer_order
FOR EACH ROW
EXECUTE FUNCTION validate_order_status_transition();

-- Registra automaticamente o histórico de status do pedido
CREATE OR REPLACE FUNCTION log_order_status_change()
RETURNS TRIGGER AS $$
BEGIN

    IF TG_OP = 'INSERT' THEN

        INSERT INTO order_status_history (
            id_order,
            old_status,
            new_status
        )
        VALUES (
            NEW.id_order,
            NULL,
            NEW.order_status
        );

    ELSIF TG_OP = 'UPDATE' THEN

        IF NEW.order_status IS DISTINCT FROM OLD.order_status THEN

            INSERT INTO order_status_history (
                id_order,
                old_status,
                new_status
            )
            VALUES (
                NEW.id_order,
                OLD.order_status,
                NEW.order_status
            );

        END IF;

    END IF;

    RETURN NEW;

END;
$$ LANGUAGE plpgsql;


CREATE TRIGGER trg_order_status_history
AFTER INSERT OR UPDATE OF order_status ON customer_order
FOR EACH ROW
EXECUTE FUNCTION log_order_status_change();

-- Protege os registros do histórico de status
CREATE OR REPLACE FUNCTION protect_order_status_history()
RETURNS TRIGGER AS $$
BEGIN

    RAISE EXCEPTION
        'Não é permitido alterar ou excluir registros do histórico de status do pedido';

    RETURN NULL;

END;
$$ LANGUAGE plpgsql;


CREATE TRIGGER trg_protect_order_status_history
BEFORE UPDATE OR DELETE ON order_status_history
FOR EACH ROW
EXECUTE FUNCTION protect_order_status_history();