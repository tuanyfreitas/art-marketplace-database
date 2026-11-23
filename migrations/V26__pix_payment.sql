CREATE TABLE pix_payment (
    id_pix BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

    id_payment BIGINT NOT NULL UNIQUE,

    qr_code TEXT
    CHECK (LENGTH(TRIM(qr_code)) > 0),

    copy_paste TEXT NOT NULL
    CHECK (LENGTH(TRIM(copy_paste)) > 0),

    expiration_at TIMESTAMPTZ NOT NULL,
    paid_at TIMESTAMPTZ,

    payment_provider VARCHAR(50) NOT NULL
    CHECK (
        LENGTH(TRIM(payment_provider)) > 0
        AND payment_provider = TRIM(payment_provider)
    ),

    txid VARCHAR(35) NOT NULL
    CHECK (txid ~ '^[A-Za-z0-9]{26,35}$'),

    gateway_response JSONB
    CHECK (jsonb_typeof(gateway_response) = 'object'),

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT fk_pix_payment
    FOREIGN KEY (id_payment)
    REFERENCES payment(id_payment)
    ON DELETE RESTRICT,
    
    CONSTRAINT chk_pix_expiration
    CHECK (expiration_at > created_at),

    CONSTRAINT chk_pix_paid_at
    CHECK (
        paid_at IS NULL
        OR paid_at >= created_at
    )

);

CREATE INDEX idx_pix_expiration
ON pix_payment(expiration_at);

CREATE INDEX idx_pix_paid_at
ON pix_payment(paid_at)
WHERE paid_at IS NOT NULL;

CREATE INDEX idx_pix_created_at
ON pix_payment(created_at);

CREATE INDEX idx_pix_pending
ON pix_payment(expiration_at)
WHERE paid_at IS NULL;

CREATE UNIQUE INDEX uq_pix_provider_txid
ON pix_payment(payment_provider, txid);


-- Valida a vinculação do PIX ao pagamento
CREATE OR REPLACE FUNCTION validate_pix_payment()
RETURNS TRIGGER AS $$
DECLARE
    v_payment_method VARCHAR(50);
    v_payment_provider VARCHAR(50);
    v_payment_status payment_status_enum;
BEGIN

    SELECT payment_method, payment_provider, payment_status
    INTO v_payment_method, v_payment_provider, v_payment_status
    FROM payment
    WHERE id_payment = NEW.id_payment
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Pagamento não encontrado';
    END IF;

    IF v_payment_method IS DISTINCT FROM 'pix' THEN
        RAISE EXCEPTION
            'O método de pagamento deve ser PIX';
    END IF;

    IF v_payment_provider IS DISTINCT FROM NEW.payment_provider THEN
        RAISE EXCEPTION
            'O provedor do PIX deve corresponder ao provedor do pagamento';
    END IF;

    IF TG_OP = 'INSERT'
    AND v_payment_status NOT IN ('pending', 'processing') THEN

    RAISE EXCEPTION
        'Não é permitido criar cobrança PIX para pagamento com status %',
        v_payment_status;

    END IF;

    RETURN NEW;

END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_validate_pix_payment
BEFORE INSERT OR UPDATE ON pix_payment
FOR EACH ROW
EXECUTE FUNCTION validate_pix_payment();

-- Protege os dados do pagamento vinculado ao PIX
CREATE OR REPLACE FUNCTION protect_pix_payment_link()
RETURNS TRIGGER AS $$
BEGIN

    IF EXISTS (
        SELECT 1
        FROM pix_payment
        WHERE id_payment = OLD.id_payment
    ) THEN

        IF NEW.payment_method IS DISTINCT FROM OLD.payment_method
           OR NEW.payment_provider IS DISTINCT FROM OLD.payment_provider
        THEN
            RAISE EXCEPTION
                'Não é permitido alterar o método ou provedor de um pagamento vinculado ao PIX';
        END IF;

    END IF;

    RETURN NEW;

END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_protect_pix_payment_link
BEFORE UPDATE OF payment_method, payment_provider ON payment
FOR EACH ROW
EXECUTE FUNCTION protect_pix_payment_link();

-- Sincroniza a confirmação do pagamento PIX
CREATE OR REPLACE FUNCTION sync_pix_paid_at()
RETURNS TRIGGER AS $$
BEGIN

    UPDATE pix_payment
    SET paid_at = NEW.paid_at
    WHERE id_payment = NEW.id_payment;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'Cobrança PIX não encontrada para o pagamento %',
            NEW.id_payment;
    END IF;

    RETURN NEW;

END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_sync_pix_paid_at
AFTER UPDATE OF payment_status ON payment
FOR EACH ROW
WHEN (
    NEW.payment_method = 'pix'
    AND NEW.payment_status = 'paid'
    AND OLD.payment_status IS DISTINCT FROM NEW.payment_status
)
EXECUTE FUNCTION sync_pix_paid_at();


-- Protege os registros da cobrança PIX
CREATE OR REPLACE FUNCTION protect_pix_payment_data()
RETURNS TRIGGER AS $$
DECLARE
    v_paid_at TIMESTAMPTZ;
BEGIN

    IF TG_OP = 'DELETE' THEN
        RAISE EXCEPTION
            'Não é permitido excluir registros de cobranças PIX';
    END IF;

    IF TG_OP = 'UPDATE' THEN

        IF NEW.id_pix IS DISTINCT FROM OLD.id_pix
           OR NEW.id_payment IS DISTINCT FROM OLD.id_payment
           OR NEW.payment_provider IS DISTINCT FROM OLD.payment_provider
           OR NEW.txid IS DISTINCT FROM OLD.txid
           OR NEW.copy_paste IS DISTINCT FROM OLD.copy_paste
           OR (
           OLD.qr_code IS NOT NULL
           AND NEW.qr_code IS DISTINCT FROM OLD.qr_code
            )
           OR NEW.expiration_at IS DISTINCT FROM OLD.expiration_at
           OR NEW.created_at IS DISTINCT FROM OLD.created_at
        THEN
            RAISE EXCEPTION
                'Não é permitido alterar os dados originais da cobrança PIX';
        END IF;

    END IF;

    SELECT paid_at
    INTO v_paid_at
    FROM payment
    WHERE id_payment = NEW.id_payment
    FOR UPDATE;

    IF NEW.paid_at IS DISTINCT FROM v_paid_at THEN
        RAISE EXCEPTION
            'A data de pagamento do PIX deve corresponder à data registrada em payment';
    END IF;

    RETURN NEW;

END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_protect_pix_payment_data
BEFORE INSERT OR UPDATE OR DELETE ON pix_payment
FOR EACH ROW
EXECUTE FUNCTION protect_pix_payment_data();

