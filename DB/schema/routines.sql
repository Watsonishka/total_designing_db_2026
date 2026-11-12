set search_path to rezyapova_food, exts;

create or replace procedure add_product(
    p_restaurant_id uuid,
    p_product_category_id uuid,
    p_name varchar,
    p_price numeric,
    p_rating numeric,
    p_status product_status,
    p_description text,
    p_photo_url text default null
)
language plpgsql
set search_path = rezyapova_food, exts
as $$
begin
    if not exists (select 1 from restaurant where restaurant_id = p_restaurant_id) then
        raise exception 'add_product: ресторан с id % не существует', p_restaurant_id;
    end if;
    if not exists (select 1 from product_category where product_category_id = p_product_category_id) then
        raise exception 'add_product: категория с id % не существует', p_product_category_id;
    end if;
    if p_price < 0 then
        raise exception 'add_product: цена не может быть отрицательной (передано %)', p_price;
    end if;
    if p_rating < 0 or p_rating > 5 then
        raise exception 'add_product: рейтинг должен быть от 0 до 5 (передано %)', p_rating;
    end if;
    insert into product(product_id, product_name, product_category_id, restaurant_id,
                        price, description, photo_url, rating, status)
    values (exts.uuid_generate_v4(), p_name, p_product_category_id, p_restaurant_id,
            p_price, p_description, p_photo_url, p_rating, p_status);
end;
$$;

create or replace function get_statistic()
returns table (
    restaurant_name varchar,
    best_product_name varchar,
    total_amount numeric,
    avg_amount numeric,
    best_user varchar
)
language plpgsql
set search_path = rezyapova_food, exts
as $$
begin
    return query
        with delivered as materialized (
            select o.order_id, o.restaurant_id, o.client_id, o.total_amount as order_total
            from "order" o
            where o.status = 'доставлен'
        ),
        totals as (
            select d.restaurant_id,
                   sum(d.order_total) as sum_total,
                   round(avg(d.order_total), 2) as avg_total
            from delivered d
            group by d.restaurant_id
        ),
        best_product as (
            select distinct on (d.restaurant_id)
                   d.restaurant_id, p.product_name
            from delivered d
            join order_structure os on os.order_id = d.order_id
            join product p on p.product_id = os.product_id
            group by d.restaurant_id, p.product_id, p.product_name
            order by d.restaurant_id, sum(os.quantity) desc, random()
        ),
        best_client as (
            select distinct on (d.restaurant_id)
                   d.restaurant_id, c.login
            from delivered d
            join client c on c.client_id = d.client_id
            group by d.restaurant_id, c.client_id, c.login
            order by d.restaurant_id, count(*) desc, random()
        )
        select r.restaurant_name::varchar,
               bp.product_name::varchar,
               coalesce(t.sum_total, 0),
               coalesce(t.avg_total, 0),
               bc.login::varchar
        from restaurant r
        left join totals t on t.restaurant_id  = r.restaurant_id
        left join best_product bp on bp.restaurant_id = r.restaurant_id
        left join best_client bc on bc.restaurant_id = r.restaurant_id
        order by r.restaurant_name;
end;
$$;

create or replace procedure courier_salary()
language plpgsql
set search_path = rezyapova_food, exts
as $$
declare
    v_month_start date := date_trunc('month', current_date)::date;
    v_next_month  date := (date_trunc('month', current_date) + interval '1 month')::date;
    v_year int  := extract(year  from current_date)::int;
    v_month int  := extract(month from current_date)::int;
    r record;
begin
    for r in
        select c.courier_id,
               c.status,
               c.coefficient,
               count(o.order_id)::int as deliveries,
               coalesce(sum(o.commission), 0) as commission_sum
        from courier c
        left join "order" o
               on o.courier_id = c.courier_id
              and o.status = 'доставлен'
              and o.order_timestamp >= v_month_start
              and o.order_timestamp <  v_next_month
        where c.dismissal_date is null or c.dismissal_date >= v_month_start
        group by c.courier_id, c.status, c.coefficient
    loop
        if exists (select 1 from courier_pay
                   where year = v_year and month = v_month and courier_id = r.courier_id) then
            update courier_pay
            set amount = round(r.commission_sum * coefficient_used, 2)
            where year = v_year and month = v_month and courier_id = r.courier_id;
        else
            insert into courier_pay(year, month, courier_id, amount, coefficient_used)
            values (v_year, v_month, r.courier_id,
                    round(r.commission_sum * r.coefficient, 2), r.coefficient);
        end if;
        if r.status <> 'уволен' then
            update courier
            set coefficient = case when r.deliveries <= 150 then 0.1
                                   when r.deliveries <= 250 then 0.2
                                   when r.deliveries <= 500 then 0.3
                                   else 0.5 end
            where courier_id = r.courier_id;
        end if;
    end loop;
end;
$$;

create or replace view how_much_money as
with recursive
bounds as (
    select date_trunc('month', min(order_timestamp))::date as first_month,
           date_trunc('month', max(order_timestamp))::date as last_month
    from "order"
    where status = 'доставлен'
),
months (month_start) as (
    select first_month from bounds where first_month is not null
    union all
    select (m.month_start + interval '1 month')::date
    from months m
    cross join bounds b
    where m.month_start < b.last_month
),
orders_by_month as (
    select date_trunc('month', order_timestamp)::date as month_start,
           sum(order_amount) as sum_no_commission,
           sum(total_amount) as sum_with_commission
    from "order"
    where status = 'доставлен'
    group by 1
),
pay_by_month as (
    select concat(year, '-', month, '-01')::date as month_start,
           sum(amount) as courier_pay
    from courier_pay
    group by 1
),
base as (
    select m.month_start,
           coalesce(o.sum_no_commission, 0)::numeric as sum_no_commission,
           coalesce(o.sum_with_commission, 0)::numeric as sum_with_commission,
           coalesce(p.courier_pay, 0)::numeric as courier_pay
    from months m
    left join orders_by_month o on o.month_start = m.month_start
    left join pay_by_month p on p.month_start = m.month_start
)
select to_char(month_start, 'YYYY-MM')::text as year_month,
       sum_no_commission,
       sum_with_commission,
       sum_with_commission - sum_no_commission as commission,
       lag(sum_with_commission - sum_no_commission)
           over (order by month_start) as prev_commission,
       (sum_with_commission - sum_no_commission)
         - lag(sum_with_commission - sum_no_commission)
               over (order by month_start) as commission_diff,
       courier_pay,
       (sum_with_commission - sum_no_commission) - courier_pay as net_profit
from base
order by month_start;
