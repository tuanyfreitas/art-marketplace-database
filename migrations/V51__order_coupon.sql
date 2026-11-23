CREATE TABLE order_coupon (
    id_order_coupon UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    id_order BIGINT NOT NULL,
    id_coupon UUID NOT NULL,

    discount_applied NUMERIC(10,2) NOT NULL,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT fk_order_coupon_order
        FOREIGN KEY (id_order)
        REFERENCES customer_order(id_order)
        ON DELETE CASCADE,

    CONSTRAINT fk_order_coupon_coupon
        FOREIGN KEY (id_coupon)
        REFERENCES coupon(id_coupon)
        ON DELETE CASCADE,
    
    CONSTRAINT uq_order_coupon_order_coupon
        UNIQUE (id_order, id_coupon),

    CONSTRAINT chk_order_coupon_discount_applied_non_negative
        CHECK (discount_applied >= 0)
);