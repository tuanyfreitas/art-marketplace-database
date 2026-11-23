CREATE TABLE user_role (
    id_user UUID NOT NULL,
    id_role INT NOT NULL,

    assigned_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    PRIMARY KEY (id_user, id_role),

    CONSTRAINT fk_user_role_user
        FOREIGN KEY (id_user)
        REFERENCES user_account(id_user)
        ON DELETE CASCADE,

    CONSTRAINT fk_user_role_role
        FOREIGN KEY (id_role)
        REFERENCES role(id_role)
        ON DELETE CASCADE
);