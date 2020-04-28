create
or replace function create_constraint_if_not_exists (
  t_name text,
  c_name text,
  constraint_sql text
) returns void AS $$ begin -- Look for our constraint
if not exists (
  select
    constraint_name
  from information_schema.constraint_column_usage
  where
    table_name = t_name
    and constraint_name = c_name
) then execute 'ALTER TABLE ' || t_name || ' ADD CONSTRAINT ' || c_name || ' ' || constraint_sql;
end if;
end;
$$ language 'plpgsql';
--
-- define the iam_auth_method_type_enm lookup table
--
CREATE TABLE if not exists iam_scope_type_enm (
  id smallint NOT NULL primary key,
  string text NOT NULL UNIQUE
);
INSERT INTO iam_scope_type_enm (id, string)
values
  (0, 'unknown');
INSERT INTO iam_scope_type_enm (id, string)
values
  (1, 'organization');
INSERT INTO iam_scope_type_enm (id, string)
values
  (2, 'project');
ALTER TABLE iam_scope_type_enm
ADD
  CONSTRAINT iam_scope_type_enm_between_chk CHECK (
    id BETWEEN 0
    AND 2
  );
CREATE TABLE if not exists iam_scope (
    id bigint generated always as identity primary key,
    create_time timestamp with time zone default current_timestamp,
    update_time timestamp with time zone default current_timestamp,
    public_id text NOT NULL UNIQUE,
    friendly_name text UNIQUE,
    type int NOT NULL REFERENCES iam_scope_type_enm(id) CHECK(
      (
        type = '1'
        and parent_id = NULL
      )
      or (
        type = '2'
        and parent_id IS NOT NULL
      )
    ),
    parent_id bigint REFERENCES iam_scope(id) ON DELETE CASCADE ON UPDATE CASCADE,
    disabled BOOLEAN NOT NULL default FALSE
  );
create table if not exists iam_scope_organization (
    id bigint generated always as identity primary key,
    scope_id bigint NOT NULL UNIQUE REFERENCES iam_scope(id) ON DELETE CASCADE ON UPDATE CASCADE
  );
create table if not exists iam_scope_project (
    id bigint generated always as identity primary key,
    scope_id bigint REFERENCES iam_scope(id) ON DELETE CASCADE ON UPDATE CASCADE,
    parent_id bigint REFERENCES iam_scope_organization(scope_id) ON DELETE CASCADE ON UPDATE CASCADE
  );
CREATE
  OR REPLACE FUNCTION iam_sub_scopes_func() RETURNS TRIGGER
SET SCHEMA
  'public' LANGUAGE plpgsql AS $$ DECLARE parent_type INT;
BEGIN IF new.type = '1' THEN
insert into iam_scope_organization (scope_id)
values
  (new.id);
return NEW;
END IF;
IF new.type = '2' THEN
insert into iam_scope_project (scope_id, parent_id)
values
  (new.id, new.parent_id);
return NEW;
END IF;
RAISE EXCEPTION 'unknown scope type';
END;
$$;
CREATE TRIGGER iam_scope_insert
AFTER
insert ON iam_scope FOR EACH ROW EXECUTE PROCEDURE iam_sub_scopes_func();
CREATE TABLE if not exists iam_user (
    id bigint generated always as identity primary key,
    create_time timestamp with time zone NOT NULL default current_timestamp,
    update_time timestamp with time zone NOT NULL default current_timestamp,
    public_id text not null UNIQUE,
    friendly_name text UNIQUE,
    name text NOT NULL,
    primary_scope_id bigint NOT NULL REFERENCES iam_scope_organization(scope_id),
    disabled BOOLEAN NOT NULL default FALSE
  );
CREATE TABLE if not exists iam_auth_method (
    id bigint generated always as identity primary key,
    create_time timestamp with time zone NOT NULL default current_timestamp,
    update_time timestamp with time zone NOT NULL default current_timestamp,
    public_id text not null UNIQUE,
    friendly_name text UNIQUE,
    primary_scope_id bigint NOT NULL REFERENCES iam_scope_organization(scope_id),
    disabled BOOLEAN NOT NULL default FALSE,
    type smallint NOT NULL
  );
CREATE TABLE if not exists iam_role (
    id bigint generated always as identity primary key,
    create_time timestamp with time zone NOT NULL default current_timestamp,
    update_time timestamp with time zone NOT NULL default current_timestamp,
    public_id text not null UNIQUE,
    friendly_name text UNIQUE,
    description text,
    primary_scope_id bigint NOT NULL REFERENCES iam_scope(id),
    disabled BOOLEAN NOT NULL default FALSE
  );
--
  -- define the iam_group_member_type_enm lookup table
  --
  CREATE TABLE if not exists iam_group_member_type_enm (
    id smallint NOT NULL primary key,
    string text NOT NULL UNIQUE
  );
INSERT INTO iam_group_member_type_enm (id, string)
values
  (0, 'unknown');
INSERT INTO iam_group_member_type_enm (id, string)
values
  (1, 'user');
ALTER TABLE iam_group_member_type_enm
ADD
  CONSTRAINT iam_group_member_type_enm_between_chk CHECK (
    id BETWEEN 0
    AND 1
  );
CREATE TABLE if not exists iam_group (
    id bigint generated always as identity primary key,
    create_time timestamp with time zone NOT NULL default current_timestamp,
    update_time timestamp with time zone NOT NULL default current_timestamp,
    public_id text not null UNIQUE,
    friendly_name text UNIQUE,
    description text,
    primary_scope_id bigint NOT NULL REFERENCES iam_scope(id),
    disabled BOOLEAN NOT NULL default FALSE
  );
CREATE TABLE if not exists iam_group_member_user (
    id bigint generated always as identity primary key,
    create_time timestamp with time zone NOT NULL default current_timestamp,
    update_time timestamp with time zone NOT NULL default current_timestamp,
    public_id text not null UNIQUE,
    friendly_name text UNIQUE,
    primary_scope_id bigint NOT NULL REFERENCES iam_scope(id),
    group_id bigint NOT NULL REFERENCES iam_group(id),
    member_id bigint NOT NULL REFERENCES iam_user(id),
    type int NOT NULL REFERENCES iam_group_member_type_enm(id) CHECK(type = 1)
  );
CREATE VIEW iam_group_member AS
SELECT
  *
FROM iam_group_member_user;
--
  -- define the iam_auth_method_type_enm lookup table
  --
  CREATE TABLE if not exists iam_auth_method_type_enm (
    id smallint NOT NULL primary key,
    string text NOT NULL UNIQUE
  );
INSERT INTO iam_auth_method_type_enm (id, string)
values
  (0, 'unknown');
INSERT INTO iam_auth_method_type_enm (id, string)
values
  (1, 'userpass');
INSERT INTO iam_auth_method_type_enm (id, string)
values
  (2, 'oidc');
ALTER TABLE iam_auth_method_type_enm
ADD
  CONSTRAINT iam_auth_method_type_enm_between_chk CHECK (
    id BETWEEN 0
    AND 2
  );
ALTER TABLE iam_auth_method
ADD
  FOREIGN KEY (type) REFERENCES iam_auth_method_type_enm(id);
--
  -- define the iam_action_emn lookup table
  --
  CREATE TABLE if not exists iam_action_enm (
    id smallint NOT NULL primary key,
    string text NOT NULL UNIQUE
  );
INSERT INTO iam_action_enm (id, string)
values
  (0, 'unknown');
INSERT INTO iam_action_enm (id, string)
values
  (1, 'list');
INSERT INTO iam_action_enm (id, string)
values
  (2, 'create');
INSERT INTO iam_action_enm (id, string)
values
  (3, 'update');
INSERT INTO iam_action_enm (id, string)
values
  (4, 'edit');
INSERT INTO iam_action_enm (id, string)
values
  (5, 'delete');
INSERT INTO iam_action_enm (id, string)
values
  (6, 'authen');
ALTER TABLE iam_action_enm
ADD
  CONSTRAINT iam_action_enm_between_chk CHECK (
    id BETWEEN 0
    AND 6
  );
--
  -- define the iam_role_type_enm lookup table
  --
  CREATE TABLE if not exists iam_role_type_enm (
    id smallint NOT NULL primary key,
    string text NOT NULL UNIQUE
  );
INSERT INTO iam_role_type_enm (id, string)
values
  (0, 'unknown');
INSERT INTO iam_role_type_enm (id, string)
values
  (1, 'user');
INSERT INTO iam_role_type_enm (id, string)
values
  (2, 'group');
ALTER TABLE iam_role_type_enm
ADD
  CONSTRAINT iam_role_type_enm_between_chk CHECK (
    id BETWEEN 0
    AND 3
  );
CREATE TABLE if not exists iam_role_user (
    id bigint generated always as identity primary key,
    create_time timestamp with time zone NOT NULL default current_timestamp,
    update_time timestamp with time zone NOT NULL default current_timestamp,
    public_id text not null UNIQUE,
    friendly_name text UNIQUE,
    primary_scope_id bigint NOT NULL REFERENCES iam_scope(id),
    role_id bigint NOT NULL REFERENCES iam_role(id),
    principal_id bigint NOT NULL REFERENCES iam_user(id),
    type int NOT NULL REFERENCES iam_role_type_enm(id) CHECK(type = 1)
  );
CREATE TABLE if not exists iam_role_group (
    id bigint generated always as identity primary key,
    create_time timestamp with time zone NOT NULL default current_timestamp,
    update_time timestamp with time zone NOT NULL default current_timestamp,
    public_id text not null UNIQUE,
    friendly_name text UNIQUE,
    primary_scope_id bigint NOT NULL REFERENCES iam_scope(id),
    role_id bigint NOT NULL REFERENCES iam_role(id),
    principal_id bigint NOT NULL REFERENCES iam_group(id),
    type int NOT NULL REFERENCES iam_role_type_enm(id) CHECK(type = 2)
  );
CREATE VIEW iam_assigned_role_vw AS
SELECT
  *
FROM iam_role_user
UNION
select
  *
from iam_role_group;
CREATE TABLE if not exists iam_role_grant (
    id bigint generated always as identity primary key,
    create_time timestamp with time zone NOT NULL default current_timestamp,
    update_time timestamp with time zone NOT NULL default current_timestamp,
    public_id text not null UNIQUE,
    friendly_name text UNIQUE,
    primary_scope_id bigint NOT NULL REFERENCES iam_scope(id),
    role_id bigint NOT NULL REFERENCES iam_role(id),
    role_grant text NOT NULL
  );