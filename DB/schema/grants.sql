do $$
begin
    if not exists (select 1 from pg_roles where rolname = 'inspector') then
        create role inspector login password 'NetoSQL2025';
    else
        alter role inspector login password 'NetoSQL2025';
    end if;
end
$$;

grant all privileges on schema rezyapova_food to inspector;
grant all privileges on all tables in schema rezyapova_food to inspector;
grant all privileges on all routines in schema rezyapova_food to inspector;
grant usage on type rezyapova_food.restaurant_status to inspector;
grant usage on type rezyapova_food.product_status to inspector;
grant usage on type rezyapova_food.courier_status to inspector;
grant usage on type rezyapova_food.order_status to inspector;
grant usage on type rezyapova_food.order_pay_status to inspector;
grant usage on type rezyapova_food.payment_status to inspector;
grant usage on type rezyapova_food.payment_type to inspector;
grant usage on type rezyapova_food.review_entity_type to inspector;

alter default privileges in schema rezyapova_food grant all privileges on tables to inspector;
alter default privileges in schema rezyapova_food grant all privileges on routines to inspector;
alter default privileges in schema rezyapova_food grant USAGE on types to inspector;

grant usage on schema exts to inspector;
grant execute on function exts.uuid_generate_v4() to inspector;

do $$
begin
    if not has_schema_privilege('inspector', 'information_schema', 'USAGE')
       or not has_schema_privilege('inspector', 'pg_catalog', 'USAGE') then
        raise exception 'У inspector нет USAGE на information_schema / pg_catalog';
    end if;
end
$$;

