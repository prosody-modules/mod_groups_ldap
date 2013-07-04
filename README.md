mod_groups_ldap
===============

Prosody module to manage roaster groups with ldap

How to use
----------

```lua
modules_enabled = {
  [...]
  "groups_ldap";
  [...]
};


ldap = {
  hostname = "myLdapServer"
  -- bind_dn = "cn=admin,dc=example,dc=com",
  -- bind_password = "password"
  
  groups = {
    basedn = "ou=groups,dc=example,dc=com",
    memberfield = "memberUid",
    namefield = "cn",
    filter = "objectClass=posixGroup",
    {
      name = "Marketing",
      cn = 'maketing',
      admin = false,
    },
    {
      name = 'Admins',
      cn = 'admins',
      admin = true,
    },
    {
      name = 'Devs",
      cn = 'devs',
      admin = false,
    },
  },
}
```
