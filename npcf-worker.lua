local dprint = townchest.dprint --debug

local MAX_SPEED = 5


townchest.npc = {
	spawn_nearly = function(pos, owner)
		local npcid = tostring(math.random(10000))
		npcf.index[npcid] = owner --owner
		local ref = {
			id = npcid,
			pos = {x=(pos.x+math.random(0,4)-4),y=(pos.y + 0.5),z=(pos.z+math.random(0,4)-4)},
			yaw = math.random(math.pi),
			name = "townchest:npcf_builder",
			owner = owner,
		}
		local npc = npcf:add_npc(ref)
		npcf:save(ref.id)
		if npc then
			npc:update()
		end
	end
}

local function get_speed(distance)
	local speed = distance * 0.5
	if speed > MAX_SPEED then
		speed = MAX_SPEED
	end
	return speed
end


local select_chest = function(self)
	-- do nothing if the chest not ready
	if not self.metadata.chestpos
			or not townchest.chest.list[self.metadata.chestpos.x..","..self.metadata.chestpos.y..","..self.metadata.chestpos.z] --chest position not valid
			or not self.chest
			or not self.chest:npc_build_allowed() then --chest buid not ready

		local npcpos = self.object:getpos()
		local selectedchest = nil
		for key, chest in pairs(townchest.chest.list) do
			if (not selectedchest or vector.distance(npcpos, chest.pos) < vector.distance(npcpos, selectedchest.pos)) and chest:npc_build_allowed() then
				selectedchest = chest
			end
		end
		if selectedchest then
			self.metadata.chestpos = selectedchest.pos
			self.chest = selectedchest
			dprint("Now I will build for chest",self.chest)
		else --stay if no chest assigned
			self.metadata.chestpos = nil
			self.chest = nil
			self.chestpos = nil
		end
	else
		dprint("Chest ok:",self.chest)
	end
end


local get_if_buildable = function(self, realpos)
	local pos = self.chest.plan:get_plan_pos(realpos)
--	dprint("in plan", pos.x.."/"..pos.y.."/"..pos.z)
	local node = self.chest.plan.building_full[pos.x..","..pos.y..","..pos.z]
	if not node then
		return nil
	end
	-- skip the chest position
	if realpos.x == self.chest.pos.x and realpos.y == self.chest.pos.y and realpos.z == self.chest.pos.z then --skip chest pos
		self.chest.plan:set_node_processed(node)
		return nil
	end

	-- check if already build (skip the most air)
	local success = minetest.forceload_block(realpos) --keep the target node loaded
	if not success then
		dprint("error forceloading:", realpos.x.."/"..realpos.y.."/"..realpos.z)
	end
	local orig_node = minetest.get_node(realpos)
	minetest.forceload_free_block(realpos)
	if orig_node.name == "ignore" then
		minetest.get_voxel_manip():read_from_map(realpos, realpos)
		orig_node = minetest.get_node(realpos)
	end
	
	if not orig_node or orig_node.name == "ignore" then --not loaded chunk. can be forced by forceload_block before check if buildable
		dprint("check ignored")
		return nil
	end
	if orig_node.name == node.name or orig_node.name == minetest.registered_nodes[node.name].name then 
		-- right node is at the place. there are no costs to touch them. Check if a touch needed
		if (node.param2 ~= orig_node.param2 and not (node.param2 == nil and orig_node.param2  == 0)) then
			--param2 adjustment
--			node.matname = townchest.nodes.c_free_item -- adjust params for free
			return node
		elseif not node.meta then
			--same item without metadata. nothing to do
			self.chest.plan:set_node_processed(node)
			return nil
		elseif townchest.nodes.is_equal_meta(minetest.get_meta(realpos):to_table(), node.meta) then
			--metadata adjustment
			self.chest.plan:set_node_processed(node)
			return nil
		elseif node.matname == townchest.nodes.c_free_item then
			-- TODO: check if nearly nodes are already built
			return node
		else
			return node
		end
	else
		-- no right node at place
		return node
	end
end


local function prefer_target(npc, t1, t2)
	if not t1 then
		return t2
	end

	local npcpos = npc.object:getpos()
	local prefer = 0

	--prefer same items in building order
	if npc.lastnode then
		if npc.lastnode.name == t1.name then
			prefer = prefer + 2.5
		end
		if npc.lastnode.name == t2.name then
			prefer = prefer - 2.5
		end
	end

	local t1_c = {x=t1.pos.x, y=t1.pos.y, z=t1.pos.z}
	local t2_c = {x=t2.pos.x, y=t2.pos.y, z=t2.pos.z}

	-- note: npc is higher by y+1.5
	-- in case of clanup task prefer higher node
	if t1.name ~= "air" then
		t1_c.y = t1_c.y + 3 -- calculate as over the npc by additional 1.5. no change means lower then npc by 1.5
	else
		prefer = prefer + 2 -- prefer air
		t1_c.y = t1_c.y - 1 
	end

	if t2.name ~= "air" then
		t2_c.y = t2_c.y + 3 -- calculate as over the npc by additional 1.5. no change means lower then npc by 1.5
	else
		prefer = prefer - 2 -- prefer air
		t2_c.y = t2_c.y - 1 
	end

	if (vector.distance(npcpos, t2_c) + prefer) < vector.distance(npcpos, t1_c) then
		return t2
	else
		return t1
	end

end


local get_target = function(self)
	local npcpos = self.object:getpos()
	local plan = self.chest.plan
	npcpos.y = npcpos.y - 1.5  -- npc is 1.5 blocks over the work
	local selectednode

	-- first try: look for nearly buildable nodes
	dprint("search for nearly node")
	for x=math.floor(npcpos.x)-5, math.floor(npcpos.x)+5 do
		for y=math.floor(npcpos.y)-5, math.floor(npcpos.y)+5 do
			for z=math.floor(npcpos.z)-5, math.floor(npcpos.z)+5 do
				local node = get_if_buildable(self,{x=x,y=y,z=z})
				if node then
					node.pos = plan:get_world_pos(node)
					selectednode = prefer_target(self, selectednode, node)
				end
			end
		end
	end
	
	if not selectednode then
	-- get the old target to compare
		if self.targetnode and self.targetnode.pos then
			selectednode = get_if_buildable(self, self.targetnode.pos)
		end
	end

	-- second try. Check the current chunk
	dprint("search for node in current chunk")
	for idx, nodeplan in ipairs(plan:get_nodes_from_chunk(plan:get_plan_pos(npcpos))) do
		local node = get_if_buildable(self, plan:get_world_pos(nodeplan))
		if node then
			node.pos = plan:get_world_pos(node)
			selectednode = prefer_target(self, selectednode, node)
		end
	end

	if not selectednode then
		--get anything - with forceloading, so the NPC can go away
		dprint("get node with random jump")
		local jump = plan.building_size
		if jump > 1000 then
			jump = 1000
		end
		if jump > 1 then
			jump = math.floor(math.random(jump))
		else
			jump = 0
		end
		
		local startingnode = plan:get_nodes(1,jump)
		if startingnode[1] then -- the one node given
			dprint("---check chunk", startingnode[1].x.."/"..startingnode[1].y.."/"..startingnode[1].z)
			for idx, nodeplan in ipairs(plan:get_nodes_from_chunk(startingnode[1])) do
				local node_wp = plan:get_world_pos(nodeplan)
				local node = get_if_buildable(self, node_wp)
				if node then
					node.pos = node_wp
					selectednode = prefer_target(self, selectednode, node)
				end
			end
		else
			dprint("something wrong with startningnode")
		end
	end

	if selectednode then
		selectednode.pos = plan:get_world_pos(selectednode)
		return selectednode
	end
end

npcf:register_npc("townchest:npcf_builder" ,{
	description = "Townchest Builder NPC",
	textures = {"npcf_builder_skin.png"},
	stepheight = 1.1,
	inventory_image = "npcf_builder_inv.png",
	on_step = function(self)
		if self.timer > 1 then
			self.timer = 0
			select_chest(self)
			self.target_prev = self.targetnode
			if self.chest and self.chest.plan and self.chest.plan.building_size > 0 then
				self.targetnode = get_target(self)
				self.dest_type = "build"
			else
				if self.dest_type ~= "home_reached" then
					self.targetnode = self.origin
					self.dest_type = "home"
				end
			end

-- simple check if target reached
		elseif self.targetnode then
			local pos = self.object:getpos()
			local target_distance = vector.distance(pos, self.targetnode.pos)
			if target_distance < 1 then
				local yaw = self.object:getyaw()
				local speed = 0
				self.object:setvelocity(npcf:get_walk_velocity(speed, self.object:getvelocity().y, yaw))
			end
			return
		end

		if not self.targetnode then
			return
		end

		local pos = self.object:getpos()
		local yaw = self.object:getyaw()
		local state = NPCF_ANIM_STAND
		local speed = 0
		local acceleration = {x=0, y=-10, z=0}
		if self.targetnode then
			local target_distance = vector.distance(pos, self.targetnode.pos)
			local target_direcion = vector.direction(pos, self.targetnode.pos)
			local real_distance = 0
			local real_direction = {x=0, y=0, z=0}
			local last_distance = 0
			if self.var.last_pos then
				real_distance = vector.distance(self.var.last_pos, pos)
				real_direction = vector.direction(self.var.last_pos, pos)
				last_distance = vector.distance(self.var.last_pos, self.targetnode.pos)
			end

			yaw = npcf:get_face_direction(pos, self.targetnode.pos)
			-- target reached build
			if target_distance < 3 and self.dest_type == "build" then
				-- do the build
				local soundspec
				if minetest.registered_items[self.targetnode.name].sounds then
					soundspec = minetest.registered_items[self.targetnode.name].sounds.place
				elseif self.targetnode.name == "air" then --TODO: should be determinated on old node, if the material handling is implemented
					soundspec = default.node_sound_leaves_defaults({place = {name = "default_place_node", gain = 0.25}})
				end
				if soundspec then
					soundspec.pos = pos
					minetest.sound_play(soundspec.name, soundspec)
				end
				minetest.env:add_node(self.targetnode.pos, self.targetnode)
				if self.targetnode.meta then
					print("meta:", self.targetnode.name, dump(self.targetnode.meta))
					minetest.env:get_meta(self.targetnode.pos):from_table(self.targetnode.meta)
				end
				self.chest.plan:set_node_processed(self.targetnode)
				self.chest:update_statistics()

				local cur_pos = {x=pos.x, y=pos.y - 0.5, z=pos.z}
				local cur_node = minetest.registered_items[minetest.get_node(cur_pos).name]
				if cur_node.walkable then
					pos = {x=pos.x, y=pos.y + 1.5, z=pos.z}
					self.object:setpos(pos)
				end

				if target_distance > 2 then
					speed = 1
					state = NPCF_ANIM_WALK_MINE

					-- jump
					if self.targetnode.name ~= "air" and (self.targetnode.pos.y -(pos.y-1.5)) > 0 and (self.targetnode.pos.y -(pos.y-1.5)) < 2 then
						acceleration = {x=0, y=0, z=0}
						pos = {x=pos.x, y=self.targetnode.pos.y + 1.5, z=pos.z}
						self.object:setpos(pos)
					end
				else
					speed = 0
					state = NPCF_ANIM_MINE
				end

				self.timer = 0
				self.lastnode = self.targetnode
				self.laststep = "build"
				self.targetnode = nil
			-- home reached
			elseif target_distance < 4 and self.dest_type == "home" then
--				self.object:setpos(self.origin.pos)
				yaw = self.origin.yaw
				speed = 0
				self.dest_type = "home_reached"
				self.targetnode = nil
			else
				--target not reached
				-- teleport in direction in case of stucking
				if (last_distance - 0.01) <= target_distance and self.laststep == "walk" and 
						(self.target_prev == self.targetnode) then
					pos = vector.add(pos, vector.multiply(target_direcion, 2))
					if pos.y < self.targetnode.pos.y then
						pos = {x=pos.x, y=self.targetnode.pos.y + 1.5, z=pos.z}
					end
					self.object:setpos(pos)
					acceleration = {x=0, y=0, z=0}
				end
				state = NPCF_ANIM_WALK
				self.var.last_pos = pos
				speed = get_speed(target_distance)
				self.laststep = "walk"
			end
		else
			dprint("no target")
		end
		self.object:setacceleration(acceleration)
		self.object:setvelocity(npcf:get_walk_velocity(speed, self.object:getvelocity().y, yaw))
		self.object:setyaw(yaw)
		npcf:set_animation(self, state)
	end,
})

