-- Função: validate_login_secure
-- Descrição: Valida o login de um usuário verificando email e senha.
--             Só permite login se a conta estiver ativa e não estiver bloqueada.
--             Incrementa contador de tentativas falhas e reseta em caso de sucesso.
-- Parâmetros:
--   p_email    : email do usuário (texto)
--   p_password : senha fornecida pelo usuário (texto)
-- Retorno:
--   INT : id do usuário logado ou NULL se falhar
-- Observações de segurança:
--   - Usa crypt() para comparar senha hash.
--   - SECURITY DEFINER para permitir execução segura por outro usuário.
CREATE OR REPLACE FUNCTION validate_login_secure(
    p_email TEXT,
    p_password TEXT
)
RETURNS UUID AS $$
DECLARE
    v_id UUID;
BEGIN

    SELECT id_user INTO v_id
    FROM user_account
    WHERE lower(email) = lower(p_email)
      AND password_hash = crypt(p_password, password_hash)
      AND account_status = 'active'
      AND locked_at IS NULL
    LIMIT 1;

    IF v_id IS NULL THEN

        UPDATE user_account
        SET failed_attempts = failed_attempts + 1,
            locked_at = CASE 
                WHEN failed_attempts + 1 >= 5 THEN NOW()
                ELSE locked_at
            END
        WHERE lower(email) = lower(p_email);

        -- log de falha (se usuário existir)
        INSERT INTO login_log (id_user, action)
        SELECT id_user, 'failed'
        FROM user_account
        WHERE lower(email) = lower(p_email);

        RETURN NULL;
    END IF;

    UPDATE user_account
    SET failed_attempts = 0,
        last_login_at = NOW()
    WHERE id_user = v_id;

    -- log de sucesso
    INSERT INTO login_log (id_user, action)
    VALUES (v_id, 'login');

    RETURN v_id;

END;
$$ LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public;


-- Função: reset_password_token
-- Descrição: Atualiza a senha de um usuário utilizando token de redefinição.
--             Valida se o token é válido, não expirou e não foi usado.
--             Reseta o contador de tentativas falhas ao trocar a senha.
-- Parâmetros:
--   p_token_hash : hash do token de redefinição
--   p_new_hash   : nova senha já hasheada
-- Retorno:
--   BOOLEAN : TRUE se a senha foi alterada com sucesso, FALSE caso contrário
-- Observações de segurança:
--   - Garante que o token só seja usado uma vez e dentro do prazo de validade.
--   - SECURITY DEFINER para execução segura mesmo por usuários sem acesso direto à tabela
CREATE OR REPLACE FUNCTION reset_password_token(
    p_token_hash TEXT,
    p_new_hash TEXT
)
RETURNS BOOLEAN AS $$
DECLARE
    v_user UUID;
BEGIN

    SELECT id_user INTO v_user
    FROM password_reset
    WHERE token_hash = p_token_hash
      AND used_at IS NULL
      AND expires_at > NOW()
    LIMIT 1;

    IF v_user IS NULL THEN
        RETURN FALSE;
    END IF;

    UPDATE user_account
    SET password_hash = p_new_hash,
        failed_attempts = 0,
        locked_at = NULL
    WHERE id_user = v_user;

    UPDATE password_reset
    SET used_at = NOW()
    WHERE token_hash = p_token_hash;

    -- log de segurança
    INSERT INTO security_log (id_user, event_type)
    VALUES (v_user, 'password_change');

    RETURN TRUE;

END;
$$ LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public;