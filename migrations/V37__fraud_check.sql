-- registra a análise de risco de pedidos/pagamentos e define o que o sistema deve fazer com eles
CREATE TABLE fraud_check (
    id_fraud_check BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

    id_order BIGINT NOT NULL,
    id_payment BIGINT,

    risk_score INT CHECK (risk_score BETWEEN 0 AND 100),

    risk_level fraud_risk_level_enum NOT NULL,

    fraud_provider VARCHAR(100),

    decision fraud_decision_enum NOT NULL,

    is_latest BOOLEAN DEFAULT TRUE,

    checked_at TIMESTAMPTZ DEFAULT NOW(),

    metadata JSONB,

    CONSTRAINT fk_fraud_order
        FOREIGN KEY (id_order)
        REFERENCES customer_order(id_order)
        ON DELETE CASCADE,

    CONSTRAINT fk_fraud_payment
        FOREIGN KEY (id_payment)
        REFERENCES payment(id_payment)
        ON DELETE SET NULL,

    -- consistência entre risco e decisão
    CONSTRAINT chk_risk_decision_consistency
    CHECK (
        (risk_level = 'low' AND decision = 'approve') OR
        (risk_level = 'medium' AND decision IN ('approve','review')) OR
        (risk_level = 'high' AND decision IN ('review','block'))
    )
);

-- consultas por pedido
CREATE INDEX idx_fraud_order 
ON fraud_check(id_order);

-- histórico ordenado
CREATE INDEX idx_fraud_order_date
ON fraud_check(id_order, checked_at DESC);

-- pagamento
CREATE INDEX idx_fraud_payment 
ON fraud_check(id_payment);

-- análise de risco
CREATE INDEX idx_fraud_risk_level 
ON fraud_check(risk_level);

-- decisão
CREATE INDEX idx_fraud_decision 
ON fraud_check(decision);

-- timeline
CREATE INDEX idx_fraud_checked_at 
ON fraud_check(checked_at DESC);

-- fila de revisão (🔥 MUITO IMPORTANTE)
CREATE INDEX idx_fraud_review_queue
ON fraud_check(checked_at)
WHERE decision = 'review';

-- garantir apenas 1 análise ativa por pedido
CREATE UNIQUE INDEX idx_unique_latest_fraud
ON fraud_check(id_order)
WHERE is_latest = TRUE;