CREATE TABLE customer_order (
    id_order BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

    order_number VARCHAR(20) NOT NULL UNIQUE
    CHECK (
        LENGTH(TRIM(order_number)) > 0
        AND order_number = TRIM(order_number)
    ),

    id_buyer UUID NOT NULL,
    id_address UUID,

    subtotal_amount NUMERIC(10,2) NOT NULL DEFAULT 0 CHECK (subtotal_amount >= 0),
    freight_amount NUMERIC(10,2) NOT NULL DEFAULT 0 CHECK (freight_amount >= 0),
    marketplace_fee NUMERIC(10,2) NOT NULL DEFAULT 0 CHECK (marketplace_fee >= 0),
    discount_amount NUMERIC(10,2) NOT NULL DEFAULT 0 CHECK (discount_amount >= 0),
    total_amount NUMERIC(10,2) NOT NULL DEFAULT 0 CHECK (total_amount >= 0),

    currency CHAR(3) NOT NULL DEFAULT 'BRL'
    CHECK (currency ~ '^[A-Z]{3}$'),

    payment_method VARCHAR(50),

    order_status order_status_enum NOT NULL DEFAULT 'created',

    freight_method VARCHAR(50),
    freight_carrier VARCHAR(50),

    logistic_status logistic_status_enum NOT NULL DEFAULT 'new',
    payment_status payment_status_enum NOT NULL DEFAULT 'pending',

    id_transaction VARCHAR(255),

    purchase_datetime TIMESTAMPTZ,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT chk_order_discount
    CHECK (discount_amount <= subtotal_amount),

    CONSTRAINT chk_order_marketplace_fee
    CHECK (marketplace_fee <= subtotal_amount - discount_amount),

    CONSTRAINT chk_order_total
    CHECK (total_amount = subtotal_amount + freight_amount - discount_amount),

    CONSTRAINT chk_order_purchase_datetime
    CHECK (
        purchase_datetime IS NULL
        OR purchase_datetime >= created_at
    ),

    CONSTRAINT fk_order_buyer
        FOREIGN KEY (id_buyer)
        REFERENCES user_account(id_user),

    CONSTRAINT fk_order_address
    FOREIGN KEY (id_buyer, id_address)
    REFERENCES address(id_user, id_address)
    ON DELETE SET NULL (id_address)
);

CREATE INDEX idx_order_buyer_created ON customer_order(id_buyer, created_at DESC);
CREATE INDEX idx_order_buyer_address ON customer_order(id_buyer, id_address);
CREATE INDEX idx_order_payment_status ON customer_order(payment_status);
CREATE INDEX idx_order_logistic_status ON customer_order(logistic_status);
CREATE INDEX idx_order_purchase_datetime ON customer_order(purchase_datetime);

-- Trigger para ORDERS
--atualizar automaticamente o campo updated_at quando o registro for alterado
CREATE TRIGGER trg_customer_order_updated_at
BEFORE UPDATE ON customer_order
FOR EACH ROW
EXECUTE FUNCTION update_updated_at();


-- Impede alterações financeiras após o fechamento do pedido
CREATE OR REPLACE FUNCTION protect_order_financial_values()
RETURNS TRIGGER AS $$
BEGIN

    IF OLD.order_status <> 'created'
    OR (
       OLD.order_status = 'created'
       AND NEW.order_status <> 'created'
    ) THEN

        IF NEW.subtotal_amount IS DISTINCT FROM OLD.subtotal_amount
           OR NEW.freight_amount IS DISTINCT FROM OLD.freight_amount
           OR NEW.marketplace_fee IS DISTINCT FROM OLD.marketplace_fee
           OR NEW.discount_amount IS DISTINCT FROM OLD.discount_amount
           OR NEW.total_amount IS DISTINCT FROM OLD.total_amount
           OR NEW.currency IS DISTINCT FROM OLD.currency
           OR NEW.payment_method IS DISTINCT FROM OLD.payment_method
           OR NEW.freight_method IS DISTINCT FROM OLD.freight_method
           OR NEW.freight_carrier IS DISTINCT FROM OLD.freight_carrier
           OR NEW.id_buyer IS DISTINCT FROM OLD.id_buyer
           OR NEW.id_address IS DISTINCT FROM OLD.id_address THEN

            RAISE EXCEPTION
                'Não é permitido alterar os valores financeiros do pedido % após sua finalização',
                OLD.id_order;

        END IF;

    END IF;

    RETURN NEW;

END;
$$ LANGUAGE plpgsql;


CREATE TRIGGER trg_protect_order_financial_values
BEFORE UPDATE ON customer_order
FOR EACH ROW
EXECUTE FUNCTION protect_order_financial_values();

