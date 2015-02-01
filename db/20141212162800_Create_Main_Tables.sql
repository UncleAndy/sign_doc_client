CREATE TABLE documents (
    id character varying(128) NOT NULL,
    code character varying(128),
    doc_data text,
    doc_template text,
    doc_sign text,
    signed integer DEFAULT 0
);

CREATE TABLE registrations (
    id bigint NOT NULL,
    code character varying(128),
    public_key text
);

CREATE TABLE signs (
    id BIGSERIAL NOT NULL PRIMARY KEY,
    doc_id VARCHAR(128),
    user_key_id VARCHAR(128),
    sign TEXT,
    public_key TEXT,
    t_sign TIMESTAMP default NOW()
);
CREATE INDEX idx_signs ON signs (doc_id, user_key_id);
