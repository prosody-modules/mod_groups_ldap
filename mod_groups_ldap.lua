-- Prosody IM
-- Copyright (C) 2008-2010 Matthew Wild
-- Copyright (C) 2008-2010 Waqas Hussain
-- 
-- This project is MIT/X11 licensed. Please see the
-- COPYING file in the source package for more information.
--


local groups;
local members;

local ldap         = module:require 'ldap';

local jid, datamanager = require "util.jid", require "util.datamanager";
local jid_bare, jid_prep = jid.bare, jid.prep;

local module_host = module:get_host();

local CACHE_EXPIRY = 300;
local params;

local gettime      = require 'socket'.gettime;

local get_alias_for_user;

do
  local user_cache;
  local last_fetch_time;

  local function populate_user_cache()
      local ld = ldap.getconnection();

      local usernamefield = params.user.usernamefield;
      local namefield     = params.user.namefield;

      user_cache = {};

      for _, attrs in ld:search { base = params.user.basedn, scope = 'onelevel', filter = params.user.filter } do
          user_cache[attrs[usernamefield]] = attrs[namefield];
      end
      last_fetch_time = gettime();
  end

  function get_alias_for_user(user)
      if last_fetch_time and last_fetch_time + CACHE_EXPIRY < gettime() then
          user_cache = nil;
      end
      if not user_cache then
          populate_user_cache();
      end
      return user_cache[user];
  end
end

function inject_roster_contacts(username, host, roster)
  --module:log("debug", "Injecting group members to roster");
	local bare_jid = username.."@"..host;
	if not members[bare_jid] and not members[false] then return; end -- Not a member of any groups
	
	local function import_jids_to_roster(group_name)
		for jid in pairs(groups[group_name]) do
			-- Add them to roster
			--module:log("debug", "processing jid %s in group %s", tostring(jid), tostring(group_name));
			if jid ~= bare_jid then
				if not roster[jid] then roster[jid] = {}; end
				roster[jid].subscription = "both";
				if groups[group_name][jid] then
					roster[jid].name = groups[group_name][jid];
				end
				if not roster[jid].groups then
					roster[jid].groups = { [group_name] = true };
				end
				roster[jid].groups[group_name] = true;
				roster[jid].persist = false;
			end
		end
	end

	-- Find groups this JID is a member of
	if members[bare_jid] then
		for _, group_name in ipairs(members[bare_jid]) do
			--module:log("debug", "Importing group %s", group_name);
			import_jids_to_roster(group_name);
		end
	end
	
	-- Import public groups
	if members[false] then
		for _, group_name in ipairs(members[false]) do
			--module:log("debug", "Importing group %s", group_name);
			import_jids_to_roster(group_name);
		end
	end
	
	if roster[false] then
		roster[false].version = true;
	end
end

function remove_virtual_contacts(username, host, datastore, data)
	if host == module_host and datastore == "roster" then
		local new_roster = {};
		for jid, contact in pairs(data) do
			if contact.persist ~= false then
				new_roster[jid] = contact;
			end
		end
		if new_roster[false] then
			new_roster[false].version = nil; -- Version is void
		end
		return username, host, datastore, new_roster;
	end

	return username, host, datastore, data;
end

function module.load()
	params = module:get_option('ldap');
	if not params then return; end
	
	local ld = ldap.getconnection();
	local memberfield = params.groups.memberfield;
	local namefield   = params.groups.namefield;

	module:hook("roster-load", inject_roster_contacts);
	datamanager.add_callback(remove_virtual_contacts);

	groups = { default = {} };
	members = { };
	for _, config in ipairs(params.groups) do
		module:log("debug", "New group: %s with name: %s", tostring(config[namefield]), tostring(config.name));
		groups[ config[namefield] ] = groups[ config[namefield] ] or {}
		-- TODO manage "name" of a group
--		groups[ config[namefield] ]['name'] = config.name
		if not members[false] then
			members[false] = {};
		end
		members[false][#members[false]+1] = config[namefield];
	end
	
	for dn, attrs in ld:search { attrs = { namefield, memberfield } , base = params.groups.basedn, scope = 'subtree', filter = params.groups.filter } do
		-- If this group as been imported by conf
		if groups[ attrs[namefield] ] then
			local members = attrs[memberfield];
			if members then
				--If only 1 member is found, members is a string and not a table
				if type(members)=="table" then
					for _, user in ipairs(members) do
						local jid    = user .. '@' .. module.host;
						if jid then
							module:log("debug", "New member of %s: %s", tostring( groups[ attrs[namefield] ] ), tostring(jid));
							groups[ attrs[namefield] ][jid] = jid --get_alias_for_user(user);
							members[jid] = members[jid] or {};
							--TODO manage name
						end
					end
				end
				if type(members)=="string" then
					local jid    = members .. '@' .. module.host;
					if jid then
						module:log("debug", "New member of %s: %s", tostring( groups[ attrs[namefield] ] ), tostring(jid));
						groups[ attrs[namefield] ][jid] = jid --get_alias_for_user(user);
					end
				end
			end
		end
	end
	module:log("info", "Groups loaded successfully");
end

function module.unload()
	datamanager.remove_callback(remove_virtual_contacts);
end
