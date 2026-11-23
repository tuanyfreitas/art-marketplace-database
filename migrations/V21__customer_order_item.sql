CREATE TABLE customer_order_item (
    id_item BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

    id_order BIGINT NOT NULL,
    id_artwork UUID NOT NULL,
    id_seller UUID NOT NULL,

    quantity INT NOT NULL CHECK (quantity > 0),

    unit_price_snapshot NUMERIC(10,2) NOT NULL CHECK (unit_price_snapshot >= 0),

    discount_amount NUMERIC(10,2) NOT NULL DEFAULT 0
    CHECK (
    discount_amount >= 0
    AND discount_amount <= quantity * unit_price_snapshot
),

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    artwork_title_snapshot VARCHAR(255) NOT NULL
    CHECK (LENGTH(TRIM(artwork_title_snapshot)) > 0),

    artwork_slug_snapshot VARCHAR(255) NOT NULL
    CHECK (artwork_slug_snapshot ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),

    seller_name_snapshot VARCHAR(255) NOT NULL
    CHECK (LENGTH(TRIM(seller_name_snapshot)) > 0),

    CONSTRAINT fk_orderitem_order
    FOREIGN KEY (id_order)
    REFERENCES customer_order(id_order)
    ON DELETE RESTRICT,

    CONSTRAINT fk_orderitem_artwork
        FOREIGN KEY (id_artwork)
        REFERENCES artwork(id_artwork)
        ON DELETE RESTRICT,

    CONSTRAINT fk_orderitem_seller
        FOREIGN KEY (id_seller)
        REFERENCES user_account(id_user)
        ON DELETE RESTRICT,

    CONSTRAINT uq_order_artwork
        UNIQUE (id_order, id_artwork)
);

CREATE INDEX idx_order_item_artwork
ON customer_order_item(id_artwork);

CREATE INDEX idx_order_item_seller_order
ON customer_order_item(id_seller, id_order);

-- Preenche automaticamente os dados da obra e do vendedor
-- no momento da criação do item do pedido.
CREATE OR REPLACE FUNCTION fill_order_item_snapshot()
RETURNS TRIGGER AS $$
BEGIN

    SELECT
        aw.id_user,
        aw.price,
        aw.title,
        aw.slug,
        ar.artist_name
    INTO
        NEW.id_seller,
        NEW.unit_price_snapshot,
        NEW.artwork_title_snapshot,
        NEW.artwork_slug_snapshot,
        NEW.seller_name_snapshot
    FROM artwork aw
    INNER JOIN artist ar
        ON ar.id_user = aw.id_user
    WHERE aw.id_artwork = NEW.id_artwork;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'Obra não encontrada ou sem artista cadastrado: %',
            NEW.id_artwork;
    END IF;

    RETURN NEW;

END;
$$ LANGUAGE plpgsql;


CREATE TRIGGER trg_fill_order_item_snapshot
BEFORE INSERT ON customer_order_item
FOR EACH ROW
EXECUTE FUNCTION fill_order_item_snapshot();

-- Protege os dados originais do item do pedido
CREATE OR REPLACE FUNCTION protect_order_item_snapshot()
RETURNS TRIGGER AS $$
BEGIN

    IF NEW.id_item IS DISTINCT FROM OLD.id_item
       OR NEW.id_order IS DISTINCT FROM OLD.id_order
       OR NEW.id_artwork IS DISTINCT FROM OLD.id_artwork
       OR NEW.id_seller IS DISTINCT FROM OLD.id_seller
       OR NEW.unit_price_snapshot IS DISTINCT FROM OLD.unit_price_snapshot
       OR NEW.artwork_title_snapshot IS DISTINCT FROM OLD.artwork_title_snapshot
       OR NEW.artwork_slug_snapshot IS DISTINCT FROM OLD.artwork_slug_snapshot
       OR NEW.seller_name_snapshot IS DISTINCT FROM OLD.seller_name_snapshot
       OR NEW.created_at IS DISTINCT FROM OLD.created_at
       
    THEN
        RAISE EXCEPTION
            'Não é permitido alterar os dados originais do item do pedido';
    END IF;

    RETURN NEW;

END;
$$ LANGUAGE plpgsql;


CREATE TRIGGER trg_protect_order_item_snapshot
BEFORE UPDATE ON customer_order_item
FOR EACH ROW
EXECUTE FUNCTION protect_order_item_snapshot();

-- Controla alterações nos itens conforme o status do pedido
CREATE OR REPLACE FUNCTION validate_order_item_operation()
RETURNS TRIGGER AS $$
DECLARE
    v_id_order BIGINT;
    v_order_status order_status_enum;
BEGIN

        
    IF TG_OP = 'DELETE' THEN
        v_id_order := OLD.id_order;
    ELSE
        v_id_order := NEW.id_order;
    END IF;

    SELECT order_status
    INTO v_order_status
    FROM customer_order
    WHERE id_order = v_id_order
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Pedido não encontrado: %', v_id_order;
    END IF;

    IF v_order_status <> 'created' THEN
        RAISE EXCEPTION
            'Não é permitido modificar itens de um pedido com status %',
            v_order_status;
    END IF;

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;

    RETURN NEW;

END;
$$ LANGUAGE plpgsql;


CREATE TRIGGER trg_validate_order_item_operation
BEFORE INSERT OR UPDATE OR DELETE ON customer_order_item
FOR EACH ROW
EXECUTE FUNCTION validate_order_item_operation();

-- Atualiza automaticamente os valores do pedido
-- quando seus itens são inseridos, alterados ou excluídos
CREATE OR REPLACE FUNCTION update_order_amounts()
RETURNS TRIGGER AS $$
DECLARE
    v_id_order BIGINT;
    v_amount_difference NUMERIC;
BEGIN

    IF TG_OP = 'INSERT' THEN

        v_id_order := NEW.id_order;
        v_amount_difference :=
            NEW.quantity * NEW.unit_price_snapshot;

    ELSIF TG_OP = 'UPDATE' THEN

        v_id_order := NEW.id_order;
        v_amount_difference :=
            (NEW.quantity * NEW.unit_price_snapshot)
            - (OLD.quantity * OLD.unit_price_snapshot);

    ELSIF TG_OP = 'DELETE' THEN

        v_id_order := OLD.id_order;
        v_amount_difference :=
            -(OLD.quantity * OLD.unit_price_snapshot);

    END IF;

    UPDATE customer_order
    SET
        subtotal_amount = subtotal_amount + v_amount_difference,
        total_amount = subtotal_amount + v_amount_difference
                       + freight_amount - discount_amount
    WHERE id_order = v_id_order;

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;

    RETURN NEW;

END;
$$ LANGUAGE plpgsql;


CREATE TRIGGER trg_update_order_amounts
AFTER INSERT OR UPDATE OF quantity, unit_price_snapshot OR DELETE
ON customer_order_item
FOR EACH ROW
EXECUTE FUNCTION update_order_amounts();

-- Distribui o desconto do pedido proporcionalmente entre os itens
CREATE OR REPLACE FUNCTION distribute_order_discount(p_id_order BIGINT)
RETURNS VOID AS $$
DECLARE
    v_subtotal NUMERIC(10,2);
    v_discount NUMERIC(10,2);
    v_item_discount NUMERIC(10,2);
    v_item RECORD;
    v_distributed_gross NUMERIC(14,2) := 0;
    v_actual_subtotal NUMERIC(14,2);
    v_total_distributed NUMERIC(14,2);
BEGIN
    SELECT subtotal_amount, discount_amount
    INTO v_subtotal, v_discount
    FROM customer_order
    WHERE id_order = p_id_order;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Pedido não encontrado: %', p_id_order;
    END IF;

    SELECT COALESCE(SUM(quantity * unit_price_snapshot), 0)
    INTO v_actual_subtotal
    FROM customer_order_item
    WHERE id_order = p_id_order;

    IF v_actual_subtotal IS DISTINCT FROM v_subtotal THEN
    RAISE EXCEPTION
        'Subtotal inconsistente no pedido %: registrado %, calculado %',
        p_id_order,
        v_subtotal,
        v_actual_subtotal;
    END IF;

    IF v_subtotal = 0 AND v_discount > 0 THEN
        RAISE EXCEPTION 'Não é possível distribuir desconto em pedido sem subtotal';
    END IF;

    IF v_discount > v_subtotal THEN
    RAISE EXCEPTION
        'Desconto (%) não pode superar o subtotal (%) do pedido %',
        v_discount,
        v_subtotal,
        p_id_order;
    END IF;

    FOR v_item IN
        SELECT
        id_item,
        quantity * unit_price_snapshot AS gross_amount
        FROM customer_order_item
        WHERE id_order = p_id_order
        ORDER BY id_item
    LOOP
        IF v_subtotal = 0 THEN
    v_item_discount := 0;
ELSE
    v_item_discount :=
        ROUND(
            v_discount * (v_distributed_gross + v_item.gross_amount)
            / v_subtotal,
            2
        )
        -
        ROUND(
            v_discount * v_distributed_gross
            / v_subtotal,
            2
        );
END IF;

v_distributed_gross :=
    v_distributed_gross + v_item.gross_amount;

        UPDATE customer_order_item
        SET discount_amount = v_item_discount
        WHERE id_item = v_item.id_item
        AND discount_amount IS DISTINCT FROM v_item_discount; 

    END LOOP;

    SELECT COALESCE(SUM(discount_amount), 0)
INTO v_total_distributed
FROM customer_order_item
WHERE id_order = p_id_order;

IF v_total_distributed IS DISTINCT FROM v_discount THEN
    RAISE EXCEPTION
        'Desconto inconsistente no pedido %: esperado %, distribuído %',
        p_id_order,
        v_discount,
        v_total_distributed;
END IF;
END;
$$ LANGUAGE plpgsql;

-- Distribui os descontos antes de finalizar o pedido
CREATE OR REPLACE FUNCTION apply_order_discount_before_payment()
RETURNS TRIGGER AS $$
BEGIN
    IF OLD.order_status = 'created'
   AND NEW.order_status = 'awaiting_payment' THEN

    IF NEW.discount_amount IS DISTINCT FROM OLD.discount_amount
       OR NEW.subtotal_amount IS DISTINCT FROM OLD.subtotal_amount THEN
        RAISE EXCEPTION
            'Atualize os valores do pedido antes de alterar seu status para awaiting_payment';
    END IF;
    IF NEW.payment_method IS NULL
       OR LENGTH(TRIM(NEW.payment_method)) = 0 THEN

        RAISE EXCEPTION
            'É necessário definir o método de pagamento antes de finalizar o pedido %',
            NEW.id_order;

    END IF;

    PERFORM distribute_order_discount(NEW.id_order);

    END IF;

    RETURN NEW;

END;
$$ LANGUAGE plpgsql;


CREATE TRIGGER trg_validate_z_apply_order_discount_before_payment
BEFORE UPDATE OF order_status ON customer_order
FOR EACH ROW
EXECUTE FUNCTION apply_order_discount_before_payment();

-- Valida a consistência entre o subtotal e os itens do pedido
CREATE OR REPLACE FUNCTION validate_order_subtotal()
RETURNS TRIGGER AS $$
DECLARE
    v_subtotal NUMERIC;
    v_expected_subtotal NUMERIC;
BEGIN

    SELECT subtotal_amount
    INTO v_subtotal
    FROM customer_order
    WHERE id_order = NEW.id_order;

    IF NOT FOUND THEN
        RETURN NULL;
    END IF;

    SELECT COALESCE(SUM(quantity * unit_price_snapshot), 0)
    INTO v_expected_subtotal
    FROM customer_order_item
    WHERE id_order = NEW.id_order;

    IF v_subtotal IS DISTINCT FROM v_expected_subtotal THEN
        RAISE EXCEPTION
            'Subtotal inconsistente no pedido %: esperado %, encontrado %',
            NEW.id_order,
            v_expected_subtotal,
            v_subtotal;
    END IF;

    RETURN NULL;

END;
$$ LANGUAGE plpgsql;


CREATE CONSTRAINT TRIGGER trg_validate_order_subtotal
AFTER INSERT OR UPDATE ON customer_order
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW
EXECUTE FUNCTION validate_order_subtotal();


-- Valida a existência de itens antes de avançar o pedido
CREATE OR REPLACE FUNCTION validate_order_has_items()
RETURNS TRIGGER AS $$
BEGIN

    IF NEW.order_status IN (
        'awaiting_payment',
        'confirmed',
        'processing',
        'completed'
    ) THEN

        IF NOT EXISTS (
            SELECT 1
            FROM customer_order_item
            WHERE id_order = NEW.id_order
        ) THEN
            RAISE EXCEPTION
                'Não é permitido avançar um pedido sem itens';
        END IF;

    END IF;

    RETURN NEW;

END;
$$ LANGUAGE plpgsql;


CREATE TRIGGER trg_validate_order_has_items
BEFORE INSERT OR UPDATE OF order_status ON customer_order
FOR EACH ROW
EXECUTE FUNCTION validate_order_has_items();