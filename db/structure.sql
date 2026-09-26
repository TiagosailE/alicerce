SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: audit_events_append_only(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.audit_events_append_only() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF current_user <> (SELECT tableowner FROM pg_tables WHERE schemaname = 'public' AND tablename = 'audit_events') THEN
    RAISE EXCEPTION 'audit_events is append-only: % is not permitted for %', TG_OP, current_user;
  END IF;

  RETURN COALESCE(NEW, OLD);
END;
$$;


--
-- Name: audit_purge(bigint, timestamp with time zone); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.audit_purge(target_organization_id bigint, purge_before timestamp with time zone) RETURNS bigint
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE
  purged_count bigint;
BEGIN
  DELETE FROM audit_events
  WHERE organization_id = target_organization_id AND created_at < purge_before;

  GET DIAGNOSTICS purged_count = ROW_COUNT;
  RETURN purged_count;
END;
$$;


--
-- Name: audit_redact(bigint, character varying, bigint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.audit_redact(target_organization_id bigint, target_subject_type character varying, target_subject_id bigint) RETURNS bigint
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE
  redacted_count bigint;
BEGIN
  UPDATE audit_events
  SET field_changes = '{"redacted": true}'::jsonb
  WHERE organization_id = target_organization_id
    AND subject_type = target_subject_type
    AND subject_id = target_subject_id;

  GET DIAGNOSTICS redacted_count = ROW_COUNT;
  RETURN redacted_count;
END;
$$;


--
-- Name: inventory_movement_redact_note(bigint, bigint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.inventory_movement_redact_note(target_organization_id bigint, target_movement_id bigint) RETURNS bigint
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE
  redacted_count bigint;
BEGIN
  IF target_organization_id IS DISTINCT FROM NULLIF(current_setting('app.organization_id', true), '')::bigint THEN
    RAISE EXCEPTION 'inventory_movement_redact_note: not the current organization';
  END IF;

  UPDATE inventory_movements
  SET note = NULL
  WHERE organization_id = target_organization_id AND id = target_movement_id AND note IS NOT NULL;

  GET DIAGNOSTICS redacted_count = ROW_COUNT;
  RETURN redacted_count;
END;
$$;


--
-- Name: inventory_movements_append_only(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.inventory_movements_append_only() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF current_user <> (SELECT tableowner FROM pg_tables WHERE schemaname = 'public' AND tablename = 'inventory_movements') THEN
    RAISE EXCEPTION 'inventory_movements is append-only: % is not permitted for %', TG_OP, current_user;
  END IF;

  RETURN COALESCE(NEW, OLD);
END;
$$;


--
-- Name: inventory_movements_no_truncate(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.inventory_movements_no_truncate() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF current_user <> (SELECT tableowner FROM pg_tables WHERE schemaname = 'public' AND tablename = 'inventory_movements') THEN
    RAISE EXCEPTION 'inventory_movements is append-only: TRUNCATE is not permitted for %', current_user;
  END IF;

  RETURN NULL;
END;
$$;


--
-- Name: invitation_organization_id(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.invitation_organization_id(target_token_digest character varying) RETURNS bigint
    LANGUAGE sql SECURITY DEFINER
    AS $$
  SELECT organization_id FROM identity_invitations WHERE token_digest = target_token_digest LIMIT 1;
$$;


--
-- Name: purchasing_order_lines_freeze(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.purchasing_order_lines_freeze() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  parent_status text;
BEGIN
  SELECT status INTO parent_status FROM purchasing_orders
    WHERE id = (CASE WHEN TG_OP = 'INSERT' THEN NEW.order_id ELSE OLD.order_id END);

  IF parent_status IS DISTINCT FROM 'draft' THEN
    IF TG_OP <> 'UPDATE' THEN
      RAISE EXCEPTION 'lines of a purchase order that is not a draft cannot be % (order status: %)', lower(TG_OP), parent_status;
    END IF;

    IF (NEW.order_id, NEW.position, NEW.product_id, NEW.purchase_unit_id, NEW.factor, NEW.quantity, NEW.unit_price_cents,
        NEW.discount_bp, NEW.gross_cents, NEW.discount_cents, NEW.net_cents)
       IS DISTINCT FROM
       (OLD.order_id, OLD.position, OLD.product_id, OLD.purchase_unit_id, OLD.factor, OLD.quantity, OLD.unit_price_cents,
        OLD.discount_bp, OLD.gross_cents, OLD.discount_cents, OLD.net_cents) THEN
      RAISE EXCEPTION 'the lines of a purchase order that is not a draft are frozen (order status: %)', parent_status;
    END IF;
  END IF;

  RETURN COALESCE(NEW, OLD);
END;
$$;


--
-- Name: purchasing_receipts_append_only(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.purchasing_receipts_append_only() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF current_user <> (SELECT tableowner FROM pg_tables WHERE schemaname = 'public' AND tablename = TG_TABLE_NAME) THEN
    RAISE EXCEPTION '% is append-only: % is not permitted for %', TG_TABLE_NAME, TG_OP, current_user;
  END IF;
  RETURN COALESCE(NEW, OLD);
END;
$$;


--
-- Name: purchasing_receipts_no_truncate(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.purchasing_receipts_no_truncate() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF current_user <> (SELECT tableowner FROM pg_tables WHERE schemaname = 'public' AND tablename = TG_TABLE_NAME) THEN
    RAISE EXCEPTION '% is append-only: TRUNCATE is not permitted for %', TG_TABLE_NAME, current_user;
  END IF;
  RETURN NULL;
END;
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: ar_internal_metadata; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ar_internal_metadata (
    key character varying NOT NULL,
    value character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: audit_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.audit_events (
    id bigint NOT NULL,
    organization_id bigint NOT NULL,
    actor_user_id bigint NOT NULL,
    action character varying NOT NULL,
    subject_type character varying NOT NULL,
    subject_id bigint NOT NULL,
    field_changes jsonb DEFAULT '{}'::jsonb NOT NULL,
    request_id character varying,
    ip_prefix character varying,
    created_at timestamp(6) without time zone NOT NULL
);


--
-- Name: audit_events_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.audit_events_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: audit_events_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.audit_events_id_seq OWNED BY public.audit_events.id;


--
-- Name: catalog_categories; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.catalog_categories (
    id bigint NOT NULL,
    organization_id bigint NOT NULL,
    name character varying NOT NULL,
    active boolean DEFAULT true NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: catalog_categories_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.catalog_categories_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: catalog_categories_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.catalog_categories_id_seq OWNED BY public.catalog_categories.id;


--
-- Name: catalog_partners; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.catalog_partners (
    id bigint NOT NULL,
    organization_id bigint NOT NULL,
    name character varying NOT NULL,
    document_type character varying NOT NULL,
    document_number character varying NOT NULL,
    customer boolean DEFAULT false NOT NULL,
    supplier boolean DEFAULT false NOT NULL,
    email character varying,
    phone character varying,
    active boolean DEFAULT true NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    revision integer DEFAULT 0 NOT NULL,
    CONSTRAINT catalog_partners_customer_or_supplier CHECK ((customer OR supplier)),
    CONSTRAINT catalog_partners_document_type_valid CHECK (((document_type)::text = ANY ((ARRAY['cpf'::character varying, 'cnpj'::character varying])::text[])))
);


--
-- Name: catalog_partners_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.catalog_partners_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: catalog_partners_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.catalog_partners_id_seq OWNED BY public.catalog_partners.id;


--
-- Name: catalog_products; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.catalog_products (
    id bigint NOT NULL,
    organization_id bigint NOT NULL,
    sku character varying NOT NULL,
    name character varying NOT NULL,
    category_id bigint,
    stock_unit_id bigint NOT NULL,
    active boolean DEFAULT true NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    revision integer DEFAULT 0 NOT NULL
);


--
-- Name: catalog_products_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.catalog_products_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: catalog_products_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.catalog_products_id_seq OWNED BY public.catalog_products.id;


--
-- Name: catalog_unit_conversions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.catalog_unit_conversions (
    id bigint NOT NULL,
    organization_id bigint NOT NULL,
    product_id bigint NOT NULL,
    purchase_unit_id bigint NOT NULL,
    factor numeric(15,6) NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT catalog_unit_conversions_factor_positive CHECK ((factor > (0)::numeric))
);


--
-- Name: catalog_unit_conversions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.catalog_unit_conversions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: catalog_unit_conversions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.catalog_unit_conversions_id_seq OWNED BY public.catalog_unit_conversions.id;


--
-- Name: catalog_units; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.catalog_units (
    id bigint NOT NULL,
    organization_id bigint NOT NULL,
    code character varying NOT NULL,
    name character varying NOT NULL,
    active boolean DEFAULT true NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: catalog_units_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.catalog_units_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: catalog_units_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.catalog_units_id_seq OWNED BY public.catalog_units.id;


--
-- Name: document_counters; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.document_counters (
    id bigint NOT NULL,
    organization_id bigint NOT NULL,
    kind character varying NOT NULL,
    last_value bigint DEFAULT 0 NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT document_counters_kind_valid CHECK (((kind)::text = ANY ((ARRAY['purchase_order'::character varying, 'receipt'::character varying])::text[]))),
    CONSTRAINT document_counters_last_value_not_negative CHECK ((last_value >= 0))
);


--
-- Name: document_counters_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.document_counters_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: document_counters_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.document_counters_id_seq OWNED BY public.document_counters.id;


--
-- Name: finance_installments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.finance_installments (
    id bigint NOT NULL,
    organization_id bigint NOT NULL,
    title_id bigint NOT NULL,
    number integer NOT NULL,
    due_on date NOT NULL,
    amount_cents bigint NOT NULL,
    settled_cents bigint DEFAULT 0 NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT finance_installments_amount_positive CHECK ((amount_cents > 0)),
    CONSTRAINT finance_installments_number_positive CHECK ((number > 0)),
    CONSTRAINT finance_installments_settled_within_amount CHECK (((settled_cents >= 0) AND (settled_cents <= amount_cents)))
);


--
-- Name: finance_installments_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.finance_installments_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: finance_installments_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.finance_installments_id_seq OWNED BY public.finance_installments.id;


--
-- Name: finance_titles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.finance_titles (
    id bigint NOT NULL,
    organization_id bigint NOT NULL,
    kind character varying NOT NULL,
    partner_id bigint NOT NULL,
    partner_name character varying NOT NULL,
    receipt_id bigint,
    total_cents bigint NOT NULL,
    currency character varying(3) DEFAULT 'BRL'::character varying NOT NULL,
    status character varying DEFAULT 'open'::character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT finance_titles_currency_brl CHECK (((currency)::text = 'BRL'::text)),
    CONSTRAINT finance_titles_kind_valid CHECK (((kind)::text = ANY ((ARRAY['payable'::character varying, 'receivable'::character varying])::text[]))),
    CONSTRAINT finance_titles_payable_has_a_receipt CHECK ((((kind)::text <> 'payable'::text) OR (receipt_id IS NOT NULL))),
    CONSTRAINT finance_titles_status_valid CHECK (((status)::text = ANY ((ARRAY['open'::character varying, 'cancelled'::character varying])::text[]))),
    CONSTRAINT finance_titles_total_range CHECK (((total_cents > 0) AND (total_cents <= '1000000000000000'::bigint)))
);


--
-- Name: finance_titles_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.finance_titles_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: finance_titles_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.finance_titles_id_seq OWNED BY public.finance_titles.id;


--
-- Name: idempotency_keys; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.idempotency_keys (
    id bigint NOT NULL,
    organization_id bigint NOT NULL,
    user_id bigint NOT NULL,
    key character varying NOT NULL,
    request_digest character varying NOT NULL,
    response_status integer,
    resource_type character varying,
    resource_id bigint,
    created_at timestamp(6) without time zone NOT NULL
);


--
-- Name: idempotency_keys_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.idempotency_keys_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: idempotency_keys_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.idempotency_keys_id_seq OWNED BY public.idempotency_keys.id;


--
-- Name: identity_invitations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.identity_invitations (
    id bigint NOT NULL,
    organization_id bigint NOT NULL,
    invited_by_user_id bigint NOT NULL,
    accepted_by_user_id bigint,
    email character varying NOT NULL,
    role character varying NOT NULL,
    token_digest character varying NOT NULL,
    expires_at timestamp(6) without time zone NOT NULL,
    accepted_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT identity_invitations_role_valid CHECK (((role)::text = ANY (ARRAY[('owner'::character varying)::text, ('admin'::character varying)::text, ('purchasing'::character varying)::text, ('sales'::character varying)::text, ('finance'::character varying)::text, ('read_only'::character varying)::text])))
);


--
-- Name: identity_invitations_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.identity_invitations_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: identity_invitations_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.identity_invitations_id_seq OWNED BY public.identity_invitations.id;


--
-- Name: identity_memberships; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.identity_memberships (
    id bigint NOT NULL,
    organization_id bigint NOT NULL,
    user_id bigint NOT NULL,
    role character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT identity_memberships_role_valid CHECK (((role)::text = ANY (ARRAY[('owner'::character varying)::text, ('admin'::character varying)::text, ('purchasing'::character varying)::text, ('sales'::character varying)::text, ('finance'::character varying)::text, ('read_only'::character varying)::text])))
);


--
-- Name: identity_memberships_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.identity_memberships_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: identity_memberships_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.identity_memberships_id_seq OWNED BY public.identity_memberships.id;


--
-- Name: identity_organizations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.identity_organizations (
    id bigint NOT NULL,
    name character varying NOT NULL,
    time_zone character varying DEFAULT 'America/Sao_Paulo'::character varying NOT NULL,
    demo boolean DEFAULT false NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: identity_organizations_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.identity_organizations_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: identity_organizations_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.identity_organizations_id_seq OWNED BY public.identity_organizations.id;


--
-- Name: identity_sessions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.identity_sessions (
    id bigint NOT NULL,
    user_id bigint NOT NULL,
    organization_id bigint NOT NULL,
    token_digest character varying NOT NULL,
    ip character varying,
    user_agent character varying,
    last_seen_at timestamp(6) without time zone NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: identity_sessions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.identity_sessions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: identity_sessions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.identity_sessions_id_seq OWNED BY public.identity_sessions.id;


--
-- Name: identity_users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.identity_users (
    id bigint NOT NULL,
    email character varying NOT NULL,
    name character varying NOT NULL,
    password_digest character varying NOT NULL,
    demo boolean DEFAULT false NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: identity_users_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.identity_users_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: identity_users_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.identity_users_id_seq OWNED BY public.identity_users.id;


--
-- Name: inventory_balances; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.inventory_balances (
    id bigint NOT NULL,
    organization_id bigint NOT NULL,
    product_id bigint NOT NULL,
    warehouse_id bigint NOT NULL,
    on_hand numeric(15,3) DEFAULT 0.0 NOT NULL,
    reserved numeric(15,3) DEFAULT 0.0 NOT NULL,
    negative_allowance numeric(15,3) DEFAULT 0.0 NOT NULL,
    value_cents bigint DEFAULT 0 NOT NULL,
    last_unit_cost numeric(19,6) DEFAULT 0.0 NOT NULL,
    currency character varying(3) DEFAULT 'BRL'::character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT inventory_balances_allowance_not_negative CHECK ((negative_allowance >= (0)::numeric)),
    CONSTRAINT inventory_balances_currency_brl CHECK (((currency)::text = 'BRL'::text)),
    CONSTRAINT inventory_balances_last_unit_cost_not_negative CHECK ((last_unit_cost >= (0)::numeric)),
    CONSTRAINT inventory_balances_on_hand_within_allowance CHECK ((on_hand >= (- negative_allowance))),
    CONSTRAINT inventory_balances_reserved_not_negative CHECK ((reserved >= (0)::numeric)),
    CONSTRAINT inventory_balances_value_follows_stock CHECK ((((on_hand > (0)::numeric) AND (value_cents >= 0)) OR ((on_hand < (0)::numeric) AND (value_cents <= 0)) OR ((on_hand = (0)::numeric) AND (value_cents = 0))))
);


--
-- Name: inventory_balances_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.inventory_balances_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: inventory_balances_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.inventory_balances_id_seq OWNED BY public.inventory_balances.id;


--
-- Name: inventory_movements; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.inventory_movements (
    id bigint NOT NULL,
    organization_id bigint NOT NULL,
    product_id bigint NOT NULL,
    warehouse_id bigint NOT NULL,
    kind character varying NOT NULL,
    quantity numeric(15,3) NOT NULL,
    value_cents bigint NOT NULL,
    currency character varying(3) DEFAULT 'BRL'::character varying NOT NULL,
    on_hand_after numeric(15,3) NOT NULL,
    value_after_cents bigint NOT NULL,
    reason character varying,
    note text,
    actor_user_id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    receipt_line_id bigint,
    CONSTRAINT inventory_movements_adjustment_has_reason CHECK ((((kind)::text <> 'adjustment'::text) OR (reason IS NOT NULL))),
    CONSTRAINT inventory_movements_adjustment_moves_stock CHECK ((((kind)::text <> 'adjustment'::text) OR (quantity <> (0)::numeric))),
    CONSTRAINT inventory_movements_currency_brl CHECK (((currency)::text = 'BRL'::text)),
    CONSTRAINT inventory_movements_kind_valid CHECK (((kind)::text = ANY ((ARRAY['adjustment'::character varying, 'receipt'::character varying])::text[]))),
    CONSTRAINT inventory_movements_only_receipts_have_a_line CHECK (((receipt_line_id IS NULL) OR ((kind)::text = 'receipt'::text))),
    CONSTRAINT inventory_movements_reason_valid CHECK (((reason IS NULL) OR ((reason)::text = ANY ((ARRAY['opening_balance'::character varying, 'count'::character varying, 'loss'::character varying, 'damage'::character varying, 'theft'::character varying, 'expiry'::character varying, 'found'::character varying, 'other'::character varying])::text[])))),
    CONSTRAINT inventory_movements_receipt_shape CHECK ((((kind)::text <> 'receipt'::text) OR ((quantity > (0)::numeric) AND (reason IS NULL) AND (receipt_line_id IS NOT NULL)))),
    CONSTRAINT inventory_movements_value_follows_quantity CHECK ((((quantity > (0)::numeric) AND (value_cents >= 0)) OR ((quantity < (0)::numeric) AND (value_cents <= 0)) OR (quantity = (0)::numeric)))
);


--
-- Name: inventory_movements_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.inventory_movements_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: inventory_movements_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.inventory_movements_id_seq OWNED BY public.inventory_movements.id;


--
-- Name: inventory_warehouses; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.inventory_warehouses (
    id bigint NOT NULL,
    organization_id bigint NOT NULL,
    name character varying NOT NULL,
    active boolean DEFAULT true NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: inventory_warehouses_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.inventory_warehouses_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: inventory_warehouses_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.inventory_warehouses_id_seq OWNED BY public.inventory_warehouses.id;


--
-- Name: purchasing_order_lines; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.purchasing_order_lines (
    id bigint NOT NULL,
    organization_id bigint NOT NULL,
    order_id bigint NOT NULL,
    "position" integer NOT NULL,
    product_id bigint NOT NULL,
    product_sku character varying NOT NULL,
    product_name character varying NOT NULL,
    purchase_unit_id bigint NOT NULL,
    purchase_unit_code character varying NOT NULL,
    stock_unit_code character varying NOT NULL,
    factor numeric(15,6) NOT NULL,
    quantity numeric(15,3) NOT NULL,
    unit_price_cents bigint NOT NULL,
    discount_bp integer DEFAULT 0 NOT NULL,
    gross_cents bigint NOT NULL,
    discount_cents bigint NOT NULL,
    net_cents bigint NOT NULL,
    received_quantity numeric(15,3) DEFAULT 0.0 NOT NULL,
    received_stock_quantity numeric(15,3) DEFAULT 0.0 NOT NULL,
    received_gross_cents bigint DEFAULT 0 NOT NULL,
    received_discount_cents bigint DEFAULT 0 NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT purchasing_order_lines_amounts_consistent CHECK (((gross_cents >= 0) AND (discount_cents >= 0) AND (discount_cents <= gross_cents) AND (net_cents = (gross_cents - discount_cents)))),
    CONSTRAINT purchasing_order_lines_discount_follows_bp CHECK (((discount_cents)::numeric = round((((gross_cents)::numeric * (discount_bp)::numeric) / (10000)::numeric)))),
    CONSTRAINT purchasing_order_lines_discount_range CHECK (((discount_bp >= 0) AND (discount_bp <= 10000))),
    CONSTRAINT purchasing_order_lines_factor_positive CHECK ((factor > (0)::numeric)),
    CONSTRAINT purchasing_order_lines_gross_cap CHECK ((gross_cents <= '1000000000000000'::bigint)),
    CONSTRAINT purchasing_order_lines_gross_follows_price CHECK (((gross_cents)::numeric = round((quantity * (unit_price_cents)::numeric)))),
    CONSTRAINT purchasing_order_lines_price_not_negative CHECK ((unit_price_cents >= 0)),
    CONSTRAINT purchasing_order_lines_quantity_positive CHECK ((quantity > (0)::numeric)),
    CONSTRAINT purchasing_order_lines_received_stock_within_line CHECK ((received_stock_quantity <= round((quantity * factor), 3))),
    CONSTRAINT purchasing_order_lines_received_within_line CHECK ((((received_quantity >= (0)::numeric) AND (received_quantity <= quantity)) AND (received_stock_quantity >= (0)::numeric) AND ((received_gross_cents >= 0) AND (received_gross_cents <= gross_cents)) AND ((received_discount_cents >= 0) AND (received_discount_cents <= discount_cents)) AND (received_discount_cents <= received_gross_cents))),
    CONSTRAINT purchasing_order_lines_stock_quantity_fits CHECK ((round((quantity * factor), 3) < ('1000000000000'::bigint)::numeric))
);


--
-- Name: purchasing_order_lines_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.purchasing_order_lines_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: purchasing_order_lines_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.purchasing_order_lines_id_seq OWNED BY public.purchasing_order_lines.id;


--
-- Name: purchasing_orders; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.purchasing_orders (
    id bigint NOT NULL,
    organization_id bigint NOT NULL,
    number bigint NOT NULL,
    supplier_id bigint NOT NULL,
    supplier_name character varying NOT NULL,
    supplier_document_type character varying NOT NULL,
    supplier_document_number character varying NOT NULL,
    status character varying DEFAULT 'draft'::character varying NOT NULL,
    currency character varying(3) DEFAULT 'BRL'::character varying NOT NULL,
    installments integer DEFAULT 1 NOT NULL,
    first_due_days integer DEFAULT 30 NOT NULL,
    interval_days integer DEFAULT 30 NOT NULL,
    note text,
    total_cents bigint DEFAULT 0 NOT NULL,
    revision integer DEFAULT 0 NOT NULL,
    approved_at timestamp(6) without time zone,
    approved_by_user_id bigint,
    cancelled_at timestamp(6) without time zone,
    cancelled_by_user_id bigint,
    created_by_user_id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT purchasing_orders_currency_brl CHECK (((currency)::text = 'BRL'::text)),
    CONSTRAINT purchasing_orders_first_due_days_range CHECK (((first_due_days >= 0) AND (first_due_days <= 365))),
    CONSTRAINT purchasing_orders_installments_range CHECK (((installments >= 1) AND (installments <= 24))),
    CONSTRAINT purchasing_orders_interval_days_range CHECK (((interval_days >= 0) AND (interval_days <= 365))),
    CONSTRAINT purchasing_orders_revision_not_negative CHECK ((revision >= 0)),
    CONSTRAINT purchasing_orders_status_valid CHECK (((status)::text = ANY ((ARRAY['draft'::character varying, 'approved'::character varying, 'partially_received'::character varying, 'received'::character varying, 'cancelled'::character varying])::text[]))),
    CONSTRAINT purchasing_orders_total_range CHECK (((total_cents >= 0) AND (total_cents <= '1000000000000000'::bigint)))
);


--
-- Name: purchasing_orders_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.purchasing_orders_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: purchasing_orders_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.purchasing_orders_id_seq OWNED BY public.purchasing_orders.id;


--
-- Name: purchasing_receipt_lines; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.purchasing_receipt_lines (
    id bigint NOT NULL,
    organization_id bigint NOT NULL,
    receipt_id bigint NOT NULL,
    order_id bigint NOT NULL,
    order_line_id bigint NOT NULL,
    product_id bigint NOT NULL,
    product_sku character varying NOT NULL,
    product_name character varying NOT NULL,
    purchase_unit_code character varying NOT NULL,
    stock_unit_code character varying NOT NULL,
    factor numeric(15,6) NOT NULL,
    unit_price_cents bigint NOT NULL,
    discount_bp integer NOT NULL,
    quantity numeric(15,3) NOT NULL,
    stock_quantity numeric(15,3) NOT NULL,
    gross_cents bigint NOT NULL,
    discount_cents bigint NOT NULL,
    net_cents bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT purchasing_receipt_lines_amounts_consistent CHECK (((gross_cents >= 0) AND (discount_cents >= 0) AND (discount_cents <= gross_cents) AND (net_cents = (gross_cents - discount_cents)))),
    CONSTRAINT purchasing_receipt_lines_discount_range CHECK (((discount_bp >= 0) AND (discount_bp <= 10000))),
    CONSTRAINT purchasing_receipt_lines_moves_stock CHECK (((quantity > (0)::numeric) AND (stock_quantity > (0)::numeric)))
);


--
-- Name: purchasing_receipt_lines_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.purchasing_receipt_lines_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: purchasing_receipt_lines_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.purchasing_receipt_lines_id_seq OWNED BY public.purchasing_receipt_lines.id;


--
-- Name: purchasing_receipts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.purchasing_receipts (
    id bigint NOT NULL,
    organization_id bigint NOT NULL,
    number bigint NOT NULL,
    order_id bigint NOT NULL,
    warehouse_id bigint NOT NULL,
    received_on date NOT NULL,
    supplier_invoice_number character varying,
    total_cents bigint DEFAULT 0 NOT NULL,
    status character varying DEFAULT 'posted'::character varying NOT NULL,
    currency character varying(3) DEFAULT 'BRL'::character varying NOT NULL,
    created_by_user_id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT purchasing_receipts_currency_brl CHECK (((currency)::text = 'BRL'::text)),
    CONSTRAINT purchasing_receipts_status_valid CHECK (((status)::text = 'posted'::text)),
    CONSTRAINT purchasing_receipts_total_range CHECK (((total_cents >= 0) AND (total_cents <= '1000000000000000'::bigint)))
);


--
-- Name: purchasing_receipts_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.purchasing_receipts_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: purchasing_receipts_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.purchasing_receipts_id_seq OWNED BY public.purchasing_receipts.id;


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_migrations (
    version character varying NOT NULL
);


--
-- Name: solid_cache_entries; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.solid_cache_entries (
    id bigint NOT NULL,
    key bytea NOT NULL,
    value bytea NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    key_hash bigint NOT NULL,
    byte_size integer NOT NULL
);


--
-- Name: solid_cache_entries_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.solid_cache_entries_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: solid_cache_entries_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.solid_cache_entries_id_seq OWNED BY public.solid_cache_entries.id;


--
-- Name: solid_queue_batch_executions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.solid_queue_batch_executions (
    id bigint NOT NULL,
    job_id bigint NOT NULL,
    batch_id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL
);


--
-- Name: solid_queue_batch_executions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.solid_queue_batch_executions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: solid_queue_batch_executions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.solid_queue_batch_executions_id_seq OWNED BY public.solid_queue_batch_executions.id;


--
-- Name: solid_queue_batches; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.solid_queue_batches (
    id bigint NOT NULL,
    active_job_batch_id character varying,
    description character varying,
    on_finish text,
    on_success text,
    on_failure text,
    metadata text,
    total_jobs integer DEFAULT 0 NOT NULL,
    completed_jobs integer DEFAULT 0 NOT NULL,
    failed_jobs integer DEFAULT 0 NOT NULL,
    enqueued_at timestamp(6) without time zone,
    finished_at timestamp(6) without time zone,
    failed_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: solid_queue_batches_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.solid_queue_batches_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: solid_queue_batches_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.solid_queue_batches_id_seq OWNED BY public.solid_queue_batches.id;


--
-- Name: solid_queue_blocked_executions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.solid_queue_blocked_executions (
    id bigint NOT NULL,
    job_id bigint NOT NULL,
    queue_name character varying NOT NULL,
    priority integer DEFAULT 0 NOT NULL,
    concurrency_key character varying NOT NULL,
    expires_at timestamp(6) without time zone NOT NULL,
    created_at timestamp(6) without time zone NOT NULL
);


--
-- Name: solid_queue_blocked_executions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.solid_queue_blocked_executions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: solid_queue_blocked_executions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.solid_queue_blocked_executions_id_seq OWNED BY public.solid_queue_blocked_executions.id;


--
-- Name: solid_queue_claimed_executions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.solid_queue_claimed_executions (
    id bigint NOT NULL,
    job_id bigint NOT NULL,
    process_id bigint,
    created_at timestamp(6) without time zone NOT NULL
);


--
-- Name: solid_queue_claimed_executions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.solid_queue_claimed_executions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: solid_queue_claimed_executions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.solid_queue_claimed_executions_id_seq OWNED BY public.solid_queue_claimed_executions.id;


--
-- Name: solid_queue_failed_executions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.solid_queue_failed_executions (
    id bigint NOT NULL,
    job_id bigint NOT NULL,
    error text,
    created_at timestamp(6) without time zone NOT NULL
);


--
-- Name: solid_queue_failed_executions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.solid_queue_failed_executions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: solid_queue_failed_executions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.solid_queue_failed_executions_id_seq OWNED BY public.solid_queue_failed_executions.id;


--
-- Name: solid_queue_jobs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.solid_queue_jobs (
    id bigint NOT NULL,
    queue_name character varying NOT NULL,
    class_name character varying NOT NULL,
    arguments text,
    priority integer DEFAULT 0 NOT NULL,
    active_job_id character varying,
    scheduled_at timestamp(6) without time zone,
    finished_at timestamp(6) without time zone,
    concurrency_key character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    batch_id bigint
);


--
-- Name: solid_queue_jobs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.solid_queue_jobs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: solid_queue_jobs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.solid_queue_jobs_id_seq OWNED BY public.solid_queue_jobs.id;


--
-- Name: solid_queue_pauses; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.solid_queue_pauses (
    id bigint NOT NULL,
    queue_name character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL
);


--
-- Name: solid_queue_pauses_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.solid_queue_pauses_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: solid_queue_pauses_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.solid_queue_pauses_id_seq OWNED BY public.solid_queue_pauses.id;


--
-- Name: solid_queue_processes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.solid_queue_processes (
    id bigint NOT NULL,
    kind character varying NOT NULL,
    last_heartbeat_at timestamp(6) without time zone NOT NULL,
    supervisor_id bigint,
    pid integer NOT NULL,
    hostname character varying,
    metadata text,
    created_at timestamp(6) without time zone NOT NULL,
    name character varying NOT NULL
);


--
-- Name: solid_queue_processes_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.solid_queue_processes_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: solid_queue_processes_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.solid_queue_processes_id_seq OWNED BY public.solid_queue_processes.id;


--
-- Name: solid_queue_ready_executions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.solid_queue_ready_executions (
    id bigint NOT NULL,
    job_id bigint NOT NULL,
    queue_name character varying NOT NULL,
    priority integer DEFAULT 0 NOT NULL,
    created_at timestamp(6) without time zone NOT NULL
);


--
-- Name: solid_queue_ready_executions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.solid_queue_ready_executions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: solid_queue_ready_executions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.solid_queue_ready_executions_id_seq OWNED BY public.solid_queue_ready_executions.id;


--
-- Name: solid_queue_recurring_executions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.solid_queue_recurring_executions (
    id bigint NOT NULL,
    job_id bigint NOT NULL,
    task_key character varying NOT NULL,
    run_at timestamp(6) without time zone NOT NULL,
    created_at timestamp(6) without time zone NOT NULL
);


--
-- Name: solid_queue_recurring_executions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.solid_queue_recurring_executions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: solid_queue_recurring_executions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.solid_queue_recurring_executions_id_seq OWNED BY public.solid_queue_recurring_executions.id;


--
-- Name: solid_queue_recurring_tasks; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.solid_queue_recurring_tasks (
    id bigint NOT NULL,
    key character varying NOT NULL,
    schedule character varying NOT NULL,
    command character varying(2048),
    class_name character varying,
    arguments text,
    queue_name character varying,
    priority integer DEFAULT 0,
    static boolean DEFAULT true NOT NULL,
    description text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: solid_queue_recurring_tasks_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.solid_queue_recurring_tasks_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: solid_queue_recurring_tasks_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.solid_queue_recurring_tasks_id_seq OWNED BY public.solid_queue_recurring_tasks.id;


--
-- Name: solid_queue_scheduled_executions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.solid_queue_scheduled_executions (
    id bigint NOT NULL,
    job_id bigint NOT NULL,
    queue_name character varying NOT NULL,
    priority integer DEFAULT 0 NOT NULL,
    scheduled_at timestamp(6) without time zone NOT NULL,
    created_at timestamp(6) without time zone NOT NULL
);


--
-- Name: solid_queue_scheduled_executions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.solid_queue_scheduled_executions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: solid_queue_scheduled_executions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.solid_queue_scheduled_executions_id_seq OWNED BY public.solid_queue_scheduled_executions.id;


--
-- Name: solid_queue_semaphores; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.solid_queue_semaphores (
    id bigint NOT NULL,
    key character varying NOT NULL,
    value integer DEFAULT 1 NOT NULL,
    expires_at timestamp(6) without time zone NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: solid_queue_semaphores_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.solid_queue_semaphores_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: solid_queue_semaphores_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.solid_queue_semaphores_id_seq OWNED BY public.solid_queue_semaphores.id;


--
-- Name: audit_events id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_events ALTER COLUMN id SET DEFAULT nextval('public.audit_events_id_seq'::regclass);


--
-- Name: catalog_categories id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.catalog_categories ALTER COLUMN id SET DEFAULT nextval('public.catalog_categories_id_seq'::regclass);


--
-- Name: catalog_partners id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.catalog_partners ALTER COLUMN id SET DEFAULT nextval('public.catalog_partners_id_seq'::regclass);


--
-- Name: catalog_products id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.catalog_products ALTER COLUMN id SET DEFAULT nextval('public.catalog_products_id_seq'::regclass);


--
-- Name: catalog_unit_conversions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.catalog_unit_conversions ALTER COLUMN id SET DEFAULT nextval('public.catalog_unit_conversions_id_seq'::regclass);


--
-- Name: catalog_units id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.catalog_units ALTER COLUMN id SET DEFAULT nextval('public.catalog_units_id_seq'::regclass);


--
-- Name: document_counters id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.document_counters ALTER COLUMN id SET DEFAULT nextval('public.document_counters_id_seq'::regclass);


--
-- Name: finance_installments id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.finance_installments ALTER COLUMN id SET DEFAULT nextval('public.finance_installments_id_seq'::regclass);


--
-- Name: finance_titles id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.finance_titles ALTER COLUMN id SET DEFAULT nextval('public.finance_titles_id_seq'::regclass);


--
-- Name: idempotency_keys id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.idempotency_keys ALTER COLUMN id SET DEFAULT nextval('public.idempotency_keys_id_seq'::regclass);


--
-- Name: identity_invitations id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.identity_invitations ALTER COLUMN id SET DEFAULT nextval('public.identity_invitations_id_seq'::regclass);


--
-- Name: identity_memberships id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.identity_memberships ALTER COLUMN id SET DEFAULT nextval('public.identity_memberships_id_seq'::regclass);


--
-- Name: identity_organizations id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.identity_organizations ALTER COLUMN id SET DEFAULT nextval('public.identity_organizations_id_seq'::regclass);


--
-- Name: identity_sessions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.identity_sessions ALTER COLUMN id SET DEFAULT nextval('public.identity_sessions_id_seq'::regclass);


--
-- Name: identity_users id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.identity_users ALTER COLUMN id SET DEFAULT nextval('public.identity_users_id_seq'::regclass);


--
-- Name: inventory_balances id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventory_balances ALTER COLUMN id SET DEFAULT nextval('public.inventory_balances_id_seq'::regclass);


--
-- Name: inventory_movements id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventory_movements ALTER COLUMN id SET DEFAULT nextval('public.inventory_movements_id_seq'::regclass);


--
-- Name: inventory_warehouses id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventory_warehouses ALTER COLUMN id SET DEFAULT nextval('public.inventory_warehouses_id_seq'::regclass);


--
-- Name: purchasing_order_lines id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.purchasing_order_lines ALTER COLUMN id SET DEFAULT nextval('public.purchasing_order_lines_id_seq'::regclass);


--
-- Name: purchasing_orders id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.purchasing_orders ALTER COLUMN id SET DEFAULT nextval('public.purchasing_orders_id_seq'::regclass);


--
-- Name: purchasing_receipt_lines id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.purchasing_receipt_lines ALTER COLUMN id SET DEFAULT nextval('public.purchasing_receipt_lines_id_seq'::regclass);


--
-- Name: purchasing_receipts id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.purchasing_receipts ALTER COLUMN id SET DEFAULT nextval('public.purchasing_receipts_id_seq'::regclass);


--
-- Name: solid_cache_entries id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_cache_entries ALTER COLUMN id SET DEFAULT nextval('public.solid_cache_entries_id_seq'::regclass);


--
-- Name: solid_queue_batch_executions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_batch_executions ALTER COLUMN id SET DEFAULT nextval('public.solid_queue_batch_executions_id_seq'::regclass);


--
-- Name: solid_queue_batches id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_batches ALTER COLUMN id SET DEFAULT nextval('public.solid_queue_batches_id_seq'::regclass);


--
-- Name: solid_queue_blocked_executions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_blocked_executions ALTER COLUMN id SET DEFAULT nextval('public.solid_queue_blocked_executions_id_seq'::regclass);


--
-- Name: solid_queue_claimed_executions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_claimed_executions ALTER COLUMN id SET DEFAULT nextval('public.solid_queue_claimed_executions_id_seq'::regclass);


--
-- Name: solid_queue_failed_executions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_failed_executions ALTER COLUMN id SET DEFAULT nextval('public.solid_queue_failed_executions_id_seq'::regclass);


--
-- Name: solid_queue_jobs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_jobs ALTER COLUMN id SET DEFAULT nextval('public.solid_queue_jobs_id_seq'::regclass);


--
-- Name: solid_queue_pauses id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_pauses ALTER COLUMN id SET DEFAULT nextval('public.solid_queue_pauses_id_seq'::regclass);


--
-- Name: solid_queue_processes id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_processes ALTER COLUMN id SET DEFAULT nextval('public.solid_queue_processes_id_seq'::regclass);


--
-- Name: solid_queue_ready_executions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_ready_executions ALTER COLUMN id SET DEFAULT nextval('public.solid_queue_ready_executions_id_seq'::regclass);


--
-- Name: solid_queue_recurring_executions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_recurring_executions ALTER COLUMN id SET DEFAULT nextval('public.solid_queue_recurring_executions_id_seq'::regclass);


--
-- Name: solid_queue_recurring_tasks id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_recurring_tasks ALTER COLUMN id SET DEFAULT nextval('public.solid_queue_recurring_tasks_id_seq'::regclass);


--
-- Name: solid_queue_scheduled_executions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_scheduled_executions ALTER COLUMN id SET DEFAULT nextval('public.solid_queue_scheduled_executions_id_seq'::regclass);


--
-- Name: solid_queue_semaphores id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_semaphores ALTER COLUMN id SET DEFAULT nextval('public.solid_queue_semaphores_id_seq'::regclass);


--
-- Name: ar_internal_metadata ar_internal_metadata_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ar_internal_metadata
    ADD CONSTRAINT ar_internal_metadata_pkey PRIMARY KEY (key);


--
-- Name: audit_events audit_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_events
    ADD CONSTRAINT audit_events_pkey PRIMARY KEY (id);


--
-- Name: catalog_categories catalog_categories_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.catalog_categories
    ADD CONSTRAINT catalog_categories_pkey PRIMARY KEY (id);


--
-- Name: catalog_partners catalog_partners_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.catalog_partners
    ADD CONSTRAINT catalog_partners_pkey PRIMARY KEY (id);


--
-- Name: catalog_products catalog_products_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.catalog_products
    ADD CONSTRAINT catalog_products_pkey PRIMARY KEY (id);


--
-- Name: catalog_unit_conversions catalog_unit_conversions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.catalog_unit_conversions
    ADD CONSTRAINT catalog_unit_conversions_pkey PRIMARY KEY (id);


--
-- Name: catalog_units catalog_units_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.catalog_units
    ADD CONSTRAINT catalog_units_pkey PRIMARY KEY (id);


--
-- Name: document_counters document_counters_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.document_counters
    ADD CONSTRAINT document_counters_pkey PRIMARY KEY (id);


--
-- Name: finance_installments finance_installments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.finance_installments
    ADD CONSTRAINT finance_installments_pkey PRIMARY KEY (id);


--
-- Name: finance_titles finance_titles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.finance_titles
    ADD CONSTRAINT finance_titles_pkey PRIMARY KEY (id);


--
-- Name: idempotency_keys idempotency_keys_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.idempotency_keys
    ADD CONSTRAINT idempotency_keys_pkey PRIMARY KEY (id);


--
-- Name: identity_invitations identity_invitations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.identity_invitations
    ADD CONSTRAINT identity_invitations_pkey PRIMARY KEY (id);


--
-- Name: identity_memberships identity_memberships_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.identity_memberships
    ADD CONSTRAINT identity_memberships_pkey PRIMARY KEY (id);


--
-- Name: identity_organizations identity_organizations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.identity_organizations
    ADD CONSTRAINT identity_organizations_pkey PRIMARY KEY (id);


--
-- Name: identity_sessions identity_sessions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.identity_sessions
    ADD CONSTRAINT identity_sessions_pkey PRIMARY KEY (id);


--
-- Name: identity_users identity_users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.identity_users
    ADD CONSTRAINT identity_users_pkey PRIMARY KEY (id);


--
-- Name: inventory_balances inventory_balances_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventory_balances
    ADD CONSTRAINT inventory_balances_pkey PRIMARY KEY (id);


--
-- Name: inventory_movements inventory_movements_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventory_movements
    ADD CONSTRAINT inventory_movements_pkey PRIMARY KEY (id);


--
-- Name: inventory_warehouses inventory_warehouses_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventory_warehouses
    ADD CONSTRAINT inventory_warehouses_pkey PRIMARY KEY (id);


--
-- Name: purchasing_order_lines purchasing_order_lines_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.purchasing_order_lines
    ADD CONSTRAINT purchasing_order_lines_pkey PRIMARY KEY (id);


--
-- Name: purchasing_orders purchasing_orders_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.purchasing_orders
    ADD CONSTRAINT purchasing_orders_pkey PRIMARY KEY (id);


--
-- Name: purchasing_receipt_lines purchasing_receipt_lines_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.purchasing_receipt_lines
    ADD CONSTRAINT purchasing_receipt_lines_pkey PRIMARY KEY (id);


--
-- Name: purchasing_receipts purchasing_receipts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.purchasing_receipts
    ADD CONSTRAINT purchasing_receipts_pkey PRIMARY KEY (id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: solid_cache_entries solid_cache_entries_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_cache_entries
    ADD CONSTRAINT solid_cache_entries_pkey PRIMARY KEY (id);


--
-- Name: solid_queue_batch_executions solid_queue_batch_executions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_batch_executions
    ADD CONSTRAINT solid_queue_batch_executions_pkey PRIMARY KEY (id);


--
-- Name: solid_queue_batches solid_queue_batches_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_batches
    ADD CONSTRAINT solid_queue_batches_pkey PRIMARY KEY (id);


--
-- Name: solid_queue_blocked_executions solid_queue_blocked_executions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_blocked_executions
    ADD CONSTRAINT solid_queue_blocked_executions_pkey PRIMARY KEY (id);


--
-- Name: solid_queue_claimed_executions solid_queue_claimed_executions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_claimed_executions
    ADD CONSTRAINT solid_queue_claimed_executions_pkey PRIMARY KEY (id);


--
-- Name: solid_queue_failed_executions solid_queue_failed_executions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_failed_executions
    ADD CONSTRAINT solid_queue_failed_executions_pkey PRIMARY KEY (id);


--
-- Name: solid_queue_jobs solid_queue_jobs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_jobs
    ADD CONSTRAINT solid_queue_jobs_pkey PRIMARY KEY (id);


--
-- Name: solid_queue_pauses solid_queue_pauses_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_pauses
    ADD CONSTRAINT solid_queue_pauses_pkey PRIMARY KEY (id);


--
-- Name: solid_queue_processes solid_queue_processes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_processes
    ADD CONSTRAINT solid_queue_processes_pkey PRIMARY KEY (id);


--
-- Name: solid_queue_ready_executions solid_queue_ready_executions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_ready_executions
    ADD CONSTRAINT solid_queue_ready_executions_pkey PRIMARY KEY (id);


--
-- Name: solid_queue_recurring_executions solid_queue_recurring_executions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_recurring_executions
    ADD CONSTRAINT solid_queue_recurring_executions_pkey PRIMARY KEY (id);


--
-- Name: solid_queue_recurring_tasks solid_queue_recurring_tasks_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_recurring_tasks
    ADD CONSTRAINT solid_queue_recurring_tasks_pkey PRIMARY KEY (id);


--
-- Name: solid_queue_scheduled_executions solid_queue_scheduled_executions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_scheduled_executions
    ADD CONSTRAINT solid_queue_scheduled_executions_pkey PRIMARY KEY (id);


--
-- Name: solid_queue_semaphores solid_queue_semaphores_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_semaphores
    ADD CONSTRAINT solid_queue_semaphores_pkey PRIMARY KEY (id);


--
-- Name: idx_on_organization_id_order_line_id_ea49188de0; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_on_organization_id_order_line_id_ea49188de0 ON public.purchasing_receipt_lines USING btree (organization_id, order_line_id);


--
-- Name: idx_on_organization_id_subject_type_subject_id_2d8753274e; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_on_organization_id_subject_type_subject_id_2d8753274e ON public.audit_events USING btree (organization_id, subject_type, subject_id);


--
-- Name: index_audit_events_on_actor_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_audit_events_on_actor_user_id ON public.audit_events USING btree (actor_user_id);


--
-- Name: index_audit_events_on_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_audit_events_on_organization_id ON public.audit_events USING btree (organization_id);


--
-- Name: index_audit_events_on_organization_id_and_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_audit_events_on_organization_id_and_created_at ON public.audit_events USING btree (organization_id, created_at);


--
-- Name: index_catalog_categories_on_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_catalog_categories_on_organization_id ON public.catalog_categories USING btree (organization_id);


--
-- Name: index_catalog_categories_on_organization_id_and_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_catalog_categories_on_organization_id_and_id ON public.catalog_categories USING btree (organization_id, id);


--
-- Name: index_catalog_categories_on_organization_id_and_lower_name; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_catalog_categories_on_organization_id_and_lower_name ON public.catalog_categories USING btree (organization_id, lower((name)::text));


--
-- Name: index_catalog_partners_on_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_catalog_partners_on_organization_id ON public.catalog_partners USING btree (organization_id);


--
-- Name: index_catalog_partners_on_organization_id_and_document_number; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_catalog_partners_on_organization_id_and_document_number ON public.catalog_partners USING btree (organization_id, document_number);


--
-- Name: index_catalog_partners_on_organization_id_and_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_catalog_partners_on_organization_id_and_id ON public.catalog_partners USING btree (organization_id, id);


--
-- Name: index_catalog_products_on_category_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_catalog_products_on_category_id ON public.catalog_products USING btree (category_id);


--
-- Name: index_catalog_products_on_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_catalog_products_on_organization_id ON public.catalog_products USING btree (organization_id);


--
-- Name: index_catalog_products_on_organization_id_and_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_catalog_products_on_organization_id_and_id ON public.catalog_products USING btree (organization_id, id);


--
-- Name: index_catalog_products_on_organization_id_and_lower_sku; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_catalog_products_on_organization_id_and_lower_sku ON public.catalog_products USING btree (organization_id, lower((sku)::text));


--
-- Name: index_catalog_products_on_stock_unit_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_catalog_products_on_stock_unit_id ON public.catalog_products USING btree (stock_unit_id);


--
-- Name: index_catalog_unit_conversions_on_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_catalog_unit_conversions_on_organization_id ON public.catalog_unit_conversions USING btree (organization_id);


--
-- Name: index_catalog_unit_conversions_on_product_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_catalog_unit_conversions_on_product_id ON public.catalog_unit_conversions USING btree (product_id);


--
-- Name: index_catalog_unit_conversions_on_purchase_unit_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_catalog_unit_conversions_on_purchase_unit_id ON public.catalog_unit_conversions USING btree (purchase_unit_id);


--
-- Name: index_catalog_units_on_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_catalog_units_on_organization_id ON public.catalog_units USING btree (organization_id);


--
-- Name: index_catalog_units_on_organization_id_and_code; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_catalog_units_on_organization_id_and_code ON public.catalog_units USING btree (organization_id, code);


--
-- Name: index_catalog_units_on_organization_id_and_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_catalog_units_on_organization_id_and_id ON public.catalog_units USING btree (organization_id, id);


--
-- Name: index_document_counters_on_organization_and_kind; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_document_counters_on_organization_and_kind ON public.document_counters USING btree (organization_id, kind);


--
-- Name: index_document_counters_on_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_document_counters_on_organization_id ON public.document_counters USING btree (organization_id);


--
-- Name: index_finance_installments_on_organization_and_due_on; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_finance_installments_on_organization_and_due_on ON public.finance_installments USING btree (organization_id, due_on);


--
-- Name: index_finance_installments_on_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_finance_installments_on_organization_id ON public.finance_installments USING btree (organization_id);


--
-- Name: index_finance_installments_on_title_and_number; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_finance_installments_on_title_and_number ON public.finance_installments USING btree (title_id, number);


--
-- Name: index_finance_titles_on_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_finance_titles_on_organization_id ON public.finance_titles USING btree (organization_id);


--
-- Name: index_finance_titles_on_organization_id_and_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_finance_titles_on_organization_id_and_id ON public.finance_titles USING btree (organization_id, id);


--
-- Name: index_finance_titles_on_organization_id_and_kind_and_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_finance_titles_on_organization_id_and_kind_and_status ON public.finance_titles USING btree (organization_id, kind, status);


--
-- Name: index_finance_titles_on_receipt_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_finance_titles_on_receipt_id ON public.finance_titles USING btree (receipt_id) WHERE (receipt_id IS NOT NULL);


--
-- Name: index_idempotency_keys_on_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_idempotency_keys_on_created_at ON public.idempotency_keys USING btree (created_at);


--
-- Name: index_idempotency_keys_on_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_idempotency_keys_on_organization_id ON public.idempotency_keys USING btree (organization_id);


--
-- Name: index_idempotency_keys_on_organization_user_and_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_idempotency_keys_on_organization_user_and_key ON public.idempotency_keys USING btree (organization_id, user_id, key);


--
-- Name: index_idempotency_keys_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_idempotency_keys_on_user_id ON public.idempotency_keys USING btree (user_id);


--
-- Name: index_identity_invitations_on_accepted_by_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_identity_invitations_on_accepted_by_user_id ON public.identity_invitations USING btree (accepted_by_user_id);


--
-- Name: index_identity_invitations_on_invited_by_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_identity_invitations_on_invited_by_user_id ON public.identity_invitations USING btree (invited_by_user_id);


--
-- Name: index_identity_invitations_on_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_identity_invitations_on_organization_id ON public.identity_invitations USING btree (organization_id);


--
-- Name: index_identity_invitations_on_organization_id_and_email; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_identity_invitations_on_organization_id_and_email ON public.identity_invitations USING btree (organization_id, email);


--
-- Name: index_identity_invitations_on_token_digest; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_identity_invitations_on_token_digest ON public.identity_invitations USING btree (token_digest);


--
-- Name: index_identity_memberships_on_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_identity_memberships_on_organization_id ON public.identity_memberships USING btree (organization_id);


--
-- Name: index_identity_memberships_on_organization_id_and_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_identity_memberships_on_organization_id_and_user_id ON public.identity_memberships USING btree (organization_id, user_id);


--
-- Name: index_identity_memberships_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_identity_memberships_on_user_id ON public.identity_memberships USING btree (user_id);


--
-- Name: index_identity_sessions_on_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_identity_sessions_on_organization_id ON public.identity_sessions USING btree (organization_id);


--
-- Name: index_identity_sessions_on_token_digest; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_identity_sessions_on_token_digest ON public.identity_sessions USING btree (token_digest);


--
-- Name: index_identity_sessions_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_identity_sessions_on_user_id ON public.identity_sessions USING btree (user_id);


--
-- Name: index_identity_users_on_lower_email; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_identity_users_on_lower_email ON public.identity_users USING btree (lower((email)::text));


--
-- Name: index_inventory_balances_on_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_inventory_balances_on_organization_id ON public.inventory_balances USING btree (organization_id);


--
-- Name: index_inventory_balances_on_organization_id_and_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_inventory_balances_on_organization_id_and_id ON public.inventory_balances USING btree (organization_id, id);


--
-- Name: index_inventory_balances_on_organization_id_and_warehouse_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_inventory_balances_on_organization_id_and_warehouse_id ON public.inventory_balances USING btree (organization_id, warehouse_id);


--
-- Name: index_inventory_balances_on_organization_product_and_warehouse; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_inventory_balances_on_organization_product_and_warehouse ON public.inventory_balances USING btree (organization_id, product_id, warehouse_id);


--
-- Name: index_inventory_movements_on_actor_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_inventory_movements_on_actor_user_id ON public.inventory_movements USING btree (actor_user_id);


--
-- Name: index_inventory_movements_on_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_inventory_movements_on_organization_id ON public.inventory_movements USING btree (organization_id);


--
-- Name: index_inventory_movements_on_organization_id_and_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_inventory_movements_on_organization_id_and_created_at ON public.inventory_movements USING btree (organization_id, created_at);


--
-- Name: index_inventory_movements_on_organization_id_and_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_inventory_movements_on_organization_id_and_id ON public.inventory_movements USING btree (organization_id, id);


--
-- Name: index_inventory_movements_on_organization_product_and_time; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_inventory_movements_on_organization_product_and_time ON public.inventory_movements USING btree (organization_id, product_id, created_at);


--
-- Name: index_inventory_movements_on_organization_warehouse_and_time; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_inventory_movements_on_organization_warehouse_and_time ON public.inventory_movements USING btree (organization_id, warehouse_id, created_at);


--
-- Name: index_inventory_movements_on_receipt_line_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_inventory_movements_on_receipt_line_id ON public.inventory_movements USING btree (receipt_line_id) WHERE (receipt_line_id IS NOT NULL);


--
-- Name: index_inventory_warehouses_on_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_inventory_warehouses_on_organization_id ON public.inventory_warehouses USING btree (organization_id);


--
-- Name: index_inventory_warehouses_on_organization_id_and_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_inventory_warehouses_on_organization_id_and_id ON public.inventory_warehouses USING btree (organization_id, id);


--
-- Name: index_inventory_warehouses_on_organization_id_and_lower_name; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_inventory_warehouses_on_organization_id_and_lower_name ON public.inventory_warehouses USING btree (organization_id, lower((name)::text));


--
-- Name: index_purchasing_order_lines_on_order_id_and_position; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_purchasing_order_lines_on_order_id_and_position ON public.purchasing_order_lines USING btree (order_id, "position");


--
-- Name: index_purchasing_order_lines_on_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_purchasing_order_lines_on_organization_id ON public.purchasing_order_lines USING btree (organization_id);


--
-- Name: index_purchasing_order_lines_on_organization_id_and_product_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_purchasing_order_lines_on_organization_id_and_product_id ON public.purchasing_order_lines USING btree (organization_id, product_id);


--
-- Name: index_purchasing_order_lines_on_organization_order_and_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_purchasing_order_lines_on_organization_order_and_id ON public.purchasing_order_lines USING btree (organization_id, order_id, id);


--
-- Name: index_purchasing_orders_on_approved_by_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_purchasing_orders_on_approved_by_user_id ON public.purchasing_orders USING btree (approved_by_user_id);


--
-- Name: index_purchasing_orders_on_cancelled_by_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_purchasing_orders_on_cancelled_by_user_id ON public.purchasing_orders USING btree (cancelled_by_user_id);


--
-- Name: index_purchasing_orders_on_created_by_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_purchasing_orders_on_created_by_user_id ON public.purchasing_orders USING btree (created_by_user_id);


--
-- Name: index_purchasing_orders_on_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_purchasing_orders_on_organization_id ON public.purchasing_orders USING btree (organization_id);


--
-- Name: index_purchasing_orders_on_organization_id_and_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_purchasing_orders_on_organization_id_and_id ON public.purchasing_orders USING btree (organization_id, id);


--
-- Name: index_purchasing_orders_on_organization_id_and_number; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_purchasing_orders_on_organization_id_and_number ON public.purchasing_orders USING btree (organization_id, number);


--
-- Name: index_purchasing_orders_on_organization_id_and_supplier_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_purchasing_orders_on_organization_id_and_supplier_id ON public.purchasing_orders USING btree (organization_id, supplier_id);


--
-- Name: index_purchasing_orders_on_organization_status_and_number; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_purchasing_orders_on_organization_status_and_number ON public.purchasing_orders USING btree (organization_id, status, number);


--
-- Name: index_purchasing_receipt_lines_on_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_purchasing_receipt_lines_on_organization_id ON public.purchasing_receipt_lines USING btree (organization_id);


--
-- Name: index_purchasing_receipt_lines_on_organization_id_and_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_purchasing_receipt_lines_on_organization_id_and_id ON public.purchasing_receipt_lines USING btree (organization_id, id);


--
-- Name: index_purchasing_receipt_lines_on_receipt_and_order_line; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_purchasing_receipt_lines_on_receipt_and_order_line ON public.purchasing_receipt_lines USING btree (receipt_id, order_line_id);


--
-- Name: index_purchasing_receipts_on_created_by_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_purchasing_receipts_on_created_by_user_id ON public.purchasing_receipts USING btree (created_by_user_id);


--
-- Name: index_purchasing_receipts_on_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_purchasing_receipts_on_organization_id ON public.purchasing_receipts USING btree (organization_id);


--
-- Name: index_purchasing_receipts_on_organization_id_and_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_purchasing_receipts_on_organization_id_and_id ON public.purchasing_receipts USING btree (organization_id, id);


--
-- Name: index_purchasing_receipts_on_organization_id_and_number; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_purchasing_receipts_on_organization_id_and_number ON public.purchasing_receipts USING btree (organization_id, number);


--
-- Name: index_purchasing_receipts_on_organization_id_and_received_on; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_purchasing_receipts_on_organization_id_and_received_on ON public.purchasing_receipts USING btree (organization_id, received_on);


--
-- Name: index_purchasing_receipts_on_organization_order_and_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_purchasing_receipts_on_organization_order_and_id ON public.purchasing_receipts USING btree (organization_id, order_id, id);


--
-- Name: index_solid_cache_entries_on_byte_size; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_cache_entries_on_byte_size ON public.solid_cache_entries USING btree (byte_size);


--
-- Name: index_solid_cache_entries_on_key_hash; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_solid_cache_entries_on_key_hash ON public.solid_cache_entries USING btree (key_hash);


--
-- Name: index_solid_cache_entries_on_key_hash_and_byte_size; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_cache_entries_on_key_hash_and_byte_size ON public.solid_cache_entries USING btree (key_hash, byte_size);


--
-- Name: index_solid_queue_batch_executions_on_batch_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_queue_batch_executions_on_batch_id ON public.solid_queue_batch_executions USING btree (batch_id);


--
-- Name: index_solid_queue_batch_executions_on_job_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_solid_queue_batch_executions_on_job_id ON public.solid_queue_batch_executions USING btree (job_id);


--
-- Name: index_solid_queue_batches_on_active_job_batch_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_solid_queue_batches_on_active_job_batch_id ON public.solid_queue_batches USING btree (active_job_batch_id);


--
-- Name: index_solid_queue_batches_on_finished_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_queue_batches_on_finished_at ON public.solid_queue_batches USING btree (finished_at);


--
-- Name: index_solid_queue_blocked_executions_for_maintenance; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_queue_blocked_executions_for_maintenance ON public.solid_queue_blocked_executions USING btree (expires_at, concurrency_key);


--
-- Name: index_solid_queue_blocked_executions_for_release; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_queue_blocked_executions_for_release ON public.solid_queue_blocked_executions USING btree (concurrency_key, priority, job_id);


--
-- Name: index_solid_queue_blocked_executions_on_job_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_solid_queue_blocked_executions_on_job_id ON public.solid_queue_blocked_executions USING btree (job_id);


--
-- Name: index_solid_queue_claimed_executions_on_job_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_solid_queue_claimed_executions_on_job_id ON public.solid_queue_claimed_executions USING btree (job_id);


--
-- Name: index_solid_queue_claimed_executions_on_process_id_and_job_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_queue_claimed_executions_on_process_id_and_job_id ON public.solid_queue_claimed_executions USING btree (process_id, job_id);


--
-- Name: index_solid_queue_dispatch_all; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_queue_dispatch_all ON public.solid_queue_scheduled_executions USING btree (scheduled_at, priority, job_id);


--
-- Name: index_solid_queue_failed_executions_on_job_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_solid_queue_failed_executions_on_job_id ON public.solid_queue_failed_executions USING btree (job_id);


--
-- Name: index_solid_queue_jobs_for_alerting; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_queue_jobs_for_alerting ON public.solid_queue_jobs USING btree (scheduled_at, finished_at);


--
-- Name: index_solid_queue_jobs_for_filtering; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_queue_jobs_for_filtering ON public.solid_queue_jobs USING btree (queue_name, finished_at);


--
-- Name: index_solid_queue_jobs_on_active_job_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_queue_jobs_on_active_job_id ON public.solid_queue_jobs USING btree (active_job_id);


--
-- Name: index_solid_queue_jobs_on_batch_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_queue_jobs_on_batch_id ON public.solid_queue_jobs USING btree (batch_id);


--
-- Name: index_solid_queue_jobs_on_class_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_queue_jobs_on_class_name ON public.solid_queue_jobs USING btree (class_name);


--
-- Name: index_solid_queue_jobs_on_finished_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_queue_jobs_on_finished_at ON public.solid_queue_jobs USING btree (finished_at);


--
-- Name: index_solid_queue_pauses_on_queue_name; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_solid_queue_pauses_on_queue_name ON public.solid_queue_pauses USING btree (queue_name);


--
-- Name: index_solid_queue_poll_all; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_queue_poll_all ON public.solid_queue_ready_executions USING btree (priority, job_id);


--
-- Name: index_solid_queue_poll_by_queue; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_queue_poll_by_queue ON public.solid_queue_ready_executions USING btree (queue_name, priority, job_id);


--
-- Name: index_solid_queue_processes_on_last_heartbeat_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_queue_processes_on_last_heartbeat_at ON public.solid_queue_processes USING btree (last_heartbeat_at);


--
-- Name: index_solid_queue_processes_on_name_and_supervisor_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_solid_queue_processes_on_name_and_supervisor_id ON public.solid_queue_processes USING btree (name, supervisor_id);


--
-- Name: index_solid_queue_processes_on_supervisor_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_queue_processes_on_supervisor_id ON public.solid_queue_processes USING btree (supervisor_id);


--
-- Name: index_solid_queue_ready_executions_on_job_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_solid_queue_ready_executions_on_job_id ON public.solid_queue_ready_executions USING btree (job_id);


--
-- Name: index_solid_queue_recurring_executions_on_job_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_solid_queue_recurring_executions_on_job_id ON public.solid_queue_recurring_executions USING btree (job_id);


--
-- Name: index_solid_queue_recurring_executions_on_task_key_and_run_at; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_solid_queue_recurring_executions_on_task_key_and_run_at ON public.solid_queue_recurring_executions USING btree (task_key, run_at);


--
-- Name: index_solid_queue_recurring_tasks_on_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_solid_queue_recurring_tasks_on_key ON public.solid_queue_recurring_tasks USING btree (key);


--
-- Name: index_solid_queue_recurring_tasks_on_static; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_queue_recurring_tasks_on_static ON public.solid_queue_recurring_tasks USING btree (static);


--
-- Name: index_solid_queue_scheduled_executions_on_job_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_solid_queue_scheduled_executions_on_job_id ON public.solid_queue_scheduled_executions USING btree (job_id);


--
-- Name: index_solid_queue_semaphores_on_expires_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_queue_semaphores_on_expires_at ON public.solid_queue_semaphores USING btree (expires_at);


--
-- Name: index_solid_queue_semaphores_on_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_solid_queue_semaphores_on_key ON public.solid_queue_semaphores USING btree (key);


--
-- Name: index_solid_queue_semaphores_on_key_and_value; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_queue_semaphores_on_key_and_value ON public.solid_queue_semaphores USING btree (key, value);


--
-- Name: audit_events audit_events_append_only; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER audit_events_append_only BEFORE DELETE OR UPDATE ON public.audit_events FOR EACH ROW EXECUTE FUNCTION public.audit_events_append_only();


--
-- Name: inventory_movements inventory_movements_append_only; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER inventory_movements_append_only BEFORE DELETE OR UPDATE ON public.inventory_movements FOR EACH ROW EXECUTE FUNCTION public.inventory_movements_append_only();


--
-- Name: inventory_movements inventory_movements_no_truncate; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER inventory_movements_no_truncate BEFORE TRUNCATE ON public.inventory_movements FOR EACH STATEMENT EXECUTE FUNCTION public.inventory_movements_no_truncate();


--
-- Name: purchasing_order_lines purchasing_order_lines_freeze; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER purchasing_order_lines_freeze BEFORE INSERT OR DELETE OR UPDATE ON public.purchasing_order_lines FOR EACH ROW EXECUTE FUNCTION public.purchasing_order_lines_freeze();


--
-- Name: purchasing_receipt_lines purchasing_receipt_lines_append_only; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER purchasing_receipt_lines_append_only BEFORE DELETE OR UPDATE ON public.purchasing_receipt_lines FOR EACH ROW EXECUTE FUNCTION public.purchasing_receipts_append_only();


--
-- Name: purchasing_receipt_lines purchasing_receipt_lines_no_truncate; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER purchasing_receipt_lines_no_truncate BEFORE TRUNCATE ON public.purchasing_receipt_lines FOR EACH STATEMENT EXECUTE FUNCTION public.purchasing_receipts_no_truncate();


--
-- Name: purchasing_receipts purchasing_receipts_append_only; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER purchasing_receipts_append_only BEFORE DELETE OR UPDATE ON public.purchasing_receipts FOR EACH ROW EXECUTE FUNCTION public.purchasing_receipts_append_only();


--
-- Name: purchasing_receipts purchasing_receipts_no_truncate; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER purchasing_receipts_no_truncate BEFORE TRUNCATE ON public.purchasing_receipts FOR EACH STATEMENT EXECUTE FUNCTION public.purchasing_receipts_no_truncate();


--
-- Name: catalog_products fk_catalog_products_category_same_organization; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.catalog_products
    ADD CONSTRAINT fk_catalog_products_category_same_organization FOREIGN KEY (organization_id, category_id) REFERENCES public.catalog_categories(organization_id, id);


--
-- Name: catalog_products fk_catalog_products_stock_unit_same_organization; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.catalog_products
    ADD CONSTRAINT fk_catalog_products_stock_unit_same_organization FOREIGN KEY (organization_id, stock_unit_id) REFERENCES public.catalog_units(organization_id, id);


--
-- Name: catalog_unit_conversions fk_catalog_unit_conversions_product_same_organization; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.catalog_unit_conversions
    ADD CONSTRAINT fk_catalog_unit_conversions_product_same_organization FOREIGN KEY (organization_id, product_id) REFERENCES public.catalog_products(organization_id, id);


--
-- Name: catalog_unit_conversions fk_catalog_unit_conversions_purchase_unit_same_organization; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.catalog_unit_conversions
    ADD CONSTRAINT fk_catalog_unit_conversions_purchase_unit_same_organization FOREIGN KEY (organization_id, purchase_unit_id) REFERENCES public.catalog_units(organization_id, id);


--
-- Name: finance_installments fk_finance_installments_title_same_organization; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.finance_installments
    ADD CONSTRAINT fk_finance_installments_title_same_organization FOREIGN KEY (organization_id, title_id) REFERENCES public.finance_titles(organization_id, id);


--
-- Name: finance_titles fk_finance_titles_partner_same_organization; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.finance_titles
    ADD CONSTRAINT fk_finance_titles_partner_same_organization FOREIGN KEY (organization_id, partner_id) REFERENCES public.catalog_partners(organization_id, id);


--
-- Name: finance_titles fk_finance_titles_receipt_same_organization; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.finance_titles
    ADD CONSTRAINT fk_finance_titles_receipt_same_organization FOREIGN KEY (organization_id, receipt_id) REFERENCES public.purchasing_receipts(organization_id, id);


--
-- Name: inventory_balances fk_inventory_balances_product_same_organization; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventory_balances
    ADD CONSTRAINT fk_inventory_balances_product_same_organization FOREIGN KEY (organization_id, product_id) REFERENCES public.catalog_products(organization_id, id);


--
-- Name: inventory_balances fk_inventory_balances_warehouse_same_organization; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventory_balances
    ADD CONSTRAINT fk_inventory_balances_warehouse_same_organization FOREIGN KEY (organization_id, warehouse_id) REFERENCES public.inventory_warehouses(organization_id, id);


--
-- Name: inventory_movements fk_inventory_movements_product_same_organization; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventory_movements
    ADD CONSTRAINT fk_inventory_movements_product_same_organization FOREIGN KEY (organization_id, product_id) REFERENCES public.catalog_products(organization_id, id);


--
-- Name: inventory_movements fk_inventory_movements_receipt_line_same_organization; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventory_movements
    ADD CONSTRAINT fk_inventory_movements_receipt_line_same_organization FOREIGN KEY (organization_id, receipt_line_id) REFERENCES public.purchasing_receipt_lines(organization_id, id);


--
-- Name: inventory_movements fk_inventory_movements_warehouse_same_organization; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventory_movements
    ADD CONSTRAINT fk_inventory_movements_warehouse_same_organization FOREIGN KEY (organization_id, warehouse_id) REFERENCES public.inventory_warehouses(organization_id, id);


--
-- Name: purchasing_order_lines fk_purchasing_order_lines_order_same_organization; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.purchasing_order_lines
    ADD CONSTRAINT fk_purchasing_order_lines_order_same_organization FOREIGN KEY (organization_id, order_id) REFERENCES public.purchasing_orders(organization_id, id);


--
-- Name: purchasing_order_lines fk_purchasing_order_lines_product_same_organization; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.purchasing_order_lines
    ADD CONSTRAINT fk_purchasing_order_lines_product_same_organization FOREIGN KEY (organization_id, product_id) REFERENCES public.catalog_products(organization_id, id);


--
-- Name: purchasing_order_lines fk_purchasing_order_lines_unit_same_organization; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.purchasing_order_lines
    ADD CONSTRAINT fk_purchasing_order_lines_unit_same_organization FOREIGN KEY (organization_id, purchase_unit_id) REFERENCES public.catalog_units(organization_id, id);


--
-- Name: purchasing_orders fk_purchasing_orders_supplier_same_organization; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.purchasing_orders
    ADD CONSTRAINT fk_purchasing_orders_supplier_same_organization FOREIGN KEY (organization_id, supplier_id) REFERENCES public.catalog_partners(organization_id, id);


--
-- Name: purchasing_receipt_lines fk_purchasing_receipt_lines_order_line_same_order; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.purchasing_receipt_lines
    ADD CONSTRAINT fk_purchasing_receipt_lines_order_line_same_order FOREIGN KEY (organization_id, order_id, order_line_id) REFERENCES public.purchasing_order_lines(organization_id, order_id, id);


--
-- Name: purchasing_receipt_lines fk_purchasing_receipt_lines_product_same_organization; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.purchasing_receipt_lines
    ADD CONSTRAINT fk_purchasing_receipt_lines_product_same_organization FOREIGN KEY (organization_id, product_id) REFERENCES public.catalog_products(organization_id, id);


--
-- Name: purchasing_receipt_lines fk_purchasing_receipt_lines_receipt_same_order; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.purchasing_receipt_lines
    ADD CONSTRAINT fk_purchasing_receipt_lines_receipt_same_order FOREIGN KEY (organization_id, order_id, receipt_id) REFERENCES public.purchasing_receipts(organization_id, order_id, id);


--
-- Name: purchasing_receipts fk_purchasing_receipts_order_same_organization; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.purchasing_receipts
    ADD CONSTRAINT fk_purchasing_receipts_order_same_organization FOREIGN KEY (organization_id, order_id) REFERENCES public.purchasing_orders(organization_id, id);


--
-- Name: purchasing_receipts fk_purchasing_receipts_warehouse_same_organization; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.purchasing_receipts
    ADD CONSTRAINT fk_purchasing_receipts_warehouse_same_organization FOREIGN KEY (organization_id, warehouse_id) REFERENCES public.inventory_warehouses(organization_id, id);


--
-- Name: finance_titles fk_rails_14553adfa1; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.finance_titles
    ADD CONSTRAINT fk_rails_14553adfa1 FOREIGN KEY (organization_id) REFERENCES public.identity_organizations(id);


--
-- Name: idempotency_keys fk_rails_149452d765; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.idempotency_keys
    ADD CONSTRAINT fk_rails_149452d765 FOREIGN KEY (organization_id) REFERENCES public.identity_organizations(id);


--
-- Name: catalog_products fk_rails_153251c57a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.catalog_products
    ADD CONSTRAINT fk_rails_153251c57a FOREIGN KEY (organization_id) REFERENCES public.identity_organizations(id);


--
-- Name: catalog_unit_conversions fk_rails_272b5ade05; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.catalog_unit_conversions
    ADD CONSTRAINT fk_rails_272b5ade05 FOREIGN KEY (product_id) REFERENCES public.catalog_products(id);


--
-- Name: catalog_categories fk_rails_2ca6796229; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.catalog_categories
    ADD CONSTRAINT fk_rails_2ca6796229 FOREIGN KEY (organization_id) REFERENCES public.identity_organizations(id);


--
-- Name: audit_events fk_rails_2e3720791c; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_events
    ADD CONSTRAINT fk_rails_2e3720791c FOREIGN KEY (actor_user_id) REFERENCES public.identity_users(id);


--
-- Name: solid_queue_recurring_executions fk_rails_318a5533ed; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_recurring_executions
    ADD CONSTRAINT fk_rails_318a5533ed FOREIGN KEY (job_id) REFERENCES public.solid_queue_jobs(id) ON DELETE CASCADE;


--
-- Name: identity_memberships fk_rails_3361feb891; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.identity_memberships
    ADD CONSTRAINT fk_rails_3361feb891 FOREIGN KEY (user_id) REFERENCES public.identity_users(id);


--
-- Name: solid_queue_failed_executions fk_rails_39bbc7a631; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_failed_executions
    ADD CONSTRAINT fk_rails_39bbc7a631 FOREIGN KEY (job_id) REFERENCES public.solid_queue_jobs(id) ON DELETE CASCADE;


--
-- Name: purchasing_order_lines fk_rails_3e29fa7f2b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.purchasing_order_lines
    ADD CONSTRAINT fk_rails_3e29fa7f2b FOREIGN KEY (organization_id) REFERENCES public.identity_organizations(id);


--
-- Name: identity_invitations fk_rails_40f5359788; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.identity_invitations
    ADD CONSTRAINT fk_rails_40f5359788 FOREIGN KEY (accepted_by_user_id) REFERENCES public.identity_users(id);


--
-- Name: purchasing_orders fk_rails_429df39186; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.purchasing_orders
    ADD CONSTRAINT fk_rails_429df39186 FOREIGN KEY (approved_by_user_id) REFERENCES public.identity_users(id);


--
-- Name: identity_invitations fk_rails_4b6fd2766b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.identity_invitations
    ADD CONSTRAINT fk_rails_4b6fd2766b FOREIGN KEY (organization_id) REFERENCES public.identity_organizations(id);


--
-- Name: solid_queue_blocked_executions fk_rails_4cd34e2228; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_blocked_executions
    ADD CONSTRAINT fk_rails_4cd34e2228 FOREIGN KEY (job_id) REFERENCES public.solid_queue_jobs(id) ON DELETE CASCADE;


--
-- Name: purchasing_orders fk_rails_569be89051; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.purchasing_orders
    ADD CONSTRAINT fk_rails_569be89051 FOREIGN KEY (cancelled_by_user_id) REFERENCES public.identity_users(id);


--
-- Name: inventory_movements fk_rails_5a348afa95; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventory_movements
    ADD CONSTRAINT fk_rails_5a348afa95 FOREIGN KEY (organization_id) REFERENCES public.identity_organizations(id);


--
-- Name: catalog_products fk_rails_603098440a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.catalog_products
    ADD CONSTRAINT fk_rails_603098440a FOREIGN KEY (stock_unit_id) REFERENCES public.catalog_units(id);


--
-- Name: document_counters fk_rails_608f5718eb; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.document_counters
    ADD CONSTRAINT fk_rails_608f5718eb FOREIGN KEY (organization_id) REFERENCES public.identity_organizations(id);


--
-- Name: inventory_movements fk_rails_64b9a559ef; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventory_movements
    ADD CONSTRAINT fk_rails_64b9a559ef FOREIGN KEY (actor_user_id) REFERENCES public.identity_users(id);


--
-- Name: catalog_unit_conversions fk_rails_72bddd13cd; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.catalog_unit_conversions
    ADD CONSTRAINT fk_rails_72bddd13cd FOREIGN KEY (organization_id) REFERENCES public.identity_organizations(id);


--
-- Name: solid_queue_batch_executions fk_rails_7c5e073422; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_batch_executions
    ADD CONSTRAINT fk_rails_7c5e073422 FOREIGN KEY (batch_id) REFERENCES public.solid_queue_batches(id) ON DELETE CASCADE;


--
-- Name: identity_sessions fk_rails_7dd5dea022; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.identity_sessions
    ADD CONSTRAINT fk_rails_7dd5dea022 FOREIGN KEY (user_id) REFERENCES public.identity_users(id);


--
-- Name: catalog_unit_conversions fk_rails_8081f8c4a5; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.catalog_unit_conversions
    ADD CONSTRAINT fk_rails_8081f8c4a5 FOREIGN KEY (purchase_unit_id) REFERENCES public.catalog_units(id);


--
-- Name: solid_queue_ready_executions fk_rails_81fcbd66af; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_ready_executions
    ADD CONSTRAINT fk_rails_81fcbd66af FOREIGN KEY (job_id) REFERENCES public.solid_queue_jobs(id) ON DELETE CASCADE;


--
-- Name: identity_sessions fk_rails_83ac02eea5; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.identity_sessions
    ADD CONSTRAINT fk_rails_83ac02eea5 FOREIGN KEY (organization_id) REFERENCES public.identity_organizations(id);


--
-- Name: purchasing_orders fk_rails_8868aedce6; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.purchasing_orders
    ADD CONSTRAINT fk_rails_8868aedce6 FOREIGN KEY (organization_id) REFERENCES public.identity_organizations(id);


--
-- Name: purchasing_orders fk_rails_88ff1f8367; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.purchasing_orders
    ADD CONSTRAINT fk_rails_88ff1f8367 FOREIGN KEY (created_by_user_id) REFERENCES public.identity_users(id);


--
-- Name: identity_memberships fk_rails_8fec4ac7b9; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.identity_memberships
    ADD CONSTRAINT fk_rails_8fec4ac7b9 FOREIGN KEY (organization_id) REFERENCES public.identity_organizations(id);


--
-- Name: purchasing_receipt_lines fk_rails_922e9f343a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.purchasing_receipt_lines
    ADD CONSTRAINT fk_rails_922e9f343a FOREIGN KEY (organization_id) REFERENCES public.identity_organizations(id);


--
-- Name: idempotency_keys fk_rails_96c4cbd0a9; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.idempotency_keys
    ADD CONSTRAINT fk_rails_96c4cbd0a9 FOREIGN KEY (user_id) REFERENCES public.identity_users(id);


--
-- Name: identity_invitations fk_rails_9cea4cebf4; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.identity_invitations
    ADD CONSTRAINT fk_rails_9cea4cebf4 FOREIGN KEY (invited_by_user_id) REFERENCES public.identity_users(id);


--
-- Name: solid_queue_claimed_executions fk_rails_9cfe4d4944; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_claimed_executions
    ADD CONSTRAINT fk_rails_9cfe4d4944 FOREIGN KEY (job_id) REFERENCES public.solid_queue_jobs(id) ON DELETE CASCADE;


--
-- Name: inventory_balances fk_rails_b2e5fe6c5d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventory_balances
    ADD CONSTRAINT fk_rails_b2e5fe6c5d FOREIGN KEY (organization_id) REFERENCES public.identity_organizations(id);


--
-- Name: solid_queue_batch_executions fk_rails_bc9f981155; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_batch_executions
    ADD CONSTRAINT fk_rails_bc9f981155 FOREIGN KEY (job_id) REFERENCES public.solid_queue_jobs(id) ON DELETE CASCADE;


--
-- Name: audit_events fk_rails_be0ed9e37f; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_events
    ADD CONSTRAINT fk_rails_be0ed9e37f FOREIGN KEY (organization_id) REFERENCES public.identity_organizations(id);


--
-- Name: solid_queue_scheduled_executions fk_rails_c4316f352d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_scheduled_executions
    ADD CONSTRAINT fk_rails_c4316f352d FOREIGN KEY (job_id) REFERENCES public.solid_queue_jobs(id) ON DELETE CASCADE;


--
-- Name: finance_installments fk_rails_cdb3f78607; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.finance_installments
    ADD CONSTRAINT fk_rails_cdb3f78607 FOREIGN KEY (organization_id) REFERENCES public.identity_organizations(id);


--
-- Name: inventory_warehouses fk_rails_df87fc6a51; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventory_warehouses
    ADD CONSTRAINT fk_rails_df87fc6a51 FOREIGN KEY (organization_id) REFERENCES public.identity_organizations(id);


--
-- Name: catalog_partners fk_rails_f241d52c95; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.catalog_partners
    ADD CONSTRAINT fk_rails_f241d52c95 FOREIGN KEY (organization_id) REFERENCES public.identity_organizations(id);


--
-- Name: purchasing_receipts fk_rails_f9fc25ff13; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.purchasing_receipts
    ADD CONSTRAINT fk_rails_f9fc25ff13 FOREIGN KEY (organization_id) REFERENCES public.identity_organizations(id);


--
-- Name: catalog_units fk_rails_fb5250d042; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.catalog_units
    ADD CONSTRAINT fk_rails_fb5250d042 FOREIGN KEY (organization_id) REFERENCES public.identity_organizations(id);


--
-- Name: purchasing_receipts fk_rails_fedc111e78; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.purchasing_receipts
    ADD CONSTRAINT fk_rails_fedc111e78 FOREIGN KEY (created_by_user_id) REFERENCES public.identity_users(id);


--
-- Name: audit_events; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.audit_events ENABLE ROW LEVEL SECURITY;

--
-- Name: audit_events audit_events_tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY audit_events_tenant_isolation ON public.audit_events USING ((organization_id = (NULLIF(current_setting('app.organization_id'::text, true), ''::text))::bigint)) WITH CHECK ((organization_id = (NULLIF(current_setting('app.organization_id'::text, true), ''::text))::bigint));


--
-- Name: catalog_categories; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.catalog_categories ENABLE ROW LEVEL SECURITY;

--
-- Name: catalog_categories catalog_categories_tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY catalog_categories_tenant_isolation ON public.catalog_categories USING ((organization_id = (NULLIF(current_setting('app.organization_id'::text, true), ''::text))::bigint)) WITH CHECK ((organization_id = (NULLIF(current_setting('app.organization_id'::text, true), ''::text))::bigint));


--
-- Name: catalog_partners; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.catalog_partners ENABLE ROW LEVEL SECURITY;

--
-- Name: catalog_partners catalog_partners_tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY catalog_partners_tenant_isolation ON public.catalog_partners USING ((organization_id = (NULLIF(current_setting('app.organization_id'::text, true), ''::text))::bigint)) WITH CHECK ((organization_id = (NULLIF(current_setting('app.organization_id'::text, true), ''::text))::bigint));


--
-- Name: catalog_products; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.catalog_products ENABLE ROW LEVEL SECURITY;

--
-- Name: catalog_products catalog_products_tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY catalog_products_tenant_isolation ON public.catalog_products USING ((organization_id = (NULLIF(current_setting('app.organization_id'::text, true), ''::text))::bigint)) WITH CHECK ((organization_id = (NULLIF(current_setting('app.organization_id'::text, true), ''::text))::bigint));


--
-- Name: catalog_unit_conversions; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.catalog_unit_conversions ENABLE ROW LEVEL SECURITY;

--
-- Name: catalog_unit_conversions catalog_unit_conversions_tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY catalog_unit_conversions_tenant_isolation ON public.catalog_unit_conversions USING ((organization_id = (NULLIF(current_setting('app.organization_id'::text, true), ''::text))::bigint)) WITH CHECK ((organization_id = (NULLIF(current_setting('app.organization_id'::text, true), ''::text))::bigint));


--
-- Name: catalog_units; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.catalog_units ENABLE ROW LEVEL SECURITY;

--
-- Name: catalog_units catalog_units_tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY catalog_units_tenant_isolation ON public.catalog_units USING ((organization_id = (NULLIF(current_setting('app.organization_id'::text, true), ''::text))::bigint)) WITH CHECK ((organization_id = (NULLIF(current_setting('app.organization_id'::text, true), ''::text))::bigint));


--
-- Name: document_counters; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.document_counters ENABLE ROW LEVEL SECURITY;

--
-- Name: document_counters document_counters_tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY document_counters_tenant_isolation ON public.document_counters USING ((organization_id = (NULLIF(current_setting('app.organization_id'::text, true), ''::text))::bigint)) WITH CHECK ((organization_id = (NULLIF(current_setting('app.organization_id'::text, true), ''::text))::bigint));


--
-- Name: finance_installments; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.finance_installments ENABLE ROW LEVEL SECURITY;

--
-- Name: finance_installments finance_installments_tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY finance_installments_tenant_isolation ON public.finance_installments USING ((organization_id = (NULLIF(current_setting('app.organization_id'::text, true), ''::text))::bigint)) WITH CHECK ((organization_id = (NULLIF(current_setting('app.organization_id'::text, true), ''::text))::bigint));


--
-- Name: finance_titles; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.finance_titles ENABLE ROW LEVEL SECURITY;

--
-- Name: finance_titles finance_titles_tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY finance_titles_tenant_isolation ON public.finance_titles USING ((organization_id = (NULLIF(current_setting('app.organization_id'::text, true), ''::text))::bigint)) WITH CHECK ((organization_id = (NULLIF(current_setting('app.organization_id'::text, true), ''::text))::bigint));


--
-- Name: idempotency_keys; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.idempotency_keys ENABLE ROW LEVEL SECURITY;

--
-- Name: idempotency_keys idempotency_keys_tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY idempotency_keys_tenant_isolation ON public.idempotency_keys USING ((organization_id = (NULLIF(current_setting('app.organization_id'::text, true), ''::text))::bigint)) WITH CHECK ((organization_id = (NULLIF(current_setting('app.organization_id'::text, true), ''::text))::bigint));


--
-- Name: identity_invitations; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.identity_invitations ENABLE ROW LEVEL SECURITY;

--
-- Name: identity_invitations identity_invitations_tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY identity_invitations_tenant_isolation ON public.identity_invitations USING ((organization_id = (NULLIF(current_setting('app.organization_id'::text, true), ''::text))::bigint)) WITH CHECK ((organization_id = (NULLIF(current_setting('app.organization_id'::text, true), ''::text))::bigint));


--
-- Name: inventory_balances; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.inventory_balances ENABLE ROW LEVEL SECURITY;

--
-- Name: inventory_balances inventory_balances_tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY inventory_balances_tenant_isolation ON public.inventory_balances USING ((organization_id = (NULLIF(current_setting('app.organization_id'::text, true), ''::text))::bigint)) WITH CHECK ((organization_id = (NULLIF(current_setting('app.organization_id'::text, true), ''::text))::bigint));


--
-- Name: inventory_movements; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.inventory_movements ENABLE ROW LEVEL SECURITY;

--
-- Name: inventory_movements inventory_movements_tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY inventory_movements_tenant_isolation ON public.inventory_movements USING ((organization_id = (NULLIF(current_setting('app.organization_id'::text, true), ''::text))::bigint)) WITH CHECK ((organization_id = (NULLIF(current_setting('app.organization_id'::text, true), ''::text))::bigint));


--
-- Name: inventory_warehouses; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.inventory_warehouses ENABLE ROW LEVEL SECURITY;

--
-- Name: inventory_warehouses inventory_warehouses_tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY inventory_warehouses_tenant_isolation ON public.inventory_warehouses USING ((organization_id = (NULLIF(current_setting('app.organization_id'::text, true), ''::text))::bigint)) WITH CHECK ((organization_id = (NULLIF(current_setting('app.organization_id'::text, true), ''::text))::bigint));


--
-- Name: purchasing_order_lines; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.purchasing_order_lines ENABLE ROW LEVEL SECURITY;

--
-- Name: purchasing_order_lines purchasing_order_lines_tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY purchasing_order_lines_tenant_isolation ON public.purchasing_order_lines USING ((organization_id = (NULLIF(current_setting('app.organization_id'::text, true), ''::text))::bigint)) WITH CHECK ((organization_id = (NULLIF(current_setting('app.organization_id'::text, true), ''::text))::bigint));


--
-- Name: purchasing_orders; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.purchasing_orders ENABLE ROW LEVEL SECURITY;

--
-- Name: purchasing_orders purchasing_orders_tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY purchasing_orders_tenant_isolation ON public.purchasing_orders USING ((organization_id = (NULLIF(current_setting('app.organization_id'::text, true), ''::text))::bigint)) WITH CHECK ((organization_id = (NULLIF(current_setting('app.organization_id'::text, true), ''::text))::bigint));


--
-- Name: purchasing_receipt_lines; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.purchasing_receipt_lines ENABLE ROW LEVEL SECURITY;

--
-- Name: purchasing_receipt_lines purchasing_receipt_lines_tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY purchasing_receipt_lines_tenant_isolation ON public.purchasing_receipt_lines USING ((organization_id = (NULLIF(current_setting('app.organization_id'::text, true), ''::text))::bigint)) WITH CHECK ((organization_id = (NULLIF(current_setting('app.organization_id'::text, true), ''::text))::bigint));


--
-- Name: purchasing_receipts; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.purchasing_receipts ENABLE ROW LEVEL SECURITY;

--
-- Name: purchasing_receipts purchasing_receipts_tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY purchasing_receipts_tenant_isolation ON public.purchasing_receipts USING ((organization_id = (NULLIF(current_setting('app.organization_id'::text, true), ''::text))::bigint)) WITH CHECK ((organization_id = (NULLIF(current_setting('app.organization_id'::text, true), ''::text))::bigint));


--
-- PostgreSQL database dump complete
--

SET search_path TO "$user", public;

INSERT INTO "schema_migrations" (version) VALUES
('20260926160400'),
('20260926160300'),
('20260926160200'),
('20260926160100'),
('20260926160000'),
('20260926150200'),
('20260926150100'),
('20260926150000'),
('20260926140000'),
('20260926130000'),
('20260926120400'),
('20260926120300'),
('20260926120200'),
('20260926120100'),
('20260926120000'),
('20260926110000'),
('20260926100100'),
('20260926100000'),
('20260921110000'),
('20260921100000'),
('20260920130000'),
('20260920120000'),
('20260920110000'),
('20260920100000'),
('20260919120000'),
('20260919110000'),
('20260919100000'),
('20260919000002'),
('20260919000001');

