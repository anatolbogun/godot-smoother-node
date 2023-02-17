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


class_name Smoother extends Node

## Smoother Node
## Version: 1.0.3
##
## A node type that smoothes scene nodes' properties by interpolating _physics_process steps.
##
## For documentation please visit https://github.com/anatolbogun/godot-smoother-node .

## Node properties that are interpolated.
## Defaults to ["position"], even if not displayed in the inspector.
@export var properties:Array[String] = ["position"]

## Apply interpolation to this node's parent.
@export var smooth_parent: = true :
	set (value):
		if value == false:
			# remove parent from _properties in case this gets toggled on and off during runtime
			_properties.erase(get_parent())

		smooth_parent = value

## Apply interpolation to the recursive children of this node's parent.
@export var recursive: = true

## Explicitly include node paths in addition to the nodes that are included by other Smoother
## settings.
@export var includes:Array[NodePath] = []

## Explicitly exclude node paths.
## This will exclude nodes that would otherwise be included by other settings.
@export var excludes:Array[NodePath] = []

# get an array of all currently smoothed nodes; mainly for debugging performance optimisations
var smoothed_nodes:Array[Node] :
	get:
		var parent: = get_parent()
		return _get_physics_process_nodes(parent, !smooth_parent) if parent != null else [] as Array[Node]

var _properties: = {}
var _physics_process_nodes:Array[Node]
var _physics_process_just_updated: = false


## Reset all smoothed nodes.
func reset() -> void:
	_properties.clear()


## Reset a specific node. You may want to call this when a node gets teleported.
func reset_node(node:Node) -> void:
	_properties.erase(node)


## Reset a specific Node by NodePath. You may want to call this when a Node gets teleported.
func reset_node_path(path:NodePath) -> void:
	var node: = get_node_or_null(path)

	if node != null:
		reset_node(node)


## Add a Node to the includes Array[NodePath].
func add_include_node(node:Node) -> Array[NodePath]:
	return add_include_path(get_path_to(node))


## Add a NodePath to the includes Array[NodePath].
func add_include_path(path:NodePath) -> Array[NodePath]:
	return _add_unique_to_array(includes, path) as Array[NodePath]


## Remove a Node from the includes Array[NodePath].
func remove_include_node(node:Node) -> Array[NodePath]:
	return remove_include_path(get_path_to(node))


## Remove a NodePath from the includes Array[NodePath].
func remove_include_path(path:NodePath) -> Array[NodePath]:
	return _remove_all_from_array(includes, path) as Array[NodePath]


## Add a Node to the excludes Array[NodePath].
func add_exclude_node(node:Node) -> Array[NodePath]:
	return add_exclude_path(get_path_to(node))


## Add a NodePath to the excludes Array[NodePath].
func add_exclude_path(path:NodePath) -> Array[NodePath]:
	return _add_unique_to_array(excludes, path) as Array[NodePath]


## Remove a Node from the excludes Array[NodePath].
func remove_exclude_node(node:Node) -> Array[NodePath]:
	return remove_exclude_path(get_path_to(node))


## Remove a NodePath from the excludes Array[NodePath].
func remove_exclude_path(path:NodePath) -> Array[NodePath]:
	return _remove_all_from_array(excludes, path) as Array[NodePath]


## Add an item to an array unless the array already contains that item.
func _add_unique_to_array(array:Array, item:Variant) -> Array:
	if !array.has(item):
		array.push_back(item)

	return array


## Remove all array items that match item.
func _remove_all_from_array(array:Array, item:Variant) -> Array:
	while array.has(item):
		array.erase(item)

	return array


## Apply interpolation to all smoothed_nodes supported properties.
func _process(_delta: float) -> void:
	for node in _physics_process_nodes:
		if !_properties.has(node): continue

		for property in _properties[node]:
			var values = _properties[node][property]

			if values.size() == 2:
				if _physics_process_just_updated:
					values[1] = node[property]

				node[property] = lerp(values[0], values[1], Engine.get_physics_interpolation_fraction())

	_physics_process_just_updated = false


## Store all smoothed_nodes' relevant properties of the previous (origin) and this (target)
## _physics_process frames for interpolation in the upcoming _process frames and apply the origin
## values.
func _physics_process(_delta: float) -> void:
	var parent: = get_parent()
	if parent == null: return

	# move this node to the top of the parent tree (typically a scene's root node) so that it is
	# called before all other _physics_processes
	parent.move_child(self, 0)

	if smooth_parent:
		process_priority = parent.process_priority - 1

	# update the relevant nodes once per _physics_process
	_physics_process_nodes = _get_physics_process_nodes(parent, !smooth_parent)

	# clean up _properties
	for key in _properties.keys():
		if !_physics_process_nodes.has(key):
			_properties.erase(key)

	for node in _physics_process_nodes:
		if !_properties.has(node):
			# called on the first frame after a node was added to _properties
			_properties[node] = {}

			# clean up _properties when a node exited the tree
			node.tree_exited.connect(func (): _properties.erase(node))

		for property in properties:
			if ! property in node: continue

			if !_properties[node].has(property):
				# called on the first frame after a node was added to _properties
				_properties[node][property] = [node[property]]
			elif _properties[node][property].size() < 2:
				# called on the second frame after a node was added to _properties
				_properties[node][property].push_front(_properties[node][property][0])
				_properties[node][property][1] = node[property]
			else:
				_properties[node][property][0] = _properties[node][property][1]
				node[property] = _properties[node][property][0]

	_physics_process_just_updated = true


## Get the relevant nodes to be smoothed based on this node's tree position and properties.
func _get_physics_process_nodes(node: Node, ignore_node: = false, with_includes: = true) -> Array[Node]:
	var nodes:Array[Node]

	nodes.assign(includes.map(
		get_node_or_null
	).filter(
		func (node:Node) -> bool: return node != null && !excludes.has(get_path_to(node))
	) if with_includes else [])

	if (
		!ignore_node
		&& node != self
		&& !node is RigidBody2D
		&& !node is RigidBody3D
		&& !nodes.has(node)
		&& !excludes.has(get_path_to(node))
		&& node.has_method("_physics_process")
	):
		nodes.push_back(node)

	if recursive:
		for child in node.get_children():
			for nested_node in _get_physics_process_nodes(child, false, false):
				_add_unique_to_array(nodes, nested_node)

	return nodes
