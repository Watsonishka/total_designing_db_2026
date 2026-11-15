set search_path to rezyapova_food, exts;

create or replace function rating_change() returns trigger 
language plpgsql
set search_path = rezyapova_food, exts
as $$
declare
    v_entity_type review_entity_type;
    v_entity_id uuid;
begin
    if current_setting('rezyapova_food.generating', true) = 'on' then return null;
    end if;
    if tg_op = 'DELETE' then
        v_entity_type:= old.entity_type;
        v_entity_id:= old.entity_id;
    else
        v_entity_type:= new.entity_type;
        v_entity_id:= new.entity_id;
    end if;
    if v_entity_type = 'блюдо' then
        update product
        set rating = (select round(avg(r.rating), 2)
                      from review r
                      where r.entity_type = 'блюдо' and r.entity_id = v_entity_id)
        where product_id = v_entity_id;
    elsif v_entity_type = 'ресторан' then
        update restaurant
        set rating = (select round(avg(r.rating), 2)
                      from review r
                      where r.entity_type = 'ресторан' and r.entity_id = v_entity_id)
        where restaurant_id = v_entity_id;
    end if;
    return null;
end;
$$;

create trigger review_rating_change
after insert or update or delete on review 
for each row  
execute function rating_change();