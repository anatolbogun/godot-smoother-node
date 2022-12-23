# MIT LICENSE
#
# Copyright 2022 Anatol Bogun
#
# Permission is hereby granted, free of charge, to any person obtaining a copy of this software and
# associated documentation files (the "Software"), to deal in the Software without restriction,
# including without limitation the rights to use, copy, modify, merge, publish, distribute,
# sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all copies or
# substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT
# NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
# DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
#
#
# SMOOTHER NODE
# -------------
#
# This node interpolates the position of other nodes between their _physics_process es. The
# interpolation is applied in the _process loop which ensures that nodes move smoothly, even if the
# _physics_process is called less often than the games fps rate which is typically synced to the
# current screen's refresh rate.
#
# NOTES:
# - By default this node applies to its parent, siblings and recursive children. Nodes that have no
#   custom _physics_process code or a position property are automatically ignored.
# - The most common scenario is to make it a direct child of the root node, e.g. in a level scene.
#   By default it will then smooth the parent, all children and deep nested children in the same
#   scene tree.
# - If the smoother should be applied to only specific nodes, just select those nodes in the
#   includes option and disable smooth_parent and recursive, or give each node that should be
#   smoothed a Smoother node child with the recursive option off.
# - The excludes option ignores nodes that would otherwise be covered by other Smoother options,
#   even when the same nodes are listed in includes.
# - Collision detection still happens in the _physics_process, so if the physics_ticks_per_second
#   value in the project settings is too low you may experience seemingly incorrect or punishing
#   collision detection. The default 60 physics_ticks_per_second should a good choice. To test this
#   node you may want to temporarily reduce physics ticks to a lower value and toggle this node on
#   and off.
# - The code will keep this node as the first child of the parent node because its _physics_process
#   and _process code must run before any other nodes.
# - When smooth_parent is enabled the process_priority will be kept at a lower value than the
#   parent's, i.e. it will be processed earlier.
# - When teleporting a sprite you may want to call reset_node(node) or reset_node_path(path) for the
#   affected sprite/s, otherwise a teleport (changing the position) may not work as expected.
# - Performance optimisations: For large levels you may want to optimise things (as you probably
#   should regardless of using the Smoother node). A good approach would be to use the
#   VisibleOnScreenNotifier2D to update the includes or excludes array:
#   1. Add all off-screen moveable nodes to excludes ($Smoother.add_exclude_node(node)) and remove
#      them when they come on-screen ($Smoother.remove_exclude_node(node)). Since excludes overwrite
#      all other Smoother options this is the most flexible option. One caveat is that on entering
#      the tree, the $VisibleOnScreenNotifier2D does not fire the screen_exited signal, so you may
#      have to emit this in a Node's func _enter_tree via $VisibleOnScreenNotifier2D.is_on_screen().
#   2. Add all on-screen moveable nodes to includes ($Smoother.add_include_node(node)) and remove
#      them when they come off-screen ($Smoother.remove_include_node(node)). Since includes adds
#      nodes but does not interfere with other options you probably should set the smooth_parent and
#      recursive options to false. On entering the tree, the VisibleOnScreenNotifier2D
#      automatically fires the screen_entered signal, so nothing needs to be done.
#   For both methods it's probably a good idea to emit the screen_exited signal on _exit_tree.
#   You can always check the currently smoothed nodes, e.g.
#   print("smoothed nodes: ", $Smoother.smoothed_nodes.map(func (node:Node): return node.name))
# - For easier understanding of the code, consider:
#	_positions[node][0] is the origin position
#	_positions[node][1] is the target position
#
# LIMITATIONS:
# - Currently this does not work with RigidBody2D or RigidBody3D nodes. Please check out
#   https://github.com/lawnjelly/smoothing-addon/ which has a more complicated setup but has more
#   precision and less limitations. Or help to make this code work with rigid bodies if it's
#   possible at all.
# - Interpolation is one _physics_process step behind because we need to know the origin and target
#   value for an interpolation to occur, so in a typical scenario this means a delay of 1/60 second
#   which is the default physics_ticks_per_second in the project settings.
# - Interpolation does not look ahead for collision detection. That means that if for example a
#   sprite falls to hit the ground and the last _physics_process step before impact is very close
#   to the ground, interpolation will still occur on all _physics frames between which may have a
#   slight impact cushioning effect. However, with 60 physics fps this is hopefully negligible.


class_name Smoother extends Node


@export var smooth_parent: = true :
	set (value):
		if value == false:
			# remove parent from _positions in case this gets toggled on and off during runtime
			_positions.erase(get_parent())

		smooth_parent = value

@export var recursive: = true
@export var includes:Array[NodePath] = []
@export var excludes:Array[NodePath] = []

# get an array of all currently smoothed nodes; mainly for debugging performance optimisations
var smoothed_nodes:Array[Node] :
	get:
		var parent: = get_parent()
		return _get_physics_process_nodes(parent, !smooth_parent) if parent != null else []

var _positions: = {}
var _physics_process_nodes:Array[Node]
var _physics_process_just_updated: = false


# reset all smoothed nodes
func reset() -> void:
	_positions.clear()


# reset a specific node; you may want to call this when a node gets teleported
func reset_node(node:Node) -> void:
	_positions.erase(node)


# reset a specific Node by NodePath; you may want to call this when a Node gets teleported
func reset_node_path(path:NodePath) -> void:
	var node: = get_node_or_null(path)

	if node != null:
		reset_node(node)


# add a Node to the includes Array[NodePath]
func add_include_node(node:Node) -> Array[NodePath]:
	return add_include_path(get_path_to(node))


# add a NodePath to the includes Array[NodePath]
func add_include_path(path:NodePath) -> Array[NodePath]:
	return _add_unique_to_array(includes, path)


# remove a Node from the includes Array[NodePath]
func remove_include_node(node:Node) -> Array[NodePath]:
	return remove_include_path(get_path_to(node))


# remove a NodePath from the includes Array[NodePath]
func remove_include_path(path:NodePath) -> Array[NodePath]:
	return _remove_all_from_array(includes, path)


# add a Node to the excludes Array[NodePath]
func add_exclude_node(node:Node) -> Array[NodePath]:
	return add_exclude_path(get_path_to(node))


# add a NodePath to the excludes Array[NodePath]
func add_exclude_path(path:NodePath) -> Array[NodePath]:
	return _add_unique_to_array(excludes, path)


# remove a Node from the excludes Array[NodePath]
func remove_exclude_node(node:Node) -> Array[NodePath]:
	return remove_exclude_path(get_path_to(node))


# remove a NodePath from the excludes Array[NodePath]
func remove_exclude_path(path:NodePath) -> Array[NodePath]:
	return _remove_all_from_array(excludes, path)


# add an item to an array unless the array already contains that item
func _add_unique_to_array(array:Array, item) -> Array:
	if !array.has(item):
		array.push_back(item)

	return array


# remove all array items that match item
func _remove_all_from_array(array:Array, item) -> Array:
	while array.has(item):
		array.erase(item)

	return array


# apply interpolation to all smoothed_nodes positions
func _process(_delta: float) -> void:
	for node in _physics_process_nodes:
		if _positions.has(node) && _positions[node].size() == 2:
			if _physics_process_just_updated:
				_positions[node][1] = node.position

			node.position = _positions[node][0].lerp(
				_positions[node][1],
				Engine.get_physics_interpolation_fraction()
			)
#
	_physics_process_just_updated = false


# store all smoothed_nodes' positions of the previous (origin) and this (target) _physics_process
# frames for interpolation in the upcoming _process frames until the next _physics_process and apply
# the origin position
func _physics_process(_delta: float) -> void:
	var parent: = get_parent()
	if parent == null: return

	# move this node to the top of the parent tree (typically a scene's root
	# node) so that it is called before all other _physics_processes
	parent.move_child(self, 0)

	if smooth_parent:
		process_priority = parent.process_priority - 1

	# update the relevant nodes once per _physics_process
	_physics_process_nodes = _get_physics_process_nodes(parent, !smooth_parent)

	# clean up _positions
	for key in _positions.keys():
		if !_physics_process_nodes.has(key):
			_positions.erase(key)

	for node in _physics_process_nodes:
		if (!_positions.has(node)):
			# called on the first frame after this node was added to _positions
			_positions[node] = [node.position]

			# clean up _positions when a node exited the tree
			node.tree_exited.connect(func (): _positions.erase(node))
		elif (_positions[node].size() < 2):
			# called on the second frame after this node was added to _positions
			_positions[node].push_front(_positions[node][0])
			_positions[node][1] = node.position
		else:
			_positions[node][0] = _positions[node][1]
			node.position = _positions[node][0]

	_physics_process_just_updated = true


# get relevant nodes to be smoothed based on this node's tree position and properties
func _get_physics_process_nodes(node: Node, ignore_node: = false, with_includes: = true) -> Array[Node]:
	var nodes:Array[Node] = includes.map(
		func (include): return get_node_or_null(include)
	).filter(
		func (node): return node != null && !excludes.has(node)
	) if with_includes else []

	if (
		!ignore_node
		&& node != self
		&& !node is RigidBody2D
		&& !node is RigidBody3D
		&& !nodes.has(node)
		&& !excludes.has(get_path_to(node))
		&& node.has_method("_physics_process")
		&& node.get("position")
	):
		nodes.push_back(node)

	if recursive:
		for child in node.get_children():
			nodes.append_array(_get_physics_process_nodes(child, false, false))

	return nodes
