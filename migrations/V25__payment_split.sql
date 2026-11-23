CREATE TABLE payment_split (
    id_split BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

    id_payment BIGINT NOT NULL,

    receiver_id UUID NOT NULL,

    split_role VARCHAR(30) NOT NULL,

    percentage NUMERIC(5,2),

    amount NUMERIC(10,2) NOT NULL CHECK (amount >= 0),

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT fk_split_payment
        FOREIGN KEY (id_payment)
        REFERENCES payment(id_payment)
        ON DELETE RESTRICT,

    CONSTRAINT fk_split_receiver
        FOREIGN KEY (receiver_id)
        REFERENCES user_account(id_user)
        ON DELETE RESTRICT,

    CONSTRAINT chk_split_role
        CHECK (split_role IN ('artist', 'marketplace', 'freight')),

    CONSTRAINT chk_split_percentage
        CHECK (percentage IS NULL OR percentage BETWEEN 0 AND 100),

    CONSTRAINT uq_payment_split_receiver
        UNIQUE (id_payment, receiver_id, split_role)
);

CREATE INDEX idx_payment_split_receiver
ON payment_split(receiver_id);


-- Configuração financeira do marketplace
CREATE TABLE marketplace_financial_config (
    id_config SMALLINT PRIMARY KEY DEFAULT 1,

    receiver_id UUID NOT NULL,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT chk_marketplace_single_config
        CHECK (id_config = 1),

    CONSTRAINT fk_marketplace_financial_receiver
        FOREIGN KEY (receiver_id)
        REFERENCES user_account(id_user)
        ON DELETE RESTRICT
);

CREATE TRIGGER trg_marketplace_financial_config_updated_at
BEFORE UPDATE ON marketplace_financial_config
FOR EACH ROW
EXECUTE FUNCTION update_updated_at();


-- Validação da divisão financeira
CREATE OR REPLACE FUNCTION validate_payment_split()
RETURNS TRIGGER AS $$
DECLARE
    v_order_id BIGINT;
    v_payment_status payment_status_enum;
    v_payment_amount NUMERIC(10,2);
    v_marketplace_receiver UUID;
    v_total_split NUMERIC;
BEGIN

    SELECT id_order, payment_status, amount
    INTO v_order_id, v_payment_status, v_payment_amount
    FROM payment
    WHERE id_payment = NEW.id_payment
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Pagamento não encontrado';
    END IF;

    IF v_payment_status <> 'paid' THEN
        RAISE EXCEPTION
            'A divisão financeira exige um pagamento efetivado';
    END IF;

    IF NEW.amount > v_payment_amount THEN
        RAISE EXCEPTION
            'O valor da divisão não pode superar o valor do pagamento';
    END IF;

    IF NEW.split_role = 'artist' THEN

        IF NOT EXISTS (
            SELECT 1
            FROM customer_order_item
            WHERE id_order = v_order_id
              AND id_seller = NEW.receiver_id
        ) THEN
            RAISE EXCEPTION
                'O artista não possui obras neste pedido';
        END IF;

    ELSIF NEW.split_role IN ('marketplace', 'freight') THEN

        SELECT receiver_id
        INTO v_marketplace_receiver
        FROM marketplace_financial_config
        WHERE id_config = 1;

        IF NOT FOUND THEN
            RAISE EXCEPTION
                'A conta financeira do marketplace não foi configurada';
        END IF;

        IF NEW.receiver_id IS DISTINCT FROM v_marketplace_receiver THEN
            RAISE EXCEPTION
                'Recebedor financeiro do marketplace inválido';
        END IF;

    END IF;

    -- Valida o valor acumulado da distribuição
    SELECT COALESCE(SUM(amount), 0)
    INTO v_total_split
    FROM payment_split
    WHERE id_payment = NEW.id_payment;

    IF v_total_split + NEW.amount > v_payment_amount THEN
        RAISE EXCEPTION
            'O total da divisão financeira supera o valor do pagamento';
    END IF;
    
    RETURN NEW;

END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_validate_payment_split
BEFORE INSERT ON payment_split
FOR EACH ROW
EXECUTE FUNCTION validate_payment_split();

-- Protege os registros da divisão financeira
CREATE OR REPLACE FUNCTION protect_payment_split()
RETURNS TRIGGER AS $$
BEGIN

    RAISE EXCEPTION
        'Não é permitido alterar ou excluir registros da divisão financeira';

    RETURN NULL;

END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_protect_payment_split
BEFORE UPDATE OR DELETE ON payment_split
FOR EACH ROW
EXECUTE FUNCTION protect_payment_split();

-- Gera automaticamente a divisão financeira do pagamento
CREATE OR REPLACE FUNCTION generate_payment_split()
RETURNS TRIGGER AS $$
DECLARE
    v_order customer_order%ROWTYPE;
    v_marketplace_receiver UUID;
    v_artist RECORD;
    v_net_amount NUMERIC;
    v_artist_amount NUMERIC;
    v_accumulated_item_net NUMERIC := 0;
    v_accumulated_net NUMERIC := 0;
    v_target_net NUMERIC;
    v_total_split NUMERIC;
BEGIN

    SELECT *
    INTO v_order
    FROM customer_order
    WHERE id_order = NEW.id_order;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Pedido não encontrado';
    END IF;

    SELECT receiver_id
    INTO v_marketplace_receiver
    FROM marketplace_financial_config
    WHERE id_config = 1
    FOR SHARE;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'A conta financeira do marketplace não foi configurada';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM payment_split
        WHERE id_payment = NEW.id_payment
    ) THEN
        RAISE EXCEPTION
            'A divisão financeira deste pagamento já existe';
    END IF;

    -- Valor líquido destinado aos artistas
    v_net_amount := v_order.subtotal_amount
                    - v_order.discount_amount
                    - v_order.marketplace_fee;

    -- Distribuição proporcional entre os artistas
    FOR v_artist IN
    SELECT
        id_seller,
        SUM(
            quantity * unit_price_snapshot - discount_amount
        ) AS net_amount
    FROM customer_order_item
    WHERE id_order = NEW.id_order
    GROUP BY id_seller
    ORDER BY id_seller
LOOP

        v_accumulated_item_net :=
        v_accumulated_item_net + v_artist.net_amount;

       IF v_order.subtotal_amount > v_order.discount_amount THEN

        v_target_net := ROUND(
        v_net_amount * v_accumulated_item_net
        / (v_order.subtotal_amount - v_order.discount_amount),
        2
        );

        v_artist_amount :=
        v_target_net - v_accumulated_net;

   ELSE
        v_artist_amount := 0;
END IF;

        v_accumulated_net :=
        v_accumulated_net + v_artist_amount;

        INSERT INTO payment_split (
            id_payment,
            receiver_id,
            split_role,
            amount
        )
        VALUES (
            NEW.id_payment,
            v_artist.id_seller,
            'artist',
            v_artist_amount
        );

    END LOOP;

    -- Comissão do marketplace
    IF v_order.marketplace_fee > 0 THEN

        INSERT INTO payment_split (
            id_payment,
            receiver_id,
            split_role,
            amount
        )
        VALUES (
            NEW.id_payment,
            v_marketplace_receiver,
            'marketplace',
            v_order.marketplace_fee
        );

    END IF;

    -- Valor destinado ao frete
    IF v_order.freight_amount > 0 THEN

        INSERT INTO payment_split (
            id_payment,
            receiver_id,
            split_role,
            amount
        )
        VALUES (
            NEW.id_payment,
            v_marketplace_receiver,
            'freight',
            v_order.freight_amount
        );

    END IF;
-- Confere o total da distribuição financeira
    SELECT COALESCE(SUM(amount), 0)
    INTO v_total_split
    FROM payment_split
    WHERE id_payment = NEW.id_payment;

    IF v_total_split IS DISTINCT FROM NEW.amount THEN
        RAISE EXCEPTION
            'Distribuição financeira inconsistente: esperado %, distribuído %',
            NEW.amount,
            v_total_split;
    END IF;
    
    RETURN NEW;

END;
$$ LANGUAGE plpgsql;


CREATE TRIGGER trg_generate_payment_split
AFTER UPDATE OF payment_status ON payment
FOR EACH ROW
WHEN (
    NEW.payment_status = 'paid'
    AND OLD.payment_status IS DISTINCT FROM NEW.payment_status
)
EXECUTE FUNCTION generate_payment_split();