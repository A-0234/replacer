
replacer = {
    -- 2x MkII drill.
    charge = 400000,
    -- Nodes that can be replaced per full charge.
    nodes = 3000,
    -- Maximum square mode.
    max_square = 3,
    blacklist = {},
}

-- Calculate per-node charge.
replacer.per = replacer.charge / replacer.nodes

-- Blacklisted nodes cannot be placed by the tool.
function replacer.register_blacklisted_node(name)
    replacer.blacklist[name] = true
end

-- Builtin blacklist.
replacer.register_blacklisted_node("air")
replacer.register_blacklisted_node("ignore")

local name = {
    "Node",
    "3x3",
    "5x5",
}

for i = 1, replacer.max_square do
    for _, place in ipairs((i == 1) and {false, true} or {false}) do
        local ncur = "replacer:replacer" .. i
        local nnext = "replacer:replacer" ..
            ((i == replacer.max_square) and 1 or (i + 1))
        local desc = "Node Replacer (" .. (name[i] or "Square " .. i) .. ")"

        if place then
            ncur = "replacer:replacer_p"
            nnext = "replacer:replacer_p"
            desc = "Node Replacer (Place)"
        end

        technic.register_power_tool(ncur, replacer.charge)

        local function handle_meta(s, node)
            local meta = minetest.deserialize(s:get_metadata())

            if not meta or not meta.charge then
                meta = {
                    charge = 0,
                }
            end

            -- Set item from available sources, revert to default:cobble if no other node is specified.
            meta.item = node or
                ((meta.item and meta.item.name) and meta.item) or {
                    name = "default:cobble",
                    param1 = 0,
                    param2 = 0,
                }

            s:set_metadata(minetest.serialize(meta))
            s:get_meta():set_string(
                "description",
                minetest.registered_items[s:get_name()].description ..
                " (" .. meta.item.name .. " " ..
                (meta.item.param1 or 0) .. " " ..
                (meta.item.param2 or 0) .. ")"
            )

            return s, meta.item
        end

        minetest.register_tool(ncur, {
            description = desc,
            inventory_image = "replacer_replacer.png^technic_tool_mode" .. i .. ".png",
            wield_image = "replacer_replacer.png",
            liquids_pointable = true,
            groups = {
                not_in_creative_inventory = (i == 1) and 0 or 1,
            },

            wear_represents = "technic_RE_charge",
            on_refill = technic.refill_RE_charge,

            on_place = function(itemstack, user, pointed_thing)
                local player_name = user:get_player_name()

                if user:get_player_control().aux1 then
                    itemstack:set_name(
                        place and "replacer:replacer1"
                        or "replacer:replacer_p"
                    )
                    itemstack = handle_meta(itemstack)

                    minetest.chat_send_player(
                        player_name,
                        minetest.registered_items[itemstack:get_name()].description
                    )
                    return itemstack
                end

                local function set_node()
                    if pointed_thing.type ~= "node" then
                        minetest.chat_send_player(
                            player_name,
                            "Error: No node selected."
                        )
                        return itemstack
                    end

                    local pos = minetest.get_pointed_thing_position(pointed_thing)
                    local node = minetest.get_node_or_nil(pos)

                    if not node then
                        minetest.chat_send_player(
                            player_name,
                            "Error: Node not yet loaded."
                        )
                        return itemstack
                    end

                    if replacer.blacklist[node.name] then
                        minetest.chat_send_player(
                            player_name,
                            "You cannot use that node in a replacer."
                        )
                        return itemstack
                    end

                    -- Select the node type to replace with.
                    local item
                    itemstack, item = handle_meta(itemstack, node)

                    minetest.chat_send_player(
                        player_name,
                        "Node Replacer: " .. item.name
                    )

                    return itemstack
                end

                if user:get_player_control().sneak then
                    if place then
                        return set_node()
                    else
                        itemstack:set_name(nnext)
                        itemstack = handle_meta(itemstack)

                        minetest.chat_send_player(
                            player_name,
                            minetest.registered_items[nnext].description
                        )

                        return itemstack
                    end
                end

                if place then
                    return minetest.registered_items[ncur].on_use(
                        itemstack,
                        user,
                        pointed_thing,
                        true
                    )
                else
                    return set_node()
                end
            end,

            on_use = function(itemstack, user, pointed_thing, do_place)
                local player_name = user:get_player_name()
                local _, item = handle_meta(itemstack)

                if pointed_thing.type ~= "node" then
                    minetest.chat_send_player(
                        player_name,
                        "Error: No node selected"
                    )
                    return itemstack
                end

                local pos = minetest.get_pointed_thing_position(
                    pointed_thing,
                    do_place
                )

                local node = minetest.get_node_or_nil(pos)

                if not node then
                    minetest.chat_send_player(
                        player_name,
                        "Error: Node not yet loaded."
                    )
                    return itemstack
                end

                if replacer.blacklist[node.name] then
                    minetest.chat_send_player(
                        player_name,
                        "You cannot use that node in a replacer."
                    )
                    return itemstack
                end

                -- Determine the plane perpendicular to the player's look direction.
                local look = user:get_look_dir()
                local extreme = "x"

                for _, c in ipairs({"y", "z"}) do
                    if math.abs(look[c]) > math.abs(look[extreme]) then
                        extreme = c
                    end
                end

                local coords = {
                    x = true,
                    y = true,
                    z = true,
                }

                coords[extreme] = nil

                local r = vector.new()

                for c in pairs(coords) do
                    r[c] = i - 1
                end

                local nodes = minetest.find_nodes_in_area(
                    vector.subtract(pos, r),
                    vector.add(pos, r),
                    {node.name}
                )

                -- Filter protected positions before consuming resources.
                local allowed_nodes = {}

                for _, p in ipairs(nodes) do
                    local current = minetest.get_node_or_nil(p)

                    if current
                            and current.name == node.name
                            and not minetest.is_protected(p, player_name) then
                        table.insert(allowed_nodes, p)
                    end
                end

                if #allowed_nodes == 0 then
                    minetest.chat_send_player(
                        player_name,
                        "Error: No replaceable nodes."
                    )
                    return itemstack
                end

                local inv = user:get_inventory()
                local old = inv:get_list("main") or {}

                -- Count available replacement items.
                local item_count = 0

                for _, stack in ipairs(old) do
                    if stack:get_name() == item.name then
                        item_count = item_count + stack:get_count()
                    end
                end

                if item_count < #allowed_nodes then
                    minetest.chat_send_player(
                        player_name,
                        "Error: Inventory does not contain necessary items."
                    )
                    return itemstack
                end

                -- Check charge before modifying nodes.
                local meta = minetest.deserialize(itemstack:get_metadata())

                if not meta or type(meta.charge) ~= "number" then
                    meta = {
                        charge = 0,
                    }
                end

                local cost = replacer.per * #allowed_nodes

                if meta.charge < cost then
                    minetest.chat_send_player(
                        player_name,
                        "Error: Not enough charge."
                    )
                    return itemstack
                end

                -- Replace each eligible target exactly once.
                local replaced = 0

                for _, p in ipairs(allowed_nodes) do
                    local current = minetest.get_node_or_nil(p)

                    if current
                            and current.name == node.name
                            and not minetest.is_protected(p, player_name) then

                        if do_place then
                            -- Place mode: replace directly at the target.
                            -- No digging and no extra node above the target.
                            local removed = inv:remove_item(
                                "main",
                                ItemStack(item.name)
                            )

                            if not removed:is_empty() then
                                minetest.set_node(p, item)
                                replaced = replaced + 1
                            end
                        else
                            -- Normal mode: dig first, then replace at the same position.
                            local removed = inv:remove_item(
                                "main",
                                ItemStack(item.name)
                            )

                            if not removed:is_empty() then
                                minetest.node_dig(p, current, user)

                                local after = minetest.get_node_or_nil(p)

                                if after and after.name == "air" then
                                    minetest.set_node(p, item)
                                    replaced = replaced + 1
                                else
                                    -- Restore the replacement item if digging failed.
                                    inv:add_item("main", removed)
                                end
                            end
                        end
                    end
                end

                -- Charge only for successful replacements.
                if replaced > 0 then
                    meta.charge = math.max(
                        0,
                        meta.charge - replacer.per * replaced
                    )

                    technic.set_RE_wear(
                        itemstack,
                        meta.charge,
                        replacer.charge
                    )

                    itemstack:set_metadata(minetest.serialize(meta))
                end

                return itemstack
            end,
        })
    end
end

minetest.register_alias("replacer:replacer", "replacer:replacer1")

for _, drill in ipairs({"", "_1", "_2", "_3", "_4", "_5"}) do
    minetest.register_craft({
        output = "replacer:replacer1",
        recipe = {
            {
                "technic:diamond_drill_head",
                "technic:mining_drill_mk3" .. drill,
                "technic:diamond_drill_head",
            },
            {
                "technic:stainless_steel_ingot",
                "technic:motor",
                "technic:stainless_steel_ingot",
            },
            {
                "pipeworks:filter",
                "technic:blue_energy_crystal",
                "default:copper_ingot",
            },
        },
    })
end
