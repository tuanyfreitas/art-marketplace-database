CREATE TABLE payment_status_history (
    id_status_history BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

    id_payment BIGINT NOT NULL,

    old_status payment_status_enum,
    new_status payment_status_enum NOT NULL,

    changed_by UUID,

    reason TEXT,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT chk_payment_status_changed
        CHECK (old_status IS DISTINCT FROM new_status),

    CONSTRAINT fk_payment_history_payment
        FOREIGN KEY (id_payment)
        REFERENCES payment(id_payment)
        ON DELETE RESTRICT,

    CONSTRAINT fk_payment_history_user
        FOREIGN KEY (changed_by)
        REFERENCES user_account(id_user)
        ON DELETE RESTRICT
);

CREATE INDEX idx_payment_history_created_at
ON payment_status_history(created_at);

CREATE INDEX idx_payment_history_payment_date
ON payment_status_history(id_payment, created_at DESC);

-- Registra automaticamente o histórico de status do pagamento
CREATE OR REPLACE FUNCTION log_payment_status_change()
RETURNS TRIGGER AS $$
BEGIN

    IF TG_OP = 'INSERT' THEN

        INSERT INTO payment_status_history (
            id_payment,
            old_status,
            new_status
        )
        VALUES (
            NEW.id_payment,
            NULL,
            NEW.payment_status
        );

    ELSIF TG_OP = 'UPDATE' THEN

        IF NEW.payment_status IS DISTINCT FROM OLD.payment_status THEN

            INSERT INTO payment_status_history (
                id_payment,
                old_status,
                new_status
            )
            VALUES (
                NEW.id_payment,
                OLD.payment_status,
                NEW.payment_status
            );

        END IF;

    END IF;

    RETURN NEW;

END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_payment_status_history
AFTER INSERT OR UPDATE OF payment_status ON payment
FOR EACH ROW
EXECUTE FUNCTION log_payment_status_change();

-- Protege o histórico de pagamentos contra alterações e exclusões
CREATE OR REPLACE FUNCTION protect_payment_status_history()
RETURNS TRIGGER AS $$
BEGIN

    RAISE EXCEPTION
        'Não é permitido alterar ou excluir registros do histórico de pagamentos';

    RETURN NULL;

END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_protect_payment_status_history
BEFORE UPDATE OR DELETE ON payment_status_history
FOR EACH ROW
EXECUTE FUNCTION protect_payment_status_history();