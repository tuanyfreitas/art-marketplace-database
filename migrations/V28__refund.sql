CREATE TABLE refund (
    id_refund BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

    id_payment BIGINT NOT NULL,

    refund_amount NUMERIC(10,2) NOT NULL CHECK (refund_amount > 0),

    freight_refund_amount NUMERIC(10,2) NOT NULL DEFAULT 0
    CHECK (freight_refund_amount >= 0),

    refund_status refund_status_enum NOT NULL DEFAULT 'pending',
    
    reason TEXT NOT NULL
    CHECK (LENGTH(TRIM(reason)) > 0),

    provider_refund_id VARCHAR(255)
    CHECK (
        LENGTH(TRIM(provider_refund_id)) > 0
        AND provider_refund_id = TRIM(provider_refund_id)
    ),

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    processed_at TIMESTAMPTZ,

    CONSTRAINT chk_refund_processed_at
    CHECK (
        processed_at IS NULL
        OR processed_at >= created_at
    ),
    

    CONSTRAINT fk_refund_payment
    FOREIGN KEY (id_payment)
    REFERENCES payment(id_payment)
    ON DELETE RESTRICT,

    CONSTRAINT chk_refund_freight_amount
    CHECK (freight_refund_amount <= refund_amount)
);

CREATE INDEX idx_refund_payment ON refund(id_payment);
CREATE INDEX idx_refund_created_at ON refund(created_at);
CREATE UNIQUE INDEX uq_refund_provider_id
ON refund(id_payment, provider_refund_id)
WHERE provider_refund_id IS NOT NULL;

-- Define as transições permitidas de estorno
CREATE TABLE refund_status_transition (
    old_status refund_status_enum NOT NULL,
    new_status refund_status_enum NOT NULL,

    PRIMARY KEY (old_status, new_status),

    CONSTRAINT chk_refund_status_transition
        CHECK (old_status <> new_status)
);

INSERT INTO refund_status_transition (old_status, new_status)
VALUES
    ('pending', 'processing'),
    ('pending', 'approved'),
    ('pending', 'failed'),
    ('pending', 'canceled'),
    ('processing', 'approved'),
    ('processing', 'failed'),
    ('processing', 'canceled');


-- Valida as transições de status do estorno
CREATE OR REPLACE FUNCTION validate_refund_status_transition()
RETURNS TRIGGER AS $$
BEGIN

    IF TG_OP = 'INSERT' THEN

        IF NEW.refund_status IS DISTINCT FROM 'pending' THEN
            RAISE EXCEPTION
                'O status inicial do estorno deve ser pending';
        END IF;

        RETURN NEW;

    END IF;

    IF NEW.refund_status IS DISTINCT FROM OLD.refund_status THEN

        IF NOT EXISTS (
            SELECT 1
            FROM refund_status_transition
            WHERE old_status = OLD.refund_status
              AND new_status = NEW.refund_status
        ) THEN
            RAISE EXCEPTION
                'Transição de status de estorno inválida: % -> %',
                OLD.refund_status,
                NEW.refund_status;
        END IF;

    END IF;

    RETURN NEW;

END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_validate_refund_status_transition
BEFORE INSERT OR UPDATE OF refund_status ON refund
FOR EACH ROW
EXECUTE FUNCTION validate_refund_status_transition();

-- Atualiza automaticamente a data de modificação
CREATE TRIGGER trg_refund_updated_at
BEFORE UPDATE ON refund
FOR EACH ROW
EXECUTE FUNCTION update_updated_at();


-- Controla a data de conclusão do estorno
CREATE OR REPLACE FUNCTION manage_refund_processed_at()
RETURNS TRIGGER AS $$
BEGIN

    IF TG_OP = 'INSERT' THEN
        NEW.processed_at := NULL;

    ELSIF OLD.processed_at IS NOT NULL THEN
        NEW.processed_at := OLD.processed_at;

    ELSIF NEW.refund_status IN ('approved', 'failed', 'canceled') THEN
        NEW.processed_at := NOW();

    ELSE
        NEW.processed_at := NULL;

    END IF;

    RETURN NEW;

END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_manage_refund_processed_at
BEFORE INSERT OR UPDATE ON refund
FOR EACH ROW
EXECUTE FUNCTION manage_refund_processed_at();

-- Valida o limite financeiro dos estornos
-- Valida o limite financeiro dos estornos
CREATE OR REPLACE FUNCTION validate_refund_amount()
RETURNS TRIGGER AS $$
DECLARE
    v_payment_amount NUMERIC(10,2);
    v_payment_status payment_status_enum;
    v_total_refunded NUMERIC;
BEGIN

    -- Permite atualizar metadados sem revalidar o valor
    IF TG_OP = 'UPDATE' THEN

        IF NEW.refund_status IS NOT DISTINCT FROM OLD.refund_status
           AND NEW.refund_amount IS NOT DISTINCT FROM OLD.refund_amount
           AND NEW.id_payment IS NOT DISTINCT FROM OLD.id_payment
        THEN
            RETURN NEW;
        END IF;

    END IF;

    SELECT amount, payment_status
    INTO v_payment_amount, v_payment_status
    FROM payment
    WHERE id_payment = NEW.id_payment
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Pagamento não encontrado';
    END IF;

    IF NEW.refund_status IN ('pending', 'processing', 'approved') THEN

        IF v_payment_status IS DISTINCT FROM 'paid' THEN
            RAISE EXCEPTION
                'O pagamento deve estar confirmado para realizar o estorno';
        END IF;

        SELECT COALESCE(SUM(refund_amount), 0)
        INTO v_total_refunded
        FROM refund
        WHERE id_payment = NEW.id_payment
          AND refund_status IN ('pending', 'processing', 'approved')
          AND id_refund IS DISTINCT FROM NEW.id_refund;

        IF v_total_refunded + NEW.refund_amount > v_payment_amount THEN
            RAISE EXCEPTION
                'O valor acumulado dos estornos excede o valor do pagamento';
        END IF;

    END IF;

    RETURN NEW;

END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_validate_refund_amount
BEFORE INSERT OR UPDATE ON refund
FOR EACH ROW
EXECUTE FUNCTION validate_refund_amount();

-- Protege os registros financeiros de estorno
CREATE OR REPLACE FUNCTION protect_refund_data()
RETURNS TRIGGER AS $$
BEGIN

    IF TG_OP = 'DELETE' THEN
        RAISE EXCEPTION
            'Não é permitido excluir registros de estorno';
    END IF;

    IF NEW.id_refund IS DISTINCT FROM OLD.id_refund
       OR NEW.id_payment IS DISTINCT FROM OLD.id_payment
       OR NEW.refund_amount IS DISTINCT FROM OLD.refund_amount
       OR NEW.freight_refund_amount IS DISTINCT FROM OLD.freight_refund_amount
       OR NEW.reason IS DISTINCT FROM OLD.reason
       OR NEW.created_at IS DISTINCT FROM OLD.created_at
    THEN
        RAISE EXCEPTION
            'Não é permitido alterar os dados originais do estorno';
    END IF;

    IF OLD.provider_refund_id IS NOT NULL
       AND NEW.provider_refund_id IS DISTINCT FROM OLD.provider_refund_id
    THEN
        RAISE EXCEPTION
            'Não é permitido alterar o identificador externo do estorno';
    END IF;

    RETURN NEW;

END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_protect_refund_data
BEFORE UPDATE OR DELETE ON refund
FOR EACH ROW
EXECUTE FUNCTION protect_refund_data();

-- Sincroniza o pagamento após estorno integral
CREATE OR REPLACE FUNCTION sync_payment_refund_status()
RETURNS TRIGGER AS $$
DECLARE
    v_payment_amount NUMERIC(10,2);
    v_total_refunded NUMERIC;
BEGIN

    SELECT amount
    INTO v_payment_amount
    FROM payment
    WHERE id_payment = NEW.id_payment
    FOR UPDATE;

    SELECT COALESCE(SUM(refund_amount), 0)
    INTO v_total_refunded
    FROM refund
    WHERE id_payment = NEW.id_payment
      AND refund_status = 'approved';

    IF v_total_refunded = v_payment_amount THEN

        UPDATE payment
        SET payment_status = 'refunded'
        WHERE id_payment = NEW.id_payment
          AND payment_status = 'paid';

    END IF;

    RETURN NEW;

END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_sync_payment_refund_status
AFTER UPDATE OF refund_status ON refund
FOR EACH ROW
WHEN (
    NEW.refund_status = 'approved'
    AND OLD.refund_status IS DISTINCT FROM NEW.refund_status
)
EXECUTE FUNCTION sync_payment_refund_status();

-- Valida o estorno integral do pagamento
-- Valida o estorno integral do pagamento
CREATE OR REPLACE FUNCTION validate_payment_refunded()
RETURNS TRIGGER AS $$
DECLARE
    v_total_refunded NUMERIC;
BEGIN

    SELECT SUM(refund_amount)
    INTO v_total_refunded
    FROM refund
    WHERE id_payment = NEW.id_payment
      AND refund_status = 'approved';

    IF v_total_refunded IS DISTINCT FROM NEW.amount THEN
        RAISE EXCEPTION
            'O pagamento somente pode ser marcado como refunded após o estorno integral';
    END IF;

    RETURN NEW;

END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_validate_payment_refunded
BEFORE UPDATE OF payment_status ON payment
FOR EACH ROW
WHEN (
    NEW.payment_status = 'refunded'
    AND OLD.payment_status IS DISTINCT FROM NEW.payment_status
)
EXECUTE FUNCTION validate_payment_refunded();


-- Detalha os itens vinculados ao estorno
CREATE TABLE refund_item (
    id_refund_item BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

    id_refund BIGINT NOT NULL,
    id_item BIGINT NOT NULL,

    quantity INT NOT NULL
    CHECK (quantity > 0),

    refund_amount NUMERIC(10,2) NOT NULL
    CHECK (refund_amount > 0),

    seller_refund_amount NUMERIC(10,2) NOT NULL
    CHECK (seller_refund_amount >= 0),

    marketplace_refund_amount NUMERIC(10,2) NOT NULL
    CHECK (marketplace_refund_amount >= 0),

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT fk_refund_item_refund
        FOREIGN KEY (id_refund)
        REFERENCES refund(id_refund)
        ON DELETE RESTRICT,

    CONSTRAINT fk_refund_item_order_item
        FOREIGN KEY (id_item)
        REFERENCES customer_order_item(id_item)
        ON DELETE RESTRICT,

    CONSTRAINT uq_refund_item
    UNIQUE (id_refund, id_item),

    CONSTRAINT chk_refund_item_distribution
    CHECK (
        seller_refund_amount + marketplace_refund_amount
        = refund_amount
    )
);

CREATE INDEX idx_refund_item_order_item
ON refund_item(id_item);

-- Valida o vínculo entre o item estornado e o pedido
CREATE OR REPLACE FUNCTION validate_refund_item_order()
RETURNS TRIGGER AS $$
BEGIN

    IF NOT EXISTS (
        SELECT 1
        FROM refund r
        JOIN payment p
            ON p.id_payment = r.id_payment
        JOIN customer_order_item oi
            ON oi.id_order = p.id_order
        WHERE r.id_refund = NEW.id_refund
          AND oi.id_item = NEW.id_item
    ) THEN

        RAISE EXCEPTION
            'O item informado não pertence ao pedido associado ao estorno';

    END IF;

    RETURN NEW;

END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_validate_refund_item_order
BEFORE INSERT OR UPDATE OF id_refund, id_item ON refund_item
FOR EACH ROW
EXECUTE FUNCTION validate_refund_item_order();

-- Valida a quantidade acumulada de itens estornados
CREATE OR REPLACE FUNCTION validate_refund_item_quantity()
RETURNS TRIGGER AS $$
DECLARE
    v_purchased_quantity INT;
    v_refunded_quantity BIGINT;
BEGIN

    -- Bloqueia o item durante a validação
    SELECT quantity
    INTO v_purchased_quantity
    FROM customer_order_item
    WHERE id_item = NEW.id_item
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Item do pedido não encontrado';
    END IF;

    SELECT COALESCE(SUM(ri.quantity), 0)
    INTO v_refunded_quantity
    FROM refund_item ri
    JOIN refund r
        ON r.id_refund = ri.id_refund
    WHERE ri.id_item = NEW.id_item
      AND r.refund_status IN (
          'pending', 'processing', 'approved'
      )
      AND ri.id_refund_item IS DISTINCT FROM NEW.id_refund_item;

    IF v_refunded_quantity + NEW.quantity > v_purchased_quantity THEN

        RAISE EXCEPTION
            'A quantidade acumulada de itens estornados excede a quantidade comprada';

    END IF;

    RETURN NEW;

END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_validate_refund_item_quantity
BEFORE INSERT OR UPDATE ON refund_item
FOR EACH ROW
EXECUTE FUNCTION validate_refund_item_quantity();

-- Protege os itens vinculados ao estorno
CREATE OR REPLACE FUNCTION protect_refund_item_data()
RETURNS TRIGGER AS $$
DECLARE
    v_refund_status refund_status_enum;
BEGIN

    IF TG_OP IN ('UPDATE', 'DELETE') THEN
        RAISE EXCEPTION
            'Não é permitido alterar ou excluir itens do estorno';
    END IF;

    SELECT refund_status
    INTO v_refund_status
    FROM refund
    WHERE id_refund = NEW.id_refund
    FOR UPDATE;

    IF v_refund_status IS DISTINCT FROM 'pending' THEN
        RAISE EXCEPTION
            'Somente estornos pendentes podem receber novos itens';
    END IF;

    RETURN NEW;

END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_protect_refund_item_data
BEFORE INSERT OR UPDATE OR DELETE ON refund_item
FOR EACH ROW
EXECUTE FUNCTION protect_refund_item_data();

-- Valida o valor líquido dos itens estornados
CREATE OR REPLACE FUNCTION validate_refund_item_amount()
RETURNS TRIGGER AS $$
DECLARE
    v_purchased_quantity INT;
    v_total_item_net NUMERIC;
    v_max_for_quantity NUMERIC;
    v_previous_refunds NUMERIC;
BEGIN

    SELECT
        quantity,
        quantity * unit_price_snapshot - discount_amount
    INTO
        v_purchased_quantity,
        v_total_item_net
    FROM customer_order_item
    WHERE id_item = NEW.id_item
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'Item do pedido não encontrado';
    END IF;

    -- Calcula o limite proporcional à quantidade devolvida
    v_max_for_quantity := ROUND(
        v_total_item_net * NEW.quantity / v_purchased_quantity,
        2
    );

    IF NEW.refund_amount > v_max_for_quantity THEN
        RAISE EXCEPTION
            'O valor do estorno excede o valor líquido dos itens devolvidos';
    END IF;

    -- Soma os reembolsos anteriores do mesmo item
    SELECT COALESCE(SUM(ri.refund_amount), 0)
    INTO v_previous_refunds
    FROM refund_item ri
    JOIN refund r
        ON r.id_refund = ri.id_refund
    WHERE ri.id_item = NEW.id_item
      AND r.refund_status IN (
          'pending', 'processing', 'approved'
      );

    IF v_previous_refunds + NEW.refund_amount > v_total_item_net THEN
        RAISE EXCEPTION
            'O total reembolsado não pode superar o valor líquido original do item';
    END IF;

    RETURN NEW;

END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_validate_refund_item_amount
BEFORE INSERT ON refund_item
FOR EACH ROW
EXECUTE FUNCTION validate_refund_item_amount();

-- Valida o valor acumulado dos itens do estorno
CREATE OR REPLACE FUNCTION validate_refund_item_total()
RETURNS TRIGGER AS $$
DECLARE
    v_refund_amount NUMERIC(10,2);
    v_freight_refund_amount NUMERIC(10,2);
    v_total_items NUMERIC;
BEGIN

    SELECT refund_amount, freight_refund_amount
    INTO v_refund_amount, v_freight_refund_amount
    FROM refund
    WHERE id_refund = NEW.id_refund
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Estorno não encontrado';
    END IF;

    SELECT COALESCE(SUM(refund_amount), 0)
    INTO v_total_items
    FROM refund_item
    WHERE id_refund = NEW.id_refund;

    IF v_total_items + NEW.refund_amount
    > v_refund_amount - v_freight_refund_amount THEN
        RAISE EXCEPTION
            'O valor acumulado dos itens excede o valor total do estorno';
    END IF;

    RETURN NEW;

END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_validate_refund_item_total
BEFORE INSERT ON refund_item
FOR EACH ROW
EXECUTE FUNCTION validate_refund_item_total();

-- Valida o limite acumulado do frete estornado
CREATE OR REPLACE FUNCTION validate_refund_freight()
RETURNS TRIGGER AS $$
DECLARE
    v_freight_amount NUMERIC(10,2);
    v_total_freight_refunded NUMERIC;
BEGIN

    -- Bloqueia o pagamento para evitar estornos simultâneos
    SELECT o.freight_amount
    INTO v_freight_amount
    FROM payment p
    JOIN customer_order o
        ON o.id_order = p.id_order
    WHERE p.id_payment = NEW.id_payment
    FOR UPDATE OF p;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Pagamento ou pedido não encontrado';
    END IF;

    IF NEW.refund_status IN ('pending', 'processing', 'approved') THEN

        SELECT COALESCE(SUM(freight_refund_amount), 0)
        INTO v_total_freight_refunded
        FROM refund
        WHERE id_payment = NEW.id_payment
          AND refund_status IN ('pending', 'processing', 'approved')
          AND id_refund IS DISTINCT FROM NEW.id_refund;

        IF v_total_freight_refunded + NEW.freight_refund_amount
           > v_freight_amount THEN

            RAISE EXCEPTION
                'O valor acumulado do frete estornado excede o frete original do pedido';

        END IF;

    END IF;

    RETURN NEW;

END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_validate_refund_freight
BEFORE INSERT OR UPDATE OF refund_status ON refund
FOR EACH ROW
EXECUTE FUNCTION validate_refund_freight();

-- Valida a composição financeira antes de processar o estorno
CREATE OR REPLACE FUNCTION validate_refund_composition()
RETURNS TRIGGER AS $$
DECLARE
    v_items_total NUMERIC(10,2);
BEGIN

    -- Valida quando o estorno sai do status pendente
    IF OLD.refund_status = 'pending'
       AND NEW.refund_status <> 'pending' THEN

        -- Estornos cancelados ou com falha não precisam
        -- ter sua composição financeira concluída
        IF NEW.refund_status IN ('failed', 'canceled') THEN
            RETURN NEW;
        END IF;

        SELECT COALESCE(SUM(refund_amount), 0)
        INTO v_items_total
        FROM refund_item
        WHERE id_refund = NEW.id_refund;

        IF v_items_total + NEW.freight_refund_amount
           <> NEW.refund_amount THEN

            RAISE EXCEPTION
                'A soma dos itens e do frete deve corresponder ao valor total do estorno';

        END IF;

    END IF;

    RETURN NEW;

END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_validate_refund_composition
BEFORE UPDATE OF refund_status ON refund
FOR EACH ROW
EXECUTE FUNCTION validate_refund_composition();

-- Valida a parcela do artista no estorno
CREATE OR REPLACE FUNCTION validate_refund_seller_amount()
RETURNS TRIGGER AS $$
DECLARE
    v_seller UUID;
    v_original_split NUMERIC(10,2);
    v_seller_net NUMERIC;
    v_previous_seller_refunds NUMERIC;
    v_previous_item_refunds NUMERIC;
    v_expected_seller_amount NUMERIC;
BEGIN

    SELECT id_seller
    INTO v_seller
    FROM customer_order_item
    WHERE id_item = NEW.id_item;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Item do pedido não encontrado';
    END IF;

    -- Consulta o repasse original do artista
    SELECT ps.amount
    INTO v_original_split
    FROM refund r
    JOIN payment_split ps
        ON ps.id_payment = r.id_payment
       AND ps.receiver_id = v_seller
       AND ps.split_role = 'artist'
    WHERE r.id_refund = NEW.id_refund
    FOR UPDATE OF ps;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'Repasse original do artista não encontrado';
    END IF;

    -- Calcula o valor líquido original das obras do artista
    SELECT COALESCE(
        SUM(
            oi.quantity * oi.unit_price_snapshot
            - oi.discount_amount
        ), 0
    )
    INTO v_seller_net
    FROM refund r
    JOIN payment p
        ON p.id_payment = r.id_payment
    JOIN customer_order_item oi
        ON oi.id_order = p.id_order
    WHERE r.id_refund = NEW.id_refund
      AND oi.id_seller = v_seller;

    IF v_seller_net <= 0 THEN
        RAISE EXCEPTION
            'O artista não possui valor líquido disponível para estorno';
    END IF;

    -- Consulta os reembolsos anteriores do mesmo artista
    SELECT
        COALESCE(SUM(ri.seller_refund_amount), 0),
        COALESCE(SUM(ri.refund_amount), 0)
    INTO
        v_previous_seller_refunds,
        v_previous_item_refunds
    FROM refund_item ri
    JOIN refund r
        ON r.id_refund = ri.id_refund
    JOIN customer_order_item oi
        ON oi.id_item = ri.id_item
    WHERE r.id_payment = (
        SELECT id_payment
        FROM refund
        WHERE id_refund = NEW.id_refund
    )
      AND oi.id_seller = v_seller
      AND r.refund_status IN (
          'pending', 'processing', 'approved'
      );

    -- Impede ultrapassar o repasse original do artista
    IF v_previous_seller_refunds
       + NEW.seller_refund_amount > v_original_split THEN

        RAISE EXCEPTION
            'O valor acumulado dos estornos excede a parcela original do artista';
    END IF;

    -- Calcula a parcela proporcional, ajustando os centavos
    v_expected_seller_amount :=
        ROUND(
            (v_previous_item_refunds + NEW.refund_amount)
            * v_original_split / v_seller_net,
            2
        )
        -
        ROUND(
            v_previous_item_refunds
            * v_original_split / v_seller_net,
            2
        );

    IF NEW.seller_refund_amount
       IS DISTINCT FROM v_expected_seller_amount
       OR NEW.marketplace_refund_amount
       IS DISTINCT FROM (
           NEW.refund_amount - v_expected_seller_amount
       ) THEN

        RAISE EXCEPTION
            'A divisão do estorno não corresponde à proporção financeira original';
    END IF;

    RETURN NEW;

END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_validate_refund_seller_amount
BEFORE INSERT ON refund_item
FOR EACH ROW
EXECUTE FUNCTION validate_refund_seller_amount();


-- Valida o limite acumulado da comissão estornada
CREATE OR REPLACE FUNCTION validate_refund_marketplace_amount()
RETURNS TRIGGER AS $$
DECLARE
    v_original_fee NUMERIC(10,2);
    v_previous_refunds NUMERIC;
BEGIN

    -- Consulta a comissão original do pedido
    SELECT o.marketplace_fee
    INTO v_original_fee
    FROM refund r
    JOIN payment p ON p.id_payment = r.id_payment
    JOIN customer_order o ON o.id_order = p.id_order
    WHERE r.id_refund = NEW.id_refund;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Pedido do estorno não encontrado';
    END IF;

    -- Soma as comissões já comprometidas em outros estornos
    SELECT COALESCE(SUM(ri.marketplace_refund_amount), 0)
    INTO v_previous_refunds
    FROM refund_item ri
    JOIN refund r ON r.id_refund = ri.id_refund
    WHERE r.id_payment = (
        SELECT id_payment
        FROM refund
        WHERE id_refund = NEW.id_refund
    )
      AND r.refund_status IN ('pending', 'processing', 'approved');

    IF v_previous_refunds + NEW.marketplace_refund_amount
       > v_original_fee THEN

        RAISE EXCEPTION
            'O valor acumulado da comissão estornada excede a comissão original do pedido';

    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_validate_refund_marketplace_amount
BEFORE INSERT ON refund_item
FOR EACH ROW
EXECUTE FUNCTION validate_refund_marketplace_amount();