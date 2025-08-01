AddCSLuaFile()

// functions used in program

// generates uvs and normals for visual meshes
-- Straight from Starfall: https://github.com/thegrb93/StarfallEx/blob/182f78686b441f19071daa8dca92f69390b413e0/lua/starfall/libs_sh/mesh.lua#L177
local function generateUV(vertices, scale) 
    local v = Vector()
    local a = Angle()
    local wtl = WorldToLocal
    local cross = v.Cross
    local getangle = v.Angle
    
    local function uv(vertex, ang)
        local p = wtl(vertex.pos, a, v, ang)
        vertex.u = p.y * scale
        vertex.v = p.z * scale
    end
    
    for i = 1, #vertices - 2, 3 do
        local a = vertices[i]
        if a.u then continue end
        local b = vertices[i + 1]
        local c = vertices[i + 2]
        local ang = getangle(cross(b.pos - a.pos, c.pos - a.pos))
        
        uv(a, ang)
        uv(b, ang)
        uv(c, ang)
    end
end

local function generateNormals(vertices) -- SF function
    local v = Vector()
    local cross = v.Cross
    local normalize = v.Normalize
    local dot = v.Dot
    local add = v.Add
    local div = v.Div
    local org = cross
    
    for i = 1, #vertices - 2, 3 do
        local a = vertices[i]
        if a.normal then continue end
        local b = vertices[i + 1]
        local c = vertices[i + 2]
        local norm = cross(c.pos - a.pos, b.pos - a.pos)
        normalize(norm)
        
        a.normal = norm
        b.normal = norm
        c.normal = norm

        //local n = cross(norm, Vector(1, 1, 1))
        //a.userdata = {n[1], n[2], n[3], 0}
        //b.userdata = a.userdata
        //c.userdata = a.userdata
    end
end

// takes input vertices and removes duplicate verts
local function simplify_vertices(verts, scale)
    local verts2 = {}
    local n = 0
    local average = Vector()
    
    -- New O(n) implementation using a hash set to track seen vertices.
    local seen_verts = {}
    
    for i = 1, #verts do
        local vert_pos = verts[i].pos or verts[i]
        
        -- Create a unique key for the vertex position by rounding it.
        -- This groups vertices that are very close together, achieving the same
        -- goal as the old distance check, but much more efficiently.
        local key = (math.floor(vert_pos.x * 10) .. "," .. math.floor(vert_pos.y * 10) .. "," .. math.floor(vert_pos.z * 10))

        if not seen_verts[key] then
            seen_verts[key] = true
            n = n + 1
            verts2[n] = vert_pos
            average = average + vert_pos
        end
    end

    if n == 0 then return {}, Vector() end

    average = average / n

    for i = 1, #verts2 do
        verts2[i] = verts2[i] - average
        verts2[i] = verts2[i] * scale
    end

    return verts2, average
end

// tris are in the format {{pos = value}, {pos = value2}}
local function split_convex(tris, plane_pos, plane_dir)
    if !tris then return {} end
    local plane_dir = plane_dir:GetNormalized()     // normalize plane direction
    local split_tris = {}
    local plane_points = {}
    // loop through all triangles in the mesh
    local util_IntersectRayWithPlane = util.IntersectRayWithPlane
    local table_insert = table.insert
    for i = 1, #tris, 3 do
        local pos1 = tris[i    ]
        local pos2 = tris[i + 1]
        local pos3 = tris[i + 2]
        if tris[i].pos then
            pos1 = tris[i    ].pos
            pos2 = tris[i + 1].pos
            pos3 = tris[i + 2].pos
        end

        // get points that are valid sides of the plane

        //if !pos1 or !pos2 or !pos3 then continue end      // just in case??

        local pos1_valid = (pos1 - plane_pos):Dot(plane_dir) > 0
        local pos2_valid = (pos2 - plane_pos):Dot(plane_dir) > 0
        local pos3_valid = (pos3 - plane_pos):Dot(plane_dir) > 0
        
        // if all points should be kept, add triangle
        if pos1_valid and pos2_valid and pos3_valid then 
            table_insert(split_tris, pos1)
            table_insert(split_tris, pos2)
            table_insert(split_tris, pos3)
            continue
        end
        
        // if none of the points should be kept, skip triangle
        if !pos1_valid and !pos2_valid and !pos3_valid then 
            continue 
        end
        
        local new_tris_index = 0    // optimization because table.insert is garbage
        local new_tris = {}
        
        // all possible states of the intersected triangle
        // extremely fast since a max of 4 if statments are required
        local point1
        local point2
        local is_flipped = false
        if pos1_valid then
            if pos2_valid then      //pos1 = valid, pos2 = valid, pos3 = invalid
                point1 = util_IntersectRayWithPlane(pos1, pos3 - pos1, plane_pos, plane_dir)
                point2 = util_IntersectRayWithPlane(pos2, pos3 - pos2, plane_pos, plane_dir)
                if !point1 then point1 = pos3 end
                if !point2 then point2 = pos3 end
                new_tris[new_tris_index + 1] = pos1
                new_tris[new_tris_index + 2] = pos2
                new_tris[new_tris_index + 3] = point1

                new_tris[new_tris_index + 4] = point2
                new_tris[new_tris_index + 5] = point1
                new_tris[new_tris_index + 6] = pos2
                new_tris_index = new_tris_index + 6
                is_flipped = true
            elseif pos3_valid then  // pos1 = valid, pos2 = invalid, pos3 = valid
                point1 = util_IntersectRayWithPlane(pos1, pos2 - pos1, plane_pos, plane_dir)
                point2 = util_IntersectRayWithPlane(pos3, pos2 - pos3, plane_pos, plane_dir)
                if !point1 then point1 = pos2 end
                if !point2 then point2 = pos2 end
                new_tris[new_tris_index + 1] = point1
                new_tris[new_tris_index + 2] = pos3
                new_tris[new_tris_index + 3] = pos1

                new_tris[new_tris_index + 4] = pos3
                new_tris[new_tris_index + 5] = point1
                new_tris[new_tris_index + 6] = point2
                new_tris_index = new_tris_index + 6
            else                    // pos1 = valid, pos2 = invalid, pos3 = invalid
                point1 = util_IntersectRayWithPlane(pos1, pos2 - pos1, plane_pos, plane_dir)
                point2 = util_IntersectRayWithPlane(pos1, pos3 - pos1, plane_pos, plane_dir)
                if !point1 then point1 = pos2 end
                if !point2 then point2 = pos3 end
                new_tris[new_tris_index + 1] = pos1
                new_tris[new_tris_index + 2] = point1
                new_tris[new_tris_index + 3] = point2
                new_tris_index = new_tris_index + 3
            end
        elseif pos2_valid then
            if pos3_valid then      // pos1 = invalid, pos2 = valid, pos3 = valid
                point1 = util_IntersectRayWithPlane(pos2, pos1 - pos2, plane_pos, plane_dir)
                point2 = util_IntersectRayWithPlane(pos3, pos1 - pos3, plane_pos, plane_dir)
                if !point1 then point1 = pos1 end
                if !point2 then point2 = pos1 end
                new_tris[new_tris_index + 1] = pos2
                new_tris[new_tris_index + 2] = pos3
                new_tris[new_tris_index + 3] = point1

                new_tris[new_tris_index + 4] = point2
                new_tris[new_tris_index + 5] = point1
                new_tris[new_tris_index + 6] = pos3
                new_tris_index = new_tris_index + 6
                is_flipped = true 
            else                    // pos1 = invalid, pos2 = valid, pos3 = invalid
                point1 = util_IntersectRayWithPlane(pos2, pos1 - pos2, plane_pos, plane_dir)
                point2 = util_IntersectRayWithPlane(pos2, pos3 - pos2, plane_pos, plane_dir)
                if !point1 then point1 = pos1 end
                if !point2 then point2 = pos3 end
                new_tris[new_tris_index + 1] = point2
                new_tris[new_tris_index + 2] = point1
                new_tris[new_tris_index + 3] = pos2
                new_tris_index = new_tris_index + 3
                is_flipped = true
            end
        else                       // pos1 = invalid, pos2 = invalid, pos3 = valid
            point1 = util_IntersectRayWithPlane(pos3, pos1 - pos3, plane_pos, plane_dir)
            point2 = util_IntersectRayWithPlane(pos3, pos2 - pos3, plane_pos, plane_dir)
            if !point1 then point1 = pos1 end
            if !point2 then point2 = pos2 end
            new_tris[new_tris_index + 1] = pos3
            new_tris[new_tris_index + 2] = point1
            new_tris[new_tris_index + 3] = point2
            new_tris_index = new_tris_index + 3
        end
    
        table.Add(split_tris, new_tris)
        if is_flipped then
            table_insert(plane_points, point1)
            table_insert(plane_points, point2)
        else
            table_insert(plane_points, point2)
            table_insert(plane_points, point1)
        end
    end
    
    // add triangles inside of the object
    // each 2 points is an edge, create a triangle between the egde and first point
    // start at index 4 since the first edge (1-2) cant exist since we are wrapping around the first point
    //PrintTable(plane_points)
    for i = 4, #plane_points, 2 do
        table_insert(split_tris, plane_points[1    ])
        table_insert(split_tris, plane_points[i - 1])
        table_insert(split_tris, plane_points[i    ])
    end

    --[[
    local original_point = Vector()
    for k, v in ipairs(plane_points) do
        original_point = original_point + v
    end
    original_point = original_point / #plane_points

    local sorted_plane_points = {}
    local plane_right = plane_dir:Cross(Vector(0, 0, 1))
    local plane_forward = plane_dir:Cross(plane_right)
    for i = 1, #plane_points do 
        local plane_point = plane_points[i]
        local compare_angle = (plane_point - original_point)
        local compare_angle_final = math.atan2(compare_angle:Dot(plane_forward), compare_angle:Dot(plane_right))

        // find where to insert new point in sorted_plane_points
        local sorted_position = #sorted_plane_points + 1
        for j = 1, #sorted_plane_points do 
            local compare_angle = (sorted_plane_points[j] - original_point)
            local compare_angle_final_2 = math.atan2(compare_angle:Dot(plane_forward), compare_angle:Dot(plane_right))
            if compare_angle_final_2 > compare_angle_final then
                sorted_position = j
                break
            end
        end
        table.insert(sorted_plane_points, sorted_position, plane_point)
    end

    for i = 3, #sorted_plane_points do
        table_insert(split_tris, sorted_plane_points[1    ])
        table_insert(split_tris, sorted_plane_points[i - 1])
        table_insert(split_tris, sorted_plane_points[i    ])
    end]]

    return split_tris
end

-- Checks if a set of vertices can form a valid 3D physics object.
-- If the shape is degenerate (e.g., flat), it returns a minimal, valid
-- tetrahedron centered on the original shape's average position.
-- This prevents the "CreateConvexObjectFromTableOfVerts: Invalid vertices" engine error.
local function are_verts_valid_for_phys(verts)
    -- A physics object needs at least 4 vertices to define a volume.
    if #verts < 4 then 
        local center = Vector(0,0,0)
        if #verts > 0 then
            for i=1, #verts do center = center + verts[i] end
            center = center / #verts
        end
        return {
            center + Vector(1, -1, -1),
            center + Vector(-1, -1, -1),
            center + Vector(0, 1, -1),
            center + Vector(0, 0, 1),
        }
    end

    -- To have a volume, the vertices can't all lie on the same plane.
    -- We check this by trying to find 4 non-coplanar points.
    local p1 = verts[1]
    local p2, p3

    -- Find the second point, must be distinct from the first.
    for i = 2, #verts do
        if (verts[i] - p1):LengthSqr() > 0.1 then
            p2 = verts[i]
            break
        end
    end
    if not p2 then return false end -- All points are in the same spot.

    -- Find the third point, must not be on the line between p1 and p2.
    local line_dir = (p2 - p1):GetNormalized()
    for i = 3, #verts do
        if not verts[i] or not verts[i].Dot then continue end -- Safety check for valid vectors
        if math.abs(line_dir:Dot((verts[i] - p1):GetNormalized())) < 0.999 then
            p3 = verts[i]
            break
        end
    end
    if not p3 then return false end -- All points are on the same line.

    -- Find the fourth point, must not be on the plane defined by p1, p2, p3.
    local plane_normal = (p2 - p1):Cross(p3 - p1):GetNormalized()
    for i = 4, #verts do
        if not verts[i] or not verts[i].Dot then continue end -- Safety check for valid vectors
        -- The distance from a point to a plane is the dot product of the vector
        -- from a point on the plane to the point, and the plane's normal vector.
        local dist_from_plane = math.abs((verts[i] - p1):Dot(plane_normal))
        if dist_from_plane > 0.1 then
            -- This point is not on the plane, so we have a volume.
            return verts -- The original vertices are valid.
        end
    end

    -- If we get here, all points were on the same plane.
    -- Create a minimal tetrahedron centered at the average position of the flat shard.
    local center = (p1 + p2 + p3) / 3
    return {
        center + Vector(1, -1, -1),
        center + Vector(-1, -1, -1),
        center + Vector(0, 1, -1),
        center + Vector(0, 0, 1),
    }
end

return generateUV, generateNormals, simplify_vertices, split_convex, are_verts_valid_for_phys
