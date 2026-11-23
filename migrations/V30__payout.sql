CREATE TABLE payout (
    id_payout BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

    id_order BIGINT NOT NULL,
    id_payment BIGINT NOT NULL,
    id_seller UUID NOT NULL,

    payout_amount NUMERIC(10,2) NOT NULL
    CHECK (payout_amount > 0),

    settlement_status settlement_status_enum NOT NULL DEFAULT 'pending',

    payout_provider VARCHAR(50)
    CHECK (LENGTH(TRIM(payout_provider)) > 0),

    provider_payout_id VARCHAR(255)
    CHECK (LENGTH(TRIM(provider_payout_id)) > 0),

    paid_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT fk_payout_order
        FOREIGN KEY (id_order)
        REFERENCES customer_order(id_order)
        ON DELETE RESTRICT,

    CONSTRAINT fk_payout_payment
        FOREIGN KEY (id_payment)
        REFERENCES payment(id_payment)
        ON DELETE RESTRICT,

    CONSTRAINT fk_payout_seller
        FOREIGN KEY (id_seller)
        REFERENCES user_account(id_user)
        ON DELETE RESTRICT,

    CONSTRAINT chk_payout_dates
        CHECK (paid_at IS NULL OR paid_at >= created_at),

    CONSTRAINT chk_payout_provider
        CHECK (
            provider_payout_id IS NULL
            OR payout_provider IS NOT NULL)

    CONSTRAINT chk_payout_completed
    CHECK (
        settlement_status <> 'completed'
        OR (
            payout_provider IS NOT NULL
            AND provider_payout_id IS NOT NULL
            AND paid_at IS NOT NULL
        )
    )        
);

CREATE INDEX idx_payout_seller_status ON payout(id_seller, settlement_status);
CREATE INDEX idx_payout_order ON payout(id_order);
CREATE INDEX idx_payout_status ON payout(settlement_status);
CREATE INDEX idx_payout_payment ON payout(id_payment);

-- Atualiza automaticamente a data de modificação
CREATE TRIGGER trg_payout_updated_at
BEFORE UPDATE ON payout
FOR EACH ROW
EXECUTE FUNCTION update_updated_at();

-- Impede a duplicidade de transferências no provedor
CREATE UNIQUE INDEX uq_payout_provider_transaction
ON payout(payout_provider, provider_payout_id)
WHERE provider_payout_id IS NOT NULL;


-- Valida o vínculo entre pagamento e pedido
CREATE OR REPLACE FUNCTION validate_payout_payment()
RETURNS TRIGGER AS $$
BEGIN

    IF NOT EXISTS (
        SELECT 1
        FROM payment
        WHERE id_payment = NEW.id_payment
          AND id_order = NEW.id_order
    ) THEN

        RAISE EXCEPTION
            'O pagamento informado não pertence ao pedido';

    END IF;

    RETURN NEW;

END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_validate_payout_payment
BEFORE INSERT OR UPDATE OF id_payment, id_order ON payout
FOR EACH ROW
EXECUTE FUNCTION validate_payout_payment();

-- Valida o beneficiário do repasse
CREATE OR REPLACE FUNCTION validate_payout_seller()
RETURNS TRIGGER AS $$
BEGIN

    IF NOT EXISTS (
        SELECT 1
        FROM payment_split
        WHERE id_payment = NEW.id_payment
          AND id_receiver = NEW.id_seller
          AND split_role = 'artist'
          AND amount > 0
    ) THEN

        RAISE EXCEPTION
            'O artista não possui direito ao repasse deste pagamento';

    END IF;

    RETURN NEW;

END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_validate_payout_seller
BEFORE INSERT OR UPDATE OF id_payment, id_seller ON payout
FOR EACH ROW
EXECUTE FUNCTION validate_payout_seller();

-- Valida o valor do repasse
CREATE OR REPLACE FUNCTION validate_payout_amount()
RETURNS TRIGGER AS $$
DECLARE
    v_split_amount NUMERIC(10,2);
BEGIN

    SELECT amount
    INTO v_split_amount
    FROM payment_split
    WHERE id_payment = NEW.id_payment
      AND id_receiver = NEW.id_seller
      AND split_role = 'artist';

    IF v_split_amount IS NULL THEN
        RAISE EXCEPTION
            'Não existe valor de repasse destinado ao artista';
    END IF;

    IF NEW.payout_amount > v_split_amount THEN
        RAISE EXCEPTION
            'O valor do repasse excede o valor destinado ao artista';
    END IF;

    RETURN NEW;

END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_validate_payout_amount
BEFORE INSERT OR UPDATE OF payout_amount, id_payment, id_seller ON payout
FOR EACH ROW
EXECUTE FUNCTION validate_payout_amount();

-- Valida o valor acumulado dos repasses
CREATE OR REPLACE FUNCTION validate_payout_balance()
RETURNS TRIGGER AS $$
DECLARE
    v_split_amount NUMERIC;
    v_total_payout NUMERIC;
BEGIN

    -- Bloqueia o pagamento durante a validação
    PERFORM 1
    FROM payment
    WHERE id_payment = NEW.id_payment
    FOR UPDATE;

    IF NEW.settlement_status IN (
        'pending', 'processing', 'completed'
    ) THEN

        SELECT amount
        INTO v_split_amount
        FROM payment_split
        WHERE id_payment = NEW.id_payment
          AND id_receiver = NEW.id_seller
          AND split_role = 'artist';

        SELECT COALESCE(SUM(payout_amount), 0)
        INTO v_total_payout
        FROM payout
        WHERE id_payment = NEW.id_payment
          AND id_seller = NEW.id_seller
          AND settlement_status IN (
              'pending', 'processing', 'completed'
          )
          AND id_payout IS DISTINCT FROM NEW.id_payout;

        IF v_split_amount IS NULL
           OR v_total_payout + NEW.payout_amount > v_split_amount
        THEN
            RAISE EXCEPTION
                'O valor acumulado dos repasses excede o saldo do artista';
        END IF;

    END IF;

    RETURN NEW;

END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_validate_payout_balance
BEFORE INSERT OR UPDATE ON payout
FOR EACH ROW
EXECUTE FUNCTION validate_payout_balance();

-- Valida a situação financeira do pagamento
CREATE OR REPLACE FUNCTION validate_payout_payment_status()
RETURNS TRIGGER AS $$
DECLARE
    v_payment_status payment_status_enum;
BEGIN

    SELECT payment_status
    INTO v_payment_status
    FROM payment
    WHERE id_payment = NEW.id_payment
    FOR UPDATE;

    IF TG_OP = 'UPDATE' THEN

        IF NEW.settlement_status = OLD.settlement_status THEN
            RETURN NEW;
        END IF;

    END IF;

    IF NEW.settlement_status IN ('pending', 'processing')
       AND v_payment_status IS DISTINCT FROM 'paid'
    THEN
        RAISE EXCEPTION
            'O repasse exige um pagamento confirmado';
    END IF;

    RETURN NEW;

END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_validate_payout_payment_status
BEFORE INSERT OR UPDATE OF settlement_status ON payout
FOR EACH ROW
EXECUTE FUNCTION validate_payout_payment_status();

-- Define as transições permitidas de repasse
CREATE TABLE payout_status_transition (
    old_status settlement_status_enum NOT NULL,
    new_status settlement_status_enum NOT NULL,

    PRIMARY KEY (old_status, new_status),

    CONSTRAINT chk_payout_status_transition
        CHECK (old_status <> new_status)
);

INSERT INTO payout_status_transition (old_status, new_status)
VALUES
    ('pending', 'processing'),
    ('pending', 'failed'),
    ('processing', 'completed'),
    ('processing', 'failed');


-- Valida as transições de status do repasse
CREATE OR REPLACE FUNCTION validate_payout_status_transition()
RETURNS TRIGGER AS $$
BEGIN

    IF TG_OP = 'INSERT' THEN

        IF NEW.settlement_status IS DISTINCT FROM 'pending' THEN
            RAISE EXCEPTION
                'O status inicial do repasse deve ser pending';
        END IF;

        RETURN NEW;

    END IF;

    IF NEW.settlement_status IS DISTINCT FROM OLD.settlement_status THEN

        IF NOT EXISTS (
            SELECT 1
            FROM payout_status_transition
            WHERE old_status = OLD.settlement_status
              AND new_status = NEW.settlement_status
        ) THEN
            RAISE EXCEPTION
                'Transição de status de repasse inválida: % -> %',
                OLD.settlement_status,
                NEW.settlement_status;
        END IF;

    END IF;

    RETURN NEW;

END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_validate_payout_status_transition
BEFORE INSERT OR UPDATE OF settlement_status ON payout
FOR EACH ROW
EXECUTE FUNCTION validate_payout_status_transition();

-- Controla a data de conclusão do repasse
CREATE OR REPLACE FUNCTION manage_payout_paid_at()
RETURNS TRIGGER AS $$
BEGIN

    IF TG_OP = 'INSERT' THEN
        NEW.paid_at := NULL;

    ELSIF OLD.paid_at IS NOT NULL THEN
        NEW.paid_at := OLD.paid_at;

    ELSIF NEW.settlement_status = 'completed' THEN
        NEW.paid_at := NOW();

    ELSE
        NEW.paid_at := NULL;

    END IF;

    RETURN NEW;

END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_manage_payout_paid_at
BEFORE INSERT OR UPDATE ON payout
FOR EACH ROW
EXECUTE FUNCTION manage_payout_paid_at();

-- Protege os dados originais do repasse
CREATE OR REPLACE FUNCTION protect_payout_data()
RETURNS TRIGGER AS $$
BEGIN

    IF TG_OP = 'DELETE' THEN
        RAISE EXCEPTION
            'Não é permitido excluir registros de repasse';
    END IF;

    IF NEW.id_payout IS DISTINCT FROM OLD.id_payout
       OR NEW.id_order IS DISTINCT FROM OLD.id_order
       OR NEW.id_payment IS DISTINCT FROM OLD.id_payment
       OR NEW.id_seller IS DISTINCT FROM OLD.id_seller
       OR NEW.payout_amount IS DISTINCT FROM OLD.payout_amount
       OR NEW.created_at IS DISTINCT FROM OLD.created_at
    THEN
        RAISE EXCEPTION
            'Não é permitido alterar os dados originais do repasse';
    END IF;
    -- Protege a identificação do provedor financeiro
    IF OLD.payout_provider IS NOT NULL
       AND NEW.payout_provider IS DISTINCT FROM OLD.payout_provider
    THEN
        RAISE EXCEPTION
            'Não é permitido alterar o provedor do repasse';
    END IF;

    -- Protege o identificador externo da transferência
    IF OLD.provider_payout_id IS NOT NULL
       AND NEW.provider_payout_id IS DISTINCT FROM OLD.provider_payout_id
    THEN
        RAISE EXCEPTION
            'Não é permitido alterar o identificador externo do repasse';
    END IF;
    RETURN NEW;

END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_protect_payout_data
BEFORE UPDATE OR DELETE ON payout
FOR EACH ROW
EXECUTE FUNCTION protect_payout_data();