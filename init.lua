-- Code by UjEdwin and mrob27
-- License, revision history and instructions are in README.txt

local portalgun_portals={}
local nxt_id = 0 -- this counts how many portalpairs have been created; TODO: this will go away
local portalgun_step_interval = 0.1
local portalgun_time=0
local portalgun_lifetime = 5000 -- We delete portals that unused for this long
local portalgun_running = false
local portalgun_max_range = 13

local function portalgun_getLength(a)-- get length of an array / table
	local count = 0
	for _ in pairs(a) do count = count + 1 end
	return count
end

-- return a node definition for the node at pos, with a fallback in case
-- that pos is not presently loaded
local function node_ok(pos)
    local fallback = "default:dirt"
    local nd = minetest.get_node_or_nil(pos)
    if not nd then
		-- pos is outside the area currently loaded
        return minetest.registered_nodes[fallback]
    end
	-- use the node's name to find the node definition
    local nodef = minetest.registered_nodes[nd.name]
    if nodef then
        return nodef
    end
    return minetest.registered_nodes[fallback]
end

minetest.register_on_leaveplayer(
	-- when a player leaves the game, make their portals expire
	function(user)
		local uname = user:get_player_name()
		for i=1, portalgun_getLength(portalgun_portals),1 do
			if portalgun_portals[i]~=0 and portalgun_portals[i].user==uname then
				portalgun_portals[i].lifetime=-1
				return 0
			end
		end
	end
)

-- step function or an individual portal: checks if there are things to
-- teleport
local function portalgun_step_proc(portal, id)
	if portalgun_portals[id] == 0 then
		return 0
	end
	-- print ("[portalgun] sproc(" .. portal .. ", " .. id  .. ")")

	-- check if portals have run out of lifetime. (If they are used, by
	-- an object getting teleported, the timer is reset, see below)
	portalgun_portals[id].lifetime = portalgun_portals[id].lifetime-1
	if portalgun_portals[id].lifetime < 0 then
		if portalgun_portals[id].portal1 ~= 0 then
			portalgun_portals[id].portal1:remove()
		end
		if portalgun_portals[id].portal2 ~= 0 then
			portalgun_portals[id].portal2:remove()
		end
		portalgun_portals[id] = 0
		return 0
	end

	-- get position and direction of entry portal (pos1, d1) and
	-- of exit portal (pos2, d2)
	local pos1 = 0
	local pos2 = 0
	local d1 = 0
	local d2 = 0
	if portal == 1 then
		pos1 = portalgun_portals[id].portal1_pos
		pos2 = portalgun_portals[id].portal2_pos
		d1 = portalgun_portals[id].portal1_dir
		d2 = portalgun_portals[id].portal2_dir
	else
		pos1 = portalgun_portals[id].portal2_pos
		pos2 = portalgun_portals[id].portal1_pos
		d1 = portalgun_portals[id].portal2_dir
		d2 = portalgun_portals[id].portal1_dir
	end


	if (pos2 ~= 0) and (pos1 ~= 0) then
		-- we have two portals, so teleporting is possible
		-- check all objects within a radius of 1.5 (it has to be this big
		-- to catch players, whose "position" is a point near the feet)
		for ii, ob in pairs(minetest.get_objects_inside_radius(pos1, 1.5)) do
			if ob:get_luaentity() and ob:get_luaentity().name=="portalgun:portal" then
				-- this object is the portal itself; ignore
			else
				-- ======= set velocity then teleport
				local p=pos2
				local x=0
				local y=0
				local z=0

				if ob:is_player()==false then
					-- get object's current velocity.
					local v=ob:getvelocity() 

					-- compute the magnitude of the velocity
					local vmag = math.sqrt(v.x*v.x + v.y*v.y + v.z*v.z)
					-- if v.x<0 then v.x=v.x*-1 end
					-- if v.y<0 then v.y=v.y*-1 end
					-- if v.z<0 then v.z=v.z*-1 end
					-- local vmag=0 -- get the biggest velocity
					-- if v.x>v.z then vmag=v.x else vmag=v.z end
					-- if vmag<v.y then vmag=v.y end

					-- compute exit velocity. Objects always exit in a
					-- direction perpendicular to the exit portal, with
					-- speed equal to the speed they had when entering.
					v.x = 0
					v.y = 0
					v.z = 0
					if d2=="x+" then v.x=vmag
					elseif d2=="x-" then v.x=vmag*-1
					elseif d2=="y+" then v.y=vmag
					elseif d2=="y-" then v.y=vmag*-1
					elseif d2=="z+" then v.z=vmag
					elseif d2=="z-" then v.z=vmag*-1 end

					ob:setvelocity({x=v.x, y=v.y, z=v.z})
				end

				-- Calculate exit point, 2 nodes away from the exit portal
				-- in whatever direction the exit portal is facing. It has
				-- to be 2 nodes away so we don't immediately get
				-- teleported again.
				if d2=="x+" then x=2
				elseif d2=="x-" then x=-2
				elseif d2=="y+" then y=2
				elseif d2=="y-" then y=-2
				elseif d2=="z+" then z=2
				elseif d2=="z-" then z=-2
				end

				ob:moveto({x=p.x+x,y=p.y+y,z=p.z+z},false)

				-- this portal has been used, so we should reset the
				-- portal's expiration timer
				portalgun_portals[id].lifetime = portalgun_lifetime

				-- ======= end of set velocity part then teleport
			end
		end
	end
	return 1
end

minetest.register_globalstep(
	-- periodically check all portals to see if objects have gotten within
	-- range
	function(dtime)
		-- if we have no portals, just exit right away
		if not portalgun_running then
			return 0
		end
		-- print "[portalgun] gstep"

		portalgun_time = portalgun_time + dtime
		if portalgun_time < portalgun_step_interval then
			return
		end

		portalgun_time=0
		local use=0

		for i=1, portalgun_getLength(portalgun_portals),1 do
			use = use + portalgun_step_proc(1, i)
			use = use + portalgun_step_proc(2, i)
		end
		if (use == 0) and (portalgun_getLength(portalgun_portals) > 0) then
			portalgun_portals = {}
			portalgun_running = false
		end
	end
)

minetest.register_entity("portalgun:portal", {		-- the portals
	visual = "mesh",
	mesh = "portalgun_portal_xp.obj",
	id=0,
	physical = false,
	textures ={"portalgun_blue.png"},
	visual_size = {x=1, y=1},
	-- automatic_rotate = math.pi * 2.9,
	spritediv = {x=7, y=0},
	collisionbox = {0,0,0,0,0,0},
	on_activate = function(self, staticdata)
		self.owner = ""
		self.pnum = 0
		self.id = 0
		if staticdata then
			local tmp = minetest.deserialize(staticdata)
			if tmp then
				if tmp.owner then
					self.owner = tmp.owner
				end
				if tmp.pnum then
					self.pnum = tmp.pnum
				end
				if tmp.id then
					self.id = tmp.id
				end
			end
		end
		if self.pnum > 0 then
--			print ("[portalgun] activate #" .. self.id .. ", p"..self.pnum.." for " .. self.owner)
		else
--			print ("[portalgun] portal just created")
		end

		-- a portal entity is being loaded into the environment because
		-- a player is nearby
		self.id = nxt_id
		if not portalgun_portals[self.id] then
--			print "[portalgun] not in pg_p table, removing."
			self.object:remove()
			return
		end
		local d=""
		local prj = 0
		if portalgun_portals[self.id].project then
			prj = portalgun_portals[self.id].project
		end
--		print ("[portalgun] id now "..self.id..", project="..prj)
		if prj==1 then
			d=portalgun_portals[self.id].portal1_dir
			self.object:set_properties({textures = {"portalgun_blue.png"},})
		else
			d=portalgun_portals[self.id].portal2_dir
			self.object:set_properties({textures = {"portalgun_orange.png"},})
		end

		if d=="x+" then self.object:setyaw(math.pi * 0)
		elseif d=="x-" then self.object:setyaw(math.pi * 1)
		elseif d=="y+" then self.object:set_properties({mesh = "portalgun_portal_yp.obj",}) -- becaouse there is no "setpitch"
		elseif d=="y-" then self.object:set_properties({mesh = "portalgun_portal_ym.obj",}) -- becaouse there is no "setpitch"
		elseif d=="z+" then self.object:setyaw(math.pi * 0.5) 
		elseif d=="z-" then self.object:setyaw(math.pi * 1.5)
			self.object:set_hp(1000)
		end	
	end,
	get_staticdata = function(self)
		local tmp = {
			owner = self.owner,
			pnum = self.pnum,
			id = self.id,
		}
--		print ("get_sd id="..self.id.." pnum="..self.pnum.." owner="..self.owner)
		return minetest.serialize(tmp)
	end,
})

local function portal_useproc(itemstack, user, pointed_thing, RMB, remove)
	-- print "[portalgun] useproc"
	local pnum = 1
	if RMB then
		pnum = 2
	end
    if pointed_thing.type ~= "node" then
		-- print "[portals] useproc: pt.type is not a node"
        return itemstack
    end
	local pos = pointed_thing.under
	local node = node_ok(pos)
	local nn = node.name

	-- portals can only be placed on walkable nodes: not torches, papyrus, etc.
	-- NOTE: We might also want to exclude certain node types (e.g. steps,
	-- fence, trapdoors, etc)
	if (not node.walkable) then
		return itemstack
	end

	pos = user:getpos()
	local dir = user:get_look_dir() -- unit vector
	local uname = user:get_player_name()
	local found = false
	local len = portalgun_getLength(portalgun_portals)

	-- in my mods is as default I set   0 or false   in a array when not
	-- using anymore, then clear the array when not used, that saves much.

	-- this check if you can hold shift+leftclick to clear your user-portals,
	-- lifetime=0 means the portals will die to next run.
	for i=1, len,1 do
		if portalgun_portals[i]~=0
			and portalgun_portals[i]~=nil
			and portalgun_portals[i].user==uname
		then
			if not RMB then
				-- left mouse button
				if remove then
					portalgun_portals[i].lifetime=0
					return itemstack
				end
			end
			found = true
			nxt_id = i
			break
		end
	end

	if not found then
		-- this user hasn't made any portals yet

		-- create a new set of portals, to add to the global list in the event
		-- this is the first time this player has used the gun
		local ob={}
		ob.project=1
		ob.lifetime=portalgun_lifetime
		ob.portal1=0
		ob.portal2=0
		ob.portal1_dir=0
		ob.portal2_dir=0
		ob.portal2_pos=0
		ob.portal1_pos=0
		ob.user = uname

		table.insert(portalgun_portals, ob)
		nxt_id = len+1
	end

	portalgun_running = true
	nxt_id = portalgun_getLength(portalgun_portals)

	-- we scan away from the player to find out what they hit. we need to
	-- start 1.5 blocks above the player's location because the gun is
	-- being held about that far above the player's feet.
	pos.y = pos.y+1.5

	-- the project
	for i = 1, (portalgun_max_range+1), 1 do
		if minetest.get_node({x=pos.x+(dir.x*i), y=pos.y+(dir.y*i), z=pos.z+(dir.z*i)}).name~="air" then
			local id = nxt_id
			if portalgun_portals[id]==0 then return itemstack end
			portalgun_portals[id].lifelim=portalgun_lifetime
			local lpos={x=pos.x+(dir.x*(i-1)), y=pos.y+(dir.y*(i-1)), z=pos.z+(dir.z*(i-1))}
			local cpos={x=pos.x+(dir.x*i), y=pos.y+(dir.y*i), z=pos.z+(dir.z*i)}
			local x=math.floor((lpos.x-cpos.x)+ 0.5)
			local y=math.floor((lpos.y-cpos.y)+ 0.5)
			local z=math.floor((lpos.z-cpos.z)+ 0.5)
			local portal_dir=0

			-- the rotation & poss of the portals 

			if x>0 then portal_dir="x+" cpos.x=(math.floor(cpos.x+ 0.5))+0.504 end 
			if x<0 then portal_dir="x-" cpos.x=(math.floor(cpos.x+ 0.5))-0.504 end
			if y>0 then portal_dir="y+"  cpos.y=(math.floor(cpos.y+ 0.5))+0.504 end
			if y<0 then portal_dir="y-" cpos.y=(math.floor(cpos.y+ 0.5))-0.504 end
			if z>0 then portal_dir="z+" cpos.z=(math.floor(cpos.z+ 0.5))+0.504 end
			if z<0 then portal_dir="z-" cpos.z=(math.floor(cpos.z+ 0.5))-0.504 end

			local obj = 0
			if RMB then
				portalgun_portals[id].project=2
				portalgun_portals[id].portal2_dir=portal_dir
				portalgun_portals[id].portal2_pos=cpos
				if portalgun_portals[id].portal2~=0 then portalgun_portals[id].portal2:remove() end
				obj = minetest.env:add_entity(cpos, "portalgun:portal")
				portalgun_portals[id].portal2 = obj
			else
				portalgun_portals[id].project=1
				portalgun_portals[id].portal1_dir=portal_dir
				portalgun_portals[id].portal1_pos=cpos
				if portalgun_portals[id].portal1~=0 then portalgun_portals[id].portal1:remove() end
				obj = minetest.env:add_entity(cpos, "portalgun:portal")
				portalgun_portals[id].portal1 = obj
			end
			if obj then
				local ent = obj:get_luaentity()
				if ent then
					ent.owner = uname
					ent.pnum = pnum
					ent.id = id
				end
			end
--			print ("[portalgun] created #"..id.." p"..pnum.." for "..uname)
			if not remove then
				minetest.sound_play("portalgun_shoot", {pos=pos})
			end
			return itemstack
		end
	end
	return itemstack
end

minetest.register_tool("portalgun:gun", {
	description = "Portal Gun",
	inventory_image = "portalgun_gun_blue.png",
	range = portalgun_max_range,
	wield_image = "portalgun_gun_blue.png",
	-- groups = { not_in_creative_inventory = 0 },
	on_use = function(itemstack, user, pointed_thing)
		-- print "[portalgun] on_use"
		local key = user:get_player_control()
		if (key.sneak) then
			-- remove both portals
			return portal_useproc(itemstack, user, pointed_thing, false, true)
		else
			-- place blue portal
			return portal_useproc(itemstack, user, pointed_thing, false, false)
		end
	end,

	on_place = function(itemstack, user, pointed_thing)
		-- print "[portalgun] on_place"
		local key = user:get_player_control()
		if (key.sneak) then
			-- remove both portals
			return portal_useproc(itemstack, user, pointed_thing, false, true)
		else
			-- place orange portal
			return portal_useproc(itemstack, user, pointed_thing, true, false)
		end
	end,
})
