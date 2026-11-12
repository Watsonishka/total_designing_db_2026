set search_path to rezyapova_food, exts;

create or replace function rating_change()
returns trigger
language plpgsql
set search_path = rezyapova_food, exts
as $$
begin
    if tg_op in ('UPDATE', 'DELETE') then
        if old.entity_type = 'блюдо' then
            update product
            set rating = (select round(avg(r.rating), 2)
                          from review r
                          where r.entity_type = 'блюдо' and r.entity_id = old.entity_id)
            where product_id = old.entity_id;
        elsif old.entity_type = 'ресторан' then
            update restaurant
            set rating = (select round(avg(r.rating), 2)
                          from review r
                          where r.entity_type = 'ресторан' and r.entity_id = old.entity_id)
            where restaurant_id = old.entity_id;
        end if;
    end if;
    if tg_op = 'INSERT'
       or (tg_op = 'UPDATE'
           and (new.entity_type <> old.entity_type or new.entity_id <> old.entity_id)) then
        if new.entity_type = 'блюдо' then
            update product
            set rating = (select round(avg(r.rating), 2)
                          from review r
                          where r.entity_type = 'блюдо' and r.entity_id = new.entity_id)
            where product_id = new.entity_id;
        elsif new.entity_type = 'ресторан' then
            update restaurant
            set rating = (select round(avg(r.rating), 2)
                          from review r
                          where r.entity_type = 'ресторан' and r.entity_id = new.entity_id)
            where restaurant_id = new.entity_id;
        end if;
    end if;
    return null;
end;
$$;

create trigger review_rating_change
after insert or update or delete on review
for each row execute function rating_change();

create or replace function check_review_target()
returns trigger
language plpgsql
set search_path = rezyapova_food, exts
as $$
begin
    if new.entity_type = 'ресторан' then
        if not exists (select 1 from "order"
                       where order_id = new.order_id and restaurant_id = new.entity_id) then
            raise exception 'Отзыв на ресторан %: это не ресторан заказа %',
                new.entity_id, new.order_id;
        end if;
    elsif new.entity_type = 'блюдо' then
        if not exists (select 1 from order_structure
                       where order_id = new.order_id and product_id = new.entity_id) then
            raise exception 'Отзыв на блюдо %: этого блюда нет в заказе %',
                new.entity_id, new.order_id;
        end if;
    elsif new.entity_type = 'заказ' then
        if new.entity_id <> new.order_id then
            raise exception 'Отзыв на заказ: entity_id (%) должен совпадать с order_id (%)',
                new.entity_id, new.order_id;
        end if;
    end if;
    return new;
end;
$$;

create trigger review_target_check
before insert or update of order_id, entity_type, entity_id on review
for each row execute function check_review_target();


create or replace function check_order_structure()
returns trigger
language plpgsql
set search_path = rezyapova_food, exts
as $$
begin
    if not exists (select 1
                   from "order" o
                   join product p on p.restaurant_id = o.restaurant_id
                   where o.order_id = new.order_id and p.product_id = new.product_id) then
        raise exception 'Блюдо % не из ресторана заказа %', new.product_id, new.order_id;
    end if;
    return new;
end;
$$;

create trigger order_structure_restaurant_check
before insert or update of order_id, product_id on order_structure
for each row execute function check_order_structure();

create or replace function check_payment_amount()
returns trigger
language plpgsql
set search_path = rezyapova_food, exts
as $$
declare
    v_total numeric;
begin
    select total_amount into v_total from "order" where order_id = new.order_id;
    if new.amount <> v_total then
        raise exception 'Сумма оплаты % не равна общей сумме заказа %', new.amount, v_total;
    end if;
    return new;
end;
$$;

create trigger payment_amount_check
before insert or update of order_id, amount on payment
for each row execute function check_payment_amount();

create or replace function protect_order_consistency()
returns trigger
language plpgsql
set search_path = rezyapova_food, exts
as $$
begin
    if new.restaurant_id <> old.restaurant_id
       and exists (select 1 from order_structure where order_id = old.order_id) then
        raise exception 'Нельзя сменить ресторан заказа %: в нём уже есть блюда', old.order_id;
    end if;
    if new.order_amount <> old.order_amount
       and exists (select 1 from payment where order_id = old.order_id) then
        raise exception 'Нельзя изменить сумму заказа %: по нему уже есть оплаты', old.order_id;
    end if;
    return new;
end;
$$;

create trigger order_consistency_protect
before update of restaurant_id, order_amount on "order"
for each row execute function protect_order_consistency();

create or replace function protect_product_restaurant()
returns trigger
language plpgsql
set search_path = rezyapova_food, exts
as $$
begin
    if new.restaurant_id <> old.restaurant_id
       and exists (select 1 from order_structure where product_id = old.product_id) then
        raise exception 'Нельзя перенести блюдо % в другой ресторан: оно уже есть в заказах',
            old.product_id;
    end if;
    return new;
end;
$$;

create trigger product_restaurant_protect
before update of restaurant_id on product
for each row execute function protect_product_restaurant();

create or replace function sync_order_pay_status()
returns trigger
language plpgsql
set search_path = rezyapova_food, exts
as $$
declare
    v_order uuid;
begin
    foreach v_order in array
        case tg_op when 'INSERT' then array[new.order_id]
                   when 'DELETE' then array[old.order_id]
                   else array[old.order_id, new.order_id] end
    loop
        update "order" o
        set pay_status = (
                select case
                           when count(*) = 0                                          then 'ожидает'
                           when count(*) filter (where p.status = 'успех') > 0       then 'оплачен'
                           when count(*) filter (where p.status = 'в_обработке') > 0 then 'ожидает'
                           else 'ошибка'
                       end::order_pay_status
                from payment p
                where p.order_id = v_order)
        where o.order_id = v_order;
    end loop;
    return null;
end;
$$;

create trigger payment_sync_pay_status
after insert or update of status, order_id or delete on payment
for each row execute function sync_order_pay_status();

