CREATE TABLE order_logistic_history (
    id_history BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

    id_order BIGINT NOT NULL,

    logistic_status logistic_status_enum NOT NULL,

    comment TEXT,

    created_at TIMESTAMPTZ DEFAULT NOW(),

    CONSTRAINT fk_logistic_history_order
        FOREIGN KEY (id_order)
        REFERENCES customer_order(id_order)
        ON DELETE CASCADE
);

CREATE INDEX idx_logistic_history_order ON order_logistic_history(id_order);
CREATE INDEX idx_logistic_history_order_date ON order_logistic_history(id_order, created_at DESC);