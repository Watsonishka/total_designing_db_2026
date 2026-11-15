set search_path to rezyapova_food, exts;

create or replace procedure rezyapova_food.erase_test_data()
language plpgsql
set search_path = rezyapova_food, exts
as $$
begin
    truncate table
        rezyapova_food.review,
        rezyapova_food.payment,
        rezyapova_food.order_structure,
        rezyapova_food."order",
        rezyapova_food.product,
        rezyapova_food.product_category,
        rezyapova_food.restaurant,
        rezyapova_food.client_address,
        rezyapova_food.client,
        rezyapova_food.address,
        rezyapova_food.courier_pay,
        rezyapova_food.courier;
end;
$$;

create or replace procedure insert_test_data(value int)
language plpgsql
set search_path = rezyapova_food, exts
set plan_cache_mode = force_custom_plan
set rezyapova_food.generating = 'on'
as $$
declare
    v_start timestamp;
    v_hire_min date;
    v_phone_base bigint;
    v_categories uuid[]:= array[]::uuid[];
    v_couriers uuid[]:= array[]::uuid[];
    v_hires date[]:= array[]::date[];
    v_dismissals date[]:= array[]::date[];
    v_addresses uuid[]:= array[]::uuid[];
    v_restaurants uuid[]:= array[]::uuid[];
    v_clients uuid[]:= array[]::uuid[];
    v_products uuid[]:= array[]::uuid[];
    v_prices numeric[]:= array[]::numeric[];
    v_idx int[];
    v_qty numeric[];
    v_attempts int;
    i int;
    j int;
    k int;
    v_tmp int;
    v_id uuid;
    v_order_id uuid;
    v_client_idx int;
    v_rest_idx int;
    v_courier_idx int;
    v_client_id uuid;
    v_rest_id uuid;
    v_courier_id uuid;
    v_addr_id uuid;
    v_cat_id uuid;
    v_prod_id uuid;
    v_first_prod uuid;
    v_price numeric;
    v_amount numeric;
    v_total numeric;
    v_lines int;
    v_courier_st courier_status;
    v_hire date;
    v_dismissal date;
    v_from timestamp;
    v_to timestamp;
    v_ts timestamp;
    v_status order_status;
    v_pay payment_status;
    v_review_type review_entity_type;
    v_month timestamp;
    v_coef numeric;
    v_cnt int;
    v_comm numeric;
begin
    if value is null or value < 1 then
        raise exception 'value должно быть положительным числом';
    end if;
    v_start:= greatest(date_trunc('month', localtimestamp) - interval '5 months', localtimestamp - interval '180 days');
    v_hire_min:= v_start::date + 1;
    v_phone_base:= coalesce((select max(right(phone_number, 10)::bigint) from client), 9000000000);
    for i in 1..value loop
        v_id:= exts.uuid_generate_v4();
        insert into product_category(product_category_id, product_category_name)
        values (v_id,
                (select string_agg(substr('абвгдеёжзийклмнопрстуфхцчшщъыьэюя', 1 + floor(random() * 33)::int, 1), '')
                 from generate_series(1, 1 + floor(random() * 80)::int)));
        v_categories:= array_append(v_categories, v_id);
    end loop;
    for i in 1..value loop
        if i = 1 then
            v_courier_st:= 'свободен';
        else
            v_courier_st:= case
                when random() < 0.2 then 'уволен'::courier_status
                else (enum_range(null::courier_status))[
                         1 + floor(random() * cardinality(enum_range(null::courier_status)))::int]
            end;
        end if;
        if i = 1 then
            v_hire:= v_hire_min;
        else
            v_hire:= v_hire_min + floor(random() * (current_date - v_hire_min))::int;
        end if;
        v_dismissal:= case when v_courier_st = 'уволен' then v_hire + floor(random() * (current_date - v_hire + 1))::int end;
        v_id:= exts.uuid_generate_v4();
        insert into courier(courier_id, last_name, first_name, patronymic, phone_number, status, hire_date, dismissal_date)
        values (v_id,
                (select string_agg(substr('абвгдеёжзийклмнопрстуфхцчшщъыьэюя', 1 + floor(random() * 33)::int, 1), '')
                 from generate_series(1, 1 + floor(random() * 50)::int)),
                (select string_agg(substr('абвгдеёжзийклмнопрстуфхцчшщъыьэюя', 1 + floor(random() * 33)::int, 1), '')
                 from generate_series(1, 1 + floor(random() * 50)::int)),
                case when random() < 0.2 then null 
                     else (select string_agg(substr('абвгдеёжзийклмнопрстуфхцчшщъыьэюя', 1 + floor(random() * 33)::int, 1), '')
                           from generate_series(1, 1 + floor(random() * 50)::int)) end,
                '+' || (1 + floor(random() * 9))::int || lpad(floor(random() * 10000000000)::bigint::text, 10, '0'),
                v_courier_st,
                v_hire,
                v_dismissal);
        v_couriers:= array_append(v_couriers, v_id);
        v_hires:= array_append(v_hires, v_hire);
        v_dismissals:= array_append(v_dismissals, v_dismissal);
    end loop;
    for i in 1..value * 5 loop
        v_id:= exts.uuid_generate_v4();
        insert into address(address_id, street, house_number, apartment_office)
        values (v_id,
                (select string_agg(substr('абвгдеёжзийклмнопрстуфхцчшщъыьэюя', 1 + floor(random() * 33)::int, 1), '')
                 from generate_series(1, 1 + floor(random() * 100)::int)),
                (floor(random() * (200 - 1 + 1)) + 1)::int::text,
                case when random() < 0.25 then null
                     else (floor(random() * (300 - 1 + 1)) + 1)::int::text end);
        v_addresses:= array_append(v_addresses, v_id);
    end loop;
    for i in 1..value loop
        v_id:= exts.uuid_generate_v4();
        v_addr_id:= v_addresses[i]; 
        insert into restaurant(restaurant_id, restaurant_name, address_id, description, inn, ogrn, payment_account, work_start, work_end, status)
        values (v_id,
                (select string_agg(substr('абвгдеёжзийклмнопрстуфхцчшщъыьэюя', 1 + floor(random() * 33)::int, 1), '')
                 from generate_series(1, 1 + floor(random() * 100)::int)),
                v_addr_id,
                (select string_agg(substr('абвгдеёжзийклмнопрстуфхцчшщъыьэюя', 1 + floor(random() * 33)::int, 1), '')
                 from generate_series(1, 1 + floor(random() * 240)::int)),
                (1000000000 + floor(random() * 9000000000))::bigint::text,
                (1000000000000 + floor(random() * 9000000000000))::bigint::text,
                '40702810' || lpad(floor(random() * 1000000000000)::bigint::text, 12, '0'),
                time '07:00' + floor(random() * 5) * interval '1 hour',
                time '19:00' + floor(random() * 4) * interval '1 hour',
                (enum_range(null::restaurant_status))[1 + floor(random() * cardinality(enum_range(null::restaurant_status)))::int]);
        v_restaurants:= array_append(v_restaurants, v_id);
    end loop;
    for i in 1..value loop
        v_id:= exts.uuid_generate_v4();
        insert into client(client_id, login, password, phone_number)
        values (v_id,
                (select string_agg(substr('абвгдеёжзийклмнопрстуфхцчшщъыьэюя', 1 + floor(random() * 33)::int, 1), '')
                 from generate_series(1, 1 + floor(random() * 39)::int))
                    || '_' || (v_phone_base + i),
                md5(random()::text),
                '+' || (1 + floor(random() * 9))::int || lpad((v_phone_base + i)::text, 10, '0'));
        v_clients:= array_append(v_clients, v_id);
    end loop;
    for i in 1..value * 4 loop
        v_client_id:= v_clients[(i - 1) % value + 1];
        v_addr_id:= v_addresses[value + i];
        insert into client_address(client_id, address_id)
        values (v_client_id, v_addr_id);
    end loop;
    for i in 1..value * 5 loop
        v_id:= exts.uuid_generate_v4();
        v_cat_id:= v_categories[1 + floor(random() * value)::int];
        v_rest_id:= v_restaurants[(i - 1) / 5 + 1];
        v_price:= round((150 + random() * 1850)::numeric, 2);
        insert into product(product_id, product_name, product_category_id, restaurant_id, price, description, photo_url, status)
        values (v_id,
                (select string_agg(substr('абвгдеёжзийклмнопрстуфхцчшщъыьэюя', 1 + floor(random() * 33)::int, 1), '')
                 from generate_series(1, 1 + floor(random() * 100)::int)),
                v_cat_id,
                v_rest_id,
                v_price,
                (select string_agg(substr('абвгдеёжзийклмнопрстуфхцчшщъыьэюя', 1 + floor(random() * 33)::int, 1), '')
                 from generate_series(1, 1 + floor(random() * 240)::int)),
                case when random() < 0.3 then null
                     else 'https://cdn.foodexpress.ru/img/' || md5(random()::text) || '.jpg' end,
                (enum_range(null::product_status))[1 + floor(random() * cardinality(enum_range(null::product_status)))::int]);
        v_products:= array_append(v_products, v_id);
        v_prices:= array_append(v_prices, v_price);
    end loop;
    for i in 1..value * 5 loop
        v_client_idx:= 1 + floor(random() * value)::int;
        v_rest_idx:= 1 + floor(random() * value)::int;
        v_courier_idx:= 1 + floor(random() * value)::int;
        v_client_id:= v_clients[v_client_idx];
        v_rest_id:= v_restaurants[v_rest_idx];
        v_courier_id:= v_couriers[v_courier_idx];
        v_addr_id:= v_addresses[value + v_client_idx + value * floor(random() * 4)::int];
        v_hire:= v_hires[v_courier_idx];
        v_dismissal:= v_dismissals[v_courier_idx];
        v_from:= greatest(v_hire::timestamp, v_start);
        v_to:= coalesce(v_dismissal::timestamp, localtimestamp - interval '2 hours');
        v_ts:= v_from + random() * (v_to - v_from);
        v_status:= case
            when random() < 0.6 then 'доставлен'::order_status
            else (enum_range(null::order_status))[
                     1 + floor(random() * cardinality(enum_range(null::order_status)))::int]
        end;
        v_pay:= case
            when v_status = 'доставлен' then 'успех'::payment_status
            else (enum_range(null::payment_status))[
                     1 + floor(random() * cardinality(enum_range(null::payment_status)))::int]
        end;
        v_lines:= 1 + floor(random() * 5)::int;
        v_idx:= array[1, 2, 3, 4, 5];
        for j in reverse 5..2 loop
            k := 1 + floor(random() * j)::int;
            v_tmp := v_idx[j]; v_idx[j] := v_idx[k]; v_idx[k] := v_tmp;
        end loop;
        v_qty:= array[]::numeric[];
        v_amount:= 0;
        for j in 1..v_lines loop
            v_price:= v_prices[(v_rest_idx - 1) * 5 + v_idx[j]];
            if j = 1 then
                v_qty[j]:= greatest(1 + floor(random() * 3), ceil(1000 / v_price));
            else
                v_qty[j]:= 1 + floor(random() * 3);
            end if;
            v_amount:= v_amount + round(v_price * v_qty[j], 2);
        end loop;
        v_order_id:= exts.uuid_generate_v4();
        insert into "order"(order_id, client_id, restaurant_id, courier_id, address_id,
                            order_timestamp, delivery_timestamp, order_amount,
                            status, pay_status, description)
        values (v_order_id,
                v_client_id,
                v_rest_id,
                v_courier_id,
                v_addr_id,
                v_ts,
                case when v_status = 'доставлен'
                     then v_ts + (30 + floor(random() * 60)) * interval '1 minute' end,
                v_amount,
                v_status,
                case v_pay when 'успех' then 'оплачен'::order_pay_status
                           when 'ошибка' then 'ошибка'::order_pay_status
                           else 'ожидает'::order_pay_status end,
                case when random() < 0.5 then null
                     else (select string_agg(substr('абвгдеёжзийклмнопрстуфхцчшщъыьэюя', 1 + floor(random() * 33)::int, 1), '')
                           from generate_series(1, 1 + floor(random() * 240)::int)) end)
        returning total_amount into v_total;
        for j in 1..v_lines loop
            v_prod_id:= v_products[(v_rest_idx - 1) * 5 + v_idx[j]];
            insert into order_structure(order_id, product_id, quantity)
            values (v_order_id, v_prod_id, v_qty[j]);
        end loop;
        v_first_prod:= v_products[(v_rest_idx - 1) * 5 + v_idx[1]];
        v_attempts:= 1 + floor(random() * 3)::int;
        for j in 1..v_attempts loop
            insert into payment(payment_id, order_id, payment_type, amount, transaction_number,
                                transaction_timestamp, status)
            values (exts.uuid_generate_v4(),
                    v_order_id,
                    (enum_range(null::payment_type))[
                        1 + floor(random() * cardinality(enum_range(null::payment_type)))::int],
                    v_total,
                    exts.uuid_generate_v4(),
                    v_ts + j * interval '5 minutes',
                    case when j < v_attempts then 'ошибка'::payment_status else v_pay end);
        end loop;
        v_review_type:= (enum_range(null::review_entity_type))[
            1 + floor(random() * cardinality(enum_range(null::review_entity_type)))::int];
        insert into review(review_id, client_id, order_id, entity_type, entity_id, description, photo_url, rating, review_timestamp)
        values (exts.uuid_generate_v4(),
                v_client_id,
                v_order_id,
                v_review_type,
                case v_review_type
                    when 'блюдо' then v_first_prod
                    when 'ресторан' then v_rest_id
                    else v_order_id
                end,
                (select string_agg(substr('абвгдеёжзийклмнопрстуфхцчшщъыьэюя', 1 + floor(random() * 33)::int, 1), '')
                 from generate_series(1, 1 + floor(random() * 240)::int)),
                case when random() < 0.5 then null
                     else 'https://cdn.foodexpress.ru/img/' || md5(random()::text) || '.jpg' end,
                floor(random() * (5 - 1 + 1)) + 1,
                least(v_ts + interval '3 hours', localtimestamp));
    end loop;
    for i in 1..value loop
        v_courier_id:= v_couriers[i];
        v_dismissal:= v_dismissals[i];
        v_coef:= 0.1;
        for v_month in
            select generate_series(date_trunc('month', v_start),
                                   date_trunc('month', localtimestamp),
                                   interval '1 month')
        loop
            select count(*), coalesce(sum(commission), 0)
            into v_cnt, v_comm
            from "order"
            where courier_id = v_courier_id
              and status = 'доставлен'
              and order_timestamp >= v_month
              and order_timestamp < v_month + interval '1 month';
            insert into courier_pay(year, month, courier_id, amount, coefficient_used)
            values (extract(year from v_month), extract(month from v_month), v_courier_id,
                    round(v_comm * v_coef, 2), v_coef);
            if v_dismissal is null or v_month < date_trunc('month', v_dismissal) then
                v_coef:= case when v_cnt <= 150 then 0.1
                              when v_cnt <= 250 then 0.2
                              when v_cnt <= 500 then 0.3
                              else 0.5 end;
            end if;
        end loop;
        update courier
        set coefficient = v_coef
        where courier_id = v_courier_id;
    end loop;
    update product p
    set rating = x.avg_rating
    from (select r.entity_id, round(avg(r.rating), 2) as avg_rating
          from review r
          where r.entity_type = 'блюдо' and r.entity_id = any (v_products)
          group by r.entity_id) x
    where p.product_id = x.entity_id;
    update restaurant rs
    set rating = x.avg_rating
    from (select r.entity_id, round(avg(r.rating), 2) as avg_rating
          from review r
          where r.entity_type = 'ресторан' and r.entity_id = any (v_restaurants)
          group by r.entity_id) x
    where rs.restaurant_id = x.entity_id;
end;
$$;