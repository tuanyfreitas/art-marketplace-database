CREATE TABLE invoice (
    id_invoice BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

    id_order BIGINT NOT NULL,

    id_seller UUID NOT NULL,

    invoice_number VARCHAR(100) NOT NULL
    CHECK (
        LENGTH(TRIM(invoice_number)) > 0
        AND invoice_number = TRIM(invoice_number)
    ),

    invoice_key VARCHAR(44) NOT NULL UNIQUE
    CHECK (invoice_key ~ '^[0-9]{44}$'),

    issued_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    invoice_url TEXT
    CHECK (
        LENGTH(TRIM(invoice_url)) > 0
        AND invoice_url = TRIM(invoice_url)
        AND invoice_url ~ '^https://[^[:space:]]+$'
    ),

    CONSTRAINT chk_invoice_dates
    CHECK (issued_at <= created_at),

    
    CONSTRAINT fk_invoice_order
    FOREIGN KEY (id_order)
    REFERENCES customer_order(id_order)
    ON DELETE RESTRICT,

    CONSTRAINT fk_invoice_seller
    FOREIGN KEY (id_seller)
    REFERENCES user_account(id_user)
    ON DELETE RESTRICT
);

CREATE INDEX idx_invoice_order_seller
ON invoice(id_order, id_seller);

CREATE INDEX idx_invoice_seller
ON invoice(id_seller);

CREATE INDEX idx_invoice_number
ON invoice(invoice_number);

CREATE INDEX idx_invoice_issued_at
ON invoice(issued_at);


-- Valida o vendedor vinculado à nota fiscal
CREATE OR REPLACE FUNCTION validate_invoice_seller()
RETURNS TRIGGER AS $$
BEGIN

    IF NOT EXISTS (
        SELECT 1
        FROM customer_order_item
        WHERE id_order = NEW.id_order
          AND id_seller = NEW.id_seller
    ) THEN
        RAISE EXCEPTION
            'O vendedor da nota fiscal não pertence ao pedido';
    END IF;

    RETURN NEW;

END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_validate_invoice_seller
BEFORE INSERT OR UPDATE OF id_order, id_seller ON invoice
FOR EACH ROW
EXECUTE FUNCTION validate_invoice_seller();

-- Valida a confirmação do pagamento para a nota fiscal
CREATE OR REPLACE FUNCTION validate_invoice_payment()
RETURNS TRIGGER AS $$
DECLARE
    v_paid_at TIMESTAMPTZ;
BEGIN

    SELECT paid_at
    INTO v_paid_at
    FROM payment
    WHERE id_order = NEW.id_order
    AND payment_status IN ('paid', 'refunded', 'chargeback')
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'O pedido deve possuir um pagamento confirmado';
    END IF;

    IF NEW.issued_at < v_paid_at THEN
        RAISE EXCEPTION
            'A nota fiscal não pode ser emitida antes da confirmação do pagamento';
    END IF;

    RETURN NEW;

END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_validate_invoice_payment
BEFORE INSERT ON invoice
FOR EACH ROW
EXECUTE FUNCTION validate_invoice_payment();

-- Protege os registros fiscais
CREATE OR REPLACE FUNCTION protect_invoice_data()
RETURNS TRIGGER AS $$
BEGIN

    IF TG_OP = 'DELETE' THEN
        RAISE EXCEPTION
            'Não é permitido excluir registros fiscais';
    END IF;

    IF NEW.id_invoice IS DISTINCT FROM OLD.id_invoice
       OR NEW.id_order IS DISTINCT FROM OLD.id_order
       OR NEW.id_seller IS DISTINCT FROM OLD.id_seller
       OR NEW.invoice_number IS DISTINCT FROM OLD.invoice_number
       OR NEW.invoice_key IS DISTINCT FROM OLD.invoice_key
       OR NEW.issued_at IS DISTINCT FROM OLD.issued_at
       OR NEW.created_at IS DISTINCT FROM OLD.created_at
    THEN
        RAISE EXCEPTION
            'Não é permitido alterar os dados originais da nota fiscal';
    END IF;

    RETURN NEW;

END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_protect_invoice_data
BEFORE UPDATE OR DELETE ON invoice
FOR EACH ROW
EXECUTE FUNCTION protect_invoice_data();