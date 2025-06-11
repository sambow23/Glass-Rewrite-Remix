AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_gmodentity"

ENT.Category		= "Glass: Rewrite"
ENT.Author			= "Mee"
ENT.Purpose			= "Destructable Fun"
ENT.Instructions	= "Spawn and damage it"
ENT.Spawnable		= false

local generateUV, generateNormals, simplify_vertices, split_convex, split_entity = include("world_functions.lua")

function ENT:SetupDataTables()
	self:NetworkVar("String", 0, "PhysModel")
    self:NetworkVar("Vector", 0, "PhysScale")
    self:NetworkVar("Entity", 0, "ReferenceShard")
    self:NetworkVar("Entity", 1, "OriginalShard")
end

local use_expensive = CreateConVar("glass_lagfriendly", 0, {FCVAR_ARCHIVE, FCVAR_NOTIFY, FCVAR_REPLICATED}, "", 0, 1)
local realistic_breaking = CreateConVar("glass_realistic_breaking", 1, {FCVAR_ARCHIVE, FCVAR_NOTIFY, FCVAR_REPLICATED}, "Use realistic radial glass breaking patterns (1) or old random breaking (0)", 0, 1)
local show_cracks = CreateConVar("glass_show_cracks", 1, {FCVAR_ARCHIVE, FCVAR_NOTIFY, FCVAR_REPLICATED}, "Show visual cracks before glass breaks (1) or break immediately (0)", 0, 1)
local crack_delay = CreateConVar("glass_crack_delay", 0.15, {FCVAR_ARCHIVE, FCVAR_NOTIFY, FCVAR_REPLICATED}, "Delay in seconds between showing cracks and breaking", 0.05, 1.0)
local shard_count = CreateConVar("glass_shard_count", 4, {FCVAR_ARCHIVE, FCVAR_NOTIFY, FCVAR_REPLICATED}, "Controls number of glass shards (1=few, 7=many)", 1, 7)
local glass_rigidity = CreateConVar("glass_rigidity", 50, {FCVAR_ARCHIVE, FCVAR_NOTIFY, FCVAR_REPLICATED}, "Glass damage threshold before breaking (0=fragile, 200=very strong)", 0, 200)
local mass_factor = CreateConVar("glass_mass_factor", 1.0, {FCVAR_ARCHIVE, FCVAR_NOTIFY, FCVAR_REPLICATED}, "How much object mass affects impact force (0.5=less, 2.0=more)", 0.1, 3.0)
local velocity_transfer = CreateConVar("glass_velocity_transfer", 1.0, {FCVAR_ARCHIVE, FCVAR_NOTIFY, FCVAR_REPLICATED}, "How much impact velocity transfers to shards (0.5=less dramatic, 2.0=more)", 0.1, 3.0)
local player_mass = CreateConVar("glass_player_mass", 70, {FCVAR_ARCHIVE, FCVAR_NOTIFY, FCVAR_REPLICATED}, "Player mass in kg for glass breaking calculations (50=light, 100=heavy)", 30, 150)
local player_break_speed = CreateConVar("glass_player_break_speed", 150, {FCVAR_ARCHIVE, FCVAR_NOTIFY, FCVAR_REPLICATED}, "Minimum player speed to break glass (100=walking, 250=sprinting)", 50, 400)

function ENT:BuildCollision(verts, pointer)
    local new_verts, offset = simplify_vertices(verts, self:GetPhysScale())
    self:EnableCustomCollisions()
	self:PhysicsInitConvex(new_verts)

    -- physics object isnt valid, remove cuz its probably weird
    if SERVER then
        local phys = self:GetPhysicsObject()
        if !phys:IsValid() then
            SafeRemoveEntity(self)
        else
            local bounding = self:BoundingRadius()
            if bounding < 40 and self:GetOriginalShard():IsValid() then
                self:SetCollisionGroup(COLLISION_GROUP_DEBRIS)
                if use_expensive then self:SetCollisionGroup(COLLISION_GROUP_WORLD) end
                if bounding < 20 then 
                    -- glass effect
                    local data = EffectData() data:SetOrigin(self:GetPos())
                    util.Effect("GlassImpact", data)
                    SafeRemoveEntity(self)
                    return
                end
            end
            phys:SetMass(math.sqrt(phys:GetVolume()))
            phys:SetMaterial("glass")
            phys:SetPos(self:LocalToWorld(offset))
            self.TRIANGLES = phys:GetMesh()

            if pointer then pointer[1] = true end     -- cant return true because of weird SENT issues, just use table pointer to indicate success
        end
    else
        self:SetRenderBounds(self:OBBMins(), self:OBBMaxs())
        local phys = self:GetPhysicsObject()
        if phys:IsValid() then
            phys:SetMaterial("glass")
        end
    end
end

if CLIENT then
    function ENT:Think()
        local physobj = self:GetPhysicsObject()
        if !physobj:IsValid() then 
            self:SetNextClientThink(CurTime())
            return true
        end

        if (self:GetPos() == physobj:GetPos() and !physobj:IsMotionEnabled()) then
            self:SetNextClientThink(CurTime() + 0.1)
            return true
        end

        physobj:EnableMotion(false)
        physobj:SetPos(self:GetPos())
        physobj:SetAngles(self:GetAngles())
        self:SetNextClientThink(CurTime())
    end

    function ENT:GetRenderMesh()
        if !self.RENDER_MESH then return end
        return self.RENDER_MESH
    end

    function ENT:Draw()
        -- Draw the normal glass mesh
        self:DrawModel()
        
        -- Draw crack overlay if present
        if self.crack_lines then
            self:DrawCracks()
        end
    end

    function ENT:OnRemove()
        if self.RENDER_MESH and self.RENDER_MESH.Mesh:IsValid() then
            self.RENDER_MESH.Mesh:Destroy()
        end
        
        -- Clean up crack mesh
        if self.crack_mesh then
            self.crack_mesh:Destroy()
        end
    end
else
    function ENT:Split(pos, explode, skip_cracks)
        local self = self
        if explode then pos = pos * 0.5 end  -- if explosion, kind of "shrink" position closer to the center of the shard
        
        -- Store impact data for velocity calculations
        local impact_velocity = Vector(0, 0, 0)
        local impact_force_magnitude = 0
        
        -- Calculate impact velocity based on stored impact data
        if self.last_impact_normal and self.last_impact_speed then
            local base_speed = math.min(self.last_impact_speed, 800) -- Cap for reasonable physics
            local transfer_factor = velocity_transfer:GetFloat()
            impact_velocity = self.last_impact_normal * (base_speed * 0.3 * transfer_factor) -- Scale down for realistic effect
            impact_force_magnitude = base_speed
        end
        
        -- Add some random scatter for more realistic breaking
        local scatter_amount = explode and 200 or 100
        
        -- Show cracks first if enabled and not skipping
        if show_cracks:GetBool() and !skip_cracks and !self.showing_cracks then
            self.showing_cracks = true
            self.crack_impact_pos = pos
            self.crack_explode = explode
            
            -- Store impact data for delayed break
            self.stored_impact_velocity = impact_velocity
            self.stored_impact_force = impact_force_magnitude
            self.stored_scatter = scatter_amount
            
            -- Show cracks on all clients
            self:ShowCracks(pos, self.last_impact_normal)
            
            -- Send crack data to clients
            if SERVER then
                net.Start("GLASS_SHOW_CRACKS")
                net.WriteEntity(self)
                net.WriteVector(pos)
                net.WriteVector(self.last_impact_normal or Vector(0, 0, 1))
                net.WriteBool(explode or false)
                net.Broadcast()
            end
            
            -- Break after delay
            timer.Simple(crack_delay:GetFloat(), function()
                if !self or !self:IsValid() or !self.CAN_BREAK then return end
                self:Split(self.crack_impact_pos, self.crack_explode, true) -- skip cracks on delayed break
            end)
            
            return
        end
        
        -- Use stored impact data if this is a delayed break
        if self.stored_impact_velocity then
            impact_velocity = self.stored_impact_velocity
            impact_force_magnitude = self.stored_impact_force or 0
            scatter_amount = self.stored_scatter or 100
        end
        
        local convexes = {}
        local split_depth = shard_count:GetInt() -- Use console variable as base
        
        -- Choose breaking pattern based on console variable
        if realistic_breaking:GetBool() then
            -- Create realistic glass fracture patterns
            local impact_pos = pos
            local shard_center = Vector(0, 0, 0) -- local center of the shard
            local impact_distance = impact_pos:Distance(shard_center)
            local shard_size = self:BoundingRadius()
            
            -- Create radial crack directions from impact point
            local crack_count = 0
            local function realisticVec() 
                crack_count = crack_count + 1
                
                -- Create radial cracks emanating from impact point
                if crack_count <= 3 then
                    -- Primary radial cracks - emanate directly from impact
                    local radial_dir = (VectorRand() * Vector(1, 1, 0.3)):GetNormalized()
                    
                    -- Bias toward perpendicular to impact if we have velocity data
                    if self.last_impact_normal then
                        local perpendicular = self.last_impact_normal:Cross(VectorRand()):GetNormalized()
                        radial_dir = (radial_dir + perpendicular * 0.7):GetNormalized()
                    end
                    
                    return radial_dir
                elseif crack_count <= 5 then
                    -- Secondary cracks - somewhat random but biased away from impact
                    local away_from_impact = (shard_center - impact_pos):GetNormalized()
                    local random_bias = VectorRand() * 0.4
                    return (away_from_impact + random_bias):GetNormalized()
                else
                    -- Tertiary cracks - more random for natural variation
                    local random_dir = VectorRand():GetNormalized()
                    
                    -- Slight bias toward horizontal/vertical for more realistic patterns
                    random_dir.x = random_dir.x * (math.random(0.6, 1.4))
                    random_dir.y = random_dir.y * (math.random(0.6, 1.4))
                    random_dir.z = random_dir.z * (math.random(0.3, 0.8))
                    
                    return random_dir:GetNormalized()
                end
            end
            
            -- Vary crack positions based on stress distribution
            local function realisticPos() 
                -- Cracks closer to impact should be more frequent
                local stress_factor = math.max(0.1, 1 - (impact_distance / shard_size))
                
                -- Create some cracks at the impact point
                if crack_count <= 2 then
                    return impact_pos + VectorRand() * (shard_size * 0.1)
                else
                    -- Other cracks distributed with stress bias
                    local random_offset = VectorRand() * shard_size * (0.3 + stress_factor * 0.4)
                    return impact_pos + random_offset
                end
            end
            
            -- Apply modifiers to the base shard count
            if explode then
                split_depth = split_depth + 2 -- explosions create more fragments
            elseif shard_size < 50 then
                split_depth = math.max(1, split_depth - 1) -- smaller pieces split less
            elseif impact_distance < shard_size * 0.3 then
                split_depth = split_depth + 1 -- direct hits create more fragments
            end
            
            -- Clamp to reasonable bounds for performance
            split_depth = math.Clamp(split_depth, 1, 7)
            
            split_entity({realisticVec, realisticPos}, self.TRIANGLES, convexes, split_depth)
        else
            -- Original random breaking pattern for backward compatibility
            -- Apply same modifiers for consistency
            if explode then
                split_depth = split_depth + 2
            elseif self:BoundingRadius() < 50 then
                split_depth = math.max(1, split_depth - 1)
            end
            
            split_depth = math.Clamp(split_depth, 1, 7)
            
            local function randVec() return VectorRand():GetNormalized() end
            local function randPos() return pos end
            split_entity({randVec, randPos}, self.TRIANGLES, convexes, split_depth)
        end
        
        local pos = self:GetPos()
        local ang = self:GetAngles()
        local model = self:GetPhysModel()
        local material = self:GetMaterial()
        local color = self:GetColor()
        local rendermode = self:GetRenderMode()
        local vel = self:GetVelocity()
        local phys_scale = self:GetPhysScale()
        local original_shard = self:GetOriginalShard():IsValid() and self:GetOriginalShard() or self
        local lastblock
        local valid_entity = {false}      -- table cuz i want pointers
        for k, physmesh in ipairs(convexes) do 
            local block = ents.Create("procedural_shard")
            block:SetPos(pos)
            block:SetAngles(ang)
            block:SetPhysModel(model)
            block:SetPhysScale(Vector(1, 1, 1))
            block:SetOriginalShard(original_shard)
            block:Spawn()
            block:SetReferenceShard(self)
            block:SetMaterial(material)
            block:SetColor(color)
            block:SetRenderMode(rendermode)
            block:BuildCollision(physmesh[1], valid_entity)   -- first thing in table is the triangles
            block.IS_FUNNY_GLASS = self.IS_FUNNY_GLASS
            
            -- Inherit a portion of accumulated damage (shards are weaker)
            if self.accumulated_damage and self.accumulated_damage > 0 then
                block.accumulated_damage = math.max(0, self.accumulated_damage * 0.3) -- Shards inherit 30% of damage
            else
                block.accumulated_damage = 0
            end
            
            local phys = block:GetPhysicsObject()
            if phys:IsValid() then
                -- Calculate realistic shard velocity based on impact
                local shard_velocity = Vector(vel.x, vel.y, vel.z) -- Start with original glass velocity
                
                if impact_velocity:Length() > 0 then
                    -- Get the center of this shard relative to impact point
                    local shard_center = block:GetPos()
                    local impact_world_pos = self:LocalToWorld(pos)
                    local impact_to_shard = (shard_center - impact_world_pos):GetNormalized()
                    
                    -- Calculate distance factor (closer shards get more velocity)
                    local distance = impact_world_pos:Distance(shard_center)
                    local distance_factor = math.Clamp(1 - (distance / self:BoundingRadius()), 0.2, 1)
                    
                    -- Apply velocity transfer scaling
                    local transfer_factor = velocity_transfer:GetFloat()
                    
                    -- Base impact velocity in the direction from impact to shard
                    local directional_velocity = impact_to_shard * (impact_force_magnitude * 0.2 * distance_factor * transfer_factor)
                    
                    -- Add the original impact direction with some force
                    local impact_contribution = impact_velocity * distance_factor * transfer_factor
                    
                    -- Combine directional and impact velocities
                    shard_velocity = shard_velocity + directional_velocity + impact_contribution
                    
                    -- Add some random scatter for realistic breaking
                    local scatter = VectorRand() * scatter_amount * distance_factor * transfer_factor
                    shard_velocity = shard_velocity + scatter
                    
                    -- Ensure upward component for dramatic effect (scaled by transfer factor)
                    local min_upward = 50 * transfer_factor
                    local max_upward = 150 * transfer_factor
                    if shard_velocity.z < min_upward then
                        shard_velocity.z = shard_velocity.z + math.random(min_upward, max_upward)
                    end
                end
                
                phys:SetVelocity(shard_velocity)
            end
            
            -- prop protection support
            if CPPI then
                local owner = self:CPPIGetOwner()
                if owner and owner:IsValid() then
                    block:CPPISetOwner(owner)
                end
            end

            if k == 1 then block:EmitSound("Glass.Break") end

            block.PLANES = physmesh[2]         -- second thing in table is the planes, in format local_pos, normal, local_pos, normal, etc
            if block.COMBINED_PLANES then
                table.Add(block.COMBINED_PLANES, physmesh[2])
            else
                block.COMBINED_PLANES = physmesh[2]
            end

            -- weld it to other shards
            if lastblock then
                constraint.Weld(block, lastblock, 0, 0, 3000, true)
            end
            lastblock = block
        end

        -- all shards have been removed because they are too small, remove the original
        if !valid_entity[1] then SafeRemoveEntity(self) return end

        constraint.RemoveAll(self)
        self:GetPhysicsObject():EnableMotion(false)
        self:SetNotSolid(true)
        self:ForcePlayerDrop()
        self.CAN_BREAK = false
        
        -- Clean up crack state and impact data
        self.showing_cracks = false
        self.crack_lines = nil
        self.stored_impact_velocity = nil
        self.stored_impact_force = nil
        self.stored_scatter = nil
        if self.crack_mesh then
            self.crack_mesh:Destroy()
            self.crack_mesh = nil
        end

        -- this shard is now invalid, decriment the original shards count
        local orig_shard = self:GetOriginalShard()
        if orig_shard and orig_shard:IsValid() then 
            orig_shard.SHARD_COUNT = orig_shard.SHARD_COUNT - 1
        end

        -- in case clientside receives sharded entity before this entity
        -- give clients 5 seconds to try and find shard
        timer.Simple(5, function()
            if !self:IsValid() then return end
            self:SetPos(Vector())
            self:SetAngles(Angle())
            self:SetNoDraw(true)
        end)
        
    end

    function ENT:OnTakeDamage(damage)
        if !self.CAN_BREAK or self.showing_cracks then return end
        local damagepos = damage:GetDamagePosition()
        if damagepos != Vector() then -- some physents are broken and have no damage position, so just set the damage to the center of the object
            damagepos = self:WorldToLocal(damagepos)
        else
            damagepos = Vector()
        end
        
        -- Store damage data for realistic cracking patterns
        local attacker = damage:GetAttacker()
        if attacker and attacker:IsValid() then
            -- Calculate impact direction from attacker to glass
            local impact_dir = (self:GetPos() - attacker:GetPos()):GetNormalized()
            self.last_impact_normal = impact_dir
        else
            -- Fallback to random direction if no attacker info
            self.last_impact_normal = VectorRand():GetNormalized()
        end
        self.last_impact_speed = damage:GetDamage() * 10 -- simulate speed from damage
        
        -- Rigidity system: fast impacts break immediately, slow impacts accumulate
        local damage_amount = damage:GetDamage()
        local damage_type = damage:GetDamageType()
        local rigidity_threshold = glass_rigidity:GetFloat()
        local should_break = false
        
        -- Fast impacts that should break immediately regardless of rigidity
        local is_fast_impact = (
            damage_type == DMG_BULLET or           -- bullets
            damage_type == DMG_BUCKSHOT or        -- shotgun pellets  
            damage_type == DMG_SNIPER or          -- sniper rifles
            damage_type == DMG_BLAST or           -- explosions
            damage_amount < 15                     -- small precise damage (like bullets)
        )
        
        if is_fast_impact or rigidity_threshold <= 0 then
            -- Break immediately for fast impacts or when rigidity disabled
            should_break = true
        else
            -- Accumulate damage for slow impacts
            self.accumulated_damage = (self.accumulated_damage or 0) + damage_amount
            
            if self.accumulated_damage >= rigidity_threshold then
                should_break = true
            else
                -- Show minor crack effect without breaking
                if show_cracks:GetBool() and math.random() < 0.3 then -- 30% chance for minor cracks
                    self:ShowCracks(damagepos, self.last_impact_normal)
                end
                
                -- Play glass stress sound
                self:EmitSound("physics/glass/glass_strain" .. math.random(1, 4) .. ".wav", 40, math.random(120, 150))
                
                -- Visual feedback for damage accumulation
                if attacker and attacker:IsPlayer() then
                    attacker:ChatPrint("Glass damage: " .. math.Round(self.accumulated_damage) .. "/" .. math.Round(rigidity_threshold))
                end
                
                return -- Don't break yet
            end
        end
        
        if should_break then
            -- Reset damage counter when breaking
            self.accumulated_damage = 0
            
            self:Split(damagepos, damage:GetDamageType() == DMG_BLAST)
            if !show_cracks:GetBool() then
                self.CAN_BREAK = false
            end
        end
    end

    function ENT:PhysicsCollide(data)
    	if self:IsPlayerHolding() then return end	--unbreakable if held
        local speed_limit = self.IS_FUNNY_GLASS and -1 or 300
    	if data.Speed > speed_limit and self.CAN_BREAK and !self.showing_cracks then
            local ho = data.HitObject
            if ho and ho:IsValid() and ho.GetClass and ho:GetClass() == "procedural_shard" and ho.CAN_BREAK then return end

            -- just some values that I thought looked nice
            local limit = 0.25
            if ho.GetClass and ho:GetClass() == "procedural_shard" then limit = -0.25 end   -- less lag
            if self.IS_FUNNY_GLASS then limit = 2 end  -- impossible to not break

            -- if the glass is directly struck straightways, dont break since this can cause break loops
            local dot = data.OurNewVelocity:GetNormalized():Dot(data.OurOldVelocity:GetNormalized())
            if dot > limit then return end
           
            local pos = data.HitPos
            
            -- Store impact data for realistic cracking
            self.last_impact_normal = data.HitNormal
            self.last_impact_speed = data.Speed
            
            -- Enhanced rigidity system considering mass and velocity
            local impact_speed = data.Speed
            local impact_mass = 1 -- Default mass if we can't get it
            
            -- Try to get the mass of the impacting object
            if ho and ho:IsValid() and ho.GetPhysicsObject and ho:GetPhysicsObject():IsValid() then
                impact_mass = ho:GetPhysicsObject():GetMass()
            end
            
            -- Apply mass factor scaling
            local adjusted_mass = impact_mass * mass_factor:GetFloat()
            
            -- Calculate impact force using momentum (mass * velocity)
            -- Add some kinetic energy consideration (0.5 * mass * velocity^2)
            local momentum = adjusted_mass * impact_speed
            local kinetic_energy = 0.5 * adjusted_mass * (impact_speed * impact_speed) / 1000 -- Scale down for reasonable numbers
            local impact_force = momentum + (kinetic_energy * 0.1) -- Combine momentum and kinetic energy
            
            -- Convert impact force to damage equivalent 
            local collision_damage = impact_force / 15 -- Adjust this divisor to balance
            
            local rigidity_threshold = glass_rigidity:GetFloat()
            local should_break = false
            
            -- Very high impact forces should break immediately (like bullets)
            -- Dense objects or very fast impacts bypass rigidity
            local is_devastating_impact = (
                impact_force > 8000 or           -- Very high momentum/energy
                impact_speed > 800 or            -- Extremely fast
                (adjusted_mass > 50 and impact_speed > 400) -- Heavy and fast (using adjusted mass)
            )
            
            if is_devastating_impact or rigidity_threshold <= 0 then
                -- Break immediately for devastating impacts
                should_break = true
            else
                -- Accumulate damage for lesser impacts
                self.accumulated_damage = (self.accumulated_damage or 0) + collision_damage
                
                if self.accumulated_damage >= rigidity_threshold then
                    should_break = true
                else
                    -- Show minor crack effect without breaking
                    if show_cracks:GetBool() and math.random() < math.min(0.5, collision_damage / 30) then 
                        -- Higher chance of cracks for stronger impacts
                        local local_pos = self:WorldToLocal(pos)
                        self:ShowCracks(local_pos, self.last_impact_normal)
                    end
                    
                    -- Play glass stress sound (pitch varies with impact force)
                    local pitch = math.Clamp(120 + (impact_force / 100), 90, 180)
                    self:EmitSound("physics/glass/glass_strain" .. math.random(1, 4) .. ".wav", 30, pitch)
                    
                    return -- Don't break yet
                end
            end
            
            if should_break then
                -- Reset damage counter when breaking
                self.accumulated_damage = 0
                
                timer.Simple(0, function() -- NEVER change collision rules in physics feedback
                    if !self or !self:IsValid() then return end
                    self:Split(self:WorldToLocal(pos))
                    if !show_cracks:GetBool() then
                        self.CAN_BREAK = false
                    end
                end)
            end
    	end
	end	

    function ENT:Touch(entity)
        if !self.CAN_BREAK or self.showing_cracks then return end
        if !entity:IsPlayer() then return end
        
        -- Prevent spam by adding a small cooldown per player
        local current_time = CurTime()
        local player_id = entity:SteamID()
        self.player_touch_cooldowns = self.player_touch_cooldowns or {}
        
        if self.player_touch_cooldowns[player_id] and (current_time - self.player_touch_cooldowns[player_id]) < 0.5 then
            return -- Still in cooldown
        end
        
        -- Get player movement data
        local player_velocity = entity:GetVelocity()
        local player_speed = player_velocity:Length()
        
        -- Minimum speed threshold for glass breaking (walking speed ~100, running speed ~200+)
        local min_break_speed = player_break_speed:GetInt() -- Players need to be moving at least this fast
        if player_speed < min_break_speed then return end
        
        -- Set cooldown for this player (they're moving fast enough to potentially break glass)
        self.player_touch_cooldowns[player_id] = current_time
        
        -- Estimate player mass (average adult ~70kg, can be adjusted)
        local player_mass_kg = player_mass:GetInt()
        
        -- Calculate player impact force using the same system as physics objects
        local adjusted_mass = player_mass_kg * mass_factor:GetFloat()
        local momentum = adjusted_mass * player_speed
        local kinetic_energy = 0.5 * adjusted_mass * (player_speed * player_speed) / 1000
        local impact_force = momentum + (kinetic_energy * 0.1)
        local collision_damage = impact_force / 15
        
        local rigidity_threshold = glass_rigidity:GetFloat()
        local should_break = false
        
        -- Fast running players should break glass immediately
        local is_fast_player = player_speed > 250 -- Sprinting speed
        
        if is_fast_player or rigidity_threshold <= 0 then
            should_break = true
        else
            -- Accumulate damage for slower movement
            self.accumulated_damage = (self.accumulated_damage or 0) + collision_damage
            
            if self.accumulated_damage >= rigidity_threshold then
                should_break = true
            else
                -- Show minor crack effect without breaking
                if show_cracks:GetBool() and math.random() < math.min(0.4, collision_damage / 25) then
                    local contact_pos = entity:GetPos() - self:GetPos()
                    local local_pos = self:WorldToLocal(entity:GetPos())
                    self:ShowCracks(local_pos, player_velocity:GetNormalized())
                end
                
                -- Play glass stress sound
                local pitch = math.Clamp(100 + (player_speed / 5), 80, 160)
                self:EmitSound("physics/glass/glass_strain" .. math.random(1, 4) .. ".wav", 40, pitch)
                
                return -- Don't break yet
            end
        end
        
        if should_break then
            -- Store player impact data for realistic shard physics
            self.last_impact_normal = player_velocity:GetNormalized()
            self.last_impact_speed = player_speed
            self.accumulated_damage = 0
            
            -- Calculate impact position (where player touches glass)
            local contact_pos = entity:GetPos() - self:GetPos()
            local local_impact_pos = self:WorldToLocal(entity:GetPos())
            
            -- Break the glass with player impact data
            self:Split(local_impact_pos, false) -- Not an explosion
            if !show_cracks:GetBool() then
                self.CAN_BREAK = false
            end
        end
    end

    function ENT:OnRemove()
        local orig_shard = self:GetOriginalShard()
        if orig_shard and orig_shard:IsValid() then 
            orig_shard.SHARD_COUNT = orig_shard.SHARD_COUNT - 1
            if orig_shard.SHARD_COUNT < 1 then
                SafeRemoveEntity(orig_shard)
            end
        else    -- must be original shard, remove parent shards
            for k, v in ipairs(ents.FindByClass("procedural_shard")) do
                if v.GetOriginalShard and v:GetOriginalShard() == self then
                    SafeRemoveEntity(v)
                end
            end
        end
    end
end

function ENT:OnDuplicated()
    self:BuildCollision(util.GetModelMeshes(self:GetPhysModel())[1].triangles)
end


local default_mat = Material("models/props_combine/health_charger_glass")
function ENT:Initialize(first)
    --self:SetModel("models/Combine_Helicopter/helicopter_bomb01.mdl")
    self:PhysicsInit(SOLID_VPHYSICS)
    self:SetMoveType(MOVETYPE_VPHYSICS)
    self:SetSolid(SOLID_VPHYSICS)
    self:PhysWake()
    self:DrawShadow(false)

    if SERVER then 
        self.CAN_BREAK = false
        self.accumulated_damage = 0 -- Track damage for rigidity system
        -- if valid to completely remove
        local orig_shard = self:GetOriginalShard()
        if orig_shard and orig_shard:IsValid() then
            orig_shard.SHARD_COUNT = orig_shard.SHARD_COUNT + 1
        else
            self.SHARD_COUNT = 0    -- it is the original shard
        end

        -- remove fast & laggy interactions
        timer.Simple(0.25, function()
            if !self then return end
            self.CAN_BREAK = true
        end)

        return 
    end

    self.RENDER_MESH = {Mesh = Mesh(), Material = default_mat}
    
    if first then return end

    -- tell server to start sending shard data
    net.Start("SHARD_NETWORK")
    net.WriteEntity(self)
    net.SendToServer()
end

-- make sure clients can always see entity, reguardless if not in view
function ENT:UpdateTransmitState()
    return TRANSMIT_ALWAYS
end

if CLIENT then 
    language.Add("procedural_shard", "Glass Shard")
    return 
end

-- glass func_breakable_surf replacement
local function replaceGlass()
    for _, glass in ipairs(ents.FindByClass("func_breakable_surf")) do
        -- func breakable surf is kinda cursed, its origin and angle are always 0,0,0
        -- so we need to find out what they are

        -- angle can be found by going through 3 of the 4 points defined on a surf entity and finding the angle by constructing a triangle
        local verts = glass:GetBrushSurfaces()[1]:GetVertices()
        local glass_angle = (verts[1] - verts[2]):Cross(verts[1] - verts[3]):Angle()

        -- position can be found by getting the middle of the bounding box in the object
        local offset = (glass:OBBMaxs() + glass:OBBMins()) * 0.5

        -- weird rotate issue fix
        local rotate_angle = glass_angle
        if glass_angle[1] >= 45 and glass_angle[2] >= 180 then
            rotate_angle = -rotate_angle
        end

        -- our bounding box needs to be rotated to match the angle of the glass, the rotation is currently in local space, we need to convert to world
        verts[1] = verts[1] - offset
        verts[3] = verts[3] - offset
        verts[1]:Rotate(-rotate_angle)
        verts[3]:Rotate(-rotate_angle)

        -- now we have the actual size of the glass, take the 2 points and subtract to find the size, then divide by 2
        local size = (verts[1] - verts[3]) * 0.5

        -- create the shard
        local block = ents.Create("procedural_shard")
        block:SetPhysModel("models/hunter/blocks/cube025x025x025.mdl")
        block:SetPhysScale(Vector(1, size[2], size[3]) / 5.90625)  -- 5.90625 is the size of the block model
        block:SetPos(offset)
        block:SetAngles(glass_angle)
        block:SetMaterial(glass:GetMaterials()[1])
        block:Spawn()
    
        block:BuildCollision(util.GetModelMeshes("models/hunter/blocks/cube025x025x025.mdl")[1].triangles)
        if block:GetPhysicsObject():IsValid() then block:GetPhysicsObject():EnableMotion(false) end

        -- remove original func_ entity
        SafeRemoveEntity(glass)
    end
end

hook.Add("InitPostEntity", "glass_init", replaceGlass)
hook.Add("PostCleanupMap", "glass_init", replaceGlass)

-- Console commands for crack system
if SERVER then
    concommand.Add("glass_test_cracks", function(ply, cmd, args)
        if !ply:IsSuperAdmin() then return end
        
        local tr = ply:GetEyeTrace()
        if tr.Entity and tr.Entity:GetClass() == "procedural_shard" then
            local shard = tr.Entity
            local impact_pos = shard:WorldToLocal(tr.HitPos)
            shard.last_impact_normal = tr.HitNormal
            shard.last_impact_speed = 500
            shard:ShowCracks(impact_pos, tr.HitNormal)
            ply:ChatPrint("Showing test cracks on glass shard")
        else
            ply:ChatPrint("Look at a glass shard to test cracks")
        end
    end, nil, "Test crack visualization on looked-at glass shard (Admin only)")
    
    concommand.Add("glass_settings", function(ply, cmd, args)
        ply:ChatPrint("=== Glass Addon Settings ===")
        ply:ChatPrint("glass_realistic_breaking: " .. (realistic_breaking:GetBool() and "ON" or "OFF"))
        ply:ChatPrint("glass_show_cracks: " .. (show_cracks:GetBool() and "ON" or "OFF"))
        ply:ChatPrint("glass_crack_delay: " .. crack_delay:GetFloat() .. " seconds")
        ply:ChatPrint("glass_shard_count: " .. shard_count:GetInt() .. " (1=few, 7=many)")
        ply:ChatPrint("glass_rigidity: " .. glass_rigidity:GetFloat() .. " (0=fragile, 200=very strong)")
        ply:ChatPrint("glass_mass_factor: " .. mass_factor:GetFloat() .. " (0.5=less mass effect, 2.0=more)")
        ply:ChatPrint("glass_velocity_transfer: " .. velocity_transfer:GetFloat() .. " (0.5=less dramatic, 2.0=more)")
        ply:ChatPrint("glass_player_mass: " .. player_mass:GetInt() .. " kg")
        ply:ChatPrint("glass_player_break_speed: " .. player_break_speed:GetInt() .. " (100=walking, 250=sprinting)")
        ply:ChatPrint("glass_lagfriendly: " .. (use_expensive:GetBool() and "ON" or "OFF"))
    end, nil, "Show current glass addon settings")
    
    concommand.Add("glass_break_test", function(ply, cmd, args)
        if !ply:IsSuperAdmin() then return end
        
        local tr = ply:GetEyeTrace()
        if tr.Entity and tr.Entity:GetClass() == "procedural_shard" then
            local shard = tr.Entity
            if shard.CAN_BREAK then
                local impact_pos = shard:WorldToLocal(tr.HitPos)
                shard.last_impact_normal = tr.HitNormal
                shard.last_impact_speed = 500
                shard:Split(impact_pos, false, true) -- skip cracks for immediate break
                ply:ChatPrint("Breaking glass with " .. shard_count:GetInt() .. " shard count")
            else
                ply:ChatPrint("Glass is not breakable right now")
            end
        else
            ply:ChatPrint("Look at a glass shard to test breaking")
        end
    end, nil, "Immediately break looked-at glass to test shard count (Admin only)")
    
    concommand.Add("glass_reset_damage", function(ply, cmd, args)
        if !ply:IsSuperAdmin() then return end
        
        local tr = ply:GetEyeTrace()
        if tr.Entity and tr.Entity:GetClass() == "procedural_shard" then
            local shard = tr.Entity
            local old_damage = shard.accumulated_damage or 0
            shard.accumulated_damage = 0
            ply:ChatPrint("Reset glass damage from " .. math.Round(old_damage) .. " to 0")
        else
            ply:ChatPrint("Look at a glass shard to reset its damage")
        end
    end, nil, "Reset accumulated damage on looked-at glass (Admin only)")
    
    concommand.Add("glass_check_damage", function(ply, cmd, args)
        local tr = ply:GetEyeTrace()
        if tr.Entity and tr.Entity:GetClass() == "procedural_shard" then
            local shard = tr.Entity
            local current_damage = shard.accumulated_damage or 0
            local threshold = glass_rigidity:GetFloat()
            ply:ChatPrint("Glass damage: " .. math.Round(current_damage) .. "/" .. math.Round(threshold) .. " (" .. math.Round((current_damage/threshold)*100) .. "%)")
        else
            ply:ChatPrint("Look at a glass shard to check its damage")
        end
    end, nil, "Check accumulated damage on looked-at glass")
    
    concommand.Add("glass_impact_debug", function(ply, cmd, args)
        if !ply:IsSuperAdmin() then return end
        
        local tr = ply:GetEyeTrace()
        if tr.Entity and tr.Entity.GetPhysicsObject then
            local ent = tr.Entity
            local phys = ent:GetPhysicsObject()
            
            if !phys or !phys:IsValid() then
                ply:ChatPrint("Object has no valid physics object")
                return
            end
            
            local mass = phys:GetMass()
            local velocity = phys:GetVelocity():Length()
            
            -- Calculate the same impact force as the collision system
            local adjusted_mass = mass * mass_factor:GetFloat()
            local momentum = adjusted_mass * velocity
            local kinetic_energy = 0.5 * adjusted_mass * (velocity * velocity) / 1000
            local impact_force = momentum + (kinetic_energy * 0.1)
            local collision_damage = impact_force / 15
            
            ply:ChatPrint("=== Impact Analysis ===")
            ply:ChatPrint("Original Mass: " .. math.Round(mass, 1) .. " kg")
            ply:ChatPrint("Adjusted Mass: " .. math.Round(adjusted_mass, 1) .. " kg (factor: " .. mass_factor:GetFloat() .. ")")
            ply:ChatPrint("Velocity: " .. math.Round(velocity, 1) .. " units/s")
            ply:ChatPrint("Momentum: " .. math.Round(momentum, 1))
            ply:ChatPrint("Kinetic Energy: " .. math.Round(kinetic_energy, 1))
            ply:ChatPrint("Impact Force: " .. math.Round(impact_force, 1))
            ply:ChatPrint("Glass Damage: " .. math.Round(collision_damage, 1))
            
            -- Predict if this would break glass
            local threshold = glass_rigidity:GetFloat()
            local would_devastate = (impact_force > 8000 or velocity > 800 or (adjusted_mass > 50 and velocity > 400))
            
            if would_devastate then
                ply:ChatPrint("Result: INSTANT BREAK (devastating impact)")
            elseif collision_damage >= threshold then
                ply:ChatPrint("Result: WOULD BREAK (exceeds rigidity)")
            else
                ply:ChatPrint("Result: Would accumulate " .. math.Round(collision_damage, 1) .. "/" .. threshold .. " damage")
            end
        else
            ply:ChatPrint("Look at an object with physics to analyze its impact potential")
        end
    end, nil, "Analyze the impact force of looked-at object (Admin only)")
    
    concommand.Add("glass_player_debug", function(ply, cmd, args)
        local player_velocity = ply:GetVelocity()
        local player_speed = player_velocity:Length()
        local player_mass_kg = player_mass:GetInt()
        local min_break_speed = player_break_speed:GetInt()
        
        -- Calculate the same impact force as the touch system
        local adjusted_mass = player_mass_kg * mass_factor:GetFloat()
        local momentum = adjusted_mass * player_speed
        local kinetic_energy = 0.5 * adjusted_mass * (player_speed * player_speed) / 1000
        local impact_force = momentum + (kinetic_energy * 0.1)
        local collision_damage = impact_force / 15
        
        ply:ChatPrint("=== Player Impact Analysis ===")
        ply:ChatPrint("Current Speed: " .. math.Round(player_speed, 1) .. " units/s")
        ply:ChatPrint("Required Speed: " .. min_break_speed .. " units/s")
        ply:ChatPrint("Player Mass: " .. player_mass_kg .. " kg")
        ply:ChatPrint("Adjusted Mass: " .. math.Round(adjusted_mass, 1) .. " kg (factor: " .. mass_factor:GetFloat() .. ")")
        ply:ChatPrint("Momentum: " .. math.Round(momentum, 1))
        ply:ChatPrint("Kinetic Energy: " .. math.Round(kinetic_energy, 1))
        ply:ChatPrint("Impact Force: " .. math.Round(impact_force, 1))
        ply:ChatPrint("Glass Damage: " .. math.Round(collision_damage, 1))
        
        -- Predict if this would break glass
        local threshold = glass_rigidity:GetFloat()
        local is_fast_enough = player_speed >= min_break_speed
        local is_sprinting = player_speed > 250
        
        if !is_fast_enough then
            ply:ChatPrint("Result: TOO SLOW (need " .. (min_break_speed - player_speed) .. " more speed)")
        elseif is_sprinting or threshold <= 0 then
            ply:ChatPrint("Result: INSTANT BREAK (sprinting speed)")
        elseif collision_damage >= threshold then
            ply:ChatPrint("Result: WOULD BREAK (exceeds rigidity)")
        else
            ply:ChatPrint("Result: Would accumulate " .. math.Round(collision_damage, 1) .. "/" .. threshold .. " damage")
        end
        
        -- Movement tips
        if player_speed < 50 then
            ply:ChatPrint("Tip: Start moving to see impact analysis")
        elseif player_speed < min_break_speed then
            ply:ChatPrint("Tip: Run faster to break glass (hold SHIFT to sprint)")
        end
    end, nil, "Analyze your current glass-breaking potential")
    
    concommand.Add("glass_panel", function(ply, cmd, args)
        ply:ChatPrint("Opening Glass Settings Panel...")
        ply:ChatPrint("Run 'glass_open_panel' in console or check the Utilities > Glass Rewrite menu in your spawnmenu!")
    end, nil, "Instructions to open the glass settings panel")
end

-- Crack visualization system
function ENT:GenerateCrackLines(impact_pos, impact_normal)
    if !show_cracks:GetBool() then return {} end
    
    local crack_lines = {}
    local shard_size = self:BoundingRadius()
    local max_crack_length = shard_size * 0.8
    
    -- Convert impact position to surface position if we have a normal
    local surface_pos = impact_pos
    if impact_normal then
        -- Project impact point onto the glass surface using server-compatible bounds
        local bounds_min, bounds_max = self:OBBMins(), self:OBBMaxs()
        local surface_offset = (bounds_max.z - bounds_min.z) * 0.5
        surface_pos = impact_pos + impact_normal * surface_offset * 0.1
    end
    
    -- Generate primary radial cracks
    local primary_cracks = math.random(4, 7)
    for i = 1, primary_cracks do
        local angle = (i / primary_cracks) * math.pi * 2 + math.random(-0.3, 0.3)
        local crack_dir = Vector(math.cos(angle), math.sin(angle), math.random(-0.1, 0.1)):GetNormalized()
        
        -- Vary crack length based on impact strength
        local crack_length = max_crack_length * math.random(0.4, 1.0)
        if self.last_impact_speed then
            crack_length = crack_length * math.min(2.0, self.last_impact_speed / 200)
        end
        
        local crack_end = surface_pos + crack_dir * crack_length
        table.insert(crack_lines, {surface_pos, crack_end, 2.0}) -- start, end, width
    end
    
    -- Generate secondary branching cracks
    local secondary_cracks = math.random(2, 4)
    for i = 1, secondary_cracks do
        local base_angle = math.random() * math.pi * 2
        local branch_angle = base_angle + math.random(-0.8, 0.8)
        local crack_dir = Vector(math.cos(branch_angle), math.sin(branch_angle), math.random(-0.2, 0.2)):GetNormalized()
        
        -- Secondary cracks start partway along primary crack paths
        local start_offset = crack_dir:Cross(Vector(0, 0, 1)):GetNormalized() * math.random(10, 30)
        local crack_start = surface_pos + start_offset
        local crack_end = crack_start + crack_dir * (max_crack_length * math.random(0.2, 0.6))
        
        table.insert(crack_lines, {crack_start, crack_end, 1.5}) -- thinner secondary cracks
    end
    
    -- Generate small tertiary cracks for detail
    local detail_cracks = math.random(3, 6)
    for i = 1, detail_cracks do
        local random_angle = math.random() * math.pi * 2
        local crack_dir = Vector(math.cos(random_angle), math.sin(random_angle), math.random(-0.3, 0.3)):GetNormalized()
        
        local start_offset = VectorRand() * (shard_size * 0.3)
        local crack_start = surface_pos + start_offset
        local crack_end = crack_start + crack_dir * (max_crack_length * math.random(0.1, 0.3))
        
        table.insert(crack_lines, {crack_start, crack_end, 1.0}) -- thin detail cracks
    end
    
    return crack_lines
end

function ENT:ShowCracks(impact_pos, impact_normal)
    if !show_cracks:GetBool() then return end
    
    -- Generate crack pattern
    local crack_lines = self:GenerateCrackLines(impact_pos, impact_normal)
    if #crack_lines == 0 then return end
    
    -- Store cracks for rendering
    self.crack_lines = crack_lines
    self.crack_alpha = 255
    self.crack_start_time = CurTime()
    
    -- Play crack sound effect
    self:EmitSound("physics/glass/glass_strain" .. math.random(1, 4) .. ".wav", 60, math.random(90, 110))
    
    if CLIENT then
        -- Create crack mesh overlay
        self:UpdateCrackMesh()
    end
end

if CLIENT then
    function ENT:UpdateCrackMesh()
        if !self.crack_lines or #self.crack_lines == 0 then return end
        
        -- Create crack geometry
        local crack_verts = {}
        local vert_count = 0
        
        for _, crack_data in ipairs(self.crack_lines) do
            local start_pos, end_pos, width = crack_data[1], crack_data[2], crack_data[3]
            
            -- Create a thin quad for each crack line
            local crack_vec = (end_pos - start_pos):GetNormalized()
            local crack_perp = crack_vec:Cross(Vector(0, 0, 1)):GetNormalized() * (width * 0.5)
            
            -- Four corners of the crack quad
            local v1 = start_pos + crack_perp
            local v2 = start_pos - crack_perp  
            local v3 = end_pos - crack_perp
            local v4 = end_pos + crack_perp
            
            -- First triangle
            vert_count = vert_count + 1
            crack_verts[vert_count] = {pos = v1, normal = Vector(0, 0, 1), u = 0, v = 0}
            vert_count = vert_count + 1
            crack_verts[vert_count] = {pos = v2, normal = Vector(0, 0, 1), u = 1, v = 0}
            vert_count = vert_count + 1
            crack_verts[vert_count] = {pos = v3, normal = Vector(0, 0, 1), u = 1, v = 1}
            
            -- Second triangle
            vert_count = vert_count + 1
            crack_verts[vert_count] = {pos = v1, normal = Vector(0, 0, 1), u = 0, v = 0}
            vert_count = vert_count + 1
            crack_verts[vert_count] = {pos = v3, normal = Vector(0, 0, 1), u = 1, v = 1}
            vert_count = vert_count + 1
            crack_verts[vert_count] = {pos = v4, normal = Vector(0, 0, 1), u = 0, v = 1}
        end
        
        -- Create or update crack mesh
        if !self.crack_mesh then
            self.crack_mesh = Mesh()
        end
        
        if #crack_verts > 0 then
            self.crack_mesh:BuildFromTriangles(crack_verts)
        end
    end
    
    function ENT:DrawCracks()
        if !self.crack_lines or !self.crack_mesh then return end
        
        -- Fade out cracks over time
        local fade_time = crack_delay:GetFloat() * 0.8
        local time_since_crack = CurTime() - (self.crack_start_time or 0)
        
        if time_since_crack > fade_time then
            local fade_progress = math.min(1, (time_since_crack - fade_time) / (crack_delay:GetFloat() * 0.2))
            self.crack_alpha = 255 * (1 - fade_progress)
            
            if self.crack_alpha <= 10 then
                self.crack_lines = nil
                if self.crack_mesh then
                    self.crack_mesh:Destroy()
                    self.crack_mesh = nil
                end
                return
            end
        end
        
        -- Set up rendering for cracks
        render.SetMaterial(Material("effects/laser1"))
        render.SetColorMaterial()
        
        -- Draw crack mesh with transparency
        render.OverrideBlend(true, BLEND_SRC_ALPHA, BLEND_ONE_MINUS_SRC_ALPHA)
        render.SetColorModulation(0.1, 0.1, 0.1) -- Dark crack color
        
        local matrix = Matrix()
        matrix:SetTranslation(self:GetPos())
        matrix:SetAngles(self:GetAngles())
        
        cam.PushModelMatrix(matrix)
        self.crack_mesh:Draw()
        cam.PopModelMatrix()
        
        render.OverrideBlend(false)
    end
end
