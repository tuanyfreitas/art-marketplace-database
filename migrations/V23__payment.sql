CREATE TABLE payment (
    id_payment BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

    id_order BIGINT NOT NULL,

    payment_provider VARCHAR(50)
        CHECK (LENGTH(TRIM(payment_provider)) > 0),

    provider_transaction_id VARCHAR(255)
        CHECK (LENGTH(TRIM(provider_transaction_id)) > 0),

    payment_method VARCHAR(50) NOT NULL
        CHECK (LENGTH(TRIM(payment_method)) > 0),

    amount NUMERIC(10,2) NOT NULL CHECK (amount >= 0),

    currency CHAR(3) NOT NULL DEFAULT 'BRL'
        CHECK (currency ~ '^[A-Z]{3}$'),

    payment_status payment_status_enum NOT NULL DEFAULT 'pending',

    paid_at TIMESTAMPTZ,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT fk_payment_order
        FOREIGN KEY (id_order)
        REFERENCES customer_order(id_order)
        ON DELETE RESTRICT,

    CONSTRAINT chk_payment_provider_transaction
        CHECK (
            provider_transaction_id IS NULL
            OR payment_provider IS NOT NULL
        ),

    CONSTRAINT chk_payment_paid_at
        CHECK (
            payment_status NOT IN ('paid', 'refunded', 'chargeback')
            OR paid_at IS NOT NULL
        ),

    CONSTRAINT chk_payment_date
        CHECK (
            paid_at IS NULL
            OR paid_at >= created_at
        )
);

CREATE INDEX idx_payment_order_status ON payment(id_order, payment_status);
CREATE INDEX idx_payment_status ON payment(payment_status);
CREATE UNIQUE INDEX uq_payment_provider_tx
ON payment(payment_provider, provider_transaction_id)
WHERE provider_transaction_id IS NOT NULL;
CREATE INDEX idx_payment_paid
ON payment(paid_at)
WHERE payment_status = 'paid';

-- Impede a exclusão de registros de pagamento
CREATE OR REPLACE FUNCTION prevent_payment_delete()
RETURNS TRIGGER AS $$
BEGIN

    RAISE EXCEPTION
        'Não é permitido excluir registros de pagamento';

    RETURN NULL;

END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_prevent_payment_delete
BEFORE DELETE ON payment
FOR EACH ROW
EXECUTE FUNCTION prevent_payment_delete();

-- Garante apenas um pagamento efetivado por pedido
CREATE UNIQUE INDEX uq_payment_successful_order
ON payment(id_order)
WHERE payment_status IN ('paid', 'refunded', 'chargeback');

-- Protege os dados originais do pagamento
CREATE OR REPLACE FUNCTION protect_payment_data()
RETURNS TRIGGER AS $$
BEGIN

    IF NEW.id_payment IS DISTINCT FROM OLD.id_payment
       OR NEW.id_order IS DISTINCT FROM OLD.id_order
       OR NEW.amount IS DISTINCT FROM OLD.amount
       OR NEW.currency IS DISTINCT FROM OLD.currency
       OR NEW.created_at IS DISTINCT FROM OLD.created_at
    THEN
        RAISE EXCEPTION
            'Não é permitido alterar os dados originais do pagamento';
    END IF;

    IF (
    OLD.payment_provider IS NOT NULL
    OR OLD.payment_status IN ('paid', 'refunded', 'chargeback')
    )
    AND NEW.payment_provider IS DISTINCT FROM OLD.payment_provider
    THEN
        RAISE EXCEPTION
            'Não é permitido alterar o provedor de pagamento';
    END IF;

        IF (
        OLD.provider_transaction_id IS NOT NULL
        OR OLD.payment_status IN ('paid', 'refunded', 'chargeback')
    )
    AND NEW.provider_transaction_id IS DISTINCT FROM OLD.provider_transaction_id
    THEN
        RAISE EXCEPTION
            'Não é permitido alterar o identificador da transação';
    END IF;

    IF NEW.payment_method IS DISTINCT FROM OLD.payment_method THEN
        RAISE EXCEPTION
            'Não é permitido alterar o método de pagamento após seu cadastro';
    END IF;

    RETURN NEW;

END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_protect_payment_data
BEFORE UPDATE ON payment
FOR EACH ROW
EXECUTE FUNCTION protect_payment_data();

-- Define as transições permitidas de pagamento
CREATE TABLE payment_status_transition (
    old_status payment_status_enum NOT NULL,
    new_status payment_status_enum NOT NULL,

    PRIMARY KEY (old_status, new_status),

    CONSTRAINT chk_payment_status_transition
        CHECK (old_status <> new_status)
);

INSERT INTO payment_status_transition (old_status, new_status)
VALUES
    ('pending', 'processing'),
    ('pending', 'paid'),
    ('pending', 'refused'),
    ('pending', 'expired'),
    ('processing', 'paid'),
    ('processing', 'refused'),
    ('processing', 'expired'),
    ('paid', 'refunded'),
    ('paid', 'chargeback');

    -- Valida as transições de status do pagamento
CREATE OR REPLACE FUNCTION validate_payment_status_transition()
RETURNS TRIGGER AS $$
BEGIN

    IF TG_OP = 'INSERT' THEN

        IF NEW.payment_status <> 'pending' THEN
            RAISE EXCEPTION
                'Todo pagamento deve iniciar com o status pending';
        END IF;

        RETURN NEW;

    END IF;

    IF NEW.payment_status IS DISTINCT FROM OLD.payment_status THEN

        IF NOT EXISTS (
            SELECT 1
            FROM payment_status_transition
            WHERE old_status = OLD.payment_status
              AND new_status = NEW.payment_status
        ) THEN
            RAISE EXCEPTION
                'Transição de pagamento não permitida: % -> %',
                OLD.payment_status,
                NEW.payment_status;
        END IF;

    END IF;

    RETURN NEW;

END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_validate_payment_status_transition
BEFORE INSERT OR UPDATE OF payment_status ON payment
FOR EACH ROW
EXECUTE FUNCTION validate_payment_status_transition();

-- Gerencia a data de confirmação do pagamento
CREATE OR REPLACE FUNCTION manage_payment_paid_at()
RETURNS TRIGGER AS $$
BEGIN

    IF TG_OP = 'UPDATE' THEN

        IF OLD.paid_at IS NOT NULL
           AND NEW.paid_at IS DISTINCT FROM OLD.paid_at
        THEN
            RAISE EXCEPTION
                'Não é permitido alterar a data original do pagamento';
        END IF;

    END IF;

    IF NEW.payment_status = 'paid'
    AND (
       NEW.payment_provider IS NULL
       OR NEW.provider_transaction_id IS NULL
  )
    THEN
    RAISE EXCEPTION
        'Pagamento confirmado deve possuir provedor e identificador da transação';
END IF;

    IF NEW.payment_status = 'paid'
   AND NEW.paid_at IS NULL
   THEN
    NEW.paid_at := NOW();
END IF;
    
    IF NEW.payment_status NOT IN ('paid', 'refunded', 'chargeback')
       AND NEW.paid_at IS NOT NULL
    THEN
        RAISE EXCEPTION
            'Pagamento não confirmado não pode possuir paid_at';
    END IF;

    RETURN NEW;

END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_manage_payment_paid_at
BEFORE INSERT OR UPDATE ON payment
FOR EACH ROW
EXECUTE FUNCTION manage_payment_paid_at();


-- Valida o pedido, o valor e a moeda do pagamento
CREATE OR REPLACE FUNCTION validate_payment_amount()
RETURNS TRIGGER AS $$
DECLARE
    v_order_total NUMERIC(10,2);
    v_order_currency CHAR(3);
    v_order_status order_status_enum;
    v_order_payment_method VARCHAR(50);

BEGIN

    SELECT total_amount, currency, order_status, payment_method
    INTO v_order_total, v_order_currency, v_order_status,
     v_order_payment_method
    FROM customer_order
    WHERE id_order = NEW.id_order
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'Pedido não encontrado: %', NEW.id_order;
    END IF;

    IF TG_OP = 'INSERT'
       AND v_order_status <> 'awaiting_payment'
    THEN
        RAISE EXCEPTION
            'O pedido deve estar aguardando pagamento';
    END IF;

    IF NEW.amount IS DISTINCT FROM v_order_total THEN
        RAISE EXCEPTION
            'Valor do pagamento (%) diferente do total do pedido (%)',
            NEW.amount, v_order_total;
    END IF;

    IF NEW.currency IS DISTINCT FROM v_order_currency THEN
        RAISE EXCEPTION
            'Moeda do pagamento diferente da moeda do pedido';
    END IF;

    IF NEW.payment_method IS DISTINCT FROM v_order_payment_method THEN
    RAISE EXCEPTION
        'Método de pagamento diferente do método registrado no pedido';
    END IF;

    RETURN NEW;

END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_validate_payment_amount
BEFORE INSERT ON payment
FOR EACH ROW
EXECUTE FUNCTION validate_payment_amount();

-- Valida o status do pedido antes de confirmar o pagamento
CREATE OR REPLACE FUNCTION validate_payment_confirmation()
RETURNS TRIGGER AS $$
DECLARE
    v_order_status order_status_enum;

BEGIN

    SELECT order_status
    INTO v_order_status
    FROM customer_order
    WHERE id_order = NEW.id_order
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'Pedido não encontrado: %', NEW.id_order;
    END IF;

    IF v_order_status <> 'awaiting_payment' THEN
        RAISE EXCEPTION
            'Não é possível confirmar o pagamento de um pedido com status %',
            v_order_status;
    END IF;

    RETURN NEW;

END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_validate_payment_confirmation
BEFORE UPDATE OF payment_status ON payment
FOR EACH ROW
WHEN (
    NEW.payment_status = 'paid'
    AND OLD.payment_status IS DISTINCT FROM NEW.payment_status
)
EXECUTE FUNCTION validate_payment_confirmation();

-- Atualiza o pedido após a confirmação do pagamento
CREATE OR REPLACE FUNCTION confirm_order_after_payment()
RETURNS TRIGGER AS $$
BEGIN

    UPDATE customer_order
    SET
        order_status = 'confirmed',
        payment_status = 'paid',
        id_transaction = NEW.provider_transaction_id,
        purchase_datetime = NEW.paid_at
    WHERE id_order = NEW.id_order
      AND order_status = 'awaiting_payment';

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'Não foi possível confirmar o pedido %',
            NEW.id_order;
    END IF;

    RETURN NEW;

END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_confirm_order_after_payment
AFTER UPDATE OF payment_status ON payment
FOR EACH ROW
WHEN (
    NEW.payment_status = 'paid'
    AND OLD.payment_status IS DISTINCT FROM NEW.payment_status
)
EXECUTE FUNCTION confirm_order_after_payment();

-- Impede a confirmação de pedidos sem pagamento efetivado
CREATE OR REPLACE FUNCTION validate_order_payment()
RETURNS TRIGGER AS $$
BEGIN

    IF NEW.order_status = 'confirmed'
       AND NEW.order_status IS DISTINCT FROM OLD.order_status
    THEN

        IF NOT EXISTS (
            SELECT 1
            FROM payment
            WHERE id_order = NEW.id_order
              AND payment_status = 'paid'
              AND amount = NEW.total_amount
              AND currency = NEW.currency
        ) THEN
            RAISE EXCEPTION
                'Não é permitido confirmar um pedido sem pagamento efetivado';
        END IF;

    END IF;

    RETURN NEW;

END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_validate_order_payment
BEFORE UPDATE OF order_status ON customer_order
FOR EACH ROW
EXECUTE FUNCTION validate_order_payment();

-- Valida o status financeiro do pedido
CREATE OR REPLACE FUNCTION validate_order_payment_status()
RETURNS TRIGGER AS $$
DECLARE
    v_payment_status payment_status_enum;

BEGIN

    SELECT payment_status
    INTO v_payment_status
    FROM payment
    WHERE id_order = NEW.id_order
      AND payment_status IN ('paid', 'refunded', 'chargeback')
      AND amount = NEW.total_amount
      AND currency = NEW.currency;

    IF FOUND THEN

        IF NEW.payment_status IS DISTINCT FROM v_payment_status THEN
            RAISE EXCEPTION
                'Status financeiro do pedido incompatível com o pagamento';
        END IF;

    ELSIF NEW.payment_status IN ('paid', 'refunded', 'chargeback') THEN

        RAISE EXCEPTION
            'Pedido não possui pagamento correspondente';

    END IF;

    RETURN NEW;

END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_validate_order_payment_status
BEFORE INSERT OR UPDATE OF payment_status ON customer_order
FOR EACH ROW
EXECUTE FUNCTION validate_order_payment_status();

-- Sincroniza estornos e chargebacks com o pedido
CREATE OR REPLACE FUNCTION sync_order_payment_reversal()
RETURNS TRIGGER AS $$
BEGIN

    UPDATE customer_order
    SET payment_status = NEW.payment_status
    WHERE id_order = NEW.id_order;

    RETURN NEW;

END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_sync_order_payment_reversal
AFTER UPDATE OF payment_status ON payment
FOR EACH ROW
WHEN (
    NEW.payment_status IN ('refunded', 'chargeback')
    AND OLD.payment_status IS DISTINCT FROM NEW.payment_status
)
EXECUTE FUNCTION sync_order_payment_reversal();

-- Sincroniza o status das tentativas de pagamento
CREATE OR REPLACE FUNCTION sync_order_payment_attempt()
RETURNS TRIGGER AS $$
BEGIN

    UPDATE customer_order
    SET payment_status = NEW.payment_status
    WHERE id_order = NEW.id_order
      AND order_status = 'awaiting_payment'
      AND NOT EXISTS (
          SELECT 1
          FROM payment
          WHERE id_order = NEW.id_order
            AND payment_status IN ('paid', 'refunded', 'chargeback')
      )
      AND NEW.id_payment = (
          SELECT MAX(id_payment)
          FROM payment
          WHERE id_order = NEW.id_order
      );

    RETURN NEW;

END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_sync_order_payment_attempt
AFTER INSERT OR UPDATE OF payment_status ON payment
FOR EACH ROW
WHEN (
    NEW.payment_status IN ('pending', 'processing', 'refused', 'expired')
)
EXECUTE FUNCTION sync_order_payment_attempt();
