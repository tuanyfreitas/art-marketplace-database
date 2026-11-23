-- Função responsável por atualizar automaticamente o campo updated_at.
-- Sempre que um registro for modificado em uma tabela que utilize esta função
-- por meio de um trigger BEFORE UPDATE, o campo updated_at receberá o timestamp
-- atual (NOW()), permitindo o controle de auditoria básica e rastreabilidade
-- de alterações nos dados
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at := NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
