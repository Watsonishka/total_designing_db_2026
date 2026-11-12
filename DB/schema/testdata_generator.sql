set search_path to rezyapova_food, exts;

create or replace procedure erase_test_data()
language plpgsql
set search_path = rezyapova_food, exts
as $$
begin
    delete from review;
    delete from payment;
    delete from order_structure;
    delete from courier_pay;
    delete from "order";
    delete from client_address;
    delete from product;
    delete from restaurant;
    delete from product_category;
    delete from client;
    delete from courier;
    delete from address;
end;
$$;

create or replace procedure insert_test_data(value int)
language plpgsql
set search_path = rezyapova_food, exts
as $$
declare
    v_win_start date;
    v_now timestamp := localtimestamp;
    v_streets text[] := array['Ленина','Мира','Гагарина','Советская','Садовая','Лесная','Школьная','Пушкина','Набережная','Центральная'];
    v_surnames text[] := array['Иванов','Петров','Сидоров','Смирнов','Кузнецов','Попов','Волков','Соколов'];
    v_names text[] := array['Иван','Пётр','Алексей','Дмитрий','Сергей','Андрей','Михаил','Олег'];
    v_patrs text[] := array['Иванович','Петрович','Алексеевич','Дмитриевич','Сергеевич','Андреевич'];
    v_cats text[] := array['Пицца','Суши','Бургеры','Супы','Салаты','Десерты','Напитки','Паста','Шашлык','Завтраки'];
    v_dishes text[] := array['Маргарита','Пепперони','Филадельфия','Борщ','Цезарь','Чизбургер','Карбонара','Тирамису','Морс','Плов','Сырники','Том ям'];
    v_rnames text[] := array['Вкусно','Уют','Огонёк','Сакура','Тануки','Хинкальная','Пельменная','Бистро'];
    v_lorem text := 'Очень вкусно, быстро привезли, всё горячее, порции большие, рекомендую друзьям';
    v_base int;
    v_categories uuid[];
    v_couriers uuid[];
    v_c_hire date[];
    v_c_dism date[];
    v_addr_rest uuid[];
    v_addr_cli uuid[];
    v_restaurants uuid[];
    v_ws time[];
    v_clients uuid[];
    v_ca_client uuid[];
    v_ca_addr uuid[];
    v_ca_cnt int;
    v_products uuid[];
    v_prices numeric[];
    v_oid uuid;
    v_r int;
    v_c int;
    v_k int;
    v_n int;
    v_start int;
    v_x int;
    v_items int[];
    v_qty numeric[];
    v_amount numeric;
    v_total numeric;
    v_from timestamp;
    v_to timestamp;
    v_ts timestamp;
    v_rev_ts timestamp;
    v_status order_status;
    v_etype review_entity_type;
    r record;
    v_coef numeric;
    v_last numeric;
begin
    if value is null or value < 1 then
        raise exception 'insert_test_data: value должно быть >= 1, получено %', value;
    end if;
    v_win_start := (date_trunc('month', current_date) - interval '5 months')::date;
    if v_win_start < current_date - 179 then
        v_win_start := current_date - 179;
    end if;

    select array_agg(exts.uuid_generate_v4() order by g) into v_categories
    from generate_series(1, value) g;

    insert into product_category(product_category_id, product_category_name)
    select v_categories[g], v_cats[((g - 1) % 10) + 1]
    from generate_series(1, value) g;

    select array_agg(exts.uuid_generate_v4() order by g) into v_couriers
    from generate_series(1, value) g;

    select array_agg(v_win_start + floor(random() * 10)::int order by g) into v_c_hire
    from generate_series(1, value) g;

    select array_agg(case when g > 1 and random() < 0.2
                          then v_c_hire[g] + floor(random() * (current_date - v_c_hire[g] + 1))::int
                     end order by g) into v_c_dism
    from generate_series(1, value) g;

    insert into courier(courier_id, fio, phone_number, status, hire_date, dismissal_date)
    select v_couriers[g],
           v_surnames[1 + floor(random() * 8)::int] || ' ' ||
           v_names   [1 + floor(random() * 8)::int] || ' ' ||
           v_patrs   [1 + floor(random() * 6)::int],
           '+79' || (100000000 + floor(random() * 900000000)::bigint)::text,
           case when v_c_dism[g] is not null then 'уволен'::courier_status
                -- первые три значения enum — свободен, занят, на_доставке (все, кроме «уволен»)
                else (enum_range(null::courier_status))[1 + floor(random() * 3)::int]
           end,
           v_c_hire[g],
           v_c_dism[g]
    from generate_series(1, value) g;

    select array_agg(exts.uuid_generate_v4() order by g) into v_addr_rest
    from generate_series(1, value) g;

    select array_agg(exts.uuid_generate_v4() order by g) into v_addr_cli
    from generate_series(1, value * 4) g;

    insert into address(address_id, street, house_number, apartment_office)
    select case when g <= value then v_addr_rest[g] else v_addr_cli[g - value] end,
           v_streets[1 + floor(random() * 10)::int],
           (1 + floor(random() * 150)::int)::text,
           case when random() < 0.3 then null
                else (1 + floor(random() * 300)::int)::text end
    from generate_series(1, value * 5) g;

    v_base := (select count(*) from restaurant);

    select array_agg(exts.uuid_generate_v4() order by g) into v_restaurants
    from generate_series(1, value) g;

    select array_agg('06:00'::time + floor(random() * 13)::int * interval '30 minutes' order by g) into v_ws
    from generate_series(1, value) g;

    insert into restaurant(restaurant_id, restaurant_name, address_id, description,
                           company_details, work_start, work_end, status)
    select v_restaurants[g],
           v_rnames[1 + floor(random() * 8)::int] || ' №' || (v_base + g),
           v_addr_rest[g],
           left(v_lorem, 1 + floor(random() * length(v_lorem))::int),
           'ИНН ' || (1000000000 + floor(random() * 9000000000)::bigint)::text ||
           ', ОГРН ' || (1000000000000 + floor(random() * 9000000000000)::bigint)::text,
           v_ws[g],
           v_ws[g] + (6 + floor(random() * 5)::int) * interval '1 hour',
           (enum_range(null::restaurant_status))[1 + floor(random() * 2)::int]
    from generate_series(1, value) g;

    v_base := (select count(*) from client);

    select array_agg(exts.uuid_generate_v4() order by g) into v_clients
    from generate_series(1, value) g;

    insert into client(client_id, login, password, phone_number)
    select v_clients[g],
           left(md5(random()::text), 3 + floor(random() * 8)::int) || '_' || (v_base + g),
           md5(random()::text),
           '+7' || (9000000000 + v_base + g)::text
    from generate_series(1, value) g;

    insert into client_address(client_id, address_id)
    select v_clients[((g - 1) % value) + 1], v_addr_cli[g]
    from generate_series(1, value * 4) g;

    insert into client_address(client_id, address_id)
    select v_clients[1 + floor(random() * value)::int], v_addr_cli[g]
    from generate_series(1, value * 4) g
    where random() < 0.2
    on conflict do nothing;

    select array_agg(client_id order by client_id, address_id),
           array_agg(address_id order by client_id, address_id),
           count(*)
    into v_ca_client, v_ca_addr, v_ca_cnt
    from client_address
    where client_id in (select v_clients[g] from generate_series(1, value) g);

    select array_agg(exts.uuid_generate_v4() order by g) into v_products
    from generate_series(1, value * 5) g;

    select array_agg(round((100 + random() * 1400)::numeric, 2) order by g) into v_prices
    from generate_series(1, value * 5) g;

    insert into product(product_id, product_name, product_category_id, restaurant_id,
                        price, description, photo_url, status)
    select v_products[g],
           v_dishes[1 + floor(random() * 12)::int],
           v_categories[1 + floor(random() * value)::int],
           v_restaurants[((g - 1) % value) + 1],
           v_prices[g],
           left(v_lorem, 1 + floor(random() * length(v_lorem))::int),
           case when random() < 0.3 then null
                else 'https://foodexpress.ru/img/' || md5(random()::text) || '.jpg' end,
           (enum_range(null::product_status))[1 + floor(random() * 3)::int]
    from generate_series(1, value * 5) g;

    for i in 1 .. value * 5 loop
        v_r := 1 + floor(random() * value)::int;
        v_k := 1 + floor(random() * v_ca_cnt)::int;
        v_c := 1 + floor(random() * value)::int;
        v_from := v_c_hire[v_c]::timestamp;
        v_to := coalesce(v_c_dism[v_c] + 1, current_date + 1)::timestamp;
        if v_to > v_now - interval '2 hours' then
            v_to := v_now - interval '2 hours';
        end if;
        v_ts := v_from + random() * (v_to - v_from);
        v_status := case when random() < 0.6 then 'доставлен'::order_status
                         else (enum_range(null::order_status))[1 + floor(random() * 5)::int] end;
        v_n := 1 + floor(random() * 5)::int;
        v_start := floor(random() * 5)::int;
        v_items := '{}';
        v_qty := '{}';
        for j in 0 .. v_n - 1 loop
            v_items := v_items || (v_r + ((v_start + j) % 5) * value);
            v_qty   := v_qty   || (1 + floor(random() * 3))::numeric;
        end loop;

        loop
            select sum(v_prices[v_items[x]] * v_qty[x]) into v_amount
            from generate_series(1, v_n) x;
            exit when v_amount >= 910;
            v_x := 1 + floor(random() * v_n)::int;
            v_qty[v_x] := v_qty[v_x] + 1;
        end loop;
        v_total := v_amount + round(v_amount * 0.10, 2);
        v_oid := exts.uuid_generate_v4();

        insert into "order"(order_id, client_id, restaurant_id, courier_id, address_id,
                            order_timestamp, delivery_timestamp, order_amount,
                            status, pay_status, description)
        values (v_oid, v_ca_client[v_k], v_restaurants[v_r], v_couriers[v_c], v_ca_addr[v_k],
                v_ts,
                case when v_status = 'доставлен'
                     then v_ts + (20 + floor(random() * 70)::int) * interval '1 minute' end,
                v_amount,
                v_status,
                'ожидает',
                left(v_lorem, 1 + floor(random() * length(v_lorem))::int));

        insert into order_structure(order_id, product_id, quantity)
        select v_oid, v_products[v_items[x]], v_qty[x]
        from generate_series(1, v_n) x;

        insert into payment(order_id, payment_type, amount, transaction_number, transaction_timestamp, status)
        values (v_oid,
                (enum_range(null::payment_type))[1 + floor(random() * 3)::int],
                v_total,
                'TX-' || replace(exts.uuid_generate_v4()::text, '-', ''),
                v_ts + (1 + floor(random() * 10)::int) * interval '1 minute',
                'успех');

        v_etype := (enum_range(null::review_entity_type))[1 + floor(random() * 3)::int];

        v_rev_ts := v_ts + (1 + floor(random() * 72)::int) * interval '1 hour';
        if v_rev_ts > v_now then
            v_rev_ts := v_now;
        end if;

        insert into review(client_id, order_id, entity_type, entity_id,
                           description, photo_url, rating, review_timestamp)
        values (v_ca_client[v_k], v_oid, v_etype,
                case v_etype when 'заказ' then v_oid
                             when 'ресторан' then v_restaurants[v_r]
                             else v_products[v_items[1]] end,
                left(v_lorem, 1 + floor(random() * length(v_lorem))::int),
                case when random() < 0.5 then null
                     else 'https://foodexpress.ru/img/' || md5(random()::text) || '.jpg' end,
                1 + floor(random() * 5)::int,
                v_rev_ts);
    end loop;

    update product p
    set rating = s.avg_rating
    from (select entity_id, round(avg(rating), 2) as avg_rating
          from review
          where entity_type = 'блюдо'
            and entity_id in (select v_products[g] from generate_series(1, value * 5) g)
          group by entity_id) s
    where p.product_id = s.entity_id;

    update restaurant rs
    set rating = s.avg_rating
    from (select entity_id, round(avg(rating), 2) as avg_rating
          from review
          where entity_type = 'ресторан'
            and entity_id in (select v_restaurants[g] from generate_series(1, value) g)
          group by entity_id) s
    where rs.restaurant_id = s.entity_id;

    for c in 1 .. value loop
        v_coef := 0.1;
        v_last := 0.1;

        for r in
            select m::date as month_start,
                   coalesce(a.cnt, 0) as cnt,
                   coalesce(a.comm, 0) as comm
            from generate_series(date_trunc('month', v_c_hire[c]),
                                 date_trunc('month', coalesce(v_c_dism[c], current_date)),
                                 interval '1 month') m
            left join (select date_trunc('month', order_timestamp) as ms,
                              count(*) as cnt,
                              sum(commission) as comm
                       from "order"
                       where courier_id = v_couriers[c] and status = 'доставлен'
                       group by 1) a on a.ms = m
            order by m
        loop
            insert into courier_pay(year, month, courier_id, amount, coefficient_used)
            values (extract(year from r.month_start), extract(month from r.month_start),
                    v_couriers[c], round(r.comm * v_coef, 2), v_coef);

            v_last := v_coef;
            v_coef := case when r.cnt <= 150 then 0.1
                           when r.cnt <= 250 then 0.2
                           when r.cnt <= 500 then 0.3
                           else 0.5 end;
        end loop;

        update courier
        set coefficient = case when v_c_dism[c] is null then v_coef else v_last end
        where courier_id = v_couriers[c];
    end loop;
end;
$$;
