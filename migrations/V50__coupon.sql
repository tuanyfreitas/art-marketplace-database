CREATE TABLE coupon (
    id_coupon UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    code VARCHAR(50) NOT NULL UNIQUE,

    discount_type discount_type_enum NOT NULL,
    discount_value NUMERIC(10,2) NOT NULL,

    max_uses INTEGER,
    expires_at TIMESTAMPTZ,

    active BOOLEAN NOT NULL DEFAULT TRUE,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT chk_coupon_discount_value_non_negative
        CHECK (discount_value >= 0),

    CONSTRAINT chk_coupon_max_uses_non_negative
        CHECK (max_uses IS NULL OR max_uses >= 0)
);