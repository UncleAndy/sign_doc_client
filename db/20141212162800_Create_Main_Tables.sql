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
