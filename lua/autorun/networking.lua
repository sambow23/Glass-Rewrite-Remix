AddCSLuaFile()

local generateUV, generateNormals, simplify_vertices, split_convex, split_entity = include("world_functions.lua")

// networking
if SERVER then
    util.AddNetworkString("SHARD_NETWORK")
    util.AddNetworkString("GLASS_SHOW_CRACKS")
    util.AddNetworkString("GLASS_NO_COLLIDE")

    // Track player interactions with physics objects for better collision detection
    hook.Add("PlayerUse", "glass_track_player_use", function(ply, ent)
        if ent and ent:IsValid() and ent:GetPhysicsObject():IsValid() then
            ent.last_player_touch = {
                player = ply,
                time = CurTime()
            }
        end
    end)
    
    hook.Add("PhysgunPickup", "glass_track_physgun", function(ply, ent)
        if ent and ent:IsValid() and ent:GetPhysicsObject():IsValid() then
            ent.last_player_touch = {
                player = ply,
                time = CurTime()
            }
        end
    end)

    // must be from client requesting data, send back shard data
    net.Receive("SHARD_NETWORK", function(len, ply)
        local shard = net.ReadEntity()
        if not shard:IsValid() or not shard.TRIANGLES then return end
        
        local triangles = shard.TRIANGLES
        if not triangles or #triangles == 0 then return end
        
        net.Start("SHARD_NETWORK")
        net.WriteUInt(shard:EntIndex(), 16)
        
        // Write vertex count
        net.WriteUInt(#triangles, 16)
        
        // Write each vertex's position
        for _, tri in ipairs(triangles) do
            local pos = tri.pos
            net.WriteFloat(pos.x)
            net.WriteFloat(pos.y)
            net.WriteFloat(pos.z)
        end
        net.Send(ply)
    end)
else
    // NEW: Receive finalized vertex data and build the visual mesh
    net.Receive("SHARD_NETWORK", function(len)
        local shard_index = net.ReadUInt(16)
        local vertex_count = net.ReadUInt(16)
        
        if vertex_count == 0 then return end

        local model_triangles = {}
        for i = 1, vertex_count do
            local pos_x = net.ReadFloat()
            local pos_y = net.ReadFloat()
            local pos_z = net.ReadFloat()
            
            // Reconstruct the vertex table structure
            model_triangles[i] = { pos = Vector(pos_x, pos_y, pos_z) }
        end

        // Try and find shard on client within 10 seconds
        timer.Create("try_shard" .. shard_index, 0.1, 100, function()
            local shard_entity = Entity(shard_index)
            if not shard_entity:IsValid() then return end
            
            // We have the exact triangles, no need to do any splitting
            shard_entity.TRIANGLES = model_triangles

            // generate missing normals and uvs
            generateUV(shard_entity.TRIANGLES, -1/50)
            generateNormals(shard_entity.TRIANGLES)

            // Build the visual mesh
            if shard_entity.RENDER_MESH and shard_entity.RENDER_MESH.Mesh:IsValid() then
                shard_entity.RENDER_MESH.Mesh:Destroy()
            end
            shard_entity.RENDER_MESH.Mesh = Mesh()
            shard_entity.RENDER_MESH.Mesh:BuildFromTriangles(shard_entity.TRIANGLES)

            // Hide the original reference shard if it exists
            local reference_shard = shard_entity:GetReferenceShard()
            if reference_shard:IsValid() then
                reference_shard:SetNoDraw(true)
            end

            // Stop this timer
            timer.Remove("try_shard" .. shard_index)
        end)
    end)
    
    // Receive crack visualization data
    net.Receive("GLASS_SHOW_CRACKS", function(len)
        local shard_entity = net.ReadEntity()
        local impact_pos = net.ReadVector()
        local impact_normal = net.ReadVector()
        local explode = net.ReadBool()
        
        if not shard_entity or not shard_entity:IsValid() then return end
        
        // Convert to local coordinates
        local local_pos = shard_entity:WorldToLocal(shard_entity:GetPos() + impact_pos)
        local local_normal = shard_entity:WorldToLocalAngles(impact_normal:Angle()):Forward()
        
        // Show cracks on client
        timer.Simple(0, function() // slight delay to ensure entity is ready
            if shard_entity and shard_entity:IsValid() and shard_entity.ShowCracks then
                shard_entity:ShowCracks(local_pos, local_normal)
            end
        end)
    end)
    
    // Receive glass no-collide data
    net.Receive("GLASS_NO_COLLIDE", function(len)
        local shard_entity = net.ReadEntity()
        local player_entity = net.ReadEntity()
        local should_be_passable = net.ReadBool()
        
        if not shard_entity or not shard_entity:IsValid() then return end
        
        if should_be_passable and player_entity and player_entity:IsValid() then
            shard_entity.passable_to_player = player_entity
            shard_entity:SetCollisionGroup(COLLISION_GROUP_PASSABLE_DOOR)
        else
            shard_entity.passable_to_player = nil
            shard_entity:SetCollisionGroup(COLLISION_GROUP_DEBRIS)
        end
    end)
end	

if SERVER then return end

// client initialize
hook.Add("InitPostEntity", "glass_init", function()
	timer.Simple(1, function()	// let SENT functions initialize, unsure why they arent in this hook.
		for k, v in ipairs(ents.FindByClass("procedural_shard")) do
			v:Initialize(true)
		end

		// tell server to send ALL shard data
		net.Start("SHARD_NETWORK")
		net.SendToServer()
	end)
end)
