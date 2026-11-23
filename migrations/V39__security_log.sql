-- registra tudo relacionado a login
CREATE TABLE login_log (
    id_log BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

    id_user UUID,

    action login_action_enum NOT NULL,

    failure_reason VARCHAR(255),

    route TEXT,

    event_time TIMESTAMPTZ DEFAULT NOW(),

    ip_origin INET,

    user_agent TEXT,

    CONSTRAINT fk_loginlog_user
        FOREIGN KEY (id_user)
        REFERENCES user_account(id_user)
        ON DELETE SET NULL
);

-- usuário
CREATE INDEX idx_loginlog_user 
ON login_log(id_user);

-- timeline
CREATE INDEX idx_loginlog_event_time 
ON login_log(event_time DESC);

-- falhas (segurança)
CREATE INDEX idx_loginlog_failed
ON login_log(event_time)
WHERE action = 'failed';

-- análise por IP (antifraude)
CREATE INDEX idx_loginlog_ip 
ON login_log(ip_origin);


-- SECURITY LOG
-- eventos de segurança gerais como mudança de senha e atividades suspeitas
CREATE TABLE security_log (
    id_log BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

    id_user UUID,

    event_type security_event_enum NOT NULL,

    event_time TIMESTAMPTZ DEFAULT NOW(),

    ip_origin INET,

    user_agent TEXT,

    route TEXT,

    details JSONB,

    CONSTRAINT fk_security_user
        FOREIGN KEY (id_user)
        REFERENCES user_account(id_user)
        ON DELETE SET NULL
);

CREATE INDEX idx_security_user ON security_log(id_user);
CREATE INDEX idx_security_event_type ON security_log(event_type);
CREATE INDEX idx_security_event_time ON security_log(event_time DESC);

-- eventos críticos recentes
CREATE INDEX idx_security_recent
ON security_log(event_time)
WHERE event_type IN ('suspicious_activity','account_locked');