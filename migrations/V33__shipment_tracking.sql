CREATE TABLE shipment_tracking (
    id_tracking BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

    id_shipment BIGINT NOT NULL,

    status shipment_status_enum NOT NULL,

    location VARCHAR(255),
    description TEXT,

    event_time TIMESTAMPTZ NOT NULL,

    created_at TIMESTAMPTZ DEFAULT NOW(),

    CONSTRAINT fk_tracking_shipment
        FOREIGN KEY (id_shipment)
        REFERENCES shipment(id_shipment)
        ON DELETE CASCADE
);

CREATE INDEX idx_tracking_shipment_time ON shipment_tracking(id_shipment, event_time DESC);
CREATE INDEX idx_tracking_status ON shipment_tracking(status);