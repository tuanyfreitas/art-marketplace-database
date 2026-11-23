CREATE TABLE role (
    id_role INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    role_name VARCHAR(100) NOT NULL UNIQUE,
    description TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO role (role_name, description) VALUES
('ADMIN','Administrador'),
('CURATOR','Curador'),
('FINANCE','Financeiro'),
('USER','Usuário padrão'),
('SUPPORT','Atendimento'),
('MARKETING','Marketing')
ON CONFLICT DO NOTHING;
