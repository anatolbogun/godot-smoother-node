# godot-smoother-node
A Godot node type that smoothes scene nodes' movements by interpolating between _physics_process steps.

![godot-smoother-node-comparison](https://user-images.githubusercontent.com/7110246/209284462-fef6365a-a0b2-49c3-8747-b93ec18933fc.gif)
Above: Not smoothed vs. smoothed (player movements are not synced, these are 2 separate runs).

## Smoother node
This node interpolates the position of other nodes between their `_physics_process` es. The interpolation is applied in the `_process` loop which ensures that nodes move smoothly, even if the `_physics_process` is called less often than the games fps rate which is typically synced to the current screen's refresh rate.

### Notes:
- By default this node applies to its parent, siblings and recursive children. Nodes that have no custom `_physics_process` code or a position property are automatically ignored.

- The most common scenario is to make it a direct child of the root node, e.g. in a level scene. By default it will then smooth the parent, all children and deep nested children in the same scene tree.
- If the smoother should be applied to only specific nodes, just select those nodes in the includes option and disable `smooth_parent` and `recursive`, or give each node that should be smoothed a Smoother node child with the `recursive` option off.
- The `excludes` option ignores nodes that would otherwise be covered by other Smoother options, even when the same nodes are listed in `includes`.
- Collision detection still happens in the `_physics_process`, so if the `physics_ticks_per_second` value in the project settings is too low you may experience seemingly incorrect or punishing collision detection. The default 60 `physics_ticks_per_second` should a good choice. To test this node you may want to temporarily reduce physics ticks to a lower value and toggle this node on and off.
- The code will keep this node as the first child of the parent node because its `_physics_process` and `_process` code must run before any other nodes.
- When `smooth_parent` is enabled the `process_priority` will be kept at a lower value than the parent's, i.e. it will be processed earlier.
- When teleporting a sprite you may want to call `reset_node(node)` or `reset_node_path(path)` for the affected sprite/s, otherwise a teleport (changing the position) may not work as expected.
- Performance optimisations: For large levels you may want to optimise things (as you probably should regardless of using the Smoother node). A good approach would be to use the `VisibleOnScreenNotifier2D` to update the `includes` or `excludes` array:
  1. Add all off-screen moveable nodes to `excludes` (`$Smoother.add_exclude_node(node)`) and remove them when they come on-screen (`$Smoother.remove_exclude_node(node)`). Since excludes overwrite all other Smoother options this is the most flexible option. One caveat is that on entering the tree, the `$VisibleOnScreenNotifier2D` does not fire the `screen_exited` signal, so you may have to emit this in a Node's `func _enter_tree` via `$VisibleOnScreenNotifier2D.is_on_screen()`.
  2. Add all on-screen moveable nodes to `includes` (`$Smoother.add_include_node(node)`) and remove them when they come off-screen (`$Smoother.remove_include_node(node)`). Since `includes` adds nodes but does not interfere with other options you probably should set the `smooth_parent` and `recursive` options to `false`. On entering the tree, the `VisibleOnScreenNotifier2D` automatically fires the `screen_entered` signal, so nothing needs to be done.
- For both performance optimisation methods above it's probably a good idea to emit the `screen_exited` signal on `_exit_tree`. You can always check the currently smoothed nodes, e.g.
  ```
  print("smoothed nodes: ", $Smoother.smoothed_nodes.map(func (node:Node): return node.name))
  ```
- For easier understanding of the code, consider:
	`_positions[node][0]` is the origin position
	`_positions[node][1]` is the target position

### Limitations:
- Currently this does not work with `RigidBody2D` or `RigidBody3D` nodes. Please check out https://github.com/lawnjelly/smoothing-addon/ which has a more complicated setup but has more precision and less limitations. Or help to make this code work with rigid bodies if it's possible at all.
- Interpolation is one `_physics_process` step behind because we need to know the origin and target value for an interpolation to occur, so in a typical scenario this means a delay of 1/60 second which is the default `physics_ticks_per_second` in the project settings.
- Interpolation does not look ahead for collision detection. That means that if for example a sprite falls to hit the ground and the last `_physics_process` step before impact is very close to the ground, interpolation will still occur on all `_physics` frames between which may have a
  slight impact cushioning effect. However, with 60 physics fps this is hopefully negligible.
- This is Godot 4+, but feel free to fork the project and make adjustments. It's probably not too hard to backport it since it only relies on other nodes' position properties.
