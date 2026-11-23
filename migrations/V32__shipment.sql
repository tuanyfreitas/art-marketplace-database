CREATE TABLE shipment (
    id_shipment BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

    id_order BIGINT NOT NULL,
    id_seller UUID NOT NULL,
    id_shipment_address UUID,

    carrier VARCHAR(100),
    tracking_code VARCHAR(100),

    status shipment_status_enum NOT NULL DEFAULT 'pending',

    shipping_cost NUMERIC(10,2) CHECK (shipping_cost >= 0),

    shipped_at TIMESTAMPTZ,
    delivered_at TIMESTAMPTZ,

    created_at TIMESTAMPTZ DEFAULT NOW(),

    CONSTRAINT fk_shipment_order
        FOREIGN KEY (id_order)
        REFERENCES customer_order(id_order)
        ON DELETE CASCADE,

    CONSTRAINT fk_shipment_seller
        FOREIGN KEY (id_seller)
        REFERENCES user_account(id_user)
        ON DELETE RESTRICT,

    CONSTRAINT fk_shipment_address
        FOREIGN KEY (id_shipment_address)
        REFERENCES address(id_address)
        ON DELETE SET NULL,

    CONSTRAINT chk_shipment_dates
        CHECK (
            delivered_at IS NULL 
            OR shipped_at IS NULL 
            OR delivered_at >= shipped_at
        )
);

CREATE INDEX idx_shipment_order ON shipment(id_order);
CREATE INDEX idx_shipment_seller ON shipment(id_seller);
CREATE INDEX idx_shipment_status ON shipment(status);
CREATE INDEX idx_shipment_tracking ON shipment(tracking_code);
CREATE INDEX idx_shipment_in_transit
ON shipment(status)
WHERE status IN ('shipped','in_transit');